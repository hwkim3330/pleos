#!/usr/bin/env python3
"""Bridge the ESP controller to PLEOS Connect WebSocket clients."""

import argparse
import asyncio
import json

import cbor2
import serial
from bleak import BleakClient, BleakScanner
from serial.tools import list_ports
import websockets

MAGIC = b"\xa5\x5a"
BLE_SERVICE = "7d2f0001-7c7a-4f7b-9b51-0af9a281d110"
BLE_CONTROL = "7d2f0002-7c7a-4f7b-9b51-0af9a281d110"
PATH_SERVICE = "7d2f0011-7c7a-4f7b-9b51-0af9a281d110"
PATH_CONTROL = "7d2f0012-7c7a-4f7b-9b51-0af9a281d110"
PATH_NODES = {"PLEOS-PATH1": "tsn_front_a", "PLEOS-PATH2": "tsn_front_b"}
CHANNEL_COUNT = 9


def crc16(data: bytes) -> int:
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def find_port(requested: str | None) -> str:
    if requested:
        return requested
    candidates = [
        port.device
        for port in list_ports.comports()
        if "usbmodem" in port.device or "wch" in port.description.lower()
    ]
    if not candidates:
        raise RuntimeError("ESP serial port not found. Pass --serial /dev/cu.usbmodem...")
    return candidates[0]


