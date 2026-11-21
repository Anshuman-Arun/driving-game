// Independent source-only scenery geometry and content validation. Node 20+, no packages.
// Usage: node content/scenery/tools/validate.mjs path/to/data/world
export function validate(metadata,graph,terrain,manifest,packs,mask,metrics,reservations) {
 const errors=[],warnings=[],report={};
 const gateZones=reservations?.zones||[];
 const fail=s=>errors.push(s);
 if(metadata.seed!==20261121 || manifest.seed!==metadata.seed)fail("World/scenery source seed mismatch");
 if(gateZones.length!==102||reservations.source_pr!==10||reservations.world_graph_blob_sha1!==manifest.sources.road_git_blob||metrics.source_race_exclusion_zones!==102)fail("Race PR #10 exclusion reservation snapshot mismatches");
 if(metadata.coordinate_system!=="godot_y_up"||manifest.coordinate_system!=="godot_y_up")fail("Coordinate convention mismatch");
 if(terrain.length!==502002)fail("R16 bytes must contain exactly 501x501 LE uint16 samples");
 if(graph.lanes.length!==104||graph.roads.length!==27)fail("Authoritative road graph changed");
 const W=501, step=4,origin=-1000,level=Number(mask.water_height_m);
 const get=(x,z)=>{const i=Math.max(0,Math.min(500,Math.round((x+1000)/4))),j=Math.max(0,Math.min(500,Math.round((z+1000)/4))),o=(j*W+i)*2;return (terrain[o]|terrain[o+1]<<8)/100};
 function surf(x,z){
  const gx=Math.max(0,Math.min(500,(x-origin)/step)),gz=Math.max(0,Math.min(500,(z-origin)/step));
  const i=Math.min(499,Math.floor(gx)),j=Math.min(499,Math.floor(gz)),u=gx-i,v=gz-j,xi=origin+i*step,zj=origin+j*step;
  const a=get(xi,zj),b=get(xi+step,zj),c=get(xi,zj+step),d=get(xi+step,zj+step);
  return u+v<=1?a+(b-a)*u+(c-a)*v:d+(c-d)*(1-u)+(b-d)*(1-v);
 }
 const physical=graph.lanes.filter(l=>l.id.startsWith("lane_")&&l.id.endsWith("_ab"));
 const turning=graph.lanes.filter(l=>l.id.startsWith("turn_"));
 if(physical.length!==16||turning.length!==72)fail("Physical road/turn count differs from expected 16/72");
 const segments=(lanes)=>lanes.flatMap(l=>l.points.slice(1).map((p,i)=>[l.points[i],p]));
 const physSegments=segments(graph.lanes.filter(l=>l.id.startsWith("lane_")));
 const turnSegments=segments(turning);
 const centers=physical.map(l=>{const b=graph.lanes.find(q=>q.id==="lane_"+l.road_id+"_ba");return {id:l.road_id,points:l.points.map((p,i)=>[(p[0]+b.points[b.points.length-1-i][0])/2,(p[2]+b.points[b.points.length-1-i][2])/2])};});
 const centerSegments=centers.flatMap(c=>c.points.slice(1).map((p,i)=>[c.points[i],p]));
 const junctions=[];
 for(const c of centers)for(const p of [c.points[0],c.points.at(-1)])if(!junctions.some(q=>Math.hypot(p[0]-q[0],p[1]-q[1])<20))junctions.push(p);
 const closest=(x,z,segs,already2D=false)=>{
  let best=Infinity;
  for(const [a,b] of segs){const ax=a[0],az=already2D?a[1]:a[2],dx=b[0]-ax,dz=(already2D?b[1]:b[2])-az;
   const t=Math.max(0,Math.min(1,((x-ax)*dx+(z-az)*dz)/Math.max(1e-10,dx*dx+dz*dz)));
   const d2=(x-ax-t*dx)**2+(z-az-t*dz)**2;if(d2<best)best=d2;}
  return Math.sqrt(best);
 };
 const packsByRegion=Object.fromEntries(packs.map(p=>[p.region,p]));
 let total=0,maxHeightMismatch=0,minPhysical=Infinity,minTurn=Infinity,maxFootRelief=0,foundationCount=0;
 const allIDs=new Set(),allWorldPositions=[],landmarks=[],minDrawBatches=new Set();
 const byRegion={},surfacesByRegion={};
 for(const r of metadata.regions){
  const p=packsByRegion[r.id];if(!p){fail("Missing pack "+r.id);continue;}
  const expected=manifest.region_packs.find(q=>q.id===r.id);
  if(!expected||p.placements.length!==expected.count)fail("Pack/manifest count mismatch "+r.id);
  byRegion[r.id]=p.placements.length;const batchSet=new Set();
  if(p.placements.length<140)fail("Region appears under-dressed: "+r.id);
  for(const item of p.placements){
   total++;if(allIDs.has(item.id))fail("Duplicate placement id "+item.id);allIDs.add(item.id);
   const def=manifest.assets[item.asset];if(!def){fail("Unknown asset "+item.asset);continue;}
   const [x,y,z]=item.position,scale=item.scale;
   if(![x,y,z,scale,item.yaw_deg].every(Number.isFinite)||scale<=0||scale>3.5){fail("Invalid transform "+item.id);continue}
   if(x<-988||x>988||z<-988||z>988)fail("Out-of-bounds "+item.id);
   if(item.district!=="old_quarry" && Math.hypot(x-r.center[0],z-r.center[1])>r.radius_m*.981)fail("Wrong region "+item.id);
   for(const gate of gateZones)if(Math.hypot(x-gate.x,z-gate.z)<gate.radius_m+def.r*scale+reservations.clearance_margin_m-.005)fail("Race gate clearance "+item.id+" at "+gate.id);
   const surfaceY=surf(x,z),error=Math.abs(y-(surfaceY+Number(item.terrain_offset_m)));
   maxHeightMismatch=Math.max(maxHeightMismatch,error);
   if(error>0.015)fail("Floating/underground pivot "+item.id+" delta="+error);
   const aspect=Math.atan(Math.hypot(surf(x+4,z)-surf(x-4,z),surf(x,z+4)-surf(x,z-4))/8)*180/Math.PI;
   if(aspect>def.slope+.05)fail("Excessive slope "+item.id+" "+aspect);
   if(Math.abs(aspect-item.slope_deg)>.12)fail("Slope metadata differs "+item.id);
   const phys=closest(x,z,physSegments),turn=closest(x,z,turnSegments),center=closest(x,z,centerSegments,true);
   minPhysical=Math.min(minPhysical,phys);minTurn=Math.min(minTurn,turn);
   if(phys<def.road-3.55)fail("Travel lane clearance "+item.id+" "+phys);
   if(turn<def.turn-.15)fail("Turn pad clearance "+item.id+" "+turn);
   // Physical deck extends approximately 4.75 m either side of centerline.
   if(center < 4.75+def.r*scale-.5)fail("Road mesh footprint collision "+item.id+" "+center);
   const jun=Math.min(...junctions.map(p=>Math.hypot(x-p[0],z-p[1])));
   if(jun<Math.max(27,def.r+20)-.1)fail("Wide junction pad clearance "+item.id);
   if(r.id==="eastwater_lake"&&item.asset!=="pier"&&surfaceY<level+1.8-.01)fail("Underwater scenery "+item.id);
   if(def.kind==="architecture"||def.kind==="landmark"){
    foundationCount++;
    const rad=def.r*scale;
    let relief=0;
    for(const [u,v] of [[rad,0],[-rad,0],[0,rad],[0,-rad],[rad*.7,rad*.7],[-rad*.7,-rad*.7],[rad*.7,-rad*.7],[-rad*.7,rad*.7]])
     relief=Math.max(relief,Math.abs(surf(x+u,z+v)-surfaceY));
    maxFootRelief=Math.max(maxFootRelief,relief);
    const limit=item.asset==="house"?1.2:item.asset==="barn"?1.5:item.asset==="garage"?1.5:item.asset==="windmill"?2:item.asset==="arch"?2.05:item.asset==="quarry"?2.5:item.asset==="pier"?3.6:1.5;
    if(relief>limit+.02)fail("Foundation relief above bound "+item.id+" "+relief);
   }
   if(item.tag==="landmark")landmarks.push(item.asset);
   allWorldPositions.push(item.position);
   batchSet.add(Math.floor(x/128)+","+Math.floor(z/128)+"|"+item.asset);
  }
  const surfCount=[...batchSet].reduce((a,k)=>a+manifest.assets[k.split("|")[1]].surfaces,0);
  surfacesByRegion[r.id]=surfCount;for(const k of batchSet)minDrawBatches.add(k);
  if(metrics.regions[r.id].count!==byRegion[r.id])fail("Metrics region total mismatches");
  if(metrics.regions[r.id].near_mesh_component_draw_batches_estimate!==surfCount)fail("Mesh surface estimates not reproducible "+r.id);
 }
 if(total!==manifest.region_packs.reduce((s,p)=>s+p.count,0)||total!==metrics.total_objects)fail("Total object count wrong");
 if(landmarks.length!==6||new Set(landmarks).size!==6)fail("Not exactly six original landmark scenes");
 const expectedLandmarks=["garage","arch","overlook","windmill","pier","quarry"];
 for(const l of expectedLandmarks)if(!landmarks.includes(l))fail("Missing landmark "+l);
 // Connected lake mask: check every water quad's four real terrain corners and region window.
 let maxSubmergedTerrain=-Infinity;
 const unique=new Set();
 for(const cell of mask.cells){const [i,j]=cell,k=i+","+j;if(unique.has(k))fail("Duplicate lake cell "+k);unique.add(k);
  if(i<375||i>=500||j<311||j>=500)fail("Water outside approved low basin "+k);
  for(const [u,v] of [[0,0],[1,0],[0,1],[1,1]])maxSubmergedTerrain=Math.max(maxSubmergedTerrain,get(-1000+(i+u)*4,-1000+(j+v)*4));
 }
 if(maxSubmergedTerrain>level+.00001)fail("Water plane over dry high terrain");
 if(mask.cells.length!==metrics.lake.quads||metrics.lake.triangles!==mask.cells.length*2)fail("Lake mesh metrics mismatch");
 if(Math.abs(level-5.35)>1e-8||Math.abs(metadata.heightfield.min_height_m-5)>1e-8)fail("Unapproved lake elevation");
 const estimatedBatches=[...minDrawBatches].reduce((sum,key)=>sum+manifest.assets[key.split("|")[1]].surfaces,0);
 if(estimatedBatches!==metrics.full_world_near_mesh_component_draw_batches_estimate)fail("Global surface batch mismatch");
 report.total_objects=total;report.regions=byRegion;report.model_surface_batches_all_cells=estimatedBatches;
 report.water_quads=mask.cells.length;report.height_error_max_m=maxHeightMismatch;report.maximum_architecture_foot_relief_m=maxFootRelief;
 report.landmarks=landmarks;report.physical_corridors=physical.length;report.turn_paths=turning.length;report.junctions=junctions.length;
 report.minimum_distance_any_object_to_lane_m=minPhysical;report.minimum_distance_any_object_to_turn_m=minTurn;
 report.foundation_count=foundationCount;report.estimated_multimesh_transform_bytes=total*64;report.verified_race_exclusion_zones=gateZones.length;
 report.warnings=warnings;report.errors=errors;
 return report;
}
// CLI ENTRY
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import {fileURLToPath} from "node:url";
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"../../..");
const world=process.argv[2]&& !process.argv[2].startsWith("--")?process.argv[2]:path.join(root,"data/world");
const json=p=>JSON.parse(fs.readFileSync(path.join(root,p),"utf8"));
const metadata=JSON.parse(fs.readFileSync(path.join(world,"world_metadata_v1.json"),"utf8"));
const graph=JSON.parse(fs.readFileSync(path.join(world,"road_graph_v1.json"),"utf8"));
const terrain=fs.readFileSync(path.join(world,"terrain_height_r16le.bin"));
const manifest=json("content/scenery/manifest.json"),metrics=json("content/scenery/metrics.json");
const paths=manifest.region_packs.map(r=>r.path),packs=paths.map(json);
const mask=json("content/scenery/lake/water_cells_v1.json");
const reservations=json("content/scenery/avoidance/race_gate_reservations_v1.json");
const sha=data=>crypto.createHash("sha1").update(Buffer.from("blob "+data.length+"\0")).update(data).digest("hex");
if(sha(terrain)!==manifest.sources.terrain_git_blob||sha(fs.readFileSync(path.join(world,"road_graph_v1.json")))!==manifest.sources.road_git_blob){
 console.error("FAIL: staged World PR #3 blob SHA does not match pinned authoritative data");process.exit(1);
}
const result=validate(metadata,graph,terrain,manifest,packs,mask,metrics,reservations);
console.log(JSON.stringify(result,null,2));
if(result.errors.length)process.exit(1);
console.log("PASS scenery: source geometry, collision-clearance, slope, foundations, water mask, landmarks and draw budgets");
