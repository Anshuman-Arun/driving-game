// Original CC0 Aster Valley authored scenery silhouettes. Node.js 20+, no dependencies.
function makeModels(){
 const pal={
 stone:[.43,.44,.42],timber:[.34,.23,.14],darkWood:[.20,.15,.12],plaster:[.73,.69,.58],brick:[.48,.31,.25],
 roof:[.21,.25,.28],roofRed:[.35,.20,.16],glass:[.22,.38,.44],trim:[.88,.79,.64],steel:[.35,.37,.37],steelLight:[.61,.64,.62],
 concrete:[.51,.51,.46],red:[.67,.25,.16],yellow:[.83,.65,.23],grass:[.38,.49,.3],boards:[.5,.33,.19],white:[.85,.83,.75]
 };
 const outputs={},stats={};
 function build(name,design){
  const groups=new Map();
  function group(mat){if(!pal[mat])throw Error("Unknown material "+mat);if(!groups.has(mat))groups.set(mat,{verts:[],norms:[],inds:[]});return groups.get(mat)}
  function tri(mat,a,b,c){
   const g=group(mat),u=[b[0]-a[0],b[1]-a[1],b[2]-a[2]],v=[c[0]-a[0],c[1]-a[1],c[2]-a[2]];
   const n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]],len=Math.hypot(...n)||1,at=g.verts.length/3;
   g.verts.push(...a,...b,...c);for(let i=0;i<3;i++)g.norms.push(n[0]/len,n[1]/len,n[2]/len);
   g.inds.push(at,at+1,at+2);
  }
  function quad(mat,a,b,c,d){tri(mat,a,b,c);tri(mat,a,c,d)}
  function box(mat,cx,cy,cz,sx,sy,sz){
   const x0=cx-sx/2,x1=cx+sx/2,y0=cy-sy/2,y1=cy+sy/2,z0=cz-sz/2,z1=cz+sz/2;
   quad(mat,[x0,y0,z1],[x1,y0,z1],[x1,y1,z1],[x0,y1,z1]);
   quad(mat,[x1,y0,z0],[x0,y0,z0],[x0,y1,z0],[x1,y1,z0]);
   quad(mat,[x0,y0,z0],[x0,y0,z1],[x0,y1,z1],[x0,y1,z0]);
   quad(mat,[x1,y0,z1],[x1,y0,z0],[x1,y1,z0],[x1,y1,z1]);
   quad(mat,[x0,y1,z1],[x1,y1,z1],[x1,y1,z0],[x0,y1,z0]);
   quad(mat,[x0,y0,z0],[x1,y0,z0],[x1,y0,z1],[x0,y0,z1]);
  }
  function gable(mat,width,depth,base,peak){
   const x=width/2,z=depth/2,y=base,yp=base+peak;
   quad(mat,[-x,y,-z],[0,yp,-z],[0,yp,z],[-x,y,z]);
   quad(mat,[0,yp,-z],[x,y,-z],[x,y,z],[0,yp,z]);
   tri("plaster",[-x,y,-z],[x,y,-z],[0,yp,-z]);tri("plaster",[x,y,z],[-x,y,z],[0,yp,z]);
  }
  function tapered(mat,bottom,top,low,high,sides=10){
   for(let i=0;i<sides;i++){
    const a=2*Math.PI*i/sides,b=2*Math.PI*(i+1)/sides;
    quad(mat,[Math.cos(a)*bottom,low,Math.sin(a)*bottom],[Math.cos(b)*bottom,low,Math.sin(b)*bottom],[Math.cos(b)*top,high,Math.sin(b)*top],[Math.cos(a)*top,high,Math.sin(a)*top]);
   }
  }
  function cone(mat,r,low,high,sides=10){
   for(let i=0;i<sides;i++){const a=2*Math.PI*i/sides,b=2*Math.PI*(i+1)/sides;tri(mat,[Math.cos(a)*r,low,Math.sin(a)*r],[Math.cos(b)*r,low,Math.sin(b)*r],[0,high,0]);}
  }
  function beam(mat,a,b,width,depth){
   const vx=b[0]-a[0],vy=b[1]-a[1],vlen=Math.hypot(vx,vy)||1,nx=-vy/vlen*width/2,ny=vx/vlen*width/2;
   const corners=[[a[0]+nx,a[1]+ny],[a[0]-nx,a[1]-ny],[b[0]-nx,b[1]-ny],[b[0]+nx,b[1]+ny]];
   const z=a[2],zf=z-depth/2,zb=z+depth/2;
   const f=corners.map(p=>[p[0],p[1],zf]),r=corners.map(p=>[p[0],p[1],zb]);
   quad(mat,f[0],f[1],f[2],f[3]);quad(mat,r[3],r[2],r[1],r[0]);for(let i=0;i<4;i++)quad(mat,f[i],r[i],r[(i+1)%4],f[(i+1)%4]);
  }
  design({box,gable,tapered,cone,beam,quad,tri});
  const views=[],accessors=[],buffer=[],materials=[];
  function pushBytes(v){while(buffer.length%4)buffer.push(0);const offset=buffer.length;for(const x of v)buffer.push(x);return offset;}
  function f32(values){const bin=new Uint8Array(values.length*4),view=new DataView(bin.buffer);values.forEach((x,i)=>view.setFloat32(i*4,x,true));return bin;}
  function u32(values){const bin=new Uint8Array(values.length*4),view=new DataView(bin.buffer);values.forEach((x,i)=>view.setUint32(i*4,x,true));return bin;}
  function accessor(values,typ,component,target){
   const data=component===5126?f32(values):u32(values),offset=pushBytes(data),viewIx=views.length;views.push({buffer:0,byteOffset:offset,byteLength:data.length,target});
   const item={bufferView:viewIx,componentType:component,count:values.length/(typ==="VEC3"?3:1),type:typ};
   if(typ==="VEC3" && target===34962 && component===5126) {
    const mins=[Infinity,Infinity,Infinity],maxs=[-Infinity,-Infinity,-Infinity];
    for(let i=0;i<values.length;i+=3)for(let k=0;k<3;k++){mins[k]=Math.min(mins[k],values[i+k]);maxs[k]=Math.max(maxs[k],values[i+k]);}
    item.min=mins;item.max=maxs;
   }
   const n=accessors.length;accessors.push(item);return n;
  }
  const primitives=[];let triangles=0;
  for(const [material,g] of groups){
   const p=accessor(g.verts,"VEC3",5126,34962),n=accessor(g.norms,"VEC3",5126,34962),id=accessor(g.inds,"SCALAR",5125,34963);
   const col=pal[material],matIndex=materials.length;materials.push({name:material,pbrMetallicRoughness:{baseColorFactor:[...col,1],metallicFactor:material.includes("steel")?.4:0,roughnessFactor:material==="glass"?.3:.83},doubleSided:true});
   primitives.push({attributes:{POSITION:p,NORMAL:n},indices:id,material:matIndex,mode:4});triangles+=g.inds.length/3;
  }
  const b64chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  while(buffer.length%4)buffer.push(0);
  let b64="";for(let i=0;i<buffer.length;i+=3){const n=(buffer[i]<<16)|((buffer[i+1]||0)<<8)|(buffer[i+2]||0);b64+=b64chars[(n>>>18)&63]+b64chars[(n>>>12)&63]+(i+1<buffer.length?b64chars[(n>>>6)&63]:"=")+(i+2<buffer.length?b64chars[n&63]:"=");}
  const gltf={asset:{version:"2.0",generator:"Aster Valley original parametric scenery models 1.0",copyright:"Aster Valley original artwork, CC0-1.0"},scene:0,scenes:[{nodes:[0]}],nodes:[{name,mesh:0}],meshes:[{name,primitives}],materials,buffers:[{byteLength:buffer.length,uri:"data:application/octet-stream;base64,"+b64}],bufferViews:views,accessors};
  outputs["content/scenery/models/"+name+".gltf"]=JSON.stringify(gltf);
  stats[name]={triangles,surfaces:primitives.length,bytes:buffer.length,materials:[...groups.keys()]};
 }
 build("town_house",({box,gable})=>{
  box("plaster",0,3.5,0,12,7.0,9);box("stone",0,.48,0,12.8,.96,9.7);gable("roof",13,10,7.1,3);
  box("darkWood",0,1.35,-4.56,2.0,2.7,.18);box("trim",0,2.85,-4.67,2.5,.24,.22);
  for(const y of [2.8,5.5])for(const x of [-4,-2.15,2.2,4]){if(y===2.8&&Math.abs(x)<2.5)continue;box("trim",x,y,-4.59,1.65,1.9,.19);box("glass",x,y,-4.72,1.24,1.46,.11);box("white",x,y,-4.8,.15,1.45,.05);box("white",x,y,-4.8,1.24,.13,.05);}
  box("brick",3.9,9.7,1.75,1.0,2.9,1.1);box("darkWood",0,2.8,-5.45,3.3,.18,1.7);
 });
 build("barn",({box,gable})=>{
  box("red",0,4,0,15,8,11.0);box("stone",0,.42,0,15.7,.83,11.7);gable("roofRed",16,12,8.12,4.0);
  for(const x of [-6.5,-4.3,4.3,6.5])box("timber",x,4.1,-5.62,.36,7.5,.22);
  box("darkWood",0,2.75,-5.64,5.2,5.5,.16);box("trim",0,6.5,-5.69,4.8,.24,.13);
  box("darkWood",0,8.85,-5.7,2.1,2.3,.2);box("yellow",0,8.8,-5.85,1.2,1.2,.1);
  for(const x of [-5.8,5.8])box("trim",x,5.3,-5.69,1.7,1.7,.2);
 });
 build("garage",({box,gable})=>{
  box("concrete",0,3.8,0,14,7.6,10);box("stone",0,.3,0,14.5,.6,10.5);box("roof",0,7.8,0,15,.75,10.8);
  for(const x of [-3.6,3.6]){box("steel",x,2.5,-5.12,5.3,4.7,.13);for(let y=.6;y<4.6;y+=.65)box("steelLight",x,y,-5.23,5.2,.09,.12);}
  box("red",0,6.4,-5.3,11,1.15,.17);box("white",0,6.4,-5.42,6.2,.22,.08);
  box("glass",6.3,4.2,-5.15,1.2,2.7,.12);
  for(const x of [-6.6,6.6])box("steel",x,2.9,-5.4,.25,5.8,.25);
 });
 build("windmill",({box,tapered,cone,beam})=>{
  tapered("stone",3.25,2.1,0,14.8,12);cone("roofRed",2.7,14.8,17.7,12);
  box("darkWood",0,1.6,-3.2,1.45,3.2,.2);box("glass",0,11.3,-2.22,1.15,1.5,.18);
  box("steel",0,13.7,-3.45,1.3,1.3,1.1);
  const z=-3.96;
  for(let i=0;i<4;i++){const a=i*Math.PI/2+Math.PI/4,v=[Math.sin(a),Math.cos(a)];beam("timber",[v[0]*.5,13.7+v[1]*.5,z],[v[0]*7.5,13.7+v[1]*7.5,z],.32,.22);
   beam("white",[v[0]*3.7,13.7+v[1]*3.7,z-.11],[v[0]*7.25,13.7+v[1]*7.25,z-.11],1.05,.12);
  }
 });
 build("stone_arch",({box})=>{
  box("stone",-3.4,2.8,0,2.1,5.6,2.5);box("stone",3.4,2.8,0,2.1,5.6,2.5);
  box("stone",0,6.0,0,9.0,1.25,2.9);box("roof",0,6.67,0,9.4,.32,3.1);
  for(const x of [-3.45,3.45])box("darkWood",x,2.5,-1.38,.22,4.1,.17);
 });
 build("overlook",({box})=>{
  box("stone",0,.45,0,12,.9,8);box("boards",0,1.0,0,11.6,.22,7.8);
  for(const z of [-3.55,3.55]){for(const x of [-5,0,5])box("timber",x,2.0,z,.28,2.2,.28);box("timber",0,2.9,z,11.4,.25,.28);}
  for(const x of [-5.55,5.55]){for(const z of [-2.4,2.4])box("timber",x,2,z,.28,2.2,.28);box("timber",x,2.9,0,.28,.25,7.5);}
  box("stone",0,.7,3.4,2,.8,1.0);
 });
 build("pier",({box})=>{
  // Compact timber shore-access platform (not a fake floating 25m lake pier).
  box("boards",0,1.0,-1.2,7.5,.3,8.2);
  for(const x of [-3.3,3.3])for(const z of [-4.8,.8,2.5])box("timber",x,-1.1,z,.48,4.2,.48);
  for(const x of [-3.4,3.4]){for(const z of [-4,-1,2])box("timber",x,2.0,z,.22,2,.22);box("timber",x,2.85,-1, .24,.22,7.5);}
  box("stone",0,-.1,2.7,7.6,.25,1.4);
  box("timber",0,1.5,2.2,1.8,2.5,.25);
 });
 build("quarry_hopper",({box,beam})=>{
  box("stone",0,.85,0,17,1.7,13);box("steel",0,5,0,10,1.4,7.4);
  for(const x of [-4.6,4.6])for(const z of [-2.9,2.9]){box("steel",x,3,z,.42,5,.42);box("yellow",x,6.1,z,.44,.35,.44);}
  box("darkWood",0,7,-1,7.4,2.8,6);box("stone",0,7.4,-4.25,8.2,1.6,1.0);
  beam("steel",[-5,1.6,-4.4],[-1.1,8,-4.4],.45,.6);beam("steel",[5,1.6,-4.4],[1.1,8,-4.4],.45,.6);
  box("steelLight",0,9.5,0,3.2,.35,7.8);box("red",0,5.0,-4.2,7.5,.55,.3);
  for(let x=-7;x<=7;x+=3.5)box("concrete",x,.8,6.2,2.9,1.6,1.8);
 });
 return {outputs,stats};
}
import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"../../..");
const out=makeModels();let bad=0;
for(const [relative,content] of Object.entries(out.outputs)) {const target=path.join(root,relative);
if(process.argv.includes("--check")){if(!fs.existsSync(target)||fs.readFileSync(target,"utf8")!==content){console.error("MISMATCH",relative);bad++;}}
else{fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,content);console.log("WROTE",relative);}}
console.log(JSON.stringify(out.stats,null,2));if(bad)process.exit(1);
