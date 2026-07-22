#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <EspUsbHost.h>
#include <WiFi.h>
#include <esp_display_panel.hpp>
#include <esp_now.h>
#include <esp_wifi.h>
#include <lvgl.h>

#include "lvgl_v8_port.h"

using namespace esp_panel::board;
using namespace esp_panel::drivers;
namespace {

constexpr uint8_t kProtocolVersion = 1;
constexpr uint32_t kHeartbeatMs = 1000;
constexpr uint32_t kEspNowPeriodMs = 250;
constexpr uint8_t kEspNowChannel = 6;
constexpr uint32_t kEspNowMagic = 0x504C454F;
constexpr uint32_t kPathAckMagic = 0x5041434B;
constexpr bool kPhysicalOutputsEnabled = false;
constexpr char kBleDeviceName[] = "PLEOS-RECONFIG";
constexpr char kBleServiceUuid[] = "7d2f0001-7c7a-4f7b-9b51-0af9a281d110";
constexpr char kBleControlUuid[] = "7d2f0002-7c7a-4f7b-9b51-0af9a281d110";

enum class Health : uint8_t { healthy, degraded, failed, isolated };

struct Channel {
  const char *id;
  const char *label;
  Health health;
  lv_obj_t *button;
  lv_obj_t *value;
};

Channel channels[] = {
    {"tsn_front_a", "FRONT TSN A", Health::healthy},
    {"tsn_front_b", "FRONT TSN B", Health::healthy},
    {"tsn_rear", "REAR TSN", Health::healthy},
    {"lidar_fl", "LiDAR FL", Health::healthy},
    {"lidar_fr", "LiDAR FR", Health::healthy},
    {"lidar_rl", "LiDAR RL", Health::healthy},
    {"lidar_rr", "LiDAR RR", Health::healthy},
    {"gnss", "GNSS", Health::healthy},
    {"camera", "CAMERA", Health::healthy},
};

constexpr size_t kChannelCount = sizeof(channels) / sizeof(channels[0]);
lv_obj_t *modeLabel;
lv_obj_t *networkLabel;
lv_obj_t *linkLabel;
lv_obj_t *eventLabel;
lv_obj_t *heartbeatArc;
uint32_t sequenceNumber = 0;
uint32_t lastHeartbeat = 0;
const char *effectiveMode = "TRIPLE";
const char *lastEvent = "Boot complete";
SemaphoreHandle_t frameMutex;
String commandBuffer;
String ioNodeBuffer;
EspUsbHost usbHost;
EspUsbHostCdcSerial ioNodeSerial(usbHost);
volatile bool ioNodeConnected = false;
bool lastRenderedIoNodeConnected = false;
BLECharacteristic *bleControl = nullptr;
volatile bool bleConnected = false;
volatile bool bleSnapshotPending = false;
uint32_t lastEspNowAt = 0;
uint32_t espNowSequence = 0;
uint32_t lastArcAt = 0;
volatile uint32_t pathAckAt[2] = {0, 0};
volatile bool pathAckPending = false;

struct __attribute__((packed)) PathNowFrame {
  uint32_t magic;
  uint32_t sequence;
  uint8_t version;
  uint8_t isolatedMask;
  uint16_t crc;
};

struct __attribute__((packed)) PathAckFrame {
  uint32_t magic;
  uint32_t sequence;
  uint8_t version;
  uint8_t pathIndex;
  uint8_t isolated;
  uint16_t crc;
};

void publishBleState(const char *eventType, bool fullSnapshot);

class BufferPrint final : public Print {
 public:
  using Print::write;
  size_t write(uint8_t byte) override {
    if (length >= sizeof(data)) return 0;
    data[length++] = byte;
    return 1;
  }
  uint8_t data[768]{};
  size_t length = 0;
};

class CborWriter {
 public:
  explicit CborWriter(BufferPrint &output) : output_(output) {}

