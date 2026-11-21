'use strict';
const assert=require('node:assert/strict');
const {makeWorld,validateWorld}=require('../generate.js');
const {makeTurn,radius}=require('../turn_geometry.js');
const {dubins}=require('../dubins.js');
const w=makeWorld(),report=validateWorld(w);
assert.deepEqual(report.errors,[],'generated graph must pass geometry validator');
const connectors=w.graph.lanes.filter(l=>l.id.startsWith('turn_'));
assert.equal(connectors.length,72);
let minimum=Infinity;
for(const lane of connectors){
 const r=radius(lane.points.map(p=>({x:p[0],z:p[2]})));
 minimum=Math.min(minimum,r);
 assert.ok(r>=7,'undrivable junction radius '+lane.id+' '+r);
}
assert.ok(report.stats.max_link_jump_m<.01);
assert.ok(report.stats.max_heading_jump_deg<15);
assert.ok(radius(makeTurn([[0,0,-5],[1,0,-5]],[[2,0,-3],[1,0,-3]]).points)>=7);
let state=20261121;
for(let i=0;i<200;i++){
 state=(Math.imul(state,1664525)+1013904223)>>>0;const x=(state%500-250)/10;
 state=(Math.imul(state,1664525)+1013904223)>>>0;const z=(state%500-250)/10;
 const start={x:0,z:0,yaw:2*Math.PI*i/200},
 end={x,z,yaw:2*Math.PI*((i*37)%200)/200},p=dubins(start,end,9,2);
 assert.ok(Math.hypot(p.points.at(-1).x-x,p.points.at(-1).z-z)<1e-5);
 assert.ok(radius(p.points)>=7);
}
console.log(JSON.stringify({passed:true,connectors:connectors.length,min_turn_radius_m:minimum,max_link_gap_m:report.stats.max_link_jump_m},null,2));
