#!/usr/bin/env node
"use strict";
// CLI: node content/traffic/tests/validate_content.js /path/to/road_graph_v1.json
// No npm packages. The canonical graph remains owned by World PR #3.
const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");

const ROOT = path.resolve(__dirname, "../../..");
const PACK = path.resolve(__dirname, "../controls_v1.json");
const SCENARIOS = path.resolve(__dirname, "../scenarios_v1.json");
const SVG = path.resolve(__dirname, "../previews/traffic_controls.svg");
const AUDIT = path.resolve(__dirname, "../conflict_audit_v1.json");
const EXPECTED_BLOB = "9bba378d68879df3baed2c97a4885c0adde88406";
const raw = (p) => JSON.parse(fs.readFileSync(p, "utf8"));
const keys = (xs) => new Set(xs);
const close = (a,b) => Math.hypot(a[0]-b[0],a[1]-b[1],a[2]-b[2]);
function distance(lane) {
  let total = 0;
  for (let i = 1; i < lane.points.length; i++) total += close(lane.points[i-1],lane.points[i]);
  return total;
}
function same(a,b) {
  return a.length === b.length && keys(a).size === a.length && a.every(id => b.includes(id));
}
function lastCross(a,b) {
  let largest = -1, sa = 0;
  const cross2=(p,q)=>p[0]*q[1]-p[1]*q[0];
  for(let i=1;i<a.points.length;i++) {
    const p=a.points[i-1],q=a.points[i],u=[q[0]-p[0],q[2]-p[2]];
    const la=close(p,q);let sb=0;
    for(let j=1;j<b.points.length;j++){
      const r=b.points[j-1],t=b.points[j],v=[t[0]-r[0],t[2]-r[2]],lb=close(r,t);
      const d=cross2(u,v);
      if(Math.abs(d)>1e-8){
        const off=[r[0]-p[0],r[2]-p[2]],x=cross2(off,v)/d,y=cross2(off,u)/d;
        if(x>=0&&x<=1&&y>=0&&y<=1){
          const ha=p[1]+x*(q[1]-p[1]),hb=r[1]+y*(t[1]-r[1]);
          if(Math.abs(ha-hb)<=2.5)largest=Math.max(largest,sa+x*la,sb+y*lb);
        }
      }
      sb+=lb;
    }
    sa+=la;
  }
  return largest;
}

