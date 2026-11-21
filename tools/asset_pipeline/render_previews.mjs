// Recreate self-contained SVG previews by decoding the actual glTF/GLB meshes.
import {readFileSync,writeFileSync,mkdirSync} from "node:fs";
import {join,extname,basename} from "node:path";
function b64decode(s){let c="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",v=s.replace(/\s/g,""),o=[];
 for(let i=0;i<v.length;i+=4){let a=c.indexOf(v[i]),b=c.indexOf(v[i+1]),d=v[i+2]==="="?-1:c.indexOf(v[i+2]),e=v[i+3]==="="?-1:c.indexOf(v[i+3]);
 o.push((a<<2)|(b>>4));if(d>=0)o.push(((b&15)<<4)|(d>>2));if(e>=0)o.push(((d&3)<<6)|e)}
 return new Uint8Array(o)}
function decodeText(a){let out="";for(let i=0;i<a.length;i+=32768)out+=String.fromCharCode(...a.slice(i,i+32768));return out}
function readModel(src,format){
 let j,bin;
 if(format==="glb"){let d=new DataView(src.buffer,src.byteOffset,src.byteLength),u=n=>d.getUint32(n,true),n=u(12);
  if(u(0)!==0x46546c67||u(16)!==0x4e4f534a)throw Error("GLB invalid");
  j=JSON.parse(decodeText(src.slice(20,20+n)).trim());bin=src.slice(28+n,28+n+j.buffers[0].byteLength)}
 else{j=JSON.parse(typeof src==="string"?src:decodeText(src));bin=b64decode(j.buffers[0].uri.split(",")[1])}
 if(bin.length!==j.buffers[0].byteLength)throw Error("buffer length");
 return {j,bin}
}
function plus(a,b){return a.map((x,i)=>x+b[i])}
function minus(a,b){return a.map((x,i)=>x-b[i])}
function times(a,s){return a.map(x=>x*s)}
function dot(a,b){return a.reduce((x,y,i)=>x+y*b[i],0)}
function cross(a,b){return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]}
function unit(a){return times(a,1/(Math.sqrt(dot(a,a))||1))}
function trianglesOf(model){
 let {j,bin}=model,d=new DataView(bin.buffer,bin.byteOffset,bin.byteLength),out=[];
 const accessorData=(a,i)=>{let v=j.bufferViews[a.bufferView],offset=v.byteOffset+(a.byteOffset||0),stride=v.byteStride||((a.type==="VEC3"?3:1)*(a.componentType===5126?4:a.componentType===5123?2:4));
  let o=offset+i*stride;
  if(a.componentType===5126)return [d.getFloat32(o,true),d.getFloat32(o+4,true),d.getFloat32(o+8,true)];
  if(a.componentType===5123)return d.getUint16(o,true);
  if(a.componentType===5125)return d.getUint32(o,true);
  throw Error("unsupported accessor "+a.componentType)};
 const walk=(ni,offset)=>{
  const n=j.nodes[ni],loc=plus(offset,n.translation||[0,0,0]);
  if(n.mesh!==undefined){for(const p of j.meshes[n.mesh].primitives){
   const a=j.accessors[p.attributes.POSITION],i=j.accessors[p.indices],rgb=j.materials[p.material].pbrMetallicRoughness.baseColorFactor;
   for(let k=0;k<i.count;k+=3)out.push({vertices:[0,1,2].map(t=>plus(accessorData(a,accessorData(i,k+t)),loc)),rgba:rgb});
  }}
  for(const ch of n.children||[])walk(ch,loc)
 };
 for(const i of j.scenes[j.scene||0].nodes)walk(i,[0,0,0]);
 return out
}
function renderPreview(src,format,label){
 const t=trianglesOf(readModel(src,format));if(!t.length)throw Error("empty triangles");
 const W=960,H=620,eye=unit([.55,.40,-.73]),right=unit(cross([0,1,0],eye)),up=unit(cross(eye,right)),sun=unit([-.54,.86,-.3]);
 const all=t.map(f=>{
  const plane=f.vertices.map(v=>[dot(v,right),dot(v,up)]),face=unit(cross(minus(f.vertices[1],f.vertices[0]),minus(f.vertices[2],f.vertices[0])));
  const light=Math.max(.36,.72+dot(face,sun)*.30);
  const color="#"+f.rgba.slice(0,3).map(c=>Math.max(0,Math.min(255,Math.round(c*light*255))).toString(16).padStart(2,"0")).join("");
  return {plane,z:f.vertices.reduce((a,v)=>a+dot(v,eye),0)/3,color,alpha:f.rgba[3]??1}
 });
 const xs=all.flatMap(f=>f.plane.map(p=>p[0])),ys=all.flatMap(f=>f.plane.map(p=>p[1]));
 const xmin=Math.min(...xs),xmax=Math.max(...xs),ymin=Math.min(...ys),ymax=Math.max(...ys);
 const scale=Math.min(760/Math.max(.01,xmax-xmin),475/Math.max(.01,ymax-ymin)),cx=(xmin+xmax)/2,cy=(ymin+ymax)/2;
 all.sort((a,b)=>a.z-b.z);
 const polygons=all.map(f=>`<polygon points="${f.plane.map(p=>`${(W/2+(p[0]-cx)*scale).toFixed(1)},${(H*.56-(p[1]-cy)*scale).toFixed(1)}`).join(" ")}" fill="${f.color}" opacity="${f.alpha.toFixed(2)}"/>`).join("");
 const title=label.replace(/&/g,"&amp;").replace(/</g,"&lt;");
 return {svg:`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}"><defs><linearGradient id="bg" x2="0" y2="1"><stop stop-color="#203541"/><stop offset="1" stop-color="#0e1921"/></linearGradient></defs><rect width="${W}" height="${H}" fill="url(#bg)"/><ellipse cx="480" cy="511" rx="245" ry="25" fill="#020508" opacity=".4"/>${polygons}<text x="26" y="49" font-family="Arial,sans-serif" font-size="32" fill="#eef2ec">${title}</text><text x="27" y="593" font-family="Arial,sans-serif" font-size="15" fill="#97abb5">Generated from authored glTF / GLB triangle geometry</text></svg>`,triangles:all.length}
}
const root=process.argv[2]||".";const manifest=JSON.parse(readFileSync(join(root,"assets/curated/MANIFEST.json"),"utf8"));
for(const asset of manifest.assets.filter(a=>a.category==="vehicle"||a.category==="environment")){const src=join(root,asset.path),data=new Uint8Array(readFileSync(src));const result=renderPreview(data,extname(src).slice(1),asset.id.replace(/_/g," ").toUpperCase());const destination=join(root,"assets/curated/previews",asset.id+".svg");mkdirSync(join(root,"assets/curated/previews"),{recursive:true});writeFileSync(destination,result.svg);console.log(asset.id,result.triangles)}