  void writeUnsignedInt(uint64_t value) { writeType(0, value); }
  void writeBoolean(bool value) { output_.write(value ? 0xF5 : 0xF4); }
  void beginText(size_t length) { writeType(3, length); }
  void beginMap(size_t length) { writeType(5, length); }
  void writeBytes(const uint8_t *data, size_t length) { output_.write(data, length); }

 private:
  void writeType(uint8_t major, uint64_t value) {
    const uint8_t prefix = major << 5;
    if (value < 24) {
      output_.write(prefix | value);
    } else if (value <= 0xFF) {
      output_.write(prefix | 24);
      output_.write(value);
    } else if (value <= 0xFFFF) {
      output_.write(prefix | 25);
      output_.write(value >> 8);
      output_.write(value);
    } else {
      output_.write(prefix | 26);
      output_.write(value >> 24);
      output_.write(value >> 16);
      output_.write(value >> 8);
      output_.write(value);
    }
  }

  BufferPrint &output_;
};

const char *healthName(Health health) {
  switch (health) {
    case Health::healthy: return "NORMAL";
    case Health::degraded: return "DEGRADED";
    case Health::failed: return "FAULT";
    case Health::isolated: return "ISOLATED";
  }
  return "UNKNOWN";
}

uint32_t healthColor(Health health) {
  switch (health) {
    case Health::healthy: return 0x177C62;
    case Health::degraded: return 0xD08A1A;
    case Health::failed: return 0xC84942;
    case Health::isolated: return 0x687178;
  }
  return 0x687178;
}

void writeText(CborWriter &writer, const char *text) {
  writer.beginText(strlen(text));
  writer.writeBytes(reinterpret_cast<const uint8_t *>(text), strlen(text));
}

uint16_t crc16(const uint8_t *data, size_t length) {
  uint16_t crc = 0xFFFF;
  for (size_t i = 0; i < length; ++i) {
    crc ^= static_cast<uint16_t>(data[i]) << 8;
    for (uint8_t bit = 0; bit < 8; ++bit) {
      crc = (crc & 0x8000) ? static_cast<uint16_t>((crc << 1) ^ 0x1021) : static_cast<uint16_t>(crc << 1);
    }
  }
  return crc;
}

void onEspNowReceive(const esp_now_recv_info_t *, const uint8_t *data, int length) {
  if (length != sizeof(PathAckFrame)) return;
  PathAckFrame frame;
  memcpy(&frame, data, sizeof(frame));
  if (frame.magic != kPathAckMagic || frame.version != kProtocolVersion ||
      frame.pathIndex > 1) return;
  const uint16_t expected = crc16(reinterpret_cast<const uint8_t *>(&frame),
                                  sizeof(frame) - sizeof(frame.crc));
  if (frame.crc != expected) return;
  pathAckAt[frame.pathIndex] = millis();
  pathAckPending = true;
}

void startEspNow() {
  WiFi.mode(WIFI_STA);
  esp_wifi_set_channel(kEspNowChannel, WIFI_SECOND_CHAN_NONE);
  if (esp_now_init() != ESP_OK) {
    Serial.println("!ESPNOW:INIT_FAILED");
    return;
  }
  esp_now_peer_info_t peer{};
  memset(peer.peer_addr, 0xFF, ESP_NOW_ETH_ALEN);
  peer.channel = kEspNowChannel;
  peer.encrypt = false;
  if (esp_now_add_peer(&peer) != ESP_OK) Serial.println("!ESPNOW:PEER_FAILED");
  esp_now_register_recv_cb(onEspNowReceive);
}

void sendEspNowState() {
  PathNowFrame frame{kEspNowMagic, ++espNowSequence, kProtocolVersion, 0, 0};
  if (channels[0].health != Health::healthy) frame.isolatedMask |= 0x01;
  if (channels[1].health != Health::healthy) frame.isolatedMask |= 0x02;
  if (channels[2].health != Health::healthy) frame.isolatedMask |= 0x04;
  frame.crc = crc16(reinterpret_cast<const uint8_t *>(&frame), sizeof(frame) - sizeof(frame.crc));
  static const uint8_t broadcast[] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
  esp_now_send(broadcast, reinterpret_cast<const uint8_t *>(&frame), sizeof(frame));
}

void sendState(const char *eventType, const char *channelId = "") {
  if (xSemaphoreTake(frameMutex, pdMS_TO_TICKS(100)) != pdTRUE) return;
  BufferPrint payload;
  CborWriter writer(payload);
  writer.beginMap(10);
  writeText(writer, "v"); writer.writeUnsignedInt(kProtocolVersion);
  writeText(writer, "seq"); writer.writeUnsignedInt(++sequenceNumber);
  writeText(writer, "uptime_ms"); writer.writeUnsignedInt(millis());
  writeText(writer, "board"); writeText(writer, "ws-esp32s3-touch-lcd-7");
  writeText(writer, "event"); writeText(writer, eventType);
  writeText(writer, "channel"); writeText(writer, channelId);
  writeText(writer, "mode"); writeText(writer, effectiveMode);
  writeText(writer, "physical_outputs"); writer.writeBoolean(kPhysicalOutputsEnabled);
  writeText(writer, "io_node_connected"); writer.writeBoolean(ioNodeConnected);
  writeText(writer, "channels");
  writer.beginMap(kChannelCount);
  for (const auto &channel : channels) {
    writeText(writer, channel.id);
    writeText(writer, healthName(channel.health));
  }

  const uint16_t size = payload.length;
  const uint16_t crc = crc16(payload.data, payload.length);
  Serial.write(0xA5);
  Serial.write(0x5A);
  Serial.write(size >> 8);
  Serial.write(size & 0xFF);
  Serial.write(payload.data, payload.length);
  Serial.write(crc >> 8);
  Serial.write(crc & 0xFF);
  xSemaphoreGive(frameMutex);
  publishBleState(eventType, strcmp(eventType, "heartbeat") != 0);
}

bool available(const char *id) {
  for (const auto &channel : channels) {
    if (!strcmp(channel.id, id)) return channel.health == Health::healthy || channel.health == Health::degraded;
  }
  return false;
}

void deriveMode() {
  const bool lidar = available("lidar_fl") || available("lidar_fr") || available("lidar_rl") || available("lidar_rr");
  const bool gnss = available("gnss");
  const bool camera = available("camera");
  const int sensorKinds = static_cast<int>(lidar) + static_cast<int>(gnss) + static_cast<int>(camera);
  const int networkPaths = static_cast<int>(available("tsn_front_a")) +
                           static_cast<int>(available("tsn_front_b")) +
                           static_cast<int>(available("tsn_rear"));
  if (networkPaths == 0 || sensorKinds == 0) effectiveMode = "MRM";
  else if (sensorKinds == 3) effectiveMode = "TRIPLE";
  else if (sensorKinds == 2) effectiveMode = "DUAL";
  else effectiveMode = "SINGLE";
}

void refreshUi() {
  deriveMode();
  for (auto &channel : channels) {
    if (channel.value == nullptr || channel.button == nullptr) continue;
    lv_label_set_text(channel.value, healthName(channel.health));
    lv_obj_set_style_bg_color(channel.button, lv_color_hex(0x182126), 0);
    lv_obj_set_style_border_color(channel.button, lv_color_hex(healthColor(channel.health)), 0);
    lv_obj_set_style_text_color(channel.value, lv_color_hex(healthColor(channel.health)), 0);
  }
  lv_label_set_text_fmt(modeLabel, "AUTOWARE MODE  %s", effectiveMode);
  lv_obj_set_style_text_color(modeLabel, lv_color_hex(!strcmp(effectiveMode, "MRM") ? 0xFF6A61 : 0x66D6B1), 0);
  const int activePaths = static_cast<int>(available("tsn_front_a")) +
                          static_cast<int>(available("tsn_front_b")) +
                          static_cast<int>(available("tsn_rear"));
  lv_label_set_text_fmt(networkLabel, "%s  |  %d/3 LINKS ACTIVE",
                        activePaths == 3 ? "NETWORK NOMINAL" :
                        (activePaths > 0 ? "REDUNDANT ROUTING" : "NETWORK MRM"),
                        activePaths);
  lv_obj_set_style_text_color(networkLabel,
                              lv_color_hex(activePaths == 3 ? 0x66D6B1 :
                                           (activePaths > 0 ? 0xF0A83B : 0xFF6A61)), 0);
  lv_label_set_text(eventLabel, lastEvent);
  const uint32_t now = millis();
  const bool path1Online = now - pathAckAt[0] < 2500;
  const bool path2Online = now - pathAckAt[1] < 2500;
  lv_label_set_text_fmt(linkLabel, "BLE %s | P1 %s | P2 %s",
                        bleConnected ? "ON" : "WAIT",
                        path1Online ? "ACK" : "--",
                        path2Online ? "ACK" : "--");
  lv_obj_set_style_text_color(linkLabel, lv_color_hex(ioNodeConnected ? 0x66D6B1 : 0x92A0A5), 0);
}

void sendNodeCommand(const String &command) {
  if (!ioNodeConnected) return;
  ioNodeSerial.print(command);
  ioNodeSerial.print('\n');
}

void channelPressed(lv_event_t *event) {
  auto *channel = static_cast<Channel *>(lv_event_get_user_data(event));
  channel->health = channel->health == Health::healthy ? Health::failed : Health::healthy;
  lastEvent = channel->health == Health::healthy ? "Channel recovered" : "Fault injected";
  refreshUi();
  sendNodeCommand(String("!CHANNEL:") + channel->id + ":" + healthName(channel->health));
  sendState("channel_changed", channel->id);
}

void setAllHealthy() {
  for (auto &channel : channels) channel.health = Health::healthy;
}

void setExclusivePathFault(int path, bool forwardToNode = true) {
  if (path < 1 || path > 3) return;
  for (int i = 0; i < 3; ++i) channels[i].health = Health::healthy;
  channels[path - 1].health = Health::failed;
  lastEvent = "Exclusive path Link Down";
  refreshUi();
  if (forwardToNode) {
    for (int i = 0; i < 3; ++i) {
      sendNodeCommand(String("!CHANNEL:") + channels[i].id + ":" +
                      healthName(channels[i].health));
    }
  }
  sendState("path_fault", channels[path - 1].id);
}

void setSwitchFault(int switchIndex) {
  for (int i = 0; i < 3; ++i) channels[i].health = Health::healthy;
  if (switchIndex == 0) {
    channels[0].health = Health::failed;
    channels[2].health = Health::failed;
    lastEvent = "Front Switch A fault";
  } else if (switchIndex == 1) {
    channels[1].health = Health::failed;
    channels[2].health = Health::failed;
    lastEvent = "Front Switch B fault";
  } else {
    channels[0].health = Health::failed;
    channels[1].health = Health::failed;
    lastEvent = "Rear Switch fault";
  }
  refreshUi();
  for (int i = 0; i < 3; ++i) {
    sendNodeCommand(String("!CHANNEL:") + channels[i].id + ":" +
                    healthName(channels[i].health));
  }
  sendState("switch_fault", switchIndex == 0 ? "front_a" :
                                  (switchIndex == 1 ? "front_b" : "rear"));
}

void pathActionPressed(lv_event_t *event) {
  const intptr_t action = reinterpret_cast<intptr_t>(lv_event_get_user_data(event));
  if (action >= 1 && action <= 3) {
    setExclusivePathFault(static_cast<int>(action));
    return;
  }
  if (action >= 4 && action <= 6) {
    setSwitchFault(static_cast<int>(action - 4));
    return;
  }
  setAllHealthy();
  lastEvent = "All network paths recovered";
  refreshUi();
  sendNodeCommand("!RECOVER");
  sendState("recovered", "network");
}

void scenarioPressed(lv_event_t *event) {
  const intptr_t scenario = reinterpret_cast<intptr_t>(lv_event_get_user_data(event));
  setAllHealthy();
  if (scenario == 1) {
    channels[3].health = Health::failed;
    lastEvent = "LiDAR FL loss / triple retained";
  } else if (scenario == 2) {
    channels[7].health = Health::degraded;
    channels[8].health = Health::failed;
    lastEvent = "GNSS degraded + camera loss";
  } else if (scenario == 3) {
    channels[0].health = Health::failed;
    channels[1].health = Health::failed;
    lastEvent = "Front TSN isolated / MRM";
  } else if (scenario == 4) {
    lastEvent = "All channels recovered";
  }
  refreshUi();
  sendNodeCommand(String("!SCENARIO:") + scenario);
  sendState(scenario == 4 ? "recovered" : "scenario", scenario == 3 ? "tsn_front" : "sensors");
}

void applyScenarioNumber(int scenario, bool forwardToNode = true) {
  setAllHealthy();
  if (scenario == 1) {
    channels[3].health = Health::failed;
    lastEvent = "Remote: LiDAR FL loss";
  } else if (scenario == 2) {
    channels[7].health = Health::degraded;
    channels[8].health = Health::failed;
    lastEvent = "Remote: dual sensor";
  } else if (scenario == 3) {
    channels[0].health = Health::failed;
    channels[1].health = Health::failed;
    lastEvent = "Remote: front TSN MRM";
  } else {
    lastEvent = "Remote: all recovered";
  }
  lvgl_port_lock(-1);
  refreshUi();
  lvgl_port_unlock();
  if (forwardToNode) sendNodeCommand(String("!SCENARIO:") + scenario);
  sendState(scenario == 4 ? "recovered" : "scenario", "remote");
}

Health parseHealth(const String &value) {
  if (value == "DEGRADED") return Health::degraded;
  if (value == "FAULT") return Health::failed;
  if (value == "ISOLATED") return Health::isolated;
  return Health::healthy;
}

void processCommand(const String &command, bool forwardToNode = true) {
  if (command == "!SYNC") {
    sendState("sync");
    return;
  }
  if (command == "!RECOVER") {
    applyScenarioNumber(4, forwardToNode);
    return;
  }
  if (command.startsWith("!SCENARIO:")) {
    applyScenarioNumber(command.substring(10).toInt(), forwardToNode);
    return;
  }
  if (command.startsWith("!PATH:")) {
    const int path = command.substring(6).toInt();
    lvgl_port_lock(-1);
    setExclusivePathFault(path, forwardToNode);
    lvgl_port_unlock();
    return;
  }
  if (!command.startsWith("!CHANNEL:")) return;
  const int separator = command.indexOf(':', 9);
  if (separator < 0) return;
  const String id = command.substring(9, separator);
  const Health health = parseHealth(command.substring(separator + 1));
  for (auto &channel : channels) {
    if (id == channel.id) {
      channel.health = health;
      lastEvent = "Remote channel command";
      lvgl_port_lock(-1);
      refreshUi();
      lvgl_port_unlock();
      if (forwardToNode) sendNodeCommand(command);
      sendState("channel_changed", channel.id);
      return;
    }
  }
}

void notifyBle(const String &message) {
  if (!bleConnected || bleControl == nullptr) return;
  bleControl->setValue(message.c_str());
  bleControl->notify();
  delay(4);
}

void publishBleState(const char *eventType, bool fullSnapshot) {
  if (!bleConnected) return;
  notifyBle(String("!STATE:") + sequenceNumber + ":" + effectiveMode + ":" +
            (ioNodeConnected ? "ONLINE" : "OFFLINE"));
  if (!fullSnapshot) return;
  for (const auto &channel : channels) {
    notifyBle(String("!CHANNEL:") + channel.id + ":" + healthName(channel.health));
  }
  notifyBle(String("!EVENT:") + eventType);
}

class ReconfigServerCallbacks final : public BLEServerCallbacks {
  void onConnect(BLEServer *) override {
    bleConnected = true;
    bleSnapshotPending = true;
  }

