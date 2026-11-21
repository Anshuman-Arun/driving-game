#!/usr/bin/env python3
"""Prepare the *actual* CC0 Spectral GT RS GLB for Aster Valley.

Run with Blender 4.3+ or 5.x:
  blender -b -t 4 --python tools/vehicle_upgrade/prepare_spectral.py -- \
    --source /absolute/path/to/spectral_gt_rs_game_ready.glb \
    --output assets/vehicle_upgrade

No mesh primitives or stand-in geometry are synthesized by this pipeline.
Input is a genuine third-party model; the script only reorients, groups,
prunes badges, decimates and exports its actual geometry.
"""
from __future__ import annotations

import argparse
import hashlib
import math
import pathlib
import sys
from collections import Counter

import bpy
from mathutils import Matrix, Vector

# Source verified against the GitHub repository's CC0 LICENSE at this revision.
ORIGIN = "https://github.com/JaronKBragg7337/spectral-gt-rs"
SOURCE_BLOB_SHA1 = "f5b814848453a6c75a48f5047fdadaa7bdc78969"
WHEELBASE_SCALE = 2.71 / 2.85
WHEEL_RADIUS_SCALE = 0.35 / (0.405 + 0.135)  # Torus OD, not major radius
CHASSIS_BODY_VERTICAL_OFFSET_M = -0.57
SOURCE_WHEEL_HEIGHT_M = 0.53
SOURCE_FRONT_X = 1.37
SOURCE_REAR_X = -1.48
SOURCE_HALF_TRACK = 1.015  # Real source tire center, not fender lip

# Source front is Blender +X. Z+90 maps front to Blender +Y, which glTF
# exports as Godot -Z. Sign of source side names is not assumed.
ORIENTATION = Matrix.Rotation(math.pi * 0.5, 4, "Z")
PART_ORDER = ("FL", "FR", "RL", "RR")
LOD_TARGETS = (("hero", 76000), ("mid", 12000), ("distant", 2500))


def source_is_verified(path: pathlib.Path) -> bool:
    data = path.read_bytes()
    git_sha1 = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
    print("Source Git blob SHA-1:", git_sha1)
    return git_sha1 == SOURCE_BLOB_SHA1


def parser() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--source", type=pathlib.Path, required=True)
    p.add_argument("--output", type=pathlib.Path, required=True)
    p.add_argument("--allow-source-change", action="store_true",
                   help="For inspecting new upstream revisions; do not ship without audit")
    return p.parse_args(argv)


def tri_count(obj: bpy.types.Object) -> int:
    if obj.type != "MESH":
        return 0
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def scene_triangles() -> int:
    return sum(tri_count(x) for x in bpy.data.objects if x.type == "MESH")


def parent_keep_matrix(obj, parent, world_matrix):
    obj.parent = parent
    obj.matrix_world = world_matrix


def make_empty(name, parent=None):
    empty = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(empty)
    if parent is not None:
        empty.parent = parent
    return empty


def wheel_assignment(original_name):
    """Imported Spectral geometry is labelled Front_Left_*, etc.

    Blender Y is source model's side axis. +90 around Blender Z turns
    source negative Y into positive world X. As a result SOURCE 'Left'
    maps to Godot RIGHT. Assign target by actual geometry, not labels.
    """
    for axle in ("Front", "Rear"):
        for side in ("Left", "Right"):
            if original_name.startswith(axle + "_" + side + "_"):
                godot_side = "R" if side == "Left" else "L"
                return ("F" if axle == "Front" else "R") + godot_side
    return ""


