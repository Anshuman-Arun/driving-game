#!/usr/bin/env node
// Non-destructive standalone staging: copies OWNED source assets only.
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const repo = path.resolve(import.meta.dirname, "../..");
const source = path.join(repo, "assets/environment_hd");
const dest = path.join(repo, "showcase/environment_hd/.staged_assets");
if (!fs.existsSync(source)) throw Error("Run from a checkout containing assets/environment_hd");
if (process.argv.includes("--clean")) {
  fs.rmSync(dest, {recursive:true, force:true});
  console.log("Removed only showcase/environment_hd/.staged_assets");
  process.exit(0);
}
const files = [];
function scan(dir, prefix = "") {
  for (const entry of fs.readdirSync(dir,{withFileTypes:true})) {
    const relative = path.join(prefix,entry.name);
    if (entry.isDirectory()) scan(path.join(dir,entry.name),relative);
    else if(entry.isFile()) files.push(relative);
  }
}
scan(source);
let copied=0;
for(const relative of files){
  const from=path.join(source,relative),to=path.join(dest,relative);
  if(process.argv.includes("--check")){
    if(!fs.existsSync(to)) throw Error("Missing staged asset: "+relative);
    const hash=p=>crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex");
    if(hash(from)!==hash(to))throw Error("Staging drift: "+relative);
  } else {
    fs.mkdirSync(path.dirname(to),{recursive:true});
    fs.copyFileSync(from,to);
    copied++;
  }
}
console.log("Needle Pass staging: "+files.length+" source assets, "+copied+" files copied; "+(process.argv.includes("--check")?"byte-for-byte checked":"not tracked in Git"));
