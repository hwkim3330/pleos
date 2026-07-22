# Fault Injection Module Wiring

This wiring applies to each 1.14-inch PLEOS Path node and one normally-closed
Fault Injection Module. Path1 controls `tsn_front_a`; Path2 controls
`tsn_front_b`.

## Control contract

| Signal | Level | Relay/LED state | Ethernet state |
| --- | --- | --- | --- |
| `RELAY_EN` | LOW (0 V) | Relay off, green on, red off | NC pass-through / normal |
| `RELAY_EN` | HIGH (3.3 V) | Relay on, green off, red on | Pair open / injected fault |

The supplied PCB file (`260714_KETI_Fault_Injection_Module.zip`, reviewed
2026-07-22) assigns the control header as follows:

| J3 pad | PCB net | Connect to |
| --- | --- | --- |
| `J3.1` (rectangular pad) | `+5V` | Regulated 5 V module supply |
| `J3.2` | `GND` | Supply and ESP32 common ground |
| `J3.3` | `/RELAY_EN` | ESP32 `GPIO27` |

Use the rectangular copper pad, pad number, or continuity measurement to find
pin 1. Do not infer pin order from which side of the assembled board is being
viewed.

### KiCad synchronization defect

The ZIP's `.kicad_sch` and `.kicad_pcb` are inconsistent at J3. The PCB pad
nets are `1=+5V, 2=GND, 3=RELAY_EN`, while the rotated schematic connector is
wired as `1=RELAY_EN, 2=GND, 3=+5V`. The work-item description matches the
PCB, not the schematic.

Before fabrication, correct the schematic connector orientation/wiring to
match the intended PCB mapping, run ERC, update the PCB from the schematic,
and verify that the three PCB pad nets remain exactly as shown above. Do not
run an automatic schematic-to-PCB update on the current files without first
fixing this mismatch.

## ESP32 connection

| T-Display 1.14-inch pin | Fault module | Purpose |
| --- | --- | --- |
| `GPIO27` | `J3.3 / RELAY_EN` | 3.3 V active-high fault command |
| `GND` | `J3.2 / GND` | Common logic reference |
| Regulated `5V` supply | `J3.1 / +5V` | Relay and indicator power |

Do not power the relay coil from a GPIO pin. Prefer one regulated 5 V supply
for the ESP32 and module, with a common ground. Confirm the module input is a
3.3 V logic input before connection. Fit a 10 kohm pull-down from `RELAY_EN`
to GND at the module connector so reset, flashing, unplugging, and an
unpowered ESP32 all select normal pass-through.

GPIO27 is intentionally used because it is exposed on the supported T-Display
board, is not used by its ST7789 display, and is not an ESP32 boot-strapping
pin. The firmware drives it LOW before serial, display, or BLE startup.

## Ethernet side

For the RJ45 version, the current design opens both conductors of one data
pair through the relay's NC contacts. Pair A (RJ45 pins 1 and 2) is the
preferred injected pair described by the board design. Verify continuity with
a meter against the final PCB before attaching network equipment.

The 100/1000BASE-T1 variant is a separate one-pair automotive Ethernet design.
Its connector, impedance-controlled routing, relay/contact suitability, and
signal integrity must be validated for 100/1000BASE-T1; the RJ45 pin guidance
does not apply to it.

Never connect an ESP32 pin, LED, or probe ground to an Ethernet differential
pair. The ESP32 connects only to the isolated module control header.

## Bench commissioning

1. Leave both Ethernet ports disconnected and confirm `J3.1=+5V`,
   `J3.2=GND`, and `J3.3=RELAY_EN` on the corrected final schematic and PCB.
2. Power the module from a current-limited 5 V bench supply. Leave
   `RELAY_EN` at LOW and verify green on, red off, and Pair A continuity.
3. Connect ESP32 GND and GPIO27. Issue an isolate command and verify 3.3 V at
   J3.3, relay operation, red on, green off, and Pair A open circuit.
4. Stop the controller or BLE bridge. Within five seconds the firmware must
   return GPIO27 LOW and restore continuity.
5. Reset and power-cycle each ESP32. The module must remain in or return to
   NC pass-through before testing on an isolated Ethernet bench network.

## Commands

The Mac BLE bridge normally refreshes commands every second. For a serial
bench test at 115200 baud:

```text
!CHANNEL:tsn_front_a:ISOLATED
!CHANNEL:tsn_front_a:NORMAL
!RECOVER
```

Use `tsn_front_b` for the Path2 firmware. A fault is never restored from
flash after reboot. A command timeout, reset, or `!RECOVER` always selects
normal pass-through.
