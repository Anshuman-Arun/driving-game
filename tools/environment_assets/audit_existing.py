"""Verify pinned existing scan bytes and GLB references; no downloads or copies."""
import argparse
import base64
import hashlib
import json
import math
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


def decode_accessor(accessors, views, binary, accessor_id, expected_type, allowed_components):
    acc = index(accessors, accessor_id, "accessor")
    check(acc.get("type") == expected_type and acc.get("componentType") in allowed_components,
          "invalid accessor type")
    check("sparse" not in acc and not acc.get("normalized", False), "unsupported sparse or normalized geometry")
    fmt, width = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}[acc["componentType"]]
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[expected_type]
    view = index(views, acc.get("bufferView"), "accessor buffer view")
    check("extensions" not in view, "unsupported compressed buffer view")
    count, start = acc.get("count"), acc.get("byteOffset", 0)
    packed = width * components
    stride = view.get("byteStride", packed)
    view_start = view.get("byteOffset", 0)
    check(type(count) is int and count > 0 and type(start) is int and start >= 0
          and type(stride) is int and stride >= packed and stride <= 252 and stride % width == 0
          and (view_start + start) % width == 0
          and start + (count - 1) * stride + packed <= view["byteLength"], "accessor exceeds buffer view")
    unpack = struct.Struct("<" + fmt * components).unpack_from
    rows = [unpack(binary, view_start + start + i * stride) for i in range(count)]
    check(all(math.isfinite(x) for row in rows for x in row), "nonfinite geometry attribute")
    return rows


def inspect_primitive(primitive, accessors, views, binary):
    check(primitive.get("mode", 4) == 4, "non-triangle primitive")
    check("extensions" not in primitive, "unsupported primitive compression")
    attributes = primitive.get("attributes", {})
    positions = decode_accessor(accessors, views, binary, attributes.get("POSITION"), "VEC3", (5126,))
    for name, fmt in (("NORMAL", "VEC3"), ("TANGENT", "VEC4"), ("TEXCOORD_0", "VEC2")):
        if name in attributes:
            rows = decode_accessor(accessors, views, binary, attributes[name], fmt, (5126,))
            check(len(rows) == len(positions), "attribute count mismatch")
    if "indices" in primitive:
        ids = [row[0] for row in decode_accessor(accessors, views, binary, primitive["indices"], "SCALAR", (5121, 5123, 5125))]
    else:
        ids = range(len(positions))
    check(len(ids) > 0 and len(ids) % 3 == 0, "invalid triangle count")
    check(all(0 <= i < len(positions) for i in ids), "index outside position accessor")
    for i in range(0, len(ids), 3):
        a, b, c = (positions[ids[j]] for j in range(i, i+3))
        x = tuple(v-u for u,v in zip(a,b))
        y = tuple(v-u for u,v in zip(a,c))
        cross = (x[1]*y[2]-x[2]*y[1], x[2]*y[0]-x[0]*y[2], x[0]*y[1]-x[1]*y[0])
        check(math.hypot(*cross) > 1e-12, "degenerate scan triangle")
    return len(ids) // 3


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
            index(materials, primitive.get("material"), "primitive material")
            triangles += inspect_primitive(primitive, accessors, views, binary)
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
