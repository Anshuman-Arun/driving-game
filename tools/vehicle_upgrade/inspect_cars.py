import bpy
import os
import sys
from mathutils import Vector

def inspect_glb(filepath):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    print(f"\n==================== INSPECTING: {os.path.basename(filepath)} ====================")
    bpy.ops.import_scene.gltf(filepath=filepath)
    
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    total_tris = 0
    min_co = Vector((1e9, 1e9, 1e9))
    max_co = Vector((-1e9, -1e9, -1e9))
    
    print(f"Total Objects: {len(bpy.data.objects)}, Meshes: {len(meshes)}, Materials: {len(bpy.data.materials)}")
    for obj in meshes:
        mesh = obj.data
        mesh.calc_loop_triangles()
        tris = len(mesh.loop_triangles)
        total_tris += tris
        
        bbox_corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
        omin = Vector((min(v.x for v in bbox_corners), min(v.y for v in bbox_corners), min(v.z for v in bbox_corners)))
        omax = Vector((max(v.x for v in bbox_corners), max(v.y for v in bbox_corners), max(v.z for v in bbox_corners)))
        for i in range(3):
            min_co[i] = min(min_co[i], omin[i])
            max_co[i] = max(max_co[i], omax[i])
        size = omax - omin
        center = (omin + omax) * 0.5
        mats = [m.name if m else "None" for m in obj.data.materials]
        if tris >= 50 or "wheel" in obj.name.lower() or "tire" in obj.name.lower() or "rim" in obj.name.lower() or "brake" in obj.name.lower() or "caliper" in obj.name.lower() or "steer" in obj.name.lower() or "glass" in obj.name.lower() or "light" in obj.name.lower():
            print(f"  Mesh '{obj.name}' (parent={obj.parent.name if obj.parent else None}): tris={tris}, center=({center.x:.2f},{center.y:.2f},{center.z:.2f}), size=({size.x:.2f},{size.y:.2f},{size.z:.2f}), mats={mats[:3]}")
            
    total_size = max_co - min_co
    print(f"TOTAL TRIS: {total_tris}")
    print(f"WORLD BBOX: min=({min_co.x:.3f}, {min_co.y:.3f}, {min_co.z:.3f}) max=({max_co.x:.3f}, {max_co.y:.3f}, {max_co.z:.3f})")
    print(f"WORLD SIZE: X={total_size.x:.3f}, Y={total_size.y:.3f}, Z={total_size.z:.3f}")
    print("MATERIALS:", [m.name for m in bpy.data.materials])

if __name__ == "__main__":
    argv = sys.argv
    if "--" in argv:
        files = argv[argv.index("--") + 1:]
        for f in files:
            inspect_glb(f)
