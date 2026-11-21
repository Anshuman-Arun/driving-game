#!/usr/bin/env node
// Source and geometry validation; no claim of Godot import or photographic quality.
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
const root=path.resolve(import.meta.dirname,"../..");
const readJSON=p=>JSON.parse(fs.readFileSync(path.join(root,p),"utf8"));
const data=readJSON("showcase/environment_hd/data/corridor_v1.json");
const p=data.patch;
function assert(v,message){if(!v)throw Error(message);}
assert(data.source.road_graph_blob==="9bba378d68879df3baed2c97a4885c0adde88406","Road graph provenance changed");
assert(data.source.terrain_blob==="d951ce11a831dad5430b4c7157e2296f73c6b151","Heightfield provenance changed");
assert(p.heights_cm.length===p.nx*p.nz,"Raster dimensions mismatch");
assert(p.spacing_m===4,"Canonical terrain spacing changed");
assert(data.road_center.length>=70,"Unexpected road sampling");
assert(data.road_width_m===7,"Unexpected visual road width");
const inside=q=>q[0]>=p.origin_x&&q[0]<=p.origin_x+4*(p.nx-1)&&q[2]>=p.origin_z&&q[2]<=p.origin_z+4*(p.nz-1);
assert(data.road_center.every(inside),"Road left terrain patch");
assert(data.placements.every(x=>inside(x.p)&&x.clearance>=8),"Unsafe or out-of-patch prior scenery");
assert(new Set(data.placements.map(x=>x.id)).size===data.placements.length,"Duplicate scenery IDs");
const expected={
  "cliff_rockface_a.gltf":6060,"cliff_rockface_b.gltf":6060,
  "cedar_fir_a.gltf":7568,"cedar_fir_b.gltf":6010,"fern_clump.gltf":598
};
const metrics={};
for(const [name,count] of Object.entries(expected)){
  const file=path.join(root,"assets/environment_hd/models",name);
  const obj=JSON.parse(fs.readFileSync(file,"utf8"));
  assert(obj.asset.version==="2.0"&&obj.buffers.length===1,"Invalid glTF: "+name);
  const b=Buffer.from(obj.buffers[0].uri.split(",")[1],"base64");
  assert(b.length===obj.buffers[0].byteLength,"glTF length mismatch: "+name);
  let triangles=0;
  for(const mesh of obj.meshes)for(const prim of mesh.primitives){
    const indexAcc=obj.accessors[prim.indices];
    assert(indexAcc.type==="SCALAR"&&indexAcc.componentType===5125,"Bad indices: "+name);
    triangles+=indexAcc.count/3;
    for(const ai of Object.values(prim.attributes)){
      const acc=obj.accessors[ai],view=obj.bufferViews[acc.bufferView];
      assert(view.byteOffset+view.byteLength<=b.length,"Accessor out of bounds: "+name);
    }
  }
  assert(triangles===count,"Wrong authored triangle count "+name);
  metrics[name]={triangles,bytes:fs.statSync(file).size,material_count:obj.materials.length};
}
const jpeg={
  "asphalt_color.jpg":[1024,1024],"asphalt_rough.jpg":[1024,1024],
  "rock_color.jpg":[1024,512],"rock_normal.jpg":[1024,512],
  "rock_rough.jpg":[1024,512],"ground_color.jpg":[1024,1024],
  "ground_rough.jpg":[1024,1024]
};
function jpgDims(filename){
  const a=fs.readFileSync(filename);
  assert(a[0]===255&&a[1]===216,"Not JPEG: "+filename);
  for(let i=2;i<a.length-8;){if(a[i]!==255){i++;continue;}const marker=a[i+1];
    if(marker===0xD8||marker===0xD9){i+=2;continue;}
    if(marker>=0xC0&&marker<=0xCF&&![0xC4,0xC8,0xCC].includes(marker))return [a.readUInt16BE(i+7),a.readUInt16BE(i+5)];
    if(i+4>=a.length)break;
    const len=a.readUInt16BE(i+2);
    if(len<2)break;
    i+=2+len;
  }
  throw Error("JPEG dimensions unavailable "+filename);
}
let jpegBytes=0;
for(const [name,expectedSize] of Object.entries(jpeg)){
  const file=path.join(root,"assets/environment_hd/textures",name);
  const [w,h]=jpgDims(file);
  assert(w===expectedSize[0]&&h===expectedSize[1],"Texture resolution changed "+name+": "+w+"x"+h);
  jpegBytes+=fs.statSync(file).size;
}
const gd=fs.readFileSync(path.join(root,"showcase/environment_hd/world.gd"),"utf8");
assert(gd.includes("render_terrain_visual: bool")&&gd.includes("NoCollision"),"Visual-only integration contract missing");
assert((gd.match(/"0[1-6] /g)||[]).length===6,"Six viewpoints missing");
assert(gd.includes("func surface_height("),"Height accessor missing");
console.log(JSON.stringify({result:"PASS (source only)",corridor_length_m:data.render_metadata.route_length_m,
  terrain_vertices:p.nx*p.nz,terrain_triangles:(p.nx-1)*(p.nz-1)*2,
  placement_count:data.placements.length,min_clearance_m:Math.min(...data.placements.map(x=>x.clearance)),
  authored_geometry:metrics,texture_count:Object.keys(jpeg).length,
  texture_footprint_bytes:jpegBytes,import_test:"NOT RUN",fps:"NOT MEASURED"},null,2));
