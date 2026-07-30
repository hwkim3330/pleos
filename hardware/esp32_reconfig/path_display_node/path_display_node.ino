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
static_assert(PLEOS_PATH_INDEX >= 0 && PLEOS_PATH_INDEX <= 2,
              "PLEOS_PATH_INDEX must be 0 (Path1), 1 (Path2), or 2 (Path3)");

constexpr int kTftCs = 5;
constexpr int kTftDc = 16;
constexpr int kTftReset = 23;
constexpr int kTftBacklight = 4;
constexpr int kInjectButton = 0;
constexpr int kRecoverButton = 35;
// T-Display GPIO27 -> fault-injection PCB RELAY_EN (J3.3).
// LOW keeps the NC Ethernet path closed; HIGH injects a link fault.
constexpr int kRelayEnable = 27;
constexpr uint32_t kCommandWatchdogMs = 10000;
constexpr uint32_t kHeartbeatMs = 1000;
constexpr uint32_t kAckPeriodMs = 600 + (PLEOS_PATH_INDEX * 250);
constexpr uint32_t kUiRefreshMs = 200;
constexpr uint32_t kButtonDebounceMs = 40;
constexpr bool kUseBleController = true;
constexpr uint8_t kEspNowChannel = 6;
constexpr uint32_t kEspNowMagic = 0x504C454F;
constexpr uint32_t kPathAckMagic = 0x5041434B;
constexpr uint8_t kControllerMac[ESP_NOW_ETH_ALEN] =
    {0xCC, 0xBA, 0x97, 0x15, 0xAD, 0x3C};
constexpr const char *kPathNames[] = {"PATH 1", "PATH 2", "PATH 3"};
constexpr const char *kChannelIds[] = {"tsn_front_a", "tsn_front_b", "tsn_rear"};
constexpr const char *kNodeIds[] = {"PLEOS_PATH_1", "PLEOS_PATH_2", "PLEOS_PATH_3"};
constexpr const char *kBleNames[] = {"PLEOS-PATH1", "PLEOS-PATH2", "PLEOS-PATH3"};
constexpr char kBleServiceUuid[] = "7d2f0011-7c7a-4f7b-9b51-0af9a281d110";
constexpr char kBleControlUuid[] = "7d2f0012-7c7a-4f7b-9b51-0af9a281d110";

Adafruit_ST7789 display(kTftCs, kTftDc, kTftReset);
String commandBuffer;
bool isolated = false;
uint32_t lastCommandAt = 0;
uint32_t lastHeartbeatAt = 0;
uint32_t lastAckAt = 0;
uint32_t lastUiAt = 0;
uint32_t sequence = 0;
bool injectButtonHigh = true;
bool recoverButtonHigh = true;
uint32_t injectButtonChangedAt = 0;
uint32_t recoverButtonChangedAt = 0;
// The upper button latches: one tap toggles the relay and gives the local
// operator ownership of this node until the lower button releases it. Holding
// is no longer required, and the latch is reported upstream so the 7-inch
// controller and the tablet follow the relay instead of diverging from it.
bool localLatched = false;
// Bumped by the lower button. Carried in the polled status value because
// notifications never reach the controller, so a counter the controller can
// diff is the only way an edge event survives the trip.
uint32_t alertSeq = 0;
uint32_t lastNowSequence = 0;
uint32_t lastNowReceiveAt = 0;
volatile bool espNowPending = false;
volatile bool espNowIsolated = false;
const char *commandSource = "SAFE";
int8_t previousRingHead = -1;
uint16_t previousRingAccent = 0;
bool ringRedrawPending = true;
volatile bool pollSeen = false;
volatile bool pendingForceRelease = false;
volatile int8_t pendingBleCommand = -1;
volatile uint32_t pendingBleCommandId = 0;
volatile bool bleDisconnectPending = false;
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