  void onDisconnect(BLEServer *server) override {
    bleConnected = false;
    bleSnapshotPending = true;
    server->startAdvertising();
  }
};

class ReconfigControlCallbacks final : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    String command = characteristic->getValue();
    command.trim();
    if (command.startsWith("!")) processCommand(command);
  }
};

void startBle() {
  BLEDevice::init(kBleDeviceName);
  BLEDevice::setMTU(185);
  auto *server = BLEDevice::createServer();
  server->setCallbacks(new ReconfigServerCallbacks());
  auto *service = server->createService(kBleServiceUuid);
  bleControl = service->createCharacteristic(
      kBleControlUuid,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE |
          BLECharacteristic::PROPERTY_WRITE_NR | BLECharacteristic::PROPERTY_NOTIFY);
  bleControl->setCallbacks(new ReconfigControlCallbacks());
  bleControl->addDescriptor(new BLE2902());
  bleControl->setValue("!BOOT:SAFE_BYPASS");
  service->start();
  auto *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(kBleServiceUuid);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();
}

void readIoNode() {
  while (ioNodeSerial.available()) {
    const char value = static_cast<char>(ioNodeSerial.read());
    if (value == '\n') {
      ioNodeBuffer.trim();
      if (ioNodeBuffer.startsWith("!")) processCommand(ioNodeBuffer, false);
      ioNodeBuffer = "";
    } else if (value != '\r' && ioNodeBuffer.length() < 160) {
      ioNodeBuffer += value;
    }
  }
}

