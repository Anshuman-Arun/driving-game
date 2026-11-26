"""Verify pinned existing scan bytes and GLB references; no downloads or copies."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import struct
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
PINNED = {
    "fern": ("b081b04855ef451972742bc4e4d3862eb9567a31dad55600b547ac26aeebc4cd", 1908084),
    "fir": ("cff013dfbe455ce8016aa82a26faf1c6747ebf72f95c18d7a59979689447f149", 14585660),
}


def check(ok, message):
    if not ok:
        raise ValueError(message)


def index(items, value, label):
    check(type(value) is int and 0 <= value < len(items), f"invalid {label} index")
    return items[value]


def inspect_glb(data, asset_dir):
    check(not data.startswith(b"version https://git-lfs.github.com/spec/v1"), "LFS pointer, run git lfs pull")
    check(len(data) >= 20 and struct.unpack_from("<4sII", data) == (b"glTF", 2, len(data)), "invalid GLB header")
    offset = 12
    chunks = {}
    while offset < len(data):
        check(offset + 8 <= len(data), "truncated chunk")
        length, typ = struct.unpack_from("<I4s", data, offset)
        offset += 8
        check(length % 4 == 0 and offset + length <= len(data) and typ not in chunks, "invalid chunk")
        check(chunks or typ == b"JSON", "JSON must be first chunk")
        chunks[typ] = data[offset:offset + length]
        offset += length
    check(b"JSON" in chunks, "missing JSON chunk")
    doc = json.loads(chunks[b"JSON"])
    check(isinstance(doc, dict) and doc.get("asset", {}).get("version") == "2.0", "invalid glTF version")
    binary = chunks.get(b"BIN\x00", b"")
    buffers = doc.get("buffers", [])
    check(len(buffers) == 1 and "uri" not in buffers[0], "expected one embedded buffer")
    declared = buffers[0].get("byteLength")
    check(type(declared) is int and 0 < declared <= len(binary) <= declared + 3, "invalid BIN length")
    views = doc.get("bufferViews", [])
    for view in views:
        start, size = view.get("byteOffset", 0), view.get("byteLength")
        check(view.get("buffer") == 0 and type(start) is int and type(size) is int and start >= 0 and size > 0 and start + size <= declared, "invalid buffer view")
    images = doc.get("images", [])
    for image in images:
        mime = image.get("mimeType")
        if "bufferView" in image:
            check("uri" not in image, "image has both URI and buffer view")
            v = index(views, image["bufferView"], "image buffer view")
            start = v.get("byteOffset", 0)
            payload = binary[start:start + v["byteLength"]]
            check(mime in ("image/png", "image/jpeg"), "unsupported embedded image MIME")
        else:
            uri = image.get("uri", "")
            check(isinstance(uri, str) and uri, "missing image URI")
            if uri.startswith("data:"):
                header, sep, encoded = uri.partition(",")
                check(sep and header in ("data:image/png;base64", "data:image/jpeg;base64"), "unsupported image data URI")
                mime = header.split(":", 1)[1].split(";", 1)[0]
                payload = base64.b64decode(encoded, validate=True)
            else:
                parts = urlsplit(uri)
                decoded = unquote(parts.path)
                check(not (parts.scheme or parts.netloc or parts.query or parts.fragment or "\\" in decoded or "\x00" in decoded), "unsafe external image URI")
                target = (asset_dir / decoded).resolve()
                check(target.is_relative_to(asset_dir.resolve()) and target.is_file(), "missing or unsafe external image")
                payload = target.read_bytes()
        png, jpeg = payload.startswith(b"\x89PNG\r\n\x1a\n"), payload.startswith(b"\xff\xd8\xff")
        check((png or jpeg) and (mime is None or (png and mime == "image/png") or (jpeg and mime == "image/jpeg")), "invalid image signature or MIME")
    textures = doc.get("textures", [])
    for texture in textures:
        index(images, texture.get("source"), "texture image")
    materials = doc.get("materials", [])
    bound_albedo = 0
    for material in materials:
        pbr = material.get("pbrMetallicRoughness", {})
        for owner, key in [(pbr, "baseColorTexture"), (pbr, "metallicRoughnessTexture"), (material, "normalTexture"), (material, "occlusionTexture"), (material, "emissiveTexture")]:
            if key in owner:
                index(textures, owner[key].get("index"), "material texture")
                if key == "baseColorTexture":
                    bound_albedo += 1
    check(bound_albedo > 0, "no base color texture bound")
    accessors = doc.get("accessors", [])
    triangles = 0
    for mesh in doc.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            check(primitive.get("mode", 4) == 4, "non-triangle primitive")
            pos = index(accessors, primitive.get("attributes", {}).get("POSITION"), "position accessor")
            check(pos.get("type") == "VEC3" and pos.get("componentType") == 5126, "invalid position accessor")
            count = pos.get("count")
            check(type(count) is int and count > 0, "invalid vertex count")
            if "indices" in primitive:
                idx = index(accessors, primitive["indices"], "index accessor")
                check(idx.get("type") == "SCALAR" and idx.get("componentType") in (5121, 5123, 5125), "invalid index accessor")
                count = idx.get("count")
            check(type(count) is int and count > 0 and count % 3 == 0, "invalid triangle count")
            index(materials, primitive.get("material"), "primitive material")
            triangles += count // 3
    check(triangles > 0, "no triangles")
    # Raw MASK flags are descriptive: PremiumMesh.fit can apply scissor on import.
    # Pixel decoding, UV alignment and actual bound material are Godot/local gates.
    return {"triangles": triangles, "materials": len(materials), "alpha_mask_materials": sum(m.get("alphaMode") == "MASK" for m in materials), "images": len(images)}


def audit(name):
    path = ROOT / "assets" / "premium_runtime" / (name + ".glb")
    data = path.read_bytes()
    check(not data.startswith(b"version https://git-lfs.github.com/spec/v1"), f"{name}: LFS pointer, run git lfs pull")
    digest, size = PINNED[name]
    check(len(data) == size and hashlib.sha256(data).hexdigest() == digest, f"{name}: unexpected bytes; re-audit changed source")
    return {"asset": name, "sha256": digest, "bytes": size, **inspect_glb(data, path.parent)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset", choices=sorted(PINNED), action="append")
    args = parser.parse_args()
    print(json.dumps([audit(name) for name in (args.asset or sorted(PINNED))], indent=2))
