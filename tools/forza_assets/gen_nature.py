"""Pure-Python generator for upgraded nature models (.glb)."""
import math
import random
import sys
from pathlib import Path
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gltf_builder import GltfModel, MaterialDef


def rock_disp(seed: int, amp: float = 0.28):
    def fn(v: np.ndarray) -> float:
        x, y, z = float(v[0]), float(v[1]), float(v[2])
        # Multi-frequency craggy rock strata & facets
        n1 = math.sin(x * 3.1 + seed) * math.cos(y * 4.3 + seed * 0.7) * math.sin(z * 2.9 - seed)
        n2 = 0.5 * math.sin(x * 7.3 - z * 5.1 + seed * 1.3) * math.cos(y * 6.1)
        strata = 0.12 * math.sin(y * 8.0 + x * 2.5)
        return 1.0 + amp * (n1 + n2) + strata
    return fn


def build_boulder():
    m = GltfModel("Boulder")
    rock_mat = MaterialDef("RockAlpine", (0.78, 0.77, 0.75, 1.0), roughness=0.88, tex_folder="rock", normal_scale=1.1)
    p = m.part(rock_mat)
    # Main craggy boulder + protruding shoulder rock (subdivs=3 -> 1280 tris + subdivs=2 -> 320 tris = 1600 tris)
    p.add_icosphere((0.0, 0.92, 0.0), (1.35, 1.02, 1.22), subdivs=3, displace_fn=rock_disp(17, 0.28), uv_scale=0.35, smooth=False)
    p.add_icosphere((0.55, 0.52, 0.35), (0.72, 0.55, 0.65), subdivs=2, displace_fn=rock_disp(43, 0.25), uv_scale=0.35, smooth=False)
    m.normalize(center_xz=True, bottom_y=0.0)
    return m.export("assets/curated/models/environment/boulder.glb")


def build_rock_cluster():
    m = GltfModel("RockCluster")
    rock_mat = MaterialDef("RockClusterAlpine", (0.76, 0.75, 0.73, 1.0), roughness=0.88, tex_folder="rock", normal_scale=1.1)
    p = m.part(rock_mat)
    specs = [
        ((0.0, 0.42, 0.0), (0.75, 0.52, 0.68), 3, 101),
        ((0.68, 0.28, -0.32), (0.55, 0.38, 0.48), 2, 203),
        ((-0.58, 0.30, 0.35), (0.52, 0.36, 0.50), 2, 307),
        ((-0.22, 0.22, -0.55), (0.42, 0.28, 0.40), 2, 409),
    ]
    for c, r, sd, seed in specs:
        p.add_icosphere(c, r, subdivs=sd, displace_fn=rock_disp(seed, 0.26), uv_scale=0.45, smooth=False)
    m.normalize(center_xz=True, bottom_y=0.0)
    return m.export("assets/curated/models/environment/rock_cluster.glb")


def add_gnarled_trunk(part, base_pos, height, r_bot, r_top, segs, rings, seed, lean=(0.0, 0.0)):
    rng = random.Random(seed)
    verts = []
    for r in range(rings + 1):
        t = r / rings
        y = base_pos[1] + t * height
        flare = 1.42 if r == 0 else (1.14 if r == 1 else 1.0)
        rad = (r_bot * (1.0 - t) + r_top * t) * flare
        cx = base_pos[0] + lean[0] * t + math.sin(t * 3.0 + seed) * 0.03 * t
        cz = base_pos[2] + lean[1] * t + math.cos(t * 2.7 + seed) * 0.03 * t
        for s in range(segs):
            ang = (s / segs) * 2.0 * math.pi
            n = 1.0 + rng.uniform(-0.08, 0.08)
            verts.append([cx + math.cos(ang) * rad * n, y, cz + math.sin(ang) * rad * n])
    verts = np.array(verts, dtype=np.float32)
    tris = []
    for r in range(rings):
        for s in range(segs):
            ns = (s + 1) % segs
            a = r * segs + s
            b = r * segs + ns
            c = (r + 1) * segs + ns
            d = (r + 1) * segs + s
            tris.append([a, c, b])
            tris.append([a, d, c])
    part.add_triangles_flat(verts, np.array(tris, dtype=np.uint32), uv_scale=0.8)


