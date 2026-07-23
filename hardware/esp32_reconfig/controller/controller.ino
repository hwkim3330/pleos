#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <EspUsbHost.h>
#include <WiFi.h>
#include <WiFiUdp.h>
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
constexpr uint32_t kEspNowPeriodMs = 200;
constexpr uint32_t kEspNowUrgentPeriodMs = 20;
constexpr uint32_t kEspNowDiscoveryMs = 500;
constexpr uint32_t kPathAckTimeoutMs = 10000;
constexpr uint8_t kEspNowChannel = 6;
constexpr uint32_t kEspNowMagic = 0x504C454F;
constexpr uint32_t kPathAckMagic = 0x5041434B;
constexpr bool kUseBlePathTransport = true;
constexpr char kPathBleServiceUuid[] = "7d2f0011-7c7a-4f7b-9b51-0af9a281d110";
constexpr char kPathBleControlUuid[] = "7d2f0012-7c7a-4f7b-9b51-0af9a281d110";
constexpr const char *kPathBleNames[] = {"PLEOS-PATH1", "PLEOS-PATH2"};
constexpr uint8_t kPathNodeMacs[][ESP_NOW_ETH_ALEN] = {
    {0xA8, 0x42, 0xE3, 0x3D, 0x70, 0xF8},  // Path 1
    {0xA8, 0x42, 0xE3, 0x3D, 0x84, 0xD8},  // Path 2
};
constexpr bool kPhysicalOutputsEnabled = true;
constexpr int kPath3RelayEnable = 6;
constexpr char kTsnApSsid[] = "KETI-TSN-GATEWAY";
constexpr char kTsnApPassword[] = "keti-tsn-9662";
constexpr uint16_t kTsnUdpPort = 5683;
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
lv_obj_t *heartbeatDot;
lv_obj_t *heartbeatLabel;
lv_obj_t *pathLines[3][2]{};
lv_obj_t *switchNodes[3]{};
lv_obj_t *sensorOverlay;
lv_obj_t *tsnOverlay;
lv_obj_t *tsnDeviceValue;
lv_obj_t *tsnTrafficValue;
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
volatile bool usbDevicePresent = false;
volatile uint16_t usbDeviceVid = 0;
volatile uint16_t usbDevicePid = 0;
bool lastRenderedIoNodeConnected = false;
WiFiUDP tsnUdp;
IPAddress tsnPeerAddress;
uint16_t tsnPeerPort = 0;
uint32_t tsnRxBytes = 0;
uint32_t tsnTxBytes = 0;
uint32_t tsnLastTrafficAt = 0;
BLECharacteristic *bleControl = nullptr;
volatile bool bleConnected = false;
volatile bool bleSnapshotPending = false;
uint32_t lastEspNowAt = 0;
uint32_t lastEspNowDiscoveryAt = 0;
volatile uint8_t urgentEspNowFrames = 0;
uint32_t espNowSequence = 0;
uint32_t lastPulseAt = 0;
volatile uint32_t pathAckAt[2] = {0, 0};
volatile bool pathAckPending = false;
BLEClient *pathBleClients[2] = {nullptr, nullptr};
BLERemoteCharacteristic *pathBleControls[2] = {nullptr, nullptr};
volatile bool pathBleConnected[2] = {false, false};
volatile uint8_t pathBleApplied[2] = {0xFF, 0xFF};
uint32_t pathBleCommandId[2] = {0, 0};
uint32_t pathBleCommandAt[2] = {0, 0};

bool isPathOnline(size_t index, uint32_t now = millis()) {
  if (kUseBlePathTransport) {
    return index < 2 && pathBleConnected[index] && pathBleApplied[index] != 0xFF;
  }
  return index < 2 && pathAckAt[index] != 0 && now - pathAckAt[index] < kPathAckTimeoutMs;
}

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
  esp_wifi_set_ps(WIFI_PS_NONE);
  esp_wifi_set_channel(kEspNowChannel, WIFI_SECOND_CHAN_NONE);
  if (esp_now_init() != ESP_OK) {
    Serial.println("!ESPNOW:INIT_FAILED");
    return;
  }
  for (const auto &mac : kPathNodeMacs) {
    esp_now_peer_info_t peer{};
    memcpy(peer.peer_addr, mac, ESP_NOW_ETH_ALEN);
    peer.channel = kEspNowChannel;
    peer.ifidx = WIFI_IF_STA;
    peer.encrypt = false;
    if (esp_now_add_peer(&peer) != ESP_OK) Serial.println("!ESPNOW:PEER_FAILED");
  }
  esp_now_peer_info_t discoveryPeer{};
  memset(discoveryPeer.peer_addr, 0xFF, ESP_NOW_ETH_ALEN);
  discoveryPeer.channel = kEspNowChannel;
  discoveryPeer.ifidx = WIFI_IF_STA;
  discoveryPeer.encrypt = false;
  if (esp_now_add_peer(&discoveryPeer) != ESP_OK) Serial.println("!ESPNOW:DISCOVERY_FAILED");
  esp_now_register_recv_cb(onEspNowReceive);
}

