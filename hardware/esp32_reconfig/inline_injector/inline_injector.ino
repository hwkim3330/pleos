#include <Arduino.h>

namespace {

// A physical build must use normally-closed bypass relays. Keep actuation
// locked until the relay board, active level, watchdog and pin map are tested.
constexpr bool kActuationEnabled = false;
constexpr uint32_t kHeartbeatMs = 1000;
#ifndef PLEOS_LINK_INDEX
#define PLEOS_LINK_INDEX 0
#endif
static_assert(PLEOS_LINK_INDEX >= 0 && PLEOS_LINK_INDEX <= 2, "PLEOS_LINK_INDEX must be 0, 1 or 2");
constexpr const char *kLinkIds[] = {"tsn_front_a", "tsn_front_b", "tsn_rear"};
constexpr const char *kNodeIds[] = {"PLEOS_INLINE_AR", "PLEOS_INLINE_BR", "PLEOS_INLINE_AB"};

struct Link {
  const char *id;
  int sensePin;
  int relayPin;
  bool isolated;
};

Link channel{kLinkIds[PLEOS_LINK_INDEX], -1, -1, false};

String input;
uint32_t sequence;
uint32_t lastHeartbeat;

void publish(const Link &link) {
  Serial.printf("!CHANNEL:%s:%s\n", link.id, link.isolated ? "ISOLATED" : "NORMAL");
}

void setIsolated(Link &link, bool isolated) {
  link.isolated = isolated;
  if (kActuationEnabled && link.relayPin >= 0) {
    digitalWrite(link.relayPin, isolated ? HIGH : LOW);
  }
  publish(link);
}

void recover() {
  setIsolated(channel, false);
}

void process(const String &command) {
  if (command == "!RECOVER") return recover();
  if (!command.startsWith("!CHANNEL:")) return;
  const int separator = command.indexOf(':', 9);
  if (separator < 0) return;
  const String id = command.substring(9, separator);
  const String health = command.substring(separator + 1);
  if (id == channel.id) setIsolated(channel, health != "NORMAL");
}

void readCommands() {
  while (Serial.available()) {
    const char value = static_cast<char>(Serial.read());
    if (value == '\n') {
      input.trim();
      process(input);
      input = "";
    } else if (value != '\r' && input.length() < 128) {
      input += value;
    }
  }
}

}  // namespace

void setup() {
  Serial.begin(115200);
  delay(500);
  if (kActuationEnabled && channel.sensePin >= 0) pinMode(channel.sensePin, INPUT_PULLUP);
  if (kActuationEnabled && channel.relayPin >= 0) pinMode(channel.relayPin, OUTPUT);
  Serial.printf("!NODE:%s:READY\n", kNodeIds[PLEOS_LINK_INDEX]);
  recover();
}

void loop() {
  readCommands();
  if (millis() - lastHeartbeat >= kHeartbeatMs) {
    lastHeartbeat = millis();
    Serial.printf("!NODE:%s:HEARTBEAT:%lu\n", kNodeIds[PLEOS_LINK_INDEX], ++sequence);
  }
  delay(5);
}
