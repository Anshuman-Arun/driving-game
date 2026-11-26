function sha256(s){
 const a=Array.from(s,c=>c.charCodeAt(0)); if(a.some(x=>x>127))throw Error("ASCII only");
 const bits=a.length*8;a.push(128);while(a.length%64!==56)a.push(0);for(let i=7;i>=0;i--)a.push(Math.floor(bits/2**(8*i))&255);
 const K=[0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
 const h=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19], R=(x,n)=>(x>>>n)|(x<<(32-n));
 for(let o=0;o<a.length;o+=64){const w=[];for(let i=0;i<16;i++)w[i]=(a[o+4*i]<<24)|(a[o+4*i+1]<<16)|(a[o+4*i+2]<<8)|a[o+4*i+3];for(let i=16;i<64;i++){const x=w[i-15],y=w[i-2];w[i]=(w[i-16]+(R(x,7)^R(x,18)^(x>>>3))+w[i-7]+(R(y,17)^R(y,19)^(y>>>10)))|0;}let [A,B,C,D,E,F,G,H]=h;for(let i=0;i<64;i++){const t1=(H+(R(E,6)^R(E,11)^R(E,25))+((E&F)^(~E&G))+K[i]+w[i])|0,t2=((R(A,2)^R(A,13)^R(A,22))+((A&B)^(A&C)^(B&C)))|0;H=G;G=F;F=E;E=(D+t1)|0;D=C;C=B;B=A;A=(t1+t2)|0;}[A,B,C,D,E,F,G,H].forEach((x,i)=>h[i]=(h[i]+x)|0);}
 return h.map(x=>(x>>>0).toString(16).padStart(8,"0")).join("");
}

function b64(a){const abc="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";let s="";for(let i=0;i<a.length;i+=3){let n=(a[i]<<16)|((a[i+1]||0)<<8)|(a[i+2]||0);s+=abc[n>>>18]+abc[(n>>>12)&63]+(i+1<a.length?abc[(n>>>6)&63]:"=")+(i+2<a.length?abc[n&63]:"=");}return s;}

function un64(s){const abc="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";if(!/^[A-Za-z0-9+/]*={0,2}$/.test(s)||s.length%4)throw Error("bad base64");const a=[];for(let i=0;i<s.length;i+=4){let n=(abc.indexOf(s[i])<<18)|(abc.indexOf(s[i+1])<<12)|(Math.max(0,abc.indexOf(s[i+2]))<<6)|Math.max(0,abc.indexOf(s[i+3]));a.push(n>>>16);if(s[i+2]!=="=")a.push((n>>>8)&255);if(s[i+3]!=="=")a.push(n&255);}return Uint8Array.from(a);}