void sendEspNowState() {
  if (kUseBlePathTransport) {
    const uint32_t now = millis();
    for (size_t index = 0; index < 2; ++index) {
      if (!pathBleConnected[index] || pathBleControls[index] == nullptr) continue;
      const uint8_t desired = channels[index].health == Health::healthy ? 0 : 1;
      if (pathBleApplied[index] == desired || now - pathBleCommandAt[index] < 250) continue;
      const uint32_t commandId = ++pathBleCommandId[index];
      const String command = String("!SET:") + commandId + ":" +
                             (desired ? "FAULT" : "SAFE");
      if (pathBleControls[index]->writeValue(command, true)) {
        pathBleCommandAt[index] = now;
      }
    }
    return;
  }
  PathNowFrame frame{kEspNowMagic, ++espNowSequence, kProtocolVersion, 0, 0};
  if (channels[0].health != Health::healthy) frame.isolatedMask |= 0x01;
  if (channels[1].health != Health::healthy) frame.isolatedMask |= 0x02;
  if (channels[2].health != Health::healthy) frame.isolatedMask |= 0x04;
  frame.crc = crc16(reinterpret_cast<const uint8_t *>(&frame), sizeof(frame) - sizeof(frame.crc));
  const uint32_t now = millis();
  for (size_t index = 0; index < 2; ++index) {
    if (isPathOnline(index, now)) {
      esp_now_send(kPathNodeMacs[index], reinterpret_cast<const uint8_t *>(&frame), sizeof(frame));
    }
  }
  if (now - lastEspNowDiscoveryAt >= kEspNowDiscoveryMs) {
    lastEspNowDiscoveryAt = now;
    static const uint8_t broadcast[] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    esp_now_send(broadcast, reinterpret_cast<const uint8_t *>(&frame), sizeof(frame));
  }
}

