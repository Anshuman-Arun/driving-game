"""
Pure Python 3 + NumPy glTF 2.0 (.glb) normalizer & rigger for Aster Valley's 3 hero cars:
  - vela_gt.glb    : Porsche 911 (Sleek RWD German Sports Coupe / Grand Tourer)
  - orion_rs.glb   : Khronos CarConcept (Nimble Lightweight Track Sports Coupe)
  - kestrel_xr.glb : Porsche 918 Spyder Weissach (Flagship AWD Exotic Hypercar)

Outputs uncompressed glTF 2.0 binary (.glb, extensionsRequired omitted) strictly in Godot
coordinate space (+Y up, -Z forward, +X right, centered X=0, tire bottoms Y=0, wheelbase ~2.71m).
"""

import json
import math
import os
import struct
import numpy as np

RAW_DIR = r"c:\Users\anshu\Documents\Coding\Driving-Game\driving-game\assets\forza_cars"
OUT_DIR = r"c:\Users\anshu\Documents\Coding\Driving-Game\driving-game\assets\curated\models\vehicles"

TARGET_WHEELBASE = 2.71
TARGET_TRACK_MAX = 1.88


# ---------------------------------------------------------------------------
# glTF 2.0 Reader
# ---------------------------------------------------------------------------
def load_glb(path):
    with open(path, "rb") as f:
        magic, ver, length = struct.unpack("<III", f.read(12))
        assert magic == 0x46546C67, f"Not a GLB: {path}"
        clen, ctype = struct.unpack("<II", f.read(8))
        assert ctype == 0x4E4F534A
        gltf = json.loads(f.read(clen).decode("utf-8"))
        blen, btype = struct.unpack("<II", f.read(8))
        assert btype == 0x004E4942
        blob = f.read(blen)
    return gltf, blob


def node_local_matrix(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=np.float64).reshape((4, 4), order="F")
    M = np.eye(4, dtype=np.float64)
    if "translation" in node:
        t = node["translation"]
        M[0, 3], M[1, 3], M[2, 3] = t[0], t[1], t[2]
    if "rotation" in node:
        x, y, z, w = node["rotation"]
        R = np.array([
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0],
            [0, 0, 0, 1],
        ], dtype=np.float64)
        M = M @ R
    if "scale" in node:
        s = node["scale"]
        M = M @ np.diag([s[0], s[1], s[2], 1.0])
    return M


def get_world_matrices(gltf):
    nodes = gltf.get("nodes", [])
    parents = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parents[c] = i
    cache = {}

    def world(i):
        if i in cache:
            return cache[i]
        m = node_local_matrix(nodes[i])
        if i in parents:
            m = world(parents[i]) @ m
        cache[i] = m
        return m

    return [world(i) for i in range(len(nodes))], parents


def read_accessor(gltf, blob, acc_idx):
    acc = gltf["accessors"][acc_idx]
    bv = gltf["bufferViews"][acc["bufferView"]]
    offset = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    comp_map = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
    count_map = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
    dtype = np.dtype(comp_map[acc["componentType"]])
    ncomp = count_map[acc["type"]]
    count = acc["count"]
    elem_bytes = dtype.itemsize * ncomp
    if stride == 0 or stride == elem_bytes:
        arr = np.frombuffer(blob, dtype=dtype, count=count * ncomp, offset=offset)
        arr = arr.reshape((count, ncomp)).copy() if ncomp > 1 else arr.copy()
    else:
        arr = np.empty((count, ncomp) if ncomp > 1 else (count,), dtype=dtype)
        for i in range(count):
            v = np.frombuffer(blob, dtype=dtype, count=ncomp, offset=offset + i * stride)
            arr[i] = v if ncomp > 1 else v[0]
    return arr


# ---------------------------------------------------------------------------
# Geometry Operations (NumPy)
# ---------------------------------------------------------------------------
def compute_smooth_normals(pos, idx):
    """Area-weighted smooth vertex normals."""
    tris = idx.reshape(-1, 3)
    v0 = pos[tris[:, 0]]
    v1 = pos[tris[:, 1]]
    v2 = pos[tris[:, 2]]
    fn = np.cross(v1 - v0, v2 - v0)
    nrm = np.zeros_like(pos, dtype=np.float64)
    np.add.at(nrm, tris[:, 0], fn)
    np.add.at(nrm, tris[:, 1], fn)
    np.add.at(nrm, tris[:, 2], fn)
    lens = np.linalg.norm(nrm, axis=1, keepdims=True)
    lens = np.where(lens < 1e-12, 1.0, lens)
    return (nrm / lens).astype(np.float32)


