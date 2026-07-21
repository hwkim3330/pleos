# PLEOS ESP32 Reconfiguration Hardware

| Module | Role | Physical actuation |
| --- | --- | --- |
| `controller` | 7-inch touch supervisor, mode derivation and CBOR host link | No |
| `inline_injector` | Flash ESP-AB, ESP-AR and ESP-BR between each switch pair | Locked by default |
| `io_node` | Expandable sensor switch inputs and relay outputs | Locked by default |
| `bridge` | macOS serial-CBOR to WebSocket gateway | No |

```text
PLEOS Reconfig Studio
  <-> WebSocket <-> Mac bridge <-> framed CBOR <-> 7-inch supervisor
  <-> USB hub/CDC <-> ESP-AB/AR/BR <-> three normally-closed relay PCBs
```

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
