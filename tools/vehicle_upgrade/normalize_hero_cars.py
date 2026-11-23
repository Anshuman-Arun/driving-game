"""
Normalize & rig 3 Forza-caliber sports cars into Godot-ready GLBs:
  - vela_gt.glb   : Porsche 911 (Sleek RWD German Sports Coupe / Grand Tourer)
  - orion_rs.glb  : Khronos CarConcept (Nimble Lightweight Sports Coupe / Track Car)
  - kestrel_xr.glb: Ferrari 458 Italia (Flagship AWD Exotic Supercar)

Contract guaranteed for every exported GLB (Godot +Y up, -Z forward, +X right):
  AssetRoot
   ├── Body_Shell (MeshInstance3D, clearcoat hero paint)
   ├── Body_Trim (MeshInstance3D, matte/satin trim, carbon, chrome, vents)
   ├── Body_Interior (MeshInstance3D, dark cabin, seats, dash)
   ├── Body_Glass (MeshInstance3D, glossy tinted transparent glass, alpha < 0.40)
   ├── Headlight_Main (MeshInstance3D, emissive-ready warm white lenses)
   ├── Taillight_Main (MeshInstance3D, emissive-ready ruby red lenses)
   ├── Reverselight_Main (MeshInstance3D, emissive-ready white reverse lenses)
   ├── SteeringWheel (MeshInstance3D, pivoted at steering column center)
   ├── Brake_FL / Brake_FR / Brake_RL / Brake_RR (MeshInstance3D, origin at wheel center)
   └── Wheel_{FL,FR,RL,RR}_Pivot (Empty at exact wheel center)
        └── Tire_{FL,FR,RL,RR} (MeshInstance3D at local 0,0,0; multi-mat tire+rim+rotor)
"""

import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector, Matrix, Euler

RAW_DIR = r"c:\Users\anshu\Documents\Coding\Driving-Game\driving-game\assets\forza_cars"
OUT_DIR = r"c:\Users\anshu\Documents\Coding\Driving-Game\driving-game\assets\curated\models\vehicles"

TARGET_WHEELBASE = 2.71
TARGET_TIRE_RADIUS = 0.355


