// Reproducible geometry authoring for Aster Valley. Node.js 20+, zero packages.
// Emits embedded-buffer glTF 2.0, meters, +Y up. Art-direct via seeds and geometry functions.
import fs from 'node:fs';
import path from 'node:path';
function generateHeroModels(){
 const assets={};const metrics={};
 function noise(a,b,c=0){let t=Math.sin(a*127.13+b*311.7+c*74.23)*43758.5453;return t-Math.floor(t);}
 function mesh(){return {pos:[],uv:[],idx:[],nor:[]};}
 function face(m,a,b,c,uva=[0,0],uvb=[1,0],uvc=[0,1]){
   const q=m.pos.length/3;
   const ax=b[0]-a[0],ay=b[1]-a[1],az=b[2]-a[2],bx=c[0]-a[0],by=c[1]-a[1],bz=c[2]-a[2];
   let nx=ay*bz-az*by,ny=az*bx-ax*bz,nz=ax*by-ay*bx;
   const mag=Math.hypot(nx,ny,nz)||1;nx/=mag;ny/=mag;nz/=mag;
   for(const [p,t] of [[a,uva],[b,uvb],[c,uvc]]){m.pos.push(...p);m.uv.push(...t);m.nor.push(nx,ny,nz);}
   m.idx.push(q,q+1,q+2);
 }
 function quad(m,a,b,c,d,uv=[[0,0],[1,0],[1,1],[0,1]]){face(m,a,b,c,uv[0],uv[1],uv[2]);face(m,a,c,d,uv[0],uv[2],uv[3]);}
 function cyl(m,a,b,ra,rb,sides,phase=0){
   let dx=b[0]-a[0],dy=b[1]-a[1],dz=b[2]-a[2],L=Math.hypot(dx,dy,dz)||1;dx/=L;dy/=L;dz/=L;
   let u=[-dz,0,dx];if(Math.hypot(...u)<0.1)u=[1,0,0];let n=Math.hypot(...u);u=u.map(v=>v/n);
   let v=[dy*u[2]-dz*u[1],dz*u[0]-dx*u[2],dx*u[1]-dy*u[0]];
   function pt(o,r,t){let co=Math.cos(t),si=Math.sin(t);return [o[0]+r*(co*u[0]+si*v[0]),o[1]+r*(co*u[1]+si*v[1]),o[2]+r*(co*u[2]+si*v[2])];}
   for(let i=0;i<sides;i++){let t=phase+2*Math.PI*i/sides,tn=phase+2*Math.PI*(i+1)/sides;quad(m,pt(a,ra,t),pt(a,ra,tn),pt(b,rb,tn),pt(b,rb,t),[[i/sides,0],[(i+1)/sides,0],[(i+1)/sides,L*.3],[i/sides,L*.3]]);}
 }
 function gltf(meshes,mats){
   const total=meshes.reduce((n,m)=>n+m.pos.length/3,0);
   const len=meshes.reduce((n,m)=>n+(m.pos.length+m.nor.length+m.uv.length)*4+m.idx.length*4,0);
   const buffer=new ArrayBuffer(len);let ptr=0;const views=[],accessors=[],prims=[];
   function pushData(data,type,count,componentType,layout,dim){
     const offset=ptr,view=new DataView(buffer);
     for(const num of data){if(componentType===5126){view.setFloat32(ptr,num,true)}else{view.setUint32(ptr,num,true)}ptr+=4;}
     const bi=views.length;views.push({buffer:0,byteOffset:offset,byteLength:data.length*4,target:type});
     const ai=accessors.length;const a={bufferView:bi,componentType,count,type:layout};
     if(dim===3){let mins=[Infinity,Infinity,Infinity],maxs=[-Infinity,-Infinity,-Infinity];for(let i=0;i<data.length;i+=3){for(let k=0;k<3;k++){mins[k]=Math.min(mins[k],data[i+k]);maxs[k]=Math.max(maxs[k],data[i+k]);}}a.min=mins;a.max=maxs;}
     accessors.push(a);return ai;
   }
   for(let k=0;k<meshes.length;k++){const m=meshes[k],v=m.pos.length/3;if(!v)continue;
     const pos=pushData(m.pos,34962,v,5126,"VEC3",3),norm=pushData(m.nor,34962,v,5126,"VEC3",0),uv=pushData(m.uv,34962,v,5126,"VEC2",0),idx=pushData(m.idx,34963,m.idx.length,5125,"SCALAR",0);
     prims.push({attributes:{POSITION:pos,NORMAL:norm,TEXCOORD_0:uv},indices:idx,material:k,mode:4});
   }
   let b64="",bytes=new Uint8Array(buffer),abc="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
   const chunk=[];
   for(let i=0;i<bytes.length;i+=3){let x=(bytes[i]<<16)|((bytes[i+1]||0)<<8)|(bytes[i+2]||0);chunk.push(abc[x>>>18],abc[(x>>>12)&63],i+1<bytes.length?abc[(x>>>6)&63]:"=",i+2<bytes.length?abc[x&63]:"=");if(chunk.length>20000){b64+=chunk.join("");chunk.length=0;}}
   b64+=chunk.join("");
   const doc={asset:{version:"2.0",generator:"Aster Valley environment_hd authored geometry v1"},scene:0,scenes:[{nodes:[0]}],nodes:[{name:"Environment_HD_Source",mesh:0}],meshes:[{primitives:prims}],materials:mats.map(m=>({name:m.name,pbrMetallicRoughness:{baseColorFactor:m.color,metallicFactor:0,roughnessFactor:m.roughness||0.96},doubleSided:!!m.doubleSided})),buffers:[{byteLength:len,uri:"data:application/octet-stream;base64,"+b64}],bufferViews:views,accessors};
   return {data:JSON.stringify(doc),triangles:meshes.reduce((n,m)=>n+m.idx.length/3,0),vertices:total,materials:mats.length};
 }
 // Geologically layered face and irregular cap: explicit relief, joints and asymmetric silhouette, not cubes.
 function cliff(seed){
   const rock=mesh(),talus=mesh(),nx=84,ny=34;
   const h=u=>19.5+4.3*Math.sin(6.1*u+seed)+2.1*Math.sin(17*u+seed*0.43)+2.3*Math.pow(noise(u*33,seed),2);
   const p=(i,j)=>{
     const u=i/nx,v=j/ny,x=(u-.5)*46.0;
     let strata=Math.sin(v*71+2.9*u)+0.37*Math.sin(v*192+u*9);
     let fault=0.9*Math.sin(u*19+v*21+seed)+0.6*Math.sin(u*47-v*12);
     let grit=(noise(i*.87,j*.75,seed)-.5)*1.3;
     let z=-1.3+1.8*(1-v)+1.0*strata+fault+grit;
     let y=h(u)*v+0.22*Math.sin(u*49+v*12);
     return [x+0.13*Math.sin(v*14+u*19),y,z];
   };
   for(let i=0;i<nx;i++)for(let j=0;j<ny;j++){const a=p(i,j),b=p(i+1,j),c=p(i+1,j+1),d=p(i,j+1);const t=[[a[0]/3,a[1]/3],[b[0]/3,b[1]/3],[c[0]/3,c[1]/3],[d[0]/3,d[1]/3]];quad(rock,a,b,c,d,t);}
   for(let i=0;i<nx;i++){const top=p(i,ny),top2=p(i+1,ny);const q=[top[0],h(i/nx)-2,6.4],q2=[top2[0],h((i+1)/nx)-2,6.4];quad(rock,top,top2,q2,q);}
   for(let i=0;i<90;i++){
     const x=-24+noise(i,seed)*48,y=.2+noise(i,seed+1)*2.1,z=-3.4-noise(i,seed+2)*4.2;
     const w=0.45+noise(i,seed+3)*1.9,d=0.6+noise(i,seed+4)*2.8;
     const a=[x-w,y,z],b=[x+w,y-.2,z],c=[x+.2,y+noise(i,seed+5)*1.5,z-d],e=[x-.5,y-.2,z-d*.4];
     face(talus,a,b,c,[x*.2,0],[x*.2+w,0],[x*.2,y*.2]);face(talus,a,c,e);
   }
   return gltf([rock,talus],[{name:"Basalt_gneiss_rock",color:[.44,.43,.4,1],roughness:.95},{name:"Talus_grit",color:[.29,.28,.25,1],roughness:1}]);
 }
 // Dense irregular crown with physical branch structure; no conical primitive foliage.
 function fir(seed){
   const bark=mesh(),needlesDark=mesh(),needlesLight=mesh();
   const height=(seed===11?23.5:18.2),branches=seed===11?176:138;
   function trunk(y){const t=y/height;return [0.32*Math.sin(t*2.8+seed)*t,y,0.27*Math.sin(t*4.2+seed*2)*t];}
   for(let i=0;i<22;i++){const y=i*height/22;let ra=.47*Math.pow(1-y/height,1.14)+.033;const a=trunk(y),b=trunk((i+1)*height/22);cyl(bark,a,b,ra,Math.max(.027,ra-.026),8,i*.12);}
   for(let i=0;i<branches;i++){
     const t=(i+.45)/branches,level=Math.pow(t,.77),y=3.4+level*(height-5.3);
     const theta=i*2.399963+seed,canopy=Math.pow(1-level,0.83);
     const gap=(i%17===0)?0.36:1;
     const arm=(2.8+3.5*canopy)*(0.7+0.32*noise(i,seed))*gap;
     const co=Math.cos(theta),si=Math.sin(theta),s=trunk(y);
     const base=[s[0]+co*.16,y,s[2]+si*.16];
     const tip=[s[0]+co*arm,y-.45-.53*canopy,s[2]+si*arm];
     const mid=[(base[0]+tip[0])*.5,y+.1,(base[2]+tip[2])*.5];
     cyl(bark,base,mid,.095*canopy+.019,.04*canopy+.011,5,theta);
     cyl(bark,mid,tip,.04*canopy+.011,.006,4,theta);
     for(let j=0;j<9;j++){
       const s0=(j+.2)/9,span=arm*(.24+.76*s0),wide=(.5+1.7*canopy)*(1-s0*.35);
       const ctr=[base[0]+co*span,y-.18-.48*canopy*s0,base[2]+si*span];
       let taper=wide*(1+.15*Math.sin(j*4+i));
       const axis=[-si,0,co],fall=.13+noise(i,j,seed)*.15;
       const a=[ctr[0]-axis[0]*taper,ctr[1]-fall,ctr[2]-axis[2]*taper];
       const b=[ctr[0]+axis[0]*taper,ctr[1]-fall*.65,ctr[2]+axis[2]*taper];
       const tip0=[ctr[0]+co*(.45+.3*canopy),ctr[1]+(.36*canopy),ctr[2]+si*(.45+.3*canopy)];
       const tip1=[ctr[0]+co*.27,ctr[1]-.3*canopy,ctr[2]+si*.27];
       let m=(i+j)%5===0?needlesLight:needlesDark;
       face(m,a,b,tip0,[0,0],[1,0],[.5,1]);
       face(m,b,a,tip1,[1,0],[0,0],[.5,1]);
       // undersides create depth without a square billboard silhouette
       if(j%2===0){const tt=[ctr[0]+axis[0]*taper*.45,ctr[1]+.29,ctr[2]+axis[2]*taper*.45];face(m,a,tip0,tt);}
     }
   }
   return gltf([bark,needlesDark,needlesLight],[{name:"Furrowed_bark",color:[.28,.235,.18,1],roughness:.94},{name:"Blue_green_needles",color:[.12,.2,.17,1],roughness:.92,doubleSided:true},{name:"Sunlit_new_needles",color:[.2,.285,.18,1],roughness:.94,doubleSided:true}]);
 }
 // Deliberately less detailed miniature ground fern, for close foreground clusters.
 function fern(seed){
   const fronds=mesh(),stems=mesh();
   for(let k=0;k<23;k++){let a=k*2.3999+seed,L=.55+noise(k,seed)*.85,dy=.22+noise(k,seed+2)*.45;
     const start=[0,0,0],mid=[Math.cos(a)*L*.55,dy*1.2,Math.sin(a)*L*.55],end=[Math.cos(a)*L,.13,Math.sin(a)*L];
     cyl(stems,start,mid,.016,.008,4);cyl(stems,mid,end,.008,.001,4);
     for(let j=0;j<10;j++){const t=(j+.5)/10,c=[Math.cos(a)*L*t,Math.sin(Math.PI*t)*dy,Math.sin(a)*L*t],wide=(1-t)*.27*Math.sin(Math.PI*t),side=[-Math.sin(a),0,Math.cos(a)];
       const tip=[c[0]+Math.cos(a)*.12,c[1]+.07,c[2]+Math.sin(a)*.12];
       face(fronds,[c[0]+side[0]*wide,c[1]-.02,c[2]+side[2]*wide],[c[0]-side[0]*wide,c[1]-.02,c[2]-side[2]*wide],tip,[0,0],[1,0],[.5,1]);}}
   return gltf([fronds,stems],[{name:"Fern_green",color:[.18,.275,.12,1],roughness:.99,doubleSided:true},{name:"Fern_stems",color:[.2,.23,.12,1],roughness:1}]);
 }
 for(const [path,a] of [["cliff_rockface_a.gltf",cliff(8)],["cliff_rockface_b.gltf",cliff(21)],["cedar_fir_a.gltf",fir(11)],["cedar_fir_b.gltf",fir(29)],["fern_clump.gltf",fern(17)]]){assets[path]=a.data;metrics[path]={triangles:a.triangles,vertices:a.vertices,materials:a.materials,bytes:a.data.length};}
 return {assets,metrics};
}
const {assets,metrics}=generateHeroModels();
const base=path.resolve(import.meta.dirname,'../../assets/environment_hd/models');
fs.mkdirSync(base,{recursive:true});
for(const [name,value] of Object.entries(assets)){const file=path.join(base,name);if(process.argv.includes('--check')){if(!fs.existsSync(file)||fs.readFileSync(file,'utf8')!==value)throw new Error('Geometry drift: '+name);}else fs.writeFileSync(file,value);}
if(!process.argv.includes('--check'))fs.writeFileSync(path.join(base,'GEOMETRY_METRICS.json'),JSON.stringify(metrics,null,2)+'\n');
console.log('Environment HD geometry: '+Object.keys(assets).length+' models; '+Object.values(metrics).reduce((n,v)=>n+v.triangles,0)+' source triangles; '+(process.argv.includes('--check')?'all byte-identical':'written'));