void readCommands() {
  while (Serial.available()) {
    const char value = static_cast<char>(Serial.read());
    if (value == '\n') {
      commandBuffer.trim();
      processCommand(commandBuffer);
      commandBuffer = "";
    } else if (value != '\r' && commandBuffer.length() < 160) {
      commandBuffer += value;
    }
  }
}

lv_obj_t *makeCard(lv_obj_t *parent, Channel &channel, int x, int y, int width) {
  auto *button = lv_btn_create(parent);
  lv_obj_set_pos(button, x, y);
  lv_obj_set_size(button, width, 66);
  lv_obj_set_style_radius(button, 5, 0);
  lv_obj_set_style_shadow_width(button, 0, 0);
  lv_obj_set_style_bg_color(button, lv_color_hex(0x182126), 0);
  lv_obj_set_style_border_width(button, 2, 0);
  lv_obj_set_style_border_color(button, lv_color_hex(healthColor(channel.health)), 0);
  lv_obj_add_event_cb(button, channelPressed, LV_EVENT_CLICKED, &channel);
  auto *title = lv_label_create(button);
  lv_label_set_text(title, channel.label);
  lv_obj_set_style_text_font(title, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(title, lv_color_hex(0xE8ECEE), 0);
  lv_obj_align(title, LV_ALIGN_TOP_LEFT, -4, -4);
  channel.value = lv_label_create(button);
  lv_label_set_text(channel.value, "NORMAL");
  lv_obj_set_style_text_font(channel.value, &lv_font_montserrat_12, 0);
  lv_obj_set_style_text_color(channel.value, lv_color_hex(healthColor(channel.health)), 0);
  lv_obj_align(channel.value, LV_ALIGN_BOTTOM_LEFT, -4, 4);
  channel.button = button;
  return button;
}

void makeScenario(lv_obj_t *parent, const char *text, int x, intptr_t scenario, uint32_t color) {
  auto *button = lv_btn_create(parent);
  lv_obj_set_pos(button, x, 411);
  lv_obj_set_size(button, 180, 52);
  lv_obj_set_style_radius(button, 4, 0);
  lv_obj_set_style_shadow_width(button, 0, 0);
  lv_obj_set_style_bg_color(button, lv_color_hex(color), 0);
  lv_obj_add_event_cb(button, scenarioPressed, LV_EVENT_CLICKED, reinterpret_cast<void *>(scenario));
  auto *label = lv_label_create(button);
  lv_label_set_text(label, text);
  lv_obj_center(label);
}

void makePathAction(lv_obj_t *parent, const char *text, int x, int y, int width,
                    intptr_t action, uint32_t color) {
  auto *button = lv_btn_create(parent);
  lv_obj_set_pos(button, x, y);
  lv_obj_set_size(button, width, 58);
  lv_obj_set_style_radius(button, 5, 0);
  lv_obj_set_style_shadow_width(button, 0, 0);
  lv_obj_set_style_bg_color(button, lv_color_hex(color), 0);
  lv_obj_add_event_cb(button, pathActionPressed, LV_EVENT_CLICKED,
                      reinterpret_cast<void *>(action));
  auto *label = lv_label_create(button);
  lv_label_set_text(label, text);
  lv_obj_set_style_text_font(label, &lv_font_montserrat_14, 0);
  lv_obj_center(label);
}

void createUi() {
  auto *screen = lv_scr_act();
  lv_obj_set_style_bg_color(screen, lv_color_hex(0x0B0F11), 0);
  lv_obj_set_style_text_color(screen, lv_color_hex(0xF4F7F7), 0);

  auto *title = lv_label_create(screen);
  lv_label_set_text(title, "PLEOS NETWORK RECONFIG");
  lv_obj_set_style_text_font(title, &lv_font_montserrat_24, 0);
  lv_obj_set_pos(title, 18, 15);
  modeLabel = lv_label_create(screen);
  lv_obj_set_style_text_font(modeLabel, &lv_font_montserrat_16, 0);
  lv_obj_align(modeLabel, LV_ALIGN_TOP_RIGHT, -18, 19);
  networkLabel = lv_label_create(screen);
  lv_obj_set_style_text_font(networkLabel, &lv_font_montserrat_16, 0);
  lv_obj_set_pos(networkLabel, 18, 58);
  heartbeatArc = lv_arc_create(screen);
  lv_obj_set_size(heartbeatArc, 34, 34);
  lv_obj_set_pos(heartbeatArc, 390, 48);
  lv_arc_set_range(heartbeatArc, 0, 100);
  lv_arc_set_value(heartbeatArc, 72);
  lv_arc_set_bg_angles(heartbeatArc, 0, 360);
  lv_obj_remove_style(heartbeatArc, nullptr, LV_PART_KNOB);
  lv_obj_clear_flag(heartbeatArc, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_set_style_arc_width(heartbeatArc, 3, LV_PART_MAIN);
  lv_obj_set_style_arc_color(heartbeatArc, lv_color_hex(0x263238), LV_PART_MAIN);
  lv_obj_set_style_arc_width(heartbeatArc, 3, LV_PART_INDICATOR);
  lv_obj_set_style_arc_color(heartbeatArc, lv_color_hex(0x66D6B1), LV_PART_INDICATOR);
  linkLabel = lv_label_create(screen);
  lv_label_set_text(linkLabel, "BLE WAITING  |  NOW TX");
  lv_obj_set_style_text_color(linkLabel, lv_color_hex(0x92A0A5), 0);
  lv_obj_align(linkLabel, LV_ALIGN_TOP_RIGHT, -18, 57);
  eventLabel = lv_label_create(screen);
  lv_obj_set_style_text_color(eventLabel, lv_color_hex(0x92A0A5), 0);
  lv_obj_align(eventLabel, LV_ALIGN_TOP_RIGHT, -18, 83);

  channels[0].label = "PATH 1  A <-> REAR";
  channels[1].label = "PATH 2  B <-> REAR";
  channels[2].label = "PATH 3  A <-> B";
  makeCard(screen, channels[0], 18, 108, 240);
  makeCard(screen, channels[1], 280, 108, 240);
  makeCard(screen, channels[2], 542, 108, 240);
  lv_obj_set_style_border_width(channels[2].button, 3, 0);

  auto *role = lv_label_create(screen);
  lv_label_set_text(role, "FAULT INJECTION CONTROL  |  PATH 3 OWNER  |  ESP-NOW LIVE");
  lv_obj_set_style_text_font(role, &lv_font_montserrat_16, 0);
  lv_obj_set_style_text_color(role, lv_color_hex(0x6CC7E8), 0);
  lv_obj_set_pos(role, 18, 190);

  auto *hint = lv_label_create(screen);
  lv_label_set_text(hint, "ESP-NOW synchronized  |  One action keeps the other two paths NORMAL");
  lv_obj_set_style_text_color(hint, lv_color_hex(0x89959A), 0);
  lv_obj_set_pos(hint, 19, 218);
  makePathAction(screen, "PATH 1 LINK DOWN", 18, 246, 240, 1, 0x263942);
  makePathAction(screen, "PATH 2 LINK DOWN", 280, 246, 240, 2, 0x263942);
  makePathAction(screen, "PATH 3 LINK DOWN", 542, 246, 240, 3, 0xA66B17);
  makePathAction(screen, "FRONT SWITCH A FAULT", 18, 316, 240, 4, 0x7E3030);
  makePathAction(screen, "FRONT SWITCH B FAULT", 280, 316, 240, 5, 0x7E3030);
  makePathAction(screen, "REAR SWITCH FAULT", 542, 316, 240, 6, 0x7E3030);
  makePathAction(screen, "RECOVER ALL PATHS", 18, 390, 764, 7, 0x177C62);
  refreshUi();
}

}  // namespace

void setup() {
  Serial.begin(115200);
  delay(300);
  frameMutex = xSemaphoreCreateMutex();
  assert(frameMutex != nullptr);
  usbHost.onDeviceConnected([](const EspUsbHostDeviceInfo &) { ioNodeConnected = true; });
  usbHost.onDeviceDisconnected([](const EspUsbHostDeviceInfo &) { ioNodeConnected = false; });
  ioNodeSerial.begin(115200);
  usbHost.begin();
  startEspNow();
  startBle();
  auto *board = new Board();
  board->init();
#if LVGL_PORT_AVOID_TEARING_MODE
  auto *lcd = board->getLCD();
  lcd->configFrameBufferNumber(LVGL_PORT_DISP_BUFFER_NUM);
#if ESP_PANEL_DRIVERS_BUS_ENABLE_RGB && CONFIG_IDF_TARGET_ESP32S3
  auto *bus = lcd->getBus();
  if (bus->getBasicAttributes().type == ESP_PANEL_BUS_TYPE_RGB) {
    static_cast<BusRGB *>(bus)->configRGB_BounceBufferSize(lcd->getFrameWidth() * 10);
  }
#endif
#endif
  assert(board->begin());
  lvgl_port_init(board->getLCD(), board->getTouch());
  lvgl_port_lock(-1);
  createUi();
  lvgl_port_unlock();
  sendState("hello");
}

void loop() {
  readCommands();
  readIoNode();
  if (bleSnapshotPending) {
    bleSnapshotPending = false;
    lvgl_port_lock(-1);
    refreshUi();
    lvgl_port_unlock();
    sendState(bleConnected ? "ble_connected" : "ble_disconnected");
  }
  if (pathAckPending) {
    pathAckPending = false;
    lvgl_port_lock(-1);
    refreshUi();
    lvgl_port_unlock();
  }
  if (ioNodeConnected != lastRenderedIoNodeConnected) {
    lastRenderedIoNodeConnected = ioNodeConnected;
    lastEvent = ioNodeConnected ? "USB I/O node connected" : "USB I/O node disconnected";
    lvgl_port_lock(-1);
    refreshUi();
    lvgl_port_unlock();
    sendState(ioNodeConnected ? "io_node_connected" : "io_node_disconnected");
  }
  const uint32_t now = millis();
  if (heartbeatArc != nullptr && now - lastArcAt >= 40) {
    lastArcAt = now;
    lvgl_port_lock(-1);
    lv_arc_set_rotation(heartbeatArc, (now / 12) % 360);
    lvgl_port_unlock();
  }
  if (now - lastEspNowAt >= kEspNowPeriodMs) {
    lastEspNowAt = now;
    sendEspNowState();
  }
  if (now - lastHeartbeat >= kHeartbeatMs) {
    lastHeartbeat = now;
    for (const auto &channel : channels) {
      sendNodeCommand(String("!CHANNEL:") + channel.id + ":" + healthName(channel.health));
    }
    sendState("heartbeat");
  }
  delay(10);
}
