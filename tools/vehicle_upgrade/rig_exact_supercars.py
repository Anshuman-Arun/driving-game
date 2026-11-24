"""Build the Godot wheel-pivot contract from the supplied Aventador and Senna meshes.

Run with Blender's Python module and pass the original ZIP, GLB, and output folder.
The original files are read only. All translations are in meters.
"""

import argparse
import math
import tempfile
import zipfile
from collections import defaultdict
from pathlib import Path, PurePosixPath

import bpy
import bmesh
from mathutils import Matrix, Vector


YAW = Matrix.Rotation(math.pi, 4, "Z")
CORNERS = ("FL", "FR", "RL", "RR")


def corner(point):
    # Source geometry faces -Y in Blender. Rotate before exporting -Z-forward glTF.
    return ("F" if point.y < 0 else "R") + ("L" if point.x > 0 else "R")


def empty(name, parent=None, position=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    if position is not None:
        obj.location = position
    return obj


def subset(mesh, keep):
    result = mesh.copy()
    edit = bmesh.new()
    edit.from_mesh(result)
    bmesh.ops.delete(edit, geom=[face for face in edit.faces if not keep(face)], context="FACES_ONLY")
    bmesh.ops.delete(edit, geom=[vert for vert in edit.verts if not vert.link_faces], context="VERTS")
    edit.to_mesh(result)
    edit.free()
    return result


def pieces(source, mode):
    """Partition evaluated geometry while retaining UVs and per-face materials."""
    mesh = bpy.data.meshes.new_from_object(source.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    mesh.transform(source.matrix_world)
    if mode == "aventador":
        if source.name in {"Tires", "Wheels", "Brake disk new", "Brake"}:
            kind = {"Tires": "tire", "Wheels": "spin", "Brake disk new": "spin", "Brake": "brake"}[source.name]
            for side in CORNERS:
                yield (kind, side), subset(mesh, lambda face: corner(face.calc_center_median()) == side)
            return
        for kind, material_name in [("Headlight", "Front Light"), ("Taillight", "Red Lights")]:
            slot = next((i for i, mat in enumerate(mesh.materials) if mat and mat.name == material_name), -1)
            if source.name == kind + "s" and slot >= 0:
                yield (kind, ""), subset(mesh, lambda face: face.material_index == slot)
                yield ("body", ""), subset(mesh, lambda face: face.material_index != slot)
                return
    else:
        parent = source.parent.name if source.parent else ""
        center = sum((vert.co for vert in mesh.vertices), Vector()) / max(len(mesh.vertices), 1)
        if parent.startswith("Object_4.") and "Scene_-_Root" in source.name:
            yield ("tire", corner(center)), mesh
            return
        if parent.startswith(("euansenna_wheel1paint", "amdb11_brakedisc_")):
            kind = "brake" if "caliper" in source.name.lower() else "spin"
            yield (kind, corner(center)), mesh
            return
        if parent == "euansenna_steer":
            yield ("steer", ""), mesh
            return
        if parent.startswith(("euansenna_headlight_L", "euansenna_headlight_R")) and source.name.endswith("_euansenna_headlight_0"):
            yield ("Headlight", ""), mesh
            return
        if parent == "euansenna_flank_hardtop" and "_taillight_" in source.name:
            yield ("Taillight", ""), mesh
            return
    yield ("body", ""), mesh


def join_group(meshes, name, parent, correction, center=Vector((0, 0, 0))):
    selected = []
    for mesh in meshes:
        if not mesh.polygons:
            continue
        mesh.transform(Matrix.Translation(-center) @ correction)
        mesh.update()
        obj = bpy.data.objects.new("Part", mesh)
        bpy.context.collection.objects.link(obj)
        obj.parent = parent
        selected.append(obj)
    if not selected:
        return
    bpy.ops.object.select_all(action="DESELECT")
    for obj in selected:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = selected[0]
    if len(selected) > 1:
        bpy.ops.object.join()
    selected[0].name = name


def bounds(meshes):
    points = [v.co for mesh in meshes for v in mesh.vertices]
    return (
        Vector(min(v[i] for v in points) for i in range(3)),
        Vector(max(v[i] for v in points) for i in range(3)),
    )


def configure_materials(mode):
    """Use named paint and glazing surfaces while preserving original PBR maps."""
    paint_name = "Body" if mode == "aventador" else "sennapaintmain"
    glass_names = ("Window Glass",) if mode == "aventador" else ("senna_glass", "senna_glass.001")
    for name in (paint_name, *glass_names):
        mat = bpy.data.materials.get(name)
        if mat is None:
            continue
        if name == paint_name:
            mat.name = "CarPaint"
        else:
            mat.name = "CabinGlass" if name == glass_names[0] else "CabinGlassInset"
            for node in mat.node_tree.nodes:
                if node.type == "BSDF_PRINCIPLED":
                    node.inputs["Roughness"].default_value = 0.18


def split_lamp_material(meshes, kind):
    lamp = bpy.data.materials.new(kind + "Emitter")
    lamp.use_nodes = True
    node = lamp.node_tree.nodes.get("Principled BSDF")
    color = (0.72, 0.87, 1.0, 1.0) if kind == "Headlight" else (0.62, 0.009, 0.013, 1.0)
    node.inputs["Base Color"].default_value = color
    node.inputs["Emission Color"].default_value = color
    node.inputs["Emission Strength"].default_value = 0.32
    for mesh in meshes:
        mesh.materials.clear()
        mesh.materials.append(lamp)


def rig(mode, output):
    original = list(bpy.context.scene.objects)
    parts = defaultdict(list)
    for obj in original:
        if obj.type != "MESH" or obj.hide_render:
            continue
        if mode == "senna" and obj.parent and obj.parent.name == "euansenna_seat_FL_stig":
            # The download includes an alternate driver's seat on top of its regular seat.
            continue
        for key, mesh in pieces(obj, mode):
            if mesh.polygons:
                parts[key].append(mesh)

    tire_boxes = {side: bounds(parts["tire", side]) for side in CORNERS}
    centers = {side: (lo + hi) * 0.5 for side, (lo, hi) in tire_boxes.items()}
    origin = sum(centers.values(), Vector()) / len(CORNERS)
    origin.z = min(lo.z for lo, _ in tire_boxes.values())
    correction = YAW @ Matrix.Translation(-origin)

    configure_materials(mode)
    for obj in original:
        bpy.data.objects.remove(obj, do_unlink=True)
    root = empty("AssetRoot")
    join_group(parts["body", ""], "Body_Shell", root, correction)
    for kind in ("Headlight", "Taillight"):
        meshes = parts[kind, ""]
        if meshes:
            split_lamp_material(meshes, kind)
            join_group(meshes, kind + "Emitters", root, correction)
    steering = parts["steer", ""]
    if steering:
        lo, hi = bounds(steering)
        at = correction @ ((lo + hi) * 0.5)
        join_group(steering, "SteeringRim", empty("SteeringWheel", root, at), correction, at)
    for side in CORNERS:
        at = correction @ centers[side]
        pivot = empty(f"Wheel_{side}_Pivot", root, at)
        brake = empty(f"Brake_{side}", root, at)
        join_group(parts["tire", side], f"Tire_{side}", pivot, correction, at)
        join_group(parts["spin", side], f"Rim_{side}", pivot, correction, at)
        join_group(parts["brake", side], f"Caliper_{side}", brake, correction, at)
        print(mode, side, tuple(round(value, 4) for value in (at.x, at.z, -at.y)), flush=True)

    bpy.ops.export_scene.gltf(
        filepath=str(output), export_format="GLB", export_apply=False,
        export_animations=False, export_cameras=False, export_lights=False,
        export_image_format="AUTO",
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("aventador", type=Path)
    parser.add_argument("senna", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as scratch, zipfile.ZipFile(args.aventador) as archive:
        for filename in archive.namelist():
            path = PurePosixPath(filename)
            if path.parts and path.parts[0] in {"source", "textures"} and ".." not in path.parts:
                archive.extract(filename, scratch)
        bpy.ops.wm.open_mainfile(filepath=str(Path(scratch) / "source/Lamborghini.blend"), load_ui=False, use_scripts=False)
        rig("aventador", args.output / "aventador_svj.glb")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.senna))
    rig("senna", args.output / "mclaren_senna.glb")


if __name__ == "__main__":
    main()