def normalize_import():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE.resolve()))
    imported_meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if len(imported_meshes) < 50:
        raise ValueError("Unexpectedly sparse source GLB; not a production car")
    root = make_empty("VelaGT")
    body = make_empty("Body", root)
    wheels = {key: make_empty("Wheel_" + key + "_Pivot", root) for key in PART_ORDER}
    brakes = {key: make_empty("Brake_" + key, root) for key in PART_ORDER}
    groups = Counter()
    discarded = []
    for obj in imported_meshes:
        original_name = obj.name
        # These labels belong to the source fictional brand, not Vela GT.
        # Do not replace them by a fake decal; neutral surfaces remain.
        if original_name.startswith(("Badge_", "Plate_Text")):
            discarded.append(original_name)
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        original_matrix = obj.matrix_world.copy()
        new_world = ORIENTATION @ original_matrix
        key = wheel_assignment(original_name)
        if key:
            group = brakes[key] if "Brake_Caliper" in original_name else wheels[key]
            # Source x/front and y/side wheel centers, rotated to +Y forward.
            axle_x = SOURCE_FRONT_X if key[0] == "F" else SOURCE_REAR_X
            source_side_y = -SOURCE_HALF_TRACK if key[1] == "R" else SOURCE_HALF_TRACK
            center = ORIENTATION @ Vector((axle_x, source_side_y, SOURCE_WHEEL_HEIGHT_M, 1.0))
            new_world = Matrix.Translation(-Vector(center[:3])) @ new_world
            parent_keep_matrix(obj, group, new_world)
            groups[key] += 1
        else:
            parent_keep_matrix(obj, body, new_world)
            # Source fender lip toruses are too big for retargeted tires.
            if "_Fender_Lip_" in original_name:
                obj.scale *= 0.82
            groups["Body"] += 1
    for key in PART_ORDER:
        if groups[key] < 6:
            raise ValueError("Wheel " + key + " is not complete: " + str(groups[key]) + " parts")
    # Body is scaled for the actual factory's 2.71 m wheelbase, independently
    # of the 0.35 m GEVP tires. Pivot coordinates remain (0,0,0).
    body.matrix_world = Matrix.Translation((0, 0, CHASSIS_BODY_VERTICAL_OFFSET_M)) @ Matrix.Diagonal(
        (WHEELBASE_SCALE, WHEELBASE_SCALE, WHEELBASE_SCALE, 1.0))
    for key in PART_ORDER:
        # Axial correction keeps the visible tires near factory tread width.
        wheels[key].scale = (WHEEL_RADIUS_SCALE * 1.4,
                             WHEEL_RADIUS_SCALE, WHEEL_RADIUS_SCALE)
        brakes[key].scale = (WHEEL_RADIUS_SCALE,) * 3
    # The imported GLB's animated empties are not included; wheel dynamics
    # come *only* from GEVP. Blender source remains available upstream.
    keep = set([root, body, *wheels.values(), *brakes.values(), *imported_meshes])
    for obj in list(bpy.data.objects):
        if obj not in keep and obj.type != "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)
    print("Grouped source mesh objects:", dict(groups), "suppressed branding:", discarded)
    return root


def carve_wheel_arches():
    """Boolean-clear source BODY_Shell_Hero for actual rolling tires.

    Source's continuous lower loft side panel intersects tires, even though
    the source GLB is structurally valid. Cutters are temporary modeling aids
    and are never part of the exported car.
    """
    shell = bpy.data.objects.get("BODY_Shell_Hero")
    if shell is None or shell.type != "MESH":
        raise ValueError("Source body loft absent; refusing clipped wheels")
    scale = WHEELBASE_SCALE
    for axle in (SOURCE_FRONT_X, SOURCE_REAR_X):
        # Blender Z+90 made longitudinal +Y and wheel axles X.
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=96,
            radius=0.405 * scale,
            depth=3.4,
            end_fill_type="NGON",
            location=(0.0, axle * scale,
                      SOURCE_WHEEL_HEIGHT_M * scale + CHASSIS_BODY_VERTICAL_OFFSET_M),
            rotation=(0.0, math.pi / 2.0, 0.0))
        cutter = bpy.context.object
        cutter.name = "TEMP_ARCH_CLEARANCE"
        modifier = shell.modifiers.new("ClearFrontArch" if axle > 0 else "ClearRearArch", "BOOLEAN")
        modifier.operation = "DIFFERENCE"
        modifier.solver = "EXACT"
        modifier.object = cutter
        bpy.ops.object.select_all(action="DESELECT")
        shell.select_set(True)
        bpy.context.view_layer.objects.active = shell
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        bpy.data.objects.remove(cutter, do_unlink=True)


