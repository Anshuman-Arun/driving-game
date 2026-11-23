"""Inspect bounding boxes and triangle counts of existing scenery models via Blender."""
import json
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(r"c:\Users\anshu\Documents\Coding\Driving-Game\driving-game")
MANIFEST = json.loads((ROOT / "content" / "scenery" / "manifest.json").read_text(encoding="utf-8"))

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def inspect_file(rel_path: str):
    clear_scene()
    full_path = ROOT / rel_path
    if not full_path.exists():
        return {"error": "missing"}
    bpy.ops.import_scene.gltf(filepath=str(full_path))
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    tris = 0
    meshes = 0
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            meshes += 1
            deps = bpy.context.evaluated_depsgraph_get()
            eval_obj = obj.evaluated_get(deps)
            mesh = eval_obj.to_mesh()
            mesh.calc_loop_triangles()
            tris += len(mesh.loop_triangles)
            for v in mesh.vertices:
                w = obj.matrix_world @ v.co
                mins.x = min(mins.x, w.x)
                mins.y = min(mins.y, w.y)
                mins.z = min(mins.z, w.z)
                maxs.x = max(maxs.x, w.x)
                maxs.y = max(maxs.y, w.y)
                maxs.z = max(maxs.z, w.z)
            eval_obj.to_mesh_clear()
    # Note: Blender uses Z-up internally; glTF importer converts +Y up -> +Z up in Blender!
    return {
        "meshes": meshes,
        "tris": tris,
        "blender_x": [round(mins.x, 3), round(maxs.x, 3)],
        "blender_y_depth": [round(mins.y, 3), round(maxs.y, 3)],
        "blender_z_up": [round(mins.z, 3), round(maxs.z, 3)],
    }

def main():
    results = {}
    for key, entry in MANIFEST["assets"].items():
        results[key] = inspect_file(entry["path"])
        results[key]["manifest_r"] = entry["r"]
        if "lod" in entry:
            results[f"{key}_lod"] = inspect_file(entry["lod"])
    print("INSPECT_RESULTS_START")
    print(json.dumps(results, indent=2))
    print("INSPECT_RESULTS_END")

if __name__ == "__main__":
    main()
