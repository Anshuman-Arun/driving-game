#!/usr/bin/env node
// Dependency-free source and independent geometric reference checks.
// This does NOT parse or run GDScript or compile GPU shaders.
"use strict";
const paths = {
  shader: "shaders/terrain_triplanar.gdshader",
  candidate: "modules/environment_terrain/terrain_candidate.gdshader",
  material: "assets/forza_env/materials/terrain_triplanar_pbr.tres",
  adapter: "modules/environment_terrain/terrain_preview.gd",
  band: "modules/environment_terrain/roadside_band.gd",
  rock: "modules/environment_terrain/rock_bank_recipe.gd",
  clearance: "modules/world_runtime/src/road_clearance.gd",
  builder: "modules/world_runtime/src/mesh_builder.gd",
  live: "scripts/integration/aster_valley_environment.gd",
  metadata: "data/world/world_metadata_v1.json",
  lake: "content/scenery/lake/water_cells_v1.json",
  roadworks: "data/world/roadworks.json",
  mask: "modules/environment_terrain/biome_mask.gd",
  contract: "modules/environment_terrain/world_contract.gd",
  runtime: "modules/world_runtime/src/world_runtime.gd",
  fixture: "modules/environment_terrain/tests/fixture_world.gd",
  fixtureGate: "modules/environment_terrain/tests/fixture_rock_gate.gd",
  tests: "modules/environment_terrain/tests/run_tests.gd",
  runner: "modules/environment_terrain/tests/run_headless.sh"
};
function verify(read, exists = null) {
  let checks = 0;
  const check = (ok, message) => { checks++; if (!ok) throw Error(message); };
  const files = Object.fromEntries(Object.entries(paths).map(([k,p]) => [k, read(p)]));
  const uniforms = (source) => Object.fromEntries([...source.matchAll(/^\s*uniform\s+(\w+)\s+(\w+)([^;]*);/gm)].map(m => [m[2], {type:m[1], tail:m[3].trim()}]));
  const old = uniforms(files.shader), candidate = uniforms(files.candidate);
  for (const [key, value] of Object.entries(old)) {
    check(JSON.stringify(value) === JSON.stringify(candidate[key]), "changed original uniform: " + key);
  }
  const list = (name) => [...files.adapter.match(new RegExp("const "+name+" := \\[([\\s\\S]*?)\\]"))[1].matchAll(/"([^"]+)"/g)].map(m=>m[1]);
  const textures = list("TEXTURES"), base = list("BASE_VALUES");
  check(textures.length === 16 && new Set(textures).size === 16, "16 unique source PBR samplers");
  check(base.length === 19 && new Set(base).size === 19, "19 unique original numeric/color/bool uniforms");
  check(Object.keys(old).length === textures.length + base.length, "every original uniform accounted for");
  check(Object.values(candidate).filter(v=>v.type==="sampler2D").length === 18, "bounded sampler count");
  for(const key of textures) check(old[key]?.type==="sampler2D", "source sampler "+key);
  const defaults = files.adapter.match(/const BASE_DEFAULTS := \{([\s\S]*?)\}\s*const LIMITS/)[1];
  const values = Object.fromEntries([...defaults.matchAll(/"([^"]+)":\s*(Color\([^)]*\)|true|false|-?\d+(?:\.\d+)?)/g)].map(m=>[m[1], m[2]]));
  for(const key of base) {
    check(key in values, "missing explicit default: "+key);
    const expected = old[key].tail.split("=").at(-1).trim();
    const actual = values[key];
    if(expected.startsWith("vec3(")) {
      check(actual.startsWith("Color(") && expected.slice(5,-1).split(",").map(Number).join() === actual.slice(6,-1).split(",").map(Number).join(), "color default "+key);
    } else if(expected==="true" || expected==="false") {
      check(expected===actual, "bool default "+key);
    } else {
      check(Number(expected)===Number(actual), "numeric default "+key);
    }
  }
  const refs = Object.fromEntries([...files.material.matchAll(/\[ext_resource type="([^"]+)" path="([^"]+)" id="([^"]+)"\]/g)].map(m=>[m[3], {type:m[1], path:m[2]}]));
  const resourcePaths = [];
  for(const key of textures) {
    const binding = files.material.match(new RegExp("shader_parameter/"+key+' = ExtResource\\("([^"]+)"\\)'));
    check(binding && refs[binding[1]]?.type==="Texture2D", "production texture binding "+key);
    resourcePaths.push(refs[binding[1]].path.replace(/^res:\/\//,""));
  }
  if(exists) for(const p of [...new Set(resourcePaths)]) check(exists(p), "PBR asset path exists: "+p);
  check(files.live.includes('const MAT_TERRAIN_PATH := "res://'+paths.material+'"'), "production prefers inspected material");
  check(files.builder.includes('terrain.name = "TerrainChunks"') && files.builder.includes('mesh.surface_set_material(0, materials["terrain"])'), "production terrain surface binding");
  check(candidate.biome_mask.tail.includes("filter_linear") && !candidate.biome_mask.tail.includes("source_color"), "biome texture treated as raw linear channels");
  check(candidate.roadside_mask.tail.includes("repeat_disable"), "roadside raster clamps at edge");
  check(files.candidate.includes("normalize(mix(n_grass, n_dirt, ground_forest))"), "roadside normal follows albedo/roughness mix");
  check(!/\bVERTEX\s*[+\-*/]?=/.test(files.candidate), "shader does not displace terrain");
  check(files.band.includes("const MAX_SIDE := 256") && files.band.includes("const CELL_M := 1.0") && files.band.includes("var half := step * 1.5") && files.band.includes("range(1, 5)"), "reference raster model constants match implementation");
  check(files.clearance.includes("extent.dot(normal.abs()) >= 0.0") && files.clearance.includes("if not include_shoulders and tri.shoulder"), "reference checks target actual SAT clearance implementation");
  check(files.rock.includes("/ GRID - 0.000001") && files.rock.includes('const MARGIN := 0.5'), "inclusive lower water boundary and setback");
  check(files.adapter.includes("not _chunk_overlaps(mesh_instance, pilot)") && files.adapter.includes('"skipped_chunks": skipped'), "pilot scope precedes mutation");
  check(files.contract.includes('report.get("full_world") == true') && files.runtime.includes('report["full_world"] = full'), "complete clearance gate uses actual runtime report");
  check(files.contract.includes('report.source_directory') && files.runtime.includes('report["source_directory"] = directory') && files.contract.includes('works == parser.data'), "canonical graded source identity gate");
  check(files.rock.includes("Contract.has_complete_clearance(world)") && files.rock.includes("_canonical_source_ok(world)"), "rock gate rejects partial/noncanonical world");
  check(files.mask.includes('length != 501 * 501 * 2') && files.mask.includes("version https://git-lfs.github.com/spec/v1"), "binary source validation rejects pointer text");
  for(const k of ["meadow_tint_multiplier","woodland_tint_multiplier"]) {
    check(candidate[k].type==="vec3" && candidate[k].tail==="= vec3(1.0)", "linear neutral tint control "+k);
    check(files.candidate.includes("mix(vec3(1.0), "+k+", candidate_w)"), "tint control limited to pilot "+k);
  }
  check(files.candidate.includes("textureLod(biome_mask, biome_uv, 0.0)") && files.candidate.includes("textureLod(roadside_mask, ruv, 0.0)"), "explicit zero-LOD mask samples");
  check(files.runner.includes("production pilot completed:") && files.tests.includes("production pilot completed:"), "full production completion marker enforced");
  check(files.tests.includes("production pilot covers only intersecting chunks"), "production scope asserted");
  const meta=JSON.parse(files.metadata);
  check(meta.bounds.min_x===-1000 && meta.bounds.max_x===1000 && meta.bounds.min_z===-1000 && meta.bounds.max_z===1000, "centered world coordinates");
  // Model the real generated grid, independently of the Godot material adapter.
  const hfield=meta.heightfield, chunkCells=32;
  const chunks=[];
  for(let z=0;z<hfield.sample_height-1;z+=chunkCells)
    for(let x=0;x<hfield.sample_width-1;x+=chunkCells)
      chunks.push([hfield.origin_x+x*hfield.spacing_m,hfield.origin_z+z*hfield.spacing_m,
        Math.min(chunkCells,hfield.sample_width-1-x)*hfield.spacing_m,Math.min(chunkCells,hfield.sample_height-1-z)*hfield.spacing_m]);
  const overlapsRect=(a,b)=>a[0]<b[0]+b[2]&&a[0]+a[2]>b[0]&&a[1]<b[1]+b[3]&&a[1]+a[3]>b[1];
  const countPilot=(p)=>chunks.filter(c=>overlapsRect(c,p)).length;
  const cedar=countPilot([-810,-450,220,220]), meadow=countPilot([-65,60,220,220]);
  check(chunks.length===256 && cedar===9 && meadow===9, "actual grid footprint selects nine of 256 chunks in each 220m pilot");
  check(countPilot([-1000,-1000,128,128])===1 && countPilot([999,999,1,1])===1, "exact chunk border and last partial cell");
  check(countPilot([1000,1000,1,1])===0, "outside map selects no terrain");
  const weight=(p,r)=>{ const fade=Math.min(8,Math.min(r[2],r[3])/2);
    const edge=Math.min(p[0]-r[0],r[0]+r[2]-p[0],p[1]-r[1],r[1]+r[3]-p[1]);
    const u=Math.max(0,Math.min(1,edge/fade)); return u*u*(3-2*u); };
  for(const r of [[-810,-450,220,220],[-1,-1,1,1],[-2,-3,4,6]]) {
    check(weight([r[0]+r[2]/2,r[1]+r[3]/2],r)===1,"adaptive pilot center reaches full weight");
    check(weight([r[0],r[1]+r[3]/2],r)===0 && weight([r[0]-0.01,r[1]+r[3]/2],r)===0,"pilot edge/outside preserves original");
  }
  const lake=JSON.parse(files.lake), works=JSON.parse(files.roadworks);
  check(lake.schema_version===1 && lake.origin_x===-1000 && lake.origin_z===-1000 && lake.spacing_m===4 && Number.isFinite(lake.water_height_m), "live lake grid");
  const waterCells=[lake.cells,...works.waters.map(p=>p.cells)].flat();
  for(const cell of waterCells) check(cell.length===2 && cell.every(v=>Number.isInteger(v)&&v>=0&&v<500), "valid rendered water cell");
  // Independent convex clipping oracle; a triangle intersects a closed rectangle iff
  // the triangle clipped by its four half-planes is nonempty.
  const clip = (poly,axis,value,sign) => {
    const out=[];
    for(let i=0;i<poly.length;i++){
      const a=poly[i], b=poly[(i+1)%poly.length];
      const da=(a[axis]-value)*sign, db=(b[axis]-value)*sign;
      if(da>=0) out.push(a);
      if((da<0&&db>0)||(da>0&&db<0)){
        const t=da/(da-db);out.push([a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t]);
      }
    }
    return out;
  };
  const oracle=(tri,c,e)=>{
    let p=tri;
    for(let axis=0;axis<2;axis++){
      p=clip(p,axis,c[axis]-e[axis],1);
      p=clip(p,axis,c[axis]+e[axis],-1);
    }
    return p.length>0;
  };
  // Numerical reference translation of the pinned clearance index's box/triangle
  // separating axes (independent of its cell lookup and Y interval).
  const sat=(t,c,e)=>{
    for(let k=0;k<2;k++) if(c[k]+e[k]<Math.min(...t.map(p=>p[k]))||c[k]-e[k]>Math.max(...t.map(p=>p[k]))) return false;
    const cross=(t[1][0]-t[0][0])*(t[2][1]-t[0][1])-(t[1][1]-t[0][1])*(t[2][0]-t[0][0]);
    if(cross===0)return false;
    const winding=Math.sign(cross);
    return t.every((a,i)=>{
      const b=t[(i+1)%3],nx=-(b[1]-a[1])*winding,ny=(b[0]-a[0])*winding;
      return (c[0]-a[0])*nx+(c[1]-a[1])*ny+e[0]*Math.abs(nx)+e[1]*Math.abs(ny)>=0;
    });
  };
  let state=20261125;
  const random=()=>((state=(Math.imul(state,1664525)+1013904223)>>>0)/4294967296);
  for(let i=0;i<5000;i++){
    const tri=Array.from({length:3},()=>[random()*30-15,random()*30-15]);
    const center=[random()*40-20,random()*40-20], extent=[random()*4+0.1,random()*4+0.1];
    check(sat(tri,center,extent)===oracle(tri,center,extent),"triangle-box oracle disagreement");
  }
  const triangles=[
    [[-40,-6],[40,-6],[-40,6]],[[40,-6],[40,6],[-40,6]],
    [[-3,15],[3,15],[-3,25]],[[3,15],[3,25],[-3,25]],
    [[-19,-16],[-4,-12],[-8,-9]], [[16,10],[24,19],[14,20]]
  ];
  let protectedSamples=0, positivePixels=0;
  for(const region of [[-24,-24,48,56],[-23.35,-21.1,47.4,52.2],[-8.2,4.1,19.2,24.3]]){
    const [ox,oz,w,h]=region, nx=Math.ceil(w),nz=Math.ceil(h),sx=w/nx,sz=h/nz;
    const grid=new Float64Array(nx*nz);
    const overlaps=(c,e,margin)=>triangles.some(t=>sat(t,c,[e[0]+margin,e[1]+margin]));
    for(let z=0;z<nz;z++)for(let x=0;x<nx;x++){
      const c=[ox+(x+0.5)*sx,oz+(z+0.5)*sz], e=[sx*1.5,sz*1.5];
      if(overlaps(c,e,0))continue;
      let weight=0;
      for(let i=1;i<=4;i++)if(overlaps(c,e,i)){weight=1-(i-1)/4;break;}
      const edge=Math.min(c[0]-ox,ox+w-c[0],c[1]-oz,oz+h-c[1]);
      grid[z*nx+x]=Math.round(255*weight*Math.min(1,Math.max(0,(edge-1)/5)))/255;
      if(grid[z*nx+x]>0)positivePixels++;
    }
    const get=(x,z)=>grid[Math.max(0,Math.min(nz-1,z))*nx+Math.max(0,Math.min(nx-1,x))];
    const bilinear=(p)=>{
      const x=(p[0]-ox)/sx-0.5,z=(p[1]-oz)/sz-0.5,ix=Math.floor(x),iz=Math.floor(z),fx=x-ix,fz=z-iz;
      return (get(ix,iz)*(1-fx)+get(ix+1,iz)*fx)*(1-fz)+(get(ix,iz+1)*(1-fx)+get(ix+1,iz+1)*fx)*fz;
    };
    for(let z=oz;z<oz+h;z+=0.2)for(let x=ox;x<ox+w;x+=0.2){
      const p=[x,z];
      if(!triangles.some(t=>oracle(t,p,[0,0])))continue;
      protectedSamples++;
      check(bilinear(p)<1e-12,"bilinear mask leakage into triangle projection");
    }
  }
  check(positivePixels>0 && protectedSamples>10000,"non-vacuous raster coverage");
  const waterIndex = (x)=>Math.floor((x+1000)/4-0.000001);
  check(waterIndex(16)===253 && waterIndex(16.001)===254,"water cell inclusive contact vs separated bounds");
  return {checks,protectedSamples,positivePixels,waterCells:waterCells.length,sourceUniforms:Object.keys(old).length,candidateSamplers:18,assetPaths:exists?new Set(resourcePaths).size:0,modeledPilotChunks:{full:chunks.length,cedar,meadow},kind:"source checks and independent geometry model; not engine execution"};
}
module.exports={verify,paths};
if(require.main===module){
  const fs=require("node:fs"), path=require("node:path");
  const root=path.resolve(__dirname,"../../..");
  const report=verify(p=>fs.readFileSync(path.join(root,p),"utf8"), p=>fs.existsSync(path.join(root,p)));
  if(process.argv.includes("--check-lfs")){
    const {execFileSync}=require("node:child_process");
    const lfs=execFileSync("git",["lfs","ls-files","--name-only"],{cwd:root,encoding:"utf8"}).trim().split(/\r?\n/).filter(Boolean);
    for(const name of lfs){
      const fd=fs.openSync(path.join(root,name),"r");
      const head=Buffer.alloc(128);
      const count=fs.readSync(fd,head,0,head.length,0);
      fs.closeSync(fd);
      if(count===0||head.toString("utf8",0,count).startsWith("version https://git-lfs.github.com/spec/v1"))throw Error("Missing LFS payload: "+name);
    }
    report.materializedLfsFiles=lfs.length;
  }
  console.log("[TerrainContract] "+JSON.stringify(report));
}
