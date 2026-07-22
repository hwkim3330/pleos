#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <SPI.h>
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>

namespace {

#ifndef PLEOS_PATH_INDEX
#define PLEOS_PATH_INDEX 0
#endif
static_assert(PLEOS_PATH_INDEX == 0 || PLEOS_PATH_INDEX == 1,
              "PLEOS_PATH_INDEX must be 0 (Path1) or 1 (Path2)");

constexpr int kTftCs = 5;
constexpr int kTftDc = 16;
constexpr int kTftReset = 23;
constexpr int kTftBacklight = 4;
constexpr int kInjectButton = 0;
constexpr int kRecoverButton = 35;
// T-Display GPIO27 -> fault-injection PCB RELAY_EN (J3.3).
// LOW keeps the NC Ethernet path closed; HIGH injects a link fault.
constexpr int kRelayEnable = 27;
constexpr uint32_t kCommandWatchdogMs = 1200;
constexpr uint32_t kHeartbeatMs = 1000;
constexpr uint32_t kUiRefreshMs = 200;
constexpr uint32_t kButtonDebounceMs = 40;
constexpr uint32_t kManualOverrideMs = 1200;
constexpr uint8_t kEspNowChannel = 6;
constexpr uint32_t kEspNowMagic = 0x504C454F;
constexpr const char *kPathNames[] = {"PATH 1", "PATH 2"};
constexpr const char *kChannelIds[] = {"tsn_front_a", "tsn_front_b"};
constexpr const char *kNodeIds[] = {"PLEOS_PATH_1", "PLEOS_PATH_2"};
constexpr const char *kBleNames[] = {"PLEOS-PATH1", "PLEOS-PATH2"};
constexpr char kBleServiceUuid[] = "7d2f0011-7c7a-4f7b-9b51-0af9a281d110";
constexpr char kBleControlUuid[] = "7d2f0012-7c7a-4f7b-9b51-0af9a281d110";

Adafruit_ST7789 display(kTftCs, kTftDc, kTftReset);
String commandBuffer;
bool isolated = false;
bool controllerOnline = false;
uint32_t lastCommandAt = 0;
uint32_t lastHeartbeatAt = 0;
uint32_t lastUiAt = 0;
uint32_t sequence = 0;
bool injectButtonHigh = true;
bool recoverButtonHigh = true;
uint32_t injectButtonChangedAt = 0;
uint32_t recoverButtonChangedAt = 0;
uint32_t manualOverrideUntil = 0;
uint32_t lastNowSequence = 0;
uint32_t lastNowReceiveAt = 0;
volatile bool espNowPending = false;
volatile bool espNowIsolated = false;
const char *commandSource = "SAFE";
int8_t previousRingHead = -1;
uint16_t previousRingAccent = 0;
bool ringRedrawPending = true;
BLECharacteristic *bleControl = nullptr;
volatile bool bleConnected = false;
volatile bool bleSnapshotPending = false;

struct __attribute__((packed)) PathNowFrame {
  uint32_t magic;
  uint32_t sequence;
  uint8_t version;
  uint8_t isolatedMask;
  uint16_t crc;
};

uint16_t crc16(const uint8_t *data, size_t length) {
  uint16_t crc = 0xFFFF;
  for (size_t i = 0; i < length; ++i) {
    crc ^= static_cast<uint16_t>(data[i]) << 8;
    for (uint8_t bit = 0; bit < 8; ++bit) {
      crc = (crc & 0x8000) ? static_cast<uint16_t>((crc << 1) ^ 0x1021) :
                             static_cast<uint16_t>(crc << 1);
    }
  }
  return crc;
}

void notifyBle(const String &message) {
  if (!bleConnected || bleControl == nullptr) return;
  bleControl->setValue(message.c_str());
  bleControl->notify();
  delay(4);
}

void sendBleSnapshot(const char *event) {
  if (!bleConnected) return;
  notifyBle(String("!PATH:") + kPathNames[PLEOS_PATH_INDEX] + ":" + sequence + ":" +
            (controllerOnline ? "ONLINE" : "WAITING"));
  notifyBle(String("!CHANNEL:") + kChannelIds[PLEOS_PATH_INDEX] + ":" +
            (isolated ? "ISOLATED" : "NORMAL"));
  notifyBle(String("!EVENT:") + event);
}

uint16_t statusColor() {
  return !controllerOnline ? ST77XX_ORANGE : isolated ? ST77XX_RED : ST77XX_GREEN;
}

void drawLiveMetrics() {
  const uint16_t accent = statusColor();
  display.fillRect(157, 12, 81, 14, ST77XX_BLACK);
  display.setTextSize(1);
  display.setTextColor(espNowPending || controllerOnline ? ST77XX_CYAN : 0x7BEF);
  display.setCursor(160, 18);
  display.printf("LINK %s", commandSource);

  display.fillRect(10, 39, 140, 30, ST77XX_BLACK);
  display.setTextSize(2);
  display.setTextColor(accent);
  display.setCursor(12, 43);
  display.print(!controllerOnline ? "WAITING" : isolated ? "ISOLATED" : "NORMAL");

  const uint32_t age = controllerOnline ? min(millis() - lastCommandAt, kCommandWatchdogMs) :
                                          kCommandWatchdogMs;
  static const int8_t ringX[] = {0, 8, 14, 16, 14, 8, 0, -8, -14, -16, -14, -8};
  static const int8_t ringY[] = {-16, -14, -8, 0, 8, 14, 16, 14, 8, 0, -8, -14};
  const uint8_t head = (millis() / kUiRefreshMs) % 12;
  if (ringRedrawPending || previousRingAccent != accent) {
    display.fillRect(160, 35, 68, 59, ST77XX_BLACK);
    for (uint8_t i = 0; i < 12; ++i) {
      display.fillCircle(194 + ringX[i], 59 + ringY[i], 2, 0x3186);
    }
    previousRingHead = -1;
    previousRingAccent = accent;
    ringRedrawPending = false;
  }
  if (previousRingHead >= 0) {
    display.fillCircle(194 + ringX[previousRingHead], 59 + ringY[previousRingHead], 3,
                       ST77XX_BLACK);
    display.fillCircle(194 + ringX[previousRingHead], 59 + ringY[previousRingHead], 2,
                       0x3186);
  }
  display.fillCircle(194 + ringX[head], 59 + ringY[head], 3, accent);
  previousRingHead = head;
  display.fillRect(176, 53, 40, 11, ST77XX_BLACK);
  display.setTextSize(1);
  display.setTextColor(ST77XX_WHITE);
  display.setCursor(age < 1000 ? 184 : 181, 56);
  display.printf("%lums", age);

  display.fillRect(12, 78, 140, 28, ST77XX_BLACK);
  display.setTextColor(0xAD55);
  display.setCursor(12, 81);
  display.printf("SOURCE  %-5s", commandSource);
  display.setCursor(12, 96);
  display.printf("SEQ     %lu", sequence);
}

void drawStatus() {
  display.fillScreen(ST77XX_BLACK);
  ringRedrawPending = true;
  display.fillRect(0, 0, 240, 6, statusColor());
  display.setTextWrap(false);
  display.setTextColor(ST77XX_WHITE);
  display.setTextSize(2);
  display.setCursor(12, 15);
  display.print(kPathNames[PLEOS_PATH_INDEX]);
  display.setTextColor(0x7BEF);
  display.setCursor(12, 119);
  display.print("BTN1 INJECT     BTN2 RECOVER");
  drawLiveMetrics();
}

void publish() {
  Serial.printf("!CHANNEL:%s:%s\n", kChannelIds[PLEOS_PATH_INDEX],
                isolated ? "ISOLATED" : "NORMAL");
  sendBleSnapshot("channel");
}

void setIsolated(bool value) {
  if (isolated == value && controllerOnline) return;
  isolated = value;
  controllerOnline = true;
  digitalWrite(kRelayEnable, isolated ? HIGH : LOW);
  drawStatus();
  publish();
}

void recoverSafe() {
  isolated = false;
  controllerOnline = false;
  commandSource = "SAFE";
  digitalWrite(kRelayEnable, LOW);
  drawStatus();
  publish();
}

void processCommand(String command) {
  command.trim();
  if (command == "!SYNC") {
    sendBleSnapshot("sync");
    return;
  }
  lastCommandAt = millis();
  commandSource = "BLE";
  if (command == "!RECOVER") {
    setIsolated(false);
    return;
  }
  if (!command.startsWith("!CHANNEL:")) return;
  const int separator = command.indexOf(':', 9);
  if (separator < 0) return;
  if (command.substring(9, separator) != kChannelIds[PLEOS_PATH_INDEX]) return;
  setIsolated(command.substring(separator + 1) != "NORMAL");
}

void onEspNowReceive(const esp_now_recv_info_t *, const uint8_t *data, int length) {
  if (length != sizeof(PathNowFrame)) return;
  PathNowFrame frame;
  memcpy(&frame, data, sizeof(frame));
  if (frame.magic != kEspNowMagic || frame.version != 1) return;
  const uint16_t expected = crc16(reinterpret_cast<const uint8_t *>(&frame),
                                  sizeof(frame) - sizeof(frame.crc));
  if (frame.crc != expected) return;
  const uint32_t now = millis();
  if (frame.sequence <= lastNowSequence && now - lastNowReceiveAt < kCommandWatchdogMs) return;
  lastNowSequence = frame.sequence;
  lastNowReceiveAt = now;
  espNowIsolated = (frame.isolatedMask & (1U << PLEOS_PATH_INDEX)) != 0;
  espNowPending = true;
}

void startEspNow() {
  WiFi.mode(WIFI_STA);
  esp_wifi_set_channel(kEspNowChannel, WIFI_SECOND_CHAN_NONE);
  if (esp_now_init() != ESP_OK) {
    Serial.println("!ESPNOW:INIT_FAILED");
    return;
  }
  esp_now_register_recv_cb(onEspNowReceive);
}

class PathServerCallbacks final : public BLEServerCallbacks {
  void onConnect(BLEServer *) override {
    bleConnected = true;
    bleSnapshotPending = true;
  }

