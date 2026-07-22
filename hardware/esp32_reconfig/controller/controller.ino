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

struct __attribute__((packed)) PathNowFrame {
  uint32_t magic;
  uint32_t sequence;
  uint8_t version;
  uint8_t isolatedMask;
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
  lv_label_set_text(linkLabel, ioNodeConnected
                                   ? (bleConnected ? "BLE ONLINE  |  NOW TX  |  I/O ONLINE"
                                                   : "BLE WAITING |  NOW TX  |  I/O ONLINE")
                                   : (bleConnected ? "BLE ONLINE  |  NOW TX  |  I/O OFFLINE"
                                                   : "BLE WAITING |  NOW TX  |  I/O OFFLINE"));
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

void pathActionPressed(lv_event_t *event) {
  const intptr_t action = reinterpret_cast<intptr_t>(lv_event_get_user_data(event));
  if (action >= 1 && action <= 3) {
    setExclusivePathFault(static_cast<int>(action));
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

void makePathAction(lv_obj_t *parent, const char *text, int x, intptr_t action,
                    uint32_t color) {
  auto *button = lv_btn_create(parent);
  lv_obj_set_pos(button, x, 405);
  lv_obj_set_size(button, 180, 56);
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
  lv_label_set_text(role, "7-INCH NODE  |  FRONT A-B INLINE INJECTOR  |  PATH 3 OWNER");
  lv_obj_set_style_text_font(role, &lv_font_montserrat_16, 0);
  lv_obj_set_style_text_color(role, lv_color_hex(0x6CC7E8), 0);
  lv_obj_set_pos(role, 18, 198);

  auto *topology = lv_label_create(screen);
  lv_label_set_text(topology,
                    "FRONT A   ===== PATH 3 =====   FRONT B\n"
                    "     \\ PATH 1             PATH 2 /\n"
                    "                  REAR SWITCH");
  lv_obj_set_style_text_font(topology, &lv_font_montserrat_20, 0);
  lv_obj_set_style_text_color(topology, lv_color_hex(0xDCE3E6), 0);
  lv_obj_set_style_text_align(topology, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_set_width(topology, 764);
  lv_obj_set_pos(topology, 18, 239);

  auto *hint = lv_label_create(screen);
  lv_label_set_text(hint, "ESP-NOW synchronized  |  One action keeps the other two paths NORMAL");
  lv_obj_set_style_text_color(hint, lv_color_hex(0x89959A), 0);
  lv_obj_set_pos(hint, 19, 369);
  makePathAction(screen, "PATH 1 LINK DOWN", 18, 1, 0x263942);
  makePathAction(screen, "PATH 2 LINK DOWN", 214, 2, 0x263942);
  makePathAction(screen, "PATH 3 LINK DOWN", 410, 3, 0xA66B17);
  makePathAction(screen, "RECOVER ALL", 606, 4, 0x177C62);
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
  if (ioNodeConnected != lastRenderedIoNodeConnected) {
    lastRenderedIoNodeConnected = ioNodeConnected;
    lastEvent = ioNodeConnected ? "USB I/O node connected" : "USB I/O node disconnected";
    lvgl_port_lock(-1);
    refreshUi();
    lvgl_port_unlock();
    sendState(ioNodeConnected ? "io_node_connected" : "io_node_disconnected");
  }
  const uint32_t now = millis();
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
