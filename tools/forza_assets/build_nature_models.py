"""Build/upgrade nature models (rocks from Poly Haven photogrammetry, multi-tier conifers, broadleaf, shrubs)."""
import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
import bmesh
from mathutils import Vector, Euler
from blender_utils import (
    ROOT,
    clear_scene,
    make_pbr_tex_mat,
    make_solid_mat,
    box_uv_project,
    join_objects,
    set_ground_and_center,
    tri_count,
    export_model,
)

RAW_DIR = ROOT / "tools" / "forza_assets" / "raw_models"


def decimate_to_target(obj, target_tris: int):
    cur = tri_count(obj)
    if cur <= target_tris:
        return
    ratio = max(0.02, min(1.0, target_tris / float(cur)))
    mod = obj.modifiers.new(name="Decimate", type="DECIMATE")
    mod.ratio = ratio
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


def build_boulder():
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(RAW_DIR / "boulder_01" / "boulder_01_1k.gltf"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    obj = join_objects(meshes, "Boulder")
    decimate_to_target(obj, 1600)
    # Normalize to match original boulder footprint (~2.9m x 2.65m x 2.0m, r=2.8)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    dims = obj.dimensions
    sx = 2.9 / max(dims.x, 0.01)
    sy = 2.65 / max(dims.y, 0.01)
    sz = 2.0 / max(dims.z, 0.01)
    s = min(sx, sy, sz)
    obj.scale = (s, s, s)
    bpy.ops.object.transform_apply(scale=True)
    set_ground_and_center(obj, center_xz=True, bottom_z=0.0)
    export_model("assets/curated/models/environment/boulder.glb", obj)


def build_rock_cluster():
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(RAW_DIR / "rock_07" / "rock_07_1k.gltf"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    base = join_objects(meshes, "RockBase")
    decimate_to_target(base, 700)
    dims = base.dimensions
    s0 = 1.45 / max(dims.x, dims.y, 0.01)
    base.scale = (s0, s0, s0 * 0.9)
    bpy.ops.object.transform_apply(scale=True)

    parts = [base]
    configs = [
        ((0.58, -0.32, -0.04), (0.12, -0.18, 1.3), (0.78, 0.72, 0.85)),
        ((-0.52, 0.36, -0.05), (-0.1, 0.15, 2.7), (0.68, 0.75, 0.72)),
        ((0.15, 0.55, -0.03), (0.05, 0.08, -0.9), (0.52, 0.55, 0.55)),
    ]
    for idx, (loc, rot, scl) in enumerate(configs):
        dup = base.copy()
        dup.data = base.data.copy()
        dup.name = f"RockPart_{idx}"
        dup.location = loc
        dup.rotation_euler = rot
        dup.scale = scl
        bpy.context.collection.objects.link(dup)
        parts.append(dup)

    cluster = join_objects(parts, "RockCluster")
    set_ground_and_center(cluster, center_xz=True, bottom_z=0.0)
    export_model("assets/curated/models/environment/rock_cluster.glb", cluster)


def create_gnarled_trunk(height: float, base_r: float, top_r: float, segs: int, rings: int, seed: int, mat):
    rng = random.Random(seed)
    bm = bmesh.new()
    ring_verts = []
    for r_idx in range(rings + 1):
        t = r_idx / rings
        z = t * height
        # Root flare at bottom
        flare = 1.38 if r_idx == 0 else (1.12 if r_idx == 1 else 1.0)
        rad = (base_r * (1.0 - t) + top_r * t) * flare
        cx = math.sin(t * 3.1 + seed) * 0.04 * t
        cy = math.cos(t * 2.5 + seed) * 0.04 * t
        rv = []
        for s_idx in range(segs):
            ang = (s_idx / segs) * 2.0 * math.pi
            n = 1.0 + rng.uniform(-0.08, 0.08)
            x = cx + math.cos(ang) * rad * n
            y = cy + math.sin(ang) * rad * n
            rv.append(bm.verts.new((x, y, z)))
        ring_verts.append(rv)

    for r_idx in range(rings):
        for s_idx in range(segs):
            ns = (s_idx + 1) % segs
            bm.faces.new((
                ring_verts[r_idx][s_idx],
                ring_verts[r_idx][ns],
                ring_verts[r_idx + 1][ns],
                ring_verts[r_idx + 1][s_idx],
            ))
    bm.faces.new(ring_verts[-1])
    mesh = bpy.data.meshes.new("TrunkMesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Trunk", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    box_uv_project(obj, scale=0.8)
    for f in obj.data.polygons:
        f.use_smooth = True
    return obj


def create_conifer_bough_tier(z_base: float, radius: float, height: float, branches: int, seed: int, mat, detail: int = 2):
    """Create an organic multi-lobe drooping conifer bough tier."""
    rng = random.Random(seed)
    bm = bmesh.new()
    # Center-top apex + outer drooping branch tips + inner under-skirt
    apex = bm.verts.new((rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), z_base + height))
    center_bot = bm.verts.new((0.0, 0.0, z_base + height * 0.18))

    n_pts = branches * detail
    upper_ring = []
    outer_ring = []
    for i in range(n_pts):
        ang = (i / n_pts) * 2.0 * math.pi + rng.uniform(-0.06, 0.06)
        is_tip = (i % detail) == 0
        r_mult = (1.0 + rng.uniform(-0.08, 0.14)) if is_tip else (0.68 + rng.uniform(-0.06, 0.06))
        r = radius * r_mult
        droop = (-height * 0.12) if is_tip else (height * 0.08)
        z_out = z_base + droop + rng.uniform(-0.04, 0.04)
        z_up = z_base + height * (0.48 if is_tip else 0.56) + rng.uniform(-0.03, 0.03)
        outer_ring.append(bm.verts.new((math.cos(ang) * r, math.sin(ang) * r, z_out)))
        upper_ring.append(bm.verts.new((math.cos(ang) * r * 0.58, math.sin(ang) * r * 0.58, z_up)))

    for i in range(n_pts):
        ni = (i + 1) % n_pts
        bm.faces.new((apex, upper_ring[i], upper_ring[ni]))
        bm.faces.new((upper_ring[i], outer_ring[i], outer_ring[ni], upper_ring[ni]))
        bm.faces.new((center_bot, outer_ring[ni], outer_ring[i]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("BoughMesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Bough", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    box_uv_project(obj, scale=0.6)
    return obj


def build_pine_tree(is_lod1: bool = False):
    clear_scene()
    bark_mat = make_pbr_tex_mat("PineBark", "bark", uv_scale=1.2)
    fol_dark = make_solid_mat("PineNeedleDark", (0.075, 0.155, 0.072, 1.0), roughness=0.82)
    fol_mid = make_solid_mat("PineNeedleMid", (0.105, 0.205, 0.088, 1.0), roughness=0.78)
    fol_tip = make_solid_mat("PineNeedleTip", (0.135, 0.245, 0.105, 1.0), roughness=0.75)

    trunk = create_gnarled_trunk(
        height=3.65,
        base_r=0.22,
        top_r=0.045,
        segs=7 if is_lod1 else 10,
        rings=4 if is_lod1 else 7,
        seed=11,
        mat=bark_mat,
    )
    parts = [trunk]

    tiers = [
        (0.95, 1.48, 0.92, 9, fol_dark),
        (1.48, 1.34, 0.88, 9, fol_mid),
        (1.98, 1.16, 0.82, 8, fol_dark),
        (2.45, 0.96, 0.76, 8, fol_mid),
        (2.88, 0.78, 0.70, 7, fol_tip),
        (3.28, 0.56, 0.64, 6, fol_mid),
        (3.64, 0.34, 0.74, 5, fol_tip),
    ]
    if is_lod1:
        tiers = [tiers[0], tiers[2], tiers[4], tiers[6]]

    for idx, (zb, rad, h, br, mat) in enumerate(tiers):
        # Main bough tier
        b = create_conifer_bough_tier(
            z_base=zb,
            radius=rad,
            height=h,
            branches=br,
            seed=100 + idx * 17,
            mat=mat,
            detail=2 if is_lod1 else 3,
        )
        parts.append(b)
        if not is_lod1 and idx < 5:
            # Secondary offset sub-whorl for rich silhouette
            b2 = create_conifer_bough_tier(
                z_base=zb + 0.16,
                radius=rad * 0.84,
                height=h * 0.78,
                branches=max(5, br - 2),
                seed=300 + idx * 23,
                mat=fol_tip if idx % 2 == 0 else fol_dark,
                detail=2,
            )
            b2.rotation_euler.z = 0.35 * idx
            parts.append(b2)

    tree = join_objects(parts, "PineTree")
    set_ground_and_center(tree, center_xz=True, bottom_z=0.0)
    out = "assets/curated/models/environment/pine_tree_lod1.glb" if is_lod1 else "assets/curated/models/environment/pine_tree_lod0.glb"
    export_model(out, tree)


def create_foliage_puff(loc: tuple[float, float, float], rad: tuple[float, float, float], subdivs: int, seed: int, mat):
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivs, radius=1.0)
    for v in bm.verts:
        n = 1.0 + 0.22 * math.sin(v.co.x * 3.7 + seed) * math.cos(v.co.y * 3.3) + rng.uniform(-0.1, 0.1)
        v.co.x = v.co.x * rad[0] * n + loc[0]
        v.co.y = v.co.y * rad[1] * n + loc[1]
        v.co.z = v.co.z * rad[2] * n + loc[2]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("PuffMesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Puff", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    box_uv_project(obj, scale=0.8)
    for f in obj.data.polygons:
        f.use_smooth = True
    return obj


def build_broadleaf_tree():
    clear_scene()
    bark_mat = make_pbr_tex_mat("BroadleafBark", "bark", uv_scale=1.1)
    leaf_a = make_solid_mat("BroadleafA", (0.145, 0.285, 0.105, 1.0), roughness=0.72)
    leaf_b = make_solid_mat("BroadleafB", (0.195, 0.345, 0.125, 1.0), roughness=0.68)
    leaf_c = make_solid_mat("BroadleafC", (0.115, 0.235, 0.095, 1.0), roughness=0.78)

    trunk = create_gnarled_trunk(2.45, 0.24, 0.10, segs=10, rings=6, seed=42, mat=bark_mat)
    parts = [trunk]

    # 4 main forked branches
    for i in range(4):
        ang = (i / 4.0) * 2.0 * math.pi + 0.3
        br = create_gnarled_trunk(1.35, 0.095, 0.04, segs=6, rings=3, seed=70 + i, mat=bark_mat)
        br.location = (0.0, 0.0, 1.85)
        br.rotation_euler = (math.sin(ang) * 0.62, -math.cos(ang) * 0.62, ang)
        bpy.context.view_layer.update()
        parts.append(br)

    puffs = [
        ((0.0, 0.0, 3.65), (1.05, 1.05, 0.92), leaf_a),
        ((0.78, 0.45, 3.05), (0.82, 0.78, 0.72), leaf_b),
        ((-0.75, 0.52, 3.12), (0.85, 0.80, 0.74), leaf_c),
        ((0.42, -0.78, 2.95), (0.80, 0.84, 0.70), leaf_a),
        ((-0.62, -0.68, 3.18), (0.78, 0.76, 0.68), leaf_b),
        ((0.0, 0.0, 4.18), (0.76, 0.74, 0.64), leaf_b),
        ((0.55, 0.0, 3.75), (0.72, 0.68, 0.62), leaf_c),
        ((-0.52, 0.12, 3.82), (0.68, 0.72, 0.60), leaf_a),
    ]
    for idx, (loc, rad, mat) in enumerate(puffs):
        parts.append(create_foliage_puff(loc, rad, subdivs=2, seed=200 + idx * 13, mat=mat))

    tree = join_objects(parts, "BroadleafTree")
    set_ground_and_center(tree, center_xz=True, bottom_z=0.0)
    export_model("assets/curated/models/environment/broadleaf_tree.glb", tree)


def build_shrub_cluster():
    clear_scene()
    stem_mat = make_pbr_tex_mat("ShrubStem", "bark", uv_scale=1.5)
    leaf_a = make_solid_mat("ShrubLeafA", (0.14, 0.27, 0.095, 1.0), roughness=0.75)
    leaf_b = make_solid_mat("ShrubLeafB", (0.18, 0.33, 0.115, 1.0), roughness=0.70)

    parts = []
    # Woody stems at center base
    for i in range(4):
        ang = (i / 4.0) * 2.0 * math.pi + 0.2
        st = create_gnarled_trunk(0.42, 0.04, 0.018, segs=5, rings=2, seed=10 + i, mat=stem_mat)
        st.rotation_euler = (math.sin(ang) * 0.45, -math.cos(ang) * 0.45, ang)
        parts.append(st)

    puffs = [
        ((0.0, 0.0, 0.48), (0.48, 0.48, 0.42), leaf_a),
        ((0.42, 0.22, 0.36), (0.38, 0.36, 0.32), leaf_b),
        ((-0.38, 0.28, 0.38), (0.40, 0.38, 0.34), leaf_a),
        ((0.18, -0.42, 0.34), (0.36, 0.38, 0.30), leaf_b),
        ((-0.32, -0.34, 0.35), (0.38, 0.34, 0.32), leaf_a),
        ((0.05, 0.08, 0.68), (0.32, 0.32, 0.28), leaf_b),
    ]
    for idx, (loc, rad, mat) in enumerate(puffs):
        parts.append(create_foliage_puff(loc, rad, subdivs=2, seed=500 + idx * 19, mat=mat))

    shrub = join_objects(parts, "ShrubCluster")
    set_ground_and_center(shrub, center_xz=True, bottom_z=0.0)
    export_model("assets/curated/models/environment/shrub_cluster.glb", shrub)


def main():
    build_boulder()
    build_rock_cluster()
    build_pine_tree(is_lod1=False)
    build_pine_tree(is_lod1=True)
    build_broadleaf_tree()
    build_shrub_cluster()


if __name__ == "__main__":
    main()