  void onDisconnect(BLEServer *server) override {
    bleConnected = false;
    server->startAdvertising();
  }
};

class PathControlCallbacks final : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    processCommand(characteristic->getValue());
  }
};

void startBle() {
  BLEDevice::init(kBleNames[PLEOS_PATH_INDEX]);
  BLEDevice::setMTU(185);
  auto *server = BLEDevice::createServer();
  server->setCallbacks(new PathServerCallbacks());
  auto *service = server->createService(kBleServiceUuid);
  bleControl = service->createCharacteristic(
      kBleControlUuid,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE |
          BLECharacteristic::PROPERTY_WRITE_NR | BLECharacteristic::PROPERTY_NOTIFY);
  bleControl->setCallbacks(new PathControlCallbacks());
  bleControl->addDescriptor(new BLE2902());
  bleControl->setValue("!BOOT:SAFE_BYPASS");
  service->start();
  auto *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(kBleServiceUuid);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();
}

void readCommands() {
  while (Serial.available()) {
    const char value = static_cast<char>(Serial.read());
    if (value == '\n') {
      processCommand(commandBuffer);
      commandBuffer = "";
    } else if (value != '\r' && commandBuffer.length() < 128) {
      commandBuffer += value;
    }
  }
}

void pollButton(int pin, bool &wasHigh, uint32_t &changedAt, bool recover) {
  const bool isHigh = digitalRead(pin) != LOW;
  if (isHigh == wasHigh || millis() - changedAt < kButtonDebounceMs) return;
  wasHigh = isHigh;
  changedAt = millis();
  if (isHigh) return;
  lastCommandAt = millis();
  if (recover) {
    manualOverrideUntil = millis() + kManualOverrideMs;
    commandSource = "LOCAL";
    setIsolated(false);
    sendBleSnapshot("manual_recover");
  } else {
    manualOverrideUntil = millis() + kManualOverrideMs;
    commandSource = "LOCAL";
    setIsolated(!isolated);
    sendBleSnapshot(isolated ? "manual_inject" : "manual_normal");
  }
}

}  // namespace

