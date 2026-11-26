import assert from 'node:assert/strict';
import {generate} from './geometry.mjs';
import {sha256,validate} from './validate.mjs';
const manifest='assets/environment_overhaul/manifest.json', asset='assets/environment_overhaul/shrub_lod0.gltf',far=asset.replace('lod0','lod1');
const header='data:application/octet-stream;base64,';
export function selfTest(files=generate()) {
  assert.equal(sha256(''),'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  assert.equal(sha256('abc'),'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  assert.deepEqual(generate(),files);
  const report=validate(files),rejected=[];
  function reject(name,reason,modify){
    const f={...files},m=JSON.parse(f[manifest]);modify(f,m);f[manifest]=JSON.stringify(m);
    assert.throws(()=>validate(f),e=>e.message===reason, name+' did not fail for '+reason);rejected.push(name);
  }
  function edit(f,m,fn,path=asset){
    const g=JSON.parse(f[path]);fn(g);f[path]=JSON.stringify(g)+'\n';const p='res://'+path;
    m.assets[0].sha256_by_path[p]=sha256(f[path]);m.assets[0].budget_by_path[p].bytes=Buffer.byteLength(f[path]);
  }
  function bytes(g,fn){const b=Buffer.from(g.buffers[0].uri.slice(header.length),'base64');fn(b);g.buffers[0].uri=header+b.toString('base64');}
  reject('missing texture','gltf top-level keys',(f,m)=>edit(f,m,g=>{g.images=[{uri:'missing.png'}];g.textures=[{source:0}];}));
  reject('LFS pointer','missing payload or LFS pointer',f=>{f[asset]='version https://git-lfs.github.com/spec/v1\n';});
  reject('malformed mesh','LOD or triangle budget',(f,m)=>edit(f,m,g=>{g.accessors[0].count=4;}));
  reject('missing license','manifest entry keys',(f,m)=>{delete m.assets[0].license;});
  reject('hash mismatch','hash/size',f=>{f[asset]+=' ';});
  reject('missing file','missing payload or LFS pointer',f=>{delete f[asset];});
  reject('degenerate geometry','degenerate triangle',(f,m)=>edit(f,m,g=>bytes(g,b=>b.copy(b,12,0,12))));
  reject('translated node','node keys',(f,m)=>edit(f,m,g=>{g.nodes[0].translation=[100,0,0];}));
  reject('wrong scene','scene cardinality',(f,m)=>edit(f,m,g=>{g.scene=1;}));
  reject('zero index accessor','primitive keys',(f,m)=>edit(f,m,g=>{g.meshes[0].primitives[0].indices=0;}));
  reject('wrong accessor offset','accessor keys',(f,m)=>edit(f,m,g=>{g.accessors[0].byteOffset=4;}));
  reject('unsupported stride','view keys',(f,m)=>edit(f,m,g=>{g.bufferViews[0].byteStride=16;}));
  reject('sparse override','accessor keys',(f,m)=>edit(f,m,g=>{g.accessors[0].sparse={count:1,indices:{bufferView:1,componentType:5123},values:{bufferView:2}};}));
  reject('missing material texture','PBR keys',(f,m)=>edit(f,m,g=>{g.materials[0].pbrMetallicRoughness.baseColorTexture={index:0};}));
  reject('transparent factor','PBR values',(f,m)=>edit(f,m,g=>{g.materials[0].pbrMetallicRoughness.baseColorFactor=[0,0,0,0];}));
  reject('extra node','nodes cardinality',(f,m)=>edit(f,m,g=>{g.nodes.push({mesh:0});g.scenes[0].nodes.push(1);}));
  reject('wrong material','material mode',(f,m)=>edit(f,m,g=>{g.materials[0].doubleSided=false;}));
  reject('wrong UV accessor','attribute indices',(f,m)=>edit(f,m,g=>{g.meshes[0].primitives[0].attributes.TEXCOORD_0=0;}));
  reject('duplicate species','species',(f,m)=>{m.assets[1]=m.assets[0];});
  reject('extra hash','hash coverage',(f,m)=>{m.assets[0].sha256_by_path['res://unowned']=sha256('test');});
  reject('wrong notice','license notice',f=>{f['assets/environment_overhaul/LICENSE.txt']='unlicensed';});
  reject('path traversal','path',(f,m)=>{m.assets[0].lod0='res://assets/environment_overhaul/../other.gltf';});
  reject('far color no longer on shared scaffold','LOD scaffold mismatch',(f,m)=>edit(f,m,g=>bytes(g,b=>b.writeFloatLE(.314159,g.bufferViews[3].byteOffset)),far));
  reject('nonfinite attribute','nonfinite vertex',(f,m)=>edit(f,m,g=>bytes(g,b=>b.writeFloatLE(NaN,0))));
  reject('duplicate triangle','duplicate triangle',(f,m)=>edit(f,m,g=>bytes(g,b=>{for(const v of g.bufferViews){const n=v.byteLength/g.accessors[0].count*3;b.copy(b,v.byteOffset+n,v.byteOffset,v.byteOffset+n);}})));
  reject('noncanonical base64','buffer length/canonical base64',(f,m)=>edit(f,m,g=>{g.buffers[0].uri+='\n';}));
  reject('wrong normal','normal mismatch',(f,m)=>edit(f,m,g=>bytes(g,b=>{const o=g.bufferViews[1].byteOffset;for(let i=0;i<3;i++)b.writeFloatLE(-b.readFloatLE(o+i*4),o+i*4);}))); 
  reject('null position accessor','accessor keys',(f,m)=>edit(f,m,g=>{g.accessors[0]=null;}));
  reject('null material','material keys',(f,m)=>edit(f,m,g=>{g.materials[0]=null;}));
  reject('overlapping buffer view','accessor bounds',(f,m)=>edit(f,m,g=>{g.bufferViews[1].byteOffset=0;}));
  return {report,negative_fixtures:rejected.length,rejected,determinism:true,sha256_vectors:2,lod_shared_scaffold:true};
}
