#!/usr/bin/env node
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {makeWorld,validateWorld,GRID,SEED}=require('../generate.js');
const ROOT=path.resolve(__dirname,'../..');
function run(){
 const a=makeWorld(),b=makeWorld(),result=validateWorld(a);
 assert.deepEqual(result.errors,[],'world graph/geometry validation');
 assert.deepEqual(a.graph,b.graph,'deterministic graph');
 assert.deepEqual(a.metadata,b.metadata,'deterministic metadata');
 assert.deepEqual(a.terrain.values,b.terrain.values,'deterministic heightfield');
 const load=p=>fs.readFileSync(path.join(ROOT,p));
 assert.deepEqual(JSON.parse(load('data/world/road_graph_v1.json')),a.graph,'committed road graph stale');
 assert.deepEqual(JSON.parse(load('data/world/world_metadata_v1.json')),a.metadata,'committed world metadata stale');
 const raw=load('data/world/terrain_height_r16le.bin');
 assert.equal(raw.length,GRID*GRID*2,'binary size');
 for(let i=0;i<a.terrain.values.length;i++)assert.equal(raw.readUInt16LE(i*2),a.terrain.values[i],'terrain sample '+i);
 for(let name of ['topographic_map.svg','road_network.svg'])assert.match(load('worldgen/previews/'+name).toString(),/<svg/,'SVG missing');
 assert.equal(a.metadata.seed,SEED);
 assert.ok(result.stats.min_turn_radius_m>=7,'sampled connector turning radius');
 console.log(JSON.stringify({passed:true,tests:['schema and IDs','bounds','point spacing','grades','minimum curve radius','lane end joins','turn headings','directed strongly connected graph','touring loop and alternative','lane/terrain separation','5 regions, landmarks','8-12km unique length','heightfield dimensions','deterministic regeneration','committed JSON and R16 bytes','SVG previews'],stats:result.stats},null,2));
}
if(require.main===module)run();
module.exports={run};
