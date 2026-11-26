import {createHash} from 'node:crypto';
import {specs} from './geometry.mjs';

const prefix = 'assets/environment_overhaul/';
const attrs = ['POSITION', 'NORMAL', 'TEXCOORD_0', 'COLOR_0'];
const widths = [3, 3, 2, 3];
export const sha256 = s => createHash('sha256').update(s).digest('hex');
const check = (ok, msg) => { if (!ok) throw Error(msg); };
const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);
const exact = (o,keys,msg) => check(o && typeof o === 'object' && !Array.isArray(o) && equal(Object.keys(o).sort(), [...keys].sort()),msg);
const array = (a,n,msg) => check(Array.isArray(a) && a.length === n,msg);
const finite = a => Array.isArray(a) && a.every(Number.isFinite);
const parse = (s,label) => { try {return JSON.parse(s);} catch {throw Error(label+' JSON');} };

function decodeAsset(s, species, lod, dimensions, budget) {
  const g = parse(s,'glTF');
  exact(g,['asset','scene','scenes','nodes','meshes','materials','buffers','bufferViews','accessors'],'gltf top-level keys');
  exact(g.asset,['version','generator'],'asset keys');
  check(g.asset.version === '2.0' && g.asset.generator === 'Aster Valley original vegetation v1','gltf version/generator');
  check(g.scene === 0,'scene cardinality');
  for (const key of ['scenes','nodes','meshes','materials','buffers']) array(g[key],1,`${key} cardinality`);
  array(g.accessors,4,'accessor cardinality'); array(g.bufferViews,4,'view cardinality');
  exact(g.scenes[0],['nodes'],'scene keys'); check(equal(g.scenes[0].nodes,[0]),'scene nodes');
  const node = g.nodes[0], mesh = g.meshes[0], name = `${species}_original_lod${lod}`;
  exact(node,['name','mesh'],'node keys'); check(node.name === name && node.mesh === 0,'node identity');
  exact(mesh,['name','primitives'],'mesh keys'); check(mesh.name === name,'mesh identity'); array(mesh.primitives,1,'primitive cardinality');
  const primitive = mesh.primitives[0];
  exact(primitive,['attributes','material','mode'],'primitive keys'); check(primitive.mode === 4 && primitive.material === 0,'triangle primitive');
  exact(primitive.attributes,attrs,'attribute keys'); check(attrs.every((a,i)=>primitive.attributes[a]===i),'attribute indices');
  const mat = g.materials[0];
  exact(mat,['name','doubleSided','alphaMode','pbrMetallicRoughness'],'material keys');
  const pbr=mat.pbrMetallicRoughness;
  check(mat.name === 'vegetation_vertex_color' && mat.doubleSided === true && mat.alphaMode === 'OPAQUE','material mode');
  exact(pbr,['baseColorFactor','metallicFactor','roughnessFactor'],'PBR keys');
  check(equal(pbr.baseColorFactor,[1,1,1,1]) && pbr.metallicFactor === 0 && pbr.roughnessFactor === .88,'PBR values');
  const b = g.buffers[0], header = 'data:application/octet-stream;base64,';
  exact(b,['byteLength','uri'],'buffer keys');
  check(Number.isSafeInteger(b.byteLength) && b.byteLength > 0 && b.byteLength <= 375000 && typeof b.uri === 'string' && b.uri.startsWith(header),'buffer URI/size');
  const encoded = b.uri.slice(header.length), bytes = Buffer.from(encoded,'base64');
  check(bytes.toString('base64') === encoded && bytes.length === b.byteLength,'buffer length/canonical base64');
  exact(g.accessors[0],['bufferView','componentType','count','type','min','max'],'accessor keys');
  const count = g.accessors[0].count;
  check(Number.isSafeInteger(count) && count > 0 && count % 3 === 0 && count/3 <= 1500,'LOD or triangle budget');
  exact(budget,['triangles','surfaces','textures','bytes'],'budget keys');
  check(budget.triangles === count/3 && budget.surfaces === 1 && budget.textures === 0 && budget.bytes === Buffer.byteLength(s),'budget');
  const decoded=[]; let offset=0;
  for (let k=0;k<4;k++) {
    const acc=g.accessors[k], view=g.bufferViews[k], dim=widths[k];
    exact(acc,k===0?['bufferView','componentType','count','type','min','max']:['bufferView','componentType','count','type'],'accessor keys');
    exact(view,['buffer','byteOffset','byteLength','target'],'view keys');
    check(acc.bufferView===k && acc.componentType===5126 && acc.type===`VEC${dim}` && acc.count===count && view.buffer===0 && view.target===34962 && view.byteLength===count*dim*4 && view.byteOffset===offset && offset+view.byteLength<=bytes.length,'accessor bounds');
    const rows=[];
    for(let i=0;i<count;i++) {
      const row=Array.from({length:dim},(_,j)=>bytes.readFloatLE(offset+(i*dim+j)*4));
      check(finite(row),'nonfinite vertex');rows.push(row);
    }
    decoded.push(rows);offset+=view.byteLength;
  }
  check(offset===bytes.length,'trailing buffer bytes');
  const [pos,normals,uv,colors]=decoded, acc=g.accessors[0];
  check([acc.min,acc.max].every(v=>finite(v)&&v.length===3),'accessor bounds metadata');
  for(let k=0;k<3;k++) {
    const low=Math.min(...pos.map(v=>v[k])),high=Math.max(...pos.map(v=>v[k]));
    check(Math.abs(high-low-dimensions[k])<1e-5 && Math.abs(low-(k===1?0:-dimensions[k]/2))<1e-5,'bounds/origin');
    check(Math.abs(low-acc.min[k])<1e-6 && Math.abs(high-acc.max[k])<1e-6,'accessor min/max');
  }
  const faces=new Set();
  for(let i=0;i<count;i+=3) {
    const p=pos.slice(i,i+3), x=p[1].map((v,j)=>v-p[0][j]),y=p[2].map((v,j)=>v-p[0][j]);
    const n=[x[1]*y[2]-x[2]*y[1],x[2]*y[0]-x[0]*y[2],x[0]*y[1]-x[1]*y[0]],len=Math.hypot(...n);
    check(len>1e-9,'degenerate triangle');
    // Identical position triples cause coplanar double drawing, even reversed.
    const key=p.map(v=>v.join(',')).sort().join(';');
    check(!faces.has(key),'duplicate triangle');faces.add(key);
    for(let j=i;j<i+3;j++) {
      check(Math.abs(Math.hypot(...normals[j])-1)<1e-5 && n.reduce((sum,v,k)=>sum+v*normals[j][k],0)/len>.999,'normal mismatch');
      check(uv[j].every(v=>v>=0&&v<=1) && colors[j].every(v=>v>=0&&v<=1),'UV/color range');
    }
  }
  return {count, vertices:new Set(pos.map((p,i)=>p.concat(colors[i]).join(',')))};
}

