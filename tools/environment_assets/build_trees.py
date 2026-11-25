#!/usr/bin/env python3
"""Author realistic temperate tree textures, 5 species x 3 LOD GLBs, and contact sheets.

Run via Blender 4.5.10:
    blender --background --python tools/environment_assets/build_trees.py -- --stage all
    blender --background --python tools/environment_assets/build_trees.py -- --stage textures
    blender --background --python tools/environment_assets/build_trees.py -- --stage meshes
    blender --background --python tools/environment_assets/build_trees.py -- --stage render
"""

import argparse
import json
import math
import os
import random
import struct
import sys
import zlib
from pathlib import Path

import bpy
import bmesh
from mathutils import Euler, Matrix, Quaternion, Vector
import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = REPO_ROOT / "assets" / "environment_realism" / "trees"
TEX_DIR = OUT_DIR / "textures"
FORZA_BARK_DIR = REPO_ROOT / "assets" / "forza_env" / "textures" / "bark"
SOURCE_ROOT = Path(
    os.environ.get("ASTER_ASSET_SOURCE_ROOT", r"C:\Users\anshu\Documents\Coding\aster-valley-asset-source")
)
DEFAULT_PREVIEW_DIR = Path(
    r"C:\Users\anshu\.gemini\antigravity\brain\53412b0e-23fc-4051-a661-de2bfd204602"
)

ATLAS_RES = 1024
BARK_RES = 1024


# ---------------------------------------------------------------------------
# Image & Array Utilities (pure NumPy + stdlib zlib + Blender image loader)
# ---------------------------------------------------------------------------

def write_png(path: Path, arr_u8: np.ndarray) -> None:
    """Write an (H, W, 3) or (H, W, 4) uint8 array as a valid PNG."""
    h, w, c = arr_u8.shape
    assert c in (3, 4)
    color_type = 6 if c == 4 else 2
    raw = b"".join(b"\x00" + arr_u8[y].tobytes() for y in range(h))
    compressed = zlib.compress(raw, level=6)

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, color_type, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def load_blender_image_rgba(path: Path) -> np.ndarray:
    """Load an image via Blender and return top-down (H, W, 4) float32 array in [0, 1]."""
    img = bpy.data.images.load(str(path), check_existing=False)
    w, h = img.size
    arr = np.array(img.pixels[:], dtype=np.float32).reshape((h, w, 4))
    bpy.data.images.remove(img)
    return np.ascontiguousarray(arr[::-1])


