"""Fetch the pinned recorded-audio catalog, prepare offline audition WAVs and verify.
Requires Python 3.10+ and ffmpeg; no game-time networking. Does not edit existing audio.
"""
import argparse, array, hashlib, json, math, os, re, shutil, subprocess, sys, tempfile, time, wave, zipfile
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "assets/audio/recorded"
CATALOG = PACK / "catalog.json"
OUT = PACK / "payload"
RATE = 48000
MAX = 40 * 1024 * 1024
HOSTS = {"raw.githubusercontent.com", "lpc.opengameart.org", "opengameart.org", "kenney.nl", "www.kenney.nl"}

def download(item, path):
    url = item["url"]
    for attempt in range(3):
        try:
            if urlsplit(url).scheme != "https" or urlsplit(url).hostname not in HOSTS:
                raise ValueError("Unapproved source host")
            with urlopen(Request(url, headers={"User-Agent":"AsterValleyAudio/1.0"}), timeout=60) as response:
                if urlsplit(response.geturl()).hostname not in HOSTS:
                    raise ValueError("Unapproved redirect")
                data = response.read(MAX + 1)
            if not data or len(data) > MAX:
                raise ValueError("Source empty or oversized")
            if "size" in item and len(data) != item["size"]:
                raise ValueError("Source size mismatch")
            if "git_blob" in item:
                sha = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
                if sha != item["git_blob"]:
                    raise ValueError("Pinned Git blob hash mismatch")
            path.write_bytes(data)
            return hashlib.sha256(data).hexdigest()
        except (OSError, ValueError) as exc:
            print(f"{url}: {attempt+1}/3: {exc}", flush=True)
            if attempt == 2: raise
            time.sleep(2 ** attempt)

def decode(path):
    proc = subprocess.run(["ffmpeg","-v","error","-nostdin","-i",str(path),"-vn","-ac","1","-ar",str(RATE),"-f","s16le","-"], check=True, capture_output=True, timeout=90)
    samples = array.array("h")
    samples.frombytes(proc.stdout)
    if sys.byteorder != "little": samples.byteswap()
    if len(samples) < RATE // 20 or len(samples) > RATE * 180 or max(map(abs,samples)) < 32:
        raise ValueError("Invalid duration or silence")
    return samples