function verify(g, pack, scenarios) {
  const check = (ok,message) => assert.ok(ok,message);
  check(g.schema_version===1 && g.units==="meters" && g.coordinate_system==="godot_y_up","graph v1");
  check(pack.schema_version===1 && scenarios.schema_version===1,"content schema");
  check(pack.source_graph.git_blob_sha===EXPECTED_BLOB && scenarios.graph_git_blob_sha===EXPECTED_BLOB,"graph provenance");
  const lanes = new Map(g.lanes.map(l=>[l.id,l]));
  const roads = new Map(g.roads.map(r=>[r.id,r]));
  check(lanes.size===104 && roads.size===27,"104 lanes / 27 records");
  check(g.roads.filter(r=>!r.id.startsWith("junction_")).length===16,"16 physical corridors");
  check(g.roads.filter(r=>r.id.startsWith("junction_")).length===11,"11 real junctions");
  check(g.lanes.filter(l=>l.id.startsWith("turn_")).length===72,"72 turn connectors");
  const predecessor = new Map();
  for (const lane of g.lanes) {
    check(roads.has(lane.road_id) && lane.points.length>=2,"valid lane road/geometry "+lane.id);
    check(lane.width_m>0 && lane.speed_limit_kph>=0,"lane dimensions/speed "+lane.id);
    for(let i=1;i<lane.points.length;i++) check(close(lane.points[i-1],lane.points[i])>.05,"no duplicate points "+lane.id);
    for(const next of lane.next_lane_ids) {
      check(lanes.has(next),"all successors defined "+lane.id);
      if(!predecessor.has(next))predecessor.set(next,[]);
      predecessor.get(next).push(lane.id);
    }
  }
  for (const lane of g.lanes) for (const next of lane.next_lane_ids) {
    const target = lanes.get(next);
    check(close(lane.points.at(-1),target.points[0])<=3.5,"directed links join "+lane.id);
    const a=lane.points.at(-1),b=lane.points.at(-2),c=target.points[1],d=target.points[0];
    const u=a.map((v,i)=>v-b[i]),v=c.map((x,i)=>x-d[i]);
    const dot=u.reduce((s,x,i)=>s+x*v[i],0)/(Math.hypot(...u)*Math.hypot(...v));
    check(dot >= -0.35,"no wrong-way link "+lane.id);
  }
  const seenNode = new Set(), seenTurn = new Set(), seenIncoming = new Set(), modes={};
  let controlledApproaches=0;
  for(const j of pack.junctions) {
    check(!seenNode.has(j.id) && roads.has(j.id) && j.id.startsWith("junction_"),"unique known junction "+j.id);
    seenNode.add(j.id);
    check(["stop","yield","pass_through"].includes(j.mode),"supported controls only "+j.id);
    modes[j.mode]=(modes[j.mode]||0)+1;
    check(same(j.turn_lane_ids,roads.get(j.id).lane_ids),"full turn inventory "+j.id);
    check(keys(j.incoming_lane_ids).size===j.incoming_lane_ids.length,"unique approach list "+j.id);
    check(keys(j.outgoing_lane_ids).size===j.outgoing_lane_ids.length,"unique departure list "+j.id);
    let inbound=new Set(),outbound=new Set(),shortest=Infinity;
    for (const turnId of j.turn_lane_ids) {
      check(!seenTurn.has(turnId) && lanes.has(turnId),"unique existing turn "+turnId);
      seenTurn.add(turnId);
      const lane=lanes.get(turnId);
      check(lane.road_id===j.id && lane.next_lane_ids.length===1,"turn assigned to right node "+turnId);
      shortest=Math.min(shortest,distance(lane));
      const parents=predecessor.get(turnId)||[];
      check(parents.length===1 && !parents[0].startsWith("turn_"),"reachable physical approach "+turnId);
      inbound.add(parents[0]);
      const destination=lane.next_lane_ids[0];
      check(!destination.startsWith("turn_"),"turn successor is travel lane "+turnId);
      outbound.add(destination);
    }
    check(same(j.incoming_lane_ids,[...inbound]) && same(j.outgoing_lane_ids,[...outbound]),"derived inbound/outbound matches "+j.id);
    for(const id of j.incoming_lane_ids) {
      check(!seenIncoming.has(id) && lanes.has(id),"unique valid incoming travel lane "+id);
      seenIncoming.add(id);
      check(lanes.get(id).next_lane_ids.every(x=>j.turn_lane_ids.includes(x)),"incoming only reaches matching junction "+id);
    }
    const last = j.incoming_lane_ids.length===2 && j.turn_lane_ids.length===2 ?
      lastCross(lanes.get(j.turn_lane_ids[0]),lanes.get(j.turn_lane_ids[1])) : -1;
    if(j.mode==="pass_through") {
      check(j.incoming_lane_ids.length===2 && j.turn_lane_ids.length===2 && last<0,"no control on non-crossing two-way continuation "+j.id);
    } else {
      // Degree in the coarse road graph is not a geometric intersection test.
      // Exactly two incoming travel lanes may still have crossed turn paths.
      if(j.incoming_lane_ids.length===2)check(j.turn_lane_ids.length===2 && last>=0 && j.clearance_m>last+1.5,"two-way crossing requires late release "+j.id);
      else check(j.incoming_lane_ids.length>=3,"controlled junction must have multi-approach topology or actual turn crossing "+j.id);
      controlledApproaches+=j.incoming_lane_ids.length;
      check(j.incoming_lane_ids.length>=2 && j.turn_lane_ids.length>=2,"valid controlled junction "+j.id);
      check(Number.isFinite(j.clearance_m) && j.clearance_m>=4 && j.clearance_m+0.5<shortest,"reservation will release on every turn "+j.id);
      if(j.mode==="stop")check(Number.isFinite(j.stop_s) && j.stop_s>0,"stop dwell "+j.id);
    }
  }
  check(pack.junctions.length===11 && seenNode.size===11 && seenTurn.size===72 && seenIncoming.size===32,"all nodes/turns/travel lanes covered");
  check(modes.stop===3 && modes.yield===5 && modes.pass_through===3 && controlledApproaches===26,"3 stop,5 yield,3 continuations,26 controlled approaches");
  const merges=[...predecessor.entries()].filter(([,src])=>src.length>1);
  check(merges.length===22 && merges.every(([,src])=>src.every(id=>id.startsWith("turn_"))),"implicit merge controls remain disjoint");
  check(scenarios.regions.length===5 && same(scenarios.populations,[0,5,10,20]),"5 regions and density matrix");
  check(scenarios.hotspots.length===2 && scenarios.hotspots.every(h=>["junction_overlook","junction_orchard"].includes(h.junction_id) && same(h.populations,[5,20])),"two crossing two-way stress sites");
  check(scenarios.seeds.length===3 && keys(scenarios.seeds).size===3 && scenarios.duration_s===90,"fixed seeds and 90-second soak");
  check(scenarios.regions.every(r=>pack.junctions.some(j=>j.id===r.junction_id) && r.view_position.length===3),"viewer coordinates derived from real nodes");
  return {nodes:11,controlled:8,implicitMerges:merges.length,approaches:controlledApproaches,cases:5*4*3+2*2*3};
}

