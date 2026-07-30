# PLEOS ESP32 Reconfiguration Hardware

| Module | Role | Physical actuation |
| --- | --- | --- |
| `controller` | 7-inch touch supervisor, BLE GATT and CBOR maintenance link | No |
| `inline_injector` | Flash ESP-AB, ESP-AR and ESP-BR between each switch pair | Locked by default |
| `path_display_node` | 1.14-inch Path1/Path2 display, BLE watchdog and GPIO27 relay control | Enabled, active-high |
| `io_node` | Expandable sensor switch inputs and relay outputs | Locked by default |
| `bridge` | macOS serial-CBOR to WebSocket gateway | No |

```text
PLEOS Reconfig Studio <-> WebSocket <-> Mac BLE bridge
  <-> BLE GATT <-> 7-inch supervisor
  <-> ESP-NOW channel 6 <-> Path1 / Path2 relay nodes
  (maintenance fallback: Mac bridge <-> USB framed CBOR)
  <-> USB hub/CDC <-> ESP-AB/AR/BR <-> three normally-closed relay PCBs
```

## BLE link

The controller advertises as `PLEOS-RECONFIG` after every boot. The Mac bridge scans and reconnects automatically, then exposes the existing `ws://10.0.2.2:8766` endpoint to PLEOS Connect. This is the default because the automotive emulator does not reliably own the Mac Bluetooth adapter. Direct Android BLE remains available in the app service as an opt-in path for a standalone physical tablet.

Start the normal PLEOS Connect path from the repository root:

```bash
./hardware/esp32_reconfig/bridge/run.sh
```

Use USB CBOR only for maintenance:

```bash
./hardware/esp32_reconfig/bridge/run.sh \
  --transport serial --serial /dev/cu.usbmodem59580282341
```

### Confirmed demo path

The confirmed configuration is **three ESP32 boards** — the 7-inch supervisor
plus the Path1 and Path2 display nodes — driven by a physical Android tablet
that connects **straight to the 7-inch controller over BLE, with no bridge
running**. `pleos_reconfig_studio` ships with `directBle: true`, so the tablet
owns the GATT link itself. The bridge below is for observation and maintenance,
not for the demo.

Path 3 (`tsn_rear`) has no display node in this configuration: the 7-inch board
drives that relay from its own `GPIO6`, which is why its card is labelled
`LOCAL`. The `PLEOS_PATH_INDEX=2` (`PATH3`) build of `path_display_node` is kept
as a future option and is currently unused.

### Linux host

A Linux host without a Bluetooth adapter cannot run `--transport ble` at all.
The USB framed-CBOR serial transport is the only option there, and it is
bidirectional — state comes back as CBOR and commands are written to the same
UART:

```bash
./hardware/esp32_reconfig/bridge/run.sh --transport serial --serial /dev/ttyUSB0
```

`find_port` matches `/dev/ttyACM*` and `/dev/ttyUSB*` as well as the macOS
`usbmodem`/`usbserial` names, prefers the Espressif/CH34x/CP210x/FTDI vendor
IDs, and prints the port it picked with its `VID:PID`. **If more than one
candidate is present it refuses to guess and asks for `--serial`** — on the KETI
Linux box the LAN9662 VelocityDRIVE board also owns a `/dev/ttyACM*`, and
opening that instead would point a CBOR reader at a MUP1 device.

If opening the port fails with a permission error, add yourself to the
`dialout` group and log back in:

```bash
sudo usermod -aG dialout $USER
```

Note that `ws://10.0.2.2:8766` is an Android emulator alias for the host. A
physical tablet cannot reach it, and needs the host's LAN address instead — but
for the confirmed demo path above the tablet does not use the bridge at all.

| GATT item | UUID |
| --- | --- |
| Service | `7d2f0001-7c7a-4f7b-9b51-0af9a281d110` |
| Notify/write control | `7d2f0002-7c7a-4f7b-9b51-0af9a281d110` |

Commands are UTF-8 `!SYNC`, `!RECOVER`, `!SCENARIO:n`, `!PATH:n`, or
`!CHANNEL:id:health`. The app sends `!SYNC` after subscribing so a reconnect
always receives a complete snapshot, and re-sends it whenever the `!STATE:`
sequence jumps or rewinds, so a dropped notification cannot leave the tablet
holding a stale channel map. Notifications are short `!STATE`, `!CHANNEL`,
`!PATHNODE` and `!EVENT` records so they remain below the negotiated BLE MTU.

Path node liveness reaches the app only through the controller's `!PATHNODE:`
record. It must not be inferred from BLE advertising: a path node stops
advertising once the controller connects to it, so a scan reports the healthy,
actively-controlled case as offline.

The inline boards always boot into normally-closed bypass. Fault state is
deliberately not restored from flash after reboot.

In the BLE path transport used by the current demo, the controller writes a
path command only when the node's reported level differs from the intended one,
rate limited to one write per 250 ms, and the node answers `!APPLIED:` with its
real relay level. The fail-safe on this transport is the BLE link itself:
`onDisconnect` returns `GPIO27` to LOW immediately. The 10-second
`kCommandWatchdogMs` timeout is a property of the ESP-NOW transport
(`kUseBleController = false`) and is not what protects the BLE path.

The ESP32 must never be wired directly into an automotive Ethernet differential pair. The inline injector controls a purpose-built isolated relay or Ethernet-switch test PCB. Loss of power, watchdog timeout, USB disconnect and firmware reset must all return the PCB to its normally-closed pass-through state.