struct __attribute__((packed)) PathAckFrame {
  uint32_t magic;
  uint32_t sequence;
  uint8_t version;
  uint8_t pathIndex;
  uint8_t isolated;
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

// Notifications are best-effort only. The Arduino BLE *client* in the 7-inch
// controller cannot subscribe: its BLERemoteCharacteristic discovers zero
// descriptors, so registerForNotify() skips the CCCD write and the peer never
// enables notifications. The controller therefore polls this characteristic by
// read instead, which uses the value handle and needs no descriptor discovery.
constexpr uint32_t kNotifyGapMs = 8;

String statusValue() {
  return String("!LOCAL:") + (localLatched ? "1" : "0") + ":" +
         (isolated ? "ISOLATED" : "NORMAL") + ":" + alertSeq;
}

// Keep the characteristic value equal to the current status at all times, so a
// read by the controller always returns the truth.
void publishStatusValue() {
  if (bleControl == nullptr) return;
  bleControl->setValue(statusValue().c_str());
}

void notifyBle(const String &message) {
  if (!bleConnected || bleControl == nullptr) return;
  bleControl->setValue(message.c_str());
  bleControl->notify();
  delay(kNotifyGapMs);
}

// Tells the controller who owns this node and what the relay actually is, so a
// locally latched fault is adopted upstream instead of being invisible there.
// Sent standalone and repeated every second: the controller adopts it
// idempotently, so a dropped notification self-heals instead of leaving the
// 7-inch and the tablet disagreeing with the relay.
void notifyLocalOwnership() {
  notifyBle(statusValue());
  publishStatusValue();
}

// Lower button: ask the operator surfaces to call out which path this is.
void notifyAlert() {
  notifyBle(String("!ALERT:") + (PLEOS_PATH_INDEX + 1));
}

void sendBleSnapshot(const char *event) {
  if (!bleConnected) return;
  notifyBle(String("!PATH:") + kPathNames[PLEOS_PATH_INDEX] + ":" + sequence + ":" +
            (bleConnected ? "ONLINE" : "WAITING"));
  notifyBle(String("!CHANNEL:") + kChannelIds[PLEOS_PATH_INDEX] + ":" +
            (isolated ? "ISOLATED" : "NORMAL"));
  notifyBle(statusValue());
  notifyBle(String("!EVENT:") + event);
  // Leave the value holding the status, not the last notification, because the
  // controller reads this characteristic to learn our state.
  publishStatusValue();
}

// Derived straight from the BLE link and the relay, with no separate
// "controller is talking to me" flag. That flag depended on the node's onRead
// callback firing for every poll; if it ever did not, the display could sit on
// an intermediate state forever. Two observable facts are enough.
const char *stateName() {
  if (isolated) return "FAULT";
  return bleConnected ? "READY" : "WAIT";
}

uint16_t statusColor() {
  if (isolated) return ST77XX_RED;
  return bleConnected ? ST77XX_GREEN : ST77XX_ORANGE;
}

void printCentered(const char *text, int16_t centerX, int16_t baselineY, uint8_t size,
                   uint16_t color) {
  int16_t x, y;
  uint16_t width, height;
  display.setTextSize(size);
  display.getTextBounds(text, 0, baselineY, &x, &y, &width, &height);
  display.setTextColor(color);
  display.setCursor(centerX - width / 2, baselineY);
  display.print(text);
}

void drawLiveMetrics() {
  const uint16_t accent = statusColor();
  const uint32_t age = bleConnected ? min(millis() - lastCommandAt, kCommandWatchdogMs)
                                    : kCommandWatchdogMs;
  static const int8_t ringX[] = {0, 7, 10, 7, 0, -7, -10, -7};
  static const int8_t ringY[] = {-10, -7, 0, 7, 10, 7, 0, -7};
  const uint8_t head = (millis() / kUiRefreshMs) % 8;
  if (ringRedrawPending || previousRingAccent != accent) {
    for (uint8_t i = 0; i < 8; ++i) {
      display.fillCircle(215 + ringX[i], 24 + ringY[i], 1, 0x2945);
    }
    previousRingHead = -1;
    previousRingAccent = accent;
    ringRedrawPending = false;
  }
  if (previousRingHead >= 0) {
    display.fillCircle(215 + ringX[previousRingHead], 24 + ringY[previousRingHead], 2,
                       ST77XX_BLACK);
    display.fillCircle(215 + ringX[previousRingHead], 24 + ringY[previousRingHead], 1,
                       0x2945);
  }
  display.fillCircle(215 + ringX[head], 24 + ringY[head], 2, accent);
  previousRingHead = head;

  display.fillRect(57, 61, 176, 31, ST77XX_BLACK);
  printCentered(stateName(), 145, 65, 3, accent);

  display.fillRect(62, 108, 166, 19, ST77XX_BLACK);
  char footer[40];
  snprintf(footer, sizeof(footer), "%s  |  %lums  |  #%lu", commandSource, age, sequence);
  printCentered(footer, 145, 112, 1, 0x9CF3);

  display.fillRect(0, 20, 3, 42,
                   localLatched && isolated ? ST77XX_RED
                                            : localLatched ? ST77XX_ORANGE : 0x4208);
  display.fillRect(0, 75, 3, 42, localLatched ? ST77XX_GREEN : 0x4208);
}

void drawShell() {
  display.fillScreen(ST77XX_BLACK);
  ringRedrawPending = true;
  display.setTextWrap(false);
  display.setTextColor(ST77XX_WHITE);
  display.setTextSize(3);
  display.setCursor(61, 13);
  display.print(kPathNames[PLEOS_PATH_INDEX]);
  display.setTextSize(1);
  display.setTextColor(0x6B6D);
  display.setCursor(62, 45);
  display.print(kChannelIds[PLEOS_PATH_INDEX]);
  display.drawFastVLine(48, 17, 104, 0x2104);
  display.drawFastHLine(6, 68, 35, 0x2104);
  display.setTextColor(0x9CF3);
  display.setCursor(8, 31);
  display.print("TAP");
  display.setCursor(8, 43);
  display.print("TOGGLE");
  display.setTextColor(0x7BEF);
  display.setCursor(8, 86);
  display.print("TAP");
  display.setCursor(8, 98);
  display.print("RELEASE");
  drawLiveMetrics();
}

void publish() {
  Serial.printf("!CHANNEL:%s:%s\n", kChannelIds[PLEOS_PATH_INDEX],
                isolated ? "ISOLATED" : "NORMAL");
  sendBleSnapshot("channel");
}

void setIsolated(bool value) {
  if (isolated == value) {
    // No change, but keep the polled value fresh.
    publishStatusValue();
    return;
  }
  isolated = value;
  digitalWrite(kRelayEnable, isolated ? HIGH : LOW);
  ringRedrawPending = true;
  drawLiveMetrics();
  publish();
}

void recoverSafe() {
  isolated = false;
  commandSource = "SAFE";
  // Fail-safe outranks the local latch: losing the controller must return the
  // pair to NC pass-through and hand ownership back.
  localLatched = false;
  digitalWrite(kRelayEnable, LOW);
  ringRedrawPending = true;
  drawLiveMetrics();
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
    localLatched = false;
    setIsolated(false);
    return;
  }
  // Bench affordance: reproduce an upper-button latch without the button, so the
  // supervisor-overrides-latch behaviour can be tested from a host.
  if (command == "!LATCH") {
    localLatched = true;
    commandSource = "LATCH";
    setIsolated(true);
    publishStatusValue();
    ringRedrawPending = true;
    drawLiveMetrics();
    return;
  }
  // Bench affordance: exercise the identify effect without the physical button.
  if (command == "!ALERT") {
    ++alertSeq;
    publishStatusValue();
    notifyAlert();
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
  esp_wifi_set_ps(WIFI_PS_NONE);
  esp_wifi_set_channel(kEspNowChannel, WIFI_SECOND_CHAN_NONE);
  if (esp_now_init() != ESP_OK) {
    Serial.println("!ESPNOW:INIT_FAILED");
    return;
  }
  esp_now_register_recv_cb(onEspNowReceive);
  esp_now_peer_info_t peer{};
  memcpy(peer.peer_addr, kControllerMac, ESP_NOW_ETH_ALEN);
  peer.channel = kEspNowChannel;
  peer.ifidx = WIFI_IF_STA;
  peer.encrypt = false;
  if (esp_now_add_peer(&peer) != ESP_OK) Serial.println("!ESPNOW:PEER_FAILED");
}

void sendEspNowAck() {
  PathAckFrame frame{kPathAckMagic, sequence, 1,
                     static_cast<uint8_t>(PLEOS_PATH_INDEX),
                     static_cast<uint8_t>(isolated), 0};
  frame.crc = crc16(reinterpret_cast<const uint8_t *>(&frame),
                    sizeof(frame) - sizeof(frame.crc));
  esp_now_send(kControllerMac, reinterpret_cast<const uint8_t *>(&frame), sizeof(frame));
}

class PathServerCallbacks final : public BLEServerCallbacks {
  void onConnect(BLEServer *) override {
    bleConnected = true;
    bleSnapshotPending = true;
  }