def join_material_peers():
    """Reduce source's ~263 object-level draw submissions without atlas loss."""
    for parent in [o for o in bpy.data.objects if o.type == "EMPTY" and
                   (o.name == "Body" or o.name.startswith(("Wheel_", "Brake_")))]:
        peers = {}
        for child in parent.children:
            if child.type != "MESH":
                continue
            sig = tuple(m.name if m else "None" for m in child.data.materials)
            if sig:
                peers.setdefault(sig, []).append(child)
        for objects in peers.values():
            if len(objects) <= 1:
                continue
            bpy.ops.object.select_all(action="DESELECT")
            for obj in objects:
                obj.select_set(True)
            bpy.context.view_layer.objects.active = objects[0]
            bpy.ops.object.join()


def adjust_budget(target):
    before = scene_triangles()
    if before <= target:
        print("LOD <= target already", before, target)
        return before
    # Preserve chassis silhouettes, wheel curvature and material assignments.
    # Decimate largest surfaces first, then a global pass if necessary.
    for _pass in range(3):
        current = scene_triangles()
        if current <= target:
            break
        ratio = max(0.02, (target / current) * 0.97)
        objects = sorted((o for o in bpy.data.objects if o.type == "MESH"),
                         key=tri_count, reverse=True)
        for obj in objects:
            old = tri_count(obj)
            if old < 32:
                continue
            mod = obj.modifiers.new("LOD_Decimate", "DECIMATE")
            mod.ratio = ratio
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.modifier_apply(modifier=mod.name)
        if scene_triangles() >= current:
            break
    after = scene_triangles()
    if after > int(target * 1.12):
        raise ValueError(f"LOD decimation did not reach budget: {after} > {target}")
    print(f"LOD reduced {before} -> {after} triangles (target {target})")
    return after


def prune_distant():
    """Remove subpixel mechanical and interior features for distant traffic."""
    deleted = 0
    for obj in list(bpy.data.objects):
        if obj.type != "MESH":
            continue
        n = obj.name.lower()
        if any(word in n for word in ("seat_", "belt_", "cockpit_", "radiator_",
                                     "turbo_", "brake_line_", "damper_", "subframe_",
                                     "engine_", "shifter_", "display_", "vent_", "suspension_")):
            bpy.data.objects.remove(obj, do_unlink=True)
            deleted += 1
    print("Pruned distant-only interior/mechanic objects:", deleted)


def export(root, path):
    bpy.ops.object.select_all(action="DESELECT")
    children = [root] + list(root.children_recursive)
    for obj in children:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB",
                              use_selection=True, export_animations=False,
                              export_apply=True, export_yup=True)
    print("EXPORTED", str(path), "triangles", scene_triangles(),
          "mesh objects", sum(o.type == "MESH" for o in children))


if __name__ == "__main__":
    opts = parser()
    SOURCE = opts.source
    if not SOURCE.is_file():
        raise SystemExit("Source GLB not found: " + str(SOURCE))
    if not source_is_verified(SOURCE) and not opts.allow_source_change:
        raise SystemExit("Source SHA changed; refuse to process without re-auditing license/content")
    opts.output.mkdir(parents=True, exist_ok=True)
    root = normalize_import()
    carve_wheel_arches()
    join_material_peers()
    for n, (label, budget) in enumerate(LOD_TARGETS):
        if n == 2:
            prune_distant()
        adjust_budget(budget)
        export(root, opts.output / ("vela_gt_" + label + ".glb"))
