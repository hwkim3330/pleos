# NEMR BLE E-Ink ESL Tags — Integration Plan

Status: **planned, not started.** Nothing in the repo implements this yet.

Hardware on hand: 4x NEMR 2.9" BLE electronic-shelf-label tags, 296x128 px,
black/white/red (BWR) e-ink. Known BLE addresses:

```text
FF:FF:92:95:75:78
FF:FF:92:95:73:06
FF:FF:92:95:73:04
FF:FF:92:95:95:81
```

The `FF:FF:` prefix is a static-random-style address, typical of low-cost OEM
ESL modules.

## Do this first — half a day, before committing to anything

"BLE" on the product listing does not guarantee a connectable GATT peripheral.
Some retail ESLs are proprietary 2.4 GHz (base-station only), some are
NFC-programmed, and newer ones implement the Bluetooth SIG ESL Profile, which
uses Periodic Advertising with Responses — **neither an Android tablet nor an
ESP32 can act as a central for PAwR.** Any of those is a hard stop for this
design.

With nRF Connect on the tablet, confirm for each tag:

1. it advertises and is **connectable**,
2. it enumerates a **writable** characteristic,
3. whether it sleeps, and if so how long its wake window is.

If (1) or (2) fails, abandon this plan; the fallback is driving four bare e-ink
panels from a spare ESP32 over SPI, which changes the parts list, not just the
software. Item (3) sets the achievable refresh latency and must be reported as
measured rather than assumed.

## Who drives the tags

**The Android tablet.** Not the 7-inch controller.

The controller is ruled out on connection budget. It already holds three
concurrent ACL links — the GATT server link to the tablet plus two client links
to `PLEOS-PATH1`/`PLEOS-PATH2` — and runs a scan task. Bluedroid in the Arduino
core defaults to about four ACL connections, and `CONFIG_BT_ACL_CONNECTIONS`
cannot be raised without rebuilding the IDF libraries. Even with
connect/push/disconnect cycles, every tag update transiently takes the last free
slot, leaving no headroom for a path-node reconnect racing a half-open link —
precisely the failure `pollPathStatus()`'s stale-link recovery exists to escape.
A roughly 9.5 KB GATT transfer also takes seconds, and on the controller it
would sit in `loop()` next to LVGL, touch, and the 250 ms path polling. Finally,
the controller's BLE *client* is already the weakest stack in the rig: on esp32
core 3.3.0 it cannot even subscribe to notifications (see the README section on
polled node status). Hanging four more peripherals off it is the most likely way
to destabilise the part that must not be destabilised.

The tablet already receives the whole state stream through
`hardware_reconfig_service.dart`, `flutter_blue_plus` handles multiple centrals,
and this design never exceeds two concurrent links (controller + one tag being
pushed). Firmware changes: none. Risk to the embedded system: none.

The cost is that tags only update while the tablet app runs. That is acceptable:
the confirmed demo path always includes the tablet, the rig still works on power
alone, and the on-image timestamp below makes a frozen tag self-evident.

A dedicated fourth ESP32 as an "ESL gateway" is a possible later phase if
tag updates are ever needed with the tablet off. It is not free: feeding it
state means either a second central on the controller's GATT server (which
today assumes a single `bleConnected` client) or re-enabling the controller's
ESP-NOW broadcast alongside BLE, and BLE/Wi-Fi coexistence has never been
validated on this rig. Defer until Phase 1 works.

## Connection lifecycle

Tags are connect -> push image -> refresh -> disconnect. Never hold a link.

- One tag at a time, strictly sequential, from a round-robin queue in a new
  `EslService` isolated from `HardwareReconfigService`.
- Trigger on state change from the existing state stream, debounced 3–5 s so a
  scenario button (9 `!CHANNEL:` lines plus `!EVENT:`) coalesces into one push.
  Only push a tag whose rendered framebuffer actually changed — hash it.
- Minimum 30 s per tag. A BWR panel needs roughly 8–15 s for a full refresh plus
  2–5 s of transfer; the floor protects panel life and stops queue pileup during
  rapid fault/recover demos. A tag always converges to the newest state and
  skips intermediates.
- Heartbeat refresh every 10 minutes so the timestamp stays honest.
- Pause the queue whenever the controller link is down. Reconnecting to the
  supervisor always outranks updating signage.
- Connect by known MAC; no scanning in steady state. Never scan while the
  controller link is being re-established.

## What each tag shows

| Tag | Placement | Content |
| --- | --- | --- |
| 1 | Path 1 relay module | `PATH 1` / `tsn_front_a`, `FRONT A <-> REAR`, large state word |
| 2 | Path 2 relay module | `PATH 2` / `tsn_front_b`, `FRONT B <-> REAR`, large state word |
| 3 | Path 3 relay (controller GPIO6) | `PATH 3` / `tsn_rear`, `FRONT A <-> FRONT B`, large state word, marked `LOCAL` |
| 4 | Rig front | Summary: Autoware mode, `n/3 LINKS ACTIVE`, sensor faults, last event |