export function validate(files) {
  const m = parse(files[prefix+'manifest.json'],'manifest');
  exact(m,['schema_version','assets'],'manifest keys'); check(m.schema_version===1,'manifest schema');array(m.assets,specs.length,'manifest species count');
  const notice=files[prefix+'LICENSE.txt'];
  check(typeof notice==='string' && notice.includes('CC0 1.0 Universal') && notice.includes('https://creativecommons.org/publicdomain/zero/1.0/'),'license notice');
  const seen=new Set(), report=[];
  for(const a of m.assets) {
    exact(a,['species_id','variant_id','dimensions_m','origin','source_url','author','license','license_notice','sha256_by_path','status','alpha','material_slots','budget_by_path','lod0','lod1'],'manifest entry keys');
    const spec=specs.find(s=>s.id===a.species_id);check(spec&&!seen.has(a.species_id),'species');seen.add(a.species_id);
    check(a.variant_id==='original_v1' && a.origin==='ground_center' && a.source_url==='local://tools/environment_assets/generate.mjs' && a.author==='Aster Valley project (original procedural geometry)' && a.license==='CC0-1.0' && a.license_notice==='res://'+prefix+'LICENSE.txt' && a.status==='candidate' && a.alpha==='opaque_geometry_no_cards' && equal(a.material_slots,['vegetation_vertex_color']),'license/metadata');
    check(equal(a.dimensions_m,spec.d),'dimensions');
    const paths=[0,1].map(l=>`res://${prefix}${spec.id}_lod${l}.gltf`);
    exact(a.sha256_by_path,paths,'hash coverage');exact(a.budget_by_path,paths,'budget coverage');
    let near;
    for(let lod=0;lod<2;lod++) {
      const p=a[`lod${lod}`];check(p===paths[lod],'path');const s=files[p.slice(6)];
      check(typeof s==='string'&&!s.startsWith('version https://git-lfs'),'missing payload or LFS pointer');
      check(Buffer.byteLength(s)<=500000 && /^[0-9a-f]{64}$/.test(a.sha256_by_path[p]) && sha256(s)===a.sha256_by_path[p],'hash/size');
      const decoded=decodeAsset(s,spec.id,lod,spec.d,a.budget_by_path[p]);
      if(lod===0)near=decoded;else {
        check(decoded.count<=near.count*.65,'LOD reduction');
        check([...decoded.vertices].every(v=>near.vertices.has(v)),'LOD scaffold mismatch');
      }
    }
    report.push({species:spec.id,lod0:a.budget_by_path[a.lod0].triangles,lod1:a.budget_by_path[a.lod1].triangles,bytes:a.budget_by_path[a.lod0].bytes+a.budget_by_path[a.lod1].bytes});
  }
  return report;
}
