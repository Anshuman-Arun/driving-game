// Aster Valley art library: deterministic, dependency-free Node.js generator.
// Run node tools/asset_pipeline/generate.js from the repository root.
function generate(){
const files=[],manifest=[],report=[],colors={
 aqua:[.04,.43,.45,.6,.24],red:[.72,.1,.085,.5,.24],graphite:[.15,.19,.24,.7,.28],
 cream:[.7,.72,.65,.32,.33],navy:[.12,.21,.4,.55,.3],orange:[.78,.37,.09,.43,.29],
 dark:[.04,.05,.055,0,.9],rubber:[.035,.04,.045,0,.92],alloy:[.62,.65,.66,.9,.23],
 glass:[.09,.17,.23,.1,.11,.73],light:[.95,.93,.8,0,.25],tail:[.73,.06,.04,0,.25],
 metal:[.43,.49,.51,.7,.38],concrete:[.52,.53,.5,0,.93],wood:[.34,.24,.13,0,.96],
 bark:[.22,.17,.12,0,1],pine:[.10,.25,.18,0,.98],fir:[.18,.31,.22,0,.95],
 leaf:[.26,.36,.16,0,.94],grass:[.39,.47,.24,0,.9],stone:[.33,.35,.34,0,.95],
 lightstone:[.48,.47,.43,0,.92],white:[.9,.86,.75,0,.6],yellow:[.96,.57,.065,0,.5]};
function add(path,data){files.push({path,content:data})}
function vadd(a,b){return a.map((x,i)=>x+b[i])}function vsub(a,b){return a.map((x,i)=>x-b[i])}
function cross(a,b){return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]}
function dot(a,b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]}
function norm(a){const l=Math.sqrt(dot(a,a))||1;return a.map(x=>x/l)}
function start(id){return {id,nodes:[{name:"AssetRoot",parent:null,pos:[0,0,0]}],parts:[]}}
function parent(m,name,from="AssetRoot",pos=[0,0,0]){m.nodes.push({name,parent:from,pos});return name}
function part(m,name,mat,from="AssetRoot"){const p={name,mat,from,tri:[]};m.parts.push(p);return p}
function tri(p,a,b,c){
 // Quantize at source so Node, V8 isolates and native math libraries serialize
 // identical generated geometry despite sub-ULP trigonometric differences.
 const q=v=>v.map(x=>{const r=Math.round(x*1e6)/1e6;return r===0?0:r});
 p.tri.push([q(a),q(b),q(c)]);
}function quad(p,a,b,c,d){tri(p,a,b,c);tri(p,a,c,d)}
function box(m,name,pos,size,mat,from="AssetRoot"){
 const p=part(m,name,mat,from),[x,y,z]=pos,[a,b,c]=size.map(q=>q/2);
 const P=[[-a,-b,-c],[a,-b,-c],[a,b,-c],[-a,b,-c],[-a,-b,c],[a,-b,c],[a,b,c],[-a,b,c]].map(q=>vadd(q,pos));
 for(const [i,j,k,l] of [[0,3,2,1],[4,5,6,7],[0,4,7,3],[1,2,6,5],[3,7,6,2],[0,1,5,4]])quad(p,P[i],P[j],P[k],P[l]);
}
function beam(m,name,a,b,r,mat,from="AssetRoot",n=9){
 const p=part(m,name,mat,from),N=norm(vsub(b,a)),U=norm(cross(N,Math.abs(N[1])>.95?[1,0,0]:[0,1,0])),V=norm(cross(N,U));
 const point=(at,t)=>at.map((v,i)=>v+r*(U[i]*Math.cos(t)+V[i]*Math.sin(t)));
 for(let i=0;i<n;i++){const t=2*Math.PI*i/n,u=2*Math.PI*(i+1)/n;quad(p,point(a,t),point(a,u),point(b,u),point(b,t));tri(p,a,point(a,u),point(a,t));tri(p,b,point(b,t),point(b,u))}
}
function cone(m,name,pos,r,h,mat,n=11){const p=part(m,name,mat);for(let i=0;i<n;i++){
 const a=2*Math.PI*i/n,b=2*Math.PI*(i+1)/n;tri(p,[pos[0]+r*Math.cos(a),pos[1],pos[2]+r*Math.sin(a)],[pos[0]+r*Math.cos(b),pos[1],pos[2]+r*Math.sin(b)],[pos[0],pos[1]+h,pos[2]])}}
