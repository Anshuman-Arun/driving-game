import {mkdirSync,writeFileSync} from "node:fs";
const C={"pine":[0.1,0.28,0.19],"pine2":[0.16,0.35,0.23],"leaf":[0.22,0.37,0.17],"leaf2":[0.34,0.44,0.2],"bark":[0.28,0.2,0.14],"rock":[0.38,0.4,0.38],"rock2":[0.5,0.5,0.46],"steel":[0.55,0.59,0.61],"cement":[0.55,0.57,0.54],"wood":[0.42,0.27,0.15],"dark":[0.08,0.09,0.1],"white":[0.9,0.88,0.79],"red":[0.8,0.12,0.1],"yellow":[0.94,0.66,0.09],"orange":[0.9,0.32,0.06]};
const names=["pine_tree_lod0","pine_tree_lod1","deciduous_tree","bush_cluster","boulder_large","rock_cluster","guardrail_4m","jersey_barrier","wood_fence_3m","roadside_bollard","warning_sign","speed_sign","road_cone","hay_bale","timber_stack","farm_stone_wall","street_lamp","mailbox"];
function plus(a,b){return a.map((v,i)=>v+b[i])}
function minus(a,b){return a.map((v,i)=>v-b[i])}
function mult(a,k){return a.map(v=>v*k)}
function dot(a,b){return a.reduce((t,v,i)=>t+v*b[i],0)}
function cross(a,b){return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]}
function unit(a){return mult(a,1/(Math.sqrt(dot(a,a))||1))}
function scene(id){return {id,parts:[]}}
function part(s,n,m){let p={name:n,material:m,triangles:[]};s.parts.push(p);return p}
function tri(p,a,b,c){p.triangles.push([a,b,c])}
function quad(p,a,b,c,d){tri(p,a,b,c);tri(p,a,c,d)}
function box(s,n,o,size,m){let p=part(s,n,m),[x,y,z]=o,[a,b,c]=size.map(k=>k/2);const v=[[x-a,y-b,z-c],[x+a,y-b,z-c],[x+a,y+b,z-c],[x-a,y+b,z-c],[x-a,y-b,z+c],[x+a,y-b,z+c],[x+a,y+b,z+c],[x-a,y+b,z+c]];
 for(let [i,j,k,l] of [[0,1,2,3],[4,7,6,5],[0,3,7,4],[1,5,6,2],[3,2,6,7],[0,4,5,1]])quad(p,v[i],v[j],v[k],v[l])}
function rod(s,n,a,b,r,m,N=10){let p=part(s,n,m),axis=unit(minus(b,a)),u=unit(cross(axis,Math.abs(axis[1])>.9?[1,0,0]:[0,1,0])),v=unit(cross(axis,u));
 let pt=(o,t)=>plus(o,plus(mult(u,r*Math.cos(t)),mult(v,r*Math.sin(t))));
 for(let j=0;j<N;j++){let x=j*2*Math.PI/N,y=(j+1)*2*Math.PI/N;quad(p,pt(a,x),pt(a,y),pt(b,y),pt(b,x));tri(p,a,pt(a,y),pt(a,x));tri(p,b,pt(b,x),pt(b,y))}}
function cone(s,n,low,high,r,m,N=12){let p=part(s,n,m);for(let j=0;j<N;j++){let a=j*2*Math.PI/N,b=(j+1)*2*Math.PI/N;tri(p,[r*Math.cos(a),low,r*Math.sin(a)],[r*Math.cos(b),low,r*Math.sin(b)],[0,high,0])}}
function sphere(s,n,center,r,m,seed,N=11,K=6){let p=part(s,n,m),rings=[];
 for(let k=0;k<=K;k++){let phi=k*Math.PI/K,row=[];for(let i=0;i<N;i++){let th=i*2*Math.PI/N,w=r*(.91+.07*Math.sin(seed*7+k*9+i*13));
 row.push([center[0]+w*Math.sin(phi)*Math.cos(th),center[1]+w*Math.cos(phi),center[2]+w*Math.sin(phi)*Math.sin(th)])}rings.push(row)}
 for(let k=0;k<K;k++)for(let i=0;i<N;i++)quad(p,rings[k][i],rings[k][(i+1)%N],rings[k+1][(i+1)%N],rings[k+1][i])}