def extract_primitives(gltf, blob, rotate_y_180=True):
    """Extract all mesh primitives into world space (Godot +Y up, -Z forward)."""
    wm, parents = get_world_matrices(gltf)
    nodes = gltf.get("nodes", [])
    mats = gltf.get("materials", [])
    rot180 = np.diag([-1.0, 1.0, -1.0, 1.0]) if rotate_y_180 else np.eye(4)

    prims = []
    for ni, node in enumerate(nodes):
        if "mesh" not in node:
            continue
        mesh = gltf["meshes"][node["mesh"]]
        M = rot180 @ wm[ni]
        M3 = M[:3, :3]
        det = np.linalg.det(M3)
        if abs(det) < 1e-12:
            continue
        N3 = np.linalg.inv(M3).T
        pname = nodes[parents[ni]].get("name", "") if ni in parents else ""

        for pi, prim in enumerate(mesh["primitives"]):
            if prim.get("mode", 4) != 4:
                continue
            pos = read_accessor(gltf, blob, prim["attributes"]["POSITION"]).astype(np.float64)
            if "indices" in prim:
                idx = read_accessor(gltf, blob, prim["indices"]).astype(np.uint32).reshape(-1)
            else:
                idx = np.arange(len(pos), dtype=np.uint32)
            if len(idx) < 3:
                continue
            idx = idx[: (len(idx) // 3) * 3]

            wpos = (pos @ M3.T) + M[:3, 3]
            if det < 0:
                tris = idx.reshape(-1, 3).copy()
                tris[:, [1, 2]] = tris[:, [2, 1]]
                idx = tris.reshape(-1)

            if "NORMAL" in prim["attributes"]:
                nrm = read_accessor(gltf, blob, prim["attributes"]["NORMAL"]).astype(np.float64)
                wnrm = nrm @ N3.T
                lens = np.linalg.norm(wnrm, axis=1, keepdims=True)
                lens = np.where(lens < 1e-12, 1.0, lens)
                wnrm = (wnrm / lens).astype(np.float32)
            else:
                wnrm = compute_smooth_normals(wpos, idx)

            mat_name = mats[prim["material"]].get("name", "") if "material" in prim else ""
            prims.append({
                "node_name": node.get("name", ""),
                "parent_name": pname,
                "mat_name": mat_name,
                "pos": wpos.astype(np.float32),
                "nrm": wnrm.astype(np.float32),
                "idx": idx.astype(np.uint32),
            })
    return prims


def transform_prims(prims, scale, offset):
    """Apply pos = (pos + offset) * scale uniformly."""
    off = np.asarray(offset, dtype=np.float32)
    sc = np.float32(scale)
    for p in prims:
        p["pos"] = (p["pos"] + off) * sc


def translate_prim(p, delta):
    p["pos"] = p["pos"] + np.asarray(delta, dtype=np.float32)


def clone_prim(p, delta=None, mat_key=None):
    c = {
        "node_name": p.get("node_name", ""),
        "parent_name": p.get("parent_name", ""),
        "mat_name": p.get("mat_name", ""),
        "mat_key": mat_key if mat_key is not None else p.get("mat_key", "plastic_dark"),
        "pos": p["pos"].copy(),
        "nrm": p["nrm"].copy(),
        "idx": p["idx"].copy(),
    }
    if delta is not None:
        c["pos"] = c["pos"] + np.asarray(delta, dtype=np.float32)
    return c


def bbox_of(prims):
    mn = np.array([1e9, 1e9, 1e9], dtype=np.float64)
    mx = np.array([-1e9, -1e9, -1e9], dtype=np.float64)
    for p in prims:
        if len(p["pos"]) == 0:
            continue
        mn = np.minimum(mn, p["pos"].min(axis=0))
        mx = np.maximum(mx, p["pos"].max(axis=0))
    return mn, mx


def split_prim_by_axis(p, axis, thresh=0.0):
    """Split a primitive into low (coord < thresh) and high (coord >= thresh) by triangle centroid."""
    pos, nrm, idx = p["pos"], p["nrm"], p["idx"]
    tris = idx.reshape(-1, 3)
    c = pos[tris, axis].mean(axis=1)
    out = []
    for mask in (c < thresh, c >= thresh):
        sub_tris = tris[mask]
        if len(sub_tris) == 0:
            out.append(None)
            continue
        uniq, inv = np.unique(sub_tris.reshape(-1), return_inverse=True)
        out.append({
            "node_name": p.get("node_name", ""),
            "parent_name": p.get("parent_name", ""),
            "mat_name": p.get("mat_name", ""),
            "mat_key": p.get("mat_key", "plastic_dark"),
            "pos": pos[uniq].copy(),
            "nrm": nrm[uniq].copy(),
            "idx": inv.astype(np.uint32),
        })
    return out[0], out[1]


def split_prim_by_x(p, x_thresh=0.0):
    return split_prim_by_axis(p, 0, x_thresh)


def merge_prims_by_mat(prims):
    """Group primitives by mat_key and merge vertex/index buffers cleanly."""
    groups = {}
    for p in prims:
        if p is None or len(p["idx"]) < 3:
            continue
        mk = p.get("mat_key", "plastic_dark")
        groups.setdefault(mk, []).append(p)
    merged = []
    for mk, plist in groups.items():
        pos_list, nrm_list, idx_list = [], [], []
        v_off = 0
        for p in plist:
            pos_list.append(p["pos"])
            nrm_list.append(p["nrm"])
            idx_list.append(p["idx"] + np.uint32(v_off))
            v_off += len(p["pos"])
        merged.append({
            "mat_key": mk,
            "pos": np.concatenate(pos_list, axis=0).astype(np.float32),
            "nrm": np.concatenate(nrm_list, axis=0).astype(np.float32),
            "idx": np.concatenate(idx_list, axis=0).astype(np.uint32),
        })
    return merged


def simplify_prim_grid(p, cell_size):
    """Fast vertex-grid clustering preserving smooth normals and removing degenerate triangles."""
    pos, nrm, idx = p["pos"], p["nrm"], p["idx"]
    if len(idx) // 3 < 600:
        return p
    q = np.floor(pos / np.float32(cell_size)).astype(np.int32)
    # Pack 3D integer cell coords into structured array for fast np.unique
    q_view = np.ascontiguousarray(q).view(np.dtype((np.void, q.dtype.itemsize * 3))).reshape(-1)
    _, first_idx, inv = np.unique(q_view, return_index=True, return_inverse=True)
    n_new = len(first_idx)
    if n_new >= len(pos) * 0.92:
        return p

    # Average positions & normals per cell
    counts = np.bincount(inv, minlength=n_new).astype(np.float32)[:, None]
    new_pos = np.zeros((n_new, 3), dtype=np.float32)
    new_nrm = np.zeros((n_new, 3), dtype=np.float32)
    for ax in range(3):
        new_pos[:, ax] = np.bincount(inv, weights=pos[:, ax], minlength=n_new)
        new_nrm[:, ax] = np.bincount(inv, weights=nrm[:, ax], minlength=n_new)
    new_pos /= counts
    nlens = np.linalg.norm(new_nrm, axis=1, keepdims=True)
    nlens = np.where(nlens < 1e-8, 1.0, nlens)
    new_nrm /= nlens

    tris = inv[idx].reshape(-1, 3)
    valid = (tris[:, 0] != tris[:, 1]) & (tris[:, 1] != tris[:, 2]) & (tris[:, 0] != tris[:, 2])
    tris = tris[valid]
    if len(tris) < 12:
        return p

    # Compact unused vertices
    uniq, inv2 = np.unique(tris.reshape(-1), return_inverse=True)
    return {
        "mat_key": p["mat_key"],
        "pos": new_pos[uniq].astype(np.float32),
        "nrm": new_nrm[uniq].astype(np.float32),
        "idx": inv2.astype(np.uint32),
    }


def make_box_prim(center, size, mat_key):
    cx, cy, cz = center
    hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
    faces = [
        # (normal, 4 corners CCW)
        ((0, 0, 1), [(-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]),
        ((0, 0, -1), [(hx, -hy, -hz), (-hx, -hy, -hz), (-hx, hy, -hz), (hx, hy, -hz)]),
        ((1, 0, 0), [(hx, -hy, hz), (hx, -hy, -hz), (hx, hy, -hz), (hx, hy, hz)]),
        ((-1, 0, 0), [(-hx, -hy, -hz), (-hx, -hy, hz), (-hx, hy, hz), (-hx, hy, -hz)]),
        ((0, 1, 0), [(-hx, hy, hz), (hx, hy, hz), (hx, hy, -hz), (-hx, hy, -hz)]),
        ((0, -1, 0), [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz)]),
    ]
    pos, nrm, idx = [], [], []
    for f_nrm, corners in faces:
        base = len(pos)
        for x, y, z in corners:
            pos.append([cx + x, cy + y, cz + z])
            nrm.append(list(f_nrm))
        idx.extend([base, base + 1, base + 2, base, base + 2, base + 3])
    return {
        "mat_key": mat_key,
        "pos": np.array(pos, dtype=np.float32),
        "nrm": np.array(nrm, dtype=np.float32),
        "idx": np.array(idx, dtype=np.uint32),
    }


def make_sculpted_caliper_prim(is_left, is_front, mat_key):
    """Curved brake caliper in local wheel-center coordinates (Godot +Y up, -Z forward)."""
    sign_z = 1.0 if is_front else -1.0  # rear of front rotor (+Z), front of rear rotor (-Z)
    sign_x = -1.0 if is_left else 1.0
    r_in, r_out = 0.145, 0.215
    x0 = -sign_x * 0.015
    x1 = -sign_x * 0.095
    if x0 > x1:
        x0, x1 = x1, x0
    steps = 8
    a0, a1 = -0.48, 0.52

    verts = []
    for i in range(steps + 1):
        t = a0 + (a1 - a0) * (i / steps)
        cz = sign_z * math.cos(t)
        cy = math.sin(t)
        verts.append([x0, cy * r_in, cz * r_in])
        verts.append([x1, cy * r_in, cz * r_in])
        verts.append([x0, cy * r_out, cz * r_out])
        verts.append([x1, cy * r_out, cz * r_out])

    tris = []
    for i in range(steps):
        b0, b1 = i * 4, (i + 1) * 4
        # Outer arc
        tris += [[b0 + 2, b1 + 2, b1 + 3], [b0 + 2, b1 + 3, b0 + 3]]
        # Inner arc
        tris += [[b0 + 1, b1 + 1, b1 + 0], [b0 + 1, b1 + 0, b0 + 0]]
        # Side x0
        tris += [[b0 + 0, b1 + 0, b1 + 2], [b0 + 0, b1 + 2, b0 + 2]]
        # Side x1
        tris += [[b0 + 3, b1 + 3, b1 + 1], [b0 + 3, b1 + 1, b0 + 1]]
    # Caps
    tris += [[0, 2, 3], [0, 3, 1]]
    e = steps * 4
    tris += [[e + 1, e + 3, e + 2], [e + 1, e + 2, e + 0]]

    pos = np.array(verts, dtype=np.float32)
    idx = np.array(tris, dtype=np.uint32).reshape(-1)
    nrm = compute_smooth_normals(pos, idx)
    return {"mat_key": mat_key, "pos": pos, "nrm": nrm, "idx": idx}


def make_wheel_well_liners(wheels_data, mat_key="plastic_dark", r_liner=0.28):
    """
    Create strictly recessed matte-black inner wheelhouse shields tucked well inward
    of the outer fender lip (|x| <= |wc.x| - 0.14m, radius <= 0.28m) so they block
    see-through gaps from 3/4 angles without ever intersecting curved fender lips.
    """
    prims = []
    fl_c = wheels_data["FL"][0]
    fr_c = wheels_data["FR"][0]
    rl_c = wheels_data["RL"][0]
    rr_c = wheels_data["RR"][0]

    # Inner chassis belly/tub blocking cross-car see-through between left & right wells
    mid_z = (fl_c[2] + rl_c[2]) * 0.5
    wb = abs(rl_c[2] - fl_c[2])
    inner_w = max(0.78, (fr_c[0] - fl_c[0]) - 0.72)
    prims.append(make_box_prim((0.0, 0.34, mid_z), (inner_w, 0.26, wb + 0.60), mat_key))

    # Recessed inner wheelhouse shields strictly inward of the wheel hub
    for corner, (wc, _) in wheels_data.items():
        is_left = corner.endswith("L")
        sign_x = -1.0 if is_left else 1.0
        wall_x = wc[0] - sign_x * 0.18
        x_in = wc[0] - sign_x * 0.28
        x_out = wc[0] - sign_x * 0.14
        if x_in > x_out:
            x_in, x_out = x_out, x_in
        steps = 10
        verts, tris = [], []
        for i in range(steps + 1):
            ang = math.radians(-5.0 + 190.0 * (i / steps))
            cz = wc[2] + math.cos(ang) * r_liner
            cy = wc[1] + math.sin(ang) * r_liner
            verts.append([x_in, cy, cz])
            verts.append([x_out, cy, cz])
        for i in range(steps):
            b0, b1 = i * 2, (i + 1) * 2
            tris += [[b0, b1, b1 + 1], [b0, b1 + 1, b0 + 1]]
            tris += [[b0, b1 + 1, b1], [b0, b0 + 1, b1 + 1]]
        c_idx = len(verts)
        verts.append([wall_x, wc[1], wc[2]])
        for i in range(steps):
            b0, b1 = i * 2, (i + 1) * 2
            v0 = b0 if is_left else b0 + 1
            v1 = b1 if is_left else b1 + 1
            tris += [[c_idx, v0, v1], [c_idx, v1, v0]]

        pos = np.array(verts, dtype=np.float32)
        idx = np.array(tris, dtype=np.uint32).reshape(-1)
        prims.append({"mat_key": mat_key, "pos": pos, "nrm": compute_smooth_normals(pos, idx), "idx": idx})
    return prims


def make_torus_steering_wheel(mat_key):
    """Sleek sporty steering wheel centered at local (0,0,0), tilted 22 deg toward driver."""
    R, r = 0.165, 0.020
    n_u, n_v = 24, 10
    pos, idx = [], []
    tilt = math.radians(22.0)
    ct, st = math.cos(tilt), math.sin(tilt)
    for i in range(n_u):
        u = (i / n_u) * 2.0 * math.pi
        cu, su = math.cos(u), math.sin(u)
        for j in range(n_v):
            v = (j / n_v) * 2.0 * math.pi
            cv, sv = math.cos(v), math.sin(v)
            x = (R + r * cv) * cu
            y0 = (R + r * cv) * su
            z0 = r * sv
            # Tilt around X axis
            y = y0 * ct - z0 * st
            z = y0 * st + z0 * ct
            pos.append([x, y, z])
    for i in range(n_u):
        i2 = (i + 1) % n_u
        for j in range(n_v):
            j2 = (j + 1) % n_v
            a = i * n_v + j
            b = i2 * n_v + j
            c = i2 * n_v + j2
            d = i * n_v + j2
            idx.extend([a, b, c, a, c, d])
    pos_arr = np.array(pos, dtype=np.float32)
    idx_arr = np.array(idx, dtype=np.uint32)
    return {"mat_key": mat_key, "pos": pos_arr, "nrm": compute_smooth_normals(pos_arr, idx_arr), "idx": idx_arr}


# ---------------------------------------------------------------------------
# glTF 2.0 Binary (.glb) Writer
# ---------------------------------------------------------------------------
def build_materials(paint_rgb, caliper_rgb, rim_rgb):
    def pbr(name, rgba, metallic=0.0, roughness=0.5, clearcoat=0.0, clearcoat_r=0.04,
            alpha_mode=None, double_sided=False, emissive=None):
        m = {
            "name": name,
            "pbrMetallicRoughness": {
                "baseColorFactor": list(rgba),
                "metallicFactor": metallic,
                "roughnessFactor": roughness,
            },
        }
        if alpha_mode:
            m["alphaMode"] = alpha_mode
        if double_sided:
            m["doubleSided"] = True
        if emissive is not None:
            m["emissiveFactor"] = list(emissive)
        if clearcoat > 0.0:
            m["extensions"] = {
                "KHR_materials_clearcoat": {
                    "clearcoatFactor": clearcoat,
                    "clearcoatRoughnessFactor": clearcoat_r,
                }
            }
        return m

    order = [
        ("paint", pbr("CarPaint_Hero", (*paint_rgb, 1.0), metallic=0.82, roughness=0.13, clearcoat=1.0, clearcoat_r=0.025)),
        ("paint_accent", pbr("CarPaint_Accent", (0.040, 0.044, 0.052, 1.0), metallic=0.35, roughness=0.22, clearcoat=0.8, clearcoat_r=0.06)),
        ("carbon", pbr("Carbon_Fiber", (0.045, 0.048, 0.054, 1.0), metallic=0.28, roughness=0.26, clearcoat=0.75, clearcoat_r=0.08)),
        ("chrome", pbr("Chrome_Trim", (0.90, 0.92, 0.95, 1.0), metallic=0.98, roughness=0.07)),
        ("plastic_dark", pbr("Trim_Dark", (0.020, 0.022, 0.025, 1.0), metallic=0.04, roughness=0.78)),
        ("interior", pbr("Interior_Dark", (0.045, 0.048, 0.054, 1.0), metallic=0.0, roughness=0.76)),
        ("interior_leather", pbr("Interior_Leather", (0.088, 0.076, 0.070, 1.0), metallic=0.0, roughness=0.58)),
        ("glass", pbr("Glass_Tinted", (0.04, 0.068, 0.095, 0.34), metallic=0.10, roughness=0.04, clearcoat=1.0, clearcoat_r=0.02, alpha_mode="BLEND", double_sided=True)),
        ("tire", pbr("Tire_Rubber", (0.018, 0.019, 0.022, 1.0), metallic=0.0, roughness=0.88)),
        ("rim", pbr("Alloy_Rim", (*rim_rgb, 1.0), metallic=0.94, roughness=0.18)),
        ("rotor", pbr("Brake_Rotor", (0.58, 0.60, 0.64, 1.0), metallic=0.92, roughness=0.28)),
        ("caliper", pbr("Brake_Caliper", (*caliper_rgb, 1.0), metallic=0.48, roughness=0.22, clearcoat=0.85, clearcoat_r=0.05)),
        ("headlight", pbr("Headlight_Emissive", (0.96, 0.97, 1.0, 1.0), metallic=0.1, roughness=0.08, emissive=(1.0, 0.97, 0.88))),
        ("taillight", pbr("Taillight_Emissive", (0.26, 0.012, 0.015, 1.0), metallic=0.1, roughness=0.08, clearcoat=1.0, clearcoat_r=0.04, emissive=(0.45, 0.01, 0.01))),
        ("reverselight", pbr("Reverselight_Emissive", (0.86, 0.88, 0.92, 1.0), metallic=0.1, roughness=0.12, emissive=(0.12, 0.13, 0.14))),
    ]
    mat_list = [m for _, m in order]
    mat_map = {k: i for i, (k, _) in enumerate(order)}
    return mat_list, mat_map


def export_rigged_glb(out_path, paint_rgb, caliper_rgb, rim_rgb,
                      body_groups, steering_data, wheels_data, calipers_data):
    """
    Write clean uncompressed glTF 2.0 GLB with exact Godot hierarchy:
      AssetRoot
        ├── Body_Shell, Body_Trim, Body_Interior, Body_Glass,
        │   Headlight_Main, Taillight_Main, Reverselight_Main, SteeringWheel
        ├── Brake_FL, Brake_FR, Brake_RL, Brake_RR (translation = wheel_center)
        └── Wheel_{FL,FR,RL,RR}_Pivot (translation = wheel_center)
             └── Tire_{FL,FR,RL,RR} (local 0,0,0)
    """
    mat_list, mat_map = build_materials(paint_rgb, caliper_rgb, rim_rgb)
    bin_chunks = []
    bin_len = 0
    buffer_views = []
    accessors = []
    meshes = []
    nodes = [{"name": "AssetRoot", "children": []}]

    def append_bytes(data_bytes, target=None):
        nonlocal bin_len
        pad = (4 - (bin_len % 4)) % 4
        if pad:
            bin_chunks.append(b"\x00" * pad)
            bin_len += pad
        offset = bin_len
        bin_chunks.append(data_bytes)
        bin_len += len(data_bytes)
        bv = {"buffer": 0, "byteOffset": offset, "byteLength": len(data_bytes)}
        if target is not None:
            bv["target"] = target
        idx = len(buffer_views)
        buffer_views.append(bv)
        return idx

    def add_mesh(mesh_name, prim_list):
        gltf_prims = []
        tri_count = 0
        for p in prim_list:
            pos = np.ascontiguousarray(p["pos"], dtype=np.float32)
            nrm = np.ascontiguousarray(p["nrm"], dtype=np.float32)
            idx = np.ascontiguousarray(p["idx"], dtype=np.uint32)
            if len(pos) == 0 or len(idx) < 3:
                continue
            tri_count += len(idx) // 3

            bv_pos = append_bytes(pos.tobytes(), 34962)
            acc_pos = len(accessors)
            accessors.append({
                "bufferView": bv_pos, "componentType": 5126, "count": len(pos), "type": "VEC3",
                "min": [float(x) for x in pos.min(axis=0)],
                "max": [float(x) for x in pos.max(axis=0)],
            })

            bv_nrm = append_bytes(nrm.tobytes(), 34962)
            acc_nrm = len(accessors)
            accessors.append({
                "bufferView": bv_nrm, "componentType": 5126, "count": len(nrm), "type": "VEC3",
            })

            if len(pos) < 65535:
                idx_u16 = np.ascontiguousarray(idx, dtype=np.uint16)
                bv_idx = append_bytes(idx_u16.tobytes(), 34963)
                comp_t = 5123
            else:
                bv_idx = append_bytes(idx.tobytes(), 34963)
                comp_t = 5125
            acc_idx = len(accessors)
            accessors.append({
                "bufferView": bv_idx, "componentType": comp_t, "count": len(idx), "type": "SCALAR",
            })

            gltf_prims.append({
                "attributes": {"POSITION": acc_pos, "NORMAL": acc_nrm},
                "indices": acc_idx,
                "material": mat_map.get(p["mat_key"], mat_map["plastic_dark"]),
                "mode": 4,
            })
        if not gltf_prims:
            return None, 0
        m_idx = len(meshes)
        meshes.append({"name": mesh_name, "primitives": gltf_prims})
        return m_idx, tri_count

    total_tris = 0
    for name, prim_list in body_groups:
        m_idx, tc = add_mesh(name, prim_list)
        if m_idx is not None:
            ni = len(nodes)
            nodes.append({"name": name, "mesh": m_idx})
            nodes[0]["children"].append(ni)
            total_tris += tc

    if steering_data is not None:
        scenter, sprims = steering_data
        m_idx, tc = add_mesh("SteeringWheel", sprims)
        if m_idx is not None:
            ni = len(nodes)
            nodes.append({"name": "SteeringWheel", "mesh": m_idx, "translation": [float(x) for x in scenter]})
            nodes[0]["children"].append(ni)
            total_tris += tc

    for corner in ("FL", "FR", "RL", "RR"):
        wcenter, wprims = wheels_data[corner]
        m_idx, tc = add_mesh(f"Tire_{corner}", wprims)
        assert m_idx is not None, f"Empty tire mesh for {corner}"
        tire_ni = len(nodes)
        nodes.append({"name": f"Tire_{corner}", "mesh": m_idx})
        piv_ni = len(nodes)
        nodes.append({
            "name": f"Wheel_{corner}_Pivot",
            "translation": [float(x) for x in wcenter],
            "children": [tire_ni],
        })
        nodes[0]["children"].append(piv_ni)
        total_tris += tc

        if corner in calipers_data and calipers_data[corner] is not None:
            ccenter, cprims = calipers_data[corner]
            cm_idx, ctc = add_mesh(f"Brake_{corner}", cprims)
            if cm_idx is not None:
                cni = len(nodes)
                nodes.append({
                    "name": f"Brake_{corner}",
                    "mesh": cm_idx,
                    "translation": [float(x) for x in ccenter],
                })
                nodes[0]["children"].append(cni)
                total_tris += ctc

    bin_data = b"".join(bin_chunks)
    pad = (4 - (len(bin_data) % 4)) % 4
    if pad:
        bin_data += b"\x00" * pad

    gltf_out = {
        "asset": {"version": "2.0", "generator": "AsterValley Vehicle Normalizer (Python/NumPy)"},
        "extensionsUsed": ["KHR_materials_clearcoat"],
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [0]}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": mat_list,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_data)}],
    }

    json_bytes = json.dumps(gltf_out, separators=(",", ":")).encode("utf-8")
    jpad = (4 - (len(json_bytes) % 4)) % 4
    if jpad:
        json_bytes += b" " * jpad

    total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_data)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total_len))
        f.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(bin_data), 0x004E4942))
        f.write(bin_data)

    mb = os.path.getsize(out_path) / (1024 * 1024)
    print(f"  WROTE {os.path.basename(out_path)}: {total_tris:,} tris, {mb:.2f} MB")