function makePair(spec){
 const add=(a,b)=>a.map((x,i)=>x+b[i]),sub=(a,b)=>a.map((x,i)=>x-b[i]),mul=(a,k)=>a.map(x=>x*k),dot=(a,b)=>a.reduce((s,x,i)=>s+x*b[i],0),cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]],norm=a=>mul(a,1/Math.sqrt(dot(a,a))),lerp=(a,b,t)=>add(mul(a,1-t),mul(b,t)),polar=(r,y,t)=>[r*Math.cos(t),y,r*Math.sin(t)];
 const groups=[], wood=[.16,.105,.049],green=[.095,.25,.049],fresh=[.19,.39,.075],dark=[.055,.15,.034],straw=[.45,.32,.10],flower=[.84,.72,.29];let state=spec.seed;
 function rnd(){state=(Math.imul(state,1664525)+1013904223)>>>0;return state/4294967296;}
 function triangle(a,b,c,color,uv=[[0,0],[1,0],[.5,1]]){return {p:[a,b,c],color,uv};}
 function tube(a,b,r0,r1,col,capStart=true,capEnd=true){
  const d=norm(sub(b,a)),u=norm(cross(d,Math.abs(d[1])>.9?[1,0,0]:[0,1,0])),v=cross(d,u);
  const ring=(center,r,k)=>add(center,add(mul(u,r*Math.cos(k*Math.PI/3)),mul(v,r*Math.sin(k*Math.PI/3))));
  const build=step=>{const out=[];for(let k=0;k<6;k+=step){const q=(k+step)%6,A=ring(a,r0,k),B=ring(a,r0,q),C=ring(b,r1,k),D=ring(b,r1,q);out.push(triangle(A,B,C,col),triangle(B,D,C,col));if(capStart)out.push(triangle(a,B,A,col));if(capEnd)out.push(triangle(b,C,D,col));}return out;};
  groups.push({near:build(1),far:build(2)});
 }
 function leaf(a,b,width,col,roll=0,retain=true){
  const d=norm(sub(b,a)),side=norm(cross(d,Math.abs(d[1])>.93?[1,0,0]:[0,1,0])),up=norm(cross(side,d));
  const s=add(mul(side,Math.cos(roll)),mul(up,Math.sin(roll))),ridge=add(lerp(a,b,.49),mul(up,width*.19)),l=add(lerp(a,b,.43),mul(s,width)),r=add(lerp(a,b,.43),mul(s,-width));
  const near=[triangle(a,l,ridge,col,[[.5,0],[0,.43],[.5,.49]]),triangle(l,b,ridge,col,[[0,.43],[.5,1],[.5,.49]]),triangle(a,ridge,r,col,[[.5,0],[.5,.49],[1,.43]]),triangle(ridge,b,r,col,[[.5,.49],[.5,1],[1,.43]])];
  const far=retain?[triangle(a,l,b,col,[[.5,0],[0,.43],[.5,1]]),triangle(a,b,r,col,[[.5,0],[.5,1],[1,.43]])]:[];
  groups.push({near,far});
 }
 function branch(a,b,r,col=wood,capStart=true,capEnd=true){tube(a,b,r,r*.4,col,capStart,capEnd);}
 const tau=2*Math.PI;
 if(spec.id==="shrub"||spec.id==="sapling"){
  const tall=spec.id==="sapling",n=tall?8:10;
  if(tall)tube([0,0,0],[.04,1.55,0],.034,.009,wood);
  for(let i=0;i<n;i++){const t=i*2.39996+.12*rnd(),base=tall?[0,.18+i*.13,0]:[0,0,0],tip=polar((tall?.36:.47)*(0.8+.2*rnd()),tall?.66+i*.125:.32+.24*rnd(),t);const mid=lerp(base,tip,.55);branch(base,mid,tall?.018:.012,wood,true,false);branch(mid,tip,.009,wood,false,true);for(let j=0;j<6;j++){const f=.20+j*.145,root=lerp(mid,tip,f),angle=t+(j%2?1:-1)*(.55+.16*(j%3)),length=tall?.19:.17;leaf(root,add(root,polar(length,.055,angle)),length*.35,j%3===0?fresh:green,.3*(j%3-1),j%2===0||j===5);}leaf(tip,add(tip,polar(.12,.075,t)),.055,fresh);}
 }else if(spec.id==="fern"){
  for(let i=0;i<8;i++){const angle=i*tau/8+.10*rnd(),r=.48+.09*rnd(),h=.27+.11*rnd(),point=t=>polar(r*t,h*Math.sin(t*2.15)+.025*t,angle);
   for(let k=0;k<6;k++){const n=6;branch(point(k/n),point((k+1)/n),.0055*(1-.65*k/n),fresh,k===0,k===5);}
   const count=9;for(let j=0;j<count;j++){let f=.14+.80*j/count,root=point(f),len=.145*Math.sin(Math.PI*f)*(.9+.1*rnd());for(let sign of [-1,1])leaf(root,add(root,polar(len,.015,angle+sign*.95)),len*.23,j%3?green:fresh,sign*.15,j%2===0);}
   leaf(point(.88),point(1),.024,fresh);
  }
 }else if(spec.id==="reed"){
  for(let i=0;i<7;i++){const angle=i*2.39996,base=polar(.075,0,angle),tip=add(base,polar(.12+.02*rnd(),.8+.28*rnd(),angle));branch(base,tip,.009,green);
   if(i%2===0){tube(lerp(base,tip,.76),lerp(base,tip,.97),.022,.018,wood);}
   for(let j=0;j<4;j++){const root=lerp(base,tip,.09+j*.14),end=add(root,polar(.34-.034*j,.38+.045*j,angle+(j%2?-.72:.72))),mid=add(lerp(root,end,.55),[0,.10,0]);leaf(root,mid,.031,green,0,j%2===0||j===3);leaf(mid,end,.021,fresh,0,j%2===0||j===3);}
  }
 }else if(spec.id==="wildflower"){
  for(let i=0;i<6;i++){const angle=i*2.39996,base=polar(.045,0,angle),tip=polar(.12+.07*rnd(),.34+.16*rnd(),angle);branch(base,tip,.0055,green);
   for(let j=0;j<4;j++){const root=lerp(base,tip,.14+j*.14);leaf(root,add(root,polar(.085,.025,angle+j*2.1)),.024,dark,0,j%2===0);}
   tube(add(tip,[0,-.012,0]),add(tip,[0,.006,0]),.017,.013,straw);for(let k=0;k<9;k++){const a=k*tau/9;leaf(tip,add(tip,polar(.052,.012,a)),.016,i%2?flower:[.72,.76,.65],0,k%2===0);}
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

function validateGeometry(files){
 const require=(condition,msg)=>{if(!condition)throw Error(msg);},prefix="assets/environment_overhaul/",m=JSON.parse(files[prefix+"manifest.json"]);require(m.schema_version===1&&Array.isArray(m.assets)&&m.assets.length===5,"schema/species count");const seen=new Set();
 for(const a of m.assets){require(specs.some(s=>s.id===a.species_id)&&!seen.has(a.species_id),"species");seen.add(a.species_id);require(a.variant_id&&a.origin==="ground_center"&&a.source_url&&a.author&&a.license==="CC0-1.0"&&a.license_notice==="res://"+prefix+"LICENSE.txt"&&files[a.license_notice.slice(6)],"license/metadata");require(Array.isArray(a.dimensions_m)&&a.dimensions_m.length===3&&a.dimensions_m.every(x=>Number.isFinite(x)&&x>0),"dimensions");let previous=Infinity;
  for(let l=0;l<2;l++){const p=a["lod"+l];require(typeof p==="string"&&p==="res://"+prefix+a.species_id+"_lod"+l+".gltf","path");const s=files[p.slice(6)];require(typeof s==="string"&&!s.startsWith("version https://git-lfs"),"missing payload or LFS pointer");require(sha256(s)===a.sha256_by_path[p],"hash");const g=JSON.parse(s);require(g.asset.version==="2.0"&&g.scenes[0].nodes[0]===0&&g.nodes[0].mesh===0&&g.meshes.length===1,"gltf scene");require(!g.images&&!g.textures,"unexpected/missing texture: original assets must be texture-free");require(g.materials.length===1&&g.materials[0].alphaMode==="OPAQUE"&&g.materials[0].doubleSided===true,"material");const prim=g.meshes[0].primitives[0];require(prim.mode===4&&prim.material===0&&!prim.indices&&g.meshes[0].primitives.length===1,"triangle primitive");const buf=g.buffers[0];require(buf.uri.startsWith("data:application/octet-stream;base64,"),"buffer URI");const b=un64(buf.uri.split(",")[1]);require(b.length===buf.byteLength,"buffer length");const d=new DataView(b.buffer,b.byteOffset,b.byteLength),count=g.accessors[0].count;require(count%3===0&&count>0&&count/3<previous&&count/3<=1500,"LOD or triangle budget");previous=count/3;const expected=a.budget_by_path[p];require(expected.triangles===count/3&&expected.surfaces===1&&expected.textures===0&&expected.bytes===s.length,"budget");const attrs=["POSITION","NORMAL","TEXCOORD_0","COLOR_0"],sizes=[3,3,2,3],decoded=[];
   for(let k=0;k<4;k++){const acc=g.accessors[prim.attributes[attrs[k]]],v=g.bufferViews[acc.bufferView],dim=sizes[k];require(acc.componentType===5126&&acc.type==="VEC"+dim&&acc.count===count&&v.buffer===0&&v.byteLength===count*dim*4&&v.byteOffset%4===0&&v.byteOffset>=0&&v.byteOffset+v.byteLength<=b.length,"accessor bounds");const rows=[];for(let i=0;i<count;i++){const row=Array.from({length:dim},(_,j)=>d.getFloat32(v.byteOffset+(i*dim+j)*4,true));require(row.every(Number.isFinite),"nonfinite vertex");rows.push(row);}decoded.push(rows);}
   const [pos,normals,uv,colors]=decoded;for(let k=0;k<3;k++){const min=Math.min(...pos.map(p=>p[k])),max=Math.max(...pos.map(p=>p[k])),target=a.dimensions_m[k];require(Math.abs(max-min-target)<1e-5&&Math.abs(min-(k===1?0:-target/2))<1e-5,"bounds/origin");require(Math.abs(min-g.accessors[0].min[k])<1e-6&&Math.abs(max-g.accessors[0].max[k])<1e-6,"accessor min/max");}
   for(let i=0;i<count;i+=3){const x=pos[i+1].map((v,j)=>v-pos[i][j]),y=pos[i+2].map((v,j)=>v-pos[i][j]),n=[x[1]*y[2]-x[2]*y[1],x[2]*y[0]-x[0]*y[2],x[0]*y[1]-x[1]*y[0]],len=Math.hypot(...n);require(len>1e-9,"degenerate triangle");for(let j=i;j<i+3;j++){require(Math.abs(Math.hypot(...normals[j])-1)<1e-5&&n.reduce((sum,v,k)=>sum+v*normals[j][k],0)/len>.999,"normal mismatch");require(uv[j].every(v=>v>=0&&v<=1)&&colors[j].every(v=>v>=0&&v<=1),"UV/color range");}}
  }
 }return m.assets.map(a=>({species:a.species_id,lod0:a.budget_by_path[a.lod0].triangles,lod1:a.budget_by_path[a.lod1].triangles,bytes:a.budget_by_path[a.lod0].bytes+a.budget_by_path[a.lod1].bytes}));
}

function validate(files){
 const check=(ok,msg)=>{if(!ok)throw Error(msg);};
 const exact=(obj,keys,msg)=>check(obj!==null&&typeof obj==="object"&&!Array.isArray(obj)&&Object.keys(obj).sort().join("|")===keys.slice().sort().join("|"),msg);
 const prefix="assets/environment_overhaul/",m=JSON.parse(files[prefix+"manifest.json"]);
 exact(m,["schema_version","assets"],"manifest keys");check(m.schema_version===1&&Array.isArray(m.assets)&&m.assets.length===specs.length,"manifest schema");
 check(typeof files[prefix+"LICENSE.txt"]==="string"&&files[prefix+"LICENSE.txt"].includes("CC0 1.0 Universal")&&files[prefix+"LICENSE.txt"].includes("https://creativecommons.org/publicdomain/zero/1.0/"),"license notice");
 const seen=new Set();
 for(const a of m.assets){
  exact(a,["species_id","variant_id","dimensions_m","origin","source_url","author","license","license_notice","sha256_by_path","status","alpha","material_slots","budget_by_path","lod0","lod1"],"manifest entry keys");
  const spec=specs.find(s=>s.id===a.species_id);check(spec&&!seen.has(a.species_id),"species");seen.add(a.species_id);
  check(a.variant_id==="original_v1"&&a.origin==="ground_center"&&a.source_url==="local://tools/environment_assets/generate.mjs"&&a.author==="Aster Valley project (original procedural geometry)"&&a.license==="CC0-1.0"&&a.license_notice==="res://"+prefix+"LICENSE.txt"&&a.status==="candidate"&&a.alpha==="opaque_geometry_no_cards"&&JSON.stringify(a.material_slots)==='["vegetation_vertex_color"]',"license/metadata");
  check(JSON.stringify(a.dimensions_m)===JSON.stringify(spec.d),"dimensions");
  const paths=[0,1].map(l=>"res://"+prefix+a.species_id+"_lod"+l+".gltf");exact(a.sha256_by_path,paths,"hash coverage");exact(a.budget_by_path,paths,"budget coverage");
  let nearVertices=null,nearCount=0;
  for(let l=0;l<2;l++){
   const p=a["lod"+l];check(p===paths[l],"path");
   const s=files[p.slice(6)];check(typeof s==="string"&&!s.startsWith("version https://git-lfs"),"missing payload or LFS pointer");
   check(s.length<=500000&&/^[0-9a-f]{64}$/.test(a.sha256_by_path[p])&&sha256(s)===a.sha256_by_path[p],"hash/size");
   const g=JSON.parse(s);
   exact(g,["asset","scene","scenes","nodes","meshes","materials","buffers","bufferViews","accessors"],"gltf top-level keys");
   exact(g.asset,["version","generator"],"asset keys");check(g.asset.version==="2.0","gltf version");
   check(g.scene===0&&Array.isArray(g.scenes)&&g.scenes.length===1&&Array.isArray(g.nodes)&&g.nodes.length===1&&Array.isArray(g.meshes)&&g.meshes.length===1,"scene cardinality");
   exact(g.scenes[0],["nodes"],"scene keys");check(JSON.stringify(g.scenes[0].nodes)==="[0]","scene nodes");
   exact(g.nodes[0],["name","mesh"],"node keys");check(g.nodes[0].mesh===0&&g.nodes[0].name===a.species_id+"_original_lod"+l,"node identity");
   exact(g.meshes[0],["name","primitives"],"mesh keys");check(g.meshes[0].name===g.nodes[0].name&&Array.isArray(g.meshes[0].primitives)&&g.meshes[0].primitives.length===1,"mesh identity");
   const prim=g.meshes[0].primitives[0];exact(prim,["attributes","material","mode"],"primitive keys");check(prim.mode===4&&prim.material===0,"triangle primitive");
   const attrs=["POSITION","NORMAL","TEXCOORD_0","COLOR_0"],sizes=[3,3,2,3];exact(prim.attributes,attrs,"attribute keys");check(attrs.every((name,i)=>prim.attributes[name]===i),"attribute indices");
   check(Array.isArray(g.materials)&&g.materials.length===1,"material count");const mat=g.materials[0];exact(mat,["name","doubleSided","alphaMode","pbrMetallicRoughness"],"material keys");
   check(mat.name==="vegetation_vertex_color"&&mat.alphaMode==="OPAQUE"&&mat.doubleSided===true,"material mode");const pbr=mat.pbrMetallicRoughness;exact(pbr,["baseColorFactor","metallicFactor","roughnessFactor"],"PBR keys");check(JSON.stringify(pbr.baseColorFactor)==="[1,1,1,1]"&&pbr.metallicFactor===0&&pbr.roughnessFactor===.88,"PBR values");
   check(Array.isArray(g.buffers)&&g.buffers.length===1&&Array.isArray(g.bufferViews)&&g.bufferViews.length===4&&Array.isArray(g.accessors)&&g.accessors.length===4,"buffer cardinality");
   const buf=g.buffers[0];exact(buf,["byteLength","uri"],"buffer keys");
   check(Number.isSafeInteger(buf.byteLength)&&buf.byteLength>0&&buf.byteLength<=375000&&typeof buf.uri==="string"&&buf.uri.startsWith("data:application/octet-stream;base64,"),"buffer URI/size");
   const encoded=buf.uri.slice("data:application/octet-stream;base64,".length),b=un64(encoded);check(b64(b)===encoded&&b.length===buf.byteLength,"buffer length/canonical base64");
   const count=g.accessors[0].count;check(Number.isSafeInteger(count)&&count%3===0&&count>0&&count/3<=1500,"LOD or triangle budget");
   if(l===0)nearCount=count;else check(count<=nearCount*.65,"LOD reduction");
   const budget=a.budget_by_path[p];exact(budget,["triangles","surfaces","textures","bytes"],"budget keys");
   let offset=0;
   for(let k=0;k<4;k++){
    const acc=g.accessors[k],v=g.bufferViews[k],dim=sizes[k];exact(acc,k===0?["bufferView","componentType","count","type","min","max"]:["bufferView","componentType","count","type"],"accessor keys");exact(v,["buffer","byteOffset","byteLength","target"],"view keys");
    check(acc.bufferView===k&&acc.componentType===5126&&acc.type==="VEC"+dim&&acc.count===count&&v.buffer===0&&v.target===34962&&v.byteLength===count*dim*4&&v.byteOffset===offset&&v.byteOffset+v.byteLength<=b.length,"accessor bounds");offset+=v.byteLength;
   }
   check(offset===b.length,"trailing buffer bytes");
   check([g.accessors[0].min,g.accessors[0].max].every(v=>Array.isArray(v)&&v.length===3&&v.every(Number.isFinite)),"accessor bounds metadata");
   const d=new DataView(b.buffer,b.byteOffset,b.byteLength),vertices=new Set();
   for(let i=0;i<count;i++){const v=[];for(const k of [0,3])for(let j=0;j<3;j++)v.push(d.getFloat32(g.bufferViews[k].byteOffset+(i*3+j)*4,true));check(v.every(Number.isFinite),"nonfinite vertex");vertices.add(v.join(","));}
   if(l===0)nearVertices=vertices;else check([...vertices].every(v=>nearVertices.has(v)),"LOD scaffold mismatch");
  }
 }
 return validateGeometry(files);
}

function selfTest(files){
 if(sha256("")!=="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"||sha256("abc")!=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")throw Error("SHA256 vectors");
 const other=generate();if(JSON.stringify(other)!==JSON.stringify(files))throw Error("non-deterministic");const report=validate(files),mPath="assets/environment_overhaul/manifest.json",asset="assets/environment_overhaul/shrub_lod0.gltf";
 const rejected=[];
 function reject(name,reason,modify){const f={...files},m=JSON.parse(f[mPath]);modify(f,m);f[mPath]=JSON.stringify(m);try{validate(f);}catch(e){if(e.message!==reason)throw Error(name+": wrong failure: "+e.message+" expected "+reason);rejected.push(name);return;}throw Error("negative fixture accepted: "+name);}
 function edit(f,m,fn,path=asset){const g=JSON.parse(f[path]);fn(g);f[path]=JSON.stringify(g)+"\n";m.assets[0].sha256_by_path["res://"+path]=sha256(f[path]);m.assets[0].budget_by_path["res://"+path].bytes=f[path].length;}
 reject("missing texture","gltf top-level keys",(f,m)=>edit(f,m,g=>{g.images=[{uri:"missing.png"}];g.textures=[{source:0}];}));reject("LFS pointer","missing payload or LFS pointer",(f,m)=>{f[asset]="version https://git-lfs.github.com/spec/v1\n";});reject("malformed mesh","LOD or triangle budget",(f,m)=>edit(f,m,g=>{g.accessors[0].count=4;}));reject("missing license","manifest entry keys",(f,m)=>{delete m.assets[0].license;});reject("hash mismatch","hash/size",f=>{f[asset]+=" ";});reject("missing file","missing payload or LFS pointer",f=>{delete f[asset];});
 reject("degenerate geometry","degenerate triangle",(f,m)=>edit(f,m,g=>{const b=un64(g.buffers[0].uri.split(",")[1]);b.set(b.slice(0,12),12);g.buffers[0].uri="data:application/octet-stream;base64,"+b64(b);}));

 reject("translated node","node keys",(f,m)=>edit(f,m,g=>{g.nodes[0].translation=[100,0,0];}));
 reject("wrong scene","scene cardinality",(f,m)=>edit(f,m,g=>{g.scene=1;}));
 reject("zero index accessor","primitive keys",(f,m)=>edit(f,m,g=>{g.meshes[0].primitives[0].indices=0;}));
 reject("wrong accessor offset","accessor keys",(f,m)=>edit(f,m,g=>{g.accessors[0].byteOffset=4;}));
 reject("unsupported stride","view keys",(f,m)=>edit(f,m,g=>{g.bufferViews[0].byteStride=16;}));
 reject("sparse override","accessor keys",(f,m)=>edit(f,m,g=>{g.accessors[0].sparse={count:1,indices:{bufferView:1,componentType:5123},values:{bufferView:2}};}));
 reject("missing material texture","PBR keys",(f,m)=>edit(f,m,g=>{g.materials[0].pbrMetallicRoughness.baseColorTexture={index:0};}));
 reject("transparent factor","PBR values",(f,m)=>edit(f,m,g=>{g.materials[0].pbrMetallicRoughness.baseColorFactor=[0,0,0,0];}));
 reject("extra node","scene cardinality",(f,m)=>edit(f,m,g=>{g.nodes.push({mesh:0});g.scenes[0].nodes.push(1);}));
 reject("wrong material","material mode",(f,m)=>edit(f,m,g=>{g.materials[0].doubleSided=false;}));
 reject("wrong UV accessor","attribute indices",(f,m)=>edit(f,m,g=>{g.meshes[0].primitives[0].attributes.TEXCOORD_0=0;}));
 reject("duplicate species","species",(f,m)=>{m.assets[1]=m.assets[0];});
 reject("extra hash","hash coverage",(f,m)=>{m.assets[0].sha256_by_path["res://unowned"]=sha256("test");});
 reject("wrong notice","license notice",f=>{f["assets/environment_overhaul/LICENSE.txt"]="unlicensed";});
 reject("path traversal","path",(f,m)=>{m.assets[0].lod0="res://assets/environment_overhaul/../other.gltf";});
 reject("far color no longer on shared scaffold","LOD scaffold mismatch",(f,m)=>edit(f,m,g=>{const b=un64(g.buffers[0].uri.split(",")[1]),v=new DataView(b.buffer);v.setFloat32(g.bufferViews[3].byteOffset,.314159,true);g.buffers[0].uri="data:application/octet-stream;base64,"+b64(b);},"assets/environment_overhaul/shrub_lod1.gltf"));
 reject("nonfinite attribute","nonfinite vertex",(f,m)=>edit(f,m,g=>{const b=un64(g.buffers[0].uri.split(",")[1]);new DataView(b.buffer).setFloat32(0,NaN,true);g.buffers[0].uri="data:application/octet-stream;base64,"+b64(b);}));
 return {report,negative_fixtures:rejected.length,rejected,determinism:true,sha256_vectors:2,lod_shared_scaffold:true};
}
import {fileURLToPath} from "node:url";
import crypto from "node:crypto";
import {stageFiles, readFiles} from "./staging.mjs";
const root = fileURLToPath(new URL("../../", import.meta.url));
const mode = process.argv[2] || "--verify";
if (process.argv.length > 3 || !["--stage","--verify","--self-test"].includes(mode)) throw Error("Use --stage, --verify or --self-test");
const expected = generate();
const result = selfTest(expected);
for (const [p,s] of Object.entries(expected)) {
  if (sha256(s) !== crypto.createHash("sha256").update(s).digest("hex")) throw Error("SHA256 mismatch: "+p);
}
if(mode==="--stage") result.changed_files=stageFiles(root,expected);
if(mode!=="--self-test") validate(readFiles(root,expected));
console.log(JSON.stringify(result,null,2));
