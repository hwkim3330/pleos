#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <Arduino.h>
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
constexpr uint32_t kCommandWatchdogMs = 5000;
constexpr uint32_t kHeartbeatMs = 1000;
constexpr const char *kPathNames[] = {"PATH 1", "PATH 2"};
constexpr const char *kChannelIds[] = {"tsn_front_a", "tsn_front_b"};
constexpr const char *kNodeIds[] = {"PLEOS_PATH_1", "PLEOS_PATH_2"};

Adafruit_ST7789 display(kTftCs, kTftDc, kTftReset);
String commandBuffer;
bool isolated = false;
bool controllerOnline = false;
uint32_t lastCommandAt = 0;
uint32_t lastHeartbeatAt = 0;
uint32_t sequence = 0;

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
}

void setIsolated(bool value) {
  if (isolated == value && controllerOnline) return;
  isolated = value;
  controllerOnline = true;
  drawStatus();
  publish();
}

void recoverSafe() {
  isolated = false;
  controllerOnline = false;
  drawStatus();
  publish();
}

void processCommand(String command) {
  command.trim();
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
  Serial.begin(115200);
  pinMode(kTftBacklight, OUTPUT);
  digitalWrite(kTftBacklight, HIGH);
  SPI.begin(18, -1, 19, kTftCs);
  display.init(135, 240);
  display.setRotation(1);
  recoverSafe();
  Serial.printf("!NODE:%s:READY\n", kNodeIds[PLEOS_PATH_INDEX]);
}

void loop() {
  readCommands();
  if (controllerOnline && millis() - lastCommandAt >= kCommandWatchdogMs) recoverSafe();
  if (millis() - lastHeartbeatAt >= kHeartbeatMs) {
    lastHeartbeatAt = millis();
    Serial.printf("!NODE:%s:HEARTBEAT:%lu\n", kNodeIds[PLEOS_PATH_INDEX], ++sequence);
  }
  delay(5);
}
