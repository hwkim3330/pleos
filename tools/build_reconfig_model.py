#!/usr/bin/env python3
"""Add inline ESP nodes and physical 3D link meshes to the ROII glTF."""

import argparse
import base64
import json
import math
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


def quaternion_from_z(direction):
    length = math.sqrt(sum(value * value for value in direction))
    x, y, z = (value / length for value in direction)
    if z < -0.999999:
        return [1.0, 0.0, 0.0, 0.0]
    qx, qy, qz, qw = -y, x, 0.0, 1.0 + z
    norm = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
    return [qx / norm, qy / norm, qz / norm, qw / norm]


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


def add_link(document, mesh, name, start, end, thickness=0.34):
    direction = tuple(end[i] - start[i] for i in range(3))
    length = math.sqrt(sum(value * value for value in direction))
    midpoint = tuple((start[i] + end[i]) / 2 for i in range(3))
    add_node(
        document, name, mesh, midpoint, (thickness, thickness, length),
        quaternion_from_z(direction),
    )


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

    blue = add_material(document, "ReconfigLinkAB", (0.08, 0.35, 0.92))
    teal = add_material(document, "ReconfigLinkZonal", (0.02, 0.58, 0.48))
    esp = add_material(document, "InlineESP", (0.04, 0.32, 0.29), metallic=0.35)
    blue_mesh = add_mesh(document, "ReconfigLinkABMesh", blue, geometry)
    teal_mesh = add_mesh(document, "ReconfigLinkZonalMesh", teal, geometry)
    esp_mesh = add_mesh(document, "InlineESPMesh", esp, geometry)

    front_a = (-10.0, 6.5, 13.0)
    front_b = (10.0, 6.5, 13.0)
    rear = (0.0, 7.0, -12.0)
    esp_ab = (0.0, 7.2, 13.0)
    esp_ar = (-5.0, 7.2, 0.5)
    esp_br = (5.0, 7.2, 0.5)
    for mesh, name, start, middle, end in (
        (blue_mesh, "Link_FrontA_ESPAB", front_a, esp_ab, front_b),
        (teal_mesh, "Link_FrontA_ESPAR", front_a, esp_ar, rear),
        (teal_mesh, "Link_FrontB_ESPBR", front_b, esp_br, rear),
    ):
        add_link(document, mesh, name + "_In", start, middle)
        add_link(document, mesh, name + "_Out", middle, end)
    for name, position in (("ESP_AB", esp_ab), ("ESP_AR", esp_ar), ("ESP_BR", esp_br)):
        add_node(document, name, esp_mesh, position, (1.5, 0.9, 1.8))

    document["buffers"][0]["byteLength"] = len(binary)
    document["buffers"][0]["uri"] = prefix + "," + base64.b64encode(binary).decode("ascii")
    args.output.write_text(json.dumps(document, separators=(",", ":")))


if __name__ == "__main__":
    main()
