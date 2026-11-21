// Aster Valley scenery composition. Original deterministic generator; no external packages.
// Usage: node content/scenery/tools/generate.mjs [path/to/data/world] [--check]
// Reads PR #3's unmodified heightfield, metadata and directed lane graph.
export function generate(meta,graph,bytes) {
 const regionIds=["alder_town","cedar_woods","north_ridge","green_valley","eastwater_lake"];
 const seed0=20261121, lakeLevel=5.35;
 if(meta.seed!==seed0||meta.regions.map(r=>r.id).join(",")!==regionIds.join(",")||meta.landmarks.length!==6||bytes.length!==502002)throw Error("Canonical world inputs changed");
 const hf=meta.heightfield, W=hf.sample_width, H=hf.sample_height, s=hf.spacing_m, ox=hf.origin_x,oz=hf.origin_z;
 const sample=(i,j)=>((bytes[2*(j*W+i)] | (bytes[2*(j*W+i)+1]<<8))*hf.scale_m_per_unit+hf.offset_m);
 const height=(x,z)=>{
  const gx=Math.max(0,Math.min(W-1,(x-ox)/s)),gz=Math.max(0,Math.min(H-1,(z-oz)/s)),i=Math.min(W-2,Math.floor(gx)),j=Math.min(H-2,Math.floor(gz)),u=gx-i,v=gz-j;
  const a=sample(i,j),b=sample(i+1,j),c=sample(i,j+1),d=sample(i+1,j+1);
  return u+v<=1?a+(b-a)*u+(c-a)*v:d+(c-d)*(1-u)+(b-d)*(1-v);
 };
 const slope=(x,z)=>Math.atan(Math.hypot(height(x+4,z)-height(x-4,z),height(x,z+4)-height(x,z-4))/8)*180/Math.PI;
 const round=(x,n=3)=>+x.toFixed(n);
 let seed=seed0|0;
 const random=()=>{seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;return (seed>>>0)/4294967296};
 const range=(a,b)=>a+(b-a)*random(),normal=()=>Math.sqrt(-2*Math.log(Math.max(1e-10,random())))*Math.cos(2*Math.PI*random());
 const assets={
  pine:{path:"assets/curated/models/environment/pine_tree_lod0.glb",lod:"assets/curated/models/environment/pine_tree_lod1.glb",tri:108,surfaces:7,lod_tri:57,lod_surfaces:4,r:2.5,slope:28,road:12,turn:20,draw:470,kind:"natural"},
  broadleaf:{path:"assets/curated/models/environment/broadleaf_tree.glb",tri:960,surfaces:8,r:3.2,slope:20,road:13,turn:21,draw:240,kind:"natural"},
  shrub:{path:"assets/curated/models/environment/shrub_cluster.glb",tri:924,surfaces:7,r:1.6,slope:32,road:9.5,turn:18,draw:145,kind:"natural"},
  boulder:{path:"assets/curated/models/environment/boulder.glb",tri:224,surfaces:1,r:2.8,slope:42,road:11,turn:21,draw:440,kind:"natural"},
  rock:{path:"assets/curated/models/environment/rock_cluster.glb",tri:528,surfaces:4,r:2.2,slope:39,road:10.5,turn:20,draw:300,kind:"natural"},
  guardrail:{path:"assets/curated/models/environment/guardrail_4m.glb",tri:192,surfaces:10,r:1.8,slope:40,road:5.0,turn:25,draw:200,kind:"roadside"},
  barrier:{path:"assets/curated/models/environment/concrete_barrier.glb",tri:48,surfaces:4,r:1.9,slope:32,road:5.2,turn:25,draw:180,kind:"roadside"},
  fence:{path:"assets/curated/models/environment/wood_fence.glb",tri:60,surfaces:5,r:1.8,slope:24,road:8.5,turn:22,draw:210,kind:"roadside"},
  bollard:{path:"assets/curated/models/environment/bollard.glb",tri:60,surfaces:3,r:.6,slope:22,road:6.0,turn:23,draw:150,kind:"roadside"},
  warning:{path:"assets/curated/models/environment/warning_sign.glb",tri:64,surfaces:4,r:.8,slope:25,road:6.1,turn:25,draw:180,kind:"roadside"},
  lamp:{path:"assets/curated/models/environment/street_lamp.glb",tri:84,surfaces:3,r:.9,slope:17,road:6.3,turn:25,draw:210,kind:"roadside"},
  hay:{path:"assets/curated/models/environment/hay_bale.glb",tri:36,surfaces:3,r:1.2,slope:15,road:12,turn:25,draw:160,kind:"rural"},
  house:{path:"content/scenery/models/town_house.gltf",tri:366,surfaces:8,r:7.4,slope:12,road:16,turn:31,draw:280,kind:"architecture"},
  barn:{path:"content/scenery/models/barn.gltf",tri:150,surfaces:8,r:8.8,slope:13,road:18,turn:32,draw:350,kind:"architecture"},
  garage:{path:"content/scenery/models/garage.gltf",tri:288,surfaces:8,r:8,slope:11,road:11,turn:26,draw:340,kind:"landmark"},
  windmill:{path:"content/scenery/models/windmill.gltf",tri:168,surfaces:7,r:7.4,slope:15,road:16,turn:28,draw:800,kind:"landmark"},
  arch:{path:"content/scenery/models/stone_arch.gltf",tri:72,surfaces:3,r:4.2,slope:24,road:10.2,turn:27,draw:310,kind:"landmark"},
  overlook:{path:"content/scenery/models/overlook.gltf",tri:204,surfaces:3,r:6.5,slope:21,road:12,turn:28,draw:310,kind:"landmark"},
  pier:{path:"content/scenery/models/pier.gltf",tri:204,surfaces:3,r:6.5,slope:16,road:11,turn:26,draw:360,kind:"landmark"},
  quarry:{path:"content/scenery/models/quarry_hopper.gltf",tri:252,surfaces:7,r:9,slope:25,road:16,turn:30,draw:550,kind:"landmark"}
 };
 const travel=graph.lanes.filter(l=>l.id.startsWith("lane_")&&l.id.endsWith("_ab")),turns=graph.lanes.filter(l=>l.id.startsWith("turn_"));
 if(travel.length!==16||turns.length!==72)throw Error("Expected 16 corridors and 72 junction turns");
 const centers=travel.map(l=>{const b=graph.lanes.find(q=>q.id==="lane_"+l.road_id+"_ba");if(!b||b.points.length!==l.points.length)throw Error("Corridor mismatch: "+l.road_id);
  return {id:l.road_id,points:l.points.map((p,i)=>[(p[0]+b.points[b.points.length-1-i][0])/2,(p[1]+b.points[b.points.length-1-i][1])/2,(p[2]+b.points[b.points.length-1-i][2])/2])};});
 const rdGrid=new Map(),gridKey=(i,j)=>i+","+j,cell=64;
 function segment(a,b,t){
  const seg={x:a[0],z:a[2],dx:b[0]-a[0],dz:b[2]-a[2],turn:t};
  const pad=t?37:29;
  for(let i=Math.floor((Math.min(a[0],b[0])-pad)/cell);i<=Math.floor((Math.max(a[0],b[0])+pad)/cell);i++)
   for(let j=Math.floor((Math.min(a[2],b[2])-pad)/cell);j<=Math.floor((Math.max(a[2],b[2])+pad)/cell);j++){const k=gridKey(i,j);if(!rdGrid.has(k))rdGrid.set(k,[]);rdGrid.get(k).push(seg);}
 }
 for(const l of [...travel,...turns])for(let i=1;i<l.points.length;i++)segment(l.points[i-1],l.points[i],l.id.startsWith("turn_"));
 const junctions=[];for(const p of centers.flatMap(c=>[c.points[0],c.points.at(-1)]))if(!junctions.some(q=>Math.hypot(p[0]-q[0],p[2]-q[2])<20))junctions.push(p);
 function roadDistance(x,z){
  let road=1e6,turn=1e6,junction=1e6;
  for(const a of rdGrid.get(gridKey(Math.floor(x/cell),Math.floor(z/cell)))||[]){
   const t=Math.max(0,Math.min(1,((x-a.x)*a.dx+(z-a.z)*a.dz)/Math.max(1e-7,a.dx*a.dx+a.dz*a.dz)));
   const d=Math.hypot(x-a.x-t*a.dx,z-a.z-t*a.dz);
   if(a.turn)turn=Math.min(turn,d);else road=Math.min(road,d);
  }
  for(const p of junctions)junction=Math.min(junction,Math.hypot(x-p[0],z-p[2]));
  return {road,turn,junction};
 }
 const packs=Object.fromEntries(regionIds.map(id=>[id,[]])),located=[],grid=new Map(),landmarkIds=new Set();
 const rejected={bounds:0,road:0,turn:0,junction:0,slope:0,water:0,landmark:0,spacing:0,no_location:0,foundation:0};
 function add(region,asset,x,z,o={}){
  const a=assets[asset],r=meta.regions.find(q=>q.id===region);if(!r||!a)throw Error("Invalid region/asset");
  const sc=o.scale??1,foot=a.r*sc;
  if(x<ox+12||x>1000-12||z<oz+12||z>1000-12||(!o.district&&Math.hypot(x-r.center[0],z-r.center[1])>r.radius_m*.98)){rejected.bounds++;return false;}
  const h=height(x,z),sl=slope(x,z);
  if(sl>(o.slope_limit??a.slope)){rejected.slope++;return false;}
  if(region==="eastwater_lake"&&asset!=="pier"&&h<lakeLevel+1.8){rejected.water++;return false;}
  if(a.kind==="architecture"||a.kind==="landmark"){
   const limit=asset==="house"?1.20:asset==="barn"?1.50:asset==="garage"?1.50:asset==="windmill"?2.00:asset==="arch"?2.05:asset==="quarry"?2.50:asset==="pier"?3.60:1.50;
   let relief=0;
   for(const [cx,cz] of [[foot,0],[-foot,0],[0,foot],[0,-foot],[foot*.7,foot*.7],[foot*.7,-foot*.7],[-foot*.7,foot*.7],[-foot*.7,-foot*.7]])relief=Math.max(relief,Math.abs(height(x+cx,z+cz)-h));
   if(relief>limit){rejected.foundation++;return false;}
  }
  const d=roadDistance(x,z);
  if(d.road<(o.road_limit??a.road)+Math.max(0,foot-a.r)*.35){rejected.road++;return false;}
  if(d.turn<(o.turn_limit??a.turn)+Math.max(0,foot-a.r)*.35){rejected.turn++;return false;}
  if(d.junction<(o.junction_limit??Math.max(27,a.r+20))){rejected.junction++;return false;}
  if(!o.landmark&&(a.kind==="natural"||a.kind==="architecture")){
   for(const lm of meta.landmarks){const min=lm.id==="ridge_lookout"?43:lm.id==="valley_windmill"?42:lm.id==="alder_garage"?31:lm.id==="eastwater_pier"?30:lm.id==="old_quarry"?27:28;if(Math.hypot(x-lm.x,z-lm.z)<min){rejected.landmark++;return false;}}
  }
  const kx=Math.floor(x/32),kz=Math.floor(z/32),sep=o.sep??(a.kind==="architecture"||a.kind==="landmark"?foot+6:a.kind==="natural"?Math.max(2.5,foot*.8):1.5);
  for(let i=kx-2;i<=kx+2;i++)for(let j=kz-2;j<=kz+2;j++)for(const q of grid.get(gridKey(i,j))||[]){
   const need=(sep+q.sep)*(o.arrangement&&o.arrangement===q.arrangement?.67:1);
   if(Math.hypot(x-q.x,z-q.z)<need){rejected.spacing++;return false;}
  }
  const sink=o.sink??(asset==="boulder"||asset==="rock"?-.24:a.kind==="natural"?-.08:0);
  const item={id:region+"_"+String(packs[region].length+1).padStart(4,"0"),asset,position:[round(x),round(h+sink),round(z)],yaw_deg:round(o.yaw??range(0,360),2),scale:round(sc),terrain_offset_m:round(sink),slope_deg:round(sl,2),road_clearance_m:round(d.road,2),district:o.district||"",tag:o.tag||"background"};
  packs[region].push(item);located.push(item);
  const k=gridKey(kx,kz);if(!grid.has(k))grid.set(k,[]);grid.get(k).push({x,z,sep,arrangement:o.arrangement});
  if(o.landmark)landmarkIds.add(o.landmark);
  return true;
 }
 function landmark(region,id,asset){
  const p=meta.landmarks.find(l=>l.id===id);if(!p)throw Error("Landmark missing: "+id);
  // Search a deliberate sequence of radial alternatives near the exact metadata anchor.
  for(const radius of [0,16,26,36,48,62,78,90])for(let i=0;i<(radius===0?1:16);i++){
   const angle=2*Math.PI*i/16,dx=Math.cos(angle)*radius,dz=Math.sin(angle)*radius;
   if(add(region,asset,p.x+dx,p.z+dz,{scale:1,yaw:0,landmark:id,tag:"landmark",district:id==="old_quarry"?"old_quarry":"",sep:10}))return;
  }
  throw Error("No safe site found within 90m of "+id);
 }
 function cluster(region,arr,o={}){
  for(const [cx,cz,rx,rz,count,weights] of arr)for(let n=0;n<count;n++){
   let ok=false;
   for(let tries=0;tries<24&&!ok;tries++){
    const x=cx+normal()*rx*.36,z=cz+normal()*rz*.36;let p=random()*weights.reduce((sum,q)=>sum+q[1],0),asset=weights.at(-1)[0];
    for(const [name,w] of weights){p-=w;if(p<=0){asset=name;break;}}
    ok=add(region,asset,x,z,{scale:range(.7,1.48),tag:o.tag||"planted_cluster",district:o.district||""});
   }
   if(!ok)rejected.no_location++;
  }
 }
 function pointOnRoad(id,t){
  const line=centers.find(c=>c.id===id);if(!line)throw Error("Unknown corridor "+id);let total=0;const lengths=[];
  for(let i=1;i<line.points.length;i++){total+=Math.hypot(line.points[i][0]-line.points[i-1][0],line.points[i][2]-line.points[i-1][2]);lengths.push(total);}
  const d=total*Math.max(0,Math.min(1,t)),idx=Math.max(0,lengths.findIndex(l=>l>=d)),previous=idx?lengths[idx-1]:0;
  const a=line.points[idx],b=line.points[idx+1],u=(d-previous)/Math.max(1e-7,lengths[idx]-previous),dx=b[0]-a[0],dz=b[2]-a[2],dist=Math.hypot(dx,dz);
  return {x:a[0]+u*dx,z:a[2]+u*dz,nx:-dz/dist,nz:dx/dist,yaw:Math.atan2(dx,dz)*180/Math.PI};
 }
 function roadside(region,id,start,end,count,asset,offset,tag,sides=[1,-1],options={}){
  for(let i=0;i<count;i++){const p=pointOnRoad(id,start+(end-start)*(i+.5)/count),side=sides[i%sides.length],jitter=range(-.3,.3);
   add(region,asset,p.x+p.nx*side*(offset+jitter),p.z+p.nz*side*(offset+jitter),{scale:range(.93,1.07),yaw:p.yaw+(side===1?0:180),tag,arrangement:tag,sep:options.sep,district:options.district||""});
  }
 }
 // The order is intentional: signature landmarks > roadsides/architecture > clustered infill.
 landmark("alder_town","alder_garage","garage");
 for(const r of [["alder_depot",.2,.8,11],["depot_chapel",.18,.82,10],["chapel_alder",.16,.85,16],["alder_market",.18,.82,12]])roadside("alder_town",r[0],r[1],r[2],r[3],"house",29,"streetwall");
 for(const r of [["alder_depot",.15,.83,18],["depot_chapel",.18,.83,15],["chapel_alder",.17,.83,20]])roadside("alder_town",r[0],r[1],r[2],r[3],"lamp",11,"town_lamps");
 roadside("alder_town","alder_market",.2,.83,13,"bollard",10,"civic_threshold",[1]);
 cluster("alder_town",[[-880,765,95,70,42,[["broadleaf",.45],["shrub",.55]]],[-555,720,60,100,45,[["broadleaf",.35],["shrub",.65]]],[-840,470,95,95,50,[["broadleaf",.35],["shrub",.65]]]]);
 landmark("cedar_woods","pine_arch","arch");
 cluster("cedar_woods",[
  [-850,-615,110,100,107,[["pine",.82],["shrub",.1],["rock",.08]]],[-840,-220,150,85,112,[["pine",.8],["shrub",.12],["boulder",.08]]],
  [-700,-510,100,140,128,[["pine",.8],["shrub",.13],["rock",.07]]],[-540,-570,95,105,84,[["pine",.77],["shrub",.12],["boulder",.11]]],
  [-485,-195,115,110,95,[["pine",.75],["shrub",.14],["rock",.11]]],[-915,-40,80,145,84,[["pine",.81],["shrub",.13],["rock",.06]]],[-570,-8,90,90,76,[["pine",.72],["boulder",.17],["rock",.11]]]
 ]);
 roadside("cedar_woods","cedar_pine",.2,.8,18,"warning",8.4,"forest_curve");
 landmark("cedar_woods","old_quarry","quarry");
 cluster("cedar_woods",[[-170,-500,75,55,90,[["boulder",.52],["rock",.43],["shrub",.05]]],[-80,-420,70,75,72,[["boulder",.55],["rock",.38],["pine",.07]]]],{district:"old_quarry",tag:"quarry_rockface"});
 roadside("cedar_woods","pine_ridge",.16,.35,25,"barrier",7.3,"quarry_edge",[-1],[{district:"old_quarry"}]);
 landmark("north_ridge","ridge_lookout","overlook");
 cluster("north_ridge",[
  [-80,-795,135,100,107,[["pine",.43],["boulder",.4],["rock",.17]]],[225,-835,130,100,108,[["pine",.35],["boulder",.44],["rock",.21]]],
  [470,-845,100,95,90,[["pine",.28],["boulder",.51],["rock",.21]]],[350,-585,105,130,102,[["pine",.35],["boulder",.48],["rock",.17]]],
  [-10,-530,110,105,91,[["pine",.45],["boulder",.44],["rock",.11]]],[580,-475,85,90,79,[["pine",.25],["boulder",.51],["rock",.24]]]
 ]);
 roadside("north_ridge","ridge_valley",.13,.41,65,"guardrail",7.3,"ridge_guardrail",[1],{sep:1.25});
 roadside("north_ridge","ridge_overlook",.2,.62,62,"guardrail",7.3,"ridge_lookout_rail",[-1],{sep:1.25});
 roadside("north_ridge","cedar_ridge",.45,.68,42,"guardrail",7.3,"needle_pass_rail",[1],{sep:1.25});
 roadside("north_ridge","ridge_valley",.48,.86,20,"warning",8,"ridge_warning");
 landmark("green_valley","valley_windmill","windmill");
 for(const [x,z] of [[-235,290],[290,315],[390,170],[-245,20],[150,415]])add("green_valley","barn",x,z,{tag:"farmstead",scale:range(.9,1.1)});
 cluster("green_valley",[
  [-165,85,130,110,92,[["broadleaf",.55],["shrub",.32],["hay",.13]]],[230,-2,100,100,88,[["broadleaf",.4],["shrub",.36],["pine",.24]]],
  [355,230,95,125,97,[["broadleaf",.45],["shrub",.29],["hay",.26]]],[-55,330,145,95,103,[["broadleaf",.4],["shrub",.3],["hay",.3]]],
  [150,425,90,80,67,[["broadleaf",.48],["pine",.27],["hay",.25]]]
 ]);
 function orchard(x,z,rows,columns,dx,dz){
  for(let i=0;i<rows;i++)for(let j=0;j<columns;j++)if(!((i===2&&j===3)||(i===4&&j===1)||random()<.12))
   add("green_valley","broadleaf",x+j*dx+range(-2.2,2.2),z+i*dz+range(-2,2),{tag:"orchard_rows",arrangement:"orchard",scale:range(.88,1.12),sep:2.8});
 }
 orchard(-130,-70,6,7,14,14);orchard(270,315,5,8,14.5,14);
 roadside("green_valley","pine_valley",.17,.82,35,"fence",15.4,"farm_boundary",[-1]);
 roadside("green_valley","market_valley",.2,.83,35,"fence",15.4,"field_boundary",[1]);
 landmark("eastwater_lake","eastwater_pier","pier");
 cluster("eastwater_lake",[
  [580,270,90,95,85,[["broadleaf",.34],["pine",.24],["rock",.42]]],[600,650,110,75,98,[["rock",.42],["pine",.31],["shrub",.27]]],
  [850,280,65,85,83,[["boulder",.48],["rock",.38],["pine",.14]]],[900,695,70,90,82,[["rock",.48],["shrub",.27],["boulder",.25]]],
  [675,780,85,65,78,[["pine",.35],["boulder",.35],["shrub",.3]]]
 ]);
 roadside("eastwater_lake","orchard_lake",.24,.74,34,"fence",14,"shore_fence",[-1]);
 roadside("eastwater_lake","lake_alder",.06,.18,19,"warning",8,"shore_warning");
 // Hydrological anchor at (800,500), in the actual R16 5m low basin.
 const waterKey=(i,j)=>j*W+i,seedX=Math.round((800-ox)/s),seedZ=Math.round((500-oz)/s),seen=new Set(),flood=new Set(),queue=[[seedX,seedZ]];
 for(let n=0;n<queue.length;n++){const [i,j]=queue[n],k=waterKey(i,j);
  if(i<0||j<0||i>=W-1||j>=H-1||seen.has(k))continue;seen.add(k);
  if(ox+i*s<500||oz+j*s<245||sample(i,j)>lakeLevel)continue;
  flood.add(k);for(const [a,b] of [[1,0],[-1,0],[0,1],[0,-1]])queue.push([i+a,j+b]);
 }
 const waterCells=[];for(const k of flood){const i=k%W,j=Math.floor(k/W);if(flood.has(waterKey(i+1,j))&&flood.has(waterKey(i,j+1))&&flood.has(waterKey(i+1,j+1)))waterCells.push([i,j]);}
 waterCells.sort((a,b)=>a[1]-b[1]||a[0]-b[0]);
 if(waterCells.length<100)throw Error("Cannot derive connected flooded region from real terrain");
 const provenance={world_pr:3,art_pr:7,road_git_blob:"9bba378d68879df3baed2c97a4885c0adde88406",terrain_git_blob:"d951ce11a831dad5430b4c7157e2296f73c6b151",art_manifest_git_blob:"7c67ab03c29169c48432b36df6ae7a429a8decee"};
 const report={},counts={};let total=0,triangles=0,batches=0,surfaceBatches=0,globalSurfaceGroups=new Set();
 for(const r of meta.regions){const list=packs[r.id],byAsset={},groups=new Set();let tri=0;
  for(const q of list){byAsset[q.asset]=(byAsset[q.asset]||0)+1;tri+=assets[q.asset].tri;groups.add(Math.floor(q.position[0]/128)+","+Math.floor(q.position[2]/128)+"|"+q.asset);}
  report[r.id]={count:list.length,by_asset:byAsset,near_mesh_triangles_estimate:tri,minimum_asset_cell_batches:groups.size};
  let sur=0;for(const item of groups){const name=item.split("|")[1];sur+=assets[name].surfaces;}
  report[r.id].near_mesh_component_draw_batches_estimate=sur;
  for(const group of groups)globalSurfaceGroups.add(group);
  total+=list.length;triangles+=tri;batches+=groups.size;surfaceBatches+=sur;counts[r.id]=list.length;
 }
 // Preview plans are generated from the same real heightfield, all 16 centerlines and committed placements.
 function preview(r){
  const cx=r.center[0],cz=r.center[1],rad=r.id==="north_ridge"?660:r.id==="cedar_woods"?540:r.id==="green_valley"?510:r.id==="alder_town"?380:420;
  const mx=x=>60+(x-cx+rad)*680/(2*rad),mz=z=>44+(z-cz+rad)*630/(2*rad),color={pine:"#23482b",broadleaf:"#b3db7c",shrub:"#4c8e58",boulder:"#c6c7b9",rock:"#929d98",house:"#f5c588",barn:"#d29a62",garage:"#ffe18a",windmill:"#fbe9bd",arch:"#d3c6b0",overlook:"#ffcc93",pier:"#69d8e1",quarry:"#de8b67",guardrail:"#ffffff",barrier:"#f5cdab",fence:"#e7b17e",hay:"#ecd36d",lamp:"#ffefb5",warning:"#fa9a73",bollard:"#d9ae85"};
  let out='<svg xmlns="http://www.w3.org/2000/svg" width="800" height="740" viewBox="0 0 800 740"><rect width="800" height="740" fill="#182330"/>';
  const tile=2*rad/50;
  for(let i=0;i<50;i++)for(let j=0;j<50;j++){const x=cx-rad+(i+.5)*tile,z=cz-rad+(j+.5)*tile,h=height(x,z),sl=slope(x,z);
   const c=h<=lakeLevel?"#2b6371":sl>26?"#827d71":h>160?"#707a6e":h>100?"#536b57":h>55?"#64835e":"#798758";
   out+='<rect x="'+round(mx(x-tile/2),1)+'" y="'+round(mz(z-tile/2),1)+'" width="13.7" height="12.7" fill="'+c+'"/>';
  }
  for(const road of centers){const pts=road.points.map(p=>round(mx(p[0]),1)+","+round(mz(p[2]),1)).join(" ");
   out+='<polyline points="'+pts+'" fill="none" stroke="#23303a" stroke-width="6" stroke-linejoin="round"/><polyline points="'+pts+'" fill="none" stroke="#e6c79b" stroke-width="2.4" stroke-linejoin="round"/>';
  }
  for(const p of packs[r.id]){const x=mx(p.position[0]),z=mz(p.position[2]);if(x<60||x>740||z<44||z>674)continue;
   out+='<circle cx="'+round(x,1)+'" cy="'+round(z,1)+'" r="'+(p.tag==="landmark"?7:p.asset==="house"?3.8:2.1)+'" fill="'+(color[p.asset]||"#fff")+'"/>';
  }
  for(const l of meta.landmarks){const x=mx(l.x),z=mz(l.z);if(x<60||x>740||z<44||z>674)continue;
   out+='<circle cx="'+round(x,1)+'" cy="'+round(z,1)+'" r="11" fill="none" stroke="#ffefb0" stroke-width="2.5"/><text x="'+round(x+12,1)+'" y="'+round(z-6,1)+'" fill="#fff3d7" font-size="11" font-family="sans-serif">'+l.name+'</text>';
  }
  return out+'<text x="60" y="27" fill="#fff4d6" font-family="sans-serif" font-size="17">ASTER VALLEY / real R16 terrain + road graph / north up</text><text x="60" y="712" fill="#fff4d6" font-family="sans-serif" font-size="21">'+r.name+' — '+packs[r.id].length+' placements</text></svg>';
 }
 const files={};
 for(const r of meta.regions){
  files["content/scenery/packs/"+r.id+".json"]=JSON.stringify({schema_version:1,seed:seed0,region:r.id,source:provenance,placements:packs[r.id]},null,1)+"\n";
  files["content/scenery/previews/"+r.id+".svg"]=preview(r);
 }
 const manifest={schema_version:1,seed:seed0,coordinate_system:"godot_y_up",units:"meters",region_definitions:meta.regions,landmark_definitions:meta.landmarks,sources:provenance,assets,region_packs:regionIds.map(id=>({id,path:"content/scenery/packs/"+id+".json",count:packs[id].length})),lake:{water_level_m:lakeLevel,source_basin_floor_m:meta.heightfield.min_height_m,source_seed_xz:[800,500],grid_spacing_m:s,origin_x:ox,origin_z:oz,cell_count:waterCells.length,mask_path:"content/scenery/lake/water_cells_v1.json",note:"Flood only four-corner submerged quads in the connected low basin; decorative, non-colliding."}};
 const metrics={schema_version:1,seed:seed0,source:provenance,source_road_corridors:travel.length,source_turn_paths:turns.length,source_r16_samples:W*H,total_objects:total,near_mesh_triangles_estimate:triangles,minimum_asset_cell_batches:batches,full_world_near_mesh_component_draw_batches_estimate:[...globalSurfaceGroups].reduce((sum,k)=>sum+assets[k.split("|")[1]].surfaces,0),regions:report,lake:{water_height_m:lakeLevel,quads:waterCells.length,triangles:2*waterCells.length},rejects:rejected,landmark_ids:[...landmarkIds].sort(),culling:{cell_size_m:128,near_m:170,far_m:450,presets:["low","medium","high"]},caveat:"Minimum theoretical one-surface draw batches and source-asset triangle arithmetic, not measured GPU performance; some scene assets contain multiple surfaces."};
 files["content/scenery/manifest.json"]=JSON.stringify(manifest,null,2)+"\n";
 files["content/scenery/lake/water_cells_v1.json"]=JSON.stringify({schema_version:1,water_height_m:lakeLevel,origin_x:ox,origin_z:oz,spacing_m:s,cells:waterCells})+"\n";
 files["content/scenery/metrics.json"]=JSON.stringify(metrics,null,2)+"\n";
 return {files,metrics};
}
// CLI ENTRY
import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"../../..");
const world=process.argv[2] && !process.argv[2].startsWith("--") ? process.argv[2] : path.join(root,"data/world");
const meta=JSON.parse(fs.readFileSync(path.join(world,"world_metadata_v1.json"),"utf8"));
const graph=JSON.parse(fs.readFileSync(path.join(world,"road_graph_v1.json"),"utf8"));
const bytes=fs.readFileSync(path.join(world,"terrain_height_r16le.bin"));
const out=generate(meta,graph,bytes);
let bad=0;
for(const [relative,content] of Object.entries(out.files)){
 const target=path.join(root,relative);
 if(process.argv.includes("--check")){if(!fs.existsSync(target)||fs.readFileSync(target,"utf8")!==content){console.error("MISMATCH",relative);bad++;}}
 else{fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,content);console.log("WROTE",relative);}
}
console.log(JSON.stringify(out.metrics,null,2));
if(bad)process.exit(1);
