"""Dependency-free orthographic silhouette QA; not a GPU or artistic acceptance test."""
import base64
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

SIZE = 256
ROOT = Path(__file__).resolve().parents[2]


def require(ok, message):
    if not ok:
        raise ValueError(message)


def load_mesh(root, entry, lod):
    resource = entry[f"lod{lod}"]
    expected = f"res://assets/environment_overhaul/{entry['species_id']}_lod{lod}.gltf"
    require(resource == expected, "unexpected asset resource")
    data = (root / resource[6:]).read_bytes()
    require(hashlib.sha256(data).hexdigest() == entry["sha256_by_path"][resource], "asset hash mismatch")
    g = json.loads(data)
    acc = g["accessors"][g["meshes"][0]["primitives"][0]["attributes"]["POSITION"]]
    view = g["bufferViews"][acc["bufferView"]]
    count = acc["count"]
    require(acc["componentType"] == 5126 and acc["type"] == "VEC3" and count > 0 and count % 3 == 0, "not a triangle-list position accessor")
    prefix = "data:application/octet-stream;base64,"
    uri = g["buffers"][0]["uri"]
    require(uri.startswith(prefix), "not an embedded buffer")
    buf = base64.b64decode(uri[len(prefix):], validate=True)
    offset = view["byteOffset"]
    length = view["byteLength"]
    require(length == count * 12 and 0 <= offset <= len(buf) - length, "bad position view")
    vertices = list(struct.iter_unpack("<3f", buf[offset:offset + length]))
    require(all(math.isfinite(x) for p in vertices for x in p), "nonfinite positions")
    return vertices


def raster(vertices, azimuth, elevation, scale):
    ca, sa = math.cos(azimuth), math.sin(azimuth)
    ce, se = math.cos(elevation), math.sin(elevation)
    coords = [(SIZE / 2 + (x * ca + z * sa) * scale,
               SIZE / 2 + (-x * sa * se + y * ce + z * ca * se) * scale)
              for x, y, z in vertices]
    mask = [0] * SIZE  # Each row is a bitset, filled at pixel centers.
    for i in range(0, len(coords), 3):
        a, b, c = coords[i:i + 3]
        y0 = max(0, math.ceil(min(a[1], b[1], c[1]) - 0.5))
        y1 = min(SIZE - 1, math.floor(max(a[1], b[1], c[1]) - 0.5))
        for row in range(y0, y1 + 1):
            y = row + 0.5
            crossings = []
            for p, q in [(a, b), (b, c), (c, a)]:
                if min(p[1], q[1]) <= y < max(p[1], q[1]):
                    crossings.append(p[0] + (q[0] - p[0]) * (y - p[1]) / (q[1] - p[1]))
            if len(crossings) != 2:
                continue
            x0 = max(0, math.ceil(min(crossings) - 0.5))
            x1 = min(SIZE - 1, math.floor(max(crossings) - 0.5))
            if x1 >= x0:
                mask[row] |= ((1 << (x1 - x0 + 1)) - 1) << x0
    return mask


def compare(a, b):
    union = sum((x | y).bit_count() for x, y in zip(a, b))
    near = sum(x.bit_count() for x in a)
    far = sum(y.bit_count() for y in b)
    require(union > 0 and near > 0 and far > 0, "empty projected silhouette")
    return sum((x & y).bit_count() for x, y in zip(a, b)) / union, far / near


def run(root):
    # Negative fixtures: empty silhouettes are invalid; disjoint nonempty ones have IoU zero.
    try:
        compare([0], [0])
    except ValueError:
        pass
    else:
        raise ValueError("empty projection accepted")
    require(compare([1], [2]) == (0.0, 1.0), "disjoint projection fixture")
    manifest = json.loads((root / "assets/environment_overhaul/manifest.json").read_text())
    require(manifest.get("schema_version") == 1 and len(manifest.get("assets", [])) == 5, "manifest schema")
    species = set()
    views = 0
    for entry in manifest["assets"]:
        name = entry["species_id"]
        require(name in {"fern", "reed", "sapling", "shrub", "wildflower"} and name not in species, "invalid species")
        species.add(name)
        near, far = load_mesh(root, entry, 0), load_mesh(root, entry, 1)
        # Center on the declared volume so neither elevated nor broad silhouettes clip.
        h = entry["dimensions_m"][1]
        near = [(x, y - h / 2, z) for x, y, z in near]
        far = [(x, y - h / 2, z) for x, y, z in far]
        scale = SIZE * 0.42 / max(math.sqrt(sum(x*x for x in p)) for p in near)
        metrics = []
        for elevation in (0, math.pi / 6, math.pi / 3):
            for step in range(8):
                azimuth = step * math.pi / 4
                iou, ratio = compare(raster(near, azimuth, elevation, scale), raster(far, azimuth, elevation, scale))
                require(iou >= 0.80 and 0.80 <= ratio <= 1.20,
                        f"{name} projection regression: az={step*45}, elev={math.degrees(elevation):.0f}, IoU={iou:.4f}, area ratio={ratio:.4f}")
                metrics.append((iou, ratio))
                views += 1
        print(f"{name}: minimum IoU={min(x for x, _ in metrics):.4f}, mean={sum(x for x, _ in metrics)/len(metrics):.4f}, area ratio={min(y for _, y in metrics):.4f}..{max(y for _, y in metrics):.4f}")
    require(views == 120, "projection count")
    print("Vegetation CPU silhouette checks passed: 120/120")


if __name__ == "__main__":
    try:
        run(Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else ROOT)
    except (ValueError, OSError, KeyError, TypeError) as exc:
        print(f"Projection check FAILED: {exc}", file=sys.stderr)
        sys.exit(1)
