import {createHash} from 'node:crypto';
const sha256 = s => createHash('sha256').update(s).digest('hex');
const b64 = a => Buffer.from(a).toString('base64');
function makePair(spec){
 const add=(a,b)=>a.map((x,i)=>x+b[i]),sub=(a,b)=>a.map((x,i)=>x-b[i]),mul=(a,k)=>a.map(x=>x*k),dot=(a,b)=>a.reduce((s,x,i)=>s+x*b[i],0),cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]],norm=a=>mul(a,1/Math.sqrt(dot(a,a))),lerp=(a,b,t)=>add(mul(a,1-t),mul(b,t)),polar=(r,y,t)=>[r*Math.cos(t),y,r*Math.sin(t)];
 const groups=[], wood=[.16,.105,.049],green=[.095,.25,.049],fresh=[.19,.39,.075],dark=[.055,.15,.034],straw=[.45,.32,.10],flower=[.84,.72,.29];let state=spec.seed;
 function rnd(){state=(Math.imul(state,1664525)+1013904223)>>>0;return state/4294967296;}
 function triangle(a,b,c,color,uv=[[0,0],[1,0],[.5,1]]){return {p:[a,b,c],color,uv};}
 function sweep(points,radii,col){
  // Shared rings at every joint; a continuous tapered tube rather than separate frusta.
  const axes=[];
  const rings=points.map((center,i)=>{
   const before=points[Math.max(i-1,0)],after=points[Math.min(i+1,points.length-1)],d=norm(sub(after,before));
   const ref=Math.abs(d[1])>.95?[1,0,0]:[0,1,0];
   // Transport the previous axis by projection onto the next tangent plane.
   const prior=i>0?axes[i-1]:norm(cross(d,ref));
   let axis=sub(prior,mul(d,dot(prior,d)));
   if(dot(axis,axis)<1e-10)axis=cross(d,ref);
   const u=norm(axis),v=cross(d,u);axes.push(u);
   return Array.from({length:6},(_,k)=>add(center,add(mul(u,radii[i]*Math.cos(k*Math.PI/3)),mul(v,radii[i]*Math.sin(k*Math.PI/3)))));
  });
  const build=step=>{const out=[];for(let k=0;k<6;k+=step){const q=(k+step)%6;
   for(let i=0;i<rings.length-1;i++){const A=rings[i][k],B=rings[i][q],C=rings[i+1][k],D=rings[i+1][q];out.push(triangle(A,B,C,col),triangle(B,D,C,col));}
   const last=rings.length-1;out.push(triangle(points[0],rings[0][q],rings[0][k],col),triangle(points[last],rings[last][k],rings[last][q],col));
  }return out;};
  groups.push({near:build(1),far:build(2)});
 }
 function tube(a,b,r0,r1,col){sweep([a,b],[r0,r1],col);}
 function leaf(a,b,width,col,roll=0,retain=true){
  const d=norm(sub(b,a)),side=norm(cross(d,Math.abs(d[1])>.93?[1,0,0]:[0,1,0])),up=norm(cross(side,d));
  const s=add(mul(side,Math.cos(roll)),mul(up,Math.sin(roll))),ridge=add(lerp(a,b,.49),mul(up,width*.19)),l=add(lerp(a,b,.43),mul(s,width)),r=add(lerp(a,b,.43),mul(s,-width));
  const near=[triangle(a,l,ridge,col,[[.5,0],[0,.43],[.5,.49]]),triangle(l,b,ridge,col,[[0,.43],[.5,1],[.5,.49]]),triangle(a,ridge,r,col,[[.5,0],[.5,.49],[1,.43]]),triangle(ridge,b,r,col,[[.5,.49],[.5,1],[1,.43]])];
  const far=retain?[triangle(a,l,b,col,[[.5,0],[0,.43],[.5,1]]),triangle(a,b,r,col,[[.5,0],[.5,1],[1,.43]])]:[];
  groups.push({near,far});
 }
 function blade(a,m,b,width,col){
  // One continuous pointed blade, with an actual shared edge at its bend.
  const direction=norm(sub(b,a)),side=norm(cross(direction,[0,1,0]));
  const left=add(m,mul(side,width)),right=add(m,mul(side,-width)),ridge=add(m,[0,width*.04,0]);
  const near=[triangle(a,left,ridge,col),triangle(a,ridge,right,col),triangle(left,b,ridge,col),triangle(ridge,b,right,col)];
  const far=[triangle(a,left,right,col),triangle(left,b,right,col)];groups.push({near,far});
 }
 function branch(a,b,r,col=wood){tube(a,b,r,r*.4,col);}
 const tau=2*Math.PI;
 if(spec.id==="shrub"||spec.id==="sapling"){
  const tall=spec.id==="sapling",n=tall?8:10;
  if(tall)tube([0,0,0],[.04,1.55,0],.034,.009,wood);
  for(let i=0;i<n;i++){const t=i*2.39996+.12*rnd(),base=tall?[0,.18+i*.13,0]:[0,0,0],tip=polar((tall?.36:.47)*(0.8+.2*rnd()),tall?.66+i*.125:.32+.24*rnd(),t);const mid=lerp(base,tip,.55);sweep([base,mid,tip],[tall?.018:.012,.009,.0036],wood);for(let j=0;j<6;j++){const f=.20+j*.145,root=lerp(mid,tip,f),angle=t+(j%2?1:-1)*(.55+.16*(j%3)),length=tall?.19:.17;leaf(root,add(root,polar(length,.055,angle)),length*.35,j%3===0?fresh:green,.3*(j%3-1),true);}leaf(tip,add(tip,polar(.12,.075,t)),.055,fresh);}
 }else if(spec.id==="fern"){
  for(let i=0;i<8;i++){const angle=i*tau/8+.10*rnd(),r=.48+.09*rnd(),h=.27+.11*rnd(),point=t=>polar(r*t,h*Math.sin(t*2.15)+.025*t,angle);
   const points=Array.from({length:7},(_,k)=>point(k/6));
   sweep(points,points.map((_,k)=>.0055*(1-.75*k/6)),fresh);
   const onStem=t=>{const f=t*6,k=Math.min(5,Math.floor(f));return lerp(points[k],points[k+1],f-k);};
   const count=9;for(let j=0;j<count;j++){let f=.14+.80*j/count,root=onStem(f),len=.145*Math.sin(Math.PI*f)*(.9+.1*rnd());for(let sign of [-1,1])leaf(root,add(root,polar(len,.015,angle+sign*.95)),len*.23,j%3?green:fresh,sign*.15,true);}
   leaf(onStem(.88),onStem(1),.024,fresh);
  }
 }else if(spec.id==="reed"){
  for(let i=0;i<7;i++){const angle=i*2.39996,base=polar(.075,0,angle),tip=add(base,polar(.12+.02*rnd(),.8+.28*rnd(),angle));branch(base,tip,.009,green);
   if(i%2===0){tube(lerp(base,tip,.76),lerp(base,tip,.97),.022,.018,wood);}
   for(let j=0;j<4;j++){const root=lerp(base,tip,.09+j*.14),end=add(root,polar(.34-.034*j,.38+.045*j,angle+(j%2?-.72:.72))),mid=add(lerp(root,end,.55),[0,.10,0]);blade(root,mid,end,.031,green);}
  }
 }else if(spec.id==="wildflower"){
  for(let i=0;i<6;i++){const angle=i*2.39996,base=polar(.045,0,angle),tip=polar(.12+.07*rnd(),.34+.16*rnd(),angle);branch(base,tip,.0055,green);
   for(let j=0;j<4;j++){const root=lerp(base,tip,.14+j*.14);leaf(root,add(root,polar(.085,.025,angle+j*2.1)),.024,dark,0,true);}
   tube(add(tip,[0,-.012,0]),add(tip,[0,.006,0]),.017,.013,straw);for(let k=0;k<9;k++){const a=k*tau/9;leaf(tip,add(tip,polar(.052,.012,a)),.016,i%2?flower:[.72,.76,.65],0,true);}
  }
 }else throw Error("unknown species");
 // Shared scaffold and normalization. Retain extreme groups if necessary.
 const bounds=tris=>{const all=tris.flatMap(t=>t.p);return {lo:[0,1,2].map(i=>Math.min(...all.map(p=>p[i]))),hi:[0,1,2].map(i=>Math.max(...all.map(p=>p[i])))};};
 const near=groups.flatMap(g=>g.near),{lo,hi}=bounds(near);
 for(const group of groups){
  if(group.near.flatMap(t=>t.p).some(p=>p.some((v,i)=>v===lo[i]||v===hi[i])))group.far=group.near;
 }
 const far=groups.flatMap(g=>g.far);
 const fit=p=>p.map((v,i)=>Math.fround(Math.round(((v-lo[i])/(hi[i]-lo[i])*spec.d[i]-(i===1?0:spec.d[i]/2))*1e6)/1e6)||0);
 function encode(tris,lod){
 const pos=[],normal=[],uv=[],color=[];
 for(const t of tris){const p=t.p.map(fit),n=norm(cross(sub(p[1],p[0]),sub(p[2],p[0])));for(let i=0;i<3;i++){pos.push(...p[i]);normal.push(...n.map(v=>Math.round(v*1e6)/1e6||0));uv.push(...t.uv[i]);color.push(...t.color);}}
 const arrays=[pos,normal,uv,color],sizes=[3,3,2,3],count=pos.length/3,bytes=new Uint8Array(arrays.reduce((s,a)=>s+a.length*4,0)),dv=new DataView(bytes.buffer),views=[],accessors=[];let offset=0;
 arrays.forEach((a,i)=>{views.push({buffer:0,byteOffset:offset,byteLength:a.length*4,target:34962});a.forEach(v=>{dv.setFloat32(offset,v,true);offset+=4;});const acc={bufferView:i,componentType:5126,count,type:"VEC"+sizes[i]};if(i===0){acc.min=[0,1,2].map(j=>Math.min(...pos.filter((_,k)=>k%3===j)));acc.max=[0,1,2].map(j=>Math.max(...pos.filter((_,k)=>k%3===j)));}accessors.push(acc);});
 const name=spec.id+"_original_lod"+lod;
 const g={asset:{version:"2.0",generator:"Aster Valley original vegetation v1"},scene:0,scenes:[{nodes:[0]}],nodes:[{name,mesh:0}],meshes:[{name,primitives:[{attributes:{POSITION:0,NORMAL:1,TEXCOORD_0:2,COLOR_0:3},material:0,mode:4}]}],materials:[{name:"vegetation_vertex_color",doubleSided:true,alphaMode:"OPAQUE",pbrMetallicRoughness:{baseColorFactor:[1,1,1,1],metallicFactor:0,roughnessFactor:.88}}],buffers:[{byteLength:bytes.length,uri:"data:application/octet-stream;base64,"+b64(bytes)}],bufferViews:views,accessors};
 return JSON.stringify(g)+"\n";
 }
 return [encode(near,0),encode(far,1)];
}
const specs=[{"id":"shrub","d":[1.05,0.65,1.05],"seed":712},{"id":"fern","d":[1.05,0.44,1.05],"seed":232},{"id":"sapling","d":[0.95,1.65,0.95],"seed":812},{"id":"reed","d":[0.68,1.15,0.68],"seed":980},{"id":"wildflower","d":[0.42,0.52,0.42],"seed":420}];

