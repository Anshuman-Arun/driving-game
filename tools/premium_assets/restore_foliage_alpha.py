"""Combine the original Poly Haven opacity map with a converted foliage GLB's diffuse image."""

import argparse
import io
import json
from pathlib import Path
import struct

from PIL import Image


def restore(model: Path, mask: Path) -> None:
    raw = model.read_bytes()
    magic, version, _ = struct.unpack_from("<4sII", raw)
    if magic != b"glTF" or version != 2:
        raise ValueError("Expected a glTF 2 GLB")
    json_length, chunk_type = struct.unpack_from("<I4s", raw, 12)
    if chunk_type != b"JSON":
        raise ValueError("GLB has no JSON chunk")
    spec = json.loads(raw[20:20 + json_length])
    bin_start = 20 + json_length + 8
    data = bytearray(raw[bin_start:])
    diffuse = [entry for entry in spec["images"] if "_diff-" in entry.get("name", "") and "_alpha" in entry["name"]]
    if len(diffuse) != 1:
        raise ValueError("Expected one foliage diffuse mapped to the alpha material")
    image = diffuse[0]
    if image["mimeType"] != "image/png":
        view = spec["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        color = Image.open(io.BytesIO(data[start:start + view["byteLength"]])).convert("RGBA")
        alpha = Image.open(mask).convert("L")
        if alpha.size != color.size or alpha.getextrema() != (0, 255):
            raise ValueError("Opacity map does not match the source diffuse")
        color.putalpha(alpha)
        color.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
        encoded = io.BytesIO()
        color.save(encoded, format="PNG", optimize=True)
        image["bufferView"] = len(spec["bufferViews"])
        image["mimeType"] = "image/png"
        spec["bufferViews"].append({"buffer": 0, "byteOffset": len(data), "byteLength": encoded.tell()})
        data += encoded.getvalue()
        data += b"\0" * (-len(data) % 4)
    image_index = spec["images"].index(image)
    textures = {index for index, tex in enumerate(spec["textures"]) if tex.get("source") == image_index}
    for material in spec["materials"]:
        diffuse_slot = material.get("pbrMetallicRoughness", {}).get("baseColorTexture", {})
        if diffuse_slot.get("index") in textures:
            material.update(alphaMode="MASK", alphaCutoff=0.39, doubleSided=True)
    spec["buffers"][0]["byteLength"] = len(data)
    metadata = json.dumps(spec, separators=(",", ":")).encode()
    metadata += b" " * (-len(metadata) % 4)
    model.write_bytes(struct.pack("<4sII", b"glTF", 2, 28 + len(metadata) + len(data))
                      + struct.pack("<I4s", len(metadata), b"JSON") + metadata
                      + struct.pack("<I4s", len(data), b"BIN\0") + data)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path)
    parser.add_argument("mask", type=Path)
    args = parser.parse_args()
    restore(args.model, args.mask)
