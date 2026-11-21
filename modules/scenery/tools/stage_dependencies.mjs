// Binary-safe, read-only staging of unmerged World PR #3 and Art PR #7.
import fs from "node:fs";
import path from "node:path";
import {execFileSync} from "node:child_process";
import {fileURLToPath} from "node:url";
const moduleDir=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"..");
const root=path.resolve(moduleDir,"../..");
const worldRef=process.argv[2]||"origin/feat/worldgen";
const artRef=process.argv[3]||"origin/feat/art-pipeline";
function gitShow(ref,filename){
 return execFileSync("git",["show",ref+":"+filename],{cwd:root,maxBuffer:8*1024*1024,stdio:["ignore","pipe","pipe"]});
}
function stage(ref,source,target){
 const data=gitShow(ref,source);
 const dest=path.join(moduleDir,target);
 fs.mkdirSync(path.dirname(dest),{recursive:true});
 fs.writeFileSync(dest,data);
 console.log("STAGED",ref+":"+source,"->",target,data.length+"B");
}
for(const file of ["world_metadata_v1.json","road_graph_v1.json","terrain_height_r16le.bin"])
 stage(worldRef,"data/world/"+file,".world_source/"+file);
const scenery=JSON.parse(fs.readFileSync(path.join(root,"content/scenery/manifest.json"),"utf8"));
const artPaths=new Set();
for(const cfg of Object.values(scenery.assets)){
 if(cfg.path.startsWith("assets/curated/"))artPaths.add(cfg.path);
 if(cfg.lod&&cfg.lod.startsWith("assets/curated/"))artPaths.add(cfg.lod);
}
stage(artRef,"assets/curated/MANIFEST.json",".art_source/MANIFEST.json");
stage(artRef,"assets/curated/ORIGINAL_ASSETS_LICENSE.md",".art_source/ORIGINAL_ASSETS_LICENSE.md");
for(const file of [...artPaths].sort())stage(artRef,file,".art_source/"+file.slice("assets/curated/".length));
for(const cfg of Object.values(scenery.assets)){
 if(!cfg.path.startsWith("content/scenery/models/"))continue;
 const source=path.join(root,cfg.path),dest=path.join(moduleDir,".models",path.basename(cfg.path));
 fs.mkdirSync(path.dirname(dest),{recursive:true});
 fs.copyFileSync(source,dest);
 console.log("STAGED",cfg.path,"->",path.relative(moduleDir,dest));
}
console.log("Complete. Staging is gitignored and does not modify any authoritative source branch.");