function generate(){
 const files={},assets=[],notice="assets/environment_overhaul/LICENSE.txt",prefix="assets/environment_overhaul/";
 files[notice]="Original procedural vegetation created for Aster Valley. No external textures, models or source archives used. Generated asset payloads are offered under CC0 1.0 Universal: https://creativecommons.org/publicdomain/zero/1.0/ . Generator and tests remain project code. No endorsement of any third-party asset is implied.\n";
 for(const spec of specs){let a={species_id:spec.id,variant_id:"original_v1",dimensions_m:spec.d,origin:"ground_center",source_url:"local://tools/environment_assets/generate.mjs",author:"Aster Valley project (original procedural geometry)",license:"CC0-1.0",license_notice:"res://"+notice,sha256_by_path:{},status:"candidate",alpha:"opaque_geometry_no_cards",material_slots:["vegetation_vertex_color"],budget_by_path:{}};const pair=makePair(spec);for(let l=0;l<2;l++){const path=prefix+spec.id+"_lod"+l+".gltf",content=pair[l],g=JSON.parse(content),res="res://"+path;files[path]=content;a["lod"+l]=res;a.sha256_by_path[res]=sha256(content);a.budget_by_path[res]={triangles:g.accessors[0].count/3,surfaces:1,textures:0,bytes:content.length};}assets.push(a);}
 files[prefix+"manifest.json"]=JSON.stringify({schema_version:1,assets},null,2)+"\n";return files;
}


export {generate, specs};
