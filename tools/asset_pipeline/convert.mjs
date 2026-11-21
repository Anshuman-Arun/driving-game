// Aster Valley: hierarchy-preserving standalone glTF/GLB conversion.
// No external dependencies; invoke from repository root with Node 20+.
import {readFileSync,writeFileSync,mkdirSync,readdirSync} from "node:fs";
import {dirname,join,extname} from "node:path";
function decode64(s){let c="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",v=s.replace(/\s/g,""),out=[];
 for(let i=0;i<v.length;i+=4){let a=c.indexOf(v[i]),b=c.indexOf(v[i+1]),d=v[i+2]==="="?-1:c.indexOf(v[i+2]),e=v[i+3]==="="?-1:c.indexOf(v[i+3]);
  out.push((a<<2)|(b>>4));if(d>=0)out.push(((b&15)<<4)|(d>>2));if(e>=0)out.push(((d&3)<<6)|e)}
 return new Uint8Array(out)}
function encode64(a){let c="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",out=[];for(let i=0;i<a.length;i+=3){let x=a[i],y=i+1<a.length?a[i+1]:0,z=i+2<a.length?a[i+2]:0;
 out.push(c[x>>2],c[((x&3)<<4)|(y>>4)],i+1<a.length?c[((y&15)<<2)|(z>>6)]:"=",i+2<a.length?c[z&63]:"=")}return out.join("")}
function fromGLB(bytes){let d=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength),U=n=>d.getUint32(n,true);
 if(U(0)!==0x46546c67||U(4)!==2||U(8)!==bytes.length)throw Error("invalid GLB");
 let jlen=U(12);if(U(16)!==0x4e4f534a||U(24+jlen)!==0x004e4942)throw Error("invalid GLB chunks");
 let j=JSON.parse(String.fromCharCode(...bytes.slice(20,20+jlen)).trim()),start=28+jlen,len=U(20+jlen);
 let bin=bytes.slice(start,start+j.buffers[0].byteLength);
 if(bin.length!==j.buffers[0].byteLength||len<bin.length)throw Error("invalid BIN length");
 j.buffers[0].uri="data:application/octet-stream;base64,"+encode64(bin);
 return j}
function toGLB(j){
 let doc=JSON.parse(JSON.stringify(j)),v=doc.buffers?.[0],uri=v?.uri;
 if(typeof uri!=="string"||!uri.startsWith("data:application/octet-stream;base64,"))throw Error("only embedded source buffers allowed");
 let bin=decode64(uri.slice(uri.indexOf(",")+1));if(bin.length!==v.byteLength)throw Error("buffer length mismatch");
 delete v.uri;
 let js=JSON.stringify(doc),txt=Uint8Array.from(js,c=>c.charCodeAt(0)),jp=(4-txt.length%4)%4,bp=(4-bin.length%4)%4;
 let out=new Uint8Array(12+8+txt.length+jp+8+bin.length+bp),D=new DataView(out.buffer),o=0;
 function u(n){D.setUint32(o,n,true);o+=4}
 u(0x46546c67);u(2);u(out.length);u(txt.length+jp);u(0x4e4f534a);out.set(txt,o);o+=txt.length;while(o%4)out[o++]=32;
 u(bin.length+bp);u(0x004e4942);out.set(bin,o);
 return out}
function convert(input,output){let bytes=new Uint8Array(readFileSync(input));let result;if(extname(input)===".glb"){let j=fromGLB(bytes);result=JSON.stringify(j);if(extname(output)!==".gltf")throw Error("GLB output must be .gltf");}else if(extname(input)===".gltf"){result=toGLB(JSON.parse(new TextDecoder().decode(bytes)));if(extname(output)!==".glb")throw Error("glTF output must be .glb");}else throw Error("expected .glb/.gltf input");mkdirSync(dirname(output),{recursive:true});writeFileSync(output,result);console.log(input+" -> "+output)}
if(process.argv[2]==="--all"){for(const id of ["vela_gt","orion_rs","kestrel_xr","alder_hatch","cedar_sedan","valley_wagon"])convert("assets/curated/sources/vehicles/"+id+".gltf","assets/curated/models/vehicles/"+id+".glb");for(const name of readdirSync("assets/curated/models/environment").filter(n=>n.endsWith(".gltf")))convert(join("assets/curated/models/environment",name),"assets/curated/models/environment/"+name.replace(/\.gltf$/,".glb"));}else if(process.argv.length===4)convert(process.argv[2],process.argv[3]);else{console.error("Usage: node tools/asset_pipeline/convert.mjs INPUT.gl[b|tf] OUTPUT.gl[b|tf] | --all");process.exitCode=2}
