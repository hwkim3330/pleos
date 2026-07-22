# PLEOS ESP32 Reconfiguration Hardware

| Module | Role | Physical actuation |
| --- | --- | --- |
| `controller` | 7-inch touch supervisor, BLE GATT and CBOR maintenance link | No |
| `inline_injector` | Flash ESP-AB, ESP-AR and ESP-BR between each switch pair | Locked by default |
| `path_display_node` | 1.14-inch non-touch Path1/Path2 status and inline watchdog node | Locked by default |
| `io_node` | Expandable sensor switch inputs and relay outputs | Locked by default |
| `bridge` | macOS serial-CBOR to WebSocket gateway | No |

```text
PLEOS Reconfig Studio <-> WebSocket <-> Mac BLE bridge
  <-> BLE GATT <-> 7-inch supervisor
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

| GATT item | UUID |
| --- | --- |
| Service | `7d2f0001-7c7a-4f7b-9b51-0af9a281d110` |
| Notify/write control | `7d2f0002-7c7a-4f7b-9b51-0af9a281d110` |

Commands are UTF-8 `!SYNC`, `!RECOVER`, `!SCENARIO:n`, or `!CHANNEL:id:health`. The app sends `!SYNC` after subscribing so a reconnect always receives a complete snapshot. Notifications are short `!STATE`, `!CHANNEL`, and `!EVENT` records so they remain below the negotiated BLE MTU.

The inline boards always boot into normally-closed bypass. An isolated relay is held only while the controller refreshes its command every second; loss of USB/controller communication triggers local recovery after five seconds. Fault state is deliberately not restored from flash after reboot.

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

Physical outputs remain disabled until the board schematic and active levels are entered in the firmware and verified on a disconnected bench harness.

## 1.14-inch Path displays

The classic ESP32/ST7789 nodes are non-touch status displays. Flash the first board as Path1 and the second as Path2:

```bash
./hardware/esp32_reconfig/path_display_node/build_and_flash.sh \
  /dev/cu.usbserial-XXXXXXXX PATH1

./hardware/esp32_reconfig/path_display_node/build_and_flash.sh \
  /dev/cu.usbserial-XXXXXXXX PATH2
```

Path1 listens to `tsn_front_a`; Path2 listens to `tsn_front_b`. Both boot in NC bypass, show `WAITING` until their first controller command, and return to `NORMAL` if command refresh stops for five seconds.

Both nodes advertise BLE independently:

| Node | BLE name | Channel |
| --- | --- | --- |
| Path1 | `PLEOS-PATH1` | `tsn_front_a` |
| Path2 | `PLEOS-PATH2` | `tsn_front_b` |

The Mac bridge connects `PLEOS-RECONFIG`, `PLEOS-PATH1`, and `PLEOS-PATH2` concurrently. It refreshes each path command once per second and reports both node connections to the PLEOS app under `path_nodes`.

Build three firmware variants with `AR`, `BR`, or `AB`. ESP-AB sits between the two front switches, ESP-AR between front A and rear R, and ESP-BR between front B and rear R. Each board ignores commands for the other two links.