function create(id){let s=scene(id);
 if(id==="pine_tree_lod0"||id==="pine_tree_lod1"){let low=id.endsWith("lod1"),n=low?7:12;
  rod(s,"Trunk",[0,0,0],[0,4.75,0],.15,"bark",n);for(let i=0;i<(low?3:6);i++)cone(s,"NeedleTier_"+i,1.03+i*.57,4.92-i*.18,1.46-i*.17,i%2?"pine2":"pine",n)}
 else if(id==="deciduous_tree"){rod(s,"Trunk",[0,0,0],[0,3.84,0],.20,"bark",12);
  for(let i=0;i<7;i++){let a=i*2.4,c=[Math.cos(a)*.66,3.50+.36*Math.sin(a*2),Math.sin(a)*.7];rod(s,"Branch_"+i,[0,2.65,0],c,.082,"bark",8);sphere(s,"Crown_"+i,c,.85,i%2?"leaf":"leaf2",i,12,7)}}
 else if(id==="bush_cluster"){for(let i=0;i<6;i++){let a=i*2.4;sphere(s,"Bush_"+i,[.48*Math.cos(a),.57,.46*Math.sin(a)],.62,i%2?"leaf2":"pine",i,9,5)}}
 else if(id==="boulder_large")sphere(s,"Boulder",[0,1.0,0],1.37,"rock",33,14,8);
 else if(id==="rock_cluster"){sphere(s,"Stone_A",[-.72,.62,-.22],.85,"rock",5);sphere(s,"Stone_B",[.63,.70,.17],.96,"rock2",6);sphere(s,"Stone_C",[0,.42,-.64],.56,"rock",7)}
 else if(id==="guardrail_4m"){for(let x of [-1.74,0,1.74]){rod(s,"SteelPost_"+x,[x,0,0],[x,1.12,0],.06,"steel",8);box(s,"Foot_"+x,[x,.055,0],[.23,.11,.24],"cement")}
  for(let y of [.63,.95])box(s,"GuardRail_"+y,[0,y,0],[4.08,.17,.12],"steel");
  for(let x of [-1.84,1.84])box(s,"Reflector_"+x,[x,.95,-.082],[.105,.11,.025],"white")}
 else if(id==="jersey_barrier"){box(s,"Base",[0,.28,0],[2.5,.56,.70],"cement");box(s,"Top",[0,.79,0],[2.45,.48,.29],"cement");for(let x of [-.96,.96])box(s,"Marker_"+x,[x,.86,-.17],[.22,.12,.022],"yellow")}
 else if(id==="wood_fence_3m"){for(let x of [-1.4,0,1.4])box(s,"FencePost_"+x,[x,.68,0],[.17,1.36,.17],"wood");for(let y of [.52,1.04])box(s,"FenceRail_"+y,[0,y,0],[3.12,.15,.12],"wood")}
 else if(id==="roadside_bollard"){rod(s,"Post",[0,.07,0],[0,1.13,0],.084,"white",12);box(s,"Reflector",[0,.82,-.09],[.185,.15,.022],"red");box(s,"Foot",[0,.055,0],[.29,.11,.29],"dark")}
 else if(id==="warning_sign"){rod(s,"SteelPole",[0,0,0],[0,2.45,0],.065,"steel",12);let p=part(s,"YellowSign","yellow");quad(p,[0,2.66,-.08],[.45,2.20,-.08],[0,1.74,-.08],[-.45,2.20,-.08]);
  box(s,"Exclamation",[0,2.27,-.105],[.06,.27,.028],"dark");box(s,"Point",[0,2.04,-.105],[.07,.07,.027],"dark")}
 else if(id==="speed_sign"){rod(s,"SteelPole",[0,0,0],[0,2.48,0],.06,"steel",12);let p=part(s,"SpeedDisc","white");
  for(let i=0;i<24;i++){let a=i*2*Math.PI/24,b=(i+1)*2*Math.PI/24;tri(p,[0,2.2,-.095],[.43*Math.cos(a),2.2+.43*Math.sin(a),-.095],[.43*Math.cos(b),2.2+.43*Math.sin(b),-.095])}
  box(s,"SpeedMark1",[0,2.28,-.12],[.26,.07,.028],"dark");box(s,"SpeedMark2",[0,2.07,-.12],[.26,.07,.028],"dark")}
 else if(id==="road_cone"){box(s,"Foot",[0,.05,0],[.49,.10,.49],"dark");cone(s,"TrafficCone",.10,.78,.22,"orange",16);
  let p=part(s,"ReflectiveBand","white");for(let i=0;i<16;i++){let a=i*2*Math.PI/16,b=(i+1)*2*Math.PI/16;quad(p,[.15*Math.cos(a),.3,.15*Math.sin(a)],[.15*Math.cos(b),.3,.15*Math.sin(b)],[.12*Math.cos(b),.41,.12*Math.sin(b)],[.12*Math.cos(a),.41,.12*Math.sin(a)])}}
 else if(id==="hay_bale"){box(s,"Bale",[0,.54,0],[1.27,1.06,.82],"wood");for(let z of [-.26,.26])box(s,"Twine_"+z,[0,.55,z],[1.3,.029,.029],"rock2")}
 else if(id==="timber_stack"){for(let row=0;row<3;row++)for(let i=0;i<3-row;i++){let x=(i+row*.5-1)*.36,y=.20+row*.32;rod(s,"Log_"+row+"_"+i,[x,y,-1.27],[x,y,1.27],.18,"wood",12)}}
 else if(id==="farm_stone_wall"){for(let row=0;row<3;row++)for(let i=0;i<8;i++)box(s,"WallStone_"+row+"_"+i,[-1.77+i*.47+(row%2)*.12,.17+row*.34,0],[.45,.33,.47],(i+row)%3?"rock":"rock2")}
 else if(id==="street_lamp"){rod(s,"Pole",[0,0,0],[0,4.7,0],.09,"steel",12);rod(s,"Arm",[0,4.68,0],[1.06,4.78,0],.07,"steel",8);box(s,"Lamp",[1.06,4.66,0],[.4,.16,.27],"white")}
 else if(id==="mailbox"){rod(s,"WoodPost",[0,0,0],[0,1.18,0],.08,"wood",8);box(s,"Box",[0,1.28,-.2],[.39,.29,.68],"steel");box(s,"Flag",[.23,1.36,-.13],[.032,.2,.2],"red")}
 else throw Error(id);
 return s}
