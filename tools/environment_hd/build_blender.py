#!/usr/bin/env python3
"""Blender 4.x reproducible source scene. Not a pre-rendered claim.
Run: blender -b --python tools/environment_hd/build_blender.py -- --render
World coordinates: Godot (x,y,z) -> Blender (x,-z,y), metres. No collision changes.
"""
import bpy
import json
import math
import sys
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets" / "environment_hd"
SHOW = ROOT / "showcase" / "environment_hd"
DATA = json.loads((SHOW / "data" / "corridor_v1.json").read_text())
P = DATA["patch"]
ROUTE = DATA["road_center"]
SHOTS = json.loads((SHOW / "data" / "camera_shots_v2.json").read_text())["shots"]
if len(SHOTS) != 6:
    raise ValueError("Needle Pass requires exactly six fixed shot cameras")
RENDER = "--render" in sys.argv
LEGACY_CLIFFS = "--legacy-cliffs" in sys.argv

def bvec(p):
    return Vector((float(p[0]), -float(p[2]), float(p[1])))

def height(ix, iz):
    ix=max(0,min(P["nx"]-1,ix))
    iz=max(0,min(P["nz"]-1,iz))
    return P["heights_cm"][iz*P["nx"]+ix] / 100.0

def surface_y(x,z):
    fx=max(0,min(P["nx"]-1,(x-P["origin_x"])/4))
    fz=max(0,min(P["nz"]-1,(z-P["origin_z"])/4))
    ix=min(P["nx"]-2,int(fx))
    iz=min(P["nz"]-2,int(fz))
    u=fx-ix
    v=fz-iz
    return (height(ix,iz)*(1-u)+height(ix+1,iz)*u)*(1-v)+(height(ix,iz+1)*(1-u)+height(ix+1,iz+1)*u)*v

def image(name, colorspace='sRGB'):
    im=bpy.data.images.load(str(ASSETS/"textures"/name),check_existing=True)
    im.colorspace_settings.name=colorspace
    return im

def pbr(name, color_name, rough_name, uvscale=1.0, normal_name=None):
    m=bpy.data.materials.new(name)
    m.diffuse_color=(0.4,0.4,0.4,1)
    m.use_nodes=True
    tree=m.node_tree
    bsdf=tree.nodes.get("Principled BSDF")
    tex=tree.nodes.new("ShaderNodeTexImage")
    tex.image=image(color_name)
    tree.links.new(tex.outputs["Color"],bsdf.inputs["Base Color"])
    rough=tree.nodes.new("ShaderNodeTexImage")
    rough.image=image(rough_name,'Non-Color')
    tree.links.new(rough.outputs["Color"],bsdf.inputs["Roughness"])
    if normal_name:
        normtex=tree.nodes.new("ShaderNodeTexImage")
        normtex.image=image(normal_name,'Non-Color')
        normal=tree.nodes.new("ShaderNodeNormalMap")
        normal.inputs["Strength"].default_value=0.82
        tree.links.new(normtex.outputs["Color"],normal.inputs["Color"])
        tree.links.new(normal.outputs["Normal"],bsdf.inputs["Normal"])
    if color_name != "rock_color.jpg":
        # Roughness-derived fine bump; the CC0 source normal is still missing.
        bump=tree.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value=.16 if color_name=="asphalt_color.jpg" else .11
        bump.inputs["Distance"].default_value=.018 if color_name=="asphalt_color.jpg" else .026
        tree.links.new(rough.outputs["Color"],bump.inputs["Height"])
        tree.links.new(bump.outputs["Normal"],bsdf.inputs["Normal"])
    bsdf.inputs["Metallic"].default_value=0.0
    return m

def plain(name, rgba):
    m=bpy.data.materials.new(name)
    m.diffuse_color=rgba
    m.use_nodes=True
    shader=m.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value=rgba
    shader.inputs["Roughness"].default_value=0.87
    return m

