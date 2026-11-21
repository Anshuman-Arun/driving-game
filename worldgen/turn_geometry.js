'use strict';
const {dubins}=require('./dubins');
const norm=(x,z)=>{let d=Math.hypot(x,z)||1;return [x/d,z/d];};
const clamp=(x,a,b)=>Math.max(a,Math.min(b,x));
// Discrete corner radius of the actual exported polyline, not control handles.
function radius(pts){
 let r=Infinity;
 for(let i=1;i<pts.length-1;i++){
  const a=pts[i-1],b=pts[i],c=pts[i+1],
  u=[b.x-a.x,b.z-a.z],v=[c.x-b.x,c.z-b.z],d1=Math.hypot(...u),d2=Math.hypot(...v);
  if(d1<.05||d2<.05)return 0;
  const angle=Math.acos(clamp((u[0]*v[0]+u[1]*v[1])/(d1*d2),-1,1));
  if(angle>1e-5)r=Math.min(r,(d1+d2)/(2*angle));
 }
 return r;
}
function cubic(p,q){
 const p0={x:p.at(-1)[0],z:p.at(-1)[2]},before={x:p.at(-2)[0],z:p.at(-2)[2]},
 q0={x:q[0][0],z:q[0][2]},after={x:q[1][0],z:q[1][2]},
 a=norm(p0.x-before.x,p0.z-before.z),b=norm(after.x-q0.x,after.z-q0.z),
 sep=Math.hypot(q0.x-p0.x,q0.z-p0.z),handle=clamp(sep*.55,6,16),
 c1={x:p0.x+handle*a[0],z:p0.z+handle*a[1]},
 c2={x:q0.x-handle*b[0],z:q0.z-handle*b[1]},n=Math.max(6,Math.ceil(sep/2)),pts=[];
 for(let j=0;j<=n;j++){
  const t=j/n,s=1-t;
  pts.push({x:s**3*p0.x+3*s*s*t*c1.x+3*s*t*t*c2.x+t**3*q0.x,
            z:s**3*p0.z+3*s*s*t*c1.z+3*s*t*t*c2.z+t**3*q0.z});
 }
 return pts;
}
function makeTurn(p,q){
 const pts=cubic(p,q);
 if(radius(pts)>=7.5)return {points:pts,kind:'cubic'};
 const s=p.at(-1),s0=p.at(-2),e=q[0],e1=q[1],
 a=norm(s[0]-s0[0],s[2]-s0[2]),b=norm(e1[0]-e[0],e1[2]-e[2]);
 return dubins({x:s[0],z:s[2],yaw:Math.atan2(a[1],a[0])},
               {x:e[0],z:e[2],yaw:Math.atan2(b[1],b[0])},9,2);
}
module.exports={makeTurn,radius,cubic};
