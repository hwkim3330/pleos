#include <Arduino.h>
#include <EspUsbHost.h>
#include <esp_display_panel.hpp>
#include <lvgl.h>

#include "lvgl_v8_port.h"

using namespace esp_panel::board;
using namespace esp_panel::drivers;
namespace {

constexpr uint8_t kProtocolVersion = 1;
constexpr uint32_t kHeartbeatMs = 1000;
constexpr bool kPhysicalOutputsEnabled = false;

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
  const bool frontNetwork = available("tsn_front_a") || available("tsn_front_b");
  const bool rearNetwork = available("tsn_rear");
  if (!frontNetwork || !rearNetwork || sensorKinds == 0) effectiveMode = "MRM";
  else if (sensorKinds == 3) effectiveMode = "TRIPLE";
  else if (sensorKinds == 2) effectiveMode = "DUAL";
  else effectiveMode = "SINGLE";
}

void refreshUi() {
  deriveMode();
  for (auto &channel : channels) {
    lv_label_set_text(channel.value, healthName(channel.health));
    lv_obj_set_style_bg_color(channel.button, lv_color_hex(healthColor(channel.health)), 0);
  }
  lv_label_set_text_fmt(modeLabel, "AUTOWARE MODE  %s", effectiveMode);
  lv_obj_set_style_text_color(modeLabel, lv_color_hex(!strcmp(effectiveMode, "MRM") ? 0xFF6A61 : 0x66D6B1), 0);
  lv_label_set_text(eventLabel, lastEvent);
  lv_label_set_text(linkLabel, ioNodeConnected ? "MAC LINK  READY   |   I/O NODE  ONLINE"
                                               : "MAC LINK  READY   |   I/O NODE  OFFLINE");
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
  if (command == "!RECOVER") {
    applyScenarioNumber(4, forwardToNode);
    return;
  }
  if (command.startsWith("!SCENARIO:")) {
    applyScenarioNumber(command.substring(10).toInt(), forwardToNode);
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
  lv_obj_set_style_bg_color(button, lv_color_hex(healthColor(channel.health)), 0);
  lv_obj_add_event_cb(button, channelPressed, LV_EVENT_CLICKED, &channel);
  auto *title = lv_label_create(button);
  lv_label_set_text(title, channel.label);
  lv_obj_set_style_text_font(title, &lv_font_montserrat_14, 0);
  lv_obj_align(title, LV_ALIGN_TOP_LEFT, -4, -4);
  channel.value = lv_label_create(button);
  lv_label_set_text(channel.value, "NORMAL");
  lv_obj_set_style_text_font(channel.value, &lv_font_montserrat_12, 0);
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

void createUi() {
  auto *screen = lv_scr_act();
  lv_obj_set_style_bg_color(screen, lv_color_hex(0x101517), 0);
  lv_obj_set_style_text_color(screen, lv_color_hex(0xF4F7F7), 0);

  auto *title = lv_label_create(screen);
  lv_label_set_text(title, "PLEOS RECONFIG CONTROLLER");
  lv_obj_set_style_text_font(title, &lv_font_montserrat_24, 0);
  lv_obj_set_pos(title, 18, 15);
  modeLabel = lv_label_create(screen);
  lv_obj_set_style_text_font(modeLabel, &lv_font_montserrat_16, 0);
  lv_obj_align(modeLabel, LV_ALIGN_TOP_RIGHT, -18, 19);
  linkLabel = lv_label_create(screen);
  lv_label_set_text(linkLabel, "MAC LINK  READY   |   I/O NODE  OFFLINE");
  lv_obj_set_style_text_color(linkLabel, lv_color_hex(0x92A0A5), 0);
  lv_obj_set_pos(linkLabel, 19, 49);
  eventLabel = lv_label_create(screen);
  lv_obj_set_style_text_color(eventLabel, lv_color_hex(0xB5C0C3), 0);
  lv_obj_align(eventLabel, LV_ALIGN_TOP_RIGHT, -18, 49);

  makeCard(screen, channels[0], 18, 82, 240);
  makeCard(screen, channels[1], 280, 82, 240);
  makeCard(screen, channels[2], 542, 82, 240);
  for (int i = 0; i < 4; ++i) makeCard(screen, channels[3 + i], 18 + i * 196, 171, 174);
  makeCard(screen, channels[7], 18, 260, 370);
  makeCard(screen, channels[8], 412, 260, 370);

  auto *hint = lv_label_create(screen);
  lv_label_set_text(hint, "Tap a channel to inject/recover. Physical relay outputs are locked.");
  lv_obj_set_style_text_color(hint, lv_color_hex(0x89959A), 0);
  lv_obj_set_pos(hint, 19, 349);
  makeScenario(screen, "LiDAR FL LOSS", 18, 1, 0x345F79);
  makeScenario(screen, "DUAL SENSOR", 214, 2, 0x735E2E);
  makeScenario(screen, "FRONT TSN / MRM", 410, 3, 0xA3423C);
  makeScenario(screen, "RECOVER ALL", 606, 4, 0x177C62);
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
  if (ioNodeConnected != lastRenderedIoNodeConnected) {
    lastRenderedIoNodeConnected = ioNodeConnected;
    lastEvent = ioNodeConnected ? "USB I/O node connected" : "USB I/O node disconnected";
    lvgl_port_lock(-1);
    refreshUi();
    lvgl_port_unlock();
    sendState(ioNodeConnected ? "io_node_connected" : "io_node_disconnected");
  }
  const uint32_t now = millis();
  if (now - lastHeartbeat >= kHeartbeatMs) {
    lastHeartbeat = now;
    sendState("heartbeat");
  }
  delay(10);
}
