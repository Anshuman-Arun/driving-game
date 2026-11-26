// Executes a restricted, explicitly translated subset of the committed pure integer GDScript.
// This is source-level numerical verification, NOT a Godot parser, runtime or shader test.
import fs from "node:fs";
function translate(source){
  // Intentionally restricted syntax. Fail on unfamiliar constructs instead of silently ignoring them.
  const out=["'use strict';","const mini=Math.min,maxi=Math.max,floori=Math.floor,float=Number,int=Math.trunc;"];
  let depth=0;
  const names=[];
  for(const raw of source.split("\n")){
    const clean=raw.split("#")[0].trimEnd();
    if(!clean.trim()||clean==="extends RefCounted")continue;
    const indent=clean.match(/^\t*/)[0].length;
    const line=clean.trim();
    while(depth>indent){out.push("}");depth--;}
    let m;
    if(m=line.match(/^const (\w+) := ([\d,\s\[\]]+)$/)){out.push(`const ${m[1]}=${m[2]};`);continue;}
    if(m=line.match(/^static func (\w+)\((.*)\) -> (?:int|float|Array):$/)){
      const params=m[2].split(",").map(p=>p.trim().match(/^(\w+): (int|float|Array)$/)?.[1]);
      if(params.some(p=>!p))throw Error("unknown parameter "+line);
      names.push(m[1]);out.push(`function ${m[1]}(${params.join(",")}){`);depth++;continue;
    }
    if(m=line.match(/^for (\w+) in range\((\d+)\):$/)){out.push(`for(let ${m[1]}=0;${m[1]}<${m[2]};${m[1]}++){`);depth++;continue;}
    if(m=line.match(/^if (.*):$/)){out.push(`if(${m[1]}){`);depth++;continue;}
    if(m=line.match(/^var (\w+): (?:int|float|Array) = (.+)$/)){out.push(`let ${m[1]}=${m[2]};`);continue;}
    if(/^return .+$/.test(line)||/^[\w\[\]]+ (?:=|\+=|-=) .+$/.test(line)){out.push(line+";");continue;}
    throw Error("unsupported GDScript numeric syntax: "+line);
  }
  while(depth>0){out.push("}");depth--;}
  out.push(`return {${names.join(",")}};`);
  return out.join("\n");
}
function verify(source,profiles){
  const math=new Function(translate(source))();
  let cases=0,checks=0;
  const assert=(condition,message)=>{checks++;if(!condition)throw Error(message);};
  for(const p of Object.values(profiles)){
    for(const near of [0,1,4,12,80])for(const mid of [0,1,20,68])for(const far of [0,1,56,240]){
      for(const cap of [1,2,3,31,63,64,999,12000,p.cap]){
        for(const chunks of [1,2,3,12,p.chunks]){
          for(const density of [p.density.map(d=>Math.ceil(d*4096)),[0,0,0],[100,0,0],[0,0,1],[2,2,2]]){
            const tiers=[near,mid,far];
            const [selected,limits]=math.allocate(tiers,density,cap,chunks,p.upload_instances);
            const reserved=selected.reduce((a,n,i)=>a+n*limits[i],0);
            assert(reserved<=cap,"reservation");
            assert(selected.reduce((a,b)=>a+b,0)<=Math.min(cap,chunks),"chunk cap");
            let previous=4096;
            for(let i=0;i<3;i++){
              assert(Number.isInteger(selected[i])&&selected[i]>=0&&selected[i]<=tiers[i],"selected");
              assert(Number.isInteger(limits[i])&&limits[i]>=0&&limits[i]<=Math.min(density[i],p.upload_instances),"quota");
              assert((selected[i]>0)===(limits[i]>0),"nonzero chunk quota");
              if(selected[i]){assert(limits[i]<=previous,"nested quota");previous=limits[i];}
            }
            if(tiers.some((n,i)=>n>0&&density[i]>0))assert(reserved>0,"nonempty feasible allocation");
            if(cap>=3&&chunks>=3&&tiers.every(n=>n>0)&&density.every(n=>n>0))assert(selected.every(n=>n>0),"all tiers represented");
            cases++;
          }
        }
      }
    }
  }
  let permutations=0;
  for(const seed of [-2147483648,-1,0,1,20261125,2147483647])for(const x of [-63,-17,0,62])for(const z of [-63,0,62]){
    const seen=new Set(), bins=Array(16).fill(0);
    let mean=0;
    for(let rank=0;rank<4096;rank++){
      const idx=math.rank_index(x,z,rank,seed);
      assert(idx>=0&&idx<4096&&!seen.has(idx),"bijection");seen.add(idx);
      if(rank<256)bins[((idx>>6)>>4)*4+((idx&63)>>4)]++;
      const random=math.unit_random(x,z,idx,seed,11);
      assert(random>=0&&random<1,"random interval");
      mean+=random;
    }
    assert(bins.every(n=>n>=2&&n<=40),"rank prefix spatial distribution "+bins);
    assert(Math.abs(mean/4096-.5)<.035,"mean random distribution");
    permutations++;
  }
  return {cases,permutations,checks,summary:Object.fromEntries(Object.entries(profiles).map(([name,p])=>[name,math.allocate(name==="low"?[4,20,56]:name==="medium"?[4,48,156]:[12,68,196],p.density.map(d=>Math.ceil(d*4096)),p.cap,p.chunks,p.upload_instances)]))};
}
const source=fs.readFileSync(new URL("../placement_math.gd",import.meta.url),"utf8");
const runtime=fs.readFileSync(new URL("../ground_cover.gd",import.meta.url),"utf8");
const profiles=JSON.parse(runtime.match(/const PROFILES := (\{[\s\S]*?\n\})/)[1]);
console.log(JSON.stringify(verify(source,profiles),null,2));
