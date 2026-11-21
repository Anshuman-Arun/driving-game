import {mkdirSync,writeFileSync} from "node:fs";
const kinds=["asphalt","gravel","grass","soil","rock","bark","foliage"]; const bases={"asphalt":[62,66,67],"gravel":[113,110,99],"grass":[73,103,60],"soil":[115,83,61],"rock":[107,112,108],"bark":[100,71,48],"foliage":[63,106,70]};
function hash(x,y,s){let h=Math.imul(x+517+s,374761393)^Math.imul(y+331+s,668265263);h=Math.imul(h^(h>>>13),1274126177);return ((h^(h>>>16))>>>0)/4294967295}
function noise(x,y,step,seed,size){let a=Math.floor(x/step),b=Math.floor(y/step),fx=x/step-a,fy=y/step-b;fx=fx*fx*(3-2*fx);fy=fy*fy*(3-2*fy);
 let wrap=n=>((n%(size/step))+(size/step))%(size/step),v=(x,y)=>hash(wrap(x),wrap(y),seed);
 return (v(a,b)*(1-fx)+v(a+1,b)*fx)*(1-fy)+(v(a,b+1)*(1-fx)+v(a+1,b+1)*fx)*fy}
function pixels(kind,normal=false,N=256){let base=bases[kind],seed=kinds.indexOf(kind)*37+17,heights=new Float32Array(N*N);
 for(let y=0;y<N;y++)for(let x=0;x<N;x++){let a=noise(x,y,64,seed,N),b=noise(x,y,16,seed+21,N),c=noise(x,y,4,seed+43,N);
  heights[y*N+x]=.39*(a-.5)+.42*(b-.5)+.19*(c-.5)}
 const at=(x,y)=>heights[((y+N)%N)*N+((x+N)%N)],buf=new Uint8Array(N*N*4);
 for(let y=0;y<N;y++)for(let x=0;x<N;x++){let p=(y*N+x)*4,h=at(x,y);
  if(normal){let dx=(at(x+1,y)-at(x-1,y))*4.2,dy=(at(x,y+1)-at(x,y-1))*4.2,k=1/Math.sqrt(dx*dx+dy*dy+1);
   buf[p]=Math.round((.5-dx*k*.5)*255);buf[p+1]=Math.round((.5-dy*k*.5)*255);buf[p+2]=Math.round((.5+k*.5)*255)}
  else{let sp=(hash(x,y,seed+99)-.5)*16,k=kind==="grass"?75:kind==="gravel"?79:kind==="asphalt"?35:54;
    for(let c=0;c<3;c++)buf[p+c]=Math.max(0,Math.min(255,Math.round(base[c]+h*k+sp)))}
  buf[p+3]=255}
 return buf}
function crc(bytes){let c=0xffffffff;for(const x of bytes){c^=x;for(let i=0;i<8;i++)c=(c&1)?(c>>>1)^0xedb88320:(c>>>1)}return (c^0xffffffff)>>>0}
function adler(bytes){let a=1,b=0;for(let x of bytes){a=(a+x)%65521;b=(b+a)%65521}return ((b<<16)|a)>>>0}
function encodePNG(pix,w,h){let raw=new Uint8Array(h*(w*4+1));for(let y=0;y<h;y++){raw[y*(w*4+1)]=0;raw.set(pix.subarray(y*w*4,(y+1)*w*4),y*(w*4+1)+1)}
 let z=[0x78,0x01];for(let at=0;at<raw.length;){let n=Math.min(65535,raw.length-at),end=at+n===raw.length?1:0;
  z.push(end,n&255,(n>>8)&255,(~n)&255,((~n)>>8)&255);for(let i=at;i<at+n;i++)z.push(raw[i]);at+=n}
 let sum=adler(raw);z.push((sum>>>24)&255,(sum>>>16)&255,(sum>>>8)&255,sum&255);
 const out=[137,80,78,71,13,10,26,10];
 function chunk(name,data){let n=data.length;out.push((n>>>24)&255,(n>>>16)&255,(n>>>8)&255,n&255);
  const check=[];for(const c of name){const x=c.charCodeAt(0);out.push(x);check.push(x)}
  for(const x of data){out.push(x);check.push(x)}
  let c=crc(check);out.push((c>>>24)&255,(c>>>16)&255,(c>>>8)&255,c&255)}
 chunk("IHDR",[(w>>>24)&255,(w>>>16)&255,(w>>>8)&255,w&255,(h>>>24)&255,(h>>>16)&255,(h>>>8)&255,8,6,0,0,0]);
 chunk("IDAT",z);chunk("IEND",[]);
 return new Uint8Array(out)}
function b64(a){let chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",o=[];for(let i=0;i<a.length;i+=3){let x=a[i],y=i+1<a.length?a[i+1]:0,z=i+2<a.length?a[i+2]:0;
  o.push(chars[x>>2],chars[((x&3)<<4)|(y>>4)],i+1<a.length?chars[((y&15)<<2)|(z>>6)]:"=",i+2<a.length?chars[z&63]:"=")}
 return o.join("")}
function checkPNG(a){if(a[0]!==137||a[1]!==80||a[2]!==78||a[3]!==71||new DataView(a.buffer).getUint32(16)!==256)throw Error("PNG")}
mkdirSync("assets/curated/materials",{recursive:true});for(const kind of kinds){for(const normal of [false,true]){const png=encodePNG(pixels(kind,normal),256,256);checkPNG(png);writeFileSync("assets/curated/materials/"+kind+"_"+(normal?"normal":"albedo")+".png",png)}console.log(kind,"256px albedo and tangent-space normal");}
