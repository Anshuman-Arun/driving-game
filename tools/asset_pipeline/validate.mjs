// Structural validator for Aster Valley curated 3D assets (Node.js 20+, no npm dependencies).
import {readFileSync,existsSync} from "node:fs";
import {join,extname} from "node:path";
function b64decode(s){const abc="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",v=s.replace(/\s/g,""),out=[];
 for(let i=0;i<v.length;i+=4){let a=abc.indexOf(v[i]),b=abc.indexOf(v[i+1]),c=v[i+2]==="="?-1:abc.indexOf(v[i+2]),d=v[i+3]==="="?-1:abc.indexOf(v[i+3]);
 if(a<0||b<0||c < -1||d < -1)throw Error("invalid base64");
 out.push((a<<2)|(b>>4));if(c>=0)out.push(((b&15)<<4)|(c>>2));if(d>=0)out.push(((c&3)<<6)|d)}
 return new Uint8Array(out)}
function asciiDecode(a){let s="";for(let i=0;i<a.length;i+=32768)s+=String.fromCharCode(...a.slice(i,i+32768));return s}
function parseModel(bytes,format){
 let j,bin;
 if(format==="glb"){
  const d=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength),u=o=>d.getUint32(o,true);
  if(bytes.length<32||u(0)!==0x46546c67||u(4)!==2||u(8)!==bytes.length||u(16)!==0x4e4f534a)throw Error("GLB header");
  let jsonLen=u(12),binLen=u(20+jsonLen);
  if(u(24+jsonLen)!==0x004e4942||28+jsonLen+binLen!==bytes.length)throw Error("GLB chunks");
  j=JSON.parse(asciiDecode(bytes.slice(20,20+jsonLen)).trim());
  bin=bytes.slice(28+jsonLen,28+jsonLen+j.buffers[0].byteLength);
 }else{
  j=JSON.parse(typeof bytes==="string"?bytes:asciiDecode(bytes));
  if(j.buffers?.length!==1||!j.buffers[0].uri?.startsWith("data:application/octet-stream;base64,"))throw Error("nonembedded glTF");
  bin=b64decode(j.buffers[0].uri.split(",")[1]);
 }
 if(j.asset?.version!=="2.0"||j.buffers.length!==1||bin.length!==j.buffers[0].byteLength)throw Error("glTF buffer");
 return {j,bin}
}
function validateModel(bytes,format,vehicle=false){
 const {j,bin}=parseModel(bytes,format);
 if(!j.meshes?.length||!j.nodes?.length||!j.materials?.length)throw Error("empty model");
 for(const v of j.bufferViews){
  if(v.buffer!==0||v.byteOffset%4||v.byteOffset+v.byteLength>bin.length)throw Error("bufferView bounds / alignment")}
 let triCount=0;
 for(const mesh of j.meshes)for(const p of mesh.primitives){
  const pa=j.accessors[p.attributes.POSITION],na=j.accessors[p.attributes.NORMAL],ia=j.accessors[p.indices];
  if(p.mode!==4||p.material>=j.materials.length||pa.count!==na.count||ia.count%3)throw Error("mesh attributes");
  const checkAcc=(a,dimension,componentBytes)=>{
   const view=j.bufferViews[a.bufferView],offset=(a.byteOffset||0),size=a.count*dimension*componentBytes;
   if(offset+size>view.byteLength)throw Error("accessor outside view");
  };
  checkAcc(pa,3,4);checkAcc(na,3,4);checkAcc(ia,1,ia.componentType===5123?2:4);
  if(!pa.min||!pa.max||pa.min.some((v,i)=>!Number.isFinite(v)||v>pa.max[i]))throw Error("POSITION range");
  triCount+=ia.count/3;
 }
 if(vehicle){
  for(const key of ["FL","FR","RL","RR"]){
   const root=j.nodes.find(n=>n.name==="Wheel_"+key+"_Pivot");
   if(!root||!Array.isArray(root.children)||!Array.isArray(root.translation)||root.translation.length!==3)throw Error("wheel pivot "+key);
   let names=root.children.map(i=>j.nodes[i]?.name);
   if(!names.includes("Tire_"+key)||!names.includes("Rim_"+key)||!names.includes("Brake_"+key))throw Error("wheel meshes "+key);
  }
  const p=j.nodes.filter(n=>n.name.endsWith("_Pivot"));if(p.length!==4)throw Error("wheel count");
 }
 return {triangles:triCount,meshes:j.meshes.length,nodes:j.nodes.length,bytes:bin.length}
}
function crc32(bytes){let c=0xffffffff;for(const n of bytes){c^=n;for(let k=0;k<8;k++)c=(c&1)?(c>>>1)^0xedb88320:(c>>>1)}return (c^0xffffffff)>>>0}
function validatePNG(bytes){
 const d=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength),u=n=>d.getUint32(n,false);
 if(bytes.length<60||u(0)!==0x89504e47||u(4)!==0x0d0a1a0a)throw Error("PNG signature");
 let off=8,w=0,h=0,seen=[],idat=0;
 while(off<bytes.length){let len=u(off),type=asciiDecode(bytes.slice(off+4,off+8));if(off+12+len>bytes.length)throw Error("PNG length");
  if(crc32(bytes.slice(off+4,off+8+len))!==u(off+8+len))throw Error("PNG CRC "+type);
  if(type==="IHDR"){w=u(off+8);h=u(off+12);if(bytes[off+16]!==8||bytes[off+17]!==6)throw Error("PNG mode")}
  if(type==="IDAT")idat+=len;seen.push(type);off+=12+len;
 }
 if(off!==bytes.length||w!==256||h!==256||idat<256*256*4||seen[0]!=="IHDR"||seen.at(-1)!=="IEND")throw Error("PNG dimensions/chunks");
 return {width:w,height:h,idatBytes:idat}
}
const root=process.argv[2]||".";
const manifest=JSON.parse(readFileSync(join(root,"assets/curated/MANIFEST.json"),"utf8"));
let total=0,cars=0,environment=0,textures=0,materialFiles=0,triangles=0;
const seen=new Set();
for(const asset of manifest.assets){if(seen.has(asset.path))throw Error("duplicate "+asset.path);seen.add(asset.path);const path=join(root,asset.path);if(!existsSync(path))throw Error("missing "+path);const ext=extname(path);if(ext===".glb"||ext===".gltf"){const bytes=new Uint8Array(readFileSync(path));const result=validateModel(bytes,ext.slice(1),asset.category==="vehicle");if(result.triangles!==asset.triangle_count)throw Error("manifest triangle mismatch "+asset.path);triangles+=result.triangles;if(asset.category==="vehicle")cars++;else environment++;const preview=join(root,"assets/curated/previews",asset.id+".svg");if(!existsSync(preview))throw Error("missing preview "+preview)}else if(ext===".png"){validatePNG(new Uint8Array(readFileSync(path)));textures++}else if(ext===".tres"){let s=readFileSync(path,"utf8");if(!s.includes("StandardMaterial3D")||!s.includes("normal_texture")||!s.includes("albedo_texture"))throw Error("material preset invalid "+path);materialFiles++}total++;}
const expected={vehicle:6,environment:18,texture:14,material:7};if(cars!==expected.vehicle||environment!==expected.environment||textures!==expected.texture||materialFiles!==expected.material)throw Error("unexpected inventory "+JSON.stringify({cars,environment,textures,materialFiles}));
console.log(JSON.stringify({success:true,total,cars,environment,textures,materialFiles,triangles},null,2));