# ---------------------------------------------------------------------------
# Car 1: VELA GT — Porsche 911 (porsche_911.glb)
# ---------------------------------------------------------------------------
def build_vela_gt():
    print("\n================ BUILDING vela_gt.glb (Porsche 911) ================")
    gltf, blob = load_glb(os.path.join(RAW_DIR, "porsche_911.glb"))
    prims = extract_primitives(gltf, blob, rotate_y_180=True)

    # Identify rear (Cylinder.000_*) & front (Cylinder.001_*) wheel axles
    # After 180° Y rot: front is at Z ≈ -2.11, rear is at Z ≈ +2.02
    rear_w = [p for p in prims if p["node_name"].startswith("Cylinder.000_")]
    front_w = [p for p in prims if p["node_name"].startswith("Cylinder.001_")]
    rear_rubber = [p for p in rear_w if p["node_name"] == "Cylinder.000_2"][0]
    front_rubber = [p for p in front_w if p["node_name"] == "Cylinder.001_2"][0]

    rmn, rmx = bbox_of([rear_rubber])
    fmn, fmx = bbox_of([front_rubber])
    rear_z = (rmn[2] + rmx[2]) * 0.5
    front_z = (fmn[2] + fmx[2]) * 0.5
    raw_wb = rear_z - front_z
    scale = TARGET_WHEELBASE / raw_wb
    mid_x = (rmn[0] + rmx[0]) * 0.5
    mid_z = (rear_z + front_z) * 0.5
    min_y = rmn[1]

    transform_prims(prims, scale, (-mid_x, -min_y, -mid_z))

    # Recompute front axle Z after scaling
    fmn2, fmx2 = bbox_of([front_rubber])
    front_z_scaled = (fmn2[2] + fmx2[2]) * 0.5

    # Split straight rear axle into RL (x < 0) and RR (x >= 0)
    rl_parts, rr_parts, rl_cal_parts, rr_cal_parts = [], [], [], []
    for p in rear_w:
        n = p["node_name"]
        if n.endswith("_0"):
            p["mat_key"] = "rim"
            l, r = split_prim_by_x(p, 0.0)
            rl_parts.append(l); rr_parts.append(r)
        elif n.endswith("_1"):
            p["mat_key"] = "rotor"
            l, r = split_prim_by_x(p, 0.0)
            rl_parts.append(l); rr_parts.append(r)
        elif n.endswith("_2"):
            p["mat_key"] = "tire"
            l, r = split_prim_by_x(p, 0.0)
            rl_parts.append(l); rr_parts.append(r)
        elif n.endswith("_3"):
            p["mat_key"] = "caliper"
            l, r = split_prim_by_x(p, 0.0)
            rl_cal_parts.append(l); rr_cal_parts.append(r)

    rl_mn, rl_mx = bbox_of(rl_parts)
    rr_mn, rr_mx = bbox_of(rr_parts)
    rl_c = (rl_mn + rl_mx) * 0.5
    rr_c = (rr_mn + rr_mx) * 0.5
    dz_front = front_z_scaled - rl_c[2]
    fl_c = rl_c + np.array([0.0, 0.0, dz_front])
    fr_c = rr_c + np.array([0.0, 0.0, dz_front])

    def center_and_simplify_wheel(plist, center):
        out = []
        for p in merge_prims_by_mat(plist):
            p["pos"] = p["pos"] - center.astype(np.float32)
            out.append(simplify_prim_grid(p, 0.010))
        return out

    rl_wheel = center_and_simplify_wheel(rl_parts, rl_c)
    rr_wheel = center_and_simplify_wheel(rr_parts, rr_c)
    fl_wheel = [clone_prim(p) for p in rl_wheel]
    fr_wheel = [clone_prim(p) for p in rr_wheel]

    wheels_data = {
        "FL": (fl_c, fl_wheel), "FR": (fr_c, fr_wheel),
        "RL": (rl_c, rl_wheel), "RR": (rr_c, rr_wheel),
    }

    rl_cal = center_and_simplify_wheel(rl_cal_parts, rl_c)
    rr_cal = center_and_simplify_wheel(rr_cal_parts, rr_c)
    calipers_data = {
        "FL": (fl_c, [clone_prim(p) for p in rl_cal]),
        "FR": (fr_c, [clone_prim(p) for p in rr_cal]),
        "RL": (rl_c, rl_cal),
        "RR": (rr_c, rr_cal),
    }

    # Classify body meshes (skip redundant 'coat' overlay and stray planes!)
    wheel_set = set(id(p) for p in rear_w + front_w)
    shell, trim, interior, glass, head, tail = [], [], [], [], [], []
    for p in prims:
        if id(p) in wheel_set:
            continue
        nn = p["node_name"].lower()
        mn = p["mat_name"].lower()
        if "plane.005" in nn or "plane.006" in nn or mn == "coat":
            continue
        pmn, pmx = bbox_of([p])
        cz = (pmn[2] + pmx[2]) * 0.5
        if mn == "paint":
            p["mat_key"] = "paint"; shell.append(p)
        elif mn in ("window", "glass"):
            p["mat_key"] = "glass"; glass.append(p)
        elif mn == "lights":
            if cz < 0.0:
                p["mat_key"] = "headlight"; head.append(p)
            else:
                p["mat_key"] = "taillight"; tail.append(p)
        elif mn == "tex_shiny":
            # Keep center rear badge/license bar (boot.003_0 or |x| <= 0.38) AND upper engine decklid
            # louvers (y > 0.71 or z < 1.92) in dark trim; only outer rear bumper taillight clusters go to Taillight_Main!
            if cz > 1.4 and "boot.003" not in nn:
                lower_p, upper_louvers = split_prim_by_axis(p, 1, 0.71)
                if upper_louvers is not None:
                    upper_louvers["mat_key"] = "plastic_dark"; trim.append(upper_louvers)
                if lower_p is not None:
                    front_louver, rear_tail = split_prim_by_axis(lower_p, 2, 1.92)
                    if front_louver is not None:
                        front_louver["mat_key"] = "plastic_dark"; trim.append(front_louver)
                    if rear_tail is not None:
                        left_outer, rest = split_prim_by_x(rear_tail, -0.38)
                        center_bar, right_outer = split_prim_by_x(rest, 0.38) if rest is not None else (None, None)
                        if left_outer is not None:
                            left_outer["mat_key"] = "taillight"; tail.append(left_outer)
                        if right_outer is not None:
                            right_outer["mat_key"] = "taillight"; tail.append(right_outer)
                        if center_bar is not None:
                            center_bar["mat_key"] = "plastic_dark"; trim.append(center_bar)
            else:
                p["mat_key"] = "plastic_dark" if cz > 1.4 else "chrome"
                trim.append(p)
        elif mn == "full_black":
            p["mat_key"] = "interior"; interior.append(p)
        elif mn == "silver":
            p["mat_key"] = "chrome"; trim.append(p)
        else:
            p["mat_key"] = "plastic_dark"; trim.append(p)

    # Add matte-black inner wheel-well liners behind all 4 wheels
    trim.extend(make_wheel_well_liners(wheels_data))

    # Finer simplification on Body_Shell so Porsche curves have zero seams
    shell_m = [simplify_prim_grid(p, 0.009) for p in merge_prims_by_mat(shell)]
    trim_m = [simplify_prim_grid(p, 0.015) for p in merge_prims_by_mat(trim)]
    int_m = [simplify_prim_grid(p, 0.018) for p in merge_prims_by_mat(interior)]
    glass_m = [simplify_prim_grid(p, 0.014) for p in merge_prims_by_mat(glass)]
    head_m = [simplify_prim_grid(p, 0.010) for p in merge_prims_by_mat(head)]
    tail_m = [simplify_prim_grid(p, 0.010) for p in merge_prims_by_mat(tail)]

    bmn, bmx = bbox_of(shell_m)
    rev_m = [
        make_box_prim((-0.44, 0.68, bmx[2] - 0.14), (0.14, 0.04, 0.04), "reverselight"),
        make_box_prim((0.44, 0.68, bmx[2] - 0.14), (0.14, 0.04, 0.04), "reverselight"),
    ]
    sw_data = (np.array([-0.34, 0.84, -0.30]), [make_torus_steering_wheel("interior_leather")])

    export_rigged_glb(
        os.path.join(OUT_DIR, "vela_gt.glb"),
        paint_rgb=(0.06, 0.22, 0.50),      # Deep Metallic Sapphire Blue
        caliper_rgb=(0.84, 0.07, 0.06),    # Guards Red calipers
        rim_rgb=(0.82, 0.85, 0.89),        # Brushed Silver rims
        body_groups=[
            ("Body_Shell", shell_m), ("Body_Trim", trim_m), ("Body_Interior", int_m),
            ("Body_Glass", glass_m), ("Headlight_Main", head_m),
            ("Taillight_Main", tail_m), ("Reverselight_Main", rev_m),
        ],
        steering_data=sw_data,
        wheels_data=wheels_data,
        calipers_data=calipers_data,
    )


