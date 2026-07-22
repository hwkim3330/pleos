# PLEOS ESP32 Reconfiguration Hardware

| Module | Role | Physical actuation |
| --- | --- | --- |
| `controller` | 7-inch touch supervisor, BLE GATT and CBOR maintenance link | No |
| `inline_injector` | Flash ESP-AB, ESP-AR and ESP-BR between each switch pair | Locked by default |
| `io_node` | Expandable sensor switch inputs and relay outputs | Locked by default |
| `bridge` | macOS serial-CBOR to WebSocket gateway | No |

```text
PLEOS Reconfig Studio <-> BLE GATT <-> 7-inch supervisor
  (maintenance fallback: WebSocket <-> Mac bridge <-> framed CBOR)
  <-> USB hub/CDC <-> ESP-AB/AR/BR <-> three normally-closed relay PCBs
```

## BLE link

The controller advertises as `PLEOS-RECONFIG` after every boot. The Android app scans and reconnects automatically; when BLE is unavailable (including most automotive emulators), it keeps using the macOS WebSocket bridge.

| GATT item | UUID |
| --- | --- |
| Service | `7d2f0001-7c7a-4f7b-9b51-0af9a281d110` |
| Notify/write control | `7d2f0002-7c7a-4f7b-9b51-0af9a281d110` |

Commands are UTF-8 `!RECOVER`, `!SCENARIO:n`, or `!CHANNEL:id:health`. Notifications are short `!STATE`, `!CHANNEL`, and `!EVENT` records so they remain below the negotiated BLE MTU.

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

Build three firmware variants with `AR`, `BR`, or `AB`. ESP-AB sits between the two front switches, ESP-AR between front A and rear R, and ESP-BR between front B and rear R. Each board ignores commands for the other two links.
