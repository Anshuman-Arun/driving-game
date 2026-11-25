"""Offline verification of the existing premium fir and fern, never copies or downloads."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[2]
PINNED = {
    "fern": ("b081b04855ef451972742bc4e4d3862eb9567a31dad55600b547ac26aeebc4cd", 1908084),
    "fir": ("cff013dfbe455ce8016aa82a26faf1c6747ebf72f95c18d7a59979689447f149", 14585660),
}

def check(ok, message):
    if not ok:
        raise ValueError(message)

def audit(name):
    path = ROOT / "assets" / "premium_runtime" / (name + ".glb")
    data = path.read_bytes()
    check(not data.startswith(b"version https://git-lfs.github.com/spec/v1"), f"{name}: LFS pointer, run git lfs pull")
    digest, size = PINNED[name]
    check(len(data) == size and hashlib.sha256(data).hexdigest() == digest, f"{name}: unexpected bytes; re-audit changed source")
    check(len(data) >= 20 and struct.unpack_from("<4sII", data) == (b"glTF", 2, len(data)), f"{name}: invalid GLB header")
    offset = 12
    chunks = {}
    while offset < len(data):
        check(offset + 8 <= len(data), "truncated chunk")
        length, typ = struct.unpack_from("<I4s", data, offset)
        offset += 8
        check(length % 4 == 0 and offset + length <= len(data) and typ not in chunks, "invalid chunk")
        chunks[typ] = data[offset:offset + length]
        offset += length
    doc = json.loads(chunks[b"JSON"])
    binary = chunks.get(b"BIN\x00", b"")
    for view in doc.get("bufferViews", []):
        check(view["buffer"] == 0 and 0 <= view.get("byteOffset", 0) <= len(binary) and view.get("byteOffset", 0) + view["byteLength"] <= len(binary), "invalid buffer view")
    for image in doc.get("images", []):
        if "bufferView" in image:
            check(0 <= image["bufferView"] < len(doc["bufferViews"]), "missing embedded image")
        elif "uri" in image and not image["uri"].startswith("data:"):
            uri = image["uri"]
            target = (path.parent / uri).resolve()
            check(target.is_relative_to(path.parent.resolve()) and target.is_file(), "missing or unsafe image")
        else:
            check(image.get("uri", "").startswith("data:"), "missing image")
    triangles = sum(doc["accessors"][primitive.get("indices", primitive["attributes"]["POSITION"])]["count"] // 3
                    for mesh in doc["meshes"] for primitive in mesh["primitives"] if primitive.get("mode", 4) == 4)
    masks = [m for m in doc.get("materials", []) if m.get("alphaMode") == "MASK"]
    # Imported/runtime alpha restoration must still be checked visually and in Godot.
    check(triangles > 0 and masks, f"{name}: no triangles or alpha-scissor material")
    return {"asset": name, "sha256": digest, "bytes": size, "triangles": triangles, "materials": len(doc["materials"]), "alpha_mask_materials": len(masks), "images": len(doc.get("images", []))}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset", choices=sorted(PINNED), action="append")
    args = parser.parse_args()
    print(json.dumps([audit(name) for name in (args.asset or sorted(PINNED))], indent=2))