function base64(a){const c="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",o=[];for(let i=0;i<a.length;i+=3){const x=a[i],y=i+1<a.length?a[i+1]:0,z=i+2<a.length?a[i+2]:0;o.push(c[x>>2],c[((x&3)<<4)|(y>>4)],i+1<a.length?c[((y&15)<<2)|(z>>6)]:"=",i+2<a.length?c[z&63]:"=")}return o.join("")}
function exportGltf(s){const bytes=[],views=[],acc=[],meshes=[],nodes=[{name:"AssetRoot",children:[]}],dv=new DataView(new ArrayBuffer(4));
 const u8=v=>bytes.push(v&255),u16=v=>{u8(v);u8(v>>8)},f32=v=>{dv.setFloat32(0,v,true);for(let i=0;i<4;i++)u8(dv.getUint8(i))},pad=()=>{while(bytes.length%4)u8(0)};
 const view=(o,target)=>{views.push({buffer:0,byteOffset:o,byteLength:bytes.length-o,target});return views.length-1};
 const accessor=(v,n,typ,component,min,max)=>{let a={bufferView:v,componentType:component,count:n,type:typ};if(min)a.min=min;if(max)a.max=max;acc.push(a);return acc.length-1};
 let triangles=0;
 for(const p of s.parts){let P=[],N=[],I=[],mn=[Infinity,Infinity,Infinity],mx=[-Infinity,-Infinity,-Infinity];
  for(const f of p.triangles){let n=unit(cross(minus(f[1],f[0]),minus(f[2],f[0])));
   for(const v of f){for(let j=0;j<3;j++){P.push(v[j]);N.push(n[j]);mn[j]=Math.min(mn[j],v[j]);mx[j]=Math.max(mx[j],v[j])}I.push(I.length)}}
  if(I.length>65535)throw Error("index overflow "+p.name);triangles+=p.triangles.length;
  pad();let o=bytes.length;P.forEach(f32);let a=accessor(view(o,34962),I.length,"VEC3",5126,mn,mx);
  pad();o=bytes.length;N.forEach(f32);let b=accessor(view(o,34962),I.length,"VEC3",5126);
  pad();o=bytes.length;I.forEach(u16);let c=accessor(view(o,34963),I.length,"SCALAR",5123);
  let meshId=meshes.length;meshes.push({name:p.name,primitives:[{attributes:{POSITION:a,NORMAL:b},indices:c,material:Object.keys(C).indexOf(p.material),mode:4}]});
  let nodeId=nodes.length;nodes.push({name:p.name,mesh:meshId});nodes[0].children.push(nodeId)}
 const materials=Object.entries(C).map(([name,rgb])=>({name,pbrMetallicRoughness:{baseColorFactor:[...rgb,1],metallicFactor:name==="steel"?.73:0,roughnessFactor:name==="steel"?.48:.92},doubleSided:true}));
 const json={asset:{version:"2.0",generator:"Aster Valley original environment generator"},scene:0,scenes:[{nodes:[0]}],nodes,meshes,materials,buffers:[{byteLength:bytes.length,uri:"data:application/octet-stream;base64,"+base64(new Uint8Array(bytes))}],bufferViews:views,accessors:acc};
 return {json,triangles,bytes:bytes.length}}