## Channel contract

| Channel | Physical meaning |
| --- | --- |
| `tsn_front_a` | ESP-AR link between front A and rear R |
| `tsn_front_b` | ESP-BR link between front B and rear R |
| `tsn_rear` | ESP-AB cross-link between the two front switches |
| `lidar_fl`, `lidar_fr`, `lidar_rl`, `lidar_rr` | Four independent LiDAR availability inputs |
| `gnss` | GNSS availability/quality input |
| `camera` | Front camera availability input |

The generic `inline_injector` and `io_node` outputs remain disabled until their
board-specific pin maps are verified. The two Path display nodes implement the
confirmed active-high `J3.3 / RELAY_EN` contract on GPIO27; commission them on
a disconnected bench harness before attaching Ethernet equipment.

The Path1/Path2 fault-module wiring, fail-safe behavior, and commissioning
procedure are documented in [FAULT_INJECTION_WIRING.md](FAULT_INJECTION_WIRING.md).

## ESP-NOW backup link

The 7-inch controller broadcasts a compact Path1/Path2 state frame every
250 ms on Wi-Fi channel 6. Each frame contains a protocol magic value,
sequence number, two isolation bits, and CRC-16. Each Path node returns a
CRC-protected acknowledgement once per second with its role and applied relay
state. The controller shows `P1 ACK` or `P2 ACK` only while that acknowledgement
is fresh; BLE advertising alone is not treated as proof of control. Path nodes accept either BLE
or ESP-NOW; the newest valid command wins. If neither path refreshes within
`kCommandWatchdogMs` (10 seconds), GPIO27 returns LOW and restores NC
pass-through. This watchdog applies to the ESP-NOW transport only.

ESP-NOW is a direct safety/demo fallback, not the application data plane. BLE
continues to carry app state and events through the Mac bridge. A local button
latch is not time limited: it holds until the lower button releases it or the
controller link drops, and the controller stops commanding a latched node
instead of fighting it. Path firmware uses the `huge_app` partition because
concurrent BLE, Wi-Fi/ESP-NOW, and display libraries exceed the default 1.3 MB
app partition.

## 1.14-inch Path displays

The classic ESP32/ST7789 nodes are non-touch status displays. Flash the first board as Path1 and the second as Path2:

```bash
./hardware/esp32_reconfig/path_display_node/build_and_flash.sh \
  /dev/cu.usbserial-XXXXXXXX PATH1

./hardware/esp32_reconfig/path_display_node/build_and_flash.sh \
  /dev/cu.usbserial-XXXXXXXX PATH2
```

Path1 listens to `tsn_front_a`; Path2 listens to `tsn_front_b`. Both boot in NC bypass and show `WAITING` until their first controller command. A circular heartbeat shows command age and uses the current state color without full-screen redraw. `SOURCE` identifies `BLE`, `LATCH` (local button holds the node), `LOCAL` (local release), `NOW`, or fail-safe `SAFE` control.

Both user controls are on the display's left edge and are **latching taps**; no
hold is required.

| Button | Action |
| --- | --- |
| Upper (`GPIO0`) | Tap to toggle the relay and take local ownership of the node |
| Lower (`GPIO35`) | Tap to return to pass-through and release ownership to the network |

A latched node reports `!LOCAL:<owned>:<level>` to the 7-inch controller, which
adopts that level into its channel state. The 7-inch card, the Autoware mode and
the tablet therefore follow the real relay instead of disagreeing with it, and
the 7-inch link line shows `LCL` for a locally owned path. While a node is
latched the controller stops commanding it, and the node still answers
`!APPLIED:` with its true level so the controller never spins reissuing a
refused command. Tapping the lower button hands control straight back — the next
controller command applies without waiting for a timer.

Fail-safe outranks the latch: losing the BLE link to the controller clears local
ownership and returns `GPIO27` to LOW.

The separate reset control remains reset. BLE callbacks only queue state
changes; all relay and LCD updates run in the main loop so button input cannot
race the display renderer.

> `GPIO35` is input-only and has no internal pull-up on the ESP32, so it relies
> on the T-Display's external pull-up. If the safe button ever appears to fire
> on its own, measure that pull-up before suspecting the firmware.

Each Path node drives its Fault Injection Module from `GPIO27` to
`J3.3 / RELAY_EN`: LOW is normal NC pass-through and HIGH is an injected
fault. Add an external 10 kohm pull-down at `RELAY_EN` so the hardware also
defaults to pass-through while the ESP32 is resetting or disconnected.

Both nodes advertise BLE independently:

| Node | BLE name | Channel |
| --- | --- | --- |
| Path1 | `PLEOS-PATH1` | `tsn_front_a` |
| Path2 | `PLEOS-PATH2` | `tsn_front_b` |

The 7-inch screen is the only normal operator surface. It provides six fault
actions (three individual links and three switches), a separate full recovery
action, and a live circular ESP-NOW heartbeat. A switch fault isolates both
links physically incident to that switch: Front A = Paths 1+3, Front B = Paths
2+3, and Rear = Paths 1+2.

The Mac bridge connects `PLEOS-RECONFIG`, `PLEOS-PATH1`, and `PLEOS-PATH2` concurrently. It refreshes each path command once per second and reports both node connections to the PLEOS app under `path_nodes`.

Build three firmware variants with `AR`, `BR`, or `AB`. ESP-AB sits between the two front switches, ESP-AR between front A and rear R, and ESP-BR between front B and rear R. Each board ignores commands for the other two links.