# ---------------------------------------------------------------------------
# Car 2: ORION RS — Khronos Group CarConcept (car_concept.glb)
# ---------------------------------------------------------------------------
def build_orion_rs():
    print("\n================ BUILDING orion_rs.glb (Khronos CarConcept) ================")
    gltf, blob = load_glb(os.path.join(RAW_DIR, "car_concept.glb"))
    prims = extract_primitives(gltf, blob, rotate_y_180=True)

    w_groups = {"FL": [], "FR": [], "RL": [], "RR": []}
    cal_set = set()
    for p in prims:
        pn, nn = p["parent_name"], p["node_name"].lower()
        corner = None
        if pn == "WheelFrontL" or "wheelfrontl" in nn:
            corner = "FL"
        elif pn == "WheelFrontR" or "wheelfrontr" in nn:
            corner = "FR"
        elif pn == "WheelRearL" or "wheelrearl" in nn:
            corner = "RL"
        elif pn == "WheelRearR" or "wheelrearr" in nn:
            corner = "RR"
        if corner:
            if "brakepad" in nn:
                cal_set.add(id(p))
            else:
                w_groups[corner].append(p)

    def gc(plist):
        mn, mx = bbox_of(plist)
        return (mn + mx) * 0.5, mn, mx

    fl_c, _, _ = gc(w_groups["FL"])
    fr_c, _, _ = gc(w_groups["FR"])
    rl_c, rl_mn, rl_mx = gc(w_groups["RL"])
    rr_c, _, _ = gc(w_groups["RR"])

    raw_wb = ((rl_c[2] + rr_c[2]) * 0.5) - ((fl_c[2] + fr_c[2]) * 0.5)
    scale = TARGET_WHEELBASE / raw_wb
    mid_x = (rl_c[0] + rr_c[0]) * 0.5
    mid_z = (fl_c[2] + fr_c[2] + rl_c[2] + rr_c[2]) * 0.25
    min_y = rl_mn[1]

    transform_prims(prims, scale, (-mid_x, -min_y, -mid_z))

    fl_c2, _, _ = gc(w_groups["FL"])
    fr_c2, _, _ = gc(w_groups["FR"])
    rl_c2, rl_mn2, rl_mx2 = gc(w_groups["RL"])
    rr_c2, _, _ = gc(w_groups["RR"])

    for corner in ("RL", "RR"):
        for p in w_groups[corner]:
            nn = p["node_name"].lower()
            if "rim" in nn:
                p["mat_key"] = "rim"
            elif "disc" in nn:
                p["mat_key"] = "rotor"
            else:
                p["mat_key"] = "tire"

    # Normalize wheel radius to ~0.365m so garage preview & live arch clearance match cleanly
    cur_r = (rl_mx2[1] - rl_mn2[1]) * 0.5
    w_scale = (0.365 / cur_r) if cur_r > 0.39 else 1.0

    def prep_wheel(plist, center):
        out = []
        for p in merge_prims_by_mat(plist):
            p["pos"] = (p["pos"] - center.astype(np.float32)) * np.float32(w_scale)
            out.append(simplify_prim_grid(p, 0.008))
        return out

    rl_w = prep_wheel(w_groups["RL"], rl_c2)
    rr_w = prep_wheel(w_groups["RR"], rr_c2)

    # Drop body & wheel centers slightly if wheel radius shrank so tires rest at Y=0
    dy_drop = (rl_c2[1] - cur_r * w_scale)
    if abs(dy_drop) > 1e-4:
        for p in prims:
            p["pos"][:, 1] -= np.float32(dy_drop)
        rl_c2[1] -= dy_drop; rr_c2[1] -= dy_drop; fl_c2[1] -= dy_drop; fr_c2[1] -= dy_drop

    dz_f = ((fl_c2[2] + fr_c2[2]) * 0.5) - ((rl_c2[2] + rr_c2[2]) * 0.5)
    fl_cf = rl_c2 + np.array([0.0, 0.0, dz_f])
    fr_cf = rr_c2 + np.array([0.0, 0.0, dz_f])

    wheels_data = {
        "FL": (fl_cf, [clone_prim(p) for p in rl_w]),
        "FR": (fr_cf, [clone_prim(p) for p in rr_w]),
        "RL": (rl_c2, rl_w),
        "RR": (rr_c2, rr_w),
    }
    calipers_data = {
        c: (wheels_data[c][0], [make_sculpted_caliper_prim(c.endswith("L"), c.startswith("F"), "caliper")])
        for c in ("FL", "FR", "RL", "RR")
    }

    skip = cal_set | set(id(p) for k in w_groups for p in w_groups[k])
    shell, trim, interior, glass, head, tail, rev, steer = [], [], [], [], [], [], [], []
    for p in prims:
        if id(p) in skip:
            continue
        nn = p["node_name"].lower()
        mn = p["mat_name"].lower()
        if "steeringwheel" in nn or "steeringemblem" in nn:
            p["mat_key"] = "interior_leather"; steer.append(p)
        elif "headlight" in nn or "headlight" in mn:
            p["mat_key"] = "headlight"; head.append(p)
        elif ("taillight" in nn and "panel" not in nn) or "brakelight" in mn:
            p["mat_key"] = "taillight"; tail.append(p)
        elif "turnsignal" in nn or "signallight" in mn:
            p["mat_key"] = "reverselight"; rev.append(p)
        elif "glass" in mn or "window" in nn or "windshield" in nn:
            if "gasket" in nn or "wiper" in nn:
                p["mat_key"] = "plastic_dark"; trim.append(p)
            else:
                p["mat_key"] = "glass"; glass.append(p)
        elif "paint 1" in mn:
            p["mat_key"] = "paint"; shell.append(p)
        elif "paint 2" in mn:
            p["mat_key"] = "paint_accent"; trim.append(p)
        elif "interior" in nn or "interior" in mn or "dashboard" in mn or "floormat" in mn:
            p["mat_key"] = "interior_leather" if "seat" in nn else "interior"
            interior.append(p)
        elif "mirror" in mn or "hardware" in mn:
            p["mat_key"] = "chrome"; trim.append(p)
        else:
            p["mat_key"] = "plastic_dark"; trim.append(p)

    # Add matte-black inner wheel-well liners behind all 4 wheels
    trim.extend(make_wheel_well_liners(wheels_data))

    # Keep Body_Shell un-simplified to preserve 100% original smooth automotive normals!
    shell_m = merge_prims_by_mat(shell)
    trim_m = [simplify_prim_grid(p, 0.012) for p in merge_prims_by_mat(trim)]
    int_m = [simplify_prim_grid(p, 0.014) for p in merge_prims_by_mat(interior)]
    glass_m = merge_prims_by_mat(glass)
    head_m = merge_prims_by_mat(head)
    tail_m = merge_prims_by_mat(tail)
    rev_m = merge_prims_by_mat(rev)

    sw_data = None
    if steer:
        smn, smx = bbox_of(steer)
        sc = (smn + smx) * 0.5
        sw_m = merge_prims_by_mat(steer)
        for p in sw_m:
            p["pos"] = p["pos"] - sc.astype(np.float32)
        sw_data = (sc, sw_m)

    export_rigged_glb(
        os.path.join(OUT_DIR, "orion_rs.glb"),
        paint_rgb=(0.018, 0.21, 0.135),    # Deep British Racing / Aston Emerald Metallic
        caliper_rgb=(0.96, 0.48, 0.04),    # Track Orange calipers
        rim_rgb=(0.32, 0.35, 0.40),        # Satin Gunmetal Alloy
        body_groups=[
            ("Body_Shell", shell_m), ("Body_Trim", trim_m), ("Body_Interior", int_m),
            ("Body_Glass", glass_m), ("Headlight_Main", head_m),
            ("Taillight_Main", tail_m), ("Reverselight_Main", rev_m),
        ],
        steering_data=sw_data,
        wheels_data=wheels_data,
        calipers_data=calipers_data,
    )


