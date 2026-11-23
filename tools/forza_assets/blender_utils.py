"""Shared Blender 4.5 modeling, PBR material, and glTF/GLB export utilities."""
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector, Matrix

ROOT = Path(r"c:\Users\anshu\Documents\Coding\Driving-Game\driving-game")
PROP_TEX = ROOT / "tools" / "forza_assets" / "prop_textures"


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def get_or_create_collection(name="Scenery"):
    if name in bpy.data.collections:
        return bpy.data.collections[name]
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col


def make_pbr_tex_mat(
    name: str,
    tex_folder: str,
    uv_scale: float = 1.0,
    tint: tuple[float, float, float, float] | None = None,
    roughness_val: float | None = None,
    metallic: float = 0.0,
    normal_strength: float = 0.85,
):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = metallic
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (uv_scale, uv_scale, uv_scale)
    nt.links.new(tex_coord.outputs["UV"], mapping.inputs["Vector"])

    tdir = PROP_TEX / tex_folder
    albedo_path = tdir / "albedo.jpg"
    normal_path = tdir / "normal.jpg"
    rough_path = tdir / "roughness.jpg"

    if albedo_path.exists():
        tex_a = nt.nodes.new("ShaderNodeTexImage")
        tex_a.image = bpy.data.images.load(str(albedo_path), check_existing=True)
        nt.links.new(mapping.outputs["Vector"], tex_a.inputs["Vector"])
        if tint is not None:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs[7].default_value = tint
            nt.links.new(tex_a.outputs["Color"], mix.inputs[6])
            nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        else:
            nt.links.new(tex_a.outputs["Color"], bsdf.inputs["Base Color"])
    elif tint is not None:
        bsdf.inputs["Base Color"].default_value = tint

    if roughness_val is not None:
        bsdf.inputs["Roughness"].default_value = roughness_val
    elif rough_path.exists():
        tex_r = nt.nodes.new("ShaderNodeTexImage")
        tex_r.image = bpy.data.images.load(str(rough_path), check_existing=True)
        tex_r.image.colorspace_settings.name = "Non-Color"
        nt.links.new(mapping.outputs["Vector"], tex_r.inputs["Vector"])
        nt.links.new(tex_r.outputs["Color"], bsdf.inputs["Roughness"])

    if normal_path.exists():
        tex_n = nt.nodes.new("ShaderNodeTexImage")
        tex_n.image = bpy.data.images.load(str(normal_path), check_existing=True)
        tex_n.image.colorspace_settings.name = "Non-Color"
        nt.links.new(mapping.outputs["Vector"], tex_n.inputs["Vector"])
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = normal_strength
        nt.links.new(tex_n.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def make_solid_mat(
    name: str,
    color: tuple[float, float, float, float],
    roughness: float = 0.55,
    metallic: float = 0.0,
    emission: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None and emission_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return mat


def box_uv_project(obj, scale: float = 0.35):
    """Assign clean world-aligned box UVs to a mesh object."""
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    bm = bmesh.new()
    bm.from_mesh(mesh)
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                u, v = co.x * scale, co.y * scale
            elif ax >= ay and ax >= az:
                u, v = co.y * scale, co.z * scale
            else:
                u, v = co.x * scale, co.z * scale
            loop[uv_layer].uv = (u, v)
    bm.to_mesh(mesh)
    bm.free()


def join_objects(objs: list, name: str = "Asset"):
    """Join a list of mesh objects into a single multi-material mesh object."""
    objs = [o for o in objs if o is not None and o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def set_ground_and_center(obj, center_xz: bool = True, bottom_z: float = 0.0):
    """Translate object vertices so min Z == bottom_z and optionally center X/Y."""
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mesh = obj.data
    verts = [v.co for v in mesh.vertices]
    min_x = min(v.x for v in verts)
    max_x = max(v.x for v in verts)
    min_y = min(v.y for v in verts)
    max_y = max(v.y for v in verts)
    min_z = min(v.z for v in verts)
    dx = -0.5 * (min_x + max_x) if center_xz else 0.0
    dy = -0.5 * (min_y + max_y) if center_xz else 0.0
    dz = bottom_z - min_z
    for v in mesh.vertices:
        v.co.x += dx
        v.co.y += dy
        v.co.z += dz
    mesh.update()


def tri_count(obj) -> int:
    deps = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(deps)
    m = ev.to_mesh()
    m.calc_loop_triangles()
    count = len(m.loop_triangles)
    ev.to_mesh_clear()
    return count


def export_model(rel_path: str, obj):
    out_path = ROOT / rel_path
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    fmt = "GLB" if out_path.suffix.lower() == ".glb" else "GLTF_EMBEDDED"
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format=fmt,
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_materials="EXPORT",
        export_image_format="JPEG",
        export_jpeg_quality=85,
    )
    tris = tri_count(obj)
    size_kb = out_path.stat().st_size // 1024
    print(f"  [export] {rel_path}: {tris} tris, {size_kb} KB")
    return tris
