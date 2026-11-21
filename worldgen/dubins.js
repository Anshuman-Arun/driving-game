'use strict';
// Curvature-constrained forward-only paths; all positions are in Godot X/Z.
const TWO_PI=2*Math.PI;
const mod=x=>((x%TWO_PI)+TWO_PI)%TWO_PI;
const clamp=(x,a,b)=>Math.max(a,Math.min(b,x));
function word(name,a,b,d){
 const sa=Math.sin(a),sb=Math.sin(b),ca=Math.cos(a),cb=Math.cos(b),cab=Math.cos(a-b);
 let t,p,q,v,tmp;
 if(name==='LSL'){
  v=2+d*d-2*cab+2*d*(sa-sb);if(v< -1e-8)return null;
  tmp=Math.atan2(cb-ca,d+sa-sb);t=mod(-a+tmp);p=Math.sqrt(Math.max(0,v));q=mod(b-tmp);
 }else if(name==='RSR'){
  v=2+d*d-2*cab+2*d*(sb-sa);if(v< -1e-8)return null;
  tmp=Math.atan2(ca-cb,d-sa+sb);t=mod(a-tmp);p=Math.sqrt(Math.max(0,v));q=mod(-b+tmp);
 }else if(name==='LSR'){
  v=-2+d*d+2*cab+2*d*(sa+sb);if(v< -1e-8)return null;
  tmp=Math.atan2(-ca-cb,d+sa+sb)-Math.atan2(-2,Math.sqrt(Math.max(0,v)));
  t=mod(-a+tmp);p=Math.sqrt(Math.max(0,v));q=mod(-b+tmp);
 }else if(name==='RSL'){
  v=d*d-2+2*cab-2*d*(sa+sb);if(v< -1e-8)return null;
  tmp=Math.atan2(ca+cb,d-sa-sb)-Math.atan2(2,Math.sqrt(Math.max(0,v)));
  t=mod(a-tmp);p=Math.sqrt(Math.max(0,v));q=mod(b-tmp);
 }else if(name==='RLR'){
  v=(6-d*d+2*cab+2*d*(sa-sb))/8;if(Math.abs(v)>1+1e-8)return null;
  p=mod(TWO_PI-Math.acos(clamp(v,-1,1)));tmp=Math.atan2(ca-cb,d-sa+sb);
  t=mod(a-tmp+p/2);q=mod(a-b-t+p);
 }else if(name==='LRL'){
  v=(6-d*d+2*cab+2*d*(-sa+sb))/8;if(Math.abs(v)>1+1e-8)return null;
  p=mod(TWO_PI-Math.acos(clamp(v,-1,1)));tmp=Math.atan2(ca-cb,d+sa-sb);
  t=mod(-a-tmp+p/2);q=mod(b-a-t+p);
 }
 return [t,p,q].every(Number.isFinite)?{name,params:[t,p,q],length:t+p+q}:null;
}
function integrate(pose,type,distance,r){
 const {x,z,yaw}=pose;
 if(type==='S')return {x:x+Math.cos(yaw)*distance,z:z+Math.sin(yaw)*distance,yaw};
 const sign=type==='L'?1:-1,da=sign*distance/r;
 return {x:x+r/sign*(Math.sin(yaw+da)-Math.sin(yaw)),
         z:z+r/sign*(-Math.cos(yaw+da)+Math.cos(yaw)),yaw:yaw+da};
}
function dubins(start,end,r=9,spacing=2){
 if(r<=0||spacing<=0)throw Error('radius and spacing must be positive');
 const dx=end.x-start.x,dz=end.z-start.z,heading=Math.atan2(dz,dx),d=Math.hypot(dx,dz)/r,
 a=mod(start.yaw-heading),b=mod(end.yaw-heading);
 const paths=['LSL','RSR','LSR','RSL','RLR','LRL'].map(x=>word(x,a,b,d)).filter(Boolean)
  .sort((x,y)=>x.length-y.length);
 if(!paths.length)throw Error('No valid Dubins path');
 const best=paths[0],pts=[{x:start.x,z:start.z}];let pose={...start};
 for(let i=0;i<3;i++){
  const len=best.params[i]*r,steps=Math.max(1,Math.ceil(len/spacing)),before=pose;
  for(let n=1;n<=steps;n++){
   const point=integrate(before,best.name[i],len*n/steps,r);
   if(Math.hypot(point.x-pts.at(-1).x,point.z-pts.at(-1).z)>.05)pts.push({x:point.x,z:point.z});
  }
  pose=integrate(before,best.name[i],len,r);
 }
 const endpointError=Math.hypot(pose.x-end.x,pose.z-end.z);
 const yawError=Math.abs(Math.atan2(Math.sin(pose.yaw-end.yaw),Math.cos(pose.yaw-end.yaw)));
 if(endpointError>1e-5||yawError>1e-5)throw Error('Curve endpoint or heading mismatch');
 pts[pts.length-1]={x:end.x,z:end.z};
 return {points:pts,kind:best.name,length:best.length*r};
}
module.exports={dubins};