function ellipsoid(m,name,pos,size,mat,n=11,k=6){
 const p=part(m,name,mat),A=[];
 for(let j=0;j<=k;j++){const t=Math.PI*j/k,row=[];for(let i=0;i<n;i++){const a=2*Math.PI*i/n,r=1+.08*Math.sin(i*9+j*4);
 row.push([pos[0]+size[0]*Math.sin(t)*Math.cos(a)*r,pos[1]+size[1]*Math.cos(t),pos[2]+size[2]*Math.sin(t)*Math.sin(a)*r])}A.push(row)}
 for(let j=0;j<k;j++)for(let i=0;i<n;i++)quad(p,A[j][i],A[j][(i+1)%n],A[j+1][(i+1)%n],A[j+1][i]);
}
function panel(m,name,P,mat){const p=part(m,name,mat);for(let i=1;i<P.length-1;i++){tri(p,P[0],P[i],P[i+1]);tri(p,P[i+1],P[i],P[0])}}
function wheel(m,key,pos,r,w,low){
 const from=parent(m,"Wheel_"+key+"_Pivot","AssetRoot",pos),n=low?12:22,t=w/2;
 const tire=part(m,"Tire_"+key,"rubber",from),rim=part(m,"Rim_"+key,"alloy",from),P=(x,r,a)=>[x,r*Math.cos(a),r*Math.sin(a)];
 for(let i=0;i<n;i++){const a=2*Math.PI*i/n,b=2*Math.PI*(i+1)/n;quad(tire,P(-t,r,a),P(t,r,a),P(t,r,b),P(-t,r,b));
  for(let s of [-1,1]){quad(tire,P(s*t,r,a),P(s*t,r,b),P(s*t,r*.77,b),P(s*t,r*.77,a));
  quad(rim,P(s*(t+.01),r*.72,a),P(s*(t+.01),r*.72,b),P(s*(t+.01),r*.19,b),P(s*(t+.01),r*.19,a))}}
 for(let s of [-1,1])for(let i=0;i<(low?5:7);i++){const a=i*2*Math.PI/(low?5:7),b=a+.14;
  quad(rim,P(s*(t+.013),r*.08,a),P(s*(t+.013),r*.08,b),P(s*(t+.013),r*.69,b+.04),P(s*(t+.013),r*.69,a+.04))}
 beam(m,"Wheel_Hub_"+key,[-t-.02,0,0],[t+.02,0,0],r*.12,"metal",from);
}
const specs=[
 {id:"vela_gt",name:"Vela GT",paint:"aqua",L:4.58,W:1.89,H:1.37,wb:2.70,sport:true},
 {id:"orion_rs",name:"Orion RS",paint:"red",L:4.17,W:1.78,H:1.29,wb:2.49,sport:true},
 {id:"kestrel_xr",name:"Kestrel XR",paint:"graphite",L:4.73,W:1.96,H:1.36,wb:2.81,sport:true},
 {id:"alder_hatch",name:"Alder Hatch",paint:"cream",L:3.95,W:1.73,H:1.51,wb:2.47,sport:false},
 {id:"cedar_sedan",name:"Cedar Sedan",paint:"navy",L:4.53,W:1.83,H:1.47,wb:2.69,sport:false},
 {id:"valley_wagon",name:"Valley Wagon",paint:"orange",L:4.47,W:1.85,H:1.59,wb:2.68,sport:false}
];
function car(c,low){
 const m=start(c.id+(low?"_lod1":"")),L=c.L,W=c.W/2,h=c.sport?.94:1.04,rail=c.sport?.81:.90;
 const rings=[[-L/2,W*.77,h-.12],[-L/2+.18,W*.94,h-.06],[-c.wb/2-.25,W,h],[-.52,W,h+.06],[.46,W,h+.05],[c.wb/2+.25,W*.98,h+.04],[L/2-.16,W*.94,h-.06],[L/2,W*.82,h-.14]]
 .map(([z,w,y])=>[[-w*.92,.32,z],[-w,.45,z],[-w,rail,z],[-w*.83,y,z],[w*.83,y,z],[w,rail,z],[w,.45,z],[w*.92,.32,z]]);
 const p=part(m,"Body_Shell",c.paint);
 for(let i=0;i<rings.length-1;i++)for(let j=0;j<8;j++)quad(p,rings[i][j],rings[i+1][j],rings[i+1][(j+1)%8],rings[i][(j+1)%8]);
 for(let j=1;j<7;j++){tri(p,rings[0][0],rings[0][j],rings[0][j+1]);tri(p,rings.at(-1)[0],rings.at(-1)[j+1],rings.at(-1)[j])}
 const roof=W*.64,A=-.51,B=-.10,D=c.sport?.92:1.10,E=c.sport?1.51:1.71;
 panel(m,"Windshield",[[-W*.73,h+.06,A],[W*.73,h+.06,A],[roof,c.H,B],[-roof,c.H,B]],"glass");
 panel(m,"Rear_Windshield",[[-roof,c.H,D],[roof,c.H,D],[W*.70,h+.05,E],[-W*.70,h+.05,E]],"glass");
 box(m,"Roof",[0,c.H-.026,(B+D)/2],[roof*2+.065,.06,D-B],"graphite");
 panel(m,"Roof_Paint",[[-roof,c.H,B],[roof,c.H,B],[roof,c.H,D],[-roof,c.H,D]],c.paint);
 for(const s of [-1,1]){
  panel(m,"Door_Glass_"+s,[[s*W*.86,h+.07,A],[s*roof,c.H,B],[s*roof,c.H,.37],[s*W*.86,h+.07,.44]],"glass");
  panel(m,"Rear_Quarter_Glass_"+s,[[s*W*.86,h+.07,.46],[s*roof,c.H,.40],[s*roof,c.H,D],[s*W*.86,h+.06,E]],"glass");
  if(!low){
   for(const [nm,a,b] of [["A",[s*W*.86,h+.07,A],[s*roof,c.H,B]],["B",[s*W*.86,h+.07,.44],[s*roof,c.H,.37]],["C",[s*W*.86,h+.06,E],[s*roof,c.H,D]]])
    beam(m,nm+"_Pillar_"+s,a,b,.026,"graphite");
   beam(m,"Mirror_Stem_"+s,[s*W*.95,h,-.44],[s*(W+.12),h+.09,-.44],.021,"graphite");
   box(m,"Mirror_Housing_"+s,[s*(W+.14),h+.09,-.44],[.23,.13,.24],c.paint);
   box(m,"Door_Handle_"+s,[s*(W+.012),rail+.025,.42],[.025,.025,.14],"alloy");
   beam(m,"Sill_"+s,[s*W*.95,.32,-.56],[s*W*.95,.32,1.16],.025,"graphite");
  }
 }
 box(m,"Grille",[0,.61,-L/2-.02],[W*1.24,.22,.05],"dark");
 box(m,"Splitter",[0,.33,-L/2-.09],[W*1.61,.05,.21],"graphite");
 box(m,"Diffuser",[0,.35,L/2+.02],[W*1.57,.1,.08],"dark");
 for(const s of [-1,1]){
  box(m,"Headlight_"+s,[s*W*.64,h-.14,-L/2-.022],[W*.47,.105,.04],"light");
  box(m,"Taillight_"+s,[s*W*.65,h-.125,L/2+.022],[W*.49,.11,.04],"tail");
  if(c.sport&&!low)beam(m,"Bonnet_Line_"+s,[s*W*.29,h+.02,-L/2+.31],[s*W*.22,h+.07,-.65],.012,"graphite");
 }
 if(c.id==="kestrel_xr"&&!low){
  box(m,"Rear_Wing",[0,h+.30,L/2-.33],[W*1.86,.065,.29],"orange");
  for(const s of [-1,1])beam(m,"Wing_Mount_"+s,[s*W*.6,h+.03,L/2-.33],[s*W*.6,h+.30,L/2-.33],.039,"dark");
 }
 for(const [name,s,z] of [["FL",-1,-c.wb/2],["FR",1,-c.wb/2],["RL",-1,c.wb/2],["RR",1,c.wb/2]])
  wheel(m,name,[s*(W-.04),c.sport?.36:.35,z],c.sport?.355:.34,c.sport?.237:.22,low||!c.sport);
 return m;
}
const env=["pine_tree_lod0","pine_tree_lod1","broadleaf_tree","shrub_cluster","boulder","rock_cluster",
"guardrail_4m","concrete_barrier","wood_fence","bollard","warning_sign","traffic_cone",
"hay_bale","stone_wall","street_lamp","bus_shelter"];
function environment(id){
 const m=start(id);
 if(id.startsWith("pine_tree")){
  const low=id.endsWith("lod1");beam(m,"Trunk",[0,0,0],[0,3.25,0],.15,"bark");
  for(let i=0;i<(low?3:6);i++)cone(m,"Needle_Layer_"+i,[0,1.12+i*.57,0],1.53-i*.24,2.13,i%2?"fir":"pine",low?7:12);
 }else if(id==="broadleaf_tree"){
  beam(m,"Trunk",[0,0,0],[0,3.75,0],.18,"bark");
  for(let i=0;i<7;i++){const a=i*2.4;ellipsoid(m,"Canopy_"+i,[.72*Math.cos(a),3.62+.28*Math.sin(a),.68*Math.sin(a)],[.84,.89,.82],i%2?"leaf":"grass")}
 }else if(id==="shrub_cluster"){for(let i=0;i<7;i++){const a=i*2.31;ellipsoid(m,"Leaves_"+i,[.47*Math.cos(a),.42,.45*Math.sin(a)],[.46,.53,.44],i%2?"fir":"leaf")}}
 else if(id==="boulder"){ellipsoid(m,"Rock_Surface",[0,1.02,0],[1.48,1.0,1.27],"stone",14,8)}
 else if(id==="rock_cluster"){for(let i=0;i<4;i++){const a=i*2.3;ellipsoid(m,"Stone_"+i,[.7*Math.cos(a),.46,.55*Math.sin(a)],[.62,.45,.53],i%2?"stone":"lightstone")}}
 else if(id==="guardrail_4m"){
  for(let i=0;i<3;i++){const x=-1.8+1.8*i;beam(m,"Support_"+i,[x,0,0],[x,1.09,0],.055,"metal");box(m,"Foot_"+i,[x,.07,0],[.22,.14,.23],"concrete")}
  for(let y of [.66,.95])box(m,"Steel_Rail_"+y,[0,y,0],[4.03,.18,.13],"metal");
  for(let x of [-1.9,1.9])box(m,"Reflector_"+x,[x,.95,-.08],[.09,.11,.025],"white");
 }else if(id==="concrete_barrier"){
  box(m,"Base",[0,.27,0],[2.54,.54,.67],"concrete");box(m,"Upper",[0,.74,0],[2.49,.43,.32],"concrete");
  for(let x of [-.9,.9])box(m,"Safety_Strip_"+x,[x,.9,-.18],[.20,.07,.028],"yellow");
 }else if(id==="wood_fence"){
  for(let i=0;i<3;i++)box(m,"Post_"+i,[-1.4+1.4*i,.66,0],[.15,1.32,.17],"bark");
  for(let y of [.48,.97])box(m,"Cross_Bar_"+y,[0,y,0],[3.03,.14,.12],"wood");
 }else if(id==="bollard"){
  beam(m,"White_Post",[0,0,0],[0,1.07,0],.08,"white");
  box(m,"Reflective_Band",[0,.78,0],[.19,.14,.19],"tail");box(m,"Foot",[0,.06,0],[.26,.12,.24],"dark");
 }else if(id==="warning_sign"){
  beam(m,"Post",[0,0,0],[0,2.42,0],.055,"metal");
  panel(m,"Yellow_Sign",[[0,2.66,-.045],[.41,2.25,-.045],[0,1.84,-.045],[-.41,2.25,-.045]],"yellow");
  box(m,"Exclamation",[0,2.32,-.07],[.065,.23,.03],"dark");box(m,"Dot",[0,2.10,-.07],[.06,.06,.03],"dark");
 }else if(id==="traffic_cone"){
  box(m,"Base",[0,.05,0],[.47,.10,.47],"dark");cone(m,"Orange_Cone",[0,.10,0],.20,.66,"yellow",14);box(m,"Reflective_Ring",[0,.38,0],[.18,.095,.18],"white");
 }else if(id==="hay_bale"){
  box(m,"Hay",[0,.51,0],[1.19,1.01,.77],"yellow");
  for(let z of [-.20,.20])box(m,"Rope_"+z,[0,.51,z],[1.22,.036,.033],"wood");
 }else if(id==="stone_wall"){
  for(let i=0;i<3;i++)for(let j=0;j<8;j++)box(m,"Stone_"+i+"_"+j,[-1.75+.46*j+.18*(i%2),.18+i*.38,0],[.45,.36,.47],(i+j)%3?"stone":"lightstone");
 }else if(id==="street_lamp"){
  beam(m,"Lamp_Pole",[0,0,0],[0,4.51,0],.083,"metal");beam(m,"Arm",[0,4.51,0],[1.08,4.6,0],.06,"metal");box(m,"Lamp_Housing",[1.08,4.49,0],[.42,.13,.27],"light");
 }else if(id==="bus_shelter"){
  for(let x of [-1.42,1.42])for(let z of [-.48,.48])beam(m,"Frame_"+x+"_"+z,[x,0,z],[x,2.36,z],.056,"metal");
  box(m,"Canopy",[0,2.38,0],[3.2,.15,1.3],"graphite");box(m,"Back_Glass",[0,1.2,.50],[2.86,2.23,.04],"glass");
  box(m,"Bench",[0,.62,.28],[1.9,.12,.35],"wood");for(let x of [-.75,.75])box(m,"Leg_"+x,[x,.34,.28],[.09,.57,.12],"metal");
 }else throw Error(id);
 return m;
}
function exportGLB(m){
 const b=[],accessors=[],bufferViews=[],meshes=[],nodes=[],lookup={},mats=Object.keys(colors),fview=new DataView(new ArrayBuffer(4));
 const u8=x=>b.push(x&255),u16=x=>{u8(x);u8(x>>8)},f32=x=>{const q=Math.round(x*1e6)/1e6;fview.setFloat32(0,q===0?0:q,true);for(let i=0;i<4;i++)u8(fview.getUint8(i))},pad=()=>{while(b.length%4)u8(0)};
 function view(from,length,target){bufferViews.push({buffer:0,byteOffset:from,byteLength:length,target});return bufferViews.length-1}
 function acc(bufferView,count,type,componentType,min,max){const a={bufferView,count,type,componentType};if(min)a.min=min;if(max)a.max=max;accessors.push(a);return accessors.length-1}
 for(const n of m.nodes){lookup[n.name]=nodes.length;nodes.push({name:n.name,translation:n.pos,children:[]})}
 for(let i=0;i<m.nodes.length;i++)if(m.nodes[i].parent)nodes[lookup[m.nodes[i].parent]].children.push(i);
 let triangles=0;
 for(const p of m.parts){
  const position=[],normal=[],indices=[],min=[Infinity,Infinity,Infinity],max=[-Infinity,-Infinity,-Infinity];
  for(const f of p.tri){const n=norm(cross(vsub(f[1],f[0]),vsub(f[2],f[0])));
   for(const v of f){for(let k=0;k<3;k++){position.push(v[k]);normal.push(n[k]);min[k]=Math.min(min[k],v[k]);max[k]=Math.max(max[k],v[k])}indices.push(indices.length)}}
  if(!indices.length)continue;if(indices.length>65535)throw Error("16-bit index overflow "+p.name);
  triangles+=indices.length/3;pad();let o=b.length;position.forEach(f32);const posAcc=acc(view(o,b.length-o,34962),indices.length,"VEC3",5126,min,max);
  pad();o=b.length;normal.forEach(f32);const nAcc=acc(view(o,b.length-o,34962),indices.length,"VEC3",5126);
  pad();o=b.length;indices.forEach(u16);const iAcc=acc(view(o,b.length-o,34963),indices.length,"SCALAR",5123);
  const k=meshes.length;meshes.push({name:p.name,primitives:[{attributes:{POSITION:posAcc,NORMAL:nAcc},indices:iAcc,material:mats.indexOf(p.mat),mode:4}]});
  nodes.push({name:p.name,mesh:k});nodes[lookup[p.from]].children.push(nodes.length-1);
 }
 const materials=mats.map(name=>{const c=colors[name],p={name,pbrMetallicRoughness:{baseColorFactor:[...c.slice(0,3),c[5]||1],metallicFactor:c[3],roughnessFactor:c[4]},doubleSided:true};if(c[5])p.alphaMode="BLEND";return p});
 const gltf={asset:{version:"2.0",generator:"Aster Valley original asset pipeline"},scene:0,scenes:[{nodes:[0]}],nodes,meshes,materials,buffers:[{byteLength:b.length}],bufferViews,accessors};
 const json=JSON.stringify(gltf).split("").map(ch=>ch.charCodeAt(0)),jp=(4-json.length%4)%4,bp=(4-b.length%4)%4,size=12+8+json.length+jp+8+b.length+bp;
 const result=new Uint8Array(size),dv=new DataView(result.buffer);let k=0;
 const u32=x=>{dv.setUint32(k,x,true);k+=4};u32(0x46546c67);u32(2);u32(size);u32(json.length+jp);u32(0x4e4f534a);
 for(const n of json)result[k++]=n;for(let i=0;i<jp;i++)result[k++]=32;
 u32(b.length+bp);u32(0x004e4942);for(const n of b)result[k++]=n;for(let i=0;i<bp;i++)result[k++]=0;
 return {bytes:result,triangles,meshCount:meshes.length,nodeCount:nodes.length};
}
function checkGLB(g,isVehicle){
 const d=new DataView(g.bytes.buffer),u=n=>d.getUint32(n,true),length=u(12),binOffset=20+length;
 if(u(0)!==0x46546c67||u(4)!==2||u(8)!==g.bytes.length||u(16)!==0x4e4f534a||u(binOffset+4)!==0x004e4942)throw Error("Invalid GLB header");
 let s="";for(let i=20;i<20+length;i++)s+=String.fromCharCode(g.bytes[i]);const data=JSON.parse(s);
 if(data.buffers[0].byteLength>u(binOffset))throw Error("Truncated buffer");
 let n=0;for(const m of data.meshes)for(const p of m.primitives){const a=data.accessors[p.indices],b=data.accessors[p.attributes.POSITION];
  if(a.count%3||a.count!==b.count||b.min.some((v,i)=>v>b.max[i]))throw Error("Invalid accessor");n+=a.count/3}
 if(n!==g.triangles)throw Error("Triangle count mismatch");
 if(isVehicle)for(const id of ["FL","FR","RL","RR"]){const node=data.nodes.find(x=>x.name==="Wheel_"+id+"_Pivot");
  if(!node||!node.children||!node.children.some(i=>data.nodes[i].name==="Tire_"+id)||!node.children.some(i=>data.nodes[i].name==="Rim_"+id))throw Error("Wheel separation: "+id)}
 return {triangles:n,meshes:data.meshes.length,nodes:data.nodes.length,bytes:g.bytes.length};
}
function render(m,title){
 const V=norm([.58,.41,-.7]),X=norm(cross([0,1,0],V)),Y=norm(cross(V,X)),sun=norm([-.6,.9,-.35]);
 const tall=m.id.includes("tree")||m.id==="street_lamp",scale=tall?56:109,eye=tall?[0,2.1,0]:[0,.72,0],pos={},faces=[];
 for(const n of m.nodes)pos[n.name]=n.parent?vadd(pos[n.parent],n.pos):n.pos;
 for(const p of m.parts)for(const face of p.tri){
  const a=face.map(v=>vadd(v,pos[p.from])),N=norm(cross(vsub(a[1],a[0]),vsub(a[2],a[0])));
  const points=a.map(v=>{const q=vsub(v,eye);return [(460+dot(q,X)*scale).toFixed(1),(355-dot(q,Y)*scale).toFixed(1)]});
  const c=colors[p.mat],shade=Math.max(.33,.65+.3*dot(N,sun)),color="#"+c.slice(0,3).map(v=>Math.min(255,Math.round(v*shade*255)).toString(16).padStart(2,"0")).join("");
  faces.push({depth:a.reduce((s,v)=>s+dot(v,V),0)/3,xml:'<polygon points="'+points.map(x=>x.join(",")).join(" ")+'" fill="'+color+'" opacity="'+(c[5]||1)+'"/>'});
 }
 faces.sort((a,b)=>a.depth-b.depth);
 return '<svg xmlns="http://www.w3.org/2000/svg" width="920" height="540" viewBox="0 0 920 540"><defs><linearGradient id="background" x2="0" y2="1"><stop stop-color="#213642"/><stop offset="1" stop-color="#11191f"/></linearGradient></defs><rect width="100%" height="100%" fill="url(#background)"/><ellipse cx="460" cy="433" rx="175" ry="24" fill="#05080b" opacity=".5"/>'+faces.map(x=>x.xml).join("")+'<text x="28" y="47" fill="#f4f5f0" font-family="Arial" font-size="32" font-weight="bold">'+title+'</text><text x="28" y="509" fill="#9db6bd" font-family="Arial" font-size="14">PROCEDURAL SOURCE MESH PREVIEW</text></svg>';
}
function crc32(seq){let c=0xffffffff;for(const x of seq){c^=x;for(let k=0;k<8;k++)c=(c&1)?(c>>>1)^0xedb88320:c>>>1}return (c^0xffffffff)>>>0}
function png(kind,normal){
 const bases={asphalt:[57,60,64],gravel:[106,104,98],grass:[76,105,62],soil:[108,82,60],bedrock:[109,113,110],bark:[96,70,49],foliage:[62,97,67]},idx=Object.keys(bases).indexOf(kind),size=128,H=new Float32Array(size*size),raw=[];
 function hash(x,y,s){let h=(Math.imul(x+s,374761393)+Math.imul(y+s,668265263))|0;h=Math.imul(h^(h>>>13),1274126177);return ((h^(h>>>16))>>>0)/4294967295}
 for(let y=0;y<size;y++)for(let x=0;x<size;x++)H[y*size+x]=.42*(hash(x>>3,y>>3,idx)-.5)+.36*(hash(x>>5,y>>5,idx+10)-.5)+.22*(hash(x,y,idx+29)-.5);
 const h=(x,y)=>H[((y+size)%size)*size+(x+size)%size];
 for(let y=0;y<size;y++){raw.push(0);for(let x=0;x<size;x++){const z=h(x,y),base=bases[kind];
  if(normal){const n=norm([(h(x-1,y)-h(x+1,y))*3,(h(x,y-1)-h(x,y+1))*3,1]);for(let c=0;c<3;c++)raw.push(Math.round((n[c]*.5+.5)*255))}
  else for(let c=0;c<3;c++)raw.push(Math.max(0,Math.min(255,Math.round(base[c]+z*52+(hash(x,y,idx+55)-.5)*20))));
  raw.push(255)}}
 const compressed=[.0+120,1];for(let i=0;i<raw.length;){const n=Math.min(65535,raw.length-i);compressed.push(i+n===raw.length?1:0,n&255,(n>>8)&255,(~n)&255,((~n)>>8)&255);for(let j=0;j<n;j++)compressed.push(raw[i++])}
 let a=1,b=0;for(const v of raw){a=(a+v)%65521;b=(b+a)%65521}const sum=((b<<16)|a)>>>0;compressed.push((sum>>>24)&255,(sum>>>16)&255,(sum>>>8)&255,sum&255);
 const out=[137,80,78,71,13,10,26,10];
 function chunk(tag,bytes){const n=bytes.length;out.push((n>>>24)&255,(n>>>16)&255,(n>>>8)&255,n&255);
  const d=[...tag.split("").map(x=>x.charCodeAt(0)),...bytes];out.push(...d);const c=crc32(d);out.push((c>>>24)&255,(c>>>16)&255,(c>>>8)&255,c&255)}
 chunk("IHDR",[0,0,0,size,0,0,0,size,8,6,0,0,0]);chunk("IDAT",compressed);chunk("IEND",[]);
 return new Uint8Array(out);
}
for(const c of specs){for(const low of c.sport?[false]:[false,true]){
 const m=car(c,low),g=exportGLB(m),r=checkGLB(g,true),kind=low?"traffic_lod":"vehicle";
 const path="assets/curated/models/"+kind+"/"+m.id+".glb",preview="assets/curated/previews/"+m.id+".svg";
 add(path,g.bytes);add(preview,render(m,c.name+(low?" (LOD1)":"")));
 manifest.push({asset_id:m.id,path,category:kind,author:"OpenAI original art generator for Aster Valley",source_url:null,source_file:"tools/asset_pipeline/generate.js",license:"Original project work; project redistribution permitted",license_evidence:"assets/curated/ORIGINAL_ASSET_LICENSE.md",modifications:"Created from original procedural geometry",unit:"meters",orientation:"+Y up, -Z forward; wheel rotation local X",triangles:r.triangles,mesh_parts:r.meshes,texture_resolution:null,dimensions_m:{length:c.L,width:c.W,height:c.H,wheelbase:c.wb},collision_proxy:{size_m:[c.W-.12,c.H-.35,c.L-.20],center_m:[0,.75,0]},usage:low?"distant traffic visual":"player or NPC vehicle visual",attribution_required:false,preview});
 report.push({id:m.id,...r});
}}
for(const id of env){
 const m=environment(id),g=exportGLB(m),r=checkGLB(g,false),path="assets/curated/models/environment/"+id+".glb",preview="assets/curated/previews/"+id+".svg";
 add(path,g.bytes);add(preview,render(m,id.replace(/_/g," ")));
 manifest.push({asset_id:id,path,category:"environment",author:"OpenAI original art generator for Aster Valley",source_url:null,source_file:"tools/asset_pipeline/generate.js",license:"Original project work; project redistribution permitted",license_evidence:"assets/curated/ORIGINAL_ASSET_LICENSE.md",modifications:"Created from original procedural geometry",unit:"meters",orientation:"+Y up",triangles:r.triangles,mesh_parts:r.meshes,texture_resolution:null,usage:"static instanced world scenery",attribution_required:false,preview});
 report.push({id,...r});
}
for(const id of ["asphalt","gravel","grass","soil","bedrock","bark","foliage"]){
 const base="assets/curated/materials/"+id;add(base+"_albedo.png",png(id,false));add(base+"_normal.png",png(id,true));
 add(base+".tres",'[gd_resource type="StandardMaterial3D" load_steps=3 format=3]\n\n[ext_resource type="Texture2D" path="res://'+base+'_albedo.png" id="1_a"]\n[ext_resource type="Texture2D" path="res://'+base+'_normal.png" id="2_n"]\n\n[resource]\nresource_name = "'+id+'"\nalbedo_texture = ExtResource("1_a")\nroughness = 0.94\nnormal_enabled = true\nnormal_scale = 0.75\nnormal_texture = ExtResource("2_n")\n');
 manifest.push({asset_id:id+"_material",path:base+".tres",additional_paths:[base+"_albedo.png",base+"_normal.png"],category:"PBR_material",author:"OpenAI original art generator for Aster Valley",source_url:null,source_file:"tools/asset_pipeline/generate.js",license:"Original project work; project redistribution permitted",license_evidence:"assets/curated/ORIGINAL_ASSET_LICENSE.md",modifications:"Tileable procedural albedo and tangent-space normal textures",texture_resolution:[128,128],triangles:0,unit:"tile UV",orientation:"surface UV",usage:"terrain / roadside surface",attribution_required:false});
}
const book={schema_version:1,generated_by:"tools/asset_pipeline/generate.js",license_summary:"Original procedural art, no downloaded third-party inputs",assets:manifest};
add("assets/curated/MANIFEST.json",JSON.stringify(book,null,2)+"\n");
return {files,manifest,report};
}
if (typeof require !== "undefined" && require.main === module) {
  const fs = require("fs"), path = require("path");
  const args = process.argv.slice(2), check = args.includes("--check");
  const result = generate();
  // This generator owns only supplemental GLBs and supplemental previews.
  // The primary authoring pipeline owns MANIFEST.json, materials and primary previews.
  const owned = result.files
    .filter(item => item.path.endsWith(".glb") || item.path.endsWith(".svg"))
    .map(item => ({
      path: item.path.endsWith(".svg")
        ? item.path.replace("assets/curated/previews/", "assets/curated/previews/supplemental/")
        : item.path,
      content: item.content
    }));
  let mismatches = 0;
  for (const item of owned) {
    const local = path.join(process.cwd(), item.path);
    const expected = Buffer.from(item.content);
    if (check) {
      if (!fs.existsSync(local) || !fs.readFileSync(local).equals(expected)) {
        console.error("MISMATCH", item.path); mismatches++;
      }
    } else {
      fs.mkdirSync(path.dirname(local), { recursive: true });
      fs.writeFileSync(local, expected);
    }
  }
  console.log(JSON.stringify({mode:check?"check":"build", models:result.report.length,
    files:owned.length, triangles:result.report.reduce((n,x)=>n+x.triangles,0),
    bytes:owned.reduce((n,x)=>n+x.content.length,0),
    mismatches},null,2));
  if (mismatches) process.exitCode = 1;
}
if (typeof module !== "undefined") module.exports = {generate};
