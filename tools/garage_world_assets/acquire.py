"""Acquire independent CC0 models, validate containers/dependencies, record provenance.
No Godot runtime changes. Python 3.10+ standard library.
"""
import argparse, datetime, hashlib, json, os, re, struct, tempfile, time
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit, unquote
from urllib.request import Request, urlopen

ROOT=Path(__file__).resolve().parents[2]
PACK=ROOT/"assets/premium_garage_world"
OUT=PACK/"payload"
CAT=PACK/"catalog.json"
MAX_FILE=85*1024*1024
MAX_TOTAL=350*1024*1024
HOSTS={"tevy.dev","files.innerscene.com","jaronkbragg7337.github.io","api.polyhaven.com","dl.polyhaven.org","dl.polyhaven.com"}

def safe(value):
    value=unquote(value)
    p=PurePosixPath(value)
    if not value or p.is_absolute() or any(x in ("",".","..") for x in value.split("/")) or any(x in value for x in ("\\",":","?","#","\x00")):
        raise ValueError("Unsafe path: "+value)
    return Path(*p.parts)

def get(url,limit):
    for i in range(3):
        try:
            p=urlsplit(url)
            if p.scheme!="https" or p.hostname not in HOSTS: raise ValueError("Unapproved source "+url)
            with urlopen(Request(url,headers={"User-Agent":"AsterValleyAssetReview/1.0"}),timeout=60) as f:
                if urlsplit(f.geturl()).hostname not in HOSTS: raise ValueError("Unexpected redirect "+f.geturl())
                b=f.read(limit+1)
            if not b or len(b)>limit: raise ValueError("Empty or oversized response")
            return b
        except (OSError,ValueError) as e:
            print(f"Attempt {i+1}/3 {url}: {e}",flush=True)
            if i==2: raise
            time.sleep(2**i)

def sha(b): return hashlib.sha256(b).hexdigest()

def model_info(p):
    b=p.read_bytes()
    if p.suffix==".glb":
        if len(b)<20: raise ValueError("GLB header missing")
        magic,version,length=struct.unpack_from("<4sII",b)
        n,typ=struct.unpack_from("<II",b,12)
        if magic!=b"glTF" or version!=2 or length!=len(b) or typ!=0x4e4f534a or n>len(b)-20: raise ValueError("Invalid GLB v2")
        data=json.loads(b[20:20+n])
        offset=20+n
        while offset<len(b):
            size,kind=struct.unpack_from("<II",b,offset)
            offset+=8+size
            if offset>len(b): raise ValueError("GLB chunk overruns file")
        if offset!=len(b): raise ValueError("Invalid chunk alignment")
    else:
        data=json.loads(b)
    if data.get("asset",{}).get("version")!="2.0" or not data.get("meshes"): raise ValueError("Missing glTF meshes")
    for section in ("buffers","images"):
        for item in data.get(section,[]):
            uri=item.get("uri")
            if uri and not uri.startswith("data:") and not (p.parent/safe(uri)).is_file(): raise ValueError("Missing dependency "+uri)
    tris=0
    for mesh in data["meshes"]:
        for prim in mesh["primitives"]:
            if prim.get("mode",4)==4:
                index=prim.get("indices",prim.get("attributes",{}).get("POSITION"))
                if index is not None: tris+=data["accessors"][index]["count"]//3
    return {"source_triangles":tris,"mesh_count":len(data["meshes"]),"materials":len(data.get("materials",[])),"required_extensions":data.get("extensionsRequired",[]),"node_names":[n.get("name","") for n in data.get("nodes",[])][:250]}

def verify(root=OUT):
    l=json.loads((root/"LICENSES_AND_HASHES.json").read_text())
    seen=set()
    for a in l["assets"]:
        for f in a["files"]:
            path=root/safe(f["path"])
            if f["path"] in seen or not path.is_file() or path.stat().st_size!=f["size"] or sha(path.read_bytes())!=f["sha256"]: raise ValueError("Invalid file "+str(path))
            seen.add(f["path"])
            if path.suffix in (".glb",".gltf"): model_info(path)
    if not seen: raise ValueError("No payload files")
    print("Verified",len(seen),"files;",sum(a["status"]=="complete" for a in l["assets"]),"complete asset packages;",sum(a["status"]=="partial" for a in l["assets"]),"partial packages",flush=True)