function validate(g){let j=g.json;if(j.asset.version!=="2.0"||!j.buffers[0].uri.startsWith("data:application/octet-stream;base64,"))throw Error("invalid gltf");
 const T=j.meshes.reduce((a,m)=>a+j.accessors[m.primitives[0].indices].count/3,0);
 if(T!==g.triangles||j.accessors.some(a=>a.count<=0))throw Error("bad geometry");
 for(const v of j.bufferViews)if(v.byteOffset+v.byteLength>g.bytes)throw Error("out of bounds");
 return true}
function preview(s){let W=650,H=450,tall=s.id.includes("tree")||s.id==="street_lamp",scale=tall?53:s.id==="guardrail_4m"||s.id==="farm_stone_wall"?87:104;
 let eye=unit([.58,.38,-.73]),R=unit(cross([0,1,0],eye)),U=unit(cross(eye,R)),center=tall?[0,2.2,0]:[0,.85,0],light=unit([-.53,.86,-.3]),polys=[];
 for(const p of s.parts)for(const f of p.triangles){let n=unit(cross(minus(f[1],f[0]),minus(f[2],f[0]))),shade=Math.max(.37,.67+dot(n,light)*.31),rgb=C[p.material].map(x=>Math.max(0,Math.min(255,Math.round(x*255*shade))));
 let c="#"+rgb.map(x=>x.toString(16).padStart(2,"0")).join(""),points=f.map(v=>{let o=minus(v,center);return [(W/2+dot(o,R)*scale).toFixed(1),(H*.67-dot(o,U)*scale).toFixed(1)].join(",")}).join(" ");
 polys.push({z:f.reduce((a,v)=>a+dot(v,eye),0)/3,c,points})}
 polys.sort((a,b)=>a.z-b.z);
 return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}"><rect width="${W}" height="${H}" fill="#192c36"/><ellipse cx="325" cy="332" rx="169" ry="22" fill="#02080a" opacity=".54"/>${polys.map(x=>`<polygon points="${x.points}" fill="${x.c}"/>`).join("")}<text x="22" y="45" fill="#f0f2ed" font-size="24" font-family="Arial,sans-serif">${s.id.replace(/_/g," ").toUpperCase()}</text><text x="23" y="419" fill="#92abb5" font-size="12" font-family="Arial,sans-serif">ACTUAL SOURCE TRIANGLE PREVIEW</text></svg>`}
for(const name of names){let s=create(name),g=exportGltf(s);validate(g);mkdirSync("assets/curated/models/environment",{recursive:true});mkdirSync("assets/curated/previews",{recursive:true});writeFileSync("assets/curated/models/environment/"+name+".gltf",JSON.stringify(g.json));writeFileSync("assets/curated/previews/"+name+".svg",preview(s));console.log(name,g.triangles);}
