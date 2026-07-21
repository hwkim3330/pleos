#!/usr/bin/env python3
"""Add inline ESP nodes to the ROII glTF without replacing its native paths."""

import argparse
import base64
import json
import struct
from pathlib import Path


CUBE_POSITIONS = [
    # front, back, left, right, top, bottom (four vertices per face)
    (-0.5, -0.5, 0.5), (0.5, -0.5, 0.5), (0.5, 0.5, 0.5), (-0.5, 0.5, 0.5),
    (0.5, -0.5, -0.5), (-0.5, -0.5, -0.5), (-0.5, 0.5, -0.5), (0.5, 0.5, -0.5),
    (-0.5, -0.5, -0.5), (-0.5, -0.5, 0.5), (-0.5, 0.5, 0.5), (-0.5, 0.5, -0.5),
    (0.5, -0.5, 0.5), (0.5, -0.5, -0.5), (0.5, 0.5, -0.5), (0.5, 0.5, 0.5),
    (-0.5, 0.5, 0.5), (0.5, 0.5, 0.5), (0.5, 0.5, -0.5), (-0.5, 0.5, -0.5),
    (-0.5, -0.5, -0.5), (0.5, -0.5, -0.5), (0.5, -0.5, 0.5), (-0.5, -0.5, 0.5),
]
CUBE_NORMALS = (
    [(0.0, 0.0, 1.0)] * 4 + [(0.0, 0.0, -1.0)] * 4
    + [(-1.0, 0.0, 0.0)] * 4 + [(1.0, 0.0, 0.0)] * 4
    + [(0.0, 1.0, 0.0)] * 4 + [(0.0, -1.0, 0.0)] * 4
)
CUBE_INDICES = [value for face in range(6) for value in (
    face * 4, face * 4 + 1, face * 4 + 2,
    face * 4, face * 4 + 2, face * 4 + 3,
)]


def add_material(document, name, color, metallic=0.15):
    document.setdefault("materials", []).append({
        "name": name,
        "pbrMetallicRoughness": {
            "baseColorFactor": [*color, 1.0],
            "metallicFactor": metallic,
            "roughnessFactor": 0.38,
        },
        "emissiveFactor": [value * 0.2 for value in color],
    })
    return len(document["materials"]) - 1


def append_geometry(document, binary):
    while len(binary) % 4:
        binary.append(0)
    position_offset = len(binary)
    for vertex in CUBE_POSITIONS:
        binary.extend(struct.pack("<3f", *vertex))
    normal_offset = len(binary)
    for normal in CUBE_NORMALS:
        binary.extend(struct.pack("<3f", *normal))
    index_offset = len(binary)
    for index in CUBE_INDICES:
        binary.extend(struct.pack("<H", index))

    views = document.setdefault("bufferViews", [])
    accessors = document.setdefault("accessors", [])
    position_view = len(views)
    views.append({"buffer": 0, "byteOffset": position_offset, "byteLength": 288, "target": 34962})
    normal_view = len(views)
    views.append({"buffer": 0, "byteOffset": normal_offset, "byteLength": 288, "target": 34962})
    index_view = len(views)
    views.append({"buffer": 0, "byteOffset": index_offset, "byteLength": 72, "target": 34963})
    position_accessor = len(accessors)
    accessors.append({
        "bufferView": position_view, "componentType": 5126, "count": 24, "type": "VEC3",
        "min": [-0.5, -0.5, -0.5], "max": [0.5, 0.5, 0.5],
    })
    normal_accessor = len(accessors)
    accessors.append({"bufferView": normal_view, "componentType": 5126, "count": 24, "type": "VEC3"})
    index_accessor = len(accessors)
    accessors.append({"bufferView": index_view, "componentType": 5123, "count": 36, "type": "SCALAR"})
    return position_accessor, normal_accessor, index_accessor


def add_mesh(document, name, material, accessors):
    position, normal, indices = accessors
    document.setdefault("meshes", []).append({
        "name": name,
        "primitives": [{
            "attributes": {"POSITION": position, "NORMAL": normal},
            "indices": indices,
            "material": material,
        }],
    })
    return len(document["meshes"]) - 1


def add_node(document, name, mesh, position, scale, rotation=None):
    node = {"name": name, "mesh": mesh, "translation": list(position), "scale": list(scale)}
    if rotation is not None:
        node["rotation"] = rotation
    document.setdefault("nodes", []).append(node)
    index = len(document["nodes"]) - 1
    document["scenes"][document.get("scene", 0)].setdefault("nodes", []).append(index)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    document = json.loads(args.source.read_text())
    uri = document["buffers"][0]["uri"]
    prefix, encoded = uri.split(",", 1)
    binary = bytearray(base64.b64decode(encoded))
    geometry = append_geometry(document, binary)

    esp = add_material(document, "InlineESP", (0.04, 0.32, 0.29), metallic=0.35)
    esp_mesh = add_mesh(document, "InlineESPMesh", esp, geometry)

    # Preserve the source model's split FrontZC, Path1/Path2 and connection meshes.
    esp_ab = (0.0, 5.6, 14.0)
    esp_ar = (-1.25, 5.6, 5.0)
    esp_br = (1.25, 5.6, 5.0)
    for name, position in (("ESP_AB", esp_ab), ("ESP_AR", esp_ar), ("ESP_BR", esp_br)):
        add_node(document, name, esp_mesh, position, (1.1, 0.5, 1.1))

    document["buffers"][0]["byteLength"] = len(binary)
    document["buffers"][0]["uri"] = prefix + "," + base64.b64encode(binary).decode("ascii")
    args.output.write_text(json.dumps(document, separators=(",", ":")))


if __name__ == "__main__":
    main()
