// Numeric planning reference only; no engine or visual assertions.
import fs from "node:fs";
function runReference(profiles) {
  // Independent numeric reference; does NOT execute GDScript or validate renderer.
  const shares=[0.50,0.32,0.18];
  const assert=(condition,message)=>{if(!condition)throw Error(message)};
  function allocate(profile, tiers){
    let remaining=profile.chunks;
    const selected=[0,0,0];
    for(let i=0;i<3;i++){
      selected[i]=Math.min(remaining,tiers[i],Math.max(1,Math.floor(profile.chunks*shares[i])));
      remaining-=selected[i];
    }
    for(let i=0;i<3;i++){
      const extra=Math.min(remaining,tiers[i]-selected[i]);
      selected[i]+=extra;remaining-=extra;
    }
    remaining=profile.cap;
    const desired=selected.map((n,i)=>n*Math.ceil(4096*profile.density[i]));
    const allocation=desired.map((n,i)=>{
      const a=Math.min(n,remaining,Math.floor(profile.cap*shares[i]));
      remaining-=a;return a;
    });
    for(let i=0;i<3;i++){
      const extra=Math.min(remaining,desired[i]-allocation[i]);
      allocation[i]+=extra;remaining-=extra;
    }
    const limits=allocation.map((a,i)=>{
      if(!selected[i])return 0;
      let n=Math.min(profile.upload_instances,Math.floor(a/selected[i]));
      return n>=64?(n>>5)<<5:n;
    });
    return {selected,limits};
  }
  function count(profile,x,z,vx,vz){
    let tiers=[0,0,0];
    const [near,mid,far]=profile.radii;
    const px=x+vx*.65,pz=z+vz*.65;
    for(let i=Math.max(-63,Math.floor((Math.min(x,px)-far-16)/16));i<=Math.min(62,Math.floor((Math.max(x,px)+far+16)/16));i++)
      for(let j=Math.max(-63,Math.floor((Math.min(z,pz)-far-16)/16));j<=Math.min(62,Math.floor((Math.max(z,pz)+far+16)/16));j++){
        const cx=(i+.5)*16,cz=(j+.5)*16;
        const d=Math.hypot(cx-x,cz-z),pd=Math.hypot(cx-px,cz-pz);
        if(Math.min(d,pd)>far)continue;
        tiers[d<near?0:d<mid?1:2]++;
      }
    return tiers;
  }
  let cases=0,assertions=0;
  const summaries={};
  for(const [name,p] of Object.entries(profiles)){
    const center=allocate(p,count(p,0,0,0,0));
    summaries[name]={...center,reserved:center.selected.reduce((sum,n,i)=>sum+n*center.limits[i],0)};
    for(const cap of [1,32,1000,12000,p.cap]){
      for(const chunks of [1,3,12,p.chunks]){
        for(const x of [-999,-950,-17,0,7,15,63,975,999]){
          for(const z of [-999,-7,0,15,999]){
            for(const [vx,vz] of [[0,0],[80,0],[-45,50],[0,-80]]){
              const profile={...p,cap,chunks};
              const tiers=count(profile,x,z,vx,vz), {selected,limits}=allocate(profile,tiers);
              const reserved=selected.reduce((sum,n,i)=>sum+n*limits[i],0);
              assert(reserved<=cap,"candidate cap");
              assert(selected.reduce((a,b)=>a+b,0)<=chunks,"chunk cap");
              assert(selected.every((n,i)=>n>=0&&n<=tiers[i]),"selection bounds");
              assert(limits.every((n,i)=>n>=0&&n<=profile.upload_instances&&n<=Math.ceil(4096*p.density[i])),"upload and density bounds");
              if(cap>=12000&&chunks>=12&&Math.abs(x)<100&&Math.abs(z)<100){
                assert(selected.every(n=>n>0)&&limits.every(n=>n>0),"interior coverage");assertions++;
              }
              cases++;assertions+=4;
            }
          }
        }
      }
    }
  }
  return {cases,assertions,summaries};
}
const source=fs.readFileSync(new URL("../ground_cover.gd",import.meta.url),"utf8");
const profiles=JSON.parse(source.match(/const PROFILES := (\{[\s\S]*?\n\})/)[1]);
console.log(JSON.stringify(runReference(profiles),null,2));