function testRejections(graph,original,scenarios) {
  let rejected=0;
  const mutation=(description,change,changeGraph=false) => {
    const copy=structuredClone(original),g=structuredClone(graph);
    change(changeGraph?g:copy);
    assert.throws(()=>verify(g,copy,scenarios),assert.AssertionError,description);
    rejected++;
  };
  mutation("duplicated junction",p=>p.junctions.push(structuredClone(p.junctions[0])));
  mutation("bogus inbound",p=>p.junctions[0].incoming_lane_ids[0]="not_a_lane");
  mutation("duplicated incoming",p=>p.junctions[0].incoming_lane_ids[1]=p.junctions[0].incoming_lane_ids[0]);
  mutation("missing turn",p=>p.junctions[0].turn_lane_ids.pop());
  mutation("nonexistent turn",p=>p.junctions[0].turn_lane_ids[0]="turn_missing");
  mutation("wrong destination",p=>p.junctions[0].outgoing_lane_ids[0]="lane_wrong");
  mutation("signal unsupported",p=>p.junctions[0].mode="signal");
  mutation("non-releasing reservation",p=>p.junctions[0].clearance_m=99);
  mutation("zero stop dwell",p=>p.junctions[0].stop_s=0);
  mutation("unreachable turn",g=>{ const id=original.junctions[0].turn_lane_ids[0];for(const l of g.lanes)l.next_lane_ids=l.next_lane_ids.filter(x=>x!==id);},true);
  mutation("duplicate travel source",p=>p.junctions[1].incoming_lane_ids[0]=p.junctions[0].incoming_lane_ids[0]);
  mutation("uncontrolled crossing",p=>p.junctions.find(j=>j.id==="junction_overlook").mode="pass_through");
  mutation("premature two-way crossing clearance",p=>p.junctions.find(j=>j.id==="junction_orchard").clearance_m=6);
  mutation("unnecessary control on non-crossing degree-two continuation",p=>{
    const j=p.junctions.find(x=>x.id==="junction_market");
    j.mode="yield"; j.clearance_m=6;
  });
  return rejected;
}

if (require.main===module) {
  const graphPath=path.resolve(process.argv[2]||path.join(ROOT,"data/world/road_graph_v1.json"));
  if(!fs.existsSync(graphPath)) {
    console.error("Canonical World PR #3 graph not found: "+graphPath);
    console.error("Supply a temporary export path as the first argument; do not copy the world graph into content/traffic.");
    process.exit(2);
  }
  const graph=raw(graphPath),pack=raw(PACK),scenarios=raw(SCENARIOS);
  const summary=verify(graph,pack,scenarios);
  const rejected=testRejections(graph,pack,scenarios);
  const audit=raw(AUDIT);
  assert.equal(audit.source_graph_git_blob_sha,EXPECTED_BLOB);
  assert.equal(audit.nodes.length,11);
  assert.ok(audit.nodes.filter(j=>j.mode==="pass_through").every(j=>j.turn_pairs_crossing===0));
  assert.ok(audit.nodes.filter(j=>["junction_overlook","junction_orchard"].includes(j.junction_id)).every(j=>j.turn_pairs_with_crossing_after_release===0));
  const laneIndex=new Map(graph.lanes.map(l=>[l.id,l]));
  const audited=new Map(audit.nodes.map(j=>[j.junction_id,j]));
  assert.equal(audited.size,11,"one independent audit per real node");
  for(const j of pack.junctions){
    const item=audited.get(j.id);
    assert.ok(item && item.mode===j.mode,"conflict audit mode matches live control "+j.id);
    assert.equal(item.clearance_m,j.mode==="pass_through"?null:j.clearance_m,"audit release matches "+j.id);
    if(j.incoming_lane_ids.length===2 && j.turn_lane_ids.length===2){
      const crossing=lastCross(laneIndex.get(j.turn_lane_ids[0]),laneIndex.get(j.turn_lane_ids[1]));
      assert.equal(crossing>=0,item.turn_pairs_crossing>0,"degree-two audited crossing matches real geometry "+j.id);
      assert.ok(Math.abs(Math.max(0,crossing)-item.furthest_crossing_arc_s_m)<0.1,"measured crossing arc matches audit "+j.id);
    }
  }
  const svg=fs.readFileSync(SVG,"utf8");
  assert.ok(svg.includes("ASTER VALLEY")&&svg.includes(EXPECTED_BLOB.slice(0,10)),"real-graph preview provenance");
  console.log("PASS canonical topology/content authoring, "+rejected+" negative mutations, preview marker");
  console.log(JSON.stringify(summary,null,2));
}
module.exports={verify,testRejections};