def crop_loop(samples, seconds):
    if not seconds: return samples
    length = min(len(samples), RATE * seconds)
    start = (len(samples) - length) // 2
    s = samples[start:start+length]
    n = min(RATE // 8, len(s)//8)
    # Rotate with an overlap so the final sample joins the first segment naturally.
    blended = array.array("h", (round(s[-n+i]*(1-i/n)+s[i]*(i/n)) for i in range(n)))
    return blended + s[n:-n]

def metrics(samples):
    peak = max(map(abs,samples))
    rms = math.sqrt(sum(x*x for x in samples)/len(samples))
    return {"sample_rate":RATE,"channels":1,"bit_depth":16,"frames":len(samples),"duration_s":round(len(samples)/RATE,5),"peak_dbfs":round(20*math.log10(max(1,peak)/32768),2),"rms_dbfs":round(20*math.log10(max(1,rms)/32768),2),"seam_delta":abs(samples[0]-samples[-1]),"clipped_samples":sum(abs(x)>=32767 for x in samples)}

def write(samples, path, gain):
    s = array.array("h",(max(-32767,min(32767,round(x*gain))) for x in samples))
    m = metrics(s)
    if sys.byteorder != "little": s.byteswap()
    path.parent.mkdir(parents=True,exist_ok=True)
    with wave.open(str(path),"wb") as w:
        w.setparams((1,2,RATE,0,"NONE","not compressed"))
        w.writeframes(s.tobytes())
    m["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    return m

def process():
    if OUT.exists(): verify(); return
    if not shutil.which("ffmpeg"): raise RuntimeError("ffmpeg required")
    c = json.loads(CATALOG.read_text(encoding="utf8"))
    with tempfile.TemporaryDirectory(prefix=".audio-",dir=PACK) as tmp:
        temp=Path(tmp)
        stage=temp/"payload";stage.mkdir()
        records=[];failures=[];bank_info=[]
        def record(samples, rel, gain, source, looping):
            p=stage/rel
            m=write(samples,p,gain)
            m.update(path=rel,loop=looping,source=source)
            records.append(m)
            return m
        for bank in c["banks"]:
            print("Bank",bank["profile"],flush=True)
            decoded=[]; missing=[]
            for i,item in enumerate(bank["loops"]):
                try:
                    path=temp/f"source-{i}.wav"
                    sha=download(item,path)
                    decoded.append((item,decode(path),sha))
                except (OSError, ValueError, subprocess.SubprocessError) as exc:
                    missing.append({"file":item["file"],"error":str(exc)})
            if not decoded:
                failures.append({"bank":bank["profile"],"reason":"All loops unavailable","details":missing})
                continue
            peak=max(max(map(abs,x[1])) for x in decoded)
            gain=min(1.0, 26000/peak)
            manifest={k:v for k,v in bank.items() if k!="loops"}
            manifest["loops"]=[];manifest["missing"]=missing
            for item,samples,sha in decoded:
                rel=f"engines/{bank['profile']}/{item['file']}"
                m=record(samples,rel,gain,{"url":item["url"],"original_sha256":sha,"license":bank["license"],"changes":"Mono PCM16 at 48kHz; common bank attenuation if needed."},True)
                manifest["loops"].append({"file":item["file"],"rpm":item["rpm"],"layer":item["layer"],"gain":item["gain"],"duration_s":m["duration_s"],"seam_delta":m["seam_delta"]})
            (stage/"engines"/bank["profile"]/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf8")
            bank_info.append({"profile":bank["profile"],"loops":len(decoded),"missing":missing,"status":bank["status"]})
        for item in c["effects"]:
            try:
                path=temp/"effect.source";sha=download(item,path)
                s=crop_loop(decode(path),item["seconds"]) if item["loop"] else decode(path)
                record(s,item["file"],min(1.0,26000/max(map(abs,s))),{**item,"original_sha256":sha,"changes":"Mono PCM16 48kHz, peak attenuation if needed; centered crop and 125ms overlap when seconds > 0."},item["loop"])
            except (OSError, ValueError, subprocess.SubprocessError) as exc:
                failures.append({"file":item["file"],"reason":str(exc)})
        try:
            item=c["impact_pack"];path=temp/"impact.zip";sha=download(item,path)
            with zipfile.ZipFile(path) as z:
                names=sorted(n for n in z.namelist() if n.lower().endswith((".ogg",".wav")) and not n.startswith("__MACOSX"))
                metal=[n for n in names if "metal" in n.lower()]
                heavy=[n for n in names if "heavy" in n.lower() and n not in metal]
                selected=metal[:4]+heavy[:3]
                if not selected: raise ValueError("No expected metal/heavy samples: "+str(names[:12]))
                for i,name in enumerate(selected):
                    if z.getinfo(name).file_size>MAX: raise ValueError("Archive entry oversized")
                    p=temp/"impact.source";p.write_bytes(z.read(name));s=decode(p)
                    label="metal" if name in metal else "heavy"
                    record(s,f"chassis/impact_{label}_{i+1:02}.wav",min(1.0,26000/max(map(abs,s))),{**item,"archive_entry":name,"original_sha256":sha,"changes":"Decoded mono PCM16 48kHz; attenuation if needed."},False)
        except (OSError, ValueError, subprocess.SubprocessError, zipfile.BadZipFile) as exc:
            failures.append({"pack":"impacts","reason":str(exc)})
        if not records: raise RuntimeError("No verified recordings")
        lock={"version":1,"banks":bank_info,"files":records,"failures":failures,"missing_sources":c["missing_sources"],"quality":"Technical checks only; no human listening, RPM truth or controlled load certification."}
        (stage/"LICENSES_AND_HASHES.json").write_text(json.dumps(lock,indent=2)+"\n",encoding="utf8")
        verify(stage)
        stage.rename(OUT)

def verify(root=OUT):
    lock=json.loads((root/"LICENSES_AND_HASHES.json").read_text(encoding="utf8"))
    seen=set()
    for m in lock["files"]:
        p=root/m["path"]
        if m["path"] in seen or not p.resolve().is_relative_to(root.resolve()): raise ValueError("Invalid path")
        seen.add(m["path"])
        if hashlib.sha256(p.read_bytes()).hexdigest()!=m["sha256"]: raise ValueError("Changed recording "+str(p))
        with wave.open(str(p),"rb") as w:
            assert (w.getnchannels(),w.getsampwidth(),w.getframerate(),w.getnframes())==(1,2,RATE,m["frames"])
            assert m["clipped_samples"]==0
    print(json.dumps({"verified_wavs":len(seen),"banks":lock["banks"],"failures":lock["failures"],"bytes":sum((root/p).stat().st_size for p in seen)},indent=2),flush=True)

if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--verify",action="store_true");a=p.parse_args()
    verify() if a.verify else process()