def downsample_u8(src_arr: np.ndarray, target_size: int) -> np.ndarray:
    """Box-downsample an (H, W, C) uint8 array to (target_size, target_size, C)."""
    h, _w, c = src_arr.shape
    factor = max(1, h // target_size)
    if factor > 1:
        trimmed = src_arr[: target_size * factor, : target_size * factor, :c]
        down = trimmed.reshape(target_size, factor, target_size, factor, c).mean(axis=(1, 3))
        return np.clip(np.rint(down), 0, 255).astype(np.uint8)
    return src_arr[:, :, :c]


def resize_u8_bilinear(src_arr: np.ndarray, target_h: int, target_w: int) -> np.ndarray:
    """Bilinear resize an (H, W, C) uint8 array in pure NumPy."""
    h, w, _c = src_arr.shape
    if h == target_h and w == target_w:
        return src_arr
    ys = np.linspace(0, h - 1, target_h, dtype=np.float32)[:, None]
    xs = np.linspace(0, w - 1, target_w, dtype=np.float32)[None, :]
    y0 = np.floor(ys).astype(np.int32)
    x0 = np.floor(xs).astype(np.int32)
    y1 = np.minimum(y0 + 1, h - 1)
    x1 = np.minimum(x0 + 1, w - 1)
    fy = (ys - y0)[..., None]
    fx = (xs - x0)[..., None]
    src_f = src_arr.astype(np.float32)
    out = (
        src_f[y0, x0] * (1.0 - fy) * (1.0 - fx)
        + src_f[y0, x1] * (1.0 - fy) * fx
        + src_f[y1, x0] * fy * (1.0 - fx)
        + src_f[y1, x1] * fy * fx
    )
    return np.clip(np.rint(out), 0, 255).astype(np.uint8)


def jump_flood_indices(mask_solid: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Compute nearest solid pixel indices once via Jump Flooding in NumPy."""
    h, w = mask_solid.shape
    ys, xs = np.mgrid[0:h, 0:w]
    seed_y = np.where(mask_solid, ys, -1).astype(np.int32)
    seed_x = np.where(mask_solid, xs, -1).astype(np.int32)
    best_d2 = np.where(mask_solid, 0, 1 << 29).astype(np.int64)

    step = 1
    while step < max(h, w):
        step *= 2
    step //= 2
    steps = []
    s = step
    while s >= 1:
        steps.append(s)
        s //= 2
    steps.extend([2, 1])

    for s in steps:
        for dy in (-s, 0, s):
            for dx in (-s, 0, s):
                if dy == 0 and dx == 0:
                    continue
                ny = np.clip(ys + dy, 0, h - 1)
                nx = np.clip(xs + dx, 0, w - 1)
                sy = seed_y[ny, nx]
                sx = seed_x[ny, nx]
                valid = sy >= 0
                d2 = np.where(valid, (ys - sy) ** 2 + (xs - sx) ** 2, 1 << 29)
                better = d2 < best_d2
                best_d2 = np.where(better, d2, best_d2)
                seed_y = np.where(better, sy, seed_y)
                seed_x = np.where(better, sx, seed_x)

    return np.clip(seed_y, 0, h - 1), np.clip(seed_x, 0, w - 1)


def linear_to_srgb(lin: np.ndarray) -> np.ndarray:
    c = np.clip(lin, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def srgb_to_linear(srgb: np.ndarray) -> np.ndarray:
    c = np.clip(srgb, 0.0, 1.0)
    return np.where(c <= 0.04045, c / 12.92, np.power((c + 0.055) / 1.055, 2.4))


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ---------------------------------------------------------------------------
# Stage 1: Photorealistic Botanical Atlases & Bark PBR Sets
# ---------------------------------------------------------------------------

def _make_leafset_material(
    name: str,
    mode: str,
    col_img_path: Path,
    opa_img_path: Path,
    nrm_img_path: Path,
    rgh_img_path: Path,
    tint_shift: tuple[float, float, float],
) -> bpy.types.Material:
    """Create material using real scanned ambientCG LeafSet Color/Opacity/Normal/Roughness."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    transparent = nt.nodes.new("ShaderNodeBsdfTransparent")
    emit = nt.nodes.new("ShaderNodeEmission")
    mix_alpha = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(transparent.outputs["BSDF"], mix_alpha.inputs[1])
    nt.links.new(emit.outputs["Emission"], mix_alpha.inputs[2])
    nt.links.new(mix_alpha.outputs["Shader"], out.inputs["Surface"])

    tex_coord = nt.nodes.new("ShaderNodeTexCoord")
    img_opa = bpy.data.images.load(str(opa_img_path), check_existing=True)
    img_opa.colorspace_settings.name = "Non-Color"
    n_opa = nt.nodes.new("ShaderNodeTexImage")
    n_opa.image = img_opa
    nt.links.new(tex_coord.outputs["UV"], n_opa.inputs["Vector"])

    # Hard threshold at 0.35 for clean silhouette without JPEG opacity noise
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    ramp.color_ramp.elements[1].position = 0.55
    ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    nt.links.new(n_opa.outputs["Color"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], mix_alpha.inputs["Fac"])

    if mode == "albedo":
        img_col = bpy.data.images.load(str(col_img_path), check_existing=True)
        img_col.colorspace_settings.name = "sRGB"
        n_col = nt.nodes.new("ShaderNodeTexImage")
        n_col.image = img_col
        nt.links.new(tex_coord.outputs["UV"], n_col.inputs["Vector"])

        vcol = nt.nodes.new("ShaderNodeVertexColor")
        vcol.layer_name = "Col"

        mul_tint = nt.nodes.new("ShaderNodeMix")
        mul_tint.data_type = "RGBA"
        mul_tint.blend_type = "MULTIPLY"
        mul_tint.inputs["Factor"].default_value = 1.0
        mul_tint.inputs["B"].default_value = (*tint_shift, 1.0)
        nt.links.new(n_col.outputs["Color"], mul_tint.inputs["A"])

        mul_vc = nt.nodes.new("ShaderNodeMix")
        mul_vc.data_type = "RGBA"
        mul_vc.blend_type = "MULTIPLY"
        mul_vc.inputs["Factor"].default_value = 1.0
        nt.links.new(mul_tint.outputs["Result"], mul_vc.inputs["A"])
        nt.links.new(vcol.outputs["Color"], mul_vc.inputs["B"])
        nt.links.new(mul_vc.outputs["Result"], emit.inputs["Color"])

    elif mode == "normal":
        # Combine mesh geometry normal with scanned leaf vein normal perturbation
        geom = nt.nodes.new("ShaderNodeNewGeometry")
        img_nrm = bpy.data.images.load(str(nrm_img_path), check_existing=True)
        img_nrm.colorspace_settings.name = "Non-Color"
        n_nrm = nt.nodes.new("ShaderNodeTexImage")
        n_nrm.image = img_nrm
        nt.links.new(tex_coord.outputs["UV"], n_nrm.inputs["Vector"])

        # Decode texture normal (0..1 -> -1..1) and blend 35% vein perturbation onto geometry normal
        sub = nt.nodes.new("ShaderNodeVectorMath")
        sub.operation = "SUBTRACT"
        sub.inputs[1].default_value = (0.5, 0.5, 0.5)
        nt.links.new(n_nrm.outputs["Color"], sub.inputs[0])

        scale_v = nt.nodes.new("ShaderNodeVectorMath")
        scale_v.operation = "SCALE"
        scale_v.inputs["Scale"].default_value = 0.70
        nt.links.new(sub.outputs["Vector"], scale_v.inputs[0])

        add_g = nt.nodes.new("ShaderNodeVectorMath")
        add_g.operation = "ADD"
        nt.links.new(geom.outputs["Normal"], add_g.inputs[0])
        nt.links.new(scale_v.outputs["Vector"], add_g.inputs[1])

        norm = nt.nodes.new("ShaderNodeVectorMath")
        norm.operation = "NORMALIZE"
        nt.links.new(add_g.outputs["Vector"], norm.inputs[0])

        mul_half = nt.nodes.new("ShaderNodeVectorMath")
        mul_half.operation = "SCALE"
        mul_half.inputs["Scale"].default_value = 0.5
        nt.links.new(norm.outputs["Vector"], mul_half.inputs[0])

        add_half = nt.nodes.new("ShaderNodeVectorMath")
        add_half.operation = "ADD"
        add_half.inputs[1].default_value = (0.5, 0.5, 0.5)
        nt.links.new(mul_half.outputs["Vector"], add_half.inputs[0])
        nt.links.new(add_half.outputs["Vector"], emit.inputs["Color"])

    elif mode == "roughness":
        img_rgh = bpy.data.images.load(str(rgh_img_path), check_existing=True)
        img_rgh.colorspace_settings.name = "Non-Color"
        n_rgh = nt.nodes.new("ShaderNodeTexImage")
        n_rgh.image = img_rgh
        nt.links.new(tex_coord.outputs["UV"], n_rgh.inputs["Vector"])
        nt.links.new(n_rgh.outputs["Color"], emit.inputs["Color"])

    return mat


def _make_unlit_procedural_material(
    name: str,
    mode: str,
    base_col_a: tuple,
    base_col_b: tuple,
    vein_col: tuple,
    rough_range: tuple,
    is_wood: bool = False,
) -> bpy.types.Material:
    """Create procedural unlit Albedo/Normal/Roughness shader for 3D needles & woody twigs."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])

    if mode == "normal":
        geom = nt.nodes.new("ShaderNodeNewGeometry")
        vec_mul = nt.nodes.new("ShaderNodeVectorMath")
        vec_mul.operation = "SCALE"
        vec_mul.inputs["Scale"].default_value = 0.5
        vec_add = nt.nodes.new("ShaderNodeVectorMath")
        vec_add.operation = "ADD"
        vec_add.inputs[1].default_value = (0.5, 0.5, 0.5)
        nt.links.new(geom.outputs["Normal"], vec_mul.inputs[0])
        nt.links.new(vec_mul.outputs["Vector"], vec_add.inputs[0])
        nt.links.new(vec_add.outputs["Vector"], emit.inputs["Color"])
        return mat

    tex_coord = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 24.0 if is_wood else 14.0
    noise.inputs["Detail"].default_value = 6.0
    nt.links.new(tex_coord.outputs["Object"], noise.inputs["Vector"])

    if mode == "roughness":
        mix_r = nt.nodes.new("ShaderNodeMix")
        mix_r.data_type = "FLOAT"
        mix_r.inputs["A"].default_value = rough_range[0]
        mix_r.inputs["B"].default_value = rough_range[1]
        nt.links.new(noise.outputs["Fac"], mix_r.inputs["Factor"])
        comb = nt.nodes.new("ShaderNodeCombineColor")
        nt.links.new(mix_r.outputs["Result"], comb.inputs["Red"])
        nt.links.new(mix_r.outputs["Result"], comb.inputs["Green"])
        nt.links.new(mix_r.outputs["Result"], comb.inputs["Blue"])
        nt.links.new(comb.outputs["Color"], emit.inputs["Color"])
        return mat

    vcol = nt.nodes.new("ShaderNodeVertexColor")
    vcol.layer_name = "Col"

    mix_base = nt.nodes.new("ShaderNodeMix")
    mix_base.data_type = "RGBA"
    mix_base.inputs["A"].default_value = (*base_col_a, 1.0)
    mix_base.inputs["B"].default_value = (*base_col_b, 1.0)
    nt.links.new(noise.outputs["Fac"], mix_base.inputs["Factor"])

    mul_vcol = nt.nodes.new("ShaderNodeMix")
    mul_vcol.data_type = "RGBA"
    mul_vcol.blend_type = "MULTIPLY"
    mul_vcol.inputs["Factor"].default_value = 1.0
    nt.links.new(mix_base.outputs["Result"], mul_vcol.inputs["A"])
    nt.links.new(vcol.outputs["Color"], mul_vcol.inputs["B"])

    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.samples = 8
    ao.inputs["Distance"].default_value = 0.035
    nt.links.new(mul_vcol.outputs["Result"], ao.inputs["Color"])

    mix_ao = nt.nodes.new("ShaderNodeMix")
    mix_ao.data_type = "RGBA"
    mix_ao.inputs["Factor"].default_value = 0.22
    nt.links.new(mul_vcol.outputs["Result"], mix_ao.inputs["A"])
    nt.links.new(ao.outputs["Color"], mix_ao.inputs["B"])
    nt.links.new(mix_ao.outputs["Result"], emit.inputs["Color"])
    return mat


def _add_tapered_twig(
    bm: bmesh.types.BMesh,
    vcol_layer,
    pts: list[Vector],
    radii: list[float],
    sides: int = 6,
    base_tint: tuple = (0.85, 0.78, 0.70),
    tip_tint: tuple = (1.05, 0.98, 0.85),
) -> None:
    rings = []
    n = len(pts)
    for i in range(n):
        p = pts[i]
        if i == 0:
            tangent = (pts[1] - pts[0]).normalized()
        elif i == n - 1:
            tangent = (pts[-1] - pts[-2]).normalized()
        else:
            tangent = (pts[i + 1] - pts[i - 1]).normalized()
        ref = Vector((0.0, 0.0, 1.0)) if abs(tangent.z) < 0.9 else Vector((1.0, 0.0, 0.0))
        right = tangent.cross(ref).normalized()
        up = right.cross(tangent).normalized()
        r = radii[i]
        ring = [
            bm.verts.new(p + (right * math.cos(s * 2.0 * math.pi / sides) + up * math.sin(s * 2.0 * math.pi / sides)) * r)
            for s in range(sides)
        ]
        rings.append(ring)

    for i in range(n - 1):
        t0 = i / max(1, n - 1)
        t1 = (i + 1) / max(1, n - 1)
        c0 = tuple(base_tint[k] * (1 - t0) + tip_tint[k] * t0 for k in range(3)) + (1.0,)
        c1 = tuple(base_tint[k] * (1 - t1) + tip_tint[k] * t1 for k in range(3)) + (1.0,)
        for s in range(sides):
            ns = (s + 1) % sides
            f = bm.faces.new((rings[i][s], rings[i][ns], rings[i + 1][ns], rings[i + 1][s]))
            f.smooth = True
            for loop, col in zip(f.loops, (c0, c0, c1, c1)):
                loop[vcol_layer] = col


def _add_conifer_needle(
    bm: bmesh.types.BMesh,
    vcol_layer,
    root: Vector,
    direction: Vector,
    length: float,
    width: float,
    ridge_z: float,
    base_col: tuple,
    tip_col: tuple,
) -> None:
    d = direction.normalized()
    side = d.cross(Vector((0.0, 0.0, 1.0)))
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    up = side.cross(d).normalized()

    p0 = root
    p1_l = root + d * (length * 0.42) - side * (width * 0.5)
    p1_c = root + d * (length * 0.42) + up * ridge_z
    p1_r = root + d * (length * 0.42) + side * (width * 0.5)
    p2_l = root + d * (length * 0.80) - side * (width * 0.34)
    p2_c = root + d * (length * 0.80) + up * (ridge_z * 0.7)
    p2_r = root + d * (length * 0.80) + side * (width * 0.34)
    p3 = root + d * length

    v0 = bm.verts.new(p0)
    v1l, v1c, v1r = bm.verts.new(p1_l), bm.verts.new(p1_c), bm.verts.new(p1_r)
    v2l, v2c, v2r = bm.verts.new(p2_l), bm.verts.new(p2_c), bm.verts.new(p2_r)
    v3 = bm.verts.new(p3)

    c0 = (*base_col, 1.0)
    c1 = tuple(base_col[k] * 0.55 + tip_col[k] * 0.45 for k in range(3)) + (1.0,)
    c2 = tuple(base_col[k] * 0.15 + tip_col[k] * 0.85 for k in range(3)) + (1.0,)
    c3 = (*tip_col, 1.0)

    for verts, cols in [
        ((v0, v1l, v1c), (c0, c1, c1)),
        ((v0, v1c, v1r), (c0, c1, c1)),
        ((v1l, v2l, v2c, v1c), (c1, c2, c2, c1)),
        ((v1c, v2c, v2r, v1r), (c1, c2, c2, c1)),
        ((v2l, v3, v2c), (c2, c3, c2)),
        ((v2c, v3, v2r), (c2, c3, c2)),
    ]:
        f = bm.faces.new(verts)
        f.smooth = False
        for loop, col in zip(f.loops, cols):
            loop[vcol_layer] = col


def _add_uv_curved_leaf_card(
    bm: bmesh.types.BMesh,
    uv_layer,
    vcol_layer,
    petiole_root: Vector,
    forward: Vector,
    length: float,
    width: float,
    uv_rect: tuple[float, float, float, float],
    curl_z: float,
    tilt_roll: float,
    tint: tuple[float, float, float],
) -> None:
    """Create a 3x2 curved 3D leaf card UV-mapped to a real scanned leaf tile."""
    fwd = forward.normalized()
    side = fwd.cross(Vector((0.0, 0.0, 1.0)))
    if side.length < 1e-4:
        side = Vector((1.0, 0.0, 0.0))
    side.normalize()
    up = side.cross(fwd).normalized()
    # Apply slight organic roll around forward vector
    q = Quaternion(fwd, tilt_roll)
    side = q @ side
    up = q @ up

    u0, v0, u1, v1 = uv_rect
    grid_v = []
    for iy in range(4):
        tv = iy / 3.0
        arch = math.sin(tv * math.pi) * length * 0.08 + (tv * tv) * curl_z
        row = []
        for ix in range(3):
            tu = ix / 2.0
            sx = (tu - 0.5) * width
            # Subtle V-fold along midrib
            vfold = abs(tu - 0.5) * width * 0.16
            pos = petiole_root + fwd * (tv * length) + side * sx + up * (arch + vfold)
            row.append((bm.verts.new(pos), (u0 + (u1 - u0) * tu, v0 + (v1 - v0) * tv)))
        grid_v.append(row)

    c_base = (tint[0] * 0.90, tint[1] * 0.90, tint[2] * 0.90, 1.0)
    c_tip = (*tint, 1.0)
    for iy in range(3):
        t0 = iy / 3.0
        t1 = (iy + 1) / 3.0
        col0 = tuple(c_base[k] * (1 - t0) + c_tip[k] * t0 for k in range(4))
        col1 = tuple(c_base[k] * (1 - t1) + c_tip[k] * t1 for k in range(4))
        for ix in range(2):
            v_a, uv_a = grid_v[iy][ix]
            v_b, uv_b = grid_v[iy][ix + 1]
            v_c, uv_c = grid_v[iy + 1][ix + 1]
            v_d, uv_d = grid_v[iy + 1][ix]
            f = bm.faces.new((v_a, v_b, v_c, v_d))
            f.smooth = True
            for loop, uv_p, col in zip(f.loops, (uv_a, uv_b, uv_c, uv_d), (col0, col0, col1, col1)):
                loop[uv_layer].uv = uv_p
                loop[vcol_layer] = col


def build_botanical_quadrant(species: str, quad_idx: int, center_xy: tuple[float, float]) -> tuple[bpy.types.Object, bpy.types.Object]:
    """Build dense 3D woody branchlets + 3D conifer needles or scanned broadleaf cards in a quadrant."""
    cx, cy = center_xy
    rng = random.Random(hash((species, quad_idx, 2026)) & 0xFFFFFFFF)

    bm_wood = bmesh.new()
    vc_wood = bm_wood.loops.layers.color.new("Col")
    bm_leaf = bmesh.new()
    uv_leaf = bm_leaf.loops.layers.uv.new("UVMap")
    vc_leaf = bm_leaf.loops.layers.color.new("Col")

    root = Vector((cx, cy - 0.44, 0.0))

    if species in ("fir_bough", "pine_bough"):
        is_pine = species == "pine_bough"
        main_len = rng.uniform(0.80, 0.86)
        lean = rng.uniform(-0.07, 0.07)
        pts = [
            root,
            root + Vector((lean * 0.3, main_len * 0.32, 0.005)),
            root + Vector((lean * 0.7, main_len * 0.66, 0.010)),
            root + Vector((lean, main_len, 0.004)),
        ]
        _add_tapered_twig(bm_wood, vc_wood, pts, [0.015, 0.011, 0.007, 0.003], sides=6)

        shoot_paths = [pts]
        n_shoots = 8 if not is_pine else 7
        for s_idx in range(n_shoots):
            t_along = 0.12 + 0.74 * (s_idx / max(1, n_shoots - 1)) + rng.uniform(-0.03, 0.03)
            t_along = max(0.08, min(0.86, t_along))
            side_sign = -1.0 if s_idx % 2 == 0 else 1.0
            base_pt = Vector((root.x + lean * t_along, root.y + main_len * t_along, 0.006))
            span = (0.42 - 0.25 * pow(t_along, 1.15)) * rng.uniform(0.90, 1.12)
            ang = math.radians(side_sign * rng.uniform(32.0, 56.0))
            dir_v = Vector((math.sin(ang), math.cos(ang), rng.uniform(-0.04, 0.06))).normalized()
            mid_pt = base_pt + dir_v * (span * 0.55) + Vector((0.0, 0.02, 0.007))
            tip_pt = base_pt + dir_v * span + Vector((-side_sign * 0.03, 0.03, 0.0))
            # Clamp inside quadrant
            tip_pt.x = max(cx - 0.43, min(cx + 0.43, tip_pt.x))
            tip_pt.y = max(cy - 0.42, min(cy + 0.43, tip_pt.y))
            s_pts = [base_pt, mid_pt, tip_pt]
            _add_tapered_twig(bm_wood, vc_wood, s_pts, [0.0075 * (1.0 - 0.3 * t_along), 0.0045, 0.002], sides=5)
            shoot_paths.append(s_pts)

            # Secondary sub-fork on lower/mid lateral shoots for rich layered bough density!
            if t_along < 0.65:
                sub_dir = Vector((math.sin(ang * 0.55), math.cos(ang * 0.55), 0.03)).normalized()
                sub_tip = mid_pt + sub_dir * (span * 0.45)
                sub_tip.x = max(cx - 0.43, min(cx + 0.43, sub_tip.x))
                sub_tip.y = max(cy - 0.42, min(cy + 0.43, sub_tip.y))
                _add_tapered_twig(bm_wood, vc_wood, [mid_pt, sub_tip], [0.004, 0.0018], sides=4)
                shoot_paths.append([mid_pt, sub_tip])

        for p_idx, path in enumerate(shoot_paths):
            seg_len = sum((path[k + 1] - path[k]).length for k in range(len(path) - 1))
            n_needles = int(seg_len * (220 if is_pine else 360))
            for k in range(n_needles):
                u = (k + rng.uniform(0.0, 0.9)) / max(1, n_needles)
                if p_idx == 0 and u < 0.07:
                    continue
                idx_f = u * (len(path) - 1)
                i0 = min(len(path) - 2, int(idx_f))
                pos = path[i0].lerp(path[i0 + 1], idx_f - i0)
                tang = (path[-1] - path[0]).normalized()
                side_s = -1.0 if (k % 2 == 0) else 1.0
                if is_pine:
                    spread = math.radians(rng.uniform(16.0, 64.0)) * side_s
                    n_dir = Vector((
                        tang.x * math.cos(spread) - tang.y * math.sin(spread),
                        tang.x * math.sin(spread) + tang.y * math.cos(spread),
                        rng.uniform(0.05, 0.38),
                    )).normalized()
                    n_len = rng.uniform(0.070, 0.118) * (0.85 + 0.22 * (1.0 - u * 0.35))
                    n_wid = rng.uniform(0.0055, 0.0085)
                    b_col = (0.45, 0.56, 0.35) if rng.random() > 0.12 else (0.58, 0.46, 0.24)
                    t_col = (0.82, 0.98, 0.58) if rng.random() > 0.12 else (0.76, 0.60, 0.30)
                else:
                    spread = math.radians(rng.uniform(24.0, 74.0)) * side_s
                    n_dir = Vector((
                        tang.x * math.cos(spread) - tang.y * math.sin(spread),
                        tang.x * math.sin(spread) + tang.y * math.cos(spread),
                        rng.uniform(0.04, 0.45),
                    )).normalized()
                    n_len = rng.uniform(0.044, 0.078) * (1.0 - 0.22 * u)
                    n_wid = rng.uniform(0.006, 0.009)
                    b_col = (0.38, 0.52, 0.32) if rng.random() > 0.07 else (0.52, 0.42, 0.22)
                    t_col = (0.76, 0.96, 0.56) if rng.random() > 0.07 else (0.70, 0.56, 0.26)
                _add_conifer_needle(
                    bm_leaf, vc_leaf,
                    pos + Vector((0.0, 0.0, rng.uniform(-0.002, 0.008))),
                    n_dir, n_len, n_wid, 0.0032, b_col, t_col,
                )

    else:
        # Broadleaf oak or birch: woody twig skeleton + REAL scanned LeafSet016/024 leaf tiles!
        is_birch = species == "birch_spray"
        main_len = rng.uniform(0.74, 0.82)
        lean = rng.uniform(-0.07, 0.07)
        pts = [
            root,
            root + Vector((lean * 0.35, main_len * 0.34, 0.005)),
            root + Vector((lean * 0.72, main_len * 0.68, 0.010)),
            root + Vector((lean, main_len, 0.005)),
        ]
        _add_tapered_twig(bm_wood, vc_wood, pts, [0.014, 0.0095, 0.0055, 0.0025], sides=6)

        # Leaf UVs inside ambientCG LeafSet016 (3x2 grid) and LeafSet024 (3x3 grid)
        if not is_birch:
            # LeafSet016: 3 cols x 2 rows (row 1 top = v 0.5..1.0, row 0 bottom = v 0.0..0.5 in Blender UV!)
            leaf_uvs = [
                (0.02, 0.52, 0.32, 0.98),
                (0.35, 0.52, 0.65, 0.98),
                (0.68, 0.52, 0.98, 0.98),
                (0.02, 0.02, 0.32, 0.48),
                (0.35, 0.02, 0.65, 0.48),
                (0.68, 0.02, 0.98, 0.48),
            ]
        else:
            # LeafSet024: 3x3 grid
            leaf_uvs = []
            for r in range(3):
                for c in range(3):
                    leaf_uvs.append((c / 3.0 + 0.02, r / 3.0 + 0.02, (c + 1) / 3.0 - 0.02, (r + 1) / 3.0 - 0.02))

        twig_paths = [(pts[1], pts[2], pts[3], (pts[3] - pts[1]).normalized())]
        n_twigs = 7 if is_birch else 6
        for t_idx in range(n_twigs):
            t_along = 0.14 + 0.70 * (t_idx / max(1, n_twigs - 1)) + rng.uniform(-0.04, 0.04)
            t_along = max(0.10, min(0.84, t_along))
            side_s = -1.0 if t_idx % 2 == 0 else 1.0
            b_pt = Vector((root.x + lean * t_along, root.y + main_len * t_along, 0.006))
            span = (0.38 - 0.14 * t_along) * rng.uniform(0.88, 1.14)
            ang = math.radians(side_s * rng.uniform(28.0, 58.0))
            d_v = Vector((math.sin(ang), math.cos(ang), rng.uniform(-0.02, 0.04))).normalized()
            m_pt = b_pt + d_v * (span * 0.52) + Vector((0.0, 0.0, 0.006))
            e_pt = b_pt + d_v * span
            e_pt.x = max(cx - 0.41, min(cx + 0.41, e_pt.x))
            e_pt.y = max(cy - 0.39, min(cy + 0.41, e_pt.y))
            _add_tapered_twig(bm_wood, vc_wood, [b_pt, m_pt, e_pt], [0.0065, 0.004, 0.002], sides=5)
            twig_paths.append((b_pt, m_pt, e_pt, d_v))

        for bp, mp, ep, dv in twig_paths:
            leaves_here = 9 if is_birch else 8
            for li in range(leaves_here):
                u = 0.18 + 0.82 * (li / max(1, leaves_here - 1)) + rng.uniform(-0.04, 0.04)
                u = max(0.12, min(1.0, u))
                anchor = bp.lerp(mp, u * 2.0) if u < 0.5 else mp.lerp(ep, (u - 0.5) * 2.0)
                side_s = -1.0 if (li % 2 == 0) else 1.0
                l_ang = rng.uniform(-0.22, 0.22) if li == leaves_here - 1 else side_s * math.radians(rng.uniform(24.0, 74.0))
                l_dir = Vector((
                    dv.x * math.cos(l_ang) - dv.y * math.sin(l_ang),
                    dv.x * math.sin(l_ang) + dv.y * math.cos(l_ang),
                    rng.uniform(-0.14, 0.22),
                )).normalized()
                pet_len = rng.uniform(0.018, 0.036)
                pet_end = anchor + l_dir * pet_len
                _add_tapered_twig(bm_wood, vc_wood, [anchor, pet_end], [0.0025, 0.0016], sides=4)

                avail = min(0.45 - abs(pet_end.x - cx), 0.45 - abs(pet_end.y - cy))
                if avail < 0.055:
                    continue
                l_len = min(avail * 0.94, rng.uniform(0.095, 0.148) if is_birch else rng.uniform(0.125, 0.185))
                l_wid = l_len * (rng.uniform(0.72, 0.88) if is_birch else rng.uniform(0.62, 0.78))
                t_var = rng.uniform(0.82, 1.14)
                tint = (0.94 * t_var, 1.0 * t_var, 0.88 * t_var)
                _add_uv_curved_leaf_card(
                    bm_leaf, uv_leaf, vc_leaf,
                    pet_end + Vector((0.0, 0.0, rng.uniform(0.002, 0.018))),
                    l_dir, l_len, l_wid,
                    rng.choice(leaf_uvs),
                    rng.uniform(-0.015, 0.020),
                    rng.uniform(-0.28, 0.28),
                    tint,
                )

    mesh_wood = bpy.data.meshes.new(f"{species}_q{quad_idx}_wood")
    bm_wood.to_mesh(mesh_wood)
    bm_wood.free()
    obj_wood = bpy.data.objects.new(mesh_wood.name, mesh_wood)
    bpy.context.scene.collection.objects.link(obj_wood)

    mesh_leaf = bpy.data.meshes.new(f"{species}_q{quad_idx}_leaf")
    bm_leaf.to_mesh(mesh_leaf)
    bm_leaf.free()
    obj_leaf = bpy.data.objects.new(mesh_leaf.name, mesh_leaf)
    bpy.context.scene.collection.objects.link(obj_leaf)
    return obj_wood, obj_leaf


def render_botanical_atlas(species: str, out_prefix: Path, res: int = ATLAS_RES) -> None:
    """Render 2x2 botanical atlas (albedo RGBA + Jump-Flood RGB dilation, tangent normal, roughness)."""
    reset_scene()
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 16
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 0
    scene.cycles.transparent_max_bounces = 16

    cam_data = bpy.data.cameras.new("AtlasCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.0
    cam_data.clip_start = 0.01
    cam_data.clip_end = 20.0
    cam_obj = bpy.data.objects.new("AtlasCam", cam_data)
    scene.collection.objects.link(cam_obj)
    cam_obj.location = (0.0, 0.0, 4.0)
    scene.camera = cam_obj
    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True

    quad_centers = [(-0.5, 0.5), (0.5, 0.5), (-0.5, -0.5), (0.5, -0.5)]
    wood_objs, leaf_objs = [], []
    for qi, cxy in enumerate(quad_centers):
        ow, ol = build_botanical_quadrant(species, qi, cxy)
        wood_objs.append(ow)
        leaf_objs.append(ol)

    # Check if ambientCG scanned LeafSet016/LeafSet024 are available for oak_spray & birch_spray
    leafset_cfg = None
    if species == "oak_spray":
        ls = SOURCE_ROOT / "ambientCG" / "LeafSet016" / "2k"
        if (ls / "LeafSet016_2K-JPG_Color.jpg").exists():
            leafset_cfg = (
                ls / "LeafSet016_2K-JPG_Color.jpg",
                ls / "LeafSet016_2K-JPG_Opacity.jpg",
                ls / "LeafSet016_2K-JPG_NormalGL.jpg",
                ls / "LeafSet016_2K-JPG_Roughness.jpg",
                (0.48, 0.62, 0.34),  # Rich temperate forest oak green shift
            )
    elif species == "birch_spray":
        ls = SOURCE_ROOT / "ambientCG" / "LeafSet024" / "2k"
        if (ls / "LeafSet024_2K-JPG_Color.jpg").exists():
            leafset_cfg = (
                ls / "LeafSet024_2K-JPG_Color.jpg",
                ls / "LeafSet024_2K-JPG_Opacity.jpg",
                ls / "LeafSet024_2K-JPG_NormalGL.jpg",
                ls / "LeafSet024_2K-JPG_Roughness.jpg",
                (0.72, 0.88, 0.52),  # Airy sunlit silver-birch leaf green
            )

    palettes = {
        "fir_bough": {
            "wood": ((0.080, 0.052, 0.034), (0.110, 0.072, 0.046), (0.065, 0.042, 0.026), (0.84, 0.93)),
            "leaf": ((0.036, 0.082, 0.022), (0.058, 0.122, 0.032), (0.048, 0.102, 0.026), (0.48, 0.68)),
        },
        "pine_bough": {
            "wood": ((0.115, 0.068, 0.038), (0.155, 0.090, 0.050), (0.088, 0.050, 0.028), (0.84, 0.93)),
            "leaf": ((0.048, 0.102, 0.026), (0.076, 0.138, 0.038), (0.062, 0.120, 0.032), (0.46, 0.66)),
        },
        "oak_spray": {
            "wood": ((0.088, 0.065, 0.044), (0.120, 0.088, 0.060), (0.070, 0.050, 0.034), (0.85, 0.94)),
            "leaf": ((0.052, 0.118, 0.026), (0.088, 0.158, 0.038), (0.074, 0.140, 0.032), (0.44, 0.64)),
        },
        "birch_spray": {
            "wood": ((0.095, 0.066, 0.046), (0.128, 0.088, 0.062), (0.072, 0.048, 0.032), (0.84, 0.92)),
            "leaf": ((0.078, 0.155, 0.035), (0.122, 0.205, 0.048), (0.100, 0.180, 0.042), (0.42, 0.62)),
        },
    }
    pal = palettes[species]
    tmp_dir = out_prefix.parent / "_tmp_bake"
    tmp_dir.mkdir(parents=True, exist_ok=True)

    passes = {}
    for mode in ("albedo", "normal", "roughness"):
        mat_w = _make_unlit_procedural_material(f"{species}_w_{mode}", mode, *pal["wood"], is_wood=True)
        if leafset_cfg is not None:
            mat_l = _make_leafset_material(f"{species}_l_{mode}", mode, *leafset_cfg)
        else:
            mat_l = _make_unlit_procedural_material(f"{species}_l_{mode}", mode, *pal["leaf"], is_wood=False)
        for o in wood_objs:
            o.data.materials.clear()
            o.data.materials.append(mat_w)
        for o in leaf_objs:
            o.data.materials.clear()
            o.data.materials.append(mat_l)

        scene.display_settings.display_device = "sRGB"
        scene.view_settings.view_transform = "Raw"
        scene.render.image_settings.file_format = "OPEN_EXR"
        scene.render.image_settings.color_mode = "RGBA"
        scene.render.image_settings.color_depth = "32"
        exr_path = tmp_dir / f"{species}_{mode}.exr"
        scene.render.filepath = str(exr_path)
        bpy.ops.render.render(write_still=True)
        passes[mode] = load_blender_image_rgba(exr_path)
        exr_path.unlink(missing_ok=True)

    try:
        tmp_dir.rmdir()
    except OSError:
        pass

    alpha = np.clip(passes["albedo"][:, :, 3], 0.0, 1.0)
    solid_for_dilate = alpha > 0.68
    cy, cx = jump_flood_indices(solid_for_dilate)
    safe_a = np.maximum(alpha[..., None], 1e-4)

    # 1. Albedo
    alb_lin = passes["albedo"][:, :, :3]
    alb_unpre = np.where(alpha[..., None] > 0.04, np.clip(alb_lin / safe_a, 0.0, 1.0), 0.0)
    alb_clean = np.where(solid_for_dilate[..., None], alb_unpre, alb_unpre[cy, cx])
    alb_srgb = linear_to_srgb(alb_clean)
    alpha_u8 = np.clip(np.rint(alpha * 255.0), 0, 255).astype(np.uint8)
    alb_u8 = np.concatenate(
        [np.clip(np.rint(alb_srgb * 255.0), 0, 255).astype(np.uint8), alpha_u8[..., None]],
        axis=-1,
    )
    write_png(Path(f"{out_prefix}_albedo.png"), alb_u8)
    write_png(Path(f"{out_prefix}_albedo_512.png"), downsample_u8(alb_u8, 512))

    # 2. Normal
    nrm_lin = passes["normal"][:, :, :3]
    nrm_unpre = np.where(alpha[..., None] > 0.04, np.clip(nrm_lin / safe_a, 0.0, 1.0), 0.5)
    nrm_clean = np.where(solid_for_dilate[..., None], nrm_unpre, nrm_unpre[cy, cx])
    nrm_u8 = np.clip(np.rint(nrm_clean * 255.0), 0, 255).astype(np.uint8)
    write_png(Path(f"{out_prefix}_normal.png"), nrm_u8)
    write_png(Path(f"{out_prefix}_normal_512.png"), downsample_u8(nrm_u8, 512))

    # 3. Roughness
    rgh_lin = passes["roughness"][:, :, :3]
    rgh_unpre = np.where(alpha[..., None] > 0.04, np.clip(rgh_lin / safe_a, 0.0, 1.0), 0.6)
    rgh_clean = np.where(solid_for_dilate[..., None], rgh_unpre, rgh_unpre[cy, cx])
    rgh_u8 = np.clip(np.rint(rgh_clean * 255.0), 0, 255).astype(np.uint8)
    write_png(Path(f"{out_prefix}_roughness.png"), rgh_u8)
    write_png(Path(f"{out_prefix}_roughness_512.png"), downsample_u8(rgh_u8, 512))
    print(f"[atlas] Rendered {species} (leafset={'scanned' if leafset_cfg else '3D'}) -> {out_prefix}")


def generate_bark_textures() -> None:
    """Create 1024x1024 + 512x512 seamless PBR bark maps using Poly Haven & ambientCG CC0 sources."""
    TEX_DIR.mkdir(parents=True, exist_ok=True)
    reset_scene()

    # 1. Pine bark (Poly Haven pine_bark in assets/forza_env/textures/bark/)
    if (FORZA_BARK_DIR / "albedo.jpg").exists():
        pine_alb = resize_u8_bilinear(
            np.clip(np.rint(load_blender_image_rgba(FORZA_BARK_DIR / "albedo.jpg")[:, :, :3] * 255.0), 0, 255).astype(np.uint8),
            BARK_RES, BARK_RES,
        )
        pine_nrm = resize_u8_bilinear(
            np.clip(np.rint(load_blender_image_rgba(FORZA_BARK_DIR / "normal.png")[:, :, :3] * 255.0), 0, 255).astype(np.uint8),
            BARK_RES, BARK_RES,
        )
        pine_rgh = resize_u8_bilinear(
            np.clip(np.rint(load_blender_image_rgba(FORZA_BARK_DIR / "roughness.png")[:, :, :3] * 255.0), 0, 255).astype(np.uint8),
            BARK_RES, BARK_RES,
        )
        write_png(TEX_DIR / "pine_bark_albedo.png", pine_alb)
        write_png(TEX_DIR / "pine_bark_normal.png", pine_nrm)
        write_png(TEX_DIR / "pine_bark_roughness.png", pine_rgh)
        write_png(TEX_DIR / "pine_bark_albedo_512.png", downsample_u8(pine_alb, 512))
        write_png(TEX_DIR / "pine_bark_normal_512.png", downsample_u8(pine_nrm, 512))
        write_png(TEX_DIR / "pine_bark_roughness_512.png", downsample_u8(pine_rgh, 512))

    # 2. Oak bark (ambientCG Bark012 if available, else derived from pine_bark)
    oak_src_dir = SOURCE_ROOT / "ambientCG" / "Bark012" / "2k"
    if (oak_src_dir / "Bark012_2K-JPG_Color.jpg").exists():
        oak_alb = resize_u8_bilinear(
            np.clip(np.rint(load_blender_image_rgba(oak_src_dir / "Bark012_2K-JPG_Color.jpg")[:, :, :3] * 255.0), 0, 255).astype(np.uint8),
            BARK_RES, BARK_RES,
        )
        oak_nrm = resize_u8_bilinear(
            np.clip(np.rint(load_blender_image_rgba(oak_src_dir / "Bark012_2K-JPG_NormalGL.jpg")[:, :, :3] * 255.0), 0, 255).astype(np.uint8),
            BARK_RES, BARK_RES,
        )
        oak_rgh = resize_u8_bilinear(
            np.clip(np.rint(load_blender_image_rgba(oak_src_dir / "Bark012_2K-JPG_Roughness.jpg")[:, :, :3] * 255.0), 0, 255).astype(np.uint8),
            BARK_RES, BARK_RES,
        )
    else:
        half_alb = resize_u8_bilinear(pine_alb, BARK_RES, BARK_RES // 2)
        oak_2x = np.concatenate([half_alb, half_alb], axis=1).astype(np.float32) / 255.0
        lum = oak_2x @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
        oak_alb = np.clip(np.rint(np.stack([lum * 0.92 + 0.03, lum * 0.88 + 0.035, lum * 0.78 + 0.025], axis=-1) * 255.0), 0, 255).astype(np.uint8)
        half_nrm = resize_u8_bilinear(pine_nrm, BARK_RES, BARK_RES // 2)
        oak_nrm = np.concatenate([half_nrm, half_nrm], axis=1)
        half_rgh = resize_u8_bilinear(pine_rgh, BARK_RES, BARK_RES // 2)
        oak_rgh = np.concatenate([half_rgh, half_rgh], axis=1)

    write_png(TEX_DIR / "oak_bark_albedo.png", oak_alb)
    write_png(TEX_DIR / "oak_bark_normal.png", oak_nrm)
    write_png(TEX_DIR / "oak_bark_roughness.png", oak_rgh)
    write_png(TEX_DIR / "oak_bark_albedo_512.png", downsample_u8(oak_alb, 512))
    write_png(TEX_DIR / "oak_bark_normal_512.png", downsample_u8(oak_nrm, 512))
    write_png(TEX_DIR / "oak_bark_roughness_512.png", downsample_u8(oak_rgh, 512))

    # 3. Silver Birch bark: ambientCG Bark004 micro-grain + chalky silver-white peeling bark & lenticels
    res = BARK_RES
    rng = np.random.default_rng(4021)

    def seamless_noise(freq_x: float, freq_y: float, seed: int) -> np.ndarray:
        r = np.random.default_rng(seed)
        grid = r.random((max(4, int(freq_y)), max(4, int(freq_x))), dtype=np.float32)
        gy = np.arange(res)[:, None] * grid.shape[0] / res
        gx = np.arange(res)[None, :] * grid.shape[1] / res
        y0 = np.floor(gy).astype(int) % grid.shape[0]
        x0 = np.floor(gx).astype(int) % grid.shape[1]
        y1 = (y0 + 1) % grid.shape[0]
        x1 = (x0 + 1) % grid.shape[1]
        fy = gy - np.floor(gy)
        fx = gx - np.floor(gx)
        fy = fy * fy * (3.0 - 2.0 * fy)
        fx = fx * fx * (3.0 - 2.0 * fx)
        return (
            grid[y0, x0] * (1 - fy) * (1 - fx)
            + grid[y0, x1] * (1 - fy) * fx
            + grid[y1, x0] * fy * (1 - fx)
            + grid[y1, x1] * fy * fx
        )

    band_low = seamless_noise(4, 24, 101)
    band_mid = seamless_noise(10, 64, 102)
    fine_grain = seamless_noise(32, 220, 103)
    peel_mask = seamless_noise(6, 36, 104)

    height = 0.68 + 0.14 * band_low + 0.10 * band_mid + 0.08 * fine_grain
    col = np.zeros((res, res, 3), dtype=np.float32)
    col[:, :, 0] = 0.78 + 0.14 * band_low + 0.06 * fine_grain
    col[:, :, 1] = 0.76 + 0.13 * band_low + 0.05 * fine_grain
    col[:, :, 2] = 0.71 + 0.12 * band_low + 0.04 * fine_grain

    tan_patch = np.clip((peel_mask - 0.62) * 3.5, 0.0, 1.0)
    col[:, :, 0] = col[:, :, 0] * (1 - tan_patch * 0.35) + 0.66 * (tan_patch * 0.35)
    col[:, :, 1] = col[:, :, 1] * (1 - tan_patch * 0.42) + 0.56 * (tan_patch * 0.42)
    col[:, :, 2] = col[:, :, 2] * (1 - tan_patch * 0.52) + 0.44 * (tan_patch * 0.52)

    # Blend subtle photographic bark grain from Bark004 if present
    b4_dir = SOURCE_ROOT / "ambientCG" / "Bark004" / "2k"
    b4_nrm = None
    if (b4_dir / "Bark004_2K-JPG_Color.jpg").exists():
        b4_col = resize_u8_bilinear(
            np.clip(np.rint(load_blender_image_rgba(b4_dir / "Bark004_2K-JPG_Color.jpg")[:, :, :3] * 255.0), 0, 255).astype(np.uint8),
            res, res,
        ).astype(np.float32) / 255.0
        b4_lum = b4_col @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
        col *= np.clip(0.84 + (b4_lum - 0.5) * 0.45, 0.68, 1.12)[..., None]
        b4_nrm = resize_u8_bilinear(
            np.clip(np.rint(load_blender_image_rgba(b4_dir / "Bark004_2K-JPG_NormalGL.jpg")[:, :, :3] * 255.0), 0, 255).astype(np.uint8),
            res, res,
        ).astype(np.float32) / 255.0

    lenticels = np.zeros((res, res), dtype=np.float32)
    for _ in range(420):
        cy_i = int(rng.integers(0, res))
        cx_i = int(rng.integers(0, res))
        half_w = int(rng.integers(14, 72))
        half_h = int(rng.integers(2, 6))
        yy = (np.arange(cy_i - half_h, cy_i + half_h + 1) % res)[:, None]
        xx = (np.arange(cx_i - half_w, cx_i + half_w + 1) % res)[None, :]
        dy = (np.arange(-half_h, half_h + 1) / max(1.0, half_h))[:, None]
        dx = (np.arange(-half_w, half_w + 1) / max(1.0, half_w))[None, :]
        shape = np.clip(1.0 - (dx * dx + dy * dy * 1.1), 0.0, 1.0) ** 0.7
        lenticels[yy, xx] = np.maximum(lenticels[yy, xx], shape * float(rng.uniform(0.55, 0.95)))

    for _ in range(18):
        cy_i = int(rng.integers(0, res))
        cx_i = int(rng.integers(0, res))
        hw = int(rng.integers(24, 52))
        hh = int(rng.integers(12, 26))
        yy = (np.arange(cy_i - hh, cy_i + hh + 1) % res)[:, None]
        xx = (np.arange(cx_i - hw, cx_i + hw + 1) % res)[None, :]
        dy = np.abs(np.arange(-hh, hh + 1) / float(hh))[:, None]
        dx = np.abs(np.arange(-hw, hw + 1) / float(hw))[None, :]
        diamond = np.clip(1.0 - (dx + dy * 1.15), 0.0, 1.0) ** 0.8
        lenticels[yy, xx] = np.maximum(lenticels[yy, xx], diamond * 0.95)

    dark_col = np.array([0.14, 0.13, 0.11], dtype=np.float32)
    col = col * (1.0 - lenticels[..., None] * 0.88) + dark_col * (lenticels[..., None] * 0.88)
    height = height - lenticels * 0.35

    dh_dx = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
    dh_dy = np.roll(height, 1, axis=0) - np.roll(height, -1, axis=0)
    nx = -dh_dx * 4.2
    ny = -dh_dy * 4.2
    nz = np.ones_like(nx)
    if b4_nrm is not None:
        nx += (b4_nrm[:, :, 0] - 0.5) * 0.8
        ny += (b4_nrm[:, :, 1] - 0.5) * 0.8
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([nx * inv_len * 0.5 + 0.5, ny * inv_len * 0.5 + 0.5, nz * inv_len * 0.5 + 0.5], axis=-1)
    rgh = np.clip(0.72 + 0.22 * lenticels + 0.08 * (1.0 - fine_grain), 0.55, 0.96)

    birch_alb = np.clip(np.rint(col * 255.0), 0, 255).astype(np.uint8)
    birch_nrm = np.clip(np.rint(nrm * 255.0), 0, 255).astype(np.uint8)
    birch_rgh_1 = np.clip(np.rint(rgh * 255.0), 0, 255).astype(np.uint8)
    birch_rgh = np.stack([birch_rgh_1, birch_rgh_1, birch_rgh_1], axis=-1)

    write_png(TEX_DIR / "birch_bark_albedo.png", birch_alb)
    write_png(TEX_DIR / "birch_bark_normal.png", birch_nrm)
    write_png(TEX_DIR / "birch_bark_roughness.png", birch_rgh)
    write_png(TEX_DIR / "birch_bark_albedo_512.png", downsample_u8(birch_alb, 512))
    write_png(TEX_DIR / "birch_bark_normal_512.png", downsample_u8(birch_nrm, 512))
    write_png(TEX_DIR / "birch_bark_roughness_512.png", downsample_u8(birch_rgh, 512))
    print(f"[bark] Generated pine_bark, oak_bark (Bark012), birch_bark (Bark004+lenticels) in {TEX_DIR}")


# ---------------------------------------------------------------------------
# Stage 2: 5 Realistic Temperate Tree Species x 3 LODs (Z-up in Blender -> Y-up GLB)
# ---------------------------------------------------------------------------

def _make_pbr_tree_materials(
    bark_prefix: str,
    foliage_prefix: str,
    use_512: bool,
) -> tuple[bpy.types.Material, bpy.types.Material]:
    """Create Surface 0 (bark) & Surface 1 (foliage) Principled BSDF materials for glTF 2.0 export."""
    suf = "_512" if use_512 else ""

    # Surface 0: Bark (opaque PBR)
    mat_bark = bpy.data.materials.new(f"bark_{bark_prefix}")
    mat_bark.use_nodes = True
    nt = mat_bark.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Specular IOR Level"].default_value = 0.25
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_alb = nt.nodes.new("ShaderNodeTexImage")
    img_alb = bpy.data.images.load(str(TEX_DIR / f"{bark_prefix}_albedo{suf}.png"), check_existing=True)
    img_alb.colorspace_settings.name = "sRGB"
    tex_alb.image = img_alb
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_rgh = nt.nodes.new("ShaderNodeTexImage")
    img_rgh = bpy.data.images.load(str(TEX_DIR / f"{bark_prefix}_roughness{suf}.png"), check_existing=True)
    img_rgh.colorspace_settings.name = "Non-Color"
    tex_rgh.image = img_rgh
    nt.links.new(tex_rgh.outputs["Color"], bsdf.inputs["Roughness"])

    tex_nrm = nt.nodes.new("ShaderNodeTexImage")
    img_nrm = bpy.data.images.load(str(TEX_DIR / f"{bark_prefix}_normal{suf}.png"), check_existing=True)
    img_nrm.colorspace_settings.name = "Non-Color"
    tex_nrm.image = img_nrm
    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.inputs["Strength"].default_value = 1.0
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    # Surface 1: Foliage (alpha mask + normal + roughness)
    mat_fol = bpy.data.materials.new(f"foliage_{foliage_prefix}")
    mat_fol.use_nodes = True
    mat_fol.blend_method = "CLIP"
    mat_fol.alpha_threshold = 0.40
    mat_fol.use_backface_culling = False
    nt2 = mat_fol.node_tree
    nt2.nodes.clear()
    out2 = nt2.nodes.new("ShaderNodeOutputMaterial")
    bsdf2 = nt2.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf2.inputs["Specular IOR Level"].default_value = 0.30
    nt2.links.new(bsdf2.outputs["BSDF"], out2.inputs["Surface"])

    tex_falb = nt2.nodes.new("ShaderNodeTexImage")
    img_falb = bpy.data.images.load(str(TEX_DIR / f"{foliage_prefix}_albedo{suf}.png"), check_existing=True)
    img_falb.colorspace_settings.name = "sRGB"
    tex_falb.image = img_falb
    nt2.links.new(tex_falb.outputs["Color"], bsdf2.inputs["Base Color"])
    nt2.links.new(tex_falb.outputs["Alpha"], bsdf2.inputs["Alpha"])

    tex_frgh = nt2.nodes.new("ShaderNodeTexImage")
    img_frgh = bpy.data.images.load(str(TEX_DIR / f"{foliage_prefix}_roughness{suf}.png"), check_existing=True)
    img_frgh.colorspace_settings.name = "Non-Color"
    tex_frgh.image = img_frgh
    nt2.links.new(tex_frgh.outputs["Color"], bsdf2.inputs["Roughness"])

    tex_fnrm = nt2.nodes.new("ShaderNodeTexImage")
    img_fnrm = bpy.data.images.load(str(TEX_DIR / f"{foliage_prefix}_normal{suf}.png"), check_existing=True)
    img_fnrm.colorspace_settings.name = "Non-Color"
    tex_fnrm.image = img_fnrm
    nrm_node2 = nt2.nodes.new("ShaderNodeNormalMap")
    nrm_node2.inputs["Strength"].default_value = 0.85
    nt2.links.new(tex_fnrm.outputs["Color"], nrm_node2.inputs["Color"])
    nt2.links.new(nrm_node2.outputs["Normal"], bsdf2.inputs["Normal"])

    return mat_bark, mat_fol


class TreeBuilder:
    """Builds Blender Z-up tree geometry with Surface 0 = bark, Surface 1 = foliage."""

    def __init__(self, tree_height: float, crown_center_z: float, crown_radius: float, seed: int):
        self.tree_height = tree_height
        self.crown_center = Vector((0.0, 0.0, crown_center_z))
        self.crown_radius = crown_radius
        self.rng = random.Random(seed)
        self.bm = bmesh.new()
        self.uv_layer = self.bm.loops.layers.uv.new("UVMap")
        self.vcol_layer = self.bm.loops.layers.color.new("Color")
        # Track foliage faces + outward/upward blended normal target per vertex
        self.foliage_faces: list[bmesh.types.BMFace] = []

    def add_wood_tube(
        self,
        points: list[Vector],
        radii: list[float],
        sides: int,
        uv_scale: float = 0.65,
        buttress_lobes: int = 0,
        buttress_strength: float = 0.0,
        bark_tint_fn=None,
        flex_fn=None,
    ) -> None:
        n = len(points)
        rings = []
        cum_len = [0.0]
        for i in range(1, n):
            cum_len.append(cum_len[-1] + (points[i] - points[i - 1]).length)

        for i in range(n):
            p = points[i]
            if i == 0:
                tang = (points[1] - points[0]).normalized()
            elif i == n - 1:
                tang = (points[-1] - points[-2]).normalized()
            else:
                tang = (points[i + 1] - points[i - 1]).normalized()
            ref = Vector((1.0, 0.0, 0.0)) if abs(tang.z) > 0.9 else Vector((0.0, 0.0, 1.0))
            right = tang.cross(ref).normalized()
            fwd = right.cross(tang).normalized()
            r_base = radii[i]
            flare_t = max(0.0, 1.0 - max(0.0, p.z + 0.15) / 0.85)

            ring = []
            # Duplicate seam vertex at s == sides so U wraps cleanly 0..circumference without seam glitch
            for s in range(sides + 1):
                ang = (s / sides) * 2.0 * math.pi
                lobe = 1.0
                if buttress_lobes > 0 and flare_t > 0.0:
                    lobe += buttress_strength * (flare_t ** 1.4) * (0.55 + 0.45 * math.cos(ang * buttress_lobes + 0.4))
                rad = r_base * lobe
                v_pos = p + (right * math.cos(ang) + fwd * math.sin(ang)) * rad
                ring.append(self.bm.verts.new(v_pos))
            rings.append(ring)

        circum = max(0.35, 2.0 * math.pi * radii[0])
        u_tiles = max(1.0, round(circum * uv_scale))
        for i in range(n - 1):
            v0 = cum_len[i] * uv_scale
            v1 = cum_len[i + 1] * uv_scale
            for s in range(sides):
                u0 = (s / sides) * u_tiles
                u1 = ((s + 1) / sides) * u_tiles
                va, vb = rings[i][s], rings[i][s + 1]
                vc, vd = rings[i + 1][s + 1], rings[i + 1][s]
                f = self.bm.faces.new((va, vb, vc, vd))
                f.material_index = 0
                f.smooth = True
                for loop, uv_p in zip(f.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
                    loop[self.uv_layer].uv = uv_p
                    pos = loop.vert.co
                    rgb = bark_tint_fn(pos) if bark_tint_fn else (0.85, 0.85, 0.85)
                    # Root AO darkening below 0.65m
                    root_ao = min(1.0, 0.46 + 0.54 * max(0.0, pos.z + 0.15) / 0.80)
                    flex = flex_fn(pos) if flex_fn else self.default_bark_flex(pos)
                    loop[self.vcol_layer] = (rgb[0] * root_ao, rgb[1] * root_ao, rgb[2] * root_ao, flex)

    def default_bark_flex(self, pos: Vector) -> float:
        h_frac = max(0.0, pos.z / max(1.0, self.tree_height))
        radial = math.hypot(pos.x, pos.y) / max(1.0, self.crown_radius)
        return min(0.26, (h_frac ** 1.5) * 0.22 + (radial ** 1.4) * 0.08)

    def add_foliage_card(
        self,
        root: Vector,
        direction: Vector,
        up_hint: Vector,
        length: float,
        width: float,
        quad_idx: int,
        droop: float = 0.08,
        cup: float = 0.16,
        roll_rad: float = 0.0,
        sub_segs_len: int = 3,
        sub_segs_wid: int = 2,
        tint: tuple[float, float, float] = (1.0, 1.0, 1.0),
        base_flex: float = 0.22,
        tip_flex: float = 1.0,
    ) -> None:
        """Add a 3D curved/V-folded foliage card rooted on branch at `root`."""
        fwd = direction.normalized()
        side = fwd.cross(up_hint)
        if side.length < 1e-4:
            side = fwd.cross(Vector((1.0, 0.0, 0.0)))
        side.normalize()
        up = side.cross(fwd).normalized()

        q = Quaternion(fwd, roll_rad)
        side = q @ side
        up = q @ up

        # 2x2 atlas quadrant UV coords (matching render_botanical_atlas)
        # Q0: top-left, Q1: top-right, Q2: bottom-left, Q3: bottom-right
        q_rects = [
            (0.015, 0.515, 0.485, 0.985),
            (0.515, 0.515, 0.985, 0.985),
            (0.015, 0.015, 0.485, 0.485),
            (0.515, 0.015, 0.985, 0.485),
        ]
        u0, v0, u1, v1 = q_rects[quad_idx % 4]

        grid = []
        for iy in range(sub_segs_len + 1):
            tv = iy / sub_segs_len
            arch_z = math.sin(tv * math.pi) * length * 0.09 - (tv * tv) * length * droop
            w_taper = 1.0 - 0.18 * (tv * tv)
            row = []
            for ix in range(sub_segs_wid + 1):
                tu = ix / sub_segs_wid
                sx = (tu - 0.5) * width * w_taper
                vfold = abs(tu - 0.5) * width * cup
                pos = root + fwd * (tv * length) + side * sx + up * (arch_z + vfold)
                row.append((self.bm.verts.new(pos), (u0 + (u1 - u0) * tu, v0 + (v1 - v0) * tv), tv))
            grid.append(row)

        for iy in range(sub_segs_len):
            for ix in range(sub_segs_wid):
                va, uva, tva = grid[iy][ix]
                vb, uvb, tvb = grid[iy][ix + 1]
                vc, uvc, tvc = grid[iy + 1][ix + 1]
                vd, uvd, tvd = grid[iy + 1][ix]
                f = self.bm.faces.new((va, vb, vc, vd))
                f.material_index = 1
                f.smooth = True
                self.foliage_faces.append(f)
                for loop, uv_p, tv in zip(f.loops, (uva, uvb, uvc, uvd), (tva, tvb, tvc, tvd)):
                    loop[self.uv_layer].uv = uv_p
                    pos = loop.vert.co
                    # Inner-crown AO: inner parts near trunk are ~0.52, outer tips 1.0
                    d_center = (pos - self.crown_center)
                    r_norm = min(1.0, Vector((d_center.x, d_center.y, d_center.z * 0.65)).length / max(0.5, self.crown_radius))
                    ao = 0.50 + 0.50 * (r_norm ** 0.75)
                    flex = min(1.0, base_flex + (tip_flex - base_flex) * (tv ** 1.1))
                    loop[self.vcol_layer] = (tint[0] * ao, tint[1] * ao, tint[2] * ao, flex)

    def add_crossed_spray_cluster(
        self,
        root: Vector,
        direction: Vector,
        length: float,
        width: float,
        quad_idx: int,
        is_lod2: bool = False,
        droop: float = 0.07,
        tint: tuple[float, float, float] = (1.0, 1.0, 1.0),
        base_flex: float = 0.25,
    ) -> None:
        """Place a 2-card crossed/cupped 3D spray cluster so no angle looks like a flat plane."""
        segs_l = 1 if is_lod2 else 2
        segs_w = 1 if is_lod2 else 2
        roll_a = self.rng.uniform(-0.35, 0.35)
        self.add_foliage_card(
            root, direction, Vector((0.0, 0.0, 1.0)),
            length, width, quad_idx, droop=droop, cup=0.18, roll_rad=roll_a,
            sub_segs_len=segs_l, sub_segs_wid=segs_w, tint=tint, base_flex=base_flex,
        )
        # Companion orthogonal/tilted card rotated ~62-85 deg around branch axis
        roll_b = roll_a + self.rng.choice((-1.0, 1.0)) * self.rng.uniform(1.02, 1.38)
        self.add_foliage_card(
            root + direction.normalized() * (length * 0.08),
            direction, Vector((0.0, 0.0, 1.0)),
            length * 0.92, width * 0.92, (quad_idx + 1) % 4, droop=droop * 0.6, cup=0.14, roll_rad=roll_b,
            sub_segs_len=segs_l, sub_segs_wid=segs_w,
            tint=(tint[0] * 0.95, tint[1] * 0.96, tint[2] * 0.94),
            base_flex=base_flex,
        )

    def finalize_object(self, name: str, mat_bark: bpy.types.Material, mat_fol: bpy.types.Material) -> bpy.types.Object:
        mesh = bpy.data.meshes.new(name)
        self.bm.normal_update()
        self.bm.to_mesh(mesh)
        self.bm.free()

        mesh.materials.append(mat_bark)
        mesh.materials.append(mat_fol)

        # Compute custom split normals: keep bark normals natural, blend foliage normals 72% outward/upward
        n_loops = len(mesh.loops)
        custom_normals = [Vector((0.0, 0.0, 1.0))] * n_loops
        for poly in mesh.polygons:
            for li in poly.loop_indices:
                v_idx = mesh.loops[li].vertex_index
                v_pos = mesh.vertices[v_idx].co
                orig_n = Vector(mesh.vertices[v_idx].normal) if hasattr(mesh.vertices[v_idx], "normal") else Vector(poly.normal)
                if poly.material_index == 1:
                    out_up = (v_pos - self.crown_center) + Vector((0.0, 0.0, 0.38 * self.crown_radius))
                    if out_up.length < 1e-4:
                        out_up = Vector((0.0, 0.0, 1.0))
                    out_up.normalize()
                    blended = orig_n.lerp(out_up, 0.72).normalized()
                    custom_normals[li] = blended
                else:
                    custom_normals[li] = orig_n.normalized() if orig_n.length > 1e-4 else Vector((0.0, 0.0, 1.0))

        mesh.normals_split_custom_set(custom_normals)
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def build_conifer_tall(lod: int) -> bpy.types.Object:
    """Tall alpine fir/spruce (H=15.0m, R=3.1m), natural layered sweeping whorls, root flare to -0.15m."""
    H = 15.0
    R = 3.1
    tb = TreeBuilder(H, crown_center_z=7.6, crown_radius=R, seed=1011)
    rng = tb.rng

    # Smooth trunk with gentle organic lean + 5 buttress root flares down to -0.15m
    trunk_segs = 10 if lod == 0 else (7 if lod == 1 else 5)
    trunk_sides = 14 if lod == 0 else (8 if lod == 1 else 6)
    trunk_pts, trunk_rads = [], []
    for i in range(trunk_segs + 1):
        t = i / trunk_segs
        z = -0.15 + t * (H - 0.15)
        lean_x = 0.18 * (t ** 1.4) + 0.07 * math.sin(t * 4.5)
        lean_y = -0.11 * (t ** 1.3) + 0.06 * math.cos(t * 3.8)
        trunk_pts.append(Vector((lean_x, lean_y, z)))
        rad = 0.34 * ((1.0 - 0.92 * t) ** 1.05) + 0.015
        trunk_pts_last = rad
        trunk_rads.append(trunk_pts_last)

    def trunk_at_z(z: float) -> Vector:
        t = max(0.0, min(1.0, (z + 0.15) / (H - 0.15)))
        return Vector((0.18 * (t ** 1.4) + 0.07 * math.sin(t * 4.5), -0.11 * (t ** 1.3) + 0.06 * math.cos(t * 3.8), z))

    tb.add_wood_tube(
        trunk_pts, trunk_rads, sides=trunk_sides, uv_scale=0.75,
        buttress_lobes=5, buttress_strength=0.68,
        bark_tint_fn=lambda p: (0.86, 0.82, 0.78),
    )

    # Dead weathered lower branch stubs (1.2..2.1m) for close-up forest depth
    if lod == 0:
        for s_i in range(4):
            z = 1.15 + s_i * 0.24
            ang = s_i * 2.1 + 0.4
            d = Vector((math.cos(ang), math.sin(ang), rng.uniform(-0.28, -0.05))).normalized()
            stem = trunk_at_z(z)
            stub_len = rng.uniform(0.45, 0.78)
            tb.add_wood_tube(
                [stem, stem + d * stub_len], [0.032, 0.010], sides=5,
                bark_tint_fn=lambda p: (0.65, 0.62, 0.58),
            )

    # Whorls from 2.1m up to 14.3m
    whorls = 19 if lod == 0 else (12 if lod == 1 else 7)
    for w_i in range(whorls):
        frac = w_i / max(1, whorls - 1)
        z = 2.15 + frac * 12.15
        stem = trunk_at_z(z)
        # Irregular spruce/fir profile: widest at frac ~ 0.15..0.28, undulating taper toward spire
        env = math.sin(math.pi * (0.12 + 0.88 * (1.0 - frac))) ** 0.72 * (1.0 - 0.78 * (frac ** 1.15))
        whorl_r = R * max(0.14, env) * rng.uniform(0.86, 1.14)
        n_boughs = (6 if frac < 0.7 else 4) if lod == 0 else (4 if lod == 1 else 3)
        for b_i in range(n_boughs):
            # Occasional missing bough for natural wind gaps
            if rng.random() < (0.16 if lod == 0 else 0.10):
                continue
            ang = b_i * (2.0 * math.pi / n_boughs) + w_i * 1.618 + rng.uniform(-0.28, 0.28)
            horiz = Vector((math.cos(ang), math.sin(ang), 0.0))
            side = Vector((-horiz.y, horiz.x, 0.0))
            b_len = whorl_r * rng.uniform(0.76, 1.16)
            # Lower boughs sweep down then turn up at tip; upper boughs angle upward
            mid_z = (-0.28 + 0.55 * frac) * b_len
            tip_z = (-0.08 + 0.70 * frac) * b_len
            p0 = stem
            p1 = stem + horiz * (b_len * 0.45) + Vector((0.0, 0.0, mid_z))
            p2 = stem + horiz * (b_len * 0.82) + Vector((0.0, 0.0, tip_z))
            if lod < 2 and b_len > 0.55:
                b_rad = 0.048 * (1.0 - 0.65 * frac) + 0.010
                tb.add_wood_tube([p0, p1, p2], [b_rad, b_rad * 0.55, 0.010], sides=5 if lod == 0 else 4)

            # Attach layered 3D fir_bough cards along outer 70% of bough
            card_scale = max(0.55, min(1.25, b_len * 0.48))
            t_var = rng.uniform(0.86, 1.14)
            tint = (0.94 * t_var, 1.00 * t_var, 0.90 * t_var)
            # Main tip fan
            tip_dir = (p2 - p1).normalized()
            tb.add_crossed_spray_cluster(
                p1.lerp(p2, 0.45), tip_dir,
                length=card_scale * 1.08, width=card_scale * 0.95,
                quad_idx=rng.randint(0, 3), is_lod2=(lod == 2),
                droop=0.06, tint=tint, base_flex=0.28 + 0.2 * frac,
            )
            if lod < 2 and b_len > 1.05:
                # Left & right lateral fans branching from mid-bough
                for s_sign in (-1.0, 1.0):
                    lat_dir = (horiz * 0.72 + side * (0.65 * s_sign) + Vector((0.0, 0.0, 0.08 + 0.25 * frac))).normalized()
                    tb.add_foliage_card(
                        p1, lat_dir, Vector((0.0, 0.0, 1.0)),
                        length=card_scale * 0.95, width=card_scale * 0.85,
                        quad_idx=rng.randint(0, 3), droop=0.08, cup=0.16,
                        roll_rad=s_sign * 0.28, sub_segs_len=2, sub_segs_wid=2,
                        tint=(tint[0] * 0.96, tint[1] * 0.98, tint[2] * 0.95),
                        base_flex=0.25 + 0.15 * frac,
                    )

    # Sharp natural leader spire at apex (14.1..15.0m)
    apex = trunk_at_z(14.15)
    for k in range(3 if lod < 2 else 2):
        ang = k * 2.1
        d = Vector((math.cos(ang) * 0.28, math.sin(ang) * 0.28, 1.0)).normalized()
        tb.add_foliage_card(
            apex, d, Vector((1.0, 0.0, 0.0)),
            length=0.92, width=0.52, quad_idx=k % 4, droop=0.02, cup=0.18,
            roll_rad=ang, sub_segs_len=2 if lod == 0 else 1, sub_segs_wid=1,
            tint=(1.04, 1.08, 0.94), base_flex=0.35,
        )

    mat_bark, mat_fol = _make_pbr_tree_materials("pine_bark", "fir_bough", use_512=(lod > 0))
    return tb.finalize_object(f"conifer_tall_lod{lod}", mat_bark, mat_fol)


def build_conifer_medium(lod: int) -> bpy.types.Object:
    """Scots/mountain pine (H=9.5m, R=2.6m), open crown gaps, sinuous trunk, warm upper bark."""
    H = 9.5
    R = 2.6
    tb = TreeBuilder(H, crown_center_z=6.1, crown_radius=R, seed=2022)
    rng = tb.rng

    trunk_segs = 9 if lod == 0 else (6 if lod == 1 else 5)
    trunk_sides = 12 if lod == 0 else (8 if lod == 1 else 6)

    def trunk_at_z(z: float) -> Vector:
        t = max(0.0, min(1.0, (z + 0.15) / (H - 0.15)))
        return Vector((-0.24 * math.sin(t * 2.8) + 0.18 * t, 0.16 * math.cos(t * 2.2) - 0.16, z))

    trunk_pts = [trunk_at_z(-0.15 + (i / trunk_segs) * (H - 0.45)) for i in range(trunk_segs + 1)]
    trunk_rads = [0.24 * ((1.0 - 0.88 * (i / trunk_segs)) ** 0.95) + 0.015 for i in range(trunk_segs + 1)]

    # Scots pine has darker gray-brown base transitioning to warm cinnamon-orange upper bark!
    def pine_tint(pos: Vector) -> tuple[float, float, float]:
        u = max(0.0, min(1.0, (pos.z - 2.2) / 3.5))
        return (0.82 + 0.36 * u, 0.78 + 0.18 * u, 0.74 + 0.04 * u)

    tb.add_wood_tube(
        trunk_pts, trunk_rads, sides=trunk_sides, uv_scale=0.80,
        buttress_lobes=5, buttress_strength=0.58, bark_tint_fn=pine_tint,
    )

    if lod == 0:
        for s_i in range(3):
            z = 1.65 + s_i * 0.42
            ang = s_i * 2.4 + 0.8
            d = Vector((math.cos(ang), math.sin(ang), rng.uniform(-0.20, 0.05))).normalized()
            stem = trunk_at_z(z)
            tb.add_wood_tube([stem, stem + d * rng.uniform(0.42, 0.68)], [0.028, 0.009], sides=5, bark_tint_fn=pine_tint)

    # Asymmetric crooked pine limbs from 3.1m..9.1m supporting airy pine needle pads
    n_limbs = 16 if lod == 0 else (10 if lod == 1 else 6)
    for li in range(n_limbs):
        frac = li / max(1, n_limbs - 1)
        z = 3.15 + frac * 5.75
        stem = trunk_at_z(z)
        ang = li * 2.39996 + rng.uniform(-0.35, 0.35)
        horiz = Vector((math.cos(ang), math.sin(ang), 0.0))
        side = Vector((-horiz.y, horiz.x, 0.0))
        # Scots pine has broader flat-topped upper crown, not a sharp point
        reach = R * (0.65 + 0.45 * math.sin(math.pi * (0.2 + 0.75 * frac))) * rng.uniform(0.75, 1.18)
        if frac > 0.82:
            reach *= 0.65
        lift = (0.15 + 0.42 * frac) * reach
        p0 = stem
        p1 = stem + horiz * (reach * 0.55) + side * rng.uniform(-0.22, 0.22) + Vector((0.0, 0.0, lift * 0.45))
        p2 = stem + horiz * reach + Vector((0.0, 0.0, lift))
        if lod < 2:
            tb.add_wood_tube([p0, p1, p2], [0.045 * (1.0 - 0.5 * frac) + 0.012, 0.024, 0.010], sides=5 if lod == 0 else 4, bark_tint_fn=pine_tint)

        # 2-3 needle pad clusters per limb
        n_pads = 3 if lod == 0 else (2 if lod == 1 else 1)
        for pi in range(n_pads):
            pad_root = p1.lerp(p2, 0.40 + 0.55 * (pi / max(1, n_pads - 1)))
            pad_dir = (horiz * 0.85 + side * rng.uniform(-0.45, 0.45) + Vector((0.0, 0.0, rng.uniform(0.18, 0.55)))).normalized()
            c_len = rng.uniform(0.95, 1.38) if lod < 2 else rng.uniform(1.25, 1.55)
            t_var = rng.uniform(0.86, 1.14)
            tb.add_crossed_spray_cluster(
                pad_root, pad_dir, length=c_len, width=c_len * 0.92,
                quad_idx=rng.randint(0, 3), is_lod2=(lod == 2),
                droop=0.04, tint=(0.98 * t_var, 1.02 * t_var, 0.88 * t_var),
                base_flex=0.30 + 0.20 * frac,
            )

    mat_bark, mat_fol = _make_pbr_tree_materials("pine_bark", "pine_bough", use_512=(lod > 0))
    return tb.finalize_object(f"conifer_medium_lod{lod}", mat_bark, mat_fol)


def build_broadleaf_oak(lod: int) -> bpy.types.Object:
    """Mature temperate oak/beech (H=12.0m, R=4.4m), gnarled branching skeleton, irregular crown gaps."""
    H = 12.0
    R = 4.4
    tb = TreeBuilder(H, crown_center_z=7.4, crown_radius=R, seed=3033)
    rng = tb.rng

    # Stout gnarled trunk (0..3.4m) with 6 root buttresses to -0.15m
    trunk_pts = [
        Vector((0.0, 0.0, -0.15)),
        Vector((0.02, -0.01, 0.45)),
        Vector((0.06, 0.03, 1.35)),
        Vector((0.04, 0.06, 2.35)),
        Vector((-0.02, 0.04, 3.25)),
    ]
    trunk_rads = [0.44, 0.36, 0.31, 0.28, 0.24]
    tb.add_wood_tube(
        trunk_pts, trunk_rads, sides=14 if lod == 0 else (8 if lod == 1 else 6),
        uv_scale=0.65, buttress_lobes=6, buttress_strength=0.72,
        bark_tint_fn=lambda p: (0.88, 0.86, 0.84),
    )

    # 5 heavy crooked primary boughs radiating at staggered heights (2.35..3.30m)
    bough_specs = [
        (0.0, 2.55, 48.0, 4.1),
        (1.35, 2.80, 42.0, 3.8),
        (2.60, 2.45, 52.0, 4.2),
        (3.85, 3.05, 38.0, 3.7),
        (5.05, 3.20, 22.0, 4.5),  # central-upper crown leader bough
    ]
    for bi, (ang, z_start, tilt_deg, reach) in enumerate(bough_specs):
        horiz = Vector((math.cos(ang), math.sin(ang), 0.0))
        side = Vector((-horiz.y, horiz.x, 0.0))
        tilt = math.radians(tilt_deg)
        d1 = (horiz * math.sin(tilt) + Vector((0.0, 0.0, math.cos(tilt)))).normalized()
        p0 = Vector((-0.01, 0.03, z_start))
        p1 = p0 + d1 * (reach * 0.48) + side * rng.uniform(-0.28, 0.28)
        d2 = (d1 + horiz * 0.22 + Vector((0.0, 0.0, 0.18))).normalized()
        p2 = p1 + d2 * (reach * 0.50) + side * rng.uniform(-0.35, 0.35)
        tb.add_wood_tube([p0, p1, p2], [0.16, 0.10, 0.055], sides=8 if lod == 0 else (5 if lod == 1 else 4))

        # Fork 2-3 secondary limbs off each primary bough -> creating separate sub-crown lobes & sky gaps!
        n_sec = 3 if lod < 2 else 2
        for si in range(n_sec):
            s_origin = p1 if si == 0 else p1.lerp(p2, 0.55 + 0.35 * (si - 1))
            s_ang = ang + (si - (n_sec - 1) * 0.5) * 0.85 + rng.uniform(-0.18, 0.18)
            s_horiz = Vector((math.cos(s_ang), math.sin(s_ang), 0.0))
            s_dir = (s_horiz * 0.72 + Vector((0.0, 0.0, rng.uniform(0.45, 0.85)))).normalized()
            s_len = rng.uniform(1.85, 2.75)
            s_mid = s_origin + s_dir * (s_len * 0.55) + Vector((0.0, 0.0, 0.12))
            s_end = s_mid + (s_dir + s_horiz * 0.18).normalized() * (s_len * 0.50)
            s_end.z = min(H - 0.45, s_end.z)
            if lod < 2:
                tb.add_wood_tube([s_origin, s_mid, s_end], [0.062, 0.038, 0.018], sides=6 if lod == 0 else 4)

            # Tertiary twigs & leaf-spray clusters around secondary limb ends (leaving central canopy open!)
            n_clusters = 4 if lod == 0 else (3 if lod == 1 else 2)
            for ci in range(n_clusters):
                t_c = 0.35 + 0.65 * (ci / max(1, n_clusters - 1))
                c_anchor = s_mid.lerp(s_end, t_c)
                c_ang = s_ang + rng.uniform(-0.95, 0.95)
                c_dir = Vector((math.cos(c_ang) * 0.82, math.sin(c_ang) * 0.82, rng.uniform(0.15, 0.75))).normalized()
                if lod == 0:
                    twig_end = c_anchor + c_dir * 0.55
                    tb.add_wood_tube([c_anchor, twig_end], [0.020, 0.008], sides=4)
                else:
                    twig_end = c_anchor + c_dir * 0.25

                t_var = rng.uniform(0.84, 1.15)
                spray_len = rng.uniform(1.20, 1.65) if lod < 2 else rng.uniform(1.60, 2.05)
                tb.add_crossed_spray_cluster(
                    twig_end - c_dir * 0.15, c_dir,
                    length=spray_len, width=spray_len * 1.02,
                    quad_idx=rng.randint(0, 3), is_lod2=(lod == 2),
                    droop=0.08, tint=(0.96 * t_var, 1.00 * t_var, 0.90 * t_var),
                    base_flex=0.32,
                )

    mat_bark, mat_fol = _make_pbr_tree_materials("oak_bark", "oak_spray", use_512=(lod > 0))
    return tb.finalize_object(f"broadleaf_oak_lod{lod}", mat_bark, mat_fol)


def build_broadleaf_birch(lod: int) -> bpy.types.Object:
    """Slender silver birch (H=10.0m, R=2.6m), forked upper stems, chalky white lenticel bark, airy crown."""
    H = 10.0
    R = 2.6
    tb = TreeBuilder(H, crown_center_z=6.2, crown_radius=R, seed=4044)
    rng = tb.rng

    # Basal dark craggy bark grading to chalky white upper trunk
    def birch_tint(pos: Vector) -> tuple[float, float, float]:
        # Dark craggy basal bark 0..0.95m, bright chalky birch bark above
        u = max(0.0, min(1.0, (pos.z - 0.15) / 1.15))
        b = 0.34 + 0.66 * (u ** 0.85)
        return (b * 1.02, b * 1.01, b * 0.98)

    # Lower trunk up to fork at 3.2m
    lower_pts = [
        Vector((0.0, 0.0, -0.15)),
        Vector((0.03, -0.02, 0.65)),
        Vector((0.09, -0.04, 1.65)),
        Vector((0.14, 0.02, 2.60)),
        Vector((0.12, 0.06, 3.25)),
    ]
    tb.add_wood_tube(
        lower_pts, [0.18, 0.14, 0.12, 0.105, 0.095],
        sides=12 if lod == 0 else (8 if lod == 1 else 6),
        uv_scale=0.85, buttress_lobes=5, buttress_strength=0.48, bark_tint_fn=birch_tint,
    )

    # Twin forked ascending stems from 3.2m up to 9.4m / 8.5m
    stems = [
        [Vector((0.12, 0.06, 3.20)), Vector((0.35, 0.22, 5.2)), Vector((0.48, 0.30, 7.3)), Vector((0.38, 0.22, 9.2))],
        [Vector((0.12, 0.06, 3.20)), Vector((-0.28, -0.18, 5.0)), Vector((-0.52, -0.32, 6.9)), Vector((-0.44, -0.25, 8.3))],
    ]
    stem_rads = [[0.072, 0.052, 0.032, 0.012], [0.062, 0.044, 0.026, 0.010]]
    for s_pts, s_rads in zip(stems, stem_rads):
        tb.add_wood_tube(s_pts, s_rads, sides=8 if lod == 0 else (5 if lod == 1 else 4), uv_scale=0.95, bark_tint_fn=birch_tint)

        # Slender steeply ascending limbs with slightly weeping airy foliage clusters
        n_limbs = 9 if lod == 0 else (6 if lod == 1 else 4)
        for li in range(n_limbs):
            frac = li / max(1, n_limbs - 1)
            idx_f = frac * (len(s_pts) - 1)
            i0 = min(len(s_pts) - 2, int(idx_f))
            anchor = s_pts[i0].lerp(s_pts[i0 + 1], idx_f - i0)
            ang = li * 2.39996 + rng.uniform(-0.3, 0.3)
            horiz = Vector((math.cos(ang), math.sin(ang), 0.0))
            reach = rng.uniform(0.95, 1.75) * (1.0 - 0.45 * frac)
            l_mid = anchor + horiz * (reach * 0.55) + Vector((0.0, 0.0, reach * 0.65))
            l_tip = anchor + horiz * reach + Vector((0.0, 0.0, reach * 0.72))
            if lod < 2:
                tb.add_wood_tube([anchor, l_mid, l_tip], [0.025, 0.014, 0.006], sides=4, bark_tint_fn=birch_tint)

            # Airy birch spray clusters (fewer, lighter, spaced out for lacy dappled look)
            t_var = rng.uniform(0.86, 1.16)
            c_len = rng.uniform(0.95, 1.32) if lod < 2 else rng.uniform(1.25, 1.60)
            c_dir = (horiz * 0.78 + Vector((0.0, 0.0, rng.uniform(0.15, 0.55)))).normalized()
            tb.add_crossed_spray_cluster(
                l_mid.lerp(l_tip, 0.55), c_dir,
                length=c_len, width=c_len * 0.92,
                quad_idx=rng.randint(0, 3), is_lod2=(lod == 2),
                droop=0.12, tint=(0.98 * t_var, 1.02 * t_var, 0.90 * t_var),
                base_flex=0.35 + 0.25 * frac,
            )

    mat_bark, mat_fol = _make_pbr_tree_materials("birch_bark", "birch_spray", use_512=(lod > 0))
    return tb.finalize_object(f"broadleaf_birch_lod{lod}", mat_bark, mat_fol)


def build_sapling_conifer(lod: int) -> bpy.types.Object:
    """Young understory fir/pine (H=3.4m, R=1.2m), feathery branches starting low, root flare to -0.15m."""
    H = 3.4
    R = 1.2
    tb = TreeBuilder(H, crown_center_z=1.75, crown_radius=R, seed=5055)
    rng = tb.rng

    trunk_pts = [Vector((0.02 * (i / 5.0), -0.015 * (i / 5.0), -0.15 + (i / 5.0) * (H - 0.15))) for i in range(6)]
    trunk_rads = [0.085 * (1.0 - 0.85 * (i / 5.0)) + 0.008 for i in range(6)]
    tb.add_wood_tube(
        trunk_pts, trunk_rads, sides=8 if lod == 0 else 6, uv_scale=1.2,
        buttress_lobes=4, buttress_strength=0.45,
        bark_tint_fn=lambda p: (0.85, 0.80, 0.74),
    )

    whorls = 9 if lod == 0 else 5
    for w_i in range(whorls):
        frac = w_i / max(1, whorls - 1)
        z = 0.42 + frac * 2.65
        stem = Vector((0.02 * frac, -0.015 * frac, z))
        whorl_r = R * max(0.18, 1.0 - 0.78 * (frac ** 1.05)) * rng.uniform(0.85, 1.15)
        n_boughs = 4 if lod == 0 else 3
        for b_i in range(n_boughs):
            ang = b_i * (2.0 * math.pi / n_boughs) + w_i * 1.7 + rng.uniform(-0.25, 0.25)
            horiz = Vector((math.cos(ang), math.sin(ang), 0.0))
            b_dir = (horiz * 0.85 + Vector((0.0, 0.0, 0.15 + 0.55 * frac))).normalized()
            if lod == 0:
                tb.add_wood_tube([stem, stem + b_dir * (whorl_r * 0.55)], [0.016, 0.006], sides=4)
            t_var = rng.uniform(0.90, 1.15)
            tb.add_crossed_spray_cluster(
                stem + b_dir * 0.10, b_dir,
                length=max(0.45, whorl_r * 0.92), width=max(0.42, whorl_r * 0.85),
                quad_idx=rng.randint(0, 3), is_lod2=(lod > 0),
                droop=0.05, tint=(0.98 * t_var, 1.06 * t_var, 0.90 * t_var),
                base_flex=0.22 + 0.35 * frac,
            )

    # Young leader tip
    tb.add_foliage_card(
        Vector((0.02, -0.015, 2.95)), Vector((0.0, 0.0, 1.0)), Vector((1.0, 0.0, 0.0)),
        length=0.52, width=0.34, quad_idx=0, droop=0.01, cup=0.18,
        sub_segs_len=1, sub_segs_wid=1, tint=(1.04, 1.10, 0.94), base_flex=0.55,
    )

    mat_bark, mat_fol = _make_pbr_tree_materials("pine_bark", "fir_bough", use_512=(lod > 0))
    return tb.finalize_object(f"sapling_conifer_lod{lod}", mat_bark, mat_fol)


SPECIES_BUILDERS = {
    "conifer_tall": (build_conifer_tall, (0, 1, 2)),
    "conifer_medium": (build_conifer_medium, (0, 1, 2)),
    "broadleaf_oak": (build_broadleaf_oak, (0, 1, 2)),
    "broadleaf_birch": (build_broadleaf_birch, (0, 1, 2)),
    "sapling_conifer": (build_sapling_conifer, (0, 1)),
}


def export_all_trees() -> dict:
    """Build and export all 14 GLBs, returning exact mesh stats (tris, bounds, file size)."""
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    stats = {}
    for species, (builder_fn, lods) in SPECIES_BUILDERS.items():
        for lod in lods:
            reset_scene()
            obj = builder_fn(lod)
            mesh = obj.data
            tris = sum(max(0, len(p.vertices) - 2) for p in mesh.polygons)
            bark_tris = sum(max(0, len(p.vertices) - 2) for p in mesh.polygons if p.material_index == 0)
            fol_tris = sum(max(0, len(p.vertices) - 2) for p in mesh.polygons if p.material_index == 1)
            xs = [v.co.x for v in mesh.vertices]
            ys = [v.co.y for v in mesh.vertices]
            zs = [v.co.z for v in mesh.vertices]

            glb_name = f"{species}_lod{lod}.glb"
            glb_path = OUT_DIR / glb_name
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.ops.export_scene.gltf(
                filepath=str(glb_path),
                export_format="GLB",
                use_selection=True,
                export_yup=True,
                export_apply=True,
                export_normals=True,
                export_vertex_color="NAME",
                export_vertex_color_name="Color",
                export_materials="EXPORT",
                export_image_format="AUTO",
            )
            size_kb = glb_path.stat().st_size / 1024.0
            stats[glb_name] = {
                "tris": tris,
                "bark_tris": bark_tris,
                "foliage_tris": fol_tris,
                "height_m": round(max(zs), 3),
                "min_y_m": round(min(zs), 3),
                "crown_radius_m": round(max(abs(min(xs)), abs(max(xs)), abs(min(ys)), abs(max(ys))), 3),
                "size_kb": round(size_kb, 1),
            }
            print(f"[export] {glb_name}: tris={tris} (bark={bark_tris}, fol={fol_tris}), H={max(zs):.2f}m, R={stats[glb_name]['crown_radius_m']:.2f}m, {size_kb:.1f} KB")

    (OUT_DIR / "tree_stats.json").write_text(json.dumps(stats, indent=2) + "\n", encoding="utf-8")
    return stats


# ---------------------------------------------------------------------------
# Stage 3: Contact Sheets & Multi-Angle Visual Verification Renders
# ---------------------------------------------------------------------------

def render_atlas_contact_sheet(preview_path: Path) -> None:
    """Pack all 4 foliage atlases + 3 bark maps into a clean contact sheet using NumPy."""
    cell = 440
    pad = 16
    cols, rows = 4, 2
    sheet = np.full((rows * (cell + pad) + pad, cols * (cell + pad) + pad, 3), (32, 36, 40), dtype=np.uint8)

    items = [
        (TEX_DIR / "fir_bough_albedo.png", True),
        (TEX_DIR / "pine_bough_albedo.png", True),
        (TEX_DIR / "oak_spray_albedo.png", True),
        (TEX_DIR / "birch_spray_albedo.png", True),
        (TEX_DIR / "pine_bark_albedo.png", False),
        (TEX_DIR / "oak_bark_albedo.png", False),
        (TEX_DIR / "birch_bark_albedo.png", False),
        (TEX_DIR / "oak_spray_normal.png", False),
    ]
    sky = np.array([135, 165, 200], dtype=np.float32)
    for idx, (path, comp_sky) in enumerate(items):
        r, c = divmod(idx, cols)
        x0 = pad + c * (cell + pad)
        y0 = pad + r * (cell + pad)
        raw = load_blender_image_rgba(path)
        u8 = np.clip(np.rint(raw * 255.0), 0, 255).astype(np.uint8)
        resized = resize_u8_bilinear(u8, cell, cell)
        if comp_sky:
            a = resized[:, :, 3:4].astype(np.float32) / 255.0
            rgb = resized[:, :, :3].astype(np.float32) * a + sky * (1.0 - a)
            tile = np.clip(np.rint(rgb), 0, 255).astype(np.uint8)
        else:
            tile = resized[:, :, :3]
        sheet[y0 : y0 + cell, x0 : x0 + cell] = tile

    preview_path.parent.mkdir(parents=True, exist_ok=True)
    write_png(preview_path, sheet)
    print(f"[preview] Saved atlas contact sheet: {preview_path}")


def _setup_preview_studio(scene: bpy.types.Scene) -> bpy.types.Object:
    """Configure bright golden-afternoon Cycles studio for inspecting exported GLBs."""
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.use_denoising = False
    scene.cycles.max_bounces = 3
    scene.cycles.transparent_max_bounces = 12

    world = bpy.data.worlds.new("Sky")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "NISHITA"
    sky.sun_elevation = math.radians(42.0)
    sky.sun_rotation = math.radians(38.0)
    bg.inputs["Strength"].default_value = 0.55
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])

    # Warm sun light
    sun_data = bpy.data.lights.new("Sun", type="SUN")
    sun_data.energy = 3.2
    sun_data.angle = math.radians(0.8)
    sun_data.color = (1.0, 0.95, 0.88)
    sun_obj = bpy.data.objects.new("Sun", sun_data)
    scene.collection.objects.link(sun_obj)
    sun_obj.rotation_euler = (math.radians(48.0), 0.0, math.radians(-38.0))

    # Neutral temperate forest ground disc
    bpy.ops.mesh.primitive_plane_add(size=120.0, location=(0.0, 0.0, 0.0))
    ground = bpy.context.active_object
    g_mat = bpy.data.materials.new("Ground")
    g_mat.use_nodes = True
    g_bsdf = g_mat.node_tree.nodes["Principled BSDF"]
    g_bsdf.inputs["Base Color"].default_value = (0.14, 0.16, 0.09, 1.0)
    g_bsdf.inputs["Roughness"].default_value = 0.95
    ground.data.materials.append(g_mat)

    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"

    cam_data = bpy.data.cameras.new("Cam")
    cam_obj = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj
    return cam_obj


def _aim_camera(cam_obj: bpy.types.Object, eye: Vector, target: Vector, lens_mm: float = 42.0) -> None:
    cam_obj.location = eye
    cam_obj.data.lens = lens_mm
    direction = (target - eye).normalized()
    cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_tree_contact_sheets(preview_dir: Path) -> None:
    """Import exported GLBs and render front, side, top, close-up, and LOD sheets."""
    preview_dir.mkdir(parents=True, exist_ok=True)
    tmp_dir = preview_dir / "_tmp_renders"
    tmp_dir.mkdir(parents=True, exist_ok=True)

    # 1. Lineup of all 5 LOD0 species side-by-side (front, side, top-angle)
    reset_scene()
    scene = bpy.context.scene
    cam = _setup_preview_studio(scene)
    offsets = [
        ("conifer_tall_lod0.glb", -14.0),
        ("conifer_medium_lod0.glb", -6.5),
        ("broadleaf_oak_lod0.glb", 1.5),
        ("broadleaf_birch_lod0.glb", 9.5),
        ("sapling_conifer_lod0.glb", 15.0),
    ]
    for fn, x_off in offsets:
        bpy.ops.import_scene.gltf(filepath=str(OUT_DIR / fn))
        for obj in bpy.context.selected_objects:
            if obj.type == "MESH" or obj.parent is None:
                obj.location.x += x_off

    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.image_settings.file_format = "PNG"

    views = [
        ("lineup_front", Vector((1.0, -34.0, 6.8)), Vector((0.5, 0.0, 6.5)), 38.0),
        ("lineup_side", Vector((30.0, -22.0, 8.2)), Vector((0.0, 0.0, 6.2)), 40.0),
        ("lineup_top", Vector((0.5, -6.0, 42.0)), Vector((0.5, 0.0, 5.0)), 42.0),
        ("closeup_trunks", Vector((1.0, -14.5, 2.2)), Vector((-1.5, 0.0, 2.4)), 46.0),
    ]
    tiles = []
    for name, eye, tgt, lens in views:
        _aim_camera(cam, eye, tgt, lens)
        p = tmp_dir / f"{name}.png"
        scene.render.filepath = str(p)
        bpy.ops.render.render(write_still=True)
        tiles.append(load_blender_image_rgba(p)[:, :, :3])
        p.unlink(missing_ok=True)

    # Pack 2x2 grid into trees_lod0_sheet.png (1600x900)
    h, w = 450, 800
    sheet = np.zeros((h * 2, w * 2, 3), dtype=np.uint8)
    for i, arr_f in enumerate(tiles):
        r, c = divmod(i, 2)
        u8 = np.clip(np.rint(arr_f * 255.0), 0, 255).astype(np.uint8)
        sheet[r * h : (r + 1) * h, c * w : (c + 1) * w] = resize_u8_bilinear(u8, h, w)
    write_png(preview_dir / "trees_lod0_sheet.png", sheet)

    # 2. LOD comparison sheet: conifer_tall LOD0/1/2 + broadleaf_oak LOD0/1/2
    reset_scene()
    scene = bpy.context.scene
    cam = _setup_preview_studio(scene)
    lod_items = [
        ("conifer_tall_lod0.glb", -14.0, 0.0),
        ("conifer_tall_lod1.glb", -7.0, 0.0),
        ("conifer_tall_lod2.glb", 0.0, 0.0),
        ("broadleaf_oak_lod0.glb", 8.0, 0.0),
        ("broadleaf_oak_lod1.glb", 17.0, 0.0),
        ("broadleaf_oak_lod2.glb", 26.0, 0.0),
    ]
    for fn, x_off, y_off in lod_items:
        bpy.ops.import_scene.gltf(filepath=str(OUT_DIR / fn))
        for obj in bpy.context.selected_objects:
            if obj.parent is None:
                obj.location.x += x_off
                obj.location.y += y_off

    scene.render.resolution_x = 1600
    scene.render.resolution_y = 720
    _aim_camera(cam, Vector((6.0, -38.0, 7.2)), Vector((6.0, 0.0, 6.8)), 40.0)
    out_lods = preview_dir / "trees_lods_comparison.png"
    scene.render.filepath = str(out_lods)
    bpy.ops.render.render(write_still=True)

    # 3. Close-up of broadleaf_oak + broadleaf_birch canopy & bark
    reset_scene()
    scene = bpy.context.scene
    cam = _setup_preview_studio(scene)
    for fn, x_off in [("broadleaf_oak_lod0.glb", -4.2), ("broadleaf_birch_lod0.glb", 3.2)]:
        bpy.ops.import_scene.gltf(filepath=str(OUT_DIR / fn))
        for obj in bpy.context.selected_objects:
            if obj.parent is None:
                obj.location.x += x_off
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    _aim_camera(cam, Vector((0.0, -14.5, 4.8)), Vector((-0.5, 0.0, 5.2)), 42.0)
    out_broad = preview_dir / "trees_broadleaf_closeup.png"
    scene.render.filepath = str(out_broad)
    bpy.ops.render.render(write_still=True)

    try:
        tmp_dir.rmdir()
    except OSError:
        pass
    print(f"[preview] Rendered tree contact sheets into {preview_dir}")


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", choices=("all", "textures", "meshes", "render"), default="all")
    parser.add_argument("--preview-dir", type=Path, default=DEFAULT_PREVIEW_DIR)
    args = parser.parse_args(argv)

    if args.stage in ("all", "textures"):
        generate_bark_textures()
        for sp in ("fir_bough", "pine_bough", "oak_spray", "birch_spray"):
            render_botanical_atlas(sp, TEX_DIR / sp, ATLAS_RES)
        render_atlas_contact_sheet(args.preview_dir / "trees_atlas_contact_sheet.png")

    if args.stage in ("all", "meshes"):
        export_all_trees()

    if args.stage in ("all", "render"):
        render_tree_contact_sheets(args.preview_dir)


if __name__ == "__main__":
    main()
