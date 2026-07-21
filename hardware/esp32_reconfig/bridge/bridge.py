#!/usr/bin/env python3
"""Bridge framed CBOR from the ESP controller to Android emulator WebSocket clients."""

import argparse
import asyncio
import json
from pathlib import Path

import cbor2
import serial
from serial.tools import list_ports
import websockets

MAGIC = b"\xa5\x5a"


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
    candidates = [p.device for p in list_ports.comports() if "usbmodem" in p.device or "wch" in p.description.lower()]
    if not candidates:
        raise RuntimeError("ESP serial port not found. Pass --serial /dev/cu.usbmodem...")
    return candidates[0]


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8766)
    args = parser.parse_args()
    port = find_port(args.serial)
    stream = serial.Serial(port, args.baud, timeout=0.05)
    clients: set = set()
    buffer = bytearray()

    async def handler(socket):
        clients.add(socket)
        print(f"[bridge] app connected ({len(clients)})")
        try:
            async for raw in socket:
                try:
                    command = json.loads(raw)
                    if command.get("command") == "scenario":
                        stream.write(f"!SCENARIO:{command['id']}\n".encode())
                    elif command.get("command") == "channel":
                        stream.write(
                            f"!CHANNEL:{command['id']}:{command['health']}\n".encode()
                        )
                    elif command.get("command") == "recover":
                        stream.write(b"!RECOVER\n")
                    else:
                        await socket.send(json.dumps({"error": "unknown_command"}))
                        continue
                    print(f"[app] {command}")
                except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
                    await socket.send(json.dumps({"error": str(error)}))
        except websockets.ConnectionClosed:
            pass
        finally:
            clients.discard(socket)
            print(f"[bridge] app disconnected ({len(clients)})")

    async with websockets.serve(handler, args.host, args.port):
        print(f"[bridge] {port} -> ws://{args.host}:{args.port}")
        while True:
            waiting = stream.in_waiting
            if waiting:
                buffer.extend(stream.read(waiting))
            while True:
                marker = buffer.find(MAGIC)
                if marker < 0:
                    buffer[:] = buffer[-1:]
                    break
                if marker:
                    del buffer[:marker]
                if len(buffer) < 6:
                    break
                size = int.from_bytes(buffer[2:4], "big")
                frame_size = 4 + size + 2
                if size > 4096:
                    del buffer[:2]
                    continue
                if len(buffer) < frame_size:
                    break
                payload = bytes(buffer[4 : 4 + size])
                expected = int.from_bytes(buffer[4 + size : frame_size], "big")
                del buffer[:frame_size]
                if crc16(payload) != expected:
                    print("[bridge] dropped frame with bad CRC")
                    continue
                message = cbor2.loads(payload)
                encoded = json.dumps(message, separators=(",", ":"))
                if message.get("event") != "heartbeat":
                    print(
                        f"[esp] {message.get('event')} "
                        f"mode={message.get('mode')} seq={message.get('seq')}"
                    )
                stale = []
                for socket in list(clients):
                    try:
                        await socket.send(encoded)
                    except websockets.ConnectionClosed:
                        stale.append(socket)
                for socket in stale:
                    clients.discard(socket)
            await asyncio.sleep(0.01)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