def wire_command(command: dict) -> str:
    if command.get("command") == "scenario":
        return f"!SCENARIO:{command['id']}"
    if command.get("command") == "channel":
        return f"!CHANNEL:{command['id']}:{command['health']}"
    if command.get("command") == "recover":
        return "!RECOVER"
    raise ValueError("unknown_command")


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--transport", choices=("ble", "serial"), default="ble")
    parser.add_argument("--ble-name", default="PLEOS-RECONFIG")
    parser.add_argument("--serial")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8766)
    args = parser.parse_args()

    clients: set = set()
    commands: asyncio.Queue[str] = asyncio.Queue()
    latest = {
        "v": 1,
        "seq": 0,
        "board": "ws-esp32s3-touch-lcd-7",
        "event": "waiting_for_controller",
        "mode": "OFFLINE",
        "io_node_connected": False,
        "channels": {},
        "path_nodes": {},
    }

    async def broadcast() -> None:
        encoded = json.dumps(latest, separators=(",", ":"))
        stale = []
        for socket in list(clients):
            try:
                await socket.send(encoded)
            except websockets.ConnectionClosed:
                stale.append(socket)
        for socket in stale:
            clients.discard(socket)

    async def handler(socket):
        clients.add(socket)
        print(f"[bridge] app connected ({len(clients)})")
        if latest["seq"]:
            await socket.send(json.dumps(latest, separators=(",", ":")))
        try:
            async for raw in socket:
                try:
                    command = json.loads(raw)
                    await commands.put(wire_command(command))
                    print(f"[app] {command}")
                except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
                    await socket.send(json.dumps({"error": str(error)}))
        except websockets.ConnectionClosed:
            pass
        finally:
            clients.discard(socket)
            print(f"[bridge] app disconnected ({len(clients)})")

    async def run_controller_ble() -> None:
        while True:
            try:
                print(f"[ble] scanning for {args.ble_name}")
                device = await BleakScanner.find_device_by_name(args.ble_name, timeout=8)
                if device is None:
                    await asyncio.sleep(2)
                    continue
                async with BleakClient(device) as client:
                    print(f"[ble] connected: {args.ble_name}")

                    async def on_notify(_, payload: bytearray) -> None:
                        line = payload.decode(errors="replace").strip()
                        fields = line.split(":")
                        if line.startswith("!STATE:") and len(fields) >= 4:
                            latest["seq"] = int(fields[1])
                            latest["mode"] = fields[2]
                            latest["io_node_connected"] = fields[3] == "ONLINE"
                            latest["event"] = "heartbeat"
                            if len(latest["channels"]) == CHANNEL_COUNT:
                                await broadcast()
                        elif line.startswith("!CHANNEL:") and len(fields) >= 3:
                            latest["channels"][fields[1]] = fields[2]
                        elif line.startswith("!EVENT:"):
                            latest["event"] = line[7:]
                            await broadcast()

                    await client.start_notify(BLE_CONTROL, on_notify)
                    await client.write_gatt_char(BLE_CONTROL, b"!SYNC", response=True)
                    while client.is_connected:
                        try:
                            command = await asyncio.wait_for(commands.get(), timeout=1)
                            await client.write_gatt_char(
                                BLE_CONTROL, command.encode(), response=True
                            )
                        except asyncio.TimeoutError:
                            pass
            except Exception as error:
                latest["event"] = "ble_disconnected"
                latest["mode"] = "OFFLINE"
                print(f"[ble] reconnecting after error: {error}")
                await broadcast()
                await asyncio.sleep(2)

    async def run_path_ble(name: str, channel_id: str) -> None:
        while True:
            try:
                print(f"[ble] scanning for {name}")
                device = await BleakScanner.find_device_by_name(name, timeout=8)
                if device is None:
                    await asyncio.sleep(2)
                    continue
                async with BleakClient(device) as client:
                    print(f"[ble] connected: {name}")
                    latest["path_nodes"][name] = {
                        "connected": True,
                        "channel": channel_id,
                        "health": "NORMAL",
                    }

                    async def on_notify(_, payload: bytearray) -> None:
                        line = payload.decode(errors="replace").strip()
                        fields = line.split(":")
                        if line.startswith("!CHANNEL:") and len(fields) >= 3:
                            latest["path_nodes"][name]["health"] = fields[2]
                        elif line.startswith("!EVENT:"):
                            await broadcast()

                    await client.start_notify(PATH_CONTROL, on_notify)
                    await client.write_gatt_char(PATH_CONTROL, b"!SYNC", response=True)
                    while client.is_connected:
                        desired = (
                            latest["channels"].get(channel_id, "NORMAL")
                            if latest["mode"] != "OFFLINE"
                            else "NORMAL"
                        )
                        command = f"!CHANNEL:{channel_id}:{desired}".encode()
                        await client.write_gatt_char(PATH_CONTROL, command, response=True)
                        await asyncio.sleep(1)
            except Exception as error:
                latest["path_nodes"][name] = {
                    "connected": False,
                    "channel": channel_id,
                    "health": "UNKNOWN",
                }
                print(f"[ble] reconnecting {name} after error: {error}")
                await broadcast()
                await asyncio.sleep(2)

    async def run_ble() -> None:
        await asyncio.gather(
            run_controller_ble(),
            *(run_path_ble(name, channel) for name, channel in PATH_NODES.items()),
        )

    async def run_serial() -> None:
        port = find_port(args.serial)
        stream = serial.Serial(port, args.baud, timeout=0.05)
        buffer = bytearray()
        print(f"[serial] connected: {port}")
        while True:
            while not commands.empty():
                stream.write((await commands.get() + "\n").encode())
            if stream.in_waiting:
                buffer.extend(stream.read(stream.in_waiting))
            marker = buffer.find(MAGIC)
            if marker < 0:
                buffer[:] = buffer[-1:]
            elif marker:
                del buffer[:marker]
            elif len(buffer) >= 6:
                size = int.from_bytes(buffer[2:4], "big")
                frame_size = 4 + size + 2
                if size > 4096:
                    del buffer[:2]
                elif len(buffer) >= frame_size:
                    payload = bytes(buffer[4 : 4 + size])
                    expected = int.from_bytes(buffer[4 + size : frame_size], "big")
                    del buffer[:frame_size]
                    if crc16(payload) == expected:
                        latest.update(cbor2.loads(payload))
                        await broadcast()
            await asyncio.sleep(0.01)

    transport = run_ble if args.transport == "ble" else run_serial
    async with websockets.serve(handler, args.host, args.port):
        print(f"[bridge] {args.transport} -> ws://{args.host}:{args.port}")
        await transport()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