def refine_foliage_materials():
    """Preserve the authored source meshes, enrich their close-up response."""
    for mat in bpy.data.materials:
        if not mat.use_nodes or not mat.node_tree:
            continue
        name=mat.name.lower()
        bsdf=mat.node_tree.nodes.get("Principled BSDF")
        if bsdf is None:
            continue
        if "furrowed" in name or "bark" in name:
            noise=mat.node_tree.nodes.new("ShaderNodeTexNoise")
            noise.inputs["Scale"].default_value=18.0
            noise.inputs["Detail"].default_value=4.0
            bump=mat.node_tree.nodes.new("ShaderNodeBump")
            bump.inputs["Strength"].default_value=.19
            bump.inputs["Distance"].default_value=.022
            mat.node_tree.links.new(noise.outputs["Fac"],bump.inputs["Height"])
            mat.node_tree.links.new(bump.outputs["Normal"],bsdf.inputs["Normal"])
            bsdf.inputs["Roughness"].default_value=.93
        if "needles" in name or "fern_green" in name:
            if "Subsurface Weight" in bsdf.inputs:
                bsdf.inputs["Subsurface Weight"].default_value=.045
            bsdf.inputs["Roughness"].default_value=.83
            info=mat.node_tree.nodes.new("ShaderNodeObjectInfo")
            tint=mat.node_tree.nodes.new("ShaderNodeValToRGB")
            tint.color_ramp.elements[0].color=(.79,.84,.72,1)
            tint.color_ramp.elements[1].color=(1.0,1.0,.92,1)
            mat.node_tree.links.new(info.outputs["Random"],tint.inputs[0])
            existing=bsdf.inputs["Base Color"].default_value[:]
            vary=mat.node_tree.nodes.new("ShaderNodeMixRGB")
            vary.blend_type="MULTIPLY"
            vary.inputs[0].default_value=.35
            vary.inputs[1].default_value=existing
            mat.node_tree.links.new(tint.outputs["Color"],vary.inputs[2])
            mat.node_tree.links.new(vary.outputs[0],bsdf.inputs["Base Color"])

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for collection in list(bpy.data.collections):
    if not collection.objects:
        bpy.data.collections.remove(collection)

soil=pbr("Ground093C – ambientCG CC0","ground_color.jpg","ground_rough.jpg")
stone=pbr("Rock063 – ambientCG CC0","rock_color.jpg","rock_rough.jpg",normal_name="rock_normal.jpg")
asphalt=pbr("Asphalt 02 – Poly Haven CC0","asphalt_color.jpg","asphalt_rough.jpg")

# Canonical hillside: blend the original CC0 soil toward rock on steep slopes.
soil_nodes=soil.node_tree.nodes
soil_links=soil.node_tree.links
ground_bsdf=soil_nodes.get("Principled BSDF")
ground_base=next(n for n in soil_nodes if n.type=="TEX_IMAGE" and n.image.name.startswith("ground_color"))
face_normal=soil_nodes.new("ShaderNodeNewGeometry")
vertical=soil_nodes.new("ShaderNodeSeparateXYZ")
soil_links.new(face_normal.outputs["Normal"],vertical.inputs[0])
rock_slope=soil_nodes.new("ShaderNodeMapRange")
rock_slope.clamp=True
rock_slope.inputs["From Min"].default_value=.66
rock_slope.inputs["From Max"].default_value=.95
rock_slope.inputs["To Min"].default_value=1.0
rock_slope.inputs["To Max"].default_value=0.0
soil_links.new(vertical.outputs["Z"],rock_slope.inputs["Value"])
rock_color=soil_nodes.new("ShaderNodeTexImage")
rock_color.image=image("rock_color.jpg")
slope_color=soil_nodes.new("ShaderNodeMixRGB")
slope_color.blend_type="MIX"
soil_links.new(rock_slope.outputs["Result"],slope_color.inputs[0])
soil_links.new(ground_base.outputs["Color"],slope_color.inputs[1])
soil_links.new(rock_color.outputs["Color"],slope_color.inputs[2])
soil_links.new(slope_color.outputs[0],ground_bsdf.inputs["Base Color"])

# Large irregular resurfacing masks, rather than uniformly repeated asphalt.
road_nodes=asphalt.node_tree.nodes
road_links=asphalt.node_tree.links
road_bsdf=road_nodes.get("Principled BSDF")
road_base=next(n for n in road_nodes if n.type=="TEX_IMAGE" and n.image.name.startswith("asphalt_color"))
patch_noise=road_nodes.new("ShaderNodeTexNoise")
patch_noise.inputs["Scale"].default_value=.23
patch_noise.inputs["Detail"].default_value=2.0
road_geometry=road_nodes.new("ShaderNodeNewGeometry")
road_links.new(road_geometry.outputs["Position"],patch_noise.inputs["Vector"])
patch_threshold=road_nodes.new("ShaderNodeValToRGB")
patch_threshold.color_ramp.elements[0].position=.52
patch_threshold.color_ramp.elements[0].color=(0,0,0,1)
patch_threshold.color_ramp.elements[1].position=.73
patch_threshold.color_ramp.elements[1].color=(.29,.29,.29,1)
road_links.new(patch_noise.outputs["Fac"],patch_threshold.inputs[0])
wear=road_nodes.new("ShaderNodeMixRGB")
wear.blend_type="MULTIPLY"
road_links.new(patch_threshold.outputs["Color"],wear.inputs[0])
road_links.new(road_base.outputs["Color"],wear.inputs[1])
wear.inputs[2].default_value=(.66,.64,.61,1)
road_links.new(wear.outputs[0],road_bsdf.inputs["Base Color"])
line_gold=plain("Weathered alpine yellow",(.58,.38,.10,1))
line_white=plain("Off-white worn paint",(.69,.7,.65,1))

