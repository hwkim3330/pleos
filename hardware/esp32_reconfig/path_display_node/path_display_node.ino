#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <SPI.h>

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
// T-Display GPIO27 -> fault-injection PCB RELAY_EN (J3.3).
// LOW keeps the NC Ethernet path closed; HIGH injects a link fault.
constexpr int kRelayEnable = 27;
constexpr uint32_t kCommandWatchdogMs = 5000;
constexpr uint32_t kHeartbeatMs = 1000;
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
uint32_t sequence = 0;
BLECharacteristic *bleControl = nullptr;
volatile bool bleConnected = false;
volatile bool bleSnapshotPending = false;

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

void drawStatus() {
  const uint16_t accent = !controllerOnline ? ST77XX_ORANGE
                           : isolated       ? ST77XX_RED
                                            : ST77XX_GREEN;
  display.fillScreen(ST77XX_BLACK);
  display.fillRect(0, 0, 240, 7, accent);
  display.setTextWrap(false);
  display.setTextColor(ST77XX_WHITE);
  display.setTextSize(3);
  display.setCursor(14, 18);
  display.print(kPathNames[PLEOS_PATH_INDEX]);
  display.setTextSize(2);
  display.setTextColor(accent);
  display.setCursor(14, 58);
  display.print(!controllerOnline ? "WAITING" : isolated ? "ISOLATED" : "NORMAL");
  display.setTextSize(1);
  display.setTextColor(0xC618);
  display.setCursor(14, 94);
  display.print("NC BYPASS  |  WATCHDOG 5s");
  display.setCursor(14, 111);
  display.print(kNodeIds[PLEOS_PATH_INDEX]);
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

}  // namespace

void setup() {
  // Establish pass-through before display, serial, or BLE initialization.
  digitalWrite(kRelayEnable, LOW);
  pinMode(kRelayEnable, OUTPUT);
  digitalWrite(kRelayEnable, LOW);
  Serial.begin(115200);
  pinMode(kTftBacklight, OUTPUT);
  digitalWrite(kTftBacklight, HIGH);
  SPI.begin(18, -1, 19, kTftCs);
  display.init(135, 240);
  display.setRotation(1);
  recoverSafe();
  startBle();
  Serial.printf("!NODE:%s:READY\n", kNodeIds[PLEOS_PATH_INDEX]);
}

void loop() {
  readCommands();
  if (bleSnapshotPending) {
    bleSnapshotPending = false;
    sendBleSnapshot("connected");
  }
  if (controllerOnline && millis() - lastCommandAt >= kCommandWatchdogMs) recoverSafe();
  if (millis() - lastHeartbeatAt >= kHeartbeatMs) {
    lastHeartbeatAt = millis();
    Serial.printf("!NODE:%s:HEARTBEAT:%lu\n", kNodeIds[PLEOS_PATH_INDEX], ++sequence);
  }
  delay(5);
}
