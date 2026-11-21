#!/usr/bin/env python3
"""Offline glTF 2.0 binary QA: geometry, hierarchy, material and memory audit.

This never accepts "GLB imported" as evidence of visual quality. Outputs are
structural counts only; draw calls are conservative primitive-submission proxies.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import struct
import sys
from collections import Counter


REQUIRED = ("Body", "Wheel_FL_Pivot", "Wheel_FR_Pivot",
            "Wheel_RL_Pivot", "Wheel_RR_Pivot")
TARGETS = {"hero": (35000, 80000), "mid": (5000, 15000),
           "distant": (1000, 3000)}


def parse_glb(path: pathlib.Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError("Truncated GLB")
    magic, version, length = struct.unpack_from("<4sII", data)
    if (magic, version, length) != (b"glTF", 2, len(data)):
        raise ValueError("Not a complete glTF 2.0 GLB")
    cursor = 12
    chunks = []
    while cursor < len(data):
        if cursor + 8 > len(data):
            raise ValueError("Incomplete GLB chunk header")
        size, kind = struct.unpack_from("<II", data, cursor)
        cursor += 8
        if size % 4 or cursor + size > len(data):
            raise ValueError("Invalid GLB chunk alignment/length")
        chunks.append((kind, data[cursor:cursor+size]))
        cursor += size
    if not chunks or chunks[0][0] != 0x4E4F534A:
        raise ValueError("Missing first JSON chunk")
    gltf = json.loads(chunks[0][1].rstrip(b" \0").decode("utf-8"))
    binary = next((body for kind, body in chunks if kind == 0x004E4942), b"")
    declared = gltf.get("buffers", [])
    if declared and declared[0]["byteLength"] > len(binary):
        raise ValueError("Missing embedded binary buffer data")
    return gltf, binary


def inspect(path: pathlib.Path, expected: str = "") -> dict:
    doc, binary = parse_glb(path)
    meshes = doc.get("meshes", [])
    nodes = doc.get("nodes", [])
    accessors = doc.get("accessors", [])
    materials = doc.get("materials", [])
    textures = doc.get("textures", [])
    triangles = 0
    primitives = 0
    material_uses = Counter()
    for mesh in meshes:
        for prim in mesh.get("primitives", []):
            mode = prim.get("mode", 4)
            if mode != 4:
                raise ValueError("Non-triangle mesh mode is not supported: " + str(mode))
            accessor = prim.get("indices", prim.get("attributes", {}).get("POSITION"))
            if accessor is None or accessor >= len(accessors):
                raise ValueError("Primitive missing a valid POSITION/index accessor")
            tri_indices = accessors[accessor].get("count", 0)
            if tri_indices % 3:
                raise ValueError("Triangle indices are not divisible by three")
            triangles += tri_indices // 3
            primitives += 1
            material_uses[prim.get("material", -1)] += 1
    named = {}
    for i, node in enumerate(nodes):
        named.setdefault(node.get("name", ""), []).append(i)

    def descendant_meshes(root_index: int) -> int:
        seen, todo, count = set(), [root_index], 0
        while todo:
            idx = todo.pop()
            if idx in seen or idx < 0 or idx >= len(nodes):
                raise ValueError("Broken or cyclic glTF node hierarchy")
            seen.add(idx)
            node = nodes[idx]
            count += int("mesh" in node)
            todo.extend(node.get("children", []))
        return count

    for req in REQUIRED:
        if len(named.get(req, [])) != 1:
            raise ValueError("Required node not uniquely present: " + req)
        if descendant_meshes(named[req][0]) < 1:
            raise ValueError("Required node has no mesh descendants: " + req)
    for brake in ("Brake_FL", "Brake_FR", "Brake_RL", "Brake_RR"):
        if len(named.get(brake, [])) != 1:
            raise ValueError("Missing stationary brake node: " + brake)
    image_report = []
    for img in doc.get("images", []):
        image_report.append({"name": img.get("name", ""), "mime": img.get("mimeType", ""),
                             "embedded": "bufferView" in img})
        if "bufferView" not in img and "uri" in img:
            raise ValueError("GLB references an external image: " + str(img["uri"]))
    approximate_texture_mb = 0.0
    # Embedded images may be compressed. The reported value is only file-size
    # lower bound until decoded dimensions are measured by Godot/Blender.
    for img in doc.get("images", []):
        v = img.get("bufferView")
        if v is not None:
            approximate_texture_mb += doc["bufferViews"][v]["byteLength"] / (1024*1024)
    result = {
        "path": str(path),
        "file_mb": round(path.stat().st_size / 1048576, 3),
        "triangles": triangles,
        "mesh_primitives_proxy_draw_calls": primitives,
        "mesh_nodes": sum("mesh" in n for n in nodes),
        "materials": len(materials),
        "material_uses": dict(material_uses),
        "textures": len(textures),
        "images": image_report,
        "embedded_compressed_image_mb": round(approximate_texture_mb, 3),
        "animations": len(doc.get("animations", [])),
        "wheels": list(REQUIRED[1:]),
        "static_brakes": 4,
        "visual_gate": "UNVERIFIED: requires rendered Godot screenshot comparison",
        "graphics_fps": None,
        "gpu_texture_memory_mb": None,
    }
    if expected:
        low, high = TARGETS[expected]
        if not low <= triangles <= high:
            raise ValueError(f"{expected} budget out of range: {triangles} not {low}..{high}")
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument("model", type=pathlib.Path, nargs="+")
    p.add_argument("--enforce-lod", choices=TARGETS, default="")
    args = p.parse_args()
    bad = False
    for model in args.model:
        try:
            if not model.is_file():
                raise FileNotFoundError(str(model))
            print(json.dumps(inspect(model, args.enforce_lod), indent=2))
        except Exception as exc:
            bad = True
            print(f"FAIL {model}: {exc}", file=sys.stderr)
    raise SystemExit(1 if bad else 0)


if __name__ == "__main__":
    main()
