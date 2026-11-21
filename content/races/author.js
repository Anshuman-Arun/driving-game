"use strict";
// Aster Valley production race author/validator. Node.js 20+; built-in modules only.
// World graph is always read-only and pinned to the World Agent's verified Git blob.
const fs=require("node:fs"),path=require("node:path"),crypto=require("node:crypto");
function generate(g, blobSha) {
  "use strict";
  const assert=(ok,msg)=>{if(!ok)throw Error(msg)};
  const rnd=n=>Number(n.toFixed(3)), d2=(a,b)=>Math.hypot(a[0]-b[0],a[2]-b[2]);
  const d3=(a,b)=>Math.hypot(a[0]-b[0],a[1]-b[1],a[2]-b[2]);
  const isnum=n=>typeof n==="number"&&Number.isFinite(n);
  const PINSHA="9bba378d68879df3baed2c97a4885c0adde88406";
  assert(blobSha===PINSHA,"World graph blob differs from verified World PR #3: "+blobSha);
  assert(g.schema_version===1&&g.units==="meters"&&g.coordinate_system==="godot_y_up","Bad graph schema");
  assert(g.bounds.min_x===-1000&&g.bounds.max_x===1000&&g.bounds.min_z===-1000&&g.bounds.max_z===1000,"Unexpected graph bounds");
  const ids=new Map(), roads=new Map();
  for(const r of g.roads){assert(!roads.has(r.id),"duplicate road "+r.id);roads.set(r.id,r)}
  for(const l of g.lanes){
    assert(!ids.has(l.id),"duplicate lane "+l.id);
    assert(roads.has(l.road_id)&&Array.isArray(l.points)&&l.points.length>=2,"malformed lane "+l.id);
    assert(l.points.every(p=>p.length===3&&p.every(isnum)&&p[0]>=-1000&&p[0]<=1000&&p[2]>=-1000&&p[2]<=1000),"bad point "+l.id);
    assert(l.points.slice(1).every((p,i)=>d3(p,l.points[i])>0.001),"duplicate point "+l.id);
    assert(isnum(l.speed_limit_kph)&&l.speed_limit_kph>=0&&l.width_m>=3,"bad speed/width "+l.id);
    ids.set(l.id,l);
  }
  for(const l of g.lanes)for(const n of l.next_lane_ids){assert(ids.has(n),"unknown next lane "+n)}
  const settings=[
    {id:"alder_street_circuit",name:"Alder Street Circuit",kind:"circuit",laps:3,difficulty:"intermediate",description:"Town-block racing across High Street, Station Lane and Chapel Crescent, with tight junction approaches.",primary:["alder_depot_ab","depot_chapel_ab","chapel_alder_ab"],spacing:78,radius:5.5},
    {id:"north_ridge_climb",name:"North Ridge Climb",kind:"sprint",laps:1,difficulty:"advanced",description:"Unbroken lakeside-to-ridgeline uphill run into Serpentine Descent's switchbacks.",primary:["valley_lake_ba","ridge_valley_ba"],spacing:128,radius:6},
    {id:"eastwater_lakeside_sprint",name:"Eastwater Lakeside Sprint",kind:"sprint",laps:1,difficulty:"beginner",description:"Fast sweeping meadow and shoreline asphalt through the lake junction onto South Shore Parkway.",primary:["valley_lake_ab","lake_alder_ab"],spacing:130,radius:6},
    {id:"green_valley_tour",name:"Green Valley Tour",kind:"circuit",laps:1,difficulty:"expert",description:"Town-to-farm gravel, ridge climb, wooded descent and an Alder finish.",primary:["alder_market_ab","market_valley_ab","ridge_valley_ba","cedar_ridge_ba","alder_cedar_ba"],spacing:142,radius:6}
  ];
  const output=[],reports=[],svgFiles={}; const pilotResults=[];
  function getRoute(raw) {
    const all=[];
    for(let i=0;i<raw.primary.length;i++){
      const a="lane_"+raw.primary[i], b="lane_"+raw.primary[(i+1)%raw.primary.length];
      assert(ids.has(a),"Primary lane missing "+a);
      all.push(a);
      if(i+1<raw.primary.length||raw.kind==="circuit"){
        const transitions=ids.get(a).next_lane_ids.filter(t=>ids.get(t).next_lane_ids.includes(b));
        assert(transitions.length===1,"Expected one directed connector "+a+" -> "+b+", found "+transitions.length);
        all.push(transitions[0]);
      }
    }
    return all;
  }
  function shape(route,closed) {
    const points=[],segs=[];let len=0;
    for(let i=0;i<route.length;i++){
      const l=ids.get(route[i]); assert(!!l,"unknown "+route[i]);
      if(i>0) {
        const prev=ids.get(route[i-1]);
        assert(prev.next_lane_ids.includes(l.id),"undirected transition "+prev.id+" -> "+l.id);
        assert(d3(prev.points.at(-1),l.points[0])<=6,"separated connector "+prev.id);
        const v1=prev.points.at(-1).map((v,j)=>v-prev.points.at(-2)[j]);
        const v2=l.points[1].map((v,j)=>v-l.points[0][j]);
        assert((v1[0]*v2[0]+v1[2]*v2[2])/(Math.hypot(v1[0],v1[2])*Math.hypot(v2[0],v2[2]))>=-0.65,"bad heading "+l.id);
      }
      for(const p of l.points){
        if(points.length&&d3(points.at(-1),p)<0.001)continue;
        if(points.length){
          const a=points.at(-1),lenSeg=d2(a,p);
          assert(lenSeg>0.001,"zero-length XZ "+l.id);
          segs.push({a,b:p,s:len,len:lenSeg,lane:l.id,surface:l.surface,limit:l.speed_limit_kph});
          len+=lenSeg;
        }
        points.push(p);
      }
    }
    if(closed){
      const last=ids.get(route.at(-1)),first=ids.get(route[0]);
      assert(last.next_lane_ids.includes(first.id)&&d3(points.at(-1),points[0])<=6,"circuit not closed");
      const a=points.at(-1),b=points[0],dl=d2(a,b);
      if(dl>0.001){segs.push({a,b,s:len,len:dl,lane:first.id,surface:first.surface,limit:first.speed_limit_kph});len+=dl;points.push(b)}
    }
    assert(len>=40,"path too short");
    const sample=s=>{
      const v=closed?((s%len)+len)%len:Math.max(0,Math.min(len,s));
      let low=0,high=segs.length-1;
      while(low<high){const m=(low+high)>>1; if(segs[m].s+segs[m].len<v)low=m+1;else high=m}
      const t=segs[low],u=Math.max(0,Math.min(1,(v-t.s)/t.len));
      return {p:t.a.map((n,j)=>n+(t.b[j]-n)*u),seg:t,at:v};
    };
    const project=(p,hint=-1)=>{
      let best={score:Infinity};
      for(const seg of segs){
        const dx=seg.b[0]-seg.a[0],dz=seg.b[2]-seg.a[2],ss=dx*dx+dz*dz;
        const t=Math.max(0,Math.min(1,((p[0]-seg.a[0])*dx+(p[2]-seg.a[2])*dz)/ss));
        const cx=seg.a[0]+t*dx,cz=seg.a[2]+t*dz;
        const dist=Math.hypot(p[0]-cx,p[2]-cz);
        const s=seg.s+seg.len*t,sep=hint<0?0:closed?Math.min(Math.abs(s-hint),len-Math.abs(s-hint)):Math.abs(s-hint);
        const score=dist*dist+.001*sep*sep;
        if(score<best.score)best={s,dist,point:[cx,seg.a[1]+t*(seg.b[1]-seg.a[1]),cz],score};
      }
      return best;
    };
    return {route,points,segs,len,sample,project,closed};
  }
  function segPointDistXZ(a,b,p){
    const dx=b[0]-a[0],dz=b[2]-a[2];
    const t=Math.max(0,Math.min(1,((p[0]-a[0])*dx+(p[2]-a[2])*dz)/(dx*dx+dz*dz)));
    return Math.hypot(a[0]+dx*t-p[0],a[2]+dz*t-p[2]);
  }
  function uniqueGate(sh,s,radius) {
    const p=sh.sample(s).p, pr=sh.project(p);
    if(Math.abs(pr.s-s)>2.0||pr.dist>0.1)return false;
    // A second, distant portion of THIS course must not enter the gate.
    for(const seg of sh.segs){
      const sep=Math.abs((seg.s+seg.len/2)-s);
      const circular=sh.closed?Math.min(sep,sh.len-sep):sep;
      if(circular<45+seg.len/2)continue;
      if(segPointDistXZ(seg.a,seg.b,p)<radius+3)return false;
    }
    return true;
  }
  function checkEvent(ev,sh) {
    assert(ev.lane_route.length===sh.route.length&&ev.lane_route.every((v,i)=>v===sh.route[i]),"route reference mismatch");
    assert(ev.start_position.length===3&&d3(ev.start_position,sh.sample(0).p)<12,"start too far");
    assert(ev.laps===(ev.kind==="sprint"?1:ev.laps)&&ev.laps>=1,"bad lap count");
    let prevS=0,prevR=0;const gatePoints=[];
    for(const cp of ev.checkpoints){
      assert(cp.radius_m>=2&&cp.radius_m<=30,"bad radius");
      const p=sh.project(cp.center);
      assert(p.dist<=cp.radius_m,"checkpoint off route "+cp.id);
      assert(p.s>prevS+prevR+cp.radius_m+2&&p.s<sh.len-4,"unordered gate "+cp.id);
      assert(uniqueGate(sh,p.s,cp.radius_m),"possible cut through gate "+cp.id);
      prevS=p.s;prevR=cp.radius_m;gatePoints.push(p.s);
    }
    assert(gatePoints.length>=6&&gatePoints[0]<100&&sh.len-gatePoints.at(-1)<190,"insufficient endpoint coverage");
    assert(gatePoints.slice(1).every((s,i)=>s-gatePoints[i]<=215),"excessive gate gap");
    assert(ev.start_grid.length===4,"grid size");
    let prev=0;
    for(const car of ev.start_grid){
      const pos=car.position,pr=sh.project(pos);
      assert(pr.dist<.05&&pr.s>=4&&pr.s<=43,"grid off lane");
      assert(pr.s-prev>=8||prev===0,"grid overlaps");
      const first=ids.get(sh.route[0]);assert(d2(first.points[0],pos)<50,"grid not at first road");
      prev=pr.s;
    }
    assert(d3(ev.finish.position,sh.closed?sh.sample(0).p:sh.sample(sh.len).p)<0.05,"bad finish");
    return gatePoints;
  }
  function pilot(ev,sh,gateS){
    // Independent discrete walk applying RaceEngine's ordered swept gate and finish thresholds.
    const R=sh.len,N=ev.checkpoints.length,rad=ev.checkpoints.map(c=>c.radius_m);
    let progress=0,prevP=sh.sample(0).p,idx=0,lap=1,hits=0,violations=0;
    const deltaS=2.75;
    const total=R*ev.laps;
    for(let global=deltaS;global<total+deltaS+0.00001;global+=deltaS){
      const target=Math.min(total,global),loc=sh.closed?target%R:target,p=sh.sample(loc).p;
      const displacement=d3(prevP,p);
      if(displacement>90*(deltaS/17)+5){violations++;break}
      const projected=sh.project(p,sh.closed?progress%R:progress);
      let cont=projected.s;
      if(sh.closed)cont+=Math.round((progress-cont)/R)*R;
      const arc=cont-progress;
      if(Math.abs(arc)>displacement*1.7+3){violations++;break}
      if(arc>0.001){
        const old=progress;progress=Math.max(old,cont);
        let guard=0;
        while(idx<N){
          const s=(lap-1)*R+gateS[idx];
          if(progress<s-rad[idx]/2)break;
          const hit=segPointDistXZ(prevP,p,ev.checkpoints[idx].center)<=rad[idx];
          if(old<=s+rad[idx]&&hit){idx++;hits++}
          else{if(progress>s+rad[idx]+2)violations++;break}
          if(++guard>100)throw Error("pilot gate loop");
        }
        if(progress>=lap*R-2.5){
          if(idx!==N){violations++;break}
          if(lap===ev.laps)break;
          lap++;idx=0;
        }
      }
      prevP=p;
    }
    assert(violations===0&&lap===ev.laps&&idx===N&&hits===N*ev.laps&&progress>=total-3,"Engine-semantics pilot failed "+ev.id+": "+JSON.stringify({violations,lap,idx,hits,progress,total}));
    return {id:ev.id,simulated_distance_m:rnd(progress),completed_laps:lap,checkpoint_hits:hits,invalid_progress:violations};
  }
  function tangent(sh,s) {
    const u=sh.closed?s:Math.max(0,Math.min(sh.len,s)); const a=sh.sample(u-1.8).p,b=sh.sample(u+1.8).p;
    const dx=b[0]-a[0],dz=b[2]-a[2],m=Math.hypot(dx,dz);
    return [dx/m,0,dz/m];
  }
  function aiProfile(sh) {
    const profile=[];
    for(let s=0;s<=sh.len;s+=65){
      const c=sh.sample(s),p1=tangent(sh,s-9),p2=tangent(sh,s+9);
      const angle=Math.acos(Math.max(-1,Math.min(1,p1[0]*p2[0]+p1[2]*p2[2])));
      const k=angle/18,speed=Math.sqrt((c.seg.surface==="gravel"?2.3:3.3)/Math.max(k,0.0001))*3.6;
      const pBefore=sh.sample(s-12).p,pAfter=sh.sample(s+12).p;
      const grade=Math.abs((pAfter[1]-pBefore[1])/Math.max(1,d2(pBefore,pAfter)));
      const aim=Math.min(c.seg.limit, speed, grade>0.09?c.seg.limit*0.83:999);
      profile.push({at_m:rnd(s),lane_id:c.seg.lane,target_kph:rnd(aim),speed_limit_kph:c.seg.limit});
    }
    return profile;
  }
  function preview(ev,sh){
    const wx=x=>80+(x+1000)*.37,wz=z=>125+(z+1000)*.37;
    const poly=pts=>pts.map(p=>`${wx(p[0]).toFixed(1)},${wz(p[2]).toFixed(1)}`).join(" ");
    const x=ev.id.split("_").map(w=>w[0].toUpperCase()+w.slice(1)).join(" ");
    const bg=g.lanes.filter(l=>l.id.startsWith("lane_")&&l.id.endsWith("_ab"))
      .map(l=>`<polyline points="${poly(l.points)}" stroke="${l.surface==="gravel"?"#ceb895":"#b9c6c8"}" stroke-width="${l.surface==="gravel"?2.7:3.8}" fill="none" stroke-linecap="round" stroke-linejoin="round"/>`).join("\n");
    const coords=sh.points.map(p=>`${wx(p[0]).toFixed(1)},${wz(p[2]).toFixed(1)}`).join(" ");
    const cps=ev.checkpoints.map((cp,i)=>`<circle cx="${wx(cp.center[0]).toFixed(1)}" cy="${wz(cp.center[2]).toFixed(1)}" r="5.4" fill="#f4e6b9" stroke="#774f35" stroke-width="1.3"/>${(i%3===0)?`<text x="${(wx(cp.center[0])+9).toFixed(1)}" y="${(wz(cp.center[2])-7).toFixed(1)}" class="num">${i+1}</text>`:""}`).join("\n");
    const st=ev.start_position,fi=ev.finish.position;
    const esc=t=>String(t).replaceAll("&","&amp;").replaceAll("<","&lt;").replaceAll(">","&gt;");
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 900 1050" role="img" aria-label="${esc(ev.name)} course derived from Aster Valley road graph"><rect width="900" height="1050" fill="#f5f4ef"/>
<style>text{font-family:Arial,Helvetica,sans-serif;fill:#20353e}.label{font-size:18px;font-weight:bold}.meta{font-size:15px}.num{font-size:13px;font-weight:bold;paint-order:stroke;stroke:#fff;stroke-width:3px}.small{font-size:12px}</style>
<text x="80" y="56" style="font-size:31px;font-weight:bold">${esc(ev.name)}</text><text x="80" y="86" class="meta">${(ev.route_length_m/1000).toFixed(2)} km / ${ev.kind==="circuit"?ev.laps+" lap(s)":"point-to-point"} · ${esc(ev.difficulty)} · generated from real directed lanes</text>
<rect x="75" y="120" width="750" height="750" rx="14" fill="#e9efe6" stroke="#bbccc3" stroke-width="2"/>
<g opacity=".95">${bg}</g><polyline points="${coords}" stroke="#20353e" stroke-width="10" fill="none" stroke-linejoin="round" stroke-linecap="round" opacity=".24"/>
<polyline points="${coords}" stroke="#c35c37" stroke-width="5.6" fill="none" stroke-linejoin="round" stroke-linecap="round"/>
<g>${cps}</g><circle cx="${wx(st[0])}" cy="${wz(st[2])}" r="9.5" fill="#238064" stroke="#fff" stroke-width="3"/>
<circle cx="${wx(fi[0])}" cy="${wz(fi[2])}" r="5.5" fill="#152f47" stroke="#fff" stroke-width="2"/>
<path d="M782 166 v-30 l-9 12 9-3 9 3z" fill="#233b48"/><text x="774" y="129" class="meta">N</text>
<text x="80" y="914" class="label">START / FINISH  •  Ordered checkpoints  •  Road graph v1</text>
<text x="80" y="944" class="meta">Orange: course direction follows authored lane sequence (not a straight-line shortcut).</text>
<text x="80" y="971" class="meta">Green: start   Dark: finish   Gold: gates (every third labeled)</text>
<text x="80" y="1005" class="small">Source: feat/worldgen · Git blob ${PINSHA} · X east / Z south · 1 px ≈ 2.70 m</text></svg>\n`;
  }
  for(const def of settings){
    const seq=getRoute(def),sh=shape(seq,def.kind==="circuit");
    const gates=[];let lastS=0;
    for(let candidate=68;candidate<sh.len-54;candidate+=def.spacing){
      let chosen=null;
      for(const off of [0,6,-6,12,-12,18,-18,24,-24,30,-30]){
        const s=candidate+off;
        if(s<=lastS+def.radius*2+4||s>=sh.len-50)continue;
        if(uniqueGate(sh,s,def.radius)){chosen=s;break}
      }
      if(chosen!==null){gates.push(chosen);lastS=chosen}
    }
    const cps=gates.map((s,i)=>({id:`${def.id}_cp_${String(i+1).padStart(2,"0")}`,center:sh.sample(s).p.map(rnd),radius_m:def.radius}));
    const stats={distance_m:rnd(sh.len),asphalt_m:0,gravel_m:0,ascent_m:0,descent_m:0,max_abs_grade_pct:0,min_speed_limit_kph:Infinity,max_speed_limit_kph:0};
    let prev=sh.points[0];
    for(const seg of sh.segs){
      const dd=seg.len,dy=seg.b[1]-seg.a[1];
      if(seg.surface==="gravel")stats.gravel_m+=dd;else stats.asphalt_m+=dd;
      stats.ascent_m+=Math.max(0,dy);stats.descent_m+=Math.max(0,-dy);
      stats.max_abs_grade_pct=Math.max(stats.max_abs_grade_pct,Math.abs(dy)/dd*100);
      stats.min_speed_limit_kph=Math.min(stats.min_speed_limit_kph,seg.limit);
      stats.max_speed_limit_kph=Math.max(stats.max_speed_limit_kph,seg.limit);
    }
    for(const k in stats)stats[k]=rnd(stats[k]);
    const roles=["player","rival_1","rival_2","rival_3"],first=ids.get(seq[0]);
    const grid=roles.map((role,i)=>{
      const s=7+i*10,x=sh.sample(s);
      assert(x.seg.lane===first.id,"grid not entirely on first road "+def.id);
      return {id:role,position:x.p.map(rnd),forward:tangent(sh,s).map(rnd),route_s_m:s};
    });
    const finishPos=sh.closed?sh.sample(0).p:sh.sample(sh.len).p;
    const ev={
      id:def.id,name:def.name,description:def.description,kind:def.kind,laps:def.laps,
      difficulty:def.difficulty,lane_route:seq,start_position:sh.sample(0).p.map(rnd),
      start_grid:grid,finish:{position:finishPos.map(rnd),forward:tangent(sh,sh.closed?0:sh.len-2).map(rnd),route_s_m:rnd(sh.len),radius_m:7},
      route_length_m:rnd(sh.len),total_race_distance_m:rnd(sh.len*def.laps),
      grid_seconds:1,countdown_seconds:3,finish_grace_seconds:25,max_speed_mps:65,
      max_race_seconds:1800,corridor_m:12,collision_reset_speed_mps:13,
      checkpoints:cps,ai_speed_guidance:aiProfile(sh),route_statistics:stats
    };
    const gateS=checkEvent(ev,sh);
    const pilotResult=pilot(ev,sh,gateS);
    output.push(ev);
    reports.push({id:ev.id,route_length_m:ev.route_length_m,full_race_distance_m:ev.total_race_distance_m,laps:ev.laps,kind:ev.kind,lanes:seq,checkpoint_count:cps.length,statistics:stats,pilot:pilotResult});
    svgFiles[`previews/${ev.id}.svg`]=preview(ev,sh);
    pilotResults.push(pilotResult);
  }
  // Corpus-level diversity: route overlap may be expected, but no course should duplicate another.
  for(let i=0;i<output.length;i++)for(let j=i+1;j<output.length;j++){
    const A=new Set(output[i].lane_route.filter(s=>s.startsWith("lane_"))),B=new Set(output[j].lane_route.filter(s=>s.startsWith("lane_")));
    const intersection=[...A].filter(x=>B.has(x)).length,union=new Set([...A,...B]).size;
    assert(intersection/union<0.7,"Events not different enough: "+output[i].id+" / "+output[j].id);
  }
  assert(reports.find(r=>r.id==="green_valley_tour").statistics.gravel_m>300,"Tour is not mixed-surface");
  assert(reports.find(r=>r.id==="north_ridge_climb").statistics.ascent_m>100,"Climb lacks elevation");
  const events={schema_version:1,source_graph:{branch:"feat/worldgen",path:"data/world/road_graph_v1.json",git_blob_sha1:PINSHA},events:output};
  const report={schema_version:1,source_graph_git_blob_sha1:PINSHA,reports,tests:{graph_schema:"PASS",lane_connectivity:"PASS",closure:"PASS",checkpoint_order_and_anti_cut:"PASS",grid_geometry:"PASS",engine_semantics_pilot:"PASS",event_diversity:"PASS",caveat:"Independent JavaScript geometry/progress pilot, not Godot runtime execution."}};
  return {files:{"events_v1.json":JSON.stringify(events,null,2)+"\n","route_report.json":JSON.stringify(report,null,2)+"\n",...svgFiles},report,events};
}
function main(){
 const args=process.argv.slice(2),ix=args.indexOf("--graph");
 const graphPath=ix<0?"data/world/road_graph_v1.json":args[ix+1];
 if(!graphPath||!fs.existsSync(graphPath)){console.error("World graph unavailable; pass --graph path/to/feat-worldgen/data/world/road_graph_v1.json");process.exit(2)}
 const raw=fs.readFileSync(graphPath),blob=crypto.createHash("sha1").update(Buffer.from("blob "+raw.length+"\0")).update(raw).digest("hex");
 const data=generate(JSON.parse(raw.toString("utf8")),blob),root=__dirname;
 const write=args.includes("--write");
 for(const [file,content] of Object.entries(data.files)){
  const dest=path.join(root,file);
  if(write){fs.mkdirSync(path.dirname(dest),{recursive:true});fs.writeFileSync(dest,content)}
  else if(!fs.existsSync(dest)||fs.readFileSync(dest,"utf8")!==content)throw Error("Missing/stale generated artifact: "+dest+" (run --write after reviewing graph)");
 }
 console.log(JSON.stringify({status:"PASS",mode:write?"write":"check",source_graph_blob:blob,events:data.report.reports.map(r=>({id:r.id,meters:r.route_length_m,checkpoints:r.checkpoint_count,pilot:r.pilot}))},null,2));
}
if(require.main===module){try{main()}catch(e){console.error(e.stack||e);process.exitCode=1}}
module.exports={generate};