Layout rules for 296x128 BWR:

- **Red is the alarm plane** — that is the reason for buying BWR. `NORMAL` is
  black on white; `FAULT`/`ISOLATED` is white on a red block; `DEGRADED` is
  black text in a red outline. Tag 4 renders `MRM` as a full red banner.
- **Every image carries `UPDATED HH:MM` and a push counter.** E-ink retains its
  last image indefinitely without power, so an un-refreshed tag is otherwise
  indistinguishable from a live one, and a retained `FAULT` would alarm visitors
  an hour after recovery. The timestamp is the only defence.
- Keep static per-tag identity (path name, endpoints) so even a stale tag
  remains useful signage.

## Image pipeline

1. Draw at exactly 296x128 with `dart:ui` `PictureRecorder`/`Canvas`, using only
   pure black, white and red; avoid anti-aliased edges on state blocks.
2. Convert to RGBA bytes and quantise each pixel to nearest of the three
   colours. No dithering — the content is flat UI graphics.
3. Pack two 1-bpp planes, black/white and red. 296x128 = 37,888 px, so **4,736
   bytes per plane, 9,472 bytes total.**
4. Chunk to the negotiated MTU, write to the tag's upload characteristic, send
   its refresh command, disconnect.

### Unknown — do not implement against guesses

The NEMR GATT service and characteristic UUIDs, the upload framing (init
command, chunk sequencing, CRC, compression, end-of-transfer/refresh trigger),
any authentication, plane order, bit polarity and scan direction are **not
documented in this repo and were not found publicly.** Do not invent them.

Discovery order, by expected yield:

1. Enumerate GATT with nRF Connect.
2. Push an image with the vendor's Android app while Android HCI snoop logging
   is on, then read the byte protocol out of the btsnoop capture in Wireshark.
   This alone usually yields a working replay.
3. Decompile the vendor APK (jadx) and search for UUID strings and framing code.
4. Compare against existing reverse-engineering work. A 296x128 BWR BLE price
   tag with a static-random address resembles the Gicisky family documented by
   atc1441 (`ATC_GICISKY_ESL`) and supported by OpenEPaperLink tooling. **This
   is an unverified lead, not a fact** — check the enumerated GATT against those
   projects before borrowing any of their protocol.

## Failure modes

| Failure | Behaviour | Handling |
| --- | --- | --- |
| Tag unreachable | Push times out | 10 s connect timeout, 3 retries with backoff, then park 60 s. Tag keeps its last image; the footer timestamp exposes the staleness, and the app shows a per-tag last-success row. |
| Partial transfer | Protocol dependent — the tag may keep the old image or show garbage. **Unknown until reverse-engineered; test deliberately.** | Always retry a failed push before parking. |
| Tablet app killed | All tags freeze | Accepted in Phase 1. Timestamps make it evident; the core demo is unaffected. |
| Controller link down | Queue paused | Tags hold last-known state; queue resumes and re-renders on reconnect. |
| Faults faster than 30 s/tag | Intermediates skipped | Tags are signage, not instrumentation. The 7-inch and tablet remain the real-time surfaces. |
| Any ESL bug | Must never block fault injection | Hard isolation: separate service, every await time-boxed, no shared state beyond subscribing to the state stream. |

## Effort and risk

| Item | Estimate |
| --- | --- |
| Bench verification (connectable, GATT map, sleep behaviour) | 0.5 day |
| Protocol reverse engineering | 1–3 days if it matches a known family, 3–5 if novel |
| Flutter `EslService`: queue, lifecycle, retries, status row | 2–3 days |
| Renderer and BWR layouts for 4 tags | 1 day |
| Integration and soak against live fault/recover demos | 1–2 days |
| **Phase 1 total (tablet-driven)** | **~1.5–2 weeks**, dominated by RE uncertainty |
| Optional gateway phase | +3–5 days |

Risks, ranked:

1. **Protocol dead end** — cloud-locked, base-station-only, or SIG-ESL/PAwR
   tags. Low-to-moderate probability, total impact, resolved in the first half
   day.
2. **Sleep windows** stretching refresh latency to tens of seconds or minutes,
   which weakens the "fault appears on the shelf label" moment.
3. **RE overrunning** the estimate on auth or checksum quirks.
4. **Android BLE flakiness** interleaving controller notifications with bulk tag
   writes. Low impact given sequential pushes, but soak-test with the real demo
   choreography.
5. Red-plane ghosting and slow cold refresh. Indoors; accept.

The deliberate stance: the ESL layer is one-way, additive and disposable.
Nothing in the existing controller/path-node/tablet triangle changes in Phase 1.
That is the only honest way to satisfy "must not destabilise" while the tag
protocol is still unknown.
