#!/usr/bin/env python3
"""Inspect source/production glTF/GLB assets in Blender 4.5.10.

Usage:
    blender --background --python tools/environment_assets/blender_inspect.py -- ^
        --input path/to/asset.gltf --out-dir path/to/out [--name label] [--res 512]
"""
import argparse
import json
import math
from pathlib import Path
import sys

import bpy
import mathutils
import numpy as np


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input", type=Path, required=True, help="Path to .gltf or .glb file")
    ap.add_argument("--out-dir", type=Path, required=True, help="Output directory for sheet and stats JSON")
    ap.add_argument("--name", type=str, default=None, help="Output basename (defaults to input stem)")
    ap.add_argument("--res", type=int, default=512, help="Per-tile render resolution (2x2 grid = 2*res)")
    ap.add_argument("--samples", type=int, default=16, help="Render samples")
    return ap.parse_args(argv)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_gltf(path: Path):
    bpy.ops.import_scene.gltf(filepath=str(path))


def collect_stats(asset_path: Path):
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    total_verts = 0
    total_polys = 0
    total_tris = 0
    uv_layers = set()
    color_attrs = set()
    materials = []
    min_co = mathutils.Vector((float("inf"), float("inf"), float("inf")))
    max_co = mathutils.Vector((float("-inf"), float("-inf"), float("-inf")))

    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in meshes:
        eval_obj = obj.evaluated_get(depsgraph)
        mesh = eval_obj.to_mesh()
        mesh.calc_loop_triangles()
        total_verts += len(mesh.vertices)
        total_polys += len(mesh.polygons)
        total_tris += len(mesh.loop_triangles)
        for uv in mesh.uv_layers:
            uv_layers.add(uv.name)
        for ca in mesh.color_attributes:
            color_attrs.add(f"{ca.name}:{ca.domain}:{ca.data_type}")
        mat_world = eval_obj.matrix_world
        for corner in obj.bound_box:
            wc = mat_world @ mathutils.Vector(corner)
            min_co.x = min(min_co.x, wc.x)
            min_co.y = min(min_co.y, wc.y)
            min_co.z = min(min_co.z, wc.z)
            max_co.x = max(max_co.x, wc.x)
            max_co.y = max(max_co.y, wc.y)
            max_co.z = max(max_co.z, wc.z)
        eval_obj.to_mesh_clear()

        for slot in obj.material_slots:
            if slot.material and slot.material.name not in materials:
                materials.append(slot.material.name)

    if not meshes:
        min_co = mathutils.Vector((0.0, 0.0, 0.0))
        max_co = mathutils.Vector((0.0, 0.0, 0.0))

    textures = []
    for img in bpy.data.images:
        if img.name in ("Render Result", "Viewer Node"):
            continue
        textures.append({
            "name": img.name,
            "size": [int(img.size[0]), int(img.size[1])],
            "channels": int(img.channels),
            "filepath": img.filepath,
        })

    size = max_co - min_co
    return {
        "file": str(asset_path),
        "mesh_objects": len(meshes),
        "vertices": total_verts,
        "polygons": total_polys,
        "triangles": total_tris,
        "bounds_min_blender_xyz": [round(min_co.x, 4), round(min_co.y, 4), round(min_co.z, 4)],
        "bounds_max_blender_xyz": [round(max_co.x, 4), round(max_co.y, 4), round(max_co.z, 4)],
        "size_m_xyz": [round(size.x, 4), round(size.y, 4), round(size.z, 4)],
        "materials": materials,
        "uv_layers": sorted(uv_layers),
        "color_attributes": sorted(color_attrs),
        "textures": textures,
    }, min_co, max_co