# ---------------------------------------------------------------------------
# Material builders (glTF 2.0 PBR + Clearcoat + Alpha Blend)
# ---------------------------------------------------------------------------
def make_pbr_material(name, base_color, metallic=0.0, roughness=0.5,
                      coat_weight=0.0, coat_roughness=0.05,
                      alpha=1.0, emission=None, emission_strength=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    bsdf.inputs["Base Color"].default_value = (*base_color[:3], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat_weight
    if "Coat Roughness" in bsdf.inputs:
        bsdf.inputs["Coat Roughness"].default_value = coat_roughness
    bsdf.inputs["Alpha"].default_value = alpha
    if alpha < 0.99:
        mat.blend_method = 'BLEND' if hasattr(mat, 'blend_method') else 'HASHED'
    if emission is not None and emission_strength > 0.0:
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (*emission[:3], 1.0)
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def create_material_palette(paint_rgb, caliper_rgb, rim_rgb=(0.76, 0.79, 0.83)):
    return {
        "paint": make_pbr_material("CarPaint_Hero", paint_rgb, metallic=0.78, roughness=0.15, coat_weight=1.0, coat_roughness=0.03),
        "paint_accent": make_pbr_material("CarPaint_Accent", (0.04, 0.045, 0.055), metallic=0.35, roughness=0.22, coat_weight=0.8, coat_roughness=0.06),
        "carbon": make_pbr_material("Carbon_Fiber", (0.045, 0.048, 0.052), metallic=0.25, roughness=0.28, coat_weight=0.7, coat_roughness=0.08),
        "chrome": make_pbr_material("Chrome_Trim", (0.90, 0.92, 0.95), metallic=0.98, roughness=0.07),
        "plastic_dark": make_pbr_material("Trim_Dark", (0.03, 0.032, 0.036), metallic=0.05, roughness=0.58),
        "interior": make_pbr_material("Interior_Dark", (0.05, 0.052, 0.058), metallic=0.0, roughness=0.72),
        "interior_leather": make_pbr_material("Interior_Leather", (0.09, 0.075, 0.07), metallic=0.0, roughness=0.55),
        "glass": make_pbr_material("Glass_Tinted", (0.04, 0.065, 0.085), metallic=0.08, roughness=0.05, coat_weight=1.0, coat_roughness=0.02, alpha=0.34),
        "tire": make_pbr_material("Tire_Rubber", (0.032, 0.034, 0.038), metallic=0.0, roughness=0.86),
        "rim": make_pbr_material("Alloy_Rim", rim_rgb, metallic=0.94, roughness=0.18),
        "rotor": make_pbr_material("Brake_Rotor", (0.58, 0.60, 0.63), metallic=0.92, roughness=0.28),
        "caliper": make_pbr_material("Brake_Caliper", caliper_rgb, metallic=0.45, roughness=0.24, coat_weight=0.8, coat_roughness=0.05),
        "headlight": make_pbr_material("Headlight_Emissive", (0.95, 0.96, 1.0), metallic=0.1, roughness=0.08, emission=(0.98, 0.96, 0.88), emission_strength=2.2),
        "taillight": make_pbr_material("Taillight_Emissive", (0.72, 0.04, 0.04), metallic=0.1, roughness=0.12, emission=(0.95, 0.06, 0.04), emission_strength=1.4),
        "reverselight": make_pbr_material("Reverselight_Emissive", (0.85, 0.87, 0.90), metallic=0.1, roughness=0.12, emission=(0.95, 0.97, 1.0), emission_strength=0.15),
    }


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------
def world_bbox(objs):
    min_co = Vector((1e9, 1e9, 1e9))
    max_co = Vector((-1e9, -1e9, -1e9))
    for obj in objs:
        if obj.type != 'MESH' or len(obj.data.vertices) == 0:
            continue
        mw = obj.matrix_world
        for corner in obj.bound_box:
            v = mw @ Vector(corner)
            for i in range(3):
                min_co[i] = min(min_co[i], v[i])
                max_co[i] = max(max_co[i], v[i])
    return min_co, max_co


def apply_all_transforms_to_meshes(objs):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objs:
        if obj.type != 'MESH':
            continue
        # Bake world matrix directly into mesh data and reset object transform
        mw = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
        obj.data = obj.data.copy()
        obj.data.transform(mw)
        if mw.determinant() < 0:
            bm = bmesh.new()
            bm.from_mesh(obj.data)
            bmesh.ops.reverse_faces(bm, faces=bm.faces)
            bm.to_mesh(obj.data)
            bm.free()
        obj.data.update()


def transform_mesh_objs(objs, mat):
    for obj in objs:
        if obj.type == 'MESH':
            obj.data.transform(mat)
            obj.data.update()


def decimate_object(obj, target_tris):
    if obj is None or obj.type != 'MESH':
        return
    obj.data.calc_loop_triangles()
    cur = len(obj.data.loop_triangles)
    if cur <= target_tris or cur < 64:
        return
    ratio = max(0.05, min(1.0, float(target_tris) / float(cur)))
    mod = obj.modifiers.new(name="Decimate", type='DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.ratio = ratio
    mod.use_collapse_triangulate = False
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


def smooth_shade_mesh(obj):
    if obj is None or obj.type != 'MESH' or len(obj.data.polygons) == 0:
        return
    mesh = obj.data
    # Remove custom split normals that may look faceted after decimation
    if mesh.has_custom_normals:
        bpy.context.view_layer.objects.active = obj
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    vals = [True] * len(mesh.polygons)
    mesh.polygons.foreach_set("use_smooth", vals)
    mesh.update()


def join_objects(objs, name, default_mat=None):
    valid = [o for o in objs if o is not None and o.type == 'MESH' and len(o.data.vertices) > 0]
    if not valid:
        # Create tiny placeholder so required node exists
        mesh = bpy.data.meshes.new(name)
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        if default_mat:
            obj.data.materials.append(default_mat)
        return obj
    if default_mat is not None:
        for o in valid:
            if len(o.data.materials) == 0:
                o.data.materials.append(default_mat)
    bpy.ops.object.select_all(action='DESELECT')
    for o in valid:
        o.select_set(True)
    bpy.context.view_layer.objects.active = valid[0]
    if len(valid) > 1:
        bpy.ops.object.join()
    res = bpy.context.view_layer.objects.active
    res.name = name
    res.data.name = name + "_Mesh"
    return res


def override_all_materials(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.material_index = 0


def split_mesh_by_x(obj, x_threshold=0.0):
    """Split a baked world-space mesh into left (x < threshold) and right (x >= threshold)."""
    left_mesh = obj.data.copy()
    right_mesh = obj.data.copy()

    for m, keep_left in ((left_mesh, True), (right_mesh, False)):
        bm = bmesh.new()
        bm.from_mesh(m)
        to_del = []
        for f in bm.faces:
            cx = f.calc_center_median().x
            if (keep_left and cx >= x_threshold) or (not keep_left and cx < x_threshold):
                to_del.append(f)
        bmesh.ops.delete(bm, geom=to_del, context='FACES')
        bm.to_mesh(m)
        bm.free()

    left_obj = bpy.data.objects.new(obj.name + "_L", left_mesh)
    right_obj = bpy.data.objects.new(obj.name + "_R", right_mesh)
    bpy.context.collection.objects.link(left_obj)
    bpy.context.collection.objects.link(right_obj)
    bpy.data.objects.remove(obj, do_unlink=True)
    return left_obj, right_obj


def create_box_mesh(name, size, center, mat):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def create_sculpted_caliper(name, wheel_center, is_left, is_front, mat):
    """Create a realistic curved brake caliper hugging the brake rotor, with object origin at wheel_center."""
    bm = bmesh.new()
    # Arc on rotor (facing rearwards on front wheels, forwards on rear wheels)
    sign_y = -1.0 if is_front else 1.0
    sign_x = -1.0 if is_left else 1.0
    r_inner = 0.145
    r_outer = 0.215
    width = 0.085
    steps = 8
    arc_start = -0.45
    arc_end = 0.55

    verts_in_l, verts_in_r, verts_out_l, verts_out_r = [], [], [], []
    for i in range(steps + 1):
        t = arc_start + (arc_end - arc_start) * (i / steps)
        cy = sign_y * math.cos(t)
        cz = math.sin(t)
        x_in = -sign_x * (width * 0.45) - sign_x * 0.03
        x_out = sign_x * (width * 0.55) - sign_x * 0.03
        verts_in_l.append(bm.verts.new((x_in, cy * r_inner, cz * r_inner)))
        verts_in_r.append(bm.verts.new((x_out, cy * r_inner, cz * r_inner)))
        verts_out_l.append(bm.verts.new((x_in, cy * r_outer, cz * r_outer)))
        verts_out_r.append(bm.verts.new((x_out, cy * r_outer, cz * r_outer)))

    for i in range(steps):
        bm.faces.new((verts_in_l[i], verts_in_l[i+1], verts_out_l[i+1], verts_out_l[i]))
        bm.faces.new((verts_in_r[i+1], verts_in_r[i], verts_out_r[i], verts_out_r[i+1]))
        bm.faces.new((verts_out_l[i], verts_out_l[i+1], verts_out_r[i+1], verts_out_r[i]))
        bm.faces.new((verts_in_r[i], verts_in_r[i+1], verts_in_l[i+1], verts_in_l[i]))
    bm.faces.new((verts_in_l[0], verts_out_l[0], verts_out_r[0], verts_in_r[0]))
    bm.faces.new((verts_in_r[-1], verts_out_r[-1], verts_out_l[-1], verts_in_l[-1]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = wheel_center
    obj.data.materials.append(mat)
    smooth_shade_mesh(obj)
    return obj


def build_final_rig(out_path, body_shell, body_trim, body_interior, body_glass,
                    headlight, taillight, reverselight, steering_wheel,
                    wheels_dict, calipers_dict, target_total_tris=75000):
    """
    Assemble AssetRoot hierarchy, decimate cleanly to target budget, smooth shade,
    and export Godot-ready GLB.
    wheels_dict: {'FL': (center_vec, mesh_obj), ...}
    calipers_dict: {'FL': (center_vec, mesh_obj), ...}
    """
    # Create AssetRoot
    root = bpy.data.objects.new("AssetRoot", None)
    bpy.context.collection.objects.link(root)

    # Decimate budget allocation
    # Body_Shell gets generous tris for silky smooth curves!
    decimate_object(body_shell, 28000)
    decimate_object(body_trim, 14000)
    decimate_object(body_interior, 8000)
    decimate_object(body_glass, 3000)
    decimate_object(headlight, 1500)
    decimate_object(taillight, 1500)
    decimate_object(reverselight, 500)
    if steering_wheel:
        decimate_object(steering_wheel, 2000)

    for corner in ("FL", "FR", "RL", "RR"):
        _, w_obj = wheels_dict[corner]
        decimate_object(w_obj, 4500)
        if corner in calipers_dict and calipers_dict[corner][1] is not None:
            decimate_object(calipers_dict[corner][1], 600)

    # Smooth shade all body and wheel meshes
    for obj in (body_shell, body_trim, body_interior, body_glass, headlight, taillight, reverselight, steering_wheel):
        if obj is not None:
            smooth_shade_mesh(obj)
            obj.parent = root

    # Center SteeringWheel pivot at its own bounding box center so local rotation works cleanly
    if steering_wheel is not None and len(steering_wheel.data.vertices) > 0:
        smin, smax = world_bbox([steering_wheel])
        scenter = (smin + smax) * 0.5
        steering_wheel.data.transform(Matrix.Translation(-scenter))
        steering_wheel.location = scenter
        steering_wheel.data.update()

    # Rig wheels: Wheel_{CORNER}_Pivot at exact center, Tire_{CORNER} at local (0,0,0)
    for corner in ("FL", "FR", "RL", "RR"):
        center, w_obj = wheels_dict[corner]
        pivot = bpy.data.objects.new(f"Wheel_{corner}_Pivot", None)
        bpy.context.collection.objects.link(pivot)
        pivot.parent = root
        pivot.location = center

        # Shift mesh vertices so local origin is (0,0,0)
        w_obj.name = f"Tire_{corner}"
        w_obj.data.name = f"Tire_{corner}_Mesh"
        w_obj.data.transform(Matrix.Translation(-center))
        w_obj.location = Vector((0.0, 0.0, 0.0))
        w_obj.parent = pivot
        smooth_shade_mesh(w_obj)

        # Rig static Brake_{CORNER} caliper as sibling of Body_Shell with origin at wheel center
        if corner in calipers_dict and calipers_dict[corner][1] is not None:
            c_center, c_obj = calipers_dict[corner]
            c_obj.name = f"Brake_{corner}"
            c_obj.data.name = f"Brake_{corner}_Mesh"
            # If caliper vertices are in world space, shift by -center; if already local, keep
            if c_obj.location.length < 1e-4:
                c_obj.data.transform(Matrix.Translation(-center))
                c_obj.location = center
            c_obj.parent = root
            smooth_shade_mesh(c_obj)

    # Remove any orphan objects not parented to root (and not root itself)
    keep = {root}
    def collect(o):
        for ch in o.children:
            keep.add(ch)
            collect(ch)
    collect(root)
    for o in list(bpy.data.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)

    # Report stats
    total_tris = 0
    for o in keep:
        if o.type == 'MESH':
            o.data.calc_loop_triangles()
            total_tris += len(o.data.loop_triangles)
    min_co, max_co = world_bbox([o for o in keep if o.type == 'MESH'])
    sz = max_co - min_co
    print(f"EXPORTING {os.path.basename(out_path)}: tris={total_tris}, size=(X={sz.x:.3f}, Y={sz.y:.3f}, Z={sz.z:.3f}), minZ={min_co.z:.4f}")
    for corner in ("FL", "FR", "RL", "RR"):
        p = bpy.data.objects[f"Wheel_{corner}_Pivot"]
        t = bpy.data.objects[f"Tire_{corner}"]
        tmin, tmax = world_bbox([t])
        tsz = tmax - tmin
        print(f"  Wheel_{corner}_Pivot: loc=({p.location.x:.3f}, {p.location.y:.3f}, {p.location.z:.3f}), tire_dia_Z={tsz.z:.3f}")

    # Export GLB (Blender +Y fwd, +Z up -> glTF/Godot -Z fwd, +Y up)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format='GLB',
        export_yup=True,
        export_apply=False,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT',
        export_cameras=False,
        export_lights=False,
    )
    print(f"  Saved {out_path} ({os.path.getsize(out_path) / (1024*1024):.2f} MB)")


# ---------------------------------------------------------------------------
# Car 1: KESTREL XR — Ferrari 458 Italia (mrdoob/three.js)
# ---------------------------------------------------------------------------
def build_kestrel_xr():
    print("\n================ BUILDING kestrel_xr.glb (Ferrari 458 Italia) ================")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(RAW_DIR, "ferrari.glb"))

    pal = create_material_palette(
        paint_rgb=(0.72, 0.045, 0.065),      # Rosso Corsa Metallic
        caliper_rgb=(0.95, 0.72, 0.04),      # Giallo Modena Yellow calipers
        rim_rgb=(0.72, 0.75, 0.80),          # Satin Titanium Alloy
    )

    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    # Record parent names BEFORE baking transforms
    parent_map = {o.name: (o.parent.name if o.parent else "") for o in meshes}
    apply_all_transforms_to_meshes(meshes)

    # Already +Y forward, +Z up! Compute raw wheel centers from wheel_fl/fr/rl/rr tires
    wheel_groups = {"FL": [], "FR": [], "RL": [], "RR": []}
    for o in meshes:
        pname = parent_map[o.name].lower()
        if pname == "wheel_fl":
            wheel_groups["FL"].append(o)
        elif pname == "wheel_fr":
            wheel_groups["FR"].append(o)
        elif pname == "wheel_rl":
            wheel_groups["RL"].append(o)
        elif pname == "wheel_rr":
            wheel_groups["RR"].append(o)

    def group_center(objs):
        mn, mx = world_bbox(objs)
        return (mn + mx) * 0.5, mn, mx

    fl_c, fl_mn, fl_mx = group_center(wheel_groups["FL"])
    fr_c, _, _ = group_center(wheel_groups["FR"])
    rl_c, _, _ = group_center(wheel_groups["RL"])
    rr_c, _, _ = group_center(wheel_groups["RR"])

    raw_wb = ((fl_c.y + fr_c.y) * 0.5) - ((rl_c.y + rr_c.y) * 0.5)
    scale = TARGET_WHEELBASE / raw_wb
    mid_x = (fl_c.x + fr_c.x + rl_c.x + rr_c.x) * 0.25
    mid_y = (fl_c.y + fr_c.y + rl_c.y + rr_c.y) * 0.25
    min_z = min(world_bbox(wheel_groups[k])[0].z for k in wheel_groups)

    # Uniform scale + ground to Z=0 + center X=0, wheelbase midpoint Y=0
    xform = Matrix.Scale(scale, 4) @ Matrix.Translation(Vector((-mid_x, -mid_y, -min_z)))
    transform_mesh_objs(meshes, xform)

    # Classify body meshes and apply clean PBR materials
    shell_objs, trim_objs, interior_objs, glass_objs = [], [], [], []
    head_objs, tail_objs, steer_objs = [], [], []

    for o in meshes:
        pname = parent_map[o.name].lower()
        lname = o.name.lower()
        if pname.startswith("wheel_"):
            if "tire" in lname:
                override_all_materials(o, pal["tire"])
            elif "brake" in lname:
                override_all_materials(o, pal["rotor"])
            elif "nuts" in lname:
                override_all_materials(o, pal["plastic_dark"])
            elif "centre" in lname:
                override_all_materials(o, pal["caliper"])
            else:
                override_all_materials(o, pal["rim"])
            continue
        if pname == "steering_wheel":
            if "carbon" in lname:
                override_all_materials(o, pal["carbon"])
            elif "centre" in lname:
                override_all_materials(o, pal["caliper"])
            elif "red" in lname or "trim" in lname:
                override_all_materials(o, pal["paint"])
            else:
                override_all_materials(o, pal["interior_leather"])
            steer_objs.append(o)
            continue

        if lname == "body":
            override_all_materials(o, pal["paint"])
            shell_objs.append(o)
        elif lname == "glass":
            override_all_materials(o, pal["glass"])
            glass_objs.append(o)
        elif lname in ("lights", "leds"):
            override_all_materials(o, pal["headlight"])
            head_objs.append(o)
        elif lname in ("brakes", "lights_red"):
            override_all_materials(o, pal["taillight"])
            tail_objs.append(o)
        elif lname in ("leather", "carpet", "interior_dark", "interior_light", "trim", "blue"):
            override_all_materials(o, pal["interior_leather"] if "leather" in lname else pal["interior"])
            interior_objs.append(o)
        else:
            if "chrome" in lname:
                override_all_materials(o, pal["chrome"])
            elif "carbon" in lname:
                override_all_materials(o, pal["carbon"])
            elif "yellow" in lname:
                override_all_materials(o, pal["caliper"])
            else:
                override_all_materials(o, pal["plastic_dark"])
            trim_objs.append(o)

    body_shell = join_objects(shell_objs, "Body_Shell", pal["paint"])
    body_trim = join_objects(trim_objs, "Body_Trim", pal["plastic_dark"])
    body_interior = join_objects(interior_objs, "Body_Interior", pal["interior"])
    body_glass = join_objects(glass_objs, "Body_Glass", pal["glass"])
    headlight = join_objects(head_objs, "Headlight_Main", pal["headlight"])
    taillight = join_objects(tail_objs, "Taillight_Main", pal["taillight"])
    steering_wheel = join_objects(steer_objs, "SteeringWheel", pal["interior_leather"])

    # Clean reverse lamp inserts tucked into rear fascia
    bmin, bmax = world_bbox([body_shell])
    rev_l = create_box_mesh("RevL", (0.14, 0.04, 0.045), (-0.42, bmin.y + 0.10, 0.62), pal["reverselight"])
    rev_r = create_box_mesh("RevR", (0.14, 0.04, 0.045), (0.42, bmin.y + 0.10, 0.62), pal["reverselight"])
    reverselight = join_objects([rev_l, rev_r], "Reverselight_Main", pal["reverselight"])

    wheels_dict = {}
    calipers_dict = {}
    for corner in ("FL", "FR", "RL", "RR"):
        w_joined = join_objects(wheel_groups[corner], f"WheelRaw_{corner}", pal["tire"])
        wmn, wmx = world_bbox([w_joined])
        wc = (wmn + wmx) * 0.5
        wheels_dict[corner] = (wc, w_joined)
        cal = create_sculpted_caliper(f"Brake_{corner}", wc, corner.endswith("L"), corner.startswith("F"), pal["caliper"])
        calipers_dict[corner] = (wc, cal)

    build_final_rig(
        os.path.join(OUT_DIR, "kestrel_xr.glb"),
        body_shell, body_trim, body_interior, body_glass,
        headlight, taillight, reverselight, steering_wheel,
        wheels_dict, calipers_dict
    )


# ---------------------------------------------------------------------------
# Car 2: VELA GT — Porsche 911 (achrefelouafi/GrassSystemThreeJS)
# ---------------------------------------------------------------------------
def build_vela_gt():
    print("\n================ BUILDING vela_gt.glb (Porsche 911) ================")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(RAW_DIR, "porsche_911.glb"))

    pal = create_material_palette(
        paint_rgb=(0.06, 0.22, 0.48),        # Deep Metallic Sapphire Blue
        caliper_rgb=(0.82, 0.07, 0.06),      # Guards Red calipers
        rim_rgb=(0.82, 0.85, 0.88),          # Brushed Silver Alloy
    )

    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    apply_all_transforms_to_meshes(meshes)

    # Porsche 911 faces -Y in raw GLB -> rotate 180° around Z so +Y is forward!
    rot180 = Matrix.Rotation(math.pi, 4, 'Z')
    transform_mesh_objs(meshes, rot180)

    # Identify front & rear wheel axles (Cylinder.000 = rear, Cylinder.001 = front)
    # Note: after 180° Z rotation, rear is at Y ≈ -2.02 and front is at Y ≈ +2.11!
    rear_wheel_meshes = [o for o in meshes if o.name.startswith("Cylinder.000_")]
    front_wheel_meshes = [o for o in meshes if o.name.startswith("Cylinder.001_")]

    # Compute exact rear & front axle centers from rubber meshes (Cylinder.000_2 / Cylinder.001_2)
    rear_rubber = [o for o in rear_wheel_meshes if o.name == "Cylinder.000_2"][0]
    front_rubber = [o for o in front_wheel_meshes if o.name == "Cylinder.001_2"][0]
    rmn, rmx = world_bbox([rear_rubber])
    fmn, fmx = world_bbox([front_rubber])

    rear_y = (rmn.y + rmx.y) * 0.5
    front_y = (fmn.y + fmx.y) * 0.5
    raw_wb = front_y - rear_y
    scale = TARGET_WHEELBASE / raw_wb
    mid_x = (rmn.x + rmx.x) * 0.5
    mid_y = (rear_y + front_y) * 0.5
    min_z = rmn.z

    xform = Matrix.Scale(scale, 4) @ Matrix.Translation(Vector((-mid_x, -mid_y, -min_z)))
    transform_mesh_objs(meshes, xform)

    # Remove the slightly-steered raw front wheel meshes; we will clone the perfectly straight rear wheels to the front!
    fmn2, fmx2 = world_bbox([front_rubber])
    front_y_scaled = (fmn2.y + fmx2.y) * 0.5
    for o in front_wheel_meshes:
        meshes.remove(o)
        bpy.data.objects.remove(o, do_unlink=True)

    # Split straight rear axle meshes into RL (x < 0) and RR (x >= 0)
    rl_parts, rr_parts = [], []
    rl_cal_parts, rr_cal_parts = [], []
    for o in rear_wheel_meshes:
        meshes.remove(o)
        if o.name.endswith("_0"):
            override_all_materials(o, pal["rim"])
            l_o, r_o = split_mesh_by_x(o, 0.0)
            rl_parts.append(l_o); rr_parts.append(r_o)
        elif o.name.endswith("_1"):
            override_all_materials(o, pal["rotor"])
            l_o, r_o = split_mesh_by_x(o, 0.0)
            rl_parts.append(l_o); rr_parts.append(r_o)
        elif o.name.endswith("_2"):
            override_all_materials(o, pal["tire"])
            l_o, r_o = split_mesh_by_x(o, 0.0)
            rl_parts.append(l_o); rr_parts.append(r_o)
        elif o.name.endswith("_3"):
            override_all_materials(o, pal["caliper"])
            l_o, r_o = split_mesh_by_x(o, 0.0)
            rl_cal_parts.append(l_o); rr_cal_parts.append(r_o)

    rl_wheel = join_objects(rl_parts, "WheelRaw_RL", pal["tire"])
    rr_wheel = join_objects(rr_parts, "WheelRaw_RR", pal["tire"])
    rl_mn, rl_mx = world_bbox([rl_wheel])
    rr_mn, rr_mx = world_bbox([rr_wheel])
    rl_c = (rl_mn + rl_mx) * 0.5
    rr_c = (rr_mn + rr_mx) * 0.5

    # Clone straight RL/RR to FL/FR at exact front axle Y
    dy_front = front_y_scaled - rl_c.y
    fl_wheel = rl_wheel.copy(); fl_wheel.data = rl_wheel.data.copy()
    fl_wheel.name = "WheelRaw_FL"
    bpy.context.collection.objects.link(fl_wheel)
    fl_wheel.data.transform(Matrix.Translation(Vector((0.0, dy_front, 0.0))))
    fl_c = rl_c + Vector((0.0, dy_front, 0.0))

    fr_wheel = rr_wheel.copy(); fr_wheel.data = rr_wheel.data.copy()
    fr_wheel.name = "WheelRaw_FR"
    bpy.context.collection.objects.link(fr_wheel)
    fr_wheel.data.transform(Matrix.Translation(Vector((0.0, dy_front, 0.0))))
    fr_c = rr_c + Vector((0.0, dy_front, 0.0))

    wheels_dict = {
        "FL": (fl_c, fl_wheel),
        "FR": (fr_c, fr_wheel),
        "RL": (rl_c, rl_wheel),
        "RR": (rr_c, rr_wheel),
    }

    # Build static calipers for all 4 corners (clone RL/RR calipers to FL/FR)
    calipers_dict = {}
    if rl_cal_parts and rr_cal_parts:
        rl_cal = join_objects(rl_cal_parts, "Brake_RL", pal["caliper"])
        rr_cal = join_objects(rr_cal_parts, "Brake_RR", pal["caliper"])
        fl_cal = rl_cal.copy(); fl_cal.data = rl_cal.data.copy(); fl_cal.name = "Brake_FL"
        bpy.context.collection.objects.link(fl_cal)
        fl_cal.data.transform(Matrix.Translation(Vector((0.0, dy_front, 0.0))))
        fr_cal = rr_cal.copy(); fr_cal.data = rr_cal.data.copy(); fr_cal.name = "Brake_FR"
        bpy.context.collection.objects.link(fr_cal)
        fr_cal.data.transform(Matrix.Translation(Vector((0.0, dy_front, 0.0))))
        calipers_dict = {
            "FL": (fl_c, fl_cal), "FR": (fr_c, fr_cal),
            "RL": (rl_c, rl_cal), "RR": (rr_c, rr_cal),
        }
    else:
        for corner, (wc, _) in wheels_dict.items():
            calipers_dict[corner] = (wc, create_sculpted_caliper(f"Brake_{corner}", wc, corner.endswith("L"), corner.startswith("F"), pal["caliper"]))

    # Classify remaining body meshes by material name
    shell_objs, trim_objs, interior_objs, glass_objs, head_objs, tail_objs = [], [], [], [], [], []
    for o in meshes:
        mat_names = [m.name.lower() for m in o.data.materials if m]
        m0 = mat_names[0] if mat_names else ""
        omn, omx = world_bbox([o])
        oc = (omn + omx) * 0.5
        # Drop any stray floor/shadow planes far outside car or flat at Z≈0
        if "plane.005" in o.name.lower() or "plane.006" in o.name.lower():
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        if m0 in ("paint", "coat"):
            override_all_materials(o, pal["paint"])
            shell_objs.append(o)
        elif m0 in ("window", "glass"):
            override_all_materials(o, pal["glass"])
            glass_objs.append(o)
        elif m0 == "lights":
            if oc.y > 0.0:
                override_all_materials(o, pal["headlight"])
                head_objs.append(o)
            else:
                override_all_materials(o, pal["taillight"])
                tail_objs.append(o)
        elif m0 == "tex_shiny":
            # Rear tailbar/emblem vs front light bezel
            if oc.y < -1.5:
                override_all_materials(o, pal["taillight"])
                tail_objs.append(o)
            else:
                override_all_materials(o, pal["chrome"])
                trim_objs.append(o)
        elif m0 in ("full_black",):
            override_all_materials(o, pal["interior"])
            interior_objs.append(o)
        elif m0 == "silver":
            override_all_materials(o, pal["chrome"])
            trim_objs.append(o)
        else:
            override_all_materials(o, pal["plastic_dark"])
            trim_objs.append(o)

    body_shell = join_objects(shell_objs, "Body_Shell", pal["paint"])
    body_trim = join_objects(trim_objs, "Body_Trim", pal["plastic_dark"])
    body_interior = join_objects(interior_objs, "Body_Interior", pal["interior"])
    body_glass = join_objects(glass_objs, "Body_Glass", pal["glass"])
    headlight = join_objects(head_objs, "Headlight_Main", pal["headlight"])
    taillight = join_objects(tail_objs, "Taillight_Main", pal["taillight"])

    # Add subtle reverse lamps on rear fascia
    bmin, bmax = world_bbox([body_shell])
    rev_l = create_box_mesh("RevL", (0.14, 0.04, 0.04), (-0.44, bmin.y + 0.14, 0.68), pal["reverselight"])
    rev_r = create_box_mesh("RevR", (0.14, 0.04, 0.04), (0.44, bmin.y + 0.14, 0.68), pal["reverselight"])
    reverselight = join_objects([rev_l, rev_r], "Reverselight_Main", pal["reverselight"])

    # Add sleek sporty steering wheel inside cockpit (visible through windshield/cockpit cam)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.165, minor_radius=0.02, location=(-0.34, 0.30, 0.84), rotation=(math.radians(68), 0.0, 0.0))
    sw = bpy.context.active_object
    sw.name = "SteeringWheel"
    override_all_materials(sw, pal["interior_leather"])
    apply_all_transforms_to_meshes([sw])

    build_final_rig(
        os.path.join(OUT_DIR, "vela_gt.glb"),
        body_shell, body_trim, body_interior, body_glass,
        headlight, taillight, reverselight, sw,
        wheels_dict, calipers_dict
    )


# ---------------------------------------------------------------------------
# Car 3: ORION RS — Khronos Group CarConcept (CC-BY 4.0)
# ---------------------------------------------------------------------------
def build_orion_rs():
    print("\n================ BUILDING orion_rs.glb (Khronos CarConcept) ================")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(RAW_DIR, "car_concept.glb"))

    pal = create_material_palette(
        paint_rgb=(0.045, 0.40, 0.28),       # Metallic Emerald / British Racing Green
        caliper_rgb=(0.96, 0.48, 0.04),      # Track Orange calipers
        rim_rgb=(0.30, 0.33, 0.37),          # Satin Gunmetal Alloy
    )

    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    parent_map = {o.name: (o.parent.name if o.parent else "") for o in meshes}
    apply_all_transforms_to_meshes(meshes)

    # CarConcept faces -Y in raw GLB -> rotate 180° around Z so +Y is forward!
    rot180 = Matrix.Rotation(math.pi, 4, 'Z')
    transform_mesh_objs(meshes, rot180)

    # Identify wheel groups via parent names (WheelFrontL/R, WheelRearL/R)
    w_groups = {"FL": [], "FR": [], "RL": [], "RR": []}
    cal_groups = {"FL": [], "FR": [], "RL": [], "RR": []}
    for o in meshes:
        pname = parent_map[o.name]
        lname = o.name.lower()
        target_corner = None
        if pname == "WheelFrontL" or "wheelfrontl" in lname:
            target_corner = "FL"
        elif pname == "WheelFrontR" or "wheelfrontr" in lname:
            target_corner = "FR"
        elif pname == "WheelRearL" or "wheelrearl" in lname:
            target_corner = "RL"
        elif pname == "WheelRearR" or "wheelrearr" in lname:
            target_corner = "RR"
        if target_corner:
            if "brakepad" in lname:
                cal_groups[target_corner].append(o)
            else:
                w_groups[target_corner].append(o)

    def gcenter(objs):
        mn, mx = world_bbox(objs)
        return (mn + mx) * 0.5, mn, mx

    fl_c, _, _ = gcenter(w_groups["FL"])
    fr_c, _, _ = gcenter(w_groups["FR"])
    rl_c, rl_mn, rl_mx = gcenter(w_groups["RL"])
    rr_c, _, _ = gcenter(w_groups["RR"])

    raw_wb = ((fl_c.y + fr_c.y) * 0.5) - ((rl_c.y + rr_c.y) * 0.5)
    scale = TARGET_WHEELBASE / raw_wb
    mid_x = (rl_c.x + rr_c.x) * 0.5
    mid_y = (fl_c.y + fr_c.y + rl_c.y + rr_c.y) * 0.25
    min_z = rl_mn.z

    xform = Matrix.Scale(scale, 4) @ Matrix.Translation(Vector((-mid_x, -mid_y, -min_z)))
    transform_mesh_objs(meshes, xform)

    # Compute scaled wheel centers
    fl_c2, _, _ = gcenter(w_groups["FL"])
    fr_c2, _, _ = gcenter(w_groups["FR"])
    rl_c2, rl_mn2, rl_mx2 = gcenter(w_groups["RL"])
    rr_c2, _, _ = gcenter(w_groups["RR"])

    # Assign wheel materials to straight rear wheels (RL, RR)
    for corner in ("RL", "RR"):
        for o in w_groups[corner]:
            lname = o.name.lower()
            if "rim" in lname:
                override_all_materials(o, pal["rim"])
            elif "disc" in lname:
                override_all_materials(o, pal["rotor"])
            else:
                override_all_materials(o, pal["tire"])

    # Delete steered raw front wheel meshes & replace with clones of straight rear wheels!
    # Also scale tires slightly so radius is ~0.37m (matching arch clearance cleanly)
    rl_wheel = join_objects(w_groups["RL"], "WheelRaw_RL", pal["tire"])
    rr_wheel = join_objects(w_groups["RR"], "WheelRaw_RR", pal["tire"])
    for corner in ("FL", "FR"):
        for o in w_groups[corner]:
            if o in meshes:
                meshes.remove(o)
            bpy.data.objects.remove(o, do_unlink=True)
    for corner in ("FL", "FR", "RL", "RR"):
        for o in cal_groups[corner]:
            if o in meshes:
                meshes.remove(o)
            bpy.data.objects.remove(o, do_unlink=True)
        if corner in ("RL", "RR"):
            for o in w_groups[corner]:
                if o in meshes:
                    meshes.remove(o)

    # Normalize wheel radius slightly if > 0.40m so preview and live arch fitment match
    cur_r = (rl_mx2.z - rl_mn2.z) * 0.5
    if cur_r > 0.39:
        w_scale = 0.37 / cur_r
        for wobj, wc in ((rl_wheel, rl_c2), (rr_wheel, rr_c2)):
            wobj.data.transform(Matrix.Translation(wc) @ Matrix.Scale(w_scale, 4) @ Matrix.Translation(-wc))
            wobj.data.update()
        # Drop entire car down so scaled tires rest on Z=0
        new_min_z = world_bbox([rl_wheel])[0].z
        if abs(new_min_z) > 1e-4:
            dz_mat = Matrix.Translation(Vector((0.0, 0.0, -new_min_z)))
            transform_mesh_objs([o for o in meshes if o.name in bpy.data.objects] + [rl_wheel, rr_wheel], dz_mat)
            fl_c2.z -= new_min_z; fr_c2.z -= new_min_z; rl_c2.z -= new_min_z; rr_c2.z -= new_min_z

    dy_f = ((fl_c2.y + fr_c2.y) * 0.5) - ((rl_c2.y + rr_c2.y) * 0.5)
    fl_wheel = rl_wheel.copy(); fl_wheel.data = rl_wheel.data.copy(); fl_wheel.name = "WheelRaw_FL"
    bpy.context.collection.objects.link(fl_wheel)
    fl_wheel.data.transform(Matrix.Translation(Vector((0.0, dy_f, 0.0))))
    fl_c_final = rl_c2 + Vector((0.0, dy_f, 0.0))

    fr_wheel = rr_wheel.copy(); fr_wheel.data = rr_wheel.data.copy(); fr_wheel.name = "WheelRaw_FR"
    bpy.context.collection.objects.link(fr_wheel)
    fr_wheel.data.transform(Matrix.Translation(Vector((0.0, dy_f, 0.0))))
    fr_c_final = rr_c2 + Vector((0.0, dy_f, 0.0))

    wheels_dict = {
        "FL": (fl_c_final, fl_wheel),
        "FR": (fr_c_final, fr_wheel),
        "RL": (rl_c2, rl_wheel),
        "RR": (rr_c2, rr_wheel),
    }
    calipers_dict = {}
    for corner, (wc, _) in wheels_dict.items():
        calipers_dict[corner] = (wc, create_sculpted_caliper(f"Brake_{corner}", wc, corner.endswith("L"), corner.startswith("F"), pal["caliper"]))

    # Classify remaining body meshes
    shell_objs, trim_objs, interior_objs, glass_objs, head_objs, tail_objs, rev_objs, steer_objs = [], [], [], [], [], [], [], []
    for o in list(meshes):
        if o.name not in bpy.data.objects:
            continue
        lname = o.name.lower()
        mat_names = [m.name.lower() for m in o.data.materials if m]
        m0 = mat_names[0] if mat_names else ""
        if "steeringwheel" in lname or "steeringemblem" in lname:
            override_all_materials(o, pal["interior_leather"])
            steer_objs.append(o)
        elif "headlight" in lname or "headlight" in m0:
            override_all_materials(o, pal["headlight"])
            head_objs.append(o)
        elif "taillight" in lname and "panel" not in lname or "brakelight" in m0:
            override_all_materials(o, pal["taillight"])
            tail_objs.append(o)
        elif "turnsignal" in lname or "signallight" in m0:
            override_all_materials(o, pal["reverselight"])
            rev_objs.append(o)
        elif "glass" in m0 or "window" in lname or "windshield" in lname:
            if "gasket" in lname or "wiper" in lname:
                override_all_materials(o, pal["plastic_dark"])
                trim_objs.append(o)
            else:
                override_all_materials(o, pal["glass"])
                glass_objs.append(o)
        elif "paint 1" in m0:
            override_all_materials(o, pal["paint"])
            shell_objs.append(o)
        elif "paint 2" in m0:
            override_all_materials(o, pal["paint_accent"])
            trim_objs.append(o)
        elif "interior" in lname or "interior" in m0 or "dashboard" in m0 or "floormat" in m0:
            override_all_materials(o, pal["interior_leather"] if "seat" in lname else pal["interior"])
            interior_objs.append(o)
        elif "mirror" in m0 or "hardware" in m0:
            override_all_materials(o, pal["chrome"])
            trim_objs.append(o)
        else:
            override_all_materials(o, pal["plastic_dark"])
            trim_objs.append(o)

    body_shell = join_objects(shell_objs, "Body_Shell", pal["paint"])
    body_trim = join_objects(trim_objs, "Body_Trim", pal["plastic_dark"])
    body_interior = join_objects(interior_objs, "Body_Interior", pal["interior"])
    body_glass = join_objects(glass_objs, "Body_Glass", pal["glass"])
    headlight = join_objects(head_objs, "Headlight_Main", pal["headlight"])
    taillight = join_objects(tail_objs, "Taillight_Main", pal["taillight"])
    reverselight = join_objects(rev_objs, "Reverselight_Main", pal["reverselight"])
    steering_wheel = join_objects(steer_objs, "SteeringWheel", pal["interior_leather"])

    build_final_rig(
        os.path.join(OUT_DIR, "orion_rs.glb"),
        body_shell, body_trim, body_interior, body_glass,
        headlight, taillight, reverselight, steering_wheel,
        wheels_dict, calipers_dict
    )


if __name__ == "__main__":
    build_vela_gt()
    build_orion_rs()
    build_kestrel_xr()
    print("\nALL 3 HERO CARS NORMALIZED & RIGGED SUCCESSFULLY!")