def add_conifer_whorl(part, y_base: float, radius: float, height: float, branches: int, detail: int, seed: int, rot_offset: float = 0.0):
    rng = random.Random(seed)
    n_pts = branches * detail
    verts = [
        [rng.uniform(-0.02, 0.02), y_base + height, rng.uniform(-0.02, 0.02)],  # 0: apex
        [0.0, y_base + height * 0.16, 0.0],  # 1: inner bottom
    ]
    for i in range(n_pts):
        ang = rot_offset + (i / n_pts) * 2.0 * math.pi + rng.uniform(-0.05, 0.05)
        is_tip = (i % detail) == 0
        r_mult = (1.0 + rng.uniform(-0.07, 0.14)) if is_tip else (0.64 + rng.uniform(-0.06, 0.06))
        r = radius * r_mult
        droop = (-height * 0.12) if is_tip else (height * 0.06)
        y_out = y_base + droop + rng.uniform(-0.03, 0.03)
        y_up = y_base + height * (0.48 if is_tip else 0.56) + rng.uniform(-0.03, 0.03)
        verts.append([math.cos(ang) * r, y_out, math.sin(ang) * r])
        verts.append([math.cos(ang) * r * 0.56, y_up, math.sin(ang) * r * 0.56])
    verts = np.array(verts, dtype=np.float32)
    tris = []
    for i in range(n_pts):
        ni = (i + 1) % n_pts
        o_i = 2 + i * 2
        u_i = 3 + i * 2
        o_ni = 2 + ni * 2
        u_ni = 3 + ni * 2
        tris.append([0, u_ni, u_i])
        tris.append([u_i, u_ni, o_ni])
        tris.append([u_i, o_ni, o_i])
        tris.append([1, o_i, o_ni])
    part.add_triangles_flat(verts, np.array(tris, dtype=np.uint32), uv_scale=0.6)


def build_pine_tree(is_lod1: bool = False):
    m = GltfModel("PineTreeLOD1" if is_lod1 else "PineTreeLOD0")
    bark = MaterialDef("PineBark", (0.45, 0.36, 0.30, 1.0), roughness=0.92, tex_folder="bark", normal_scale=1.0)
    fol_d = MaterialDef("PineNeedleDark", (0.032, 0.082, 0.028, 1.0), roughness=0.84)
    fol_m = MaterialDef("PineNeedleMid", (0.048, 0.115, 0.038, 1.0), roughness=0.80)
    fol_t = MaterialDef("PineNeedleTip", (0.068, 0.145, 0.052, 1.0), roughness=0.76)

    add_gnarled_trunk(
        m.part(bark), (0, 0, 0), height=3.65, r_bot=0.22, r_top=0.045,
        segs=7 if is_lod1 else 10, rings=4 if is_lod1 else 7, seed=11,
    )

    tiers = [
        (0.95, 1.48, 0.92, 9, fol_d),
        (1.48, 1.34, 0.88, 9, fol_m),
        (1.98, 1.16, 0.82, 8, fol_d),
        (2.45, 0.96, 0.76, 8, fol_m),
        (2.88, 0.78, 0.70, 7, fol_t),
        (3.28, 0.56, 0.64, 6, fol_m),
        (3.64, 0.34, 0.74, 5, fol_t),
    ]
    if is_lod1:
        tiers = [tiers[0], tiers[2], tiers[4], tiers[6]]

    for idx, (yb, rad, h, br, mat) in enumerate(tiers):
        add_conifer_whorl(m.part(mat), yb, rad, h, br, 3 if is_lod1 else 4, 100 + idx * 17, idx * 0.42)
        if not is_lod1 and idx < 6:
            sub_mat = fol_t if idx % 2 == 0 else fol_d
            add_conifer_whorl(m.part(sub_mat), yb + 0.16, rad * 0.84, h * 0.78, max(5, br - 2), 4, 300 + idx * 23, idx * 0.42 + 0.35)

    m.normalize(center_xz=True, bottom_y=0.0)
    out = "assets/curated/models/environment/pine_tree_lod1.glb" if is_lod1 else "assets/curated/models/environment/pine_tree_lod0.glb"
    return m.export(out)


def foliage_disp(seed: int):
    def fn(v: np.ndarray) -> float:
        x, y, z = float(v[0]), float(v[1]), float(v[2])
        return 1.0 + 0.18 * math.sin(x * 4.2 + seed) * math.cos(y * 3.8 - seed) + 0.10 * math.sin(z * 6.5 + seed * 1.7)
    return fn