def acquire():
    if OUT.exists(): verify(); return
    c=json.loads(CAT.read_text())
    total=0; results=[]
    with tempfile.TemporaryDirectory(prefix=".models-",dir=PACK) as tmp:
        stage=Path(tmp)/"payload";stage.mkdir()
        for a in c["assets"]:
            print("Asset",a["id"],flush=True)
            folder=stage/safe(a["category"])/safe(a["id"])
            entry={k:v for k,v in a.items() if k!="files"}
            entry.update(files=[],errors=[],models=[])
            def save(url,name,meta=None):
                nonlocal total
                if meta and int(meta["size"])>MAX_FILE: raise ValueError("Upstream file exceeds budget")
                b=get(url,MAX_FILE)
                if meta and (len(b)!=int(meta["size"]) or hashlib.md5(b).hexdigest()!=meta["md5"]): raise ValueError("Source size or MD5 mismatch")
                if total+len(b)>MAX_TOTAL: raise ValueError("Pack exceeds total budget")
                p=folder/safe(name)
                p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
                total+=len(b)
                entry["files"].append({"path":p.relative_to(stage).as_posix(),"url":url,"sha256":sha(b),"size":len(b)})
                return p
            def rollback(start):
                nonlocal total
                for f in entry["files"][start:]:
                    (stage/f["path"]).unlink(missing_ok=True);total-=f["size"]
                del entry["files"][start:]
            if "polyhaven" in a:
                try:
                    slug=a["polyhaven"]
                    info=json.loads(get("https://api.polyhaven.com/info/"+slug,1024*1024))
                    entry["author"]=info.get("authors",entry["author"])
                    files=json.loads(get("https://api.polyhaven.com/files/"+slug,4*1024*1024))
                    model=files["gltf"][a["resolution"]]["gltf"]
                    deps=model.get("include",{})
                    if any(int(d["size"])>MAX_FILE for d in [model,*deps.values()]) or sum(int(d["size"]) for d in [model,*deps.values()])>90*1024*1024: raise ValueError("Source mesh package exceeds 90 MiB budget")
                    p=save(model["url"],Path(urlsplit(model["url"]).path).name,model)
                    for rel,d in sorted(deps.items()): save(d["url"],rel,d)
                    entry["models"].append({"path":p.relative_to(stage).as_posix(),**model_info(p)})
                except (OSError,ValueError,KeyError,struct.error) as e:
                    rollback(0);entry["errors"].append(str(e))
                expected=1
            else:
                expected=len(a["files"])
                for f in a["files"]:
                    start=len(entry["files"])
                    try:
                        p=save(f["url"],f["name"])
                        entry["models"].append({"path":p.relative_to(stage).as_posix(),**model_info(p)})
                    except (OSError,ValueError,KeyError,struct.error) as e:
                        rollback(start);entry["errors"].append(f["name"]+": "+str(e))
            entry["status"]="complete" if len(entry["models"])==expected else ("partial" if entry["models"] else "unavailable")
            results.append(entry)
        (stage/".gdignore").write_text("Source assets are not automatically imported. Copy accepted assets to a Godot runtime directory after QA.\n")
        lock={"version":1,"downloaded_on":datetime.date.today().isoformat(),"assets":results,"bytes":total,"note":"Source candidates only; Godot import and visual review pending. Required extensions may require Blender conversion."}
        (stage/"LICENSES_AND_HASHES.json").write_text(json.dumps(lock,indent=2)+"\n")
        verify(stage)
        stage.rename(OUT)
    print("Published staging payload",total,"bytes",flush=True)

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--verify",action="store_true");a=p.parse_args()
    verify() if a.verify else acquire()
