# PLEOS ESP32 Reconfiguration Hardware

| Module | Role | Physical actuation |
| --- | --- | --- |
| `controller` | 7-inch touch supervisor, BLE GATT and CBOR maintenance link | No |
| `inline_injector` | Flash ESP-AB, ESP-AR and ESP-BR between each switch pair | Locked by default |
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

Build three firmware variants with `AR`, `BR`, or `AB`. ESP-AB sits between the two front switches, ESP-AR between front A and rear R, and ESP-BR between front B and rear R. Each board ignores commands for the other two links.
