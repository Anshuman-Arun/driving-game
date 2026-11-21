'use strict';
// Vector contact sheet rendered from actual authored roads and exported turn lanes.
// No invented routes or separately sketched junctions.
const neat=v=>(Math.round(v*100)/100).toFixed(2);
const pathOf=pts=>pts.map((p,i)=>(i?'L':'M')+neat(p[0])+' '+neat(p[2])).join(' ');
function renderJunctionPreview(w){
 const locations=new Map();
 for(const line of w.lines){
  if(!locations.has(line.a))locations.set(line.a,{x:line.points[0].x,z:line.points[0].z});
  if(!locations.has(line.b))locations.set(line.b,{x:line.points.at(-1).x,z:line.points.at(-1).z});
 }
 const cells=[...locations].sort(([a],[b])=>a.localeCompare(b)),cols=3,pw=388,ph=356,gutter=14,
 width=cols*(pw+gutter)+gutter,height=Math.ceil(cells.length/cols)*(ph+gutter)+gutter;
 const out=['<svg xmlns="http://www.w3.org/2000/svg" width="'+width+'" height="'+height+'" viewBox="0 0 '+width+' '+height+'">',
 '<title>Aster Valley: generated lane turns at all junctions</title>',
 '<rect width="'+width+'" height="'+height+'" fill="#eef0ed"/>'];
 for(let i=0;i<cells.length;i++){
  const [id,center]=cells[i],left=gutter+(i%cols)*(pw+gutter),top=gutter+Math.floor(i/cols)*(ph+gutter),
  x0=left+pw/2,z0=top+ph/2-6,scale=1.75,clip='clip_'+i,
  turns=w.graph.lanes.filter(l=>l.id.startsWith('turn_'+id+'_')),
  centerlines=w.lines.filter(l=>l.points.some(p=>Math.hypot(p.x-center.x,p.z-center.z)<140));
  out.push('<defs><clipPath id="'+clip+'"><rect x="'+(left+8)+'" y="'+(top+30)+'" width="'+(pw-16)+'" height="'+(ph-40)+'"/></clipPath></defs>',
  '<rect x="'+left+'" y="'+top+'" width="'+pw+'" height="'+ph+'" rx="8" fill="#fff" stroke="#ccd4cf"/>',
  '<text x="'+(left+18)+'" y="'+(top+25)+'" font-size="19" fill="#25383b" font-family="sans-serif" font-weight="bold">'+id.replace(/_/g,' ').toUpperCase()+'</text>',
  '<text x="'+(left+pw-15)+'" y="'+(top+25)+'" text-anchor="end" font-size="12" fill="#626e72" font-family="sans-serif">'+turns.length+' turns</text>',
  '<g clip-path="url(#'+clip+')"><g transform="translate('+neat(x0)+' '+neat(z0)+') scale('+scale+') translate('+neat(-center.x)+' '+neat(-center.z)+')">');
  for(const l of centerlines){
   const roadcolor=l.surface==='gravel'?'#b8a07d':'#b4c0c2',
   pts=l.points.map(p=>[p.x,p.y,p.z]),d=pathOf(pts);
   out.push('<path d="'+d+'" fill="none" stroke="#64777b" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/>',
   '<path d="'+d+'" fill="none" stroke="'+roadcolor+'" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>');
  }
  for(const l of turns){
   out.push('<path d="'+pathOf(l.points)+'" fill="none" stroke="'+(l.surface==='gravel'?'#a66b25':'#ad2763')+'" stroke-width="1.2" stroke-opacity=".76" stroke-linecap="round"/>');
   const p=l.points[0],end=l.points.at(-1);
   out.push('<circle cx="'+neat(p[0])+'" cy="'+neat(p[2])+'" r="1.1" fill="#2a81b9"/>',
            '<circle cx="'+neat(end[0])+'" cy="'+neat(end[2])+'" r="1" fill="#2b895c"/>');
  }
  out.push('<circle cx="'+neat(center.x)+'" cy="'+neat(center.z)+'" r="2.3" fill="#172f38"/>','</g></g>');
 }
 out.push('<text x="22" y="'+(height-8)+'" font-family="sans-serif" font-size="12" fill="#425358">Asphalt turns: magenta · Gravel turns: ochre · Blue: incoming · Green: outgoing · Scale: 1.75 px/m</text>',
 '</svg>');
 return out.join('\n')+'\n';
}
module.exports={renderJunctionPreview};