  void onDisconnect(BLEServer *server) override {
    bleConnected = false;
    bleDisconnectPending = true;
    server->startAdvertising();
  }
};

class PathControlCallbacks final : public BLECharacteristicCallbacks {
  // The controller polls this characteristic every 250 ms, so a read is proof
  // that it is alive and talking to us. Without this the node could not tell it
  // was being supervised at all once command traffic stopped, and the display
  // stayed on WAIT forever.
  void onRead(BLECharacteristic *) override { pollSeen = true; }

  void onWrite(BLECharacteristic *characteristic) override {
    String command = characteristic->getValue();
    command.trim();
    if (command.startsWith("!SET:")) {
      const int separator = command.indexOf(':', 5);
      if (separator > 5) {
        pendingBleCommandId = command.substring(5, separator).toInt();
        pendingBleCommand = command.substring(separator + 1) == "SAFE" ? 0 : 1;
      }
      return;
    }
    if (command == "!SYNC") {
      pendingBleCommand = 2;
    } else if (command == "!RECOVER") {
      // Explicit operator action from the supervisor: it must break a local
      // latch. A button on a bench node cannot be allowed to lock the 7-inch
      // out of recovering the network.
      pendingForceRelease = true;
    } else if (command.startsWith("!CHANNEL:")) {
      const int separator = command.indexOf(':', 9);
      if (separator >= 0 && command.substring(9, separator) == kChannelIds[PLEOS_PATH_INDEX]) {
        pendingBleCommand = command.substring(separator + 1) == "NORMAL" ? 0 : 1;
      }
    }
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
  // Start from a readable status rather than a boot banner: the controller polls
  // this value and should get a parseable answer from the first read.
  bleControl->setValue(statusValue().c_str());
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

void pollButtons() {
  const uint32_t now = millis();

  // Upper button (GPIO0): tap to toggle the relay and take local ownership.
  const bool injectHigh = digitalRead(kInjectButton) != LOW;
  if (injectHigh != injectButtonHigh && now - injectButtonChangedAt >= kButtonDebounceMs) {
    injectButtonHigh = injectHigh;
    injectButtonChangedAt = now;
    if (!injectHigh) {
      const bool target = !isolated;
      localLatched = true;
      lastCommandAt = now;
      commandSource = "LATCH";
      setIsolated(target);
      sendBleSnapshot(target ? "local_fault" : "local_normal");
    }
  }

  // Lower button (GPIO35): does not touch the relay. It hands control back to
  // the network and raises a "this is Path N" alert on the 7-inch and the
  // tablet, so the two buttons have plainly different jobs: the upper one is
  // the relay, the lower one is control and attention.
  const bool recoverHigh = digitalRead(kRecoverButton) != LOW;
  if (recoverHigh != recoverButtonHigh && now - recoverButtonChangedAt >= kButtonDebounceMs) {
    recoverButtonHigh = recoverHigh;
    recoverButtonChangedAt = now;
    if (!recoverHigh) {
      localLatched = false;
      lastCommandAt = now;
      commandSource = "LOCAL";
      ++alertSeq;
      setIsolated(false);
      notifyLocalOwnership();
      notifyAlert();
      ringRedrawPending = true;
      drawLiveMetrics();
    }
  }

  if (localLatched) lastCommandAt = now;
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
  drawShell();
  recoverSafe();
  if (!kUseBleController) startEspNow();
  startBle();
  Serial.printf("!NODE:%s:READY\n", kNodeIds[PLEOS_PATH_INDEX]);
}

void loop() {
  readCommands();
  if (bleDisconnectPending) {
    bleDisconnectPending = false;
    recoverSafe();
  }
  if (pendingForceRelease) {
    pendingForceRelease = false;
    localLatched = false;
    lastCommandAt = millis();
    commandSource = "BLE";
    setIsolated(false);
    publishStatusValue();
    ringRedrawPending = true;
    drawLiveMetrics();
  }
  const int8_t bleCommand = pendingBleCommand;
  if (bleCommand >= 0) {
    // Latch the id before acting: a second !SET: landing in the BLE callback
    // would otherwise make us echo an id the controller no longer recognises.
    const uint32_t commandId = pendingBleCommandId;
    pendingBleCommand = -1;
    if (bleCommand == 2) {
      sendBleSnapshot("sync");
    } else {
      if (!localLatched) {
        lastCommandAt = millis();
        commandSource = "BLE";
        setIsolated(bleCommand == 1);
      } else {
        // The local operator owns the node. Refuse the command but still report
        // the real relay level, otherwise the controller never learns what this
        // node is doing and reissues the same command every 250 ms.
        notifyLocalOwnership();
      }
      notifyBle(String("!APPLIED:") + commandId + ":" + (isolated ? "HIGH" : "LOW"));
    }
    // The controller's write left its command in the value; restore the status.
    publishStatusValue();
  }
  if (!kUseBleController && espNowPending && !localLatched) {
    espNowPending = false;
    lastCommandAt = millis();
    commandSource = "NOW";
    setIsolated(espNowIsolated);
  }
  if (pollSeen) {
    pollSeen = false;
    lastCommandAt = millis();
  }
  pollButtons();
  if (bleSnapshotPending) {
    bleSnapshotPending = false;
    sendBleSnapshot("connected");
    // A client just attached: leave WAIT for SYNC immediately rather than
    // waiting for the first poll to land.
    ringRedrawPending = true;
    drawLiveMetrics();
  }
  // On the BLE transport the link itself is the fail-safe: losing the client
  // fires onDisconnect and recoverSafe(). A poll-age watchdog on top of that
  // could trip while the link is perfectly healthy, so it stays ESP-NOW only.
  if (!kUseBleController && millis() - lastCommandAt >= kCommandWatchdogMs) recoverSafe();
  if (!kUseBleController && millis() - lastAckAt >= kAckPeriodMs) {
    lastAckAt = millis();
    sendEspNowAck();
  }
  if (millis() - lastHeartbeatAt >= kHeartbeatMs) {
    lastHeartbeatAt = millis();
    Serial.printf("!NODE:%s:HEARTBEAT:%lu\n", kNodeIds[PLEOS_PATH_INDEX], ++sequence);
    // Re-state ownership and the real relay level once per second. The
    // controller adopts it only on change, so this costs nothing while it
    // agrees and repairs the state if a notification was dropped.
    notifyLocalOwnership();
  }
  if (millis() - lastUiAt >= kUiRefreshMs) {
    lastUiAt = millis();
    drawLiveMetrics();
  }
  delay(5);
}