def build_broadleaf_tree():
    m = GltfModel("BroadleafTree")
    bark = MaterialDef("BroadleafBark", (0.46, 0.38, 0.31, 1.0), roughness=0.90, tex_folder="bark", normal_scale=1.0)
    leaf_a = MaterialDef("BroadleafA", (0.052, 0.145, 0.036, 1.0), roughness=0.74)
    leaf_b = MaterialDef("BroadleafB", (0.078, 0.190, 0.048, 1.0), roughness=0.70)
    leaf_c = MaterialDef("BroadleafC", (0.038, 0.110, 0.028, 1.0), roughness=0.78)

    p_bark = m.part(bark)
    add_gnarled_trunk(p_bark, (0, 0, 0), 2.50, 0.24, 0.09, segs=10, rings=6, seed=42)
    for i in range(4):
        ang = (i / 4.0) * 2.0 * math.pi + 0.3
        add_gnarled_trunk(
            p_bark, (0.0, 1.85, 0.0), 1.30, 0.095, 0.04, segs=6, rings=3, seed=70 + i,
            lean=(math.cos(ang) * 0.75, math.sin(ang) * 0.75),
        )

    puffs = [
        ((0.0, 3.65, 0.0), (1.05, 0.92, 1.05), leaf_a),
        ((0.78, 3.05, 0.45), (0.82, 0.72, 0.78), leaf_b),
        ((-0.75, 3.12, 0.52), (0.85, 0.74, 0.80), leaf_c),
        ((0.42, 2.95, -0.78), (0.80, 0.70, 0.84), leaf_a),
        ((-0.62, 3.18, -0.68), (0.78, 0.68, 0.76), leaf_b),
        ((0.0, 4.18, 0.0), (0.76, 0.64, 0.74), leaf_b),
        ((0.55, 3.75, 0.0), (0.72, 0.62, 0.68), leaf_c),
        ((-0.52, 3.82, 0.12), (0.68, 0.60, 0.72), leaf_a),
    ]
    for idx, (c, r, mat) in enumerate(puffs):
        m.part(mat).add_icosphere(c, r, subdivs=2, displace_fn=foliage_disp(200 + idx * 13), uv_scale=0.8, smooth=True)

    m.normalize(center_xz=True, bottom_y=0.0)
    return m.export("assets/curated/models/environment/broadleaf_tree.glb")


def build_shrub_cluster():
    m = GltfModel("ShrubCluster")
    stem = MaterialDef("ShrubStem", (0.42, 0.34, 0.26, 1.0), roughness=0.90, tex_folder="bark")
    leaf_a = MaterialDef("ShrubLeafA", (0.048, 0.135, 0.034, 1.0), roughness=0.76)
    leaf_b = MaterialDef("ShrubLeafB", (0.072, 0.175, 0.045, 1.0), roughness=0.72)

    p_stem = m.part(stem)
    for i in range(4):
        ang = (i / 4.0) * 2.0 * math.pi + 0.2
        add_gnarled_trunk(p_stem, (0, 0, 0), 0.44, 0.04, 0.018, segs=5, rings=2, seed=10 + i, lean=(math.cos(ang) * 0.22, math.sin(ang) * 0.22))

    puffs = [
        ((0.0, 0.48, 0.0), (0.48, 0.42, 0.48), leaf_a),
        ((0.42, 0.36, 0.22), (0.38, 0.32, 0.36), leaf_b),
        ((-0.38, 0.38, 0.28), (0.40, 0.34, 0.38), leaf_a),
        ((0.18, 0.34, -0.42), (0.36, 0.30, 0.38), leaf_b),
        ((-0.32, 0.35, -0.34), (0.38, 0.32, 0.34), leaf_a),
        ((0.05, 0.68, 0.08), (0.32, 0.28, 0.32), leaf_b),
    ]
    for idx, (c, r, mat) in enumerate(puffs):
        m.part(mat).add_icosphere(c, r, subdivs=2, displace_fn=foliage_disp(500 + idx * 19), uv_scale=0.9, smooth=True)

    m.normalize(center_xz=True, bottom_y=0.0)
    return m.export("assets/curated/models/environment/shrub_cluster.glb")


def main():
    build_boulder()
    build_rock_cluster()
    build_pine_tree(is_lod1=False)
    build_pine_tree(is_lod1=True)
    build_broadleaf_tree()
    build_shrub_cluster()


if __name__ == "__main__":
    main()
