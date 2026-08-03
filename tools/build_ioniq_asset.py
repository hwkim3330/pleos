#!/usr/bin/env python3
"""Strip PLEOS's driving overlays out of the CE_X (IONIQ 6) asset.

Prepares the model for use in a reconfiguration console, where the vehicle's own
indicators are the display surface and LG's driving HUD is in the way.

The model ships that HUD baked in as geometry: highway-assist chevrons stretching metres
ahead of the car, the blue FVSA plane, trunk/frunk/charge-port warning boards, the charging
cable, door and side warning panels. Setting their materials to zero alpha in model-viewer
is **not** enough, and both reasons cost real debugging time:

  * a mesh still contributes to the bounding box, so `camera-target="auto auto auto"` frames
    a volume that is mostly empty space and the car comes out small and off-centre
  * a mesh still casts a shadow, so invisible chevrons leave smears on the ground plane

So they are removed from the scene graph instead. The proximity arcs, ADAS warnings and
turn signals are deliberately kept: they sit on or beside the car and they are what a
reconfiguration console lights up when a TSN path is isolated. See
`docs/ioniq_vehicle_notes.md` for the target-to-indicator mapping and the model-viewer
trap that goes with it.

The source asset is LG's licence, not ours -- see ~/roii_ioniq_assets/README.md. Neither
the input nor the output belongs in a remote.

    python3 tools/build_ioniq_asset.py [source.glb] [target.glb]
"""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = Path.home() / "roii_ioniq_assets" / "ce_x_raw.glb"
DEFAULT_TARGET = ROOT / "tools" / "assets" / "ce_x_console.glb"

# PLEOS driving overlays: geometry that belongs to LG's HUD, not to the vehicle.
DROP_NODES = {
    "HDS_01", "HDS_02", "HDS_03", "HDS_04",   # highway-assist chevrons, the worst offender
    "FVSA",                                    # forward vehicle start alert plane + arrow
    "TW", "FW",                                # trunk / frunk warning boards
    "CPW",                                     # charge port warning
    "Chaging_cable",                           # sic, as the asset spells it
    "Charging_Port",
    "DW_F_L", "DW_F_R", "DW_R_L", "DW_R_R",   # door warning boards
    "SW_L", "SW_R",                            # side warning boards
}

GLB_MAGIC = 0x46546C67
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def pad(data: bytes, filler: int) -> bytes:
    remainder = len(data) % 4
    return data if remainder == 0 else data + bytes([filler]) * (4 - remainder)


def main() -> None:
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SOURCE
    target = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_TARGET
    if not source.exists():
        sys.exit(
            f"missing {source}\n"
            "Rebuild it with the recipe in ~/roii_ioniq_assets/README.md "
            "(adb pull + gltf-transform, keeping the node graph intact).\n"
            "Use ce_x_raw.glb, not ce_x.glb: the latter is Draco compressed and "
            "model-viewer fetches its Draco decoder from gstatic, which an offline "
            "bench demo cannot rely on."
        )

    raw = source.read_bytes()
    if raw[:4] != b"glTF":
        sys.exit(f"{source} is not a binary glb")
    json_length = struct.unpack("<I", raw[12:16])[0]
    gltf = json.loads(raw[20 : 20 + json_length].decode("utf-8").rstrip("\x00 "))
    bin_offset = 20 + ((json_length + 3) & ~3)
    bin_length, bin_kind = struct.unpack("<II", raw[bin_offset : bin_offset + 8])
    if bin_kind != BIN_CHUNK:
        sys.exit("expected a BIN chunk after the JSON chunk")
    blob = raw[bin_offset + 8 : bin_offset + 8 + bin_length]

    nodes = gltf.get("nodes", [])
    dropped = {
        index for index, node in enumerate(nodes) if node.get("name") in DROP_NODES
    }
    missing = DROP_NODES - {node.get("name") for node in nodes}
    if missing:
        print(f"note: not present in this asset, skipped: {sorted(missing)}")

    # Unparent rather than delete: node indices are referenced by scenes, children lists,
    # skins and animation channels, and renumbering all of that to save a few unused
    # accessors is not worth the risk of silently corrupting one of them.
    for scene in gltf.get("scenes", []):
        scene["nodes"] = [i for i in scene.get("nodes", []) if i not in dropped]
    for node in nodes:
        if "children" in node:
            node["children"] = [i for i in node["children"] if i not in dropped]
            if not node["children"]:
                del node["children"]

    json_chunk = pad(json.dumps(gltf, separators=(",", ":")).encode("utf-8"), 0x20)
    bin_chunk = pad(blob, 0x00)
    total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)

    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("wb") as out:
        out.write(struct.pack("<III", GLB_MAGIC, 2, total))
        out.write(struct.pack("<II", len(json_chunk), JSON_CHUNK))
        out.write(json_chunk)
        out.write(struct.pack("<II", len(bin_chunk), BIN_CHUNK))
        out.write(bin_chunk)

    print(
        f"{source.name} -> {target}: dropped {len(dropped)} overlay nodes "
        f"({total / 1e6:.2f} MB)"
    )


if __name__ == "__main__":
    main()
