#!/usr/bin/env python3
"""Prepare the ROii asset for the native Filament viewer in PLEOS Reconfig Studio.

`lib/assets/roii_reconfig.glb` is not a binary glb at all: it is glTF JSON with its
buffer and both images inlined as base64 `data:` URIs. That works in a WebView but it
makes every native loader depend on decoding data URIs, and it costs 33% in size for
the base64. Two changes are made here:

  * repack as a real binary glb, so any loader can read it and the file shrinks
  * switch the body shell material to alphaMode BLEND

The second one is what makes the shell slider work natively. gltfio bakes blending
into the material variant it picks from the glTF, and `MaterialInstance` cannot switch
it at runtime, so an OPAQUE body simply ignores whatever alpha is set on it -- the
slider would appear to do nothing. model-viewer can flip it in JS; Filament cannot.

Run from the repository root:

    python3 tools/build_native_vehicle_asset.py
"""
from __future__ import annotations

import base64
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "apps" / "pleos_reconfig_studio" / "lib" / "assets" / "roii_reconfig.glb"
TARGET = (
    ROOT
    / "apps"
    / "pleos_reconfig_studio"
    / "android"
    / "app"
    / "src"
    / "main"
    / "assets"
    / "roii_reconfig.glb"
)

# The textured body. Its material is the one that has to become translucent for the
# shell slider to mean anything.
BODY_MATERIAL = "roii"
GLB_MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def decode_data_uri(uri: str) -> bytes:
    marker = "base64,"
    index = uri.index(marker)
    return base64.b64decode(uri[index + len(marker) :])


def pad(data: bytes, filler: int) -> bytes:
    remainder = len(data) % 4
    return data if remainder == 0 else data + bytes([filler]) * (4 - remainder)


def main() -> None:
    raw = SOURCE.read_bytes()
    if raw[:4] == b"glTF":
        sys.exit(f"{SOURCE} is already a binary glb; nothing to repack")
    gltf = json.loads(raw)

    # Every buffer and image becomes a view into one BIN chunk.
    blob = bytearray()

    def append(data: bytes) -> tuple[int, int]:
        offset = len(blob)
        blob.extend(data)
        # Buffer views must start on a four byte boundary.
        while len(blob) % 4:
            blob.append(0)
        return offset, len(data)

    buffers = gltf.get("buffers", [])
    if len(buffers) != 1:
        sys.exit(f"expected exactly one buffer, found {len(buffers)}")
    original = decode_data_uri(buffers[0]["uri"])
    base_offset, base_length = append(original)
    if base_offset != 0:
        sys.exit("the primary buffer must land at offset 0")

    # Existing buffer views keep their offsets because the original buffer is first.
    views = gltf.setdefault("bufferViews", [])
    for image in gltf.get("images", []):
        uri = image.pop("uri", None)
        if uri is None:
            continue
        data = decode_data_uri(uri)
        offset, length = append(data)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": length})
        image["bufferView"] = len(views) - 1

    gltf["buffers"] = [{"byteLength": len(blob)}]

    patched = False
    for material in gltf.get("materials", []):
        if material.get("name") != BODY_MATERIAL:
            continue
        material["alphaMode"] = "BLEND"
        pbr = material.setdefault("pbrMetallicRoughness", {})
        factor = pbr.get("baseColorFactor") or [1.0, 1.0, 1.0, 1.0]
        # Start opaque; the app drives the alpha from the shell slider.
        pbr["baseColorFactor"] = [factor[0], factor[1], factor[2], 1.0]
        patched = True
    if not patched:
        sys.exit(f"material {BODY_MATERIAL!r} not found; the asset layout changed")

    json_chunk = pad(json.dumps(gltf, separators=(",", ":")).encode("utf-8"), 0x20)
    bin_chunk = pad(bytes(blob), 0x00)
    total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)

    TARGET.parent.mkdir(parents=True, exist_ok=True)
    with TARGET.open("wb") as out:
        out.write(struct.pack("<III", GLB_MAGIC, 2, total))
        out.write(struct.pack("<II", len(json_chunk), JSON_CHUNK))
        out.write(json_chunk)
        out.write(struct.pack("<II", len(bin_chunk), BIN_CHUNK))
        out.write(bin_chunk)

    print(
        f"{SOURCE.name}: {len(raw) / 1e6:.2f} MB JSON -> {TARGET.name}: "
        f"{total / 1e6:.2f} MB binary glb "
        f"({len(gltf.get('images', []))} images embedded, {BODY_MATERIAL} set to BLEND)"
    )


if __name__ == "__main__":
    main()
