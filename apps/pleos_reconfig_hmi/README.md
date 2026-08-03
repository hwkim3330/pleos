# PLEOS Reconfig HMI

Operator surface for the zonal reconfiguration rig. Connects straight to the
7-inch ESP32 controller over BLE — the confirmed demo chain is tablet → 7-inch →
Path1/Path2, all BLE, with no host bridge anywhere in it — and drives the same
GATT contract as the studio app.

```bash
cd apps/pleos_reconfig_hmi
flutter pub get
flutter analyze
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.keti.pleos.hmi/com.keti.pleos.pleos_reconfig_hmi.MainActivity
```

Only one BLE client can own the controller at a time, so **force-stop the studio
app before starting this one** or it will sit on `OFFLINE`:

```bash
adb shell am force-stop com.keti.pleos.reconfig
```

## Why a third app

The two existing consoles answer "what does the architecture look like". Neither
answers "is the hardware actually there right now", which is the question that
matters when a link flaps: they show a single last-event string, so a node that
dropped and came back leaves no trace. Debugging the controller's lower link
meant reading framed CBOR off a serial cable because the tablet could not show
it.

So this app is built around live link state and an event timeline:

- **Status word** — NOMINAL / ISOLATED / OFFLINE, derived from the three
  Ethernet links, not from a scenario the operator picked.
- **Topology** — drawn to the channel contract: `tsn_front_a` is Front A to
  Rear, `tsn_front_b` is Front B to Rear, and `tsn_rear` is the cross-link
  *between the two front switches*. Healthy links carry a slow dash flow; an
  isolated link is drawn broken and marked, so it reads without relying on
  colour.
- **Timeline** — every gateway link change, node loss and return, command and
  command failure, timestamped. A controller self-heal shows up as a sequence
  rewind followed by both nodes coming back.
- **Node bar** — per-node ACK/LOST plus the real relay state, and the snapshot
  sequence number so a stalled stream is visible.

Design-wise it is a dark instrument layout rather than light cards: one accent
per state, labels small and wide, values large and tight, and a single panel
container reused everywhere so the screen reads as one system.

No WebView and no glTF viewer. The topology is a `CustomPainter`, which is
sharper on this screen than a model in a WebView and drops 7 MB of glb assets.
Debug APKs are ~145 MB either way — that is the unstripped multi-ABI Flutter
engine, not this app.

## Switch faults are three commands, not one

`!SCENARIO:` on this transport is the controller's *sensor* scenario space —
1 LiDAR FL loss, 2 dual sensor, 3 front TSN MRM, anything else recover-all. The
4..6 switch numbering belongs to the 7-inch's own touch actions and is not
reachable over BLE. `!SCENARIO:4` therefore quietly recovers everything instead
of isolating Front A.

So a switch fault is sent as three explicit `!CHANNEL:` writes covering all
three links, matching the firmware's `setSwitchFault`: Front A isolates paths 1
and 3, Front B isolates paths 2 and 3, Rear isolates paths 1 and 2. The third
link is set back to `NORMAL` rather than left alone, because `!CHANNEL:` is not
exclusive and the result would otherwise depend on the previous action.

## Verified on hardware

Against the three-board rig on 2026-08-03: gateway links and syncs, all three
links report NORMAL with both nodes ACK, `Path 2 link down` isolates node 2
alone, `Front A switch` isolates path 1 and path 3, `Front B switch` isolates
path 2 and path 3, and recover-all returns every relay to NC pass-through. The
Rear switch action is the one control not yet exercised on hardware.
