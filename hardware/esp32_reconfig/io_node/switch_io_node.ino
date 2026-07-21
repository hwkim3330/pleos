#include <Arduino.h>

namespace {

// Keep relay outputs locked until the switch PCB pin map is verified.
constexpr bool kPhysicalIoEnabled = false;
constexpr uint32_t kReportIntervalMs = 1000;

struct Channel {
  const char *id;
  const char *health;
  int inputPin;
  int relayPin;
};

Channel channels[] = {
    {"tsn_front_a", "NORMAL", -1, -1}, {"tsn_front_b", "NORMAL", -1, -1},
    {"tsn_rear", "NORMAL", -1, -1},    {"lidar_fl", "NORMAL", -1, -1},
    {"lidar_fr", "NORMAL", -1, -1},   {"lidar_rl", "NORMAL", -1, -1},
    {"lidar_rr", "NORMAL", -1, -1},   {"gnss", "NORMAL", -1, -1},
    {"camera", "NORMAL", -1, -1},
};

String commandBuffer;
uint32_t lastReport;

void publishChannel(const Channel &channel) {
  Serial.printf("!CHANNEL:%s:%s\n", channel.id, channel.health);
}

void publishAll() {
  for (const auto &channel : channels) publishChannel(channel);
}

void setChannel(Channel &channel, const String &health) {
  channel.health = health == "FAULT"      ? "FAULT"
                   : health == "DEGRADED" ? "DEGRADED"
                   : health == "ISOLATED" ? "ISOLATED"
                                            : "NORMAL";
  if (kPhysicalIoEnabled && channel.relayPin >= 0) {
    digitalWrite(channel.relayPin, strcmp(channel.health, "NORMAL") ? HIGH : LOW);
  }
  publishChannel(channel);
}

void recoverAll() {
  for (auto &channel : channels) setChannel(channel, "NORMAL");
}

void applyScenario(int id) {
  recoverAll();
  if (id == 1) setChannel(channels[3], "FAULT");
  if (id == 2) {
    setChannel(channels[7], "DEGRADED");
    setChannel(channels[8], "FAULT");
  }
  if (id == 3) {
    setChannel(channels[0], "FAULT");
    setChannel(channels[1], "FAULT");
  }
}

void processCommand(const String &command) {
  if (command == "!RECOVER") return recoverAll();
  if (command.startsWith("!SCENARIO:")) return applyScenario(command.substring(10).toInt());
  if (!command.startsWith("!CHANNEL:")) return;
  const int separator = command.indexOf(':', 9);
  if (separator < 0) return;
  const String id = command.substring(9, separator);
  for (auto &channel : channels) {
    if (id == channel.id) return setChannel(channel, command.substring(separator + 1));
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

void readPhysicalInputs() {
  if (!kPhysicalIoEnabled) return;
  for (auto &channel : channels) {
    if (channel.inputPin < 0) continue;
    const char *health = digitalRead(channel.inputPin) == LOW ? "FAULT" : "NORMAL";
    if (strcmp(channel.health, health)) setChannel(channel, health);
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);
  delay(500);
  for (auto &channel : channels) {
    if (kPhysicalIoEnabled && channel.inputPin >= 0) pinMode(channel.inputPin, INPUT_PULLUP);
    if (kPhysicalIoEnabled && channel.relayPin >= 0) pinMode(channel.relayPin, OUTPUT);
  }
  Serial.println("!NODE:PLEOS_SWITCH_IO:READY");
  publishAll();
}

void loop() {
  readCommands();
  readPhysicalInputs();
  if (millis() - lastReport >= kReportIntervalMs) {
    lastReport = millis();
    publishAll();
  }
  delay(5);
}
