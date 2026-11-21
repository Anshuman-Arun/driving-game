"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs");
const path=require("node:path");
const crypto=require("node:crypto");
const {generate}=require("../author.js");
const graphPath=process.argv[2]||"data/world/road_graph_v1.json";
if(!fs.existsSync(graphPath))throw Error("Pass actual feat/worldgen road_graph_v1.json as first argument");
const raw=fs.readFileSync(graphPath);
const sha=crypto.createHash("sha1").update(Buffer.from("blob "+raw.length+"\0")).update(raw).digest("hex");
const original=JSON.parse(raw.toString("utf8"));
const build=generate(original,sha);
const bad=(label,mutator,hash=sha)=>{
 const mutated=structuredClone(original);
 mutator(mutated);
 assert.throws(()=>generate(mutated,hash),undefined,label);
 console.log("PASS: rejects "+label);
};
assert.equal(build.events.events.length,4);
for(const [file,generated] of Object.entries(build.files)){
 const actual=fs.readFileSync(path.join(__dirname,"..",file),"utf8");
 assert.equal(actual,generated,"generated artifact stale: "+file);
}
console.log("PASS: regenerated event catalog, report and 4 SVGs match committed files");
const byId=new Map(original.lanes.map(l=>[l.id,l]));
const R=e=>{
 const points=[];
 for(const id of e.lane_route){
  const l=byId.get(id);
  assert(l,"missing lane "+id);
  for(const p of l.points){
   if(points.length&&Math.hypot(...p.map((v,i)=>v-points.at(-1)[i]))<0.001)continue;
   points.push(p);
  }
 }
 return points;
};
const norm=(a,b)=>Math.hypot(a[0]-b[0],a[2]-b[2]);
const project=(points,p)=>{
 let best={distance:Infinity,s:-1},from=0;
 for(let j=0;j<points.length-1;j++){
  const a=points[j],b=points[j+1],dx=b[0]-a[0],dz=b[2]-a[2],d=dx*dx+dz*dz;
  assert(d>1e-6);
  const t=Math.max(0,Math.min(1,((p[0]-a[0])*dx+(p[2]-a[2])*dz)/d));
  const dist=Math.hypot(a[0]+t*dx-p[0],a[2]+t*dz-p[2]);
  if(dist<best.distance)best={distance:dist,s:from+Math.sqrt(d)*t};
  from+=Math.sqrt(d);
 }
 return {...best,fullLength:from};
};
const totals=[];
for(const e of build.events.events){
 assert.equal(e.laps,e.kind==="sprint"?1:e.laps);
 assert.equal(e.checkpoints.length,build.report.reports.find(r=>r.id===e.id).checkpoint_count);
 for(let j=0;j<e.lane_route.length-1;j++)assert(byId.get(e.lane_route[j]).next_lane_ids.includes(e.lane_route[j+1]),"non-directed adjacency");
 if(e.kind==="circuit")assert(byId.get(e.lane_route.at(-1)).next_lane_ids.includes(e.lane_route[0]),"circuit not closed");
 const pts=R(e),length=project(pts,pts.at(-1)).fullLength;
 assert(Math.abs(length-e.route_length_m)<0.003,"independent route length "+e.id);
 assert(Math.abs(length*e.laps-e.total_race_distance_m)<0.004,"total length "+e.id);
 let last=0,prevRad=0;
 for(const cp of e.checkpoints){
  const q=project(pts,cp.center);
  assert(q.distance<0.02,"gate off line "+cp.id);
  assert(q.s>last+prevRad+cp.radius_m+2&&q.s<length-4,"gate misordered "+cp.id);
  last=q.s;prevRad=cp.radius_m;
 }
 assert(last>length-195,"finish gate coverage "+e.id);
 assert(e.start_grid.length===4);
 let prior=-10;
 for(const car of e.start_grid){
  const q=project(pts,car.position);
  assert(q.distance<0.03&&q.s>=4&&q.s<=44&&q.s-prior>=9,"grid geometry "+car.id);
  prior=q.s;
 }
 assert(e.ai_speed_guidance.length>5);
 for(const tip of e.ai_speed_guidance){
  assert(byId.has(tip.lane_id),"AI lane ref");
  assert(tip.target_kph>0&&tip.target_kph<=tip.speed_limit_kph+0.001,"AI limit");
 }
 assert(build.report.reports.find(x=>x.id===e.id).pilot.invalid_progress===0,"progress pilot");
 totals.push(e.id+": "+length.toFixed(3)+"m, gates="+e.checkpoints.length);
}
bad("source hash mismatch",()=>{},"bad-hash");
bad("missing lane",g=>{g.lanes=g.lanes.filter(l=>l.id!=="lane_ridge_valley_ba")});
bad("duplicate point",g=>{const l=g.lanes.find(l=>l.id==="lane_alder_depot_ab");l.points[1]=l.points[0]});
bad("bad bounds",g=>{g.bounds.max_z=1200});
bad("broken directed successor",g=>{g.lanes.find(l=>l.id==="lane_valley_lake_ba").next_lane_ids=[]});
bad("removed connector destination",g=>{g.lanes.find(l=>l.id==="turn_chapel_depot_chapel_ab__chapel_alder_ab").next_lane_ids=[]});
console.log("PASS: independent lane, checkpoint, length, grid, AI, circuit checks");
console.log(totals.join("\n"));