def mesh_object(name,verts,faces,material,uv_from_world=False):
    me=bpy.data.meshes.new(name)
    me.from_pydata(verts,[],faces)
    me.update(calc_edges=True)
    ob=bpy.data.objects.new(name,me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(material)
    if uv_from_world:
        uv=me.uv_layers.new(name="WorldUV")
        for poly in me.polygons:
            for loop_index in poly.loop_indices:
                i=me.loops[loop_index].vertex_index
                co=me.vertices[i].co
                uv.data[loop_index].uv=(co.x*0.12,co.y*0.12)
        for poly in me.polygons:
            poly.use_smooth=True
    return ob

verts=[]
faces=[]
for z in range(P["nz"]):
    for x in range(P["nx"]):
        verts.append((P["origin_x"]+x*4,-(P["origin_z"]+z*4),height(x,z)+.04))
for z in range(P["nz"]-1):
    for x in range(P["nx"]-1):
        a=z*P["nx"]+x
        faces.append((a,a+P["nx"],a+1))
        faces.append((a+1,a+P["nx"],a+P["nx"]+1))
terrain=mesh_object("CANONICAL TERRAIN, visual only",verts,faces,soil,True)

def ribbon(label,width,lateral,lift,material,conform_edges=False):
    verts=[]
    faces=[]
    lengths=[]
    progress=0.0
    for i,point in enumerate(ROUTE):
        a=Vector(ROUTE[max(0,i-1)])
        b=Vector(ROUTE[min(len(ROUTE)-1,i+1)])
        tangent=b-a
        tangent.y=0
        tangent.normalize()
        side=Vector((tangent.z,0,-tangent.x))
        c=Vector(point)+side*lateral+Vector((0,lift,0))
        for sign in (-1,1):
            v=c+side*sign*width*.5
            if conform_edges:
                v.y=.1*v.y+.9*(surface_y(v.x,v.z)+.07)
            verts.append(bvec(v))
        lengths.append(progress)
        if i:
            j=2*(i-1)
            faces.extend([(j,j+2,j+1),(j+1,j+2,j+3)])
        if i<len(ROUTE)-1:
            progress+=(Vector(ROUTE[i+1])-Vector(ROUTE[i])).length
    ob=mesh_object(label,verts,faces,material)
    uv=ob.data.uv_layers.new(name="Across / arc length 3m tiles")
    for poly in ob.data.polygons:
        for li in poly.loop_indices:
            ix=ob.data.loops[li].vertex_index
            uv.data[li].uv=((0 if ix%2==0 else width/3.0),lengths[ix//2]/3.0)
    return ob

ribbon("Blended outer verge / no collision",13.8,0,.07,soil,True)
ribbon("Stony road shoulder / no collision",10.2,0,.115,soil,True)
ribbon("Asphalt visual, no collider",DATA["road_width_m"],0,.165,asphalt)
for side in [-3.17,3.17]:
    ribbon("Weathered edge paint",.12,side,.187,line_white)
for side in [-.13,.13]:
    ribbon("Double safety line",.11,side,.189,line_gold)

models={}
def source_meshes(model):
    if model in models:return models[model]
    before=set(bpy.data.objects)
    file=ASSETS/"models"/model
    if not file.is_file():raise FileNotFoundError(file)
    bpy.ops.import_scene.gltf(filepath=str(file))
    added=[o for o in bpy.data.objects if o not in before and o.type=="MESH"]
    for o in added:
        o.name="SOURCE_"+model+"_"+o.name
        o.hide_render=True
        o.hide_set(True)
    models[model]=added
    return added

def place(model,name,p,yaw,scale,replace_rock=False):
    R=Matrix.Rotation(math.radians(yaw),4,'Z')
    T=Matrix.Translation(bvec(p))
    S=Matrix.Scale(scale,4)
    for i,original in enumerate(source_meshes(model)):
        dup=original.copy()
        dup.data=original.data
        bpy.context.collection.objects.link(dup)
        dup.name=name+("_%d"%i)
        dup.hide_render=False
        dup.hide_set(False)
        dup.matrix_world=T@R@S@original.matrix_world
        if replace_rock:
            for slot in dup.material_slots:
                slot.link='OBJECT'
                slot.material=stone
    return True

trees=0
for item in DATA["placements"]:
    kind=item["asset"]
    if kind=="pine":
        if item["clearance"]>14 and trees%4!=0:
            model="cedar_fir_a.gltf" if trees%3==0 else "cedar_fir_b.gltf"
            factor=item["scale"]*.92
        else:
            model="pine_lod0.glb" if item["clearance"]<100 else "pine_lod1.glb"
            factor=item["scale"]
        trees+=1
    elif kind in ("rock","boulder"):
        model="boulder.glb";factor=item["scale"]
    elif kind=="shrub":
        model="fern_clump.gltf" if trees%3!=0 else "shrub.glb"
        factor=item["scale"];trees+=1
    elif kind=="arch":
        model="stone_arch.gltf";factor=item["scale"]
    else:
        continue
    place(model,item["id"],item["p"],item["yaw"],factor,kind in ("rock","boulder"))

# Flat procedural cliffs remain opt-in for old-draft comparison only.
# Default composition uses actual canonical hillside, not repeating cliff sheets.
if LEGACY_CLIFFS:
    for j,i in enumerate([24,45,66]):
        a=Vector(ROUTE[i-3]);b=Vector(ROUTE[i+3])
        t=b-a;t.y=0;t.normalize()
        side=Vector((-t.z,0,t.x))
        direction=-1 if j==1 else 1
        c=Vector(ROUTE[i])+side*direction*53
        c.y=surface_y(c.x,c.z)-1
        yaw=-math.degrees(math.atan2(t.z,t.x))
        if direction>0: yaw+=180.0
        name="cliff_rockface_b.gltf" if j==1 else "cliff_rockface_a.gltf"
        place(name,"Legacy_Cliff_"+str(j),c,yaw,1+.13*j,True)

for i in [30,31,32,49,50,51]:
    a=Vector(ROUTE[i-1]);b=Vector(ROUTE[i+1])
    t=b-a;t.y=0;t.normalize()
    edge=Vector((t.z,0,-t.x))
    p=Vector(ROUTE[i])+edge*5.7
    p.y=surface_y(p.x,p.z)+.15
    place("guardrail.glb","Road furniture_%d"%i,p,-math.degrees(math.atan2(t.z,t.x)),1.0)

sun_data=bpy.data.lights.new("Sun, 4:45 PM",type='SUN')
sun_data.energy=1.65
sun_data.angle=math.radians(0.85)
sun=bpy.data.objects.new("Golden sun",sun_data)
bpy.context.collection.objects.link(sun)
sun.rotation_euler=(math.radians(37),math.radians(-20),math.radians(-31))

world=bpy.context.scene.world
if world is None:
    world=bpy.data.worlds.new("Needle Pass sky")
    bpy.context.scene.world=world
world.use_nodes=True
nodes=world.node_tree.nodes
nodes.clear()
out=nodes.new("ShaderNodeOutputWorld")
bg=nodes.new("ShaderNodeBackground")
sky=nodes.new("ShaderNodeTexSky")
sky.sky_type='NISHITA'
sky.sun_elevation=math.radians(15)
sky.air_density=1.3
sky.dust_density=1.2
world.node_tree.links.new(sky.outputs["Color"],bg.inputs["Color"])
world.node_tree.links.new(bg.outputs["Background"],out.inputs["Surface"])

# All six cameras use explicit authored world-space shots shared with Godot.
refine_foliage_materials()
cameras=[]
for index,shot in enumerate(SHOTS):
    cam=bpy.data.cameras.new("CAM_%s" % shot["id"])
    cam.type='PERSP'
    cam.sensor_fit='VERTICAL'
    cam.sensor_height=24.0
    cam.lens=24.0/(2.0*math.tan(math.radians(shot["vertical_fov_deg"])*.5))
    obj=bpy.data.objects.new("CAM_%s_%s" % (shot["id"],shot["name"].replace(" ","_")),cam)
    bpy.context.collection.objects.link(obj)
    obj.location=bvec(shot["camera"])
    obj.rotation_euler=(bvec(shot["target"])-obj.location).to_track_quat('-Z','Y').to_euler()
    cameras.append(obj)

scene=bpy.context.scene
scene.camera=cameras[0]
scene.render.engine='CYCLES'
scene.cycles.samples=96
if hasattr(bpy.context.view_layer, "cycles"):
    bpy.context.view_layer.cycles.use_denoising=True
scene.render.resolution_x=1600
scene.render.resolution_y=900
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='AgX'
save=SHOW/"NeedlePass_Portfolio.blend"
bpy.ops.wm.save_as_mainfile(filepath=str(save))
print("Saved",save,"six fixed shot cameras",len(cameras),"procedural cliff blockouts",LEGACY_CLIFFS)
if RENDER:
    folder=SHOW/"renders"
    folder.mkdir(exist_ok=True)
    for i,camera in enumerate(cameras):
        scene.camera=camera
        scene.render.filepath=str(folder/("view_%02d.png"%(i+1)))
        bpy.ops.render.render(write_still=True)
    print("Rendered six real Cycles views to",folder)
