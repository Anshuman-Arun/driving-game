#!/usr/bin/env python3
"""Powered by Poly Haven. Acquire immutable source assets, not runtime imports.
Python 3.10+, stdlib only. No Git operations. Default output outside project.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import tempfile
import time
import urllib.request
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "docs/environment_assets/catalog.json"
API = "https://api.polyhaven.com"
HEADERS = {"User-Agent": "AsterValleyEnvironmentAssetLibrary/1.0 (Powered by Poly Haven)"}
MIB = 1024 * 1024
KINDS = ("models", "textures", "hdris")
MAP_ALIASES = {
    "diff": ("Diffuse", "diff", "col", "albedo"),
    "nor_gl": ("nor_gl",),
    "rough": ("Rough", "rough"),
    "ao": ("AO", "ao"),
    "arm": ("arm",),
    "disp": ("Displacement", "disp"),
    "metal": ("Metal", "metal"),
    "opacity": ("Opacity", "opacity", "Mask", "mask"),
    "alpha": ("Alpha", "alpha"),
    "transmission": ("Transmission", "transmission"),
    "sss": ("SSS", "sss"),
    "spec": ("Specular", "spec"),
    "emission": ("Emission", "emission"),
}

def request(url):
    for attempt in range(3):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=90)
        except OSError:
            if attempt == 2:
                raise
            time.sleep(2 ** (attempt + 1))

def api(path):
    time.sleep(0.35)
    with request(API + path) as response:
        return json.load(response)

def write_json(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(path)

def safe_path(value):
    p = PurePosixPath(value)
    if p.is_absolute() or not p.parts or any(x in ("..", ".") or ":" in x or "\\" in x for x in p.parts):
        raise ValueError("Unsafe relative asset path: " + value)
    return Path(*p.parts)

def trusted_url(url):
    u = urlparse(url)
    if u.scheme != "https" or not u.hostname or not any(u.hostname == h or u.hostname.endswith("." + h) for h in ("polyhaven.com", "polyhaven.org")):
        raise ValueError("Unexpected asset URL: " + url)
    return url

def select(catalog, assets, scope):
    selected = {}
    missing = []
    def add(kind, slug, purpose, priority):
        if slug not in assets[kind]:
            missing.append({"kind":kind,"id":slug,"reason":"not in live catalog"})
            return
        if not re.fullmatch(r"[a-z0-9_-]+", slug):
            return
        key = (kind, slug)
        if key not in selected:
            info = assets[kind][slug]
            selected[key] = {"kind":kind,"id":slug,"purpose":purpose,"priority":priority,
                "name":info.get("name",slug),"authors":info.get("authors",{}),
                "source_url":"https://polyhaven.com/a/"+slug,"license":"CC0-1.0",
                "license_url":catalog["license_url"],"metadata":{k:info[k] for k in
                ("category","categories","tags","polycount","dimensions","max_resolution","files_hash","lods") if k in info}}
    for group in catalog["priority"]:
        for slug in group["ids"]:
            add(group["kind"],slug,group["purpose"],"core")
    if scope == "expanded":
        for group in catalog["discovery"]:
            kind = group["kind"]
            ranked = []
            for slug, info in assets[kind].items():
                category = " ".join([str(info.get("category",""))]+info.get("categories",[])).lower()
                hay = " ".join([slug.replace("_"," "),str(info.get("name","")),category]+info.get("tags",[])).lower()
                if group.get("category") and group["category"] not in category:
                    continue
                if any(term in hay for term in group["exclude"]):
                    continue
                matches = [term for term in group["terms"] if re.search(r"(?<!\w)"+re.escape(term)+r"(?!\w)",hay)]
                if matches:
                    ranked.append((-sum(1+len(x)/12 for x in matches),slug))
            for _, slug in sorted(ranked)[:group["limit"]]:
                add(kind,slug," / ".join(group["terms"]),"expanded")
    return list(selected.values()), missing

def choose_entry(node, resolutions, formats):
    for res in resolutions:
        for fmt in formats:
            entry = node.get(res,{}).get(fmt,{})
            if isinstance(entry,dict) and entry.get("url"):
                return entry,res,fmt
    return None,None,None

def file_spec(rel, entry):
    return {"path":safe_path(rel).as_posix(),"url":trusted_url(entry["url"]),
            "bytes":int(entry.get("size",0)),"md5":entry.get("md5"),"upstream_hash":entry.get("hash")}

def make_plan(candidate, resolution):
    slug,kind = candidate["id"],candidate["kind"]
    files = api("/files/"+slug)
    # Never silently fall back to a lower quality tier.
    resolutions = [resolution]
    result = []
    if kind == "models":
        entry,res,fmt = choose_entry(files.get("gltf",{}),resolutions,["gltf"])
        if not entry:
            raise ValueError("no requested glTF resolution")
        name = Path(urlparse(entry["url"]).path).name
        result.append(file_spec(name,entry))
        for rel, info in entry.get("include",{}).items():
            result.append(file_spec(rel,info))
    elif kind == "textures":
        files_lower = {k.lower(): v for k, v in files.items() if isinstance(v, dict)}
        for key, aliases in MAP_ALIASES.items():
            node = {}
            for alias in aliases:
                if isinstance(files.get(alias), dict):
                    node = files[alias]
                    break
                if alias.lower() in files_lower:
                    node = files_lower[alias.lower()]
                    break
            entry,res,fmt = choose_entry(node,resolutions,["png","jpg","jpeg","exr"])
            if entry:
                result.append(file_spec(key+"/"+Path(urlparse(entry["url"]).path).name,entry))
        if not any(x["path"].startswith("diff/") for x in result):
            raise ValueError("no requested diffuse map")
    else:
        entry,res,fmt = choose_entry(files.get("hdri",{}),resolutions,["hdr","exr"])
        if not entry:
            raise ValueError("no requested HDRI resolution")
        result.append(file_spec(Path(urlparse(entry["url"]).path).name,entry))
    if not result or len({x["path"] for x in result}) != len(result):
        raise ValueError("empty or duplicate file plan")
    if any(x["bytes"] <= 0 for x in result):
        raise ValueError("missing upstream size; cannot enforce storage budget")
    return {**candidate,"resolution":resolution,"files":result,"bytes":sum(x["bytes"] for x in result)}

def digest(path):
    sha = hashlib.sha256()
    md5 = hashlib.md5(usedforsecurity=False)
    with path.open("rb") as file:
        for chunk in iter(lambda:file.read(MIB),b""):
            sha.update(chunk)
            md5.update(chunk)
    return sha.hexdigest(),md5.hexdigest()

def fetch_file(spec,destination):
    destination.parent.mkdir(parents=True,exist_ok=True)
    with request(spec["url"]) as response, destination.open("wb") as f:
        if response.headers.get("Content-Type","").startswith("text/html"):
            raise ValueError("HTML instead of asset")
        count = 0
        while chunk := response.read(MIB):
            count += len(chunk)
            if count > spec["bytes"]:
                raise ValueError("download exceeded declared size")
            f.write(chunk)
    if count != spec["bytes"]:
        raise ValueError(f"size mismatch: {count} != {spec['bytes']}")
    sha,md5 = digest(destination)
    if spec.get("md5") and md5.lower() != spec["md5"].lower():
        raise ValueError("upstream MD5 mismatch")
    return {**spec,"sha256":sha}

def validate_gltf(folder,records):
    if not any(x["path"].endswith(".gltf") for x in records):
        raise ValueError("missing glTF")
    for record in records:
        if record["path"].endswith(".gltf"):
            path=folder/safe_path(record["path"])
            obj=json.loads(path.read_text(encoding="utf-8"))
            if obj.get("asset",{}).get("version") != "2.0" or not obj.get("meshes"):
                raise ValueError("invalid or empty glTF")
            for item in obj.get("buffers",[])+obj.get("images",[]):
                uri=item.get("uri","")
                if uri and not uri.startswith("data:"):
                    if not (path.parent/safe_path(uri)).is_file():
                        raise ValueError("missing glTF dependency: "+uri)

def acquire(plan,output):
    folder=output/plan["kind"]/plan["id"]/plan["resolution"]
    if folder.exists():
        meta=folder/"PROVENANCE.json"
        if not meta.is_file():
            raise ValueError("existing directory without provenance; refusing overwrite")
        saved=json.loads(meta.read_text(encoding="utf-8"))
        old={x["path"]:x for x in saved["files"]}
        for spec in plan["files"]:
            record=old.get(spec["path"])
            path=folder/safe_path(spec["path"])
            if not record or record["url"] != spec["url"] or not path.is_file() or path.stat().st_size != spec["bytes"] or digest(path)[0] != record["sha256"]:
                raise ValueError("existing source changed; archive or move it before retry")
            if spec.get("md5") and digest(path)[1].lower() != spec["md5"].lower():
                raise ValueError("cached MD5 mismatch")
        return "cached"
    folder.parent.mkdir(parents=True,exist_ok=True)
    staging=Path(tempfile.mkdtemp(prefix=".acquire-",dir=folder.parent))
    try:
        records=[fetch_file(x,staging/safe_path(x["path"])) for x in plan["files"]]
        if plan["kind"]=="models":
            validate_gltf(staging,records)
        write_json(staging/"PROVENANCE.json",{**plan,"files":records,
            "retrieved_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"status":"source integrity checked; visual approval pending"})
        staging.rename(folder)
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    return "downloaded"

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--output",type=Path,default=ROOT.parent/"aster-valley-asset-source")
    ap.add_argument("--scope",choices=["core","expanded"],default="expanded")
    ap.add_argument("--resolution",choices=["1k","2k","4k","8k"],default="4k")
    ap.add_argument("--budget-mib",type=int,default=8192,help="maximum declared bytes for this run, including cached files")
    ap.add_argument("--max-assets",type=int,default=250)
    ap.add_argument("--catalog-only",action="store_true",help="save shortlist without querying individual files")
    ap.add_argument("--plan-only",action="store_true",help="resolve file metadata without downloading")
    ap.add_argument("--only",nargs="+",help="optional asset IDs")
    args=ap.parse_args()
    if args.budget_mib <= 0 or args.max_assets <= 0:
        ap.error("positive limits required")
    output=args.output.resolve()
    if output==ROOT or ROOT in output.parents:
        # Exception: explicit ignored external staging directory within clone is not permitted.
        ap.error("choose output outside the Godot repository to prevent accidental imports")
    output.mkdir(parents=True,exist_ok=True)
    catalog=json.loads(CATALOG.read_text(encoding="utf-8"))
    assets={kind:api("/assets?t="+kind) for kind in KINDS}
    candidates,missing=select(catalog,assets,args.scope)
    if args.only:
        candidates=[x for x in candidates if x["id"] in args.only]
    candidates=candidates[:args.max_assets]
    write_json(output/"SHORTLIST.json",{"provider":"Powered by Poly Haven","candidates":candidates,"missing_priority_ids":missing})
    if args.catalog_only:
        print(f"{len(candidates)} catalog candidates")
        return 0
    report=[]
    total=0
    for item in candidates:
        try:
            plan=make_plan(item,args.resolution)
            if total+plan["bytes"] > args.budget_mib*MIB:
                report.append({**plan,"status":"skipped_budget"})
                continue
            total+=plan["bytes"]
            status="planned" if args.plan_only else acquire(plan,output)
            report.append({**plan,"status":status})
            print(item["id"],status,round(plan["bytes"]/MIB,1),"MiB",flush=True)
        except Exception as e:
            report.append({**item,"status":"failed","error":str(e)})
            print(item["id"],"FAILED",e,flush=True)
        finally:
            write_json(output/"ACQUISITION_REPORT.json",{"scope":args.scope,"resolution":args.resolution,
                "budget_mib":args.budget_mib,"declared_bytes":total,"results":report,"missing_priority_ids":missing})
    ok=sum(x["status"] in ("downloaded","cached","planned") for x in report)
    print(f"{ok}/{len(candidates)} completed; inspect ACQUISITION_REPORT.json")
    return 0 if ok else 1

if __name__=="__main__":
    raise SystemExit(main())