void setup() {
  // Establish pass-through before display, serial, or BLE initialization.
  digitalWrite(kRelayEnable, LOW);
  pinMode(kRelayEnable, OUTPUT);
  digitalWrite(kRelayEnable, LOW);
  pinMode(kInjectButton, INPUT_PULLUP);
  pinMode(kRecoverButton, INPUT);
  Serial.begin(115200);
  pinMode(kTftBacklight, OUTPUT);
  digitalWrite(kTftBacklight, HIGH);
  SPI.begin(18, -1, 19, kTftCs);
  display.init(135, 240);
  display.setRotation(1);
  recoverSafe();
  startEspNow();
  startBle();
  Serial.printf("!NODE:%s:READY\n", kNodeIds[PLEOS_PATH_INDEX]);
}

void loop() {
  readCommands();
  if (espNowPending && static_cast<int32_t>(millis() - manualOverrideUntil) >= 0) {
    espNowPending = false;
    lastCommandAt = millis();
    commandSource = "NOW";
    setIsolated(espNowIsolated);
  }
  pollButton(kInjectButton, injectButtonHigh, injectButtonChangedAt, false);
  pollButton(kRecoverButton, recoverButtonHigh, recoverButtonChangedAt, true);
  if (bleSnapshotPending) {
    bleSnapshotPending = false;
    sendBleSnapshot("connected");
  }
  if (controllerOnline && millis() - lastCommandAt >= kCommandWatchdogMs) recoverSafe();
  if (millis() - lastHeartbeatAt >= kHeartbeatMs) {
    lastHeartbeatAt = millis();
    Serial.printf("!NODE:%s:HEARTBEAT:%lu\n", kNodeIds[PLEOS_PATH_INDEX], ++sequence);
  }
  if (millis() - lastUiAt >= kUiRefreshMs) {
    lastUiAt = millis();
    drawLiveMetrics();
  }
  delay(5);
}