def setup_lighting_and_render(scene, res: int, samples: int):
    # Pick EEVEE Next in Blender 4.2+, fallback to EEVEE or Cycles
    engines = {e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items}
    if "BLENDER_EEVEE_NEXT" in engines:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
        scene.eevee.taa_render_samples = samples
    elif "BLENDER_EEVEE" in engines:
        scene.render.engine = "BLENDER_EEVEE"
        scene.eevee.taa_render_samples = samples
    else:
        scene.render.engine = "CYCLES"
        scene.cycles.samples = samples

    scene.render.resolution_x = res
    scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "AgX"

    world = bpy.data.worlds.new("InspectWorld")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.38, 0.42, 0.48, 1.0)
        bg.inputs[1].default_value = 1.1

    sun_data = bpy.data.lights.new("InspectSun", type="SUN")
    sun_data.energy = 3.2
    sun_data.angle = math.radians(2.0)
    sun_obj = bpy.data.objects.new("InspectSun", sun_data)
    sun_obj.rotation_euler = (math.radians(50.0), math.radians(10.0), math.radians(35.0))
    scene.collection.objects.link(sun_obj)

    fill_data = bpy.data.lights.new("InspectFill", type="SUN")
    fill_data.energy = 0.8
    fill_obj = bpy.data.objects.new("InspectFill", fill_data)
    fill_obj.rotation_euler = (math.radians(65.0), 0.0, math.radians(-145.0))
    scene.collection.objects.link(fill_obj)


def look_at(cam_obj, eye: mathutils.Vector, target: mathutils.Vector):
    cam_obj.location = eye
    direction = target - eye
    rot_quat = direction.to_track_quat("-Z", "Y")
    cam_obj.rotation_euler = rot_quat.to_euler()


def render_contact_sheet(min_co: mathutils.Vector, max_co: mathutils.Vector, out_png: Path, res: int, samples: int):
    scene = bpy.context.scene
    setup_lighting_and_render(scene, res, samples)

    center = (min_co + max_co) * 0.5
    size = max_co - min_co
    radius = max(size.length * 0.5, 0.25)
    dist = radius / math.tan(math.radians(22.0)) * 1.15

    cam_data = bpy.data.cameras.new("InspectCam")
    cam_data.lens = 50.0
    cam_data.clip_start = 0.02
    cam_data.clip_end = max(1000.0, dist * 10.0)
    cam_obj = bpy.data.objects.new("InspectCam", cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj

    views = [
        ("front", center + mathutils.Vector((0.0, -dist, size.z * 0.08))),
        ("side", center + mathutils.Vector((dist, 0.0, size.z * 0.08))),
        ("three_quarter", center + mathutils.Vector((dist * 0.72, -dist * 0.72, dist * 0.42))),
        ("top", center + mathutils.Vector((0.0, -0.01 * dist, dist * 1.05))),
    ]

    tiles = []
    tmp_dir = out_png.parent / f".tmp_{out_png.stem}"
    tmp_dir.mkdir(parents=True, exist_ok=True)
    try:
        for label, eye in views:
            look_at(cam_obj, eye, center)
            tile_path = tmp_dir / f"{label}.png"
            scene.render.filepath = str(tile_path)
            bpy.ops.render.render(write_still=True)
            img = bpy.data.images.load(str(tile_path))
            arr = np.array(img.pixels[:], dtype=np.float32).reshape((res, res, 4))
            bpy.data.images.remove(img)
            tiles.append(arr)

        # Blender image pixels are bottom-up: top row = front (left) + side (right), bottom row = 3/4 (left) + top (right)
        top_row = np.concatenate([tiles[0], tiles[1]], axis=1)
        bot_row = np.concatenate([tiles[2], tiles[3]], axis=1)
        grid = np.concatenate([bot_row, top_row], axis=0)

        sheet = bpy.data.images.new("ContactSheet", width=res * 2, height=res * 2, alpha=True)
        sheet.pixels.foreach_set(grid.ravel())
        sheet.filepath_raw = str(out_png)
        sheet.file_format = "PNG"
        sheet.save()
        bpy.data.images.remove(sheet)
    finally:
        for p in tmp_dir.glob("*"):
            p.unlink(missing_ok=True)
        tmp_dir.rmdir()


def main():
    args = parse_args()
    inp = args.input.resolve()
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    name = args.name or inp.stem

    clear_scene()
    import_gltf(inp)
    stats, min_co, max_co = collect_stats(inp)

    stats_path = out_dir / f"{name}_stats.json"
    stats_path.write_text(json.dumps(stats, indent=2) + "\n", encoding="utf-8")

    sheet_path = out_dir / f"{name}_sheet.png"
    render_contact_sheet(min_co, max_co, sheet_path, args.res, args.samples)
    print(f"Inspected {name}: {stats['triangles']} tris, size={stats['size_m_xyz']}, sheet={sheet_path}")


if __name__ == "__main__":
    main()
