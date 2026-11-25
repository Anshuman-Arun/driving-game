#!/usr/bin/env python3
"""Build Phase A Forza-grade undergrowth GLB assets (LOD0 + LOD1) and contact sheets.

Generates Y-up, ground-pivot, metric GLBs in assets/environment_realism/undergrowth/
from verified CC0 Poly Haven 4K sources:
  - grass_short_lod{0,1}.glb      (from grass_medium_01)
  - grass_meadow_lod{0,1}.glb     (from grass_medium_02)
  - grass_tall_verge_lod{0,1}.glb (from grass_medium_01 tall seed-head & grass_medium_02)
  - fern_lod{0,1}.glb             (from fern_02)
  - wildflower_lod{0,1}.glb       (from celandine_01)
  - shrub_woodland_lod{0,1}.glb   (from shrub_02, Surface 0=bark, Surface 1=foliage)
  - rock_moss_lod{0,1}.glb        (from rock_moss_set_02)

Usage:
  python tools/environment_assets/build_undergrowth.py [--skip-renders] [--variants ...]
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

DEFAULT_BLENDER = (
    r"C:\Users\anshu\AppData\Local\Programs\Blender4.5\blender-4.5.10-windows-x64\blender.exe"
)
DEFAULT_EXT_CACHE = r"C:\Users\anshu\Documents\Coding\aster-valley-asset-source\models"


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


# ---------------------------------------------------------------------------
# Phase 1: Python Texture Calibration, Alpha Extraction & RGB Dilation
# ---------------------------------------------------------------------------
def prepare_all_textures(repo_root: Path, ext_cache: Path, tex_dir: Path) -> dict:
    """Prepare calibrated, mip-dilated PBR textures in tex_dir."""
    import numpy as np
    from PIL import Image, ImageDraw
    from scipy.ndimage import binary_dilation, binary_erosion, distance_transform_edt, gaussian_filter

    tex_dir.mkdir(parents=True, exist_ok=True)
    src_repo = repo_root / "asset_library" / "environment_sources"

    def dilate_rgb(rgb: np.ndarray, mask: np.ndarray) -> np.ndarray:
        if mask.all() or not mask.any():
            return rgb
        _, idx = distance_transform_edt(~mask, return_indices=True)
        return np.where(mask[..., None], rgb, rgb[idx[0], idx[1]])

    def resize_rgb(path: Path, size: int, is_color: bool = True) -> np.ndarray:
        im = Image.open(path).convert("RGB")
        if im.size != (size, size):
            filt = Image.Resampling.LANCZOS if is_color else Image.Resampling.BILINEAR
            im = im.resize((size, size), filt)
        return np.array(im)

    def save_rgb(arr: np.ndarray, name: str, quality: int = 90) -> str:
        p = tex_dir / f"{name}.jpg"
        Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGB").save(
            p, quality=quality, subsampling=0
        )
        return str(p)

    def save_rgba(rgb: np.ndarray, alpha_01: np.ndarray, name: str) -> str:
        p = tex_dir / f"{name}.png"
        rgba = np.dstack([
            np.clip(rgb, 0, 255).astype(np.uint8),
            np.clip(alpha_01 * 255.0, 0, 255).astype(np.uint8),
        ])
        Image.fromarray(rgba, mode="RGBA").save(p, optimize=True)
        return str(p)

    def read_gltf_uvs(gltf_path: Path, u_min_filter: float = -1.0) -> list[np.ndarray]:
        gltf = json.loads(gltf_path.read_text(encoding="utf-8"))
        bin_data = (gltf_path.parent / gltf["buffers"][0]["uri"]).read_bytes()
        comp_map = {
            5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
            5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4),
        }
        type_map = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}

        def read_acc(acc_idx: int) -> np.ndarray:
            acc = gltf["accessors"][acc_idx]
            bv = gltf["bufferViews"][acc["bufferView"]]
            off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
            fmt_c, sz_c = comp_map[acc["componentType"]]
            ncomp = type_map[acc["type"]]
            stride = bv.get("byteStride", 0) or (sz_c * ncomp)
            rows = [
                struct.unpack_from("<" + fmt_c * ncomp, bin_data, off + i * stride)
                for i in range(acc["count"])
            ]
            arr = np.array(rows)
            return arr[:, 0] if ncomp == 1 else arr

        tris_out = []
        for mesh in gltf["meshes"]:
            for prim in mesh["primitives"]:
                uv = read_acc(prim["attributes"]["TEXCOORD_0"])
                idx = read_acc(prim["indices"]).reshape(-1, 3)
                for tri in idx:
                    pts = uv[tri]
                    if pts[:, 0].mean() >= u_min_filter:
                        tris_out.append(pts)
        return tris_out

    manifest = {}

    # 1) grass_medium_01 -> grass_short (opaque) + grass_tall_verge (RGBA cutout for seed heads)
    g1_dir = src_repo / "grass_medium_01" / "textures"
    g1_diff = resize_rgb(g1_dir / "grass_medium_01_diff_4k.jpg", 1024, True)
    g1_nor = resize_rgb(g1_dir / "grass_medium_01_nor_gl_4k.jpg", 1024, False)
    g1_arm = resize_rgb(g1_dir / "grass_medium_01_arm_4k.jpg", 1024, False)
    g1_lum = g1_diff.max(axis=-1).astype(np.float32)
    g1_solid = g1_lum > 18.0
    g1_core = binary_erosion(g1_solid, iterations=1)
    if not g1_core.any():
        g1_core = g1_solid
    g1_dil = dilate_rgb(g1_diff, g1_core)
    # Calibrate slightly brighter/warmer olive-green so grass_medium_01 blends into Forza meadow terrain
    g1_cal = np.clip(g1_dil.astype(np.float32) * np.array([1.28, 1.32, 1.22]) + 7.0, 0, 255)
    g1_alpha = np.clip((g1_lum - 10.0) / 16.0, 0.0, 1.0)
    g1_nor_dil = dilate_rgb(g1_nor, g1_core)
    g1_arm_dil = dilate_rgb(g1_arm, g1_core)

    manifest["grass_short"] = {
        "diff": save_rgb(g1_cal, "grass_short_diff", 90),
        "nor": save_rgb(g1_nor_dil, "grass_short_nor", 88),
        "arm": save_rgb(g1_arm_dil, "grass_short_arm", 88),
    }
    manifest["grass_tall_verge"] = {
        "diff": save_rgba(g1_cal, g1_alpha, "grass_tall_verge_rgba"),
        "nor": manifest["grass_short"]["nor"],
        "arm": manifest["grass_short"]["arm"],
    }

    # 2) grass_medium_02 -> grass_meadow (opaque dilated RGB)
    g2_dir = src_repo / "grass_medium_02" / "textures"
    g2_diff = resize_rgb(g2_dir / "grass_medium_02_diff_4k.jpg", 1024, True)
    g2_nor = resize_rgb(g2_dir / "grass_medium_02_nor_gl_4k.jpg", 1024, False)
    g2_arm = resize_rgb(g2_dir / "grass_medium_02_arm_4k.jpg", 1024, False)
    g2_lum = g2_diff.max(axis=-1).astype(np.float32)
    g2_core = binary_erosion(g2_lum > 24.0, iterations=1)
    g2_dil = dilate_rgb(g2_diff, g2_core)
    # Harmonize saturation & value with grass_short & terrain_forza
    g2_cal = np.clip(g2_dil.astype(np.float32) * np.array([0.84, 0.90, 0.72]), 0, 255)
    g2_nor_dil = dilate_rgb(g2_nor, g2_core)
    g2_arm_dil = dilate_rgb(g2_arm, g2_core)
    manifest["grass_meadow"] = {
        "diff": save_rgb(g2_cal, "grass_meadow_diff", 90),
        "nor": save_rgb(g2_nor_dil, "grass_meadow_nor", 88),
        "arm": save_rgb(g2_arm_dil, "grass_meadow_arm", 88),
    }

    # 3) fern_02 -> fern (RGBA cutout from arm.g + nor_gl)
    f_dir = src_repo / "fern_02" / "textures"
    f_diff = resize_rgb(f_dir / "fern_02_diff_4k.jpg", 1024, True)
    f_nor = resize_rgb(f_dir / "fern_02_nor_gl_4k.jpg", 1024, False)
    f_arm = resize_rgb(f_dir / "fern_02_arm_4k.jpg", 1024, False)
    nor_dev = np.linalg.norm(f_nor.astype(np.float32) - np.array([128.0, 128.0, 255.0]), axis=-1)
    f_alpha = np.maximum(
        np.clip((248.0 - f_arm[:, :, 1].astype(np.float32)) / 14.0, 0.0, 1.0),
        np.clip((nor_dev - 11.0) / 14.0, 0.0, 1.0),
    )
    # Zero out tiny top-left corner artifact outside UV bounds
    f_alpha[:80, :180] = 0.0
    f_solid = f_alpha > 0.35
    f_rgb_dil = dilate_rgb(f_diff, f_solid)
    f_cal = np.clip(f_rgb_dil.astype(np.float32) * np.array([0.96, 1.04, 0.92]), 0, 255)
    manifest["fern"] = {
        "diff": save_rgba(f_cal, f_alpha, "fern_rgba"),
        "nor": save_rgb(f_nor, "fern_nor", 88),
        "arm": save_rgb(f_arm, "fern_arm", 88),
    }

    # 4) celandine_01 -> wildflower (RGBA cutout + RGB dilation)
    c_dir = src_repo / "celandine_01" / "textures"
    c_diff = resize_rgb(c_dir / "celandine_01_diff_4k.jpg", 1024, True)
    c_nor = resize_rgb(c_dir / "celandine_01_nor_gl_4k.jpg", 1024, False)
    c_arm = resize_rgb(c_dir / "celandine_01_arm_4k.jpg", 1024, False)
    c_lum = c_diff.max(axis=-1).astype(np.float32)
    c_core = binary_erosion(c_lum > 22.0, iterations=1)
    c_dil = dilate_rgb(c_diff, c_core)
    c_alpha = np.clip((c_lum - 10.0) / 18.0, 0.0, 1.0)
    manifest["wildflower"] = {
        "diff": save_rgba(c_dil, c_alpha, "wildflower_rgba"),
        "nor": save_rgb(dilate_rgb(c_nor, c_core), "wildflower_nor", 88),
        "arm": save_rgb(dilate_rgb(c_arm, c_core), "wildflower_arm", 88),
    }

    # 5) shrub_02 -> shrub_woodland (bark opaque + foliage RGBA rasterized from original leaf UVs)
    s2_root = ext_cache / "shrub_02" / "4k"
    s2_tex = s2_root / "textures"
    s2_diff = resize_rgb(s2_tex / "shrub_02_diff_4k.jpg", 1024, True)
    s2_nor = resize_rgb(s2_tex / "shrub_02_nor_gl_4k.jpg", 1024, False)
    s2_arm = resize_rgb(s2_tex / "shrub_02_arm_4k.jpg", 1024, False)

    mask_im = Image.new("L", (1024, 1024), 0)
    draw = ImageDraw.Draw(mask_im)
    for tri in read_gltf_uvs(s2_root / "shrub_02_4k.gltf", u_min_filter=0.165):
        pts = [(float(u) * 1024.0, float(v) * 1024.0) for u, v in tri]
        draw.polygon(pts, fill=255)
    leaf_mask = np.array(mask_im) > 128
    # Slightly feather alpha & dilate leaf interior RGB outward so decimated edges have zero Voronoi seams
    leaf_core = binary_erosion(leaf_mask, iterations=1)
    if not leaf_core.any():
        leaf_core = leaf_mask
    s2_leaf_rgb = dilate_rgb(s2_diff, leaf_core)
    # Keep thin leaf tips crisp (dilate 1px instead of blurring) so leaves stay 100% solid
    s2_leaf_alpha = binary_dilation(leaf_mask, iterations=1).astype(np.float32)

    # Bark strip is u < 0.165; keep clean 512x512 opaque bark + full 1024 foliage RGBA
    manifest["shrub_woodland_bark"] = {
        "diff": save_rgb(s2_diff, "shrub_bark_diff", 88),
        "nor": save_rgb(s2_nor, "shrub_bark_nor", 85),
        "arm": save_rgb(s2_arm, "shrub_bark_arm", 85),
    }
    manifest["shrub_woodland_foliage"] = {
        "diff": save_rgba(s2_leaf_rgb, s2_leaf_alpha, "shrub_foliage_rgba"),
        "nor": save_rgb(dilate_rgb(s2_nor, leaf_core), "shrub_foliage_nor", 88),
        "arm": save_rgb(dilate_rgb(s2_arm, leaf_core), "shrub_foliage_arm", 88),
    }

    # 6) rock_moss_set_02 -> rock_moss (1024 opaque PBR; source uses separate _rough_4k.jpg)
    r_tex = ext_cache / "rock_moss_set_02" / "4k" / "textures"
    r_rough = resize_rgb(r_tex / "rock_moss_set_02_rough_4k.jpg", 1024, False)[:, :, 0]
    r_arm = np.zeros((1024, 1024, 3), dtype=np.uint8)
    r_arm[:, :, 0] = 255
    r_arm[:, :, 1] = r_rough
    manifest["rock_moss"] = {
        "diff": save_rgb(resize_rgb(r_tex / "rock_moss_set_02_diff_4k.jpg", 1024, True), "rock_moss_diff", 90),
        "nor": save_rgb(resize_rgb(r_tex / "rock_moss_set_02_nor_gl_4k.jpg", 1024, False), "rock_moss_nor", 88),
        "arm": save_rgb(r_arm, "rock_moss_arm", 88),
    }

    manifest_path = tex_dir / "tex_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


# ---------------------------------------------------------------------------
# Phase 2: Blender 4.5.10 Geometry Assembly, LOD1 Card Baking, Export & Sheets
# ---------------------------------------------------------------------------
def blender_worker(args: argparse.Namespace) -> None:
    import bpy
    import bmesh
    import numpy as np
    from mathutils import Euler, Matrix, Vector

    repo_root = _repo_root()
    src_repo = repo_root / "asset_library" / "environment_sources"
    ext_cache = Path(args.ext_cache)
    out_dir = repo_root / "assets" / "environment_realism" / "undergrowth"
    out_dir.mkdir(parents=True, exist_ok=True)
    sheet_dir = Path(args.sheet_dir)
    sheet_dir.mkdir(parents=True, exist_ok=True)
    cache_dir = Path(args.cache_dir)
    tex_manifest = json.loads((cache_dir / "tex_manifest.json").read_text(encoding="utf-8"))

    # ---- Helpers ----
    def reset_scene():
        bpy.ops.wm.read_factory_settings(use_empty=True)

    def import_gltf_map(gltf_path: Path) -> dict[str, bpy.types.Object]:
        before = set(bpy.data.objects.keys())
        bpy.ops.import_scene.gltf(filepath=str(gltf_path))
        after = set(bpy.data.objects.keys())
        created = {}
        for name in sorted(after - before):
            obj = bpy.data.objects[name]
            if obj.type == "MESH":
                created[obj.name] = obj
        return created

    def bake_obj_transform(obj: bpy.types.Object, loc=(0, 0, 0), rot_deg=(0, 0, 0), scale=1.0):
        """Duplicate mesh data with baked transform in Z-up world coordinates."""
        mesh = obj.data.copy()
        s = scale if isinstance(scale, (tuple, list)) else (scale, scale, scale)
        mat = Matrix.Translation(Vector(loc)) @ Euler(
            [math.radians(a) for a in rot_deg], "XYZ"
        ).to_matrix().to_4x4() @ Matrix.Diagonal((*s, 1.0))
        mesh.transform(mat)
        new_obj = bpy.data.objects.new(obj.name + "_inst", mesh)
        bpy.context.scene.collection.objects.link(new_obj)
        return new_obj

    def join_objects(objs: list[bpy.types.Object], name: str) -> bpy.types.Object:
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        res = bpy.context.view_layer.objects.active
        res.name = name
        res.data.name = name
        return res

    def ground_and_sink(obj: bpy.types.Object, sink_z: float):
        """Shift mesh so min_z sits at sink_z and XY centroid is centered near (0, 0)."""
        verts = obj.data.vertices
        xs = [v.co.x for v in verts]
        ys = [v.co.y for v in verts]
        zs = [v.co.z for v in verts]
        cx = 0.5 * (min(xs) + max(xs))
        cy = 0.5 * (min(ys) + max(ys))
        mz = min(zs)
        offset = Vector((-cx, -cy, sink_z - mz))
        for v in verts:
            v.co += offset
        obj.data.update()

    def decimate_obj(obj: bpy.types.Object, target_tris: int):
        cur_tris = len(obj.data.polygons)
        if cur_tris <= target_tris:
            return
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = max(0.03, float(target_tris) / float(cur_tris))
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)

    def make_pbr_material(
        mat_name: str,
        tex_entry: dict,
        alpha_mode: str = "OPAQUE",
        alpha_cutoff: float = 0.42,
        roughness_scale: float = 1.0,
    ) -> bpy.types.Material:
        mat = bpy.data.materials.new(name=mat_name)
        mat.use_nodes = True
        nt = mat.node_tree
        nt.nodes.clear()

        out = nt.nodes.new("ShaderNodeOutputMaterial")
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        bsdf.inputs["Metallic"].default_value = 0.0
        bsdf.inputs["IOR"].default_value = 1.45

        # Albedo (+ Alpha if cutout)
        tex_diff = nt.nodes.new("ShaderNodeTexImage")
        img_diff = bpy.data.images.load(tex_entry["diff"], check_existing=True)
        img_diff.colorspace_settings.name = "sRGB"
        tex_diff.image = img_diff
        nt.links.new(tex_diff.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha_mode == "MASK":
            nt.links.new(tex_diff.outputs["Alpha"], bsdf.inputs["Alpha"])
            mat.blend_method = "CLIP"
            mat.alpha_threshold = alpha_cutoff
        else:
            mat.blend_method = "OPAQUE"

        # Normal GL
        tex_nor = nt.nodes.new("ShaderNodeTexImage")
        img_nor = bpy.data.images.load(tex_entry["nor"], check_existing=True)
        img_nor.colorspace_settings.name = "Non-Color"
        tex_nor.image = img_nor
        nor_map = nt.nodes.new("ShaderNodeNormalMap")
        nor_map.inputs["Strength"].default_value = 0.85
        nt.links.new(tex_nor.outputs["Color"], nor_map.inputs["Color"])
        nt.links.new(nor_map.outputs["Normal"], bsdf.inputs["Normal"])

        # ARM -> Separate Color -> G to Roughness
        tex_arm = nt.nodes.new("ShaderNodeTexImage")
        img_arm = bpy.data.images.load(tex_entry["arm"], check_existing=True)
        img_arm.colorspace_settings.name = "Non-Color"
        tex_arm.image = img_arm
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(tex_arm.outputs["Color"], sep.inputs["Color"])
        if abs(roughness_scale - 1.0) > 1e-3:
            mul = nt.nodes.new("ShaderNodeMath")
            mul.operation = "MULTIPLY"
            mul.use_clamp = True
            mul.inputs[1].default_value = roughness_scale
            nt.links.new(sep.outputs["Green"], mul.inputs[0])
            nt.links.new(mul.outputs["Value"], bsdf.inputs["Roughness"])
        else:
            nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])

        return mat

    def apply_vertex_attributes(
        obj: bpy.types.Object,
        flex_power: float = 1.15,
        root_ao_min: float = 0.78,
        normal_up_blend: float = 0.68,
        is_rock: bool = False,
        anchor_z: float = 0.01,
    ):
        """Encode COLOR.rgb = gentle inner/root AO, COLOR.a = wind flex, and blend normals."""
        mesh = obj.data
        verts = mesh.vertices
        zs = [v.co.z for v in verts]
        max_z = max(max(zs), 0.08)
        radii = [math.hypot(v.co.x, v.co.y) for v in verts]
        max_r = max(max(radii), 0.05)

        if mesh.color_attributes.get("Color"):
            mesh.color_attributes.remove(mesh.color_attributes["Color"])
        col_attr = mesh.color_attributes.new(name="Color", type="BYTE_COLOR", domain="CORNER")

        vert_cols = []
        target_norms = []
        for idx, v in enumerate(verts):
            if is_rock:
                h_t = max(0.0, min(1.0, (v.co.z + 0.12) / (max_z + 0.12)))
                ao = 0.78 + 0.22 * h_t
                vert_cols.append((ao, ao, ao, 0.0))
                target_norms.append(v.normal.normalized())
            else:
                h_t = max(0.0, min(1.0, (v.co.z - anchor_z) / max(max_z - anchor_z, 0.05)))
                flex = 0.0 if v.co.z <= anchor_z else (h_t ** flex_power)
                rad_t = min(1.0, radii[idx] / max_r)
                ao = (root_ao_min + (1.0 - root_ao_min) * (h_t ** 0.7)) * (0.86 + 0.14 * rad_t)
                vert_cols.append((ao, ao * 1.01, ao * 0.97, flex))

                up_bias = Vector((v.co.x * 0.65, v.co.y * 0.65, max(0.75, max_z * 1.3))).normalized()
                n = v.normal.normalized().lerp(up_bias, normal_up_blend).normalized()
                target_norms.append(n)

        for poly in mesh.polygons:
            for li in poly.loop_indices:
                vi = mesh.loops[li].vertex_index
                col_attr.data[li].color = vert_cols[vi]
        mesh.color_attributes.active_color = col_attr

        if not is_rock and normal_up_blend > 0.0:
            mesh.normals_split_custom_set_from_vertices(target_norms)
        mesh.update()

    def verify_bounds_and_export(obj: bpy.types.Object, glb_path: Path) -> dict:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        # Apply triangulate cleanly before export
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.quads_convert_to_tris()
        bpy.ops.object.mode_set(mode="OBJECT")

        verts = obj.data.vertices
        mn = [min(v.co[i] for v in verts) for i in range(3)]
        mx = [max(v.co[i] for v in verts) for i in range(3)]
        # Convert Z-up bounds to Y-up bounds: (x, z, -y)
        yup_min = [round(mn[0], 3), round(mn[2], 3), round(-mx[1], 3)]
        yup_max = [round(mx[0], 3), round(mx[2], 3), round(-mn[1], 3)]
        tris = len(obj.data.polygons)

        bpy.ops.export_scene.gltf(
            filepath=str(glb_path),
            export_format="GLB",
            use_selection=True,
            export_yup=True,
            export_texcoords=True,
            export_normals=True,
            export_tangents=True,
            export_materials="EXPORT",
            export_vertex_color="ACTIVE",
            export_vertex_color_name="Color",
            export_image_format="AUTO",
        )
        size_kb = round(glb_path.stat().st_size / 1024.0, 1)
        mats = [m.name for m in obj.data.materials if m]
        info = {
            "glb": glb_path.name,
            "tris": tris,
            "size_kb": size_kb,
            "yup_min": yup_min,
            "yup_max": yup_max,
            "materials": mats,
        }
        print(f"EXPORTED {glb_path.name}: tris={tris}, size={size_kb} KB, y=[{yup_min[1]}..{yup_max[1]}], xz_rad={max(abs(yup_min[0]), abs(yup_max[0]), abs(yup_min[2]), abs(yup_max[2])):.3f}m, mats={mats}")
        return info

    def dilate_rgba_numpy(rgba: np.ndarray, threshold: float = 0.25, passes: int = 28) -> np.ndarray:
        """Pure-NumPy iterative neighbor dilation of RGB into transparent texels."""
        out = rgba.copy()
        valid = out[:, :, 3] > threshold
        for _ in range(passes):
            if valid.all():
                break
            cur_rgb = out[:, :, :3]
            cur_v = valid
            acc_rgb = np.zeros_like(cur_rgb)
            acc_cnt = np.zeros(valid.shape, dtype=np.float32)
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
                sr = np.roll(cur_rgb, shift=(dy, dx), axis=(0, 1))
                sv = np.roll(cur_v, shift=(dy, dx), axis=(0, 1))
                w = sv.astype(np.float32)
                acc_rgb += sr * w[:, :, None]
                acc_cnt += w
            fill = (~valid) & (acc_cnt > 0)
            if not fill.any():
                break
            out[fill, :3] = acc_rgb[fill] / acc_cnt[fill, None]
            valid = valid | fill
        return out

    def bake_lod1_cards(
        lod0_obj: bpy.types.Object,
        name: str,
        target_mat_name: str,
        alpha_cutoff: float = 0.38,
    ) -> bpy.types.Object:
        """Render 4 unlit ortho views of lod0_obj into a 512x512 dilated RGBA atlas and build crossed cards."""
        verts = lod0_obj.data.vertices
        mn = Vector((min(v.co.x for v in verts), min(v.co.y for v in verts), min(v.co.z for v in verts)))
        mx = Vector((max(v.co.x for v in verts), max(v.co.y for v in verts), max(v.co.z for v in verts)))
        width = max(mx.x - mn.x, mx.y - mn.y)
        height = mx.z - min(0.0, mn.z)
        ortho_scale = max(width, height) * 1.12
        center_z = 0.5 * (max(0.0, mn.z) + mx.z)
        look_target = Vector((0.0, 0.0, center_z))

        # Save original materials and build temporary emission-only albedo material for unlit capture
        orig_mats = list(lod0_obj.data.materials)
        temp_mats = []
        for m in orig_mats:
            tm = m.copy()
            nt = tm.node_tree
            out_n = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
            bsdf_n = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
            emis = nt.nodes.new("ShaderNodeEmission")
            for link in list(nt.links):
                if link.to_node == bsdf_n and link.to_socket == bsdf_n.inputs["Base Color"]:
                    nt.links.new(link.from_socket, emis.inputs["Color"])
                    break
            else:
                emis.inputs["Color"].default_value = bsdf_n.inputs["Base Color"].default_value
            alpha_link = next(
                (l for l in nt.links if l.to_node == bsdf_n and l.to_socket == bsdf_n.inputs["Alpha"]),
                None,
            )
            if alpha_link:
                transp = nt.nodes.new("ShaderNodeBsdfTransparent")
                mix_s = nt.nodes.new("ShaderNodeMixShader")
                nt.links.new(alpha_link.from_socket, mix_s.inputs["Fac"])
                nt.links.new(transp.outputs["BSDF"], mix_s.inputs[1])
                nt.links.new(emis.outputs["Emission"], mix_s.inputs[2])
                nt.links.new(mix_s.outputs["Shader"], out_n.inputs["Surface"])
            else:
                nt.links.new(emis.outputs["Emission"], out_n.inputs["Surface"])
            temp_mats.append(tm)

        for idx, tm in enumerate(temp_mats):
            lod0_obj.data.materials[idx] = tm

        scene = bpy.context.scene
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = 16
        scene.cycles.use_denoising = False
        scene.render.resolution_x = 256
        scene.render.resolution_y = 256
        scene.render.film_transparent = True
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.exposure = 0.0

        cam_data = bpy.data.cameras.new("BakeCam")
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = ortho_scale
        cam_obj = bpy.data.objects.new("BakeCam", cam_data)
        scene.collection.objects.link(cam_obj)
        scene.camera = cam_obj

        # 4 views: azimuth 0, 60, 120 at 10 deg elev + top-angled 38 deg view
        views = [(0.0, 10.0), (60.0, 10.0), (120.0, 10.0), (30.0, 38.0)]
        atlas = np.zeros((512, 512, 4), dtype=np.float32)
        for vi, (az_deg, el_deg) in enumerate(views):
            az = math.radians(az_deg)
            el = math.radians(el_deg)
            dist = ortho_scale * 2.5
            cam_pos = look_target + Vector((
                math.cos(el) * math.sin(az) * dist,
                -math.cos(el) * math.cos(az) * dist,
                math.sin(el) * dist,
            ))
            cam_obj.location = cam_pos
            cam_obj.rotation_euler = (look_target - cam_pos).to_track_quat("-Z", "Y").to_euler()
            tile_path = cache_dir / f"{name}_tile_{vi}.png"
            scene.render.filepath = str(tile_path)
            bpy.ops.render.render(write_still=True)

            img = bpy.data.images.load(str(tile_path), check_existing=False)
            px = np.array(img.pixels[:], dtype=np.float32).reshape((256, 256, 4))
            # Flip vertically because bpy image pixels start at bottom-left, row 0 = bottom
            bpy.data.images.remove(img)
            r0 = 256 if vi < 2 else 0
            c0 = (vi % 2) * 256
            atlas[r0 : r0 + 256, c0 : c0 + 256] = px

        # Clean up bake cam & restore materials
        bpy.data.objects.remove(cam_obj, do_unlink=True)
        bpy.data.cameras.remove(cam_data)
        for idx, om in enumerate(orig_mats):
            lod0_obj.data.materials[idx] = om
        for tm in temp_mats:
            bpy.data.materials.remove(tm)

        # Un-premultiply RGB where alpha > 0 before dilation so dark edges don't bleed!
        a = atlas[:, :, 3:4]
        safe_a = np.maximum(a, 1e-4)
        atlas[:, :, :3] = np.where(a > 0.08, np.clip(atlas[:, :, :3] / safe_a, 0.0, 1.0), 0.0)
        atlas_dil = dilate_rgba_numpy(atlas, threshold=0.25, passes=28)

        # Save baked atlas PNG via bpy.data.images
        atlas_path = cache_dir / f"{name}_lod1_atlas.png"
        out_img = bpy.data.images.new(f"{name}_lod1_atlas", width=512, height=512, alpha=True)
        out_img.pixels[:] = atlas_dil.ravel().tolist()
        out_img.filepath_raw = str(atlas_path)
        out_img.file_format = "PNG"
        out_img.save()

        # Create neutral flat normal + soft high-roughness ARM for LOD1 cards
        nor_path = cache_dir / f"{name}_lod1_nor.jpg"
        if not nor_path.exists():
            nor_img = bpy.data.images.new("lod1_flat_nor", width=64, height=64, alpha=False)
            nor_px = np.tile(np.array([0.5, 0.5, 1.0, 1.0], dtype=np.float32), (64 * 64, 1))
            nor_img.pixels[:] = nor_px.ravel().tolist()
            nor_img.filepath_raw = str(nor_path)
            nor_img.file_format = "JPEG"
            nor_img.save()
        arm_path = cache_dir / f"{name}_lod1_arm.jpg"
        if not arm_path.exists():
            arm_img = bpy.data.images.new("lod1_arm", width=64, height=64, alpha=False)
            arm_px = np.tile(np.array([0.88, 0.85, 0.0, 1.0], dtype=np.float32), (64 * 64, 1))
            arm_img.pixels[:] = arm_px.ravel().tolist()
            arm_img.filepath_raw = str(arm_path)
            arm_img.file_format = "JPEG"
            arm_img.save()

        # Build LOD1 crossed curved cards using the 4 baked quadrants:
        # Quadrant UV rects (Blender UV origin bottom-left):
        # tile 0: r=[256..512], c=[0..256]   -> u=[0..0.5], v=[0.5..1.0]
        # tile 1: r=[256..512], c=[256..512] -> u=[0.5..1.0], v=[0.5..1.0]
        # tile 2: r=[0..256], c=[0..256]     -> u=[0..0.5], v=[0..0.5]
        # tile 3: r=[0..256], c=[256..512]   -> u=[0.5..1.0], v=[0..0.5]
        uv_rects = [
            (0.01, 0.51, 0.49, 0.99),
            (0.51, 0.51, 0.99, 0.99),
            (0.01, 0.01, 0.49, 0.49),
            (0.51, 0.01, 0.99, 0.49),
        ]
        bm = bmesh.new()
        uv_layer = bm.loops.layers.uv.new("UVMap")

        half_s = ortho_scale * 0.5
        z_bot = center_z - half_s
        z_top = center_z + half_s

        # 3 splayed & gently curved vertical cards (2x2 grid each = 8 tris per card)
        for ci, az_deg in enumerate([0.0, 60.0, 120.0]):
            u0, v0, u1, v1 = uv_rects[ci]
            az = math.radians(az_deg)
            tilt = math.radians(10.0 * (1 if ci % 2 == 0 else -1))
            rot = Euler((tilt, 0.0, az), "XYZ").to_matrix()
            grid = []
            for iy, ty in enumerate([0.0, 0.5, 1.0]):
                row = []
                z = z_bot + ty * (z_top - z_bot)
                for ix, tx in enumerate([-1.0, 0.0, 1.0]):
                    x = tx * half_s
                    bow = (1.0 - tx * tx) * (half_s * 0.14)
                    p = rot @ Vector((x, bow, z - center_z)) + Vector((0.0, 0.0, center_z))
                    v = bm.verts.new(p)
                    row.append((v, u0 + (ix * 0.5) * (u1 - u0), v0 + ty * (v1 - v0)))
                grid.append(row)
            for iy in range(2):
                for ix in range(2):
                    a, ua, va = grid[iy][ix]
                    b, ub, vb = grid[iy][ix + 1]
                    c, uc, vc = grid[iy + 1][ix + 1]
                    d, ud, vd = grid[iy + 1][ix]
                    f1 = bm.faces.new((a, b, c))
                    f1.loops[0][uv_layer].uv = (ua, va)
                    f1.loops[1][uv_layer].uv = (ub, vb)
                    f1.loops[2][uv_layer].uv = (uc, vc)
                    f2 = bm.faces.new((a, c, d))
                    f2.loops[0][uv_layer].uv = (ua, va)
                    f2.loops[1][uv_layer].uv = (uc, vc)
                    f2.loops[2][uv_layer].uv = (ud, vd)

        # 1 angled crown fill card using tile 3 (top-angled view)
        u0, v0, u1, v1 = uv_rects[3]
        crown_rot = Euler((math.radians(52.0), 0.0, math.radians(30.0)), "XYZ").to_matrix()
        crown_z = center_z + half_s * 0.10
        c_pts = [
            (-half_s * 0.78, -half_s * 0.78, u0, v0),
            (half_s * 0.78, -half_s * 0.78, u1, v0),
            (half_s * 0.78, half_s * 0.78, u1, v1),
            (-half_s * 0.78, half_s * 0.78, u0, v1),
        ]
        c_verts = [
            (bm.verts.new(crown_rot @ Vector((px, py, 0.0)) + Vector((0.0, 0.0, crown_z))), uu, vv)
            for px, py, uu, vv in c_pts
        ]
        for tri in ((0, 1, 2), (0, 2, 3)):
            f = bm.faces.new([c_verts[k][0] for k in tri])
            for j, k in enumerate(tri):
                f.loops[j][uv_layer].uv = (c_verts[k][1], c_verts[k][2])

        lod1_mesh = bpy.data.meshes.new(f"{name}_lod1")
        bm.to_mesh(lod1_mesh)
        bm.free()
        lod1_obj = bpy.data.objects.new(f"{name}_lod1", lod1_mesh)
        scene.collection.objects.link(lod1_obj)

        mat_lod1 = make_pbr_material(
            target_mat_name,
            {"diff": str(atlas_path), "nor": str(nor_path), "arm": str(arm_path)},
            alpha_mode="MASK",
            alpha_cutoff=alpha_cutoff,
        )
        lod1_obj.data.materials.append(mat_lod1)
        return lod1_obj

    # ---- Builders per Variant ----
    rng = random.Random(20261125)
    results = []
    variants = set(args.variants)

    def build_grass_short():
        reset_scene()
        parts = import_gltf_map(src_repo / "grass_medium_01" / "grass_medium_01_4k.gltf")
        # Dense low turf patch (~0.58 m wide, 0.14 m tall) from small & mid clumps (no seed-head cards)
        layout = [
            ("grass_medium_01_mid_c_LOD0", (0.00, 0.00, 0.0), (0, 0, 12), 0.92),
            ("grass_medium_01_small_a_LOD0", (0.14, 0.08, 0.0), (4, -3, 78), 0.98),
            ("grass_medium_01_small_b_LOD0", (-0.15, 0.07, 0.0), (-3, 5, 152), 1.05),
            ("grass_medium_01_small_a_LOD0", (-0.10, -0.14, 0.0), (5, 2, 238), 0.94),
            ("grass_medium_01_small_b_LOD0", (0.13, -0.12, 0.0), (-4, -4, 310), 1.02),
            ("grass_medium_01_tiny_a_LOD0", (0.04, 0.18, 0.0), (0, 0, 40), 1.15),
        ]
        insts = [bake_obj_transform(parts[n], loc, rot, sc) for n, loc, rot, sc in layout]
        obj = join_objects(insts, "grass_short_lod0")
        decimate_obj(obj, 310)
        ground_and_sink(obj, -0.035)
        mat = make_pbr_material("grass_short_mat", tex_manifest["grass_short"], "OPAQUE")
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        apply_vertex_attributes(obj, flex_power=1.20, root_ao_min=0.80, normal_up_blend=0.70)
        results.append(verify_bounds_and_export(obj, out_dir / "grass_short_lod0.glb"))

        lod1 = bake_lod1_cards(obj, "grass_short", "grass_short_lod1_mat", alpha_cutoff=0.36)
        apply_vertex_attributes(lod1, flex_power=1.15, root_ao_min=0.82, normal_up_blend=0.72)
        results.append(verify_bounds_and_export(lod1, out_dir / "grass_short_lod1.glb"))

    def build_grass_meadow():
        reset_scene()
        parts = import_gltf_map(src_repo / "grass_medium_02" / "grass_medium_02_4k.gltf")
        # Layered 15-38 cm meadow grass patch (~0.66 m wide) mixing green & dry straw blades
        layout = [
            ("grass_medium_02_d", (0.00, 0.00, 0.0), (2, -2, 18), 0.95),
            ("grass_medium_02_e", (0.12, 0.09, 0.0), (-3, 4, 96), 0.88),
            ("grass_medium_02_c", (-0.16, 0.06, 0.0), (4, 3, 174), 0.96),
            ("grass_medium_02_b", (-0.11, -0.15, 0.0), (-2, -4, 248), 1.05),
            ("grass_medium_02_a", (0.15, -0.13, 0.0), (3, -2, 312), 1.08),
            ("grass_medium_02_c", (0.02, -0.18, 0.0), (-4, 2, 55), 0.90),
        ]
        insts = [bake_obj_transform(parts[n], loc, rot, sc) for n, loc, rot, sc in layout]
        obj = join_objects(insts, "grass_meadow_lod0")
        decimate_obj(obj, 380)
        ground_and_sink(obj, -0.04)
        mat = make_pbr_material("grass_meadow_mat", tex_manifest["grass_meadow"], "OPAQUE")
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        apply_vertex_attributes(obj, flex_power=1.15, root_ao_min=0.78, normal_up_blend=0.68)
        results.append(verify_bounds_and_export(obj, out_dir / "grass_meadow_lod0.glb"))

        lod1 = bake_lod1_cards(obj, "grass_meadow", "grass_meadow_lod1_mat", alpha_cutoff=0.34)
        apply_vertex_attributes(lod1, flex_power=1.15, root_ao_min=0.80, normal_up_blend=0.70)
        results.append(verify_bounds_and_export(lod1, out_dir / "grass_meadow_lod1.glb"))

    def build_grass_tall_verge():
        reset_scene()
        parts = import_gltf_map(src_repo / "grass_medium_01" / "grass_medium_01_4k.gltf")
        # Tall 45-70 cm roadside verge grass with feathery seed heads + dense lower collar
        layout = [
            ("grass_medium_01_tall_a_LOD0", (0.00, 0.00, 0.0), (3, -2, 15), 2.15),
            ("grass_medium_01_tall_b_LOD0", (0.14, 0.09, 0.0), (-4, 3, 128), 2.05),
            ("grass_medium_01_tall_c_LOD0", (-0.13, -0.08, 0.0), (2, 5, 244), 2.25),
            ("grass_medium_01_mid_a_LOD0", (-0.11, 0.12, 0.0), (0, -3, 62), 1.45),
            ("grass_medium_01_mid_b_LOD0", (0.12, -0.13, 0.0), (-3, 0, 195), 1.40),
        ]
        insts = [bake_obj_transform(parts[n], loc, rot, sc) for n, loc, rot, sc in layout]
        obj = join_objects(insts, "grass_tall_verge_lod0")
        decimate_obj(obj, 420)
        ground_and_sink(obj, -0.045)
        mat = make_pbr_material(
            "grass_tall_verge_mat", tex_manifest["grass_tall_verge"], "MASK", alpha_cutoff=0.38
        )
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        apply_vertex_attributes(obj, flex_power=1.22, root_ao_min=0.78, normal_up_blend=0.66)
        results.append(verify_bounds_and_export(obj, out_dir / "grass_tall_verge_lod0.glb"))

        lod1 = bake_lod1_cards(obj, "grass_tall_verge", "grass_tall_verge_lod1_mat", alpha_cutoff=0.34)
        apply_vertex_attributes(lod1, flex_power=1.20, root_ao_min=0.80, normal_up_blend=0.68)
        results.append(verify_bounds_and_export(lod1, out_dir / "grass_tall_verge_lod1.glb"))

    def build_fern():
        reset_scene()
        parts = import_gltf_map(src_repo / "fern_02" / "fern_02_4k.gltf")
        # Build natural 1.0 m diameter fern rosette by clustering 2 staggered fern clumps (~10-12 fronds)
        # LOD0: decimated 3D arched fronds (~380 tris); LOD1: simplified 3D fronds (~48 tris - keeps 3D arch!)
        layout_lod0 = [
            ("fern_02_b", (0.00, 0.00, 0.00), (0, 0, 0), 1.08),
            ("fern_02_c", (0.03, -0.02, 0.02), (5, -4, 48), 0.96),
            ("fern_02_a", (-0.02, 0.03, 0.04), (-6, 5, 132), 0.85),
        ]
        insts0 = [bake_obj_transform(parts[n], loc, rot, sc) for n, loc, rot, sc in layout_lod0]
        obj0 = join_objects(insts0, "fern_lod0")
        decimate_obj(obj0, 390)
        ground_and_sink(obj0, -0.04)
        mat = make_pbr_material("fern_mat", tex_manifest["fern"], "MASK", alpha_cutoff=0.42)
        obj0.data.materials.clear()
        obj0.data.materials.append(mat)
        apply_vertex_attributes(obj0, flex_power=1.10, root_ao_min=0.75, normal_up_blend=0.60)
        results.append(verify_bounds_and_export(obj0, out_dir / "fern_lod0.glb"))

        # LOD1: simplified 3D fronds (preserves drooping fern rosette silhouette from every angle)
        layout_lod1 = [
            ("fern_02_b", (0.00, 0.00, 0.00), (0, 0, 0), 1.10),
            ("fern_02_c", (0.02, -0.02, 0.02), (4, -3, 52), 0.95),
        ]
        insts1 = [bake_obj_transform(parts[n], loc, rot, sc) for n, loc, rot, sc in layout_lod1]
        obj1 = join_objects(insts1, "fern_lod1")
        decimate_obj(obj1, 72)
        ground_and_sink(obj1, -0.04)
        obj1.data.materials.clear()
        obj1.data.materials.append(mat)
        apply_vertex_attributes(obj1, flex_power=1.10, root_ao_min=0.76, normal_up_blend=0.62)
        results.append(verify_bounds_and_export(obj1, out_dir / "fern_lod1.glb"))

    def build_wildflower():
        reset_scene()
        parts = import_gltf_map(src_repo / "celandine_01" / "celandine_01_4k.gltf")
        layout = [
            ("celandine_01_c_LOD0", (0.00, 0.00, 0.0), (0, 0, 10), 1.25),
            ("celandine_01_d_LOD0", (0.14, 0.08, 0.0), (4, -3, 82), 1.20),
            ("celandine_01_a_LOD0", (-0.15, 0.07, 0.0), (-3, 4, 170), 1.15),
            ("celandine_01_b_LOD0", (-0.08, -0.14, 0.0), (3, 3, 255), 1.18),
            ("celandine_01_e_LOD0", (0.12, -0.12, 0.0), (-4, -2, 325), 1.22),
        ]
        insts = [bake_obj_transform(parts[n], loc, rot, sc) for n, loc, rot, sc in layout]
        obj = join_objects(insts, "wildflower_lod0")
        decimate_obj(obj, 420)
        ground_and_sink(obj, -0.035)
        mat = make_pbr_material("wildflower_mat", tex_manifest["wildflower"], "MASK", alpha_cutoff=0.40)
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        apply_vertex_attributes(obj, flex_power=1.12, root_ao_min=0.78, normal_up_blend=0.62)
        results.append(verify_bounds_and_export(obj, out_dir / "wildflower_lod0.glb"))

        lod1 = bake_lod1_cards(obj, "wildflower", "wildflower_lod1_mat", alpha_cutoff=0.35)
        apply_vertex_attributes(lod1, flex_power=1.10, root_ao_min=0.80, normal_up_blend=0.64)
        results.append(verify_bounds_and_export(lod1, out_dir / "wildflower_lod1.glb"))

    def build_shrub_woodland():
        reset_scene()
        parts = import_gltf_map(ext_cache / "shrub_02" / "4k" / "shrub_02_4k.gltf")
        # Multi-stemmed 1.28 m tall x 1.45 m wide woodland shrub built from shrub_02_a..d
        # Notice shrub_02_a..d lean in -X/-Y originally; arrange radially outward like a real multi-stem bush!
        layout = [
            ("shrub_02_a", (0.04, 0.02, 0.00), (8, -6, 15), 0.82),
            ("shrub_02_b", (-0.05, 0.04, 0.00), (-10, 8, 92), 0.92),
            ("shrub_02_d", (0.02, -0.06, 0.00), (12, 6, 178), 0.88),
            ("shrub_02_b", (-0.04, -0.03, 0.00), (-8, -10, 265), 0.86),
            ("shrub_02_c", (0.00, 0.03, 0.02), (16, -12, 325), 0.78),
        ]
        insts = [bake_obj_transform(parts[n], loc, rot, sc) for n, loc, rot, sc in layout]
        obj = join_objects(insts, "shrub_woodland_lod0")

        # Assign Surface 0 = bark (UV u < 0.165), Surface 1 = foliage (UV u >= 0.165) BEFORE decimation
        # Actually split into two temp objects by polygon UV centroid so decimation preserves bark vs foliage!
        mesh = obj.data
        uv_layer = mesh.uv_layers.active.data
        bark_mat = make_pbr_material("bark", tex_manifest["shrub_woodland_bark"], "OPAQUE")
        fol_mat = make_pbr_material(
            "foliage", tex_manifest["shrub_woodland_foliage"], "MASK", alpha_cutoff=0.40
        )

        mesh.materials.clear()
        mesh.materials.append(bark_mat)  # Slot 0
        mesh.materials.append(fol_mat)   # Slot 1

        # Separate bark vs foliage, decimate each cleanly, then rejoin
        bm_bark = bmesh.new()
        bm_fol = bmesh.new()
        bm_all = bmesh.new()
        bm_all.from_mesh(mesh)
        uv_bm = bm_all.loops.layers.uv.active

        # Copy UV and split faces
        def copy_faces_to_bm(src_bm, dst_bm, predicate):
            dst_uv = dst_bm.loops.layers.uv.new("UVMap")
            vmap = {}
            for face in src_bm.faces:
                u_avg = sum(l[uv_bm].uv.x for l in face.loops) / len(face.loops)
                if not predicate(u_avg):
                    continue
                new_verts = []
                for v in face.verts:
                    if v.index not in vmap:
                        vmap[v.index] = dst_bm.verts.new(v.co)
                    new_verts.append(vmap[v.index])
                try:
                    nf = dst_bm.faces.new(new_verts)
                    for i, l in enumerate(face.loops):
                        nf.loops[i][dst_uv].uv = l[uv_bm].uv
                except ValueError:
                    pass

        copy_faces_to_bm(bm_all, bm_bark, lambda u: u < 0.165)
        copy_faces_to_bm(bm_all, bm_fol, lambda u: u >= 0.165)
        bm_all.free()

        m_bark = bpy.data.meshes.new("shrub_bark_tmp")
        bm_bark.to_mesh(m_bark)
        bm_bark.free()
        o_bark = bpy.data.objects.new("shrub_bark_tmp", m_bark)
        bpy.context.scene.collection.objects.link(o_bark)
        o_bark.data.materials.append(bark_mat)
        decimate_obj(o_bark, 340)

        m_fol = bpy.data.meshes.new("shrub_fol_tmp")
        bm_fol.to_mesh(m_fol)
        bm_fol.free()
        o_fol = bpy.data.objects.new("shrub_fol_tmp", m_fol)
        bpy.context.scene.collection.objects.link(o_fol)
        o_fol.data.materials.append(fol_mat)
        decimate_obj(o_fol, 1550)

        bpy.data.objects.remove(obj, do_unlink=True)
        lod0 = join_objects([o_bark, o_fol], "shrub_woodland_lod0")
        ground_and_sink(lod0, -0.07)
        apply_vertex_attributes(
            lod0, flex_power=1.25, root_ao_min=0.72, normal_up_blend=0.62, anchor_z=0.04
        )
        results.append(verify_bounds_and_export(lod0, out_dir / "shrub_woodland_lod0.glb"))

        # LOD1: Keep Surface 0 = simplified bark (~80 tris) + Surface 1 = crossed foliage cards (~24 tris)
        # Bake foliage-only LOD1 card atlas by hiding Surface 0 temporarily or rendering whole shrub as foliage card + stem core
        o_bark_l1 = lod0.copy()
        o_bark_l1.data = lod0.data.copy()
        bpy.context.scene.collection.objects.link(o_bark_l1)
        # Keep only Surface 0 on o_bark_l1
        bm1 = bmesh.new()
        bm1.from_mesh(o_bark_l1.data)
        for f in [f for f in bm1.faces if f.material_index != 0]:
            bm1.faces.remove(f)
        bm1.to_mesh(o_bark_l1.data)
        bm1.free()
        while len(o_bark_l1.data.materials) > 1:
            o_bark_l1.data.materials.pop(index=1)
        decimate_obj(o_bark_l1, 90)

        # Bake foliage-only LOD1 cards — MUST use a foliage-only temp object so bark
        # (reddish/brown opaque Voronoi surface) doesn't bleed into the ortho renders.
        o_fol_bake = lod0.copy()
        o_fol_bake.data = lod0.data.copy()
        o_fol_bake.name = "shrub_fol_bake_tmp"
        bpy.context.scene.collection.objects.link(o_fol_bake)
        # Strip all faces that are NOT foliage (material_index != 1)
        bm_tmp = bmesh.new()
        bm_tmp.from_mesh(o_fol_bake.data)
        for f in [f for f in bm_tmp.faces if f.material_index != 1]:
            bm_tmp.faces.remove(f)
        bm_tmp.to_mesh(o_fol_bake.data)
        bm_tmp.free()
        # Remove bark material slot (index 0); keep only foliage (now at index 0)
        while len(o_fol_bake.data.materials) > 1:
            o_fol_bake.data.materials.pop(index=0)
        # Remap material indices so the remaining foliage slot is 0
        for poly in o_fol_bake.data.polygons:
            poly.material_index = 0
        fol_cards = bake_lod1_cards(o_fol_bake, "shrub_woodland", "foliage", alpha_cutoff=0.35)
        bpy.data.objects.remove(o_fol_bake, do_unlink=True)
        lod1 = join_objects([o_bark_l1, fol_cards], "shrub_woodland_lod1")
        apply_vertex_attributes(
            lod1, flex_power=1.20, root_ao_min=0.76, normal_up_blend=0.64, anchor_z=0.04
        )
        results.append(verify_bounds_and_export(lod1, out_dir / "shrub_woodland_lod1.glb"))

    def build_rock_moss():
        reset_scene()
        parts = import_gltf_map(ext_cache / "rock_moss_set_02" / "4k" / "rock_moss_set_02_4k.gltf")
        layout = [
            ("rock_moss_set_02_rock10", (0.00, 0.00, 0.00), (0, 0, 12), 0.72),
            ("rock_moss_set_02_rock08", (0.52, 0.18, -0.02), (5, -8, 118), 0.68),
            ("rock_moss_set_02_rock09", (-0.45, -0.22, -0.02), (-4, 6, 232), 0.65),
        ]
        insts = [bake_obj_transform(parts[n], loc, rot, sc) for n, loc, rot, sc in layout]
        obj0 = join_objects(insts, "rock_moss_lod0")
        ground_and_sink(obj0, -0.14)
        mat = make_pbr_material("rock_moss_mat", tex_manifest["rock_moss"], "OPAQUE", roughness_scale=0.95)
        obj0.data.materials.clear()
        obj0.data.materials.append(mat)

        obj1 = obj0.copy()
        obj1.data = obj0.data.copy()
        obj1.name = "rock_moss_lod1"
        bpy.context.scene.collection.objects.link(obj1)

        decimate_obj(obj0, 900)
        apply_vertex_attributes(obj0, is_rock=True)
        results.append(verify_bounds_and_export(obj0, out_dir / "rock_moss_lod0.glb"))

        decimate_obj(obj1, 260)
        # Second pass: collapse decimate is inexact — re-apply if still above target
        actual_tris = len(obj1.data.polygons)
        if actual_tris > 300:
            print(f"rock_moss_lod1 first-pass tris={actual_tris} > 300, re-applying decimate to 260")
            mod2 = obj1.modifiers.new("Decimate2", "DECIMATE")
            mod2.decimate_type = "COLLAPSE"
            mod2.ratio = max(0.03, 260.0 / float(actual_tris))
            mod2.use_collapse_triangulate = True
            bpy.context.view_layer.objects.active = obj1
            bpy.ops.object.modifier_apply(modifier=mod2.name)
            print(f"rock_moss_lod1 after re-decimate: tris={len(obj1.data.polygons)}")
        apply_vertex_attributes(obj1, is_rock=True)
        results.append(verify_bounds_and_export(obj1, out_dir / "rock_moss_lod1.glb"))

    builders = {
        "grass_short": build_grass_short,
        "grass_meadow": build_grass_meadow,
        "grass_tall_verge": build_grass_tall_verge,
        "fern": build_fern,
        "wildflower": build_wildflower,
        "shrub_woodland": build_shrub_woodland,
        "rock_moss": build_rock_moss,
    }
    for name in args.variants:
        if name in builders:
            builders[name]()

    # Save export stats manifest
    (out_dir / "undergrowth_manifest.json").write_text(
        json.dumps({"assets": results}, indent=2), encoding="utf-8"
    )

    if args.skip_renders:
        return

    # ---- Contact Sheet Rendering (Cycles CPU + AgX Daylight, zero GPU contention) ----
    def render_contact_sheet():
        reset_scene()
        scene = bpy.context.scene
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = 24
        scene.cycles.use_denoising = True
        scene.render.resolution_x = 1600
        scene.render.resolution_y = 900
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.exposure = 0.0

        world = bpy.data.worlds.new("Daylight")
        scene.world = world
        world.use_nodes = True
        bg = world.node_tree.nodes["Background"]
        bg.inputs[0].default_value = (0.45, 0.56, 0.68, 1.0)
        bg.inputs[1].default_value = 0.85

        sun_d = bpy.data.lights.new("Sun", "SUN")
        sun_d.energy = 3.2
        sun_d.angle = math.radians(0.8)
        sun_o = bpy.data.objects.new("Sun", sun_d)
        scene.collection.objects.link(sun_o)
        sun_o.rotation_euler = (math.radians(46), math.radians(12), math.radians(38))

        # Ground plane matching calibrated Forza meadow grass color (sRGB ~ [58, 86, 23] -> linear ~ [0.042, 0.094, 0.008])
        bpy.ops.mesh.primitive_plane_add(size=18.0, location=(0, 0, 0))
        gnd = bpy.context.active_object
        gmat = bpy.data.materials.new("Ground")
        gmat.use_nodes = True
        gbsdf = gmat.node_tree.nodes["Principled BSDF"]
        gbsdf.inputs["Base Color"].default_value = (0.048, 0.088, 0.014, 1.0)
        gbsdf.inputs["Roughness"].default_value = 0.92
        gnd.data.materials.append(gmat)

        # Line up LOD0 (front row y=0) and LOD1 (back row y=1.35) across X
        order = [
            ("grass_short", -2.5),
            ("grass_meadow", -1.65),
            ("grass_tall_verge", -0.80),
            ("wildflower", 0.05),
            ("fern", 0.95),
            ("shrub_woodland", 2.25),
            ("rock_moss", 3.85),
        ]
        for vname, px in order:
            for lod, py in [("lod0", 0.0), ("lod1", 1.35)]:
                gp = out_dir / f"{vname}_{lod}.glb"
                if not gp.exists():
                    continue
                before = set(bpy.data.objects.keys())
                bpy.ops.import_scene.gltf(filepath=str(gp))
                after = set(bpy.data.objects.keys())
                for k in after - before:
                    o = bpy.data.objects[k]
                    o.location = (px, py, 0.0)

        cam_d = bpy.data.cameras.new("Cam")
        cam_o = bpy.data.objects.new("Cam", cam_d)
        scene.collection.objects.link(cam_o)
        scene.camera = cam_o

        # Shot 1: Overview 3/4 (LOD0 front, LOD1 behind)
        cam_o.location = (0.55, -4.8, 1.85)
        cam_o.rotation_euler = (Vector((0.55, 0.45, 0.35)) - cam_o.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(sheet_dir / "undergrowth_overview_lod0_lod1.png")
        bpy.ops.render.render(write_still=True)

        # Shot 2: Low driving-eye close-up on grass + wildflower + fern LOD0
        cam_o.location = (-0.85, -2.15, 0.52)
        cam_o.rotation_euler = (Vector((-0.45, 0.0, 0.22)) - cam_o.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(sheet_dir / "undergrowth_closeup_grass_fern.png")
        bpy.ops.render.render(write_still=True)

        # Shot 3: Close-up on shrub_woodland + rock_moss LOD0 vs LOD1
        cam_o.location = (2.8, -2.8, 1.05)
        cam_o.rotation_euler = (Vector((2.7, 0.5, 0.45)) - cam_o.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(sheet_dir / "undergrowth_closeup_shrub_rock.png")
        bpy.ops.render.render(write_still=True)

        # Shot 4: Top-down silhouette & alpha coverage check
        cam_o.location = (0.65, 0.65, 6.2)
        cam_o.rotation_euler = (Vector((0.65, 0.65, 0.0)) - cam_o.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(sheet_dir / "undergrowth_topdown.png")
        bpy.ops.render.render(write_still=True)

    render_contact_sheet()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blender", default=DEFAULT_BLENDER)
    parser.add_argument("--ext-cache", default=DEFAULT_EXT_CACHE)
    parser.add_argument(
        "--sheet-dir",
        default=str(Path(tempfile.gettempdir()) / "aster_undergrowth_sheets"),
    )
    parser.add_argument("--cache-dir", default=str(Path(tempfile.gettempdir()) / "aster_undergrowth_cache"))
    parser.add_argument(
        "--variants",
        nargs="+",
        default=["grass_short", "grass_meadow", "grass_tall_verge", "fern", "wildflower", "shrub_woodland", "rock_moss"],
    )
    parser.add_argument("--skip-renders", action="store_true")
    parser.add_argument("--blender-worker", action="store_true", help=argparse.SUPPRESS)
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    args = parser.parse_args(argv)

    # Auto-detect Blender execution context: if 'bpy' is importable we ARE inside
    # Blender's Python — skip host-only texture prep and go straight to blender_worker.
    try:
        import bpy as _bpy_probe  # noqa: F401
        _in_blender = True
    except ImportError:
        _in_blender = False

    if args.blender_worker or _in_blender:
        blender_worker(args)
        return

    repo_root = _repo_root()
    cache_dir = Path(args.cache_dir)
    prepare_all_textures(repo_root, Path(args.ext_cache), cache_dir)

    cmd = [
        args.blender,
        "-b",
        "-P",
        str(Path(__file__).resolve()),
        "--",
        "--blender-worker",
        "--ext-cache",
        args.ext_cache,
        "--sheet-dir",
        args.sheet_dir,
        "--cache-dir",
        str(cache_dir),
        "--variants",
        *args.variants,
    ]
    if args.skip_renders:
        cmd.append("--skip-renders")
    subprocess.run(cmd, check=True)


if __name__ == "__main__":
    main()
