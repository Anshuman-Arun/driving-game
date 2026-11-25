#!/usr/bin/env python3
"""Reference-only audit of publicly accessible recorded-car clips.
No source audio or derivative WAV is included in the report or game.
A filename/model label is not proof of recording identity.
"""
import hashlib
import json
import pathlib
import subprocess
import sys
import urllib.request
import numpy as np
from scipy import signal
import imageio_ffmpeg
from continuous_sweep_research import track, candidates

SOURCES = [
    {"id":"svj_pixabay","profile":"aventador_svj","order":6,"idle":900,"redline":8700,
     "source":"https://pixabay.com/sound-effects/film-special-effects-lamborghini-aventador-svj-racing-sound-effect-161994/",
     "credit":"mizanstock; mirror verified by filename only",
     "url":"https://raw.githubusercontent.com/rRau2008/Webseite_M293/3e2cb81fab1987c779ad60565b36f64034f6de21/lamborghini-aventador-svj-racing-sound-effect-161994.mp3",
     "blob":"ea83afdc95f4ec12cddd3843c4c6fae8c59733dc"},
    {"id":"aventador_soundboard","profile":"aventador_svj","order":6,"idle":900,"redline":8700,
     "source":"https://github.com/shari003/carSounds","credit":"Unknown original recorder; reference only",
     "url":"https://raw.githubusercontent.com/shari003/carSounds/8a486080ee5ecfb4adfbfc35327b6d9c583e5ecf/sounds/aventador.mp3",
     "blob":"5edeb184c5aae372e3a134c645649dc6d05df790"},
    {"id":"765lt_configurator","profile":"mclaren_senna","order":4,"idle":980,"redline":8000,
     "source":"https://github.com/SAISH1609/MSA_mini_project","credit":"Labeled 765LT; unknown original recorder; reference only",
     "url":"https://raw.githubusercontent.com/SAISH1609/MSA_mini_project/05ba9d25f21c0a9bd3dd4478737800b1435cc654/public/media/mclaren/mclaren.mp3",
     "blob":"76f95e42a22a5057fcd0c5e42e93f91f45a4f5ad"},
]

def inspect(path,cfg):
    raw=subprocess.check_output([imageio_ffmpeg.get_ffmpeg_exe(),"-v","error","-i",str(path),"-ac","1","-ar","44100","-f","f32le","-"])
    x=np.frombuffer(raw,dtype="<f4")
    if len(x)<44100 or not np.isfinite(x).all(): raise ValueError("invalid decoded audio")
    y=signal.resample_poly(x,80,147)
    t,hz,confidence,level=track(y,cfg["order"],cfg["idle"],cfg["redline"])
    sweeps=candidates(t,hz,confidence,level,cfg["order"])
    f,t,z=signal.stft(x,44100,nperseg=2048,noverlap=1792,boundary=None,padded=False)
    band=(f>=40)&(f<=4500)
    energy=abs(z[band])**2
    concentration=np.max(energy,axis=0)/np.maximum(np.sum(energy,axis=0),1e-15)
    active=np.sqrt(np.sum(energy,axis=0))>0.01*np.max(np.sqrt(np.sum(energy,axis=0)))
    peak=f[band][np.argmax(energy,axis=0)]
    nominal=cfg["redline"]*cfg["order"]/60
    hi=active&(peak>=nominal*.8)&(peak<=nominal*1.05)
    def summary(mask):
        return {"frames":int(mask.sum()),"median":float(np.median(concentration[mask])) if mask.any() else None,
                "p90":float(np.quantile(concentration[mask],.9)) if mask.any() else None}
    return {"duration_s":len(x)/44100,"rms_dbfs":float(20*np.log10(max(1e-9,np.sqrt(np.mean(x*x))))),
            "all_active_concentration":summary(active),"high_firing_peak_concentration":summary(hi),
            "candidate_sweeps":sweeps[:12],
            "identity_verified":False,"load_verified":False,"reference_only":True}

def main():
    out=pathlib.Path(sys.argv[1]); out.mkdir(parents=True,exist_ok=True)
    scratch=pathlib.Path(sys.argv[2]); scratch.mkdir(parents=True,exist_ok=True)
    reports=[]
    for cfg in SOURCES:
        row=dict(cfg)
        path=scratch/(cfg["id"]+".mp3")
        try:
            req=urllib.request.Request(cfg["url"],headers={"User-Agent":"AsterValleyAudioReference/1.0"})
            with urllib.request.urlopen(req,timeout=30) as resp:
                data=resp.read(8*1024*1024+1)
            actual=hashlib.sha1(b"blob "+str(len(data)).encode()+b"\0"+data).hexdigest()
            if actual!=cfg["blob"]: raise ValueError("Source blob mismatch: "+actual)
            path.write_bytes(data)
            row.update(inspect(path,cfg));row["status"]="decoded"
        except Exception as exc:
            row.update(status="failed",error=repr(exc))
        finally:
            path.unlink(missing_ok=True)
        reports.append(row)
        print("CLIP REFERENCE",json.dumps(row),flush=True)
        (out/"clip_references.json").write_text(json.dumps(reports,indent=2)+"\n")
    return 0 if any(x["status"]=="decoded" for x in reports) else 1

if __name__=="__main__": sys.exit(main())