void sendState(const char *eventType, const char *channelId = "") {
  if (strcmp(eventType, "heartbeat") != 0 && strcmp(eventType, "path_ack") != 0) {
    urgentEspNowFrames = 3;
  }
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
  digitalWrite(kPath3RelayEnable,
               channels[2].health == Health::healthy ? LOW : HIGH);
  deriveMode();
  for (auto &channel : channels) {
    if (channel.value == nullptr || channel.button == nullptr) continue;
    lv_label_set_text(channel.value, healthName(channel.health));
    const bool faulted = channel.health != Health::healthy;
    lv_obj_set_style_bg_color(channel.button,
                              lv_color_hex(faulted ? 0x241719 : 0x151A1D), 0);
    lv_obj_set_style_border_width(channel.button, faulted ? 2 : 1, 0);
    lv_obj_set_style_border_color(channel.button, lv_color_hex(healthColor(channel.health)), 0);
    lv_obj_set_style_text_color(channel.value, lv_color_hex(healthColor(channel.health)), 0);
  }
  for (int index = 0; index < 3; ++index) {
    const uint32_t color = healthColor(channels[index].health);
    for (auto *line : pathLines[index]) {
      if (line != nullptr) lv_obj_set_style_line_color(line, lv_color_hex(color), 0);
    }
  }
  const bool switchFaults[] = {
      channels[0].health != Health::healthy && channels[2].health != Health::healthy,
      channels[1].health != Health::healthy && channels[2].health != Health::healthy,
      channels[0].health != Health::healthy && channels[1].health != Health::healthy,
  };
  for (int index = 0; index < 3; ++index) {
    if (switchNodes[index] == nullptr) continue;
    lv_obj_set_style_bg_color(switchNodes[index],
                              lv_color_hex(switchFaults[index] ? 0x2A1719 : 0x171D20), 0);
    lv_obj_set_style_border_color(switchNodes[index],
                                  lv_color_hex(switchFaults[index] ? 0xE56C65 : 0x39454A), 0);
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
  const bool path1Online = isPathOnline(0, now);
  const bool path2Online = isPathOnline(1, now);
  lv_label_set_text_fmt(linkLabel, "TABLET %s | P1 %s | P2 %s",
                        bleConnected ? "ON" : "WAIT",
                        path1Online ? "ACK" : "--",
                        path2Online ? "ACK" : "--");
  const uint32_t linkColor = path1Online && path2Online ? 0x66D6B1 :
                             (path1Online || path2Online ? 0xF0A83B : 0x687178);
  lv_obj_set_style_text_color(linkLabel, lv_color_hex(linkColor), 0);
  lv_obj_set_style_bg_color(heartbeatDot, lv_color_hex(linkColor), 0);
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

void sensorActionPressed(lv_event_t *event) {
  const intptr_t action = reinterpret_cast<intptr_t>(lv_event_get_user_data(event));
  for (int i = 3; i < 9; ++i) channels[i].health = Health::healthy;
  if (action == 0) {
    channels[3].health = Health::failed;
    lastEvent = "LiDAR FL fault";
  } else if (action == 1) {
    channels[4].health = Health::failed;
    lastEvent = "LiDAR FR fault";
  } else if (action == 2) {
    channels[5].health = Health::failed;
    channels[6].health = Health::failed;
    lastEvent = "Rear LiDAR fault";
  } else if (action == 3) {
    channels[8].health = Health::failed;
    lastEvent = "Camera fault";
  } else if (action == 4) {
    channels[7].health = Health::failed;
    lastEvent = "GNSS fault";
  } else {
    channels[7].health = Health::degraded;
    channels[8].health = Health::failed;
    lastEvent = "GNSS degraded + Camera fault";
  }
  refreshUi();
  for (int i = 3; i < 9; ++i) {
    sendNodeCommand(String("!CHANNEL:") + channels[i].id + ":" +
                    healthName(channels[i].health));
  }
  sendState("sensor_fault", channels[action == 4 ? 7 : (action == 3 ? 8 : 3)].id);
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
  const uint32_t now = millis();
  notifyBle(String("!PATHNODE:1:") +
            (isPathOnline(0, now) ? "ONLINE" : "OFFLINE"));
  notifyBle(String("!PATHNODE:2:") +
            (isPathOnline(1, now) ? "ONLINE" : "OFFLINE"));
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

void onPathBleNotify(BLERemoteCharacteristic *characteristic, uint8_t *data,
                     size_t length, bool) {
  int index = -1;
  for (int candidate = 0; candidate < 2; ++candidate) {
    if (pathBleControls[candidate] == characteristic) index = candidate;
  }
  if (index < 0 || length == 0) return;
  String message;
  message.reserve(length);
  for (size_t i = 0; i < length; ++i) message += static_cast<char>(data[i]);
  if (!message.startsWith("!APPLIED:")) return;
  const int separator = message.indexOf(':', 9);
  if (separator < 0) return;
  const uint32_t commandId = message.substring(9, separator).toInt();
  if (commandId != pathBleCommandId[index]) return;
  pathBleApplied[index] = message.substring(separator + 1) == "HIGH" ? 1 : 0;
  pathAckAt[index] = millis();
  pathAckPending = true;
}

class PathBleClientCallbacks final : public BLEClientCallbacks {
 public:
  explicit PathBleClientCallbacks(uint8_t index) : index_(index) {}

  void onConnect(BLEClient *) override { pathBleConnected[index_] = true; }

  void onDisconnect(BLEClient *) override {
    pathBleConnected[index_] = false;
    pathBleControls[index_] = nullptr;
    pathBleApplied[index_] = 0xFF;
    pathAckPending = true;
  }

 private:
  uint8_t index_;
};

bool connectPathBle(uint8_t index, BLEAdvertisedDevice *device) {
  if (index > 1 || pathBleConnected[index]) return true;
  if (pathBleClients[index] == nullptr) {
    pathBleClients[index] = BLEDevice::createClient();
    pathBleClients[index]->setClientCallbacks(new PathBleClientCallbacks(index));
  }
  if (!pathBleClients[index]->connectTimeout(device, 1500)) return false;
  pathBleClients[index]->setMTU(185);
  auto *service = pathBleClients[index]->getService(BLEUUID(kPathBleServiceUuid));
  if (service == nullptr) {
    pathBleClients[index]->disconnect();
    return false;
  }
  pathBleControls[index] = service->getCharacteristic(BLEUUID(kPathBleControlUuid));
  if (pathBleControls[index] == nullptr) {
    pathBleClients[index]->disconnect();
    return false;
  }
  if (pathBleControls[index]->canNotify()) {
    pathBleControls[index]->registerForNotify(onPathBleNotify);
  }
  pathBleConnected[index] = true;
  pathBleApplied[index] = 0xFF;
  pathAckPending = true;
  return true;
}

void pathBleConnectionTask(void *) {
  auto *scan = BLEDevice::getScan();
  scan->setActiveScan(true);
  scan->setInterval(100);
  scan->setWindow(80);
  for (;;) {
    if (!pathBleConnected[0] || !pathBleConnected[1]) {
      auto *results = scan->start(2, false);
      if (results != nullptr) {
        for (int i = 0; i < results->getCount(); ++i) {
          auto device = results->getDevice(i);
          if (!device.haveName() || !device.haveServiceUUID() ||
              !device.isAdvertisingService(BLEUUID(kPathBleServiceUuid))) continue;
          for (uint8_t index = 0; index < 2; ++index) {
            if (!pathBleConnected[index] && device.getName() == kPathBleNames[index]) {
              connectPathBle(index, &device);
            }
          }
        }
      }
      scan->clearResults();
      if (!bleConnected) BLEDevice::startAdvertising();
    }
    vTaskDelay(pdMS_TO_TICKS(1000));
  }
}

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
  if (kUseBlePathTransport) {
    xTaskCreatePinnedToCore(pathBleConnectionTask, "path-ble", 8192, nullptr, 1,
                            nullptr, 0);
  }
}

void readTsnBridge() {
  const int packetSize = tsnUdp.parsePacket();
  if (packetSize > 0 && ioNodeConnected) {
    tsnPeerAddress = tsnUdp.remoteIP();
    tsnPeerPort = tsnUdp.remotePort();
    uint8_t buffer[256];
    int remaining = packetSize;
    while (remaining > 0) {
      const int count = tsnUdp.read(buffer, min(remaining, static_cast<int>(sizeof(buffer))));
      if (count <= 0) break;
      ioNodeSerial.write(buffer, count);
      tsnRxBytes += count;
      remaining -= count;
    }
    tsnLastTrafficAt = millis();
  }

  if (tsnPeerPort != 0 && ioNodeSerial.available()) {
    uint8_t buffer[256];
    size_t count = 0;
    while (ioNodeSerial.available() && count < sizeof(buffer)) {
      buffer[count++] = static_cast<uint8_t>(ioNodeSerial.read());
    }
    if (count > 0) {
      tsnUdp.beginPacket(tsnPeerAddress, tsnPeerPort);
      tsnUdp.write(buffer, count);
      tsnUdp.endPacket();
      tsnTxBytes += count;
      tsnLastTrafficAt = millis();
    }
  }
}

void readIoNode() {
  readTsnBridge();
  if (tsnPeerPort != 0) return;
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

void startTsnGateway() {
  WiFi.mode(WIFI_AP);
  WiFi.softAP(kTsnApSsid, kTsnApPassword, kEspNowChannel, false, 2);
  tsnUdp.begin(kTsnUdpPort);
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
  lv_obj_set_size(button, width, 100);
  lv_obj_set_style_radius(button, 4, 0);
  lv_obj_set_style_shadow_width(button, 0, 0);
  lv_obj_set_style_bg_color(button, lv_color_hex(0x151A1D), 0);
  lv_obj_set_style_bg_color(button, lv_color_hex(0x20282C), LV_STATE_PRESSED);
  lv_obj_set_style_border_width(button, 1, 0);
  lv_obj_set_style_border_color(button, lv_color_hex(healthColor(channel.health)), 0);
  lv_obj_add_event_cb(button, channelPressed, LV_EVENT_CLICKED, &channel);
  auto *title = lv_label_create(button);
  lv_label_set_text(title, channel.label);
  lv_obj_set_style_text_font(title, &lv_font_montserrat_22, 0);
  lv_obj_set_style_text_color(title, lv_color_hex(0xE8ECEE), 0);
  lv_obj_align(title, LV_ALIGN_TOP_LEFT, -4, -2);
  auto *route = lv_label_create(button);
  const char *routeText = !strcmp(channel.id, "tsn_front_a") ? "FRONT A  /  REAR" :
                          !strcmp(channel.id, "tsn_front_b") ? "FRONT B  /  REAR" :
                                                               "FRONT A  /  FRONT B";
  lv_label_set_text(route, routeText);
  lv_obj_set_style_text_font(route, &lv_font_montserrat_12, 0);
  lv_obj_set_style_text_color(route, lv_color_hex(0x7F8B91), 0);
  lv_obj_align(route, LV_ALIGN_LEFT_MID, -4, 2);
  auto *transport = lv_label_create(button);
  lv_label_set_text(transport, !strcmp(channel.id, "tsn_rear") ? "LOCAL" : "BLE");
  lv_obj_set_style_text_font(transport, &lv_font_montserrat_12, 0);
  lv_obj_set_style_text_color(transport, lv_color_hex(0x66D6B1), 0);
  lv_obj_align(transport, LV_ALIGN_TOP_RIGHT, 4, 3);
  channel.value = lv_label_create(button);
  lv_label_set_text(channel.value, "NORMAL");
  lv_obj_set_style_text_font(channel.value, &lv_font_montserrat_12, 0);
  lv_obj_set_style_text_color(channel.value, lv_color_hex(healthColor(channel.health)), 0);
  lv_obj_align(channel.value, LV_ALIGN_BOTTOM_LEFT, -4, 3);
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
  lv_obj_set_size(button, width, 76);
  lv_obj_set_style_radius(button, 4, 0);
  lv_obj_set_style_shadow_width(button, 0, 0);
  lv_obj_set_style_bg_color(button, lv_color_hex(0x181E21), 0);
  lv_obj_set_style_bg_color(button, lv_color_hex(0x242D31), LV_STATE_PRESSED);
  lv_obj_set_style_border_width(button, 1, 0);
  lv_obj_set_style_border_color(button, lv_color_hex(color), 0);
  lv_obj_add_event_cb(button, pathActionPressed, LV_EVENT_CLICKED,
                      reinterpret_cast<void *>(action));
  auto *label = lv_label_create(button);
  lv_label_set_text(label, text);
  lv_obj_set_style_text_font(label, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(label, lv_color_hex(color), 0);
  lv_obj_center(label);
}

void makeSensorAction(lv_obj_t *parent, const char *text, int x, int y,
                      intptr_t action, uint32_t color) {
  auto *button = lv_btn_create(parent);
  lv_obj_set_pos(button, x, y);
  lv_obj_set_size(button, 226, 54);
  lv_obj_set_style_radius(button, 5, 0);
  lv_obj_set_style_shadow_width(button, 0, 0);
  lv_obj_set_style_bg_color(button, lv_color_hex(0x181E21), 0);
  lv_obj_set_style_bg_color(button, lv_color_hex(0x242D31), LV_STATE_PRESSED);
  lv_obj_set_style_border_width(button, 1, 0);
  lv_obj_set_style_border_color(button, lv_color_hex(color), 0);
  lv_obj_add_event_cb(button, sensorActionPressed, LV_EVENT_CLICKED,
                      reinterpret_cast<void *>(action));
  auto *label = lv_label_create(button);
  lv_label_set_text(label, text);
  lv_obj_set_style_text_font(label, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(label, lv_color_hex(color), 0);
  lv_obj_center(label);
}

void makeTopologyLine(lv_obj_t *parent, int pathIndex, const lv_point_t *points,
                      uint16_t pointCount) {
  auto *shadow = lv_line_create(parent);
  lv_line_set_points(shadow, points, pointCount);
  lv_obj_set_style_line_width(shadow, 8, 0);
  lv_obj_set_style_line_color(shadow, lv_color_hex(0x0A0D0F), 0);
  lv_obj_set_style_line_rounded(shadow, true, 0);
  pathLines[pathIndex][0] = lv_line_create(parent);
  lv_line_set_points(pathLines[pathIndex][0], points, pointCount);
  lv_obj_set_style_line_width(pathLines[pathIndex][0], 3, 0);
  lv_obj_set_style_line_color(pathLines[pathIndex][0],
                              lv_color_hex(healthColor(channels[pathIndex].health)), 0);
  lv_obj_set_style_line_rounded(pathLines[pathIndex][0], true, 0);
}

void makePathPill(lv_obj_t *parent, int index, int x, int y) {
  auto *button = lv_btn_create(parent);
  lv_obj_set_pos(button, x, y);
  lv_obj_set_size(button, 104, 46);
  lv_obj_set_style_radius(button, 4, 0);
  lv_obj_set_style_shadow_width(button, 0, 0);
  lv_obj_set_style_bg_color(button, lv_color_hex(0x151A1D), 0);
  lv_obj_set_style_bg_color(button, lv_color_hex(0x242D31), LV_STATE_PRESSED);
  lv_obj_set_style_border_width(button, 1, 0);
  lv_obj_set_style_border_color(button, lv_color_hex(healthColor(channels[index].health)), 0);
  lv_obj_add_event_cb(button, channelPressed, LV_EVENT_CLICKED, &channels[index]);
  auto *title = lv_label_create(button);
  lv_label_set_text_fmt(title, "PATH %d", index + 1);
  lv_obj_set_style_text_font(title, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(title, lv_color_hex(0xF4F7F7), 0);
  lv_obj_align(title, LV_ALIGN_TOP_LEFT, -4, -5);
  channels[index].value = lv_label_create(button);
  lv_label_set_text(channels[index].value, "NORMAL");
  lv_obj_set_style_text_font(channels[index].value, &lv_font_montserrat_12, 0);
  lv_obj_align(channels[index].value, LV_ALIGN_BOTTOM_LEFT, -4, 5);
  channels[index].button = button;
}

void makeSwitchNode(lv_obj_t *parent, int index, const char *titleText,
                    const char *subtitle, int x, int y, intptr_t action) {
  auto *button = lv_btn_create(parent);
  lv_obj_set_pos(button, x, y);
  lv_obj_set_size(button, 184, 70);
  lv_obj_set_style_radius(button, 4, 0);
  lv_obj_set_style_shadow_width(button, 0, 0);
  lv_obj_set_style_bg_color(button, lv_color_hex(0x171D20), 0);
  lv_obj_set_style_bg_color(button, lv_color_hex(0x242D31), LV_STATE_PRESSED);
  lv_obj_set_style_border_width(button, 1, 0);
  lv_obj_set_style_border_color(button, lv_color_hex(0x39454A), 0);
  lv_obj_add_event_cb(button, pathActionPressed, LV_EVENT_CLICKED,
                      reinterpret_cast<void *>(action));
  auto *title = lv_label_create(button);
  lv_label_set_text(title, titleText);
  lv_obj_set_style_text_font(title, &lv_font_montserrat_16, 0);
  lv_obj_set_style_text_color(title, lv_color_hex(0xF4F7F7), 0);
  lv_obj_align(title, LV_ALIGN_TOP_LEFT, -4, -3);
  auto *detail = lv_label_create(button);
  lv_label_set_text(detail, subtitle);
  lv_obj_set_style_text_font(detail, &lv_font_montserrat_12, 0);
  lv_obj_set_style_text_color(detail, lv_color_hex(0x7F8B91), 0);
  lv_obj_align(detail, LV_ALIGN_BOTTOM_LEFT, -4, 3);
  switchNodes[index] = button;
}

void toggleSensorOverlay(lv_event_t *) {
  if (sensorOverlay == nullptr) return;
  if (lv_obj_has_flag(sensorOverlay, LV_OBJ_FLAG_HIDDEN)) {
    lv_obj_clear_flag(sensorOverlay, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(sensorOverlay);
  } else {
    lv_obj_add_flag(sensorOverlay, LV_OBJ_FLAG_HIDDEN);
  }
}

void toggleTsnOverlay(lv_event_t *) {
  if (tsnOverlay == nullptr) return;
  if (lv_obj_has_flag(tsnOverlay, LV_OBJ_FLAG_HIDDEN)) {
    lv_obj_clear_flag(tsnOverlay, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(tsnOverlay);
  } else {
    lv_obj_add_flag(tsnOverlay, LV_OBJ_FLAG_HIDDEN);
  }
}

lv_obj_t *makeModeButton(lv_obj_t *parent, const char *text, int x, int y);

lv_obj_t *makeTsnButton(lv_obj_t *parent, const char *text, int x, int y) {
  auto *button = makeModeButton(parent, text, x, y);
  lv_obj_remove_event_cb(button, toggleSensorOverlay);
  lv_obj_add_event_cb(button, toggleTsnOverlay, LV_EVENT_CLICKED, nullptr);
  return button;
}

void createTsnOverlay(lv_obj_t *screen) {
  tsnOverlay = lv_obj_create(screen);
  lv_obj_set_pos(tsnOverlay, 18, 101);
  lv_obj_set_size(tsnOverlay, 764, 286);
  lv_obj_set_style_radius(tsnOverlay, 4, 0);
  lv_obj_set_style_bg_color(tsnOverlay, lv_color_hex(0x101619), 0);
  lv_obj_set_style_border_width(tsnOverlay, 1, 0);
  lv_obj_set_style_border_color(tsnOverlay, lv_color_hex(0x2D383D), 0);
  lv_obj_clear_flag(tsnOverlay, LV_OBJ_FLAG_SCROLLABLE);

  auto *title = lv_label_create(tsnOverlay);
  lv_label_set_text(title, "VELOCITYDRIVE TSN GATEWAY");
  lv_obj_set_style_text_font(title, &lv_font_montserrat_22, 0);
  lv_obj_set_pos(title, 20, 18);
  auto *subtitle = lv_label_create(tsnOverlay);
  lv_label_set_text(subtitle, "LAN9662  USB / MUP1     LAN9692  ETHERNET / COAP");
  lv_obj_set_style_text_color(subtitle, lv_color_hex(0x7F8B91), 0);
  lv_obj_set_pos(subtitle, 20, 52);

  auto *deviceCaption = lv_label_create(tsnOverlay);
  lv_label_set_text(deviceCaption, "USB TARGET");
  lv_obj_set_style_text_color(deviceCaption, lv_color_hex(0x7F8B91), 0);
  lv_obj_set_pos(deviceCaption, 20, 102);
  tsnDeviceValue = lv_label_create(tsnOverlay);
  lv_obj_set_style_text_font(tsnDeviceValue, &lv_font_montserrat_22, 0);
  lv_obj_set_pos(tsnDeviceValue, 20, 126);

  auto *networkCaption = lv_label_create(tsnOverlay);
  lv_label_set_text(networkCaption, "MANAGEMENT AP");
  lv_obj_set_style_text_color(networkCaption, lv_color_hex(0x7F8B91), 0);
  lv_obj_set_pos(networkCaption, 270, 102);
  auto *networkValue = lv_label_create(tsnOverlay);
  lv_label_set_text(networkValue, "KETI-TSN-GATEWAY\n192.168.4.1 : 5683");
  lv_obj_set_style_text_font(networkValue, &lv_font_montserrat_16, 0);
  lv_obj_set_pos(networkValue, 270, 126);

  auto *trafficCaption = lv_label_create(tsnOverlay);
  lv_label_set_text(trafficCaption, "MUP1 TRAFFIC");
  lv_obj_set_style_text_color(trafficCaption, lv_color_hex(0x7F8B91), 0);
  lv_obj_set_pos(trafficCaption, 540, 102);
  tsnTrafficValue = lv_label_create(tsnOverlay);
  lv_obj_set_style_text_font(tsnTrafficValue, &lv_font_montserrat_16, 0);
  lv_obj_set_pos(tsnTrafficValue, 540, 126);

  makeTsnButton(tsnOverlay, "BACK TO NETWORK", 596, 222);
  lv_obj_add_flag(tsnOverlay, LV_OBJ_FLAG_HIDDEN);
}

lv_obj_t *makeModeButton(lv_obj_t *parent, const char *text, int x, int y) {
  auto *button = lv_btn_create(parent);
  lv_obj_set_pos(button, x, y);
  lv_obj_set_size(button, 128, 30);
  lv_obj_set_style_radius(button, 4, 0);
  lv_obj_set_style_shadow_width(button, 0, 0);
  lv_obj_set_style_bg_color(button, lv_color_hex(0x171D20), 0);
  lv_obj_set_style_bg_color(button, lv_color_hex(0x242D31), LV_STATE_PRESSED);
  lv_obj_set_style_border_width(button, 1, 0);
  lv_obj_set_style_border_color(button, lv_color_hex(0x39454A), 0);
  lv_obj_add_event_cb(button, toggleSensorOverlay, LV_EVENT_CLICKED, nullptr);
  auto *label = lv_label_create(button);
  lv_label_set_text(label, text);
  lv_obj_set_style_text_font(label, &lv_font_montserrat_12, 0);
  lv_obj_set_style_text_color(label, lv_color_hex(0xC8D0D3), 0);
  lv_obj_center(label);
  return button;
}

void createUi() {
  auto *screen = lv_scr_act();
  lv_obj_set_style_bg_color(screen, lv_color_hex(0x0B0F11), 0);
  lv_obj_set_style_text_color(screen, lv_color_hex(0xF4F7F7), 0);

  auto *keti = lv_label_create(screen);
  lv_label_set_text(keti, "KETI");
  lv_obj_set_style_text_font(keti, &lv_font_montserrat_16, 0);
  lv_obj_set_style_text_color(keti, lv_color_hex(0x4DA3FF), 0);
  lv_obj_set_pos(keti, 18, 20);
  auto *title = lv_label_create(screen);
  lv_label_set_text(title, "PLEOS RECONFIG");
  lv_obj_set_style_text_font(title, &lv_font_montserrat_22, 0);
  lv_obj_set_pos(title, 76, 15);
  modeLabel = lv_label_create(screen);
  lv_obj_set_style_text_font(modeLabel, &lv_font_montserrat_16, 0);
  lv_obj_align(modeLabel, LV_ALIGN_TOP_RIGHT, -18, 19);
  networkLabel = lv_label_create(screen);
  lv_obj_set_style_text_font(networkLabel, &lv_font_montserrat_16, 0);
  lv_obj_set_pos(networkLabel, 18, 58);
  heartbeatDot = lv_obj_create(screen);
  lv_obj_set_size(heartbeatDot, 10, 10);
  lv_obj_set_pos(heartbeatDot, 382, 62);
  lv_obj_set_style_radius(heartbeatDot, LV_RADIUS_CIRCLE, 0);
  lv_obj_set_style_border_width(heartbeatDot, 0, 0);
  lv_obj_set_style_bg_color(heartbeatDot, lv_color_hex(0x66D6B1), 0);
  lv_obj_clear_flag(heartbeatDot, LV_OBJ_FLAG_SCROLLABLE);
  heartbeatLabel = lv_label_create(screen);
  lv_label_set_text(heartbeatLabel, "PATH BLE");
  lv_obj_set_style_text_color(heartbeatLabel, lv_color_hex(0x92A0A5), 0);
  lv_obj_set_pos(heartbeatLabel, 399, 57);
  linkLabel = lv_label_create(screen);
  lv_label_set_text(linkLabel, "BLE WAITING  |  NOW TX");
  lv_obj_set_style_text_color(linkLabel, lv_color_hex(0x92A0A5), 0);
  lv_obj_align(linkLabel, LV_ALIGN_TOP_RIGHT, -18, 57);
  eventLabel = lv_label_create(screen);
  lv_obj_set_style_text_color(eventLabel, lv_color_hex(0x92A0A5), 0);
  lv_obj_align(eventLabel, LV_ALIGN_TOP_RIGHT, -18, 83);

  static const lv_point_t path1Points[] = {{202, 183}, {354, 292}};
  static const lv_point_t path2Points[] = {{598, 183}, {446, 292}};
  static const lv_point_t path3Points[] = {{264, 148}, {536, 148}};
  makeTopologyLine(screen, 0, path1Points, 2);
  makeTopologyLine(screen, 1, path2Points, 2);
  makeTopologyLine(screen, 2, path3Points, 2);

  makeSwitchNode(screen, 0, "FRONT SWITCH A", "TSN ZONE A", 80, 113, 4);
  makeSwitchNode(screen, 1, "FRONT SWITCH B", "TSN ZONE B", 536, 113, 5);
  makeSwitchNode(screen, 2, "REAR SWITCH", "TSN REAR ZONE", 308, 292, 6);

  makePathPill(screen, 0, 218, 215);
  makePathPill(screen, 1, 478, 215);
  makePathPill(screen, 2, 348, 125);

  auto *topologyLabel = lv_label_create(screen);
  lv_label_set_text(topologyLabel, "BLE VERIFIED VEHICLE NETWORK");
  lv_obj_set_style_text_font(topologyLabel, &lv_font_montserrat_12, 0);
  lv_obj_set_style_text_color(topologyLabel, lv_color_hex(0x687178), 0);
  lv_obj_set_pos(topologyLabel, 18, 370);
  makeModeButton(screen, "SENSORS", 518, 359);
  makeTsnButton(screen, "TSN CONFIG", 654, 359);

  sensorOverlay = lv_obj_create(screen);
  lv_obj_set_pos(sensorOverlay, 18, 101);
  lv_obj_set_size(sensorOverlay, 764, 286);
  lv_obj_set_style_radius(sensorOverlay, 4, 0);
  lv_obj_set_style_bg_color(sensorOverlay, lv_color_hex(0x101619), 0);
  lv_obj_set_style_border_width(sensorOverlay, 1, 0);
  lv_obj_set_style_border_color(sensorOverlay, lv_color_hex(0x2D383D), 0);
  lv_obj_set_style_pad_all(sensorOverlay, 12, 0);
  lv_obj_clear_flag(sensorOverlay, LV_OBJ_FLAG_SCROLLABLE);
  auto *sensorTitle = lv_label_create(sensorOverlay);
  lv_label_set_text(sensorTitle, "SENSOR CONTROL");
  lv_obj_set_style_text_font(sensorTitle, &lv_font_montserrat_16, 0);
  lv_obj_set_style_text_color(sensorTitle, lv_color_hex(0xF4F7F7), 0);
  lv_obj_set_pos(sensorTitle, 4, 0);
  makeModeButton(sensorOverlay, "NETWORK", 596, -4);
  makeSensorAction(sensorOverlay, "LIDAR FRONT LEFT", 0, 42, 0, 0x68A8D8);
  makeSensorAction(sensorOverlay, "LIDAR FRONT RIGHT", 244, 42, 1, 0x68A8D8);
  makeSensorAction(sensorOverlay, "LIDAR REAR", 488, 42, 2, 0x68A8D8);
  makeSensorAction(sensorOverlay, "CAMERA LOSS", 0, 108, 3, 0xC391D4);
  makeSensorAction(sensorOverlay, "GNSS LOSS", 244, 108, 4, 0xC391D4);
  makeSensorAction(sensorOverlay, "DUAL SENSOR", 488, 108, 5, 0xE0A65A);
  lv_obj_add_flag(sensorOverlay, LV_OBJ_FLAG_HIDDEN);

  createTsnOverlay(screen);

  makePathAction(screen, "RECOVER ALL", 18, 394, 764, 7, 0x66D6B1);
  refreshUi();
}

}  // namespace

void setup() {
  digitalWrite(kPath3RelayEnable, LOW);
  pinMode(kPath3RelayEnable, OUTPUT);
  digitalWrite(kPath3RelayEnable, LOW);
  Serial.begin(115200);
  delay(300);
  frameMutex = xSemaphoreCreateMutex();
  assert(frameMutex != nullptr);
  usbHost.onDeviceConnected([](const EspUsbHostDeviceInfo &info) {
    usbDevicePresent = true;
    usbDeviceVid = info.vid;
    usbDevicePid = info.pid;
    ioNodeConnected = info.supported;
    Serial.printf("\n[USB] connected %04X:%04X supported=%d product=%s\n",
                  info.vid, info.pid, info.supported, info.product);
  });
  usbHost.onDeviceDisconnected([](const EspUsbHostDeviceInfo &) {
    usbDevicePresent = false;
    ioNodeConnected = false;
    tsnPeerPort = 0;
  });
  ioNodeSerial.begin(115200);
  usbHost.begin();
  startTsnGateway();
  if (!kUseBlePathTransport) startEspNow();
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
    publishBleState("path_ack", true);
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
  if (heartbeatDot != nullptr && now - lastPulseAt >= 500) {
    lastPulseAt = now;
    lvgl_port_lock(-1);
    lv_label_set_text(heartbeatLabel, "PATH BLE");
    if (tsnDeviceValue != nullptr) {
      if (ioNodeSerial.connected()) {
        ioNodeConnected = true;
        lv_label_set_text_fmt(tsnDeviceValue, "MUP1 READY  %04X:%04X", usbDeviceVid, usbDevicePid);
      } else if (usbDevicePresent) {
        ioNodeConnected = false;
        lv_label_set_text_fmt(tsnDeviceValue, "USB DETECTED  %04X:%04X\nCDC NOT READY", usbDeviceVid, usbDevicePid);
      } else {
        ioNodeConnected = false;
        lv_label_set_text(tsnDeviceValue, "WAITING FOR USB");
      }
      lv_obj_set_style_text_color(tsnDeviceValue,
          lv_color_hex(ioNodeConnected ? 0x66D6B1 : 0xE0A65A), 0);
    }
    if (tsnTrafficValue != nullptr) {
      lv_label_set_text_fmt(tsnTrafficValue, "RX %lu B\nTX %lu B%s",
          static_cast<unsigned long>(tsnRxBytes), static_cast<unsigned long>(tsnTxBytes),
          millis() - tsnLastTrafficAt < 1500 ? "  LIVE" : "");
    }
    lvgl_port_unlock();
  }
  const uint32_t espNowPeriod = urgentEspNowFrames > 0 ?
      kEspNowUrgentPeriodMs : kEspNowPeriodMs;
  if (now - lastEspNowAt >= espNowPeriod) {
    lastEspNowAt = now;
    sendEspNowState();
    if (urgentEspNowFrames > 0) --urgentEspNowFrames;
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
