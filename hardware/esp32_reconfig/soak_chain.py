#!/usr/bin/env python3
"""Bounded soak over the whole four-device chain: tablet -> 7-inch -> Path1 + Path2.

Every check is made from the controller's framed-CBOR stream, because that is the only
place where all four devices show up at once:

  * a `path_fault` event proves the *tablet's* BLE write arrived at the 7-inch
  * `path_nodes[n].applied` proves the 7-inch reached that node and the node moved its relay
  * `connected` proves the 7-inch still owns both node links

So one stream verifies the operator surface, the gateway and both nodes without trusting
any of them to report on themselves.

Each cycle: inject Path 1 from the tablet, inject Path 2, recover, then knock a node over
and wait for the rig to heal itself. Prints PASS/FAIL per step and a summary.

    python3 soak4.py [cycles]
"""
import subprocess
import sys
import time

import cbor2
import serial

CONTROLLER = "/dev/ttyACM3"
TABLET = "R54T202T7PY"
NODE_PORTS = {"PATH_1": "/dev/ttyACM2", "PATH_2": "/dev/ttyACM1"}
RESET = "/tmp/claude-1000/-home-kim/5ec866c8-9903-41f9-8409-38636c45661e/scratchpad/esp_reset.py"
MAGIC = b"\xa5\x5a"

# Studio's scenario rail, in real device pixels.
TAP = {
    "normal": (262, 384),
    "path1": (262, 509),
    "path2": (262, 634),
}

CYCLES = int(sys.argv[1]) if len(sys.argv) > 1 else 3
COMMAND_DEADLINE = 12.0   # tablet tap -> relay moved
RECOVER_DEADLINE = 12.0
HEAL_DEADLINE = 90.0      # node knocked over -> both links back
SETTLE = 6.0


def crc16(data: bytes) -> int:
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


class Controller:
    def __init__(self, port):
        self.ser = serial.Serial(port, 115200, timeout=0.1)
        self.buf = bytearray()

    def frames(self):
        if self.ser.in_waiting:
            self.buf.extend(self.ser.read(self.ser.in_waiting))
        while True:
            marker = self.buf.find(MAGIC)
            if marker < 0:
                del self.buf[:-1]
                return
            if marker:
                del self.buf[:marker]
                continue
            if len(self.buf) < 6:
                return
            size = int.from_bytes(self.buf[2:4], "big")
            total = 4 + size + 2
            if size > 4096:
                del self.buf[:2]
                continue
            if len(self.buf) < total:
                return
            payload = bytes(self.buf[4 : 4 + size])
            expected = int.from_bytes(self.buf[4 + size : total], "big")
            del self.buf[:total]
            if crc16(payload) == expected:
                yield cbor2.loads(payload)

    def wait(self, predicate, deadline):
        """Returns (elapsed, events_seen) or (None, events_seen) on timeout."""
        start = time.time()
        events = []
        while time.time() - start < deadline:
            for state in self.frames():
                event = state.get("event")
                if event not in ("heartbeat", None):
                    events.append(event)
                if predicate(state):
                    return time.time() - start, events
            time.sleep(0.05)
        return None, events

    def drain(self):
        for _ in self.frames():
            pass


def applied(state, node):
    return (state.get("path_nodes", {}).get(node) or {}).get("applied")


def connected(state, node):
    return (state.get("path_nodes", {}).get(node) or {}).get("connected")


def isolated_only(node):
    """Exactly that node's relay open, the other closed -- the whole point of the demo."""
    other = "2" if node == "1" else "1"
    return lambda s: applied(s, node) == 1 and applied(s, other) == 0


def both_closed(state):
    return applied(state, "1") == 0 and applied(state, "2") == 0


def both_up(state):
    nodes = state.get("path_nodes", {})
    return len(nodes) == 2 and all(n.get("connected") for n in nodes.values())


def tap(name):
    x, y = TAP[name]
    subprocess.run(
        ["adb", "-s", TABLET, "shell", "input", "tap", str(x), str(y)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def main():
    controller = Controller(CONTROLLER)
    print(f"soak: {CYCLES} cycles over tablet + 7-inch + Path1 + Path2", flush=True)
    controller.drain()
    elapsed, _ = controller.wait(lambda s: both_up(s) and both_closed(s), 60)
    if elapsed is None:
        print("FAIL precondition: the rig is not idle with both nodes up", flush=True)
        return 1
    print(f"precondition ok ({elapsed:.1f}s)", flush=True)

    failures = []
    for cycle in range(1, CYCLES + 1):
        role = "PATH_1" if cycle % 2 else "PATH_2"
        print(f"\n=== cycle {cycle}/{CYCLES}", flush=True)

        for label, target, node in (
            ("Path 1 from tablet", "path1", "1"),
            ("Path 2 from tablet", "path2", "2"),
        ):
            controller.drain()
            tap(target)
            took, events = controller.wait(isolated_only(node), COMMAND_DEADLINE)
            if took is None:
                failures.append(f"cycle {cycle}: {label} did not reach the relay")
                print(f"  FAIL {label}: no relay change in {COMMAND_DEADLINE:.0f}s "
                      f"(events {events})", flush=True)
            else:
                print(f"  PASS {label}: node {node} isolated alone in {took:.1f}s", flush=True)

        controller.drain()
        tap("normal")
        took, events = controller.wait(both_closed, RECOVER_DEADLINE)
        if took is None:
            failures.append(f"cycle {cycle}: recover-all did not close both relays")
            print(f"  FAIL recover: relays not closed in {RECOVER_DEADLINE:.0f}s", flush=True)
        else:
            print(f"  PASS recover: both relays closed in {took:.1f}s", flush=True)

        # Now break it: reset a node and see whether the chain heals without a human.
        port = NODE_PORTS[role]
        print(f"  -- knocking over {role} ({port})", flush=True)
        controller.drain()
        subprocess.run(["timeout", "10", "python3", RESET, port, "2"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        dropped, _ = controller.wait(lambda s: not both_up(s), 30)
        if dropped is None:
            print("  note: the node never reported down; reset did not take", flush=True)
        else:
            healed, events = controller.wait(both_up, HEAL_DEADLINE)
            if healed is None:
                failures.append(f"cycle {cycle}: chain did not heal after {role} reset")
                print(f"  FAIL heal: both links not back in {HEAL_DEADLINE:.0f}s "
                      f"(events {events})", flush=True)
            else:
                relinked = "ble_connected" in events
                print(f"  PASS heal: both links back in {healed:.1f}s"
                      f"{', tablet relinked' if relinked else ''} (events {events})",
                      flush=True)
        time.sleep(SETTLE)

    print(f"\nsoak done: {len(failures)} failures", flush=True)
    for line in failures:
        print(f"  - {line}", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