# ---------------------------------------------------------------------------
# Car 3: KESTREL XR — Porsche 918 Spyder Weissach (porsche_918.glb)
# ---------------------------------------------------------------------------
def build_kestrel_xr():
    print("\n================ BUILDING kestrel_xr.glb (Porsche 918 Spyder) ================")
    gltf, blob = load_glb(os.path.join(RAW_DIR, "porsche_918.glb"))
    prims = extract_primitives(gltf, blob, rotate_y_180=True)

    # Identify all 4 wheels & calipers by position after 180° Y rotation!
    # Tires: Object_4.001..004, Rims: p918_rim_wei*, Rotors: amdb11_brake / amdb11_misc, Calipers: amdb11_caliper / amdb11_misc_chrome / amdb11_badging
    w_groups = {"FL": [], "FR": [], "RL": [], "RR": []}
    cal_groups = {"FL": [], "FR": [], "RL": [], "RR": []}
    wheel_ids = set()

    for p in prims:
        nn = p["node_name"].lower()
        mn = p["mat_name"].lower()
        is_tire = nn.startswith("object_4.") and mn == "scene_-_root"
        is_rim = "918weissach_wheel" in mn or "p918_rim_wei" in nn
        is_rotor = mn in ("amdb11_brake", "amdb11_misc")
        is_cal = mn in ("amdb11_caliper", "amdb11_misc_chrome", "amdb11_badging")
        if is_tire or is_rim or is_rotor or is_cal:
            pmn, pmx = bbox_of([p])
            pc = (pmn + pmx) * 0.5
            corner = ("F" if pc[2] < 0.0 else "R") + ("L" if pc[0] < 0.0 else "R")
            wheel_ids.add(id(p))
            if is_cal:
                p["mat_key"] = "caliper" if mn == "amdb11_caliper" else "chrome"
                cal_groups[corner].append(p)
            else:
                p["mat_key"] = "tire" if is_tire else ("rim" if is_rim else "rotor")
                w_groups[corner].append(p)

    def gc(plist):
        mn, mx = bbox_of(plist)
        return (mn + mx) * 0.5, mn, mx

    fl_c, fl_mn, _ = gc(w_groups["FL"])
    fr_c, _, _ = gc(w_groups["FR"])
    rl_c, rl_mn, _ = gc(w_groups["RL"])
    rr_c, _, _ = gc(w_groups["RR"])

    raw_wb = ((rl_c[2] + rr_c[2]) * 0.5) - ((fl_c[2] + fr_c[2]) * 0.5)
    scale = TARGET_WHEELBASE / raw_wb
    mid_x = (fl_c[0] + fr_c[0] + rl_c[0] + rr_c[0]) * 0.25
    mid_z = (fl_c[2] + fr_c[2] + rl_c[2] + rr_c[2]) * 0.25
    min_y = min(fl_mn[1], rl_mn[1])

    transform_prims(prims, scale, (-mid_x, -min_y, -mid_z))

    wheels_data = {}
    calipers_data = {}
    for corner in ("FL", "FR", "RL", "RR"):
        wc, _, _ = gc(w_groups[corner])
        wm = []
        for p in merge_prims_by_mat(w_groups[corner]):
            p["pos"] = p["pos"] - wc.astype(np.float32)
            wm.append(simplify_prim_grid(p, 0.012))
        wheels_data[corner] = (wc, wm)

        cm = []
        for p in merge_prims_by_mat(cal_groups[corner]):
            p["pos"] = p["pos"] - wc.astype(np.float32)
            cm.append(simplify_prim_grid(p, 0.010))
        calipers_data[corner] = (wc, cm)

    shell, trim, interior, glass, head, tail, rev, steer = [], [], [], [], [], [], [], []
    for p in prims:
        if id(p) in wheel_ids:
            continue
        nn = p["node_name"].lower()
        mn = p["mat_name"].lower()
        if "p918_steer" in nn:
            p["mat_key"] = "interior_leather"; steer.append(p)
        elif "revlight" in mn:
            p["mat_key"] = "reverselight"; rev.append(p)
        elif "taillight" in mn or "bump_rear_ok" in mn or "headlight" in mn or "light_front" in mn or "light_ref_front" in mn:
            # Split strictly by Z: front (Z < -0.5) -> cool-white Headlight_Main; rear (Z > 0.5) -> ruby Taillight_Main!
            front_part, rest_part = split_prim_by_axis(p, 2, -0.5)
            mid_part, rear_part = split_prim_by_axis(rest_part, 2, 0.5) if rest_part is not None else (None, None)
            if front_part is not None:
                front_part["mat_key"] = "headlight"; head.append(front_part)
            if rear_part is not None:
                rear_part["mat_key"] = "taillight"; tail.append(rear_part)
            if mid_part is not None:
                mid_part["mat_key"] = "plastic_dark"; trim.append(mid_part)
        elif "glass" in mn or "windscreen" in mn:
            p["mat_key"] = "glass"; glass.append(p)
        elif "p918_paint" in mn or "bonnet_ok" in mn:
            p["mat_key"] = "paint"; shell.append(p)
        elif "carbon" in mn or "besi" in mn:
            # Use dark satin carbon for side-intake/engine bezels (eliminates bright pale seam on rear quarter!)
            p["mat_key"] = "carbon"; trim.append(p)
        elif "ext_details_rim" in mn:
            p["mat_key"] = "chrome"; trim.append(p)
        elif any(k in mn for k in ("interior", "int_s", "leather", "seat", "dash", "lcd", "tombol", "storege", "tahook")):
            p["mat_key"] = "interior_leather" if ("leather" in mn or "seat" in mn) else "interior"
            interior.append(p)
        else:
            p["mat_key"] = "plastic_dark"; trim.append(p)

    # Add strictly recessed matte-black inner wheelhouse shields (never intersects fenders!)
    trim.extend(make_wheel_well_liners(wheels_data, r_liner=0.28))

    # Keep Body_Shell un-simplified to preserve 100% original razor-sharp Porsche 918 normals (zero seam!)
    shell_m = merge_prims_by_mat(shell)
    trim_m = [simplify_prim_grid(p, 0.012) for p in merge_prims_by_mat(trim)]
    int_m = [simplify_prim_grid(p, 0.016) for p in merge_prims_by_mat(interior)]
    glass_m = merge_prims_by_mat(glass)
    head_m = merge_prims_by_mat(head)
    tail_m = merge_prims_by_mat(tail)
    rev_m = merge_prims_by_mat(rev)
    if not rev_m:
        bmn, bmx = bbox_of(shell_m)
        rev_m = [
            make_box_prim((-0.36, 0.58, bmx[2] - 0.10), (0.14, 0.035, 0.035), "reverselight"),
            make_box_prim((0.36, 0.58, bmx[2] - 0.10), (0.14, 0.035, 0.035), "reverselight"),
        ]

    sw_data = None
    if steer:
        smn, smx = bbox_of(steer)
        sc = (smn + smx) * 0.5
        sw_m = [simplify_prim_grid(p, 0.008) for p in merge_prims_by_mat(steer)]
        for p in sw_m:
            p["pos"] = p["pos"] - sc.astype(np.float32)
        sw_data = (sc, sw_m)

    export_rigged_glb(
        os.path.join(OUT_DIR, "kestrel_xr.glb"),
        paint_rgb=(0.74, 0.045, 0.065),    # Exotic Rosso Corsa Metallic
        caliper_rgb=(0.96, 0.76, 0.04),    # Giallo Modena Yellow calipers
        rim_rgb=(0.74, 0.78, 0.83),        # Satin Titanium Weissach rims
        body_groups=[
            ("Body_Shell", shell_m), ("Body_Trim", trim_m), ("Body_Interior", int_m),
            ("Body_Glass", glass_m), ("Headlight_Main", head_m),
            ("Taillight_Main", tail_m), ("Reverselight_Main", rev_m),
        ],
        steering_data=sw_data,
        wheels_data=wheels_data,
        calipers_data=calipers_data,
    )


# ---------------------------------------------------------------------------
# Strict Validation
# ---------------------------------------------------------------------------
def validate_glb(path):
    gltf, blob = load_glb(path)
    assert gltf.get("extensionsRequired") is None, f"{path} has extensionsRequired!"
    nodes = gltf["nodes"]
    by_name = {n["name"]: i for i, n in enumerate(nodes)}
    assert "AssetRoot" in by_name
    assert "Body_Shell" in by_name and "mesh" in nodes[by_name["Body_Shell"]]
    print(f"VALIDATING {os.path.basename(path)}:")
    for c in ("FL", "FR", "RL", "RR"):
        pn = f"Wheel_{c}_Pivot"
        tn = f"Tire_{c}"
        bn = f"Brake_{c}"
        assert pn in by_name and tn in by_name and bn in by_name
        piv = nodes[by_name[pn]]
        tire_i = by_name[tn]
        assert tire_i in piv.get("children", []), f"{tn} not child of {pn}"
        t_mesh = gltf["meshes"][nodes[tire_i]["mesh"]]
        ymin, ymax = 1e9, -1e9
        for pr in t_mesh["primitives"]:
            acc = gltf["accessors"][pr["attributes"]["POSITION"]]
            ymin = min(ymin, acc["min"][1])
            ymax = max(ymax, acc["max"][1])
        dia = ymax - ymin
        assert dia > 0.4, f"{tn} invalid Y extent {dia}"
        tr = piv["translation"]
        print(f"  {pn}: pos=({tr[0]:+.3f}, {tr[1]:+.3f}, {tr[2]:+.3f}), {tn} dia={dia:.3f}m, centerY={(ymin+ymax)*0.5:+.4f}")


if __name__ == "__main__":
    build_vela_gt()
    build_orion_rs()
    build_kestrel_xr()
    print("\n--- VALIDATION ---")
    for fn in ("vela_gt.glb", "orion_rs.glb", "kestrel_xr.glb"):
        validate_glb(os.path.join(OUT_DIR, fn))
    print("\nALL 3 HERO CARS EXPORTED & VALIDATED!")
