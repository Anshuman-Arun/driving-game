#!/usr/bin/env python3
"""Acquire two original professional onboard ramp references from official free GDC ZIPs.
Only fetch the selected members using public HTTP ranges. No source audio is committed,
published or uploaded by CI. The index is a locator, not the audio provider.
"""
import argparse
import hashlib
import json
import pathlib
import struct
import urllib.request
import urllib.parse
import zipfile
import time
import zlib
import shutil
import subprocess
import sys

SOURCES = {
    "aventador_svj": {
        "car": "2014 Lamborghini Aventador (V12 family reference, not SVJ)",
        "file": "lamborghini_aventador_t14_onbrd_start_drive_ramps_stop_off_exhaust_right_DPA4062.wav",
        "url": "https://downloads.sonniss.com/Sonniss.com%20-%20GDC%202020%20-%20Game%20Audio%20Bundle%20Part7of14.zip",
        "offset": 2032976165, "compressed": 144143335, "order": 6, "idle": 900, "redline": 8700,
    },
    "mclaren_senna": {
        "car": "2019 McLaren 720S Spider SSG (V8 family reference, not Senna)",
        "file": "McLaren 720S - t5 - ONBRD - RAMPS - Drive - EXHAUST - Left - BETA58.wav",
        "url": "https://downloads.sonniss.com/Sonniss.com-GDC2024-GameAudioBundle5of9.zip",
        "offset": 1935837018, "compressed": 61474480, "order": 4, "idle": 980, "redline": 8000,
    },
}
LICENSE = "https://sonniss.com/gdc-bundle-license/"
INDEX = "https://github.com/yansixing/gdc-bundle-finder"


def get_range(url, start, count):
    end = start + count - 1
    req = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}",
                                "User-Agent": "AsterValleyAudioResearch/1.0"})
    with urllib.request.urlopen(req, timeout=25) as response:
        if response.status != 206 or not response.headers.get("Content-Range", "").startswith(f"bytes {start}-{end}/"):
            raise RuntimeError(f"Expected HTTP 206; got {response.status}, range={response.headers.get('Content-Range')}, type={response.headers.get('Content-Type')}, length={response.headers.get('Content-Length')}, prefix={response.read(24)!r}")
        body = response.read(count + 1)
    if len(body) != count:
        raise RuntimeError(f"Wrong range size: {len(body)} instead of {count}")
    return body


def acquire_range(cfg, target):
    header = get_range(cfg["url"], cfg["offset"], 30)
    sig, version, flags, method, tm, dt, crc, csize, usize, nlen, xlen = struct.unpack("<I5H3I2H", header)
    if sig != 0x04034B50 or flags & 1 or method != 8 or nlen > 4096:
        raise ValueError("Unexpected ZIP local header")
    metadata = get_range(cfg["url"], cfg["offset"]+30, nlen+xlen)
    name = metadata[:nlen].decode("utf-8" if flags & 0x800 else "cp437")
    if pathlib.PurePosixPath(name).name != cfg["file"]:
        raise ValueError(f"Index stale: ZIP member is {name!r}")
    if csize not in (0,0xffffffff,cfg["compressed"]):
        raise ValueError("ZIP member compressed size mismatch")
    start = cfg["offset"] + 30+nlen+xlen
    decompressor = zlib.decompressobj(-15)
    checksum = 0
    written = 0
    sha = hashlib.sha256()
    with target.open("wb") as out:
        for offset in range(0,cfg["compressed"],8*1024*1024):
            size = min(8*1024*1024,cfg["compressed"]-offset)
            chunk = get_range(cfg["url"],start+offset,size)
            raw = decompressor.decompress(chunk)
            written += len(raw)
            if written > 512*1024*1024:
                raise ValueError("Reference exceeds safe size")
            checksum = zlib.crc32(raw,checksum)
            sha.update(raw)
            out.write(raw)
        tail = decompressor.flush()
        out.write(tail)
        sha.update(tail)
        checksum = zlib.crc32(tail,checksum)
        written += len(tail)
    if not decompressor.eof or (usize not in (0,0xffffffff) and usize != written) or (crc and crc != checksum):
        raise ValueError("ZIP member decompression or CRC mismatch")
    with target.open("rb") as f:
        if f.read(4) not in (b"RIFF",b"RF64",b"BW64"):
            raise ValueError("Expected original WAV")
    print("Downloaded verified member",name,"bytes",written,"sha256",sha.hexdigest(),flush=True)
    return sha.hexdigest()


def acquire_full(cfg, target):
    # If a publisher serves a real ZIP but ignores Range, read the archive
    # once rather than repeatedly requesting the same multi-GB object.
    # Limit transfer, time and extraction size; never accept an HTML error.
    archive=target.with_suffix(".zip")
    request=urllib.request.Request(cfg["url"],headers={"User-Agent":"AsterValleyAudioResearch/1.0"})
    deadline=time.monotonic()+180
    try:
        with urllib.request.urlopen(request,timeout=25) as response:
            prefix=response.read(4)
            length=int(response.headers.get("Content-Length","0"))
            if prefix!=b"PK\\x03\\x04" or length>3_200_000_000:
                raise ValueError(f"Not a bounded ZIP: {prefix!r}, length={length}")
            with archive.open("wb") as out:
                out.write(prefix)
                count=4
                while True:
                    if time.monotonic()>deadline:
                        raise TimeoutError("180-second archive transfer budget exceeded")
                    chunk=response.read(4*1024*1024)
                    if not chunk: break
                    count+=len(chunk)
                    if count>3_200_000_000:
                        raise ValueError("Archive size limit exceeded")
                    out.write(chunk)
        with zipfile.ZipFile(archive) as z:
            matches=[m for m in z.infolist() if pathlib.PurePosixPath(m.filename).name==cfg["file"]]
            if len(matches)!=1 or matches[0].file_size>512*1024*1024:
                raise ValueError("Expected a single bounded WAV member")
            sha=hashlib.sha256()
            with z.open(matches[0]) as source,target.open("wb") as out:
                for chunk in iter(lambda:source.read(1024*1024),b""):
                    sha.update(chunk);out.write(chunk)
        print("Downloaded full archive member",cfg["file"],sha.hexdigest(),flush=True)
        return sha.hexdigest()
    finally:
        archive.unlink(missing_ok=True)


def acquire(cfg,target):
    primary=cfg["url"]
    mirror="https://hippolytus.feralhosting.com/sonniss/"+urllib.parse.urlsplit(primary).path.rsplit("/",1)[-1]
    errors=[]
    for url in (mirror,primary):
        for method in (acquire_range,acquire_full):
            try:
                print("REFERENCE attempt",method.__name__,url,flush=True)
                return method(dict(cfg,url=url),target)
            except Exception as exc:
                errors.append(f"{method.__name__}: {exc}")
                print("REFERENCE attempt failed",repr(exc),flush=True)
                target.unlink(missing_ok=True)
    raise RuntimeError("; ".join(errors))


def analyze(path, cfg):
    import numpy as np
    from scipy import signal,ndimage
    from continuous_sweep_research import track,candidates
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    # Whole take, not arbitrarily truncated to the first 120 seconds.
    raw = subprocess.check_output([ffmpeg,"-v","error","-i",str(path),"-ac","1","-ar","24000","-f","f32le","-"])
    x = np.frombuffer(raw,dtype="<f4")
    if not np.isfinite(x).all() or len(x)<24000:
        raise ValueError("Invalid decoded WAV")
    # Analyze in chunks to keep memory bounded. A real RPM estimate is NOT
    # measured tachometer data. No automated sound-bank promotion.
    segments=[]
    for start in range(0,len(x),24000*45):
        segment=x[start:start+24000*45]
        if len(segment)<24000: continue
        t,hz,conf,level=track(segment,cfg["order"],cfg["idle"],cfg["redline"])
        rows=candidates(t,hz,conf,level,cfg["order"])
        for row in rows:
            row["start_s"]+=start/24000
            row["end_s"]+=start/24000
            row.pop("a",None);row.pop("b",None)
            segments.append(row)
    segments.sort(key=lambda row:row["score"],reverse=True)
    # Character statistics on genuine high-RPM windows only, as an objective
    # starting point for comparison. Not a substitute for an audible A/B.
    high=[]
    for start in range(0,len(x)-24000,24000//2):
        chunk=x[start:start+24000]
        f,t,z=signal.stft(chunk,24000,nperseg=2048,noverlap=1536)
        power=abs(z)**2
        band=(f>=40)&(f<=4500)
        firing=(f>=cfg["redline"]*cfg["order"]/60*.80)&(f<=cfg["redline"]*cfg["order"]/60*1.05)
        if not np.any(firing): continue
        peak=f[np.argmax(power[band],axis=0)+np.flatnonzero(band)[0]]
        if np.mean((peak>=f[firing][0])&(peak<=f[firing][-1]))<0.7: continue
        total=power[band].sum(axis=0)
        if np.sqrt(np.mean(chunk*chunk))<0.005: continue
        concentration=np.median(power[band].max(axis=0)/np.maximum(total,1e-15))
        high.append({"start_s":round(start/24000,2),"dominant_hz":float(np.median(peak)),
                     "dominant_bin_fraction":float(concentration)})
    return {"duration_s":len(x)/24000,"sweeps":segments[:20],"high_rpm_windows":high[:50],
            "high_rpm_window_count":len(high),"high_rpm_median_concentration":float(np.median([w["dominant_bin_fraction"] for w in high])) if high else None}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output",type=pathlib.Path,required=True)
    p.add_argument("--raw-dir",type=pathlib.Path,required=True)
    args=p.parse_args()
    args.output.mkdir(parents=True,exist_ok=True); args.raw_dir.mkdir(parents=True,exist_ok=True)
    results=[]
    for profile,cfg in SOURCES.items():
        row={"profile":profile,"source":cfg,"license":LICENSE,"index":INDEX,"reference_only":True}
        try:
            dest=args.raw_dir/(profile+".wav")
            row["sha256"]=acquire(cfg,dest)
            row.update(analyze(dest,cfg))
            row["status"]="downloaded_and_analyzed"
            print("REFERENCE",profile,"duration",row["duration_s"],"high RPM windows",row["high_rpm_window_count"],
                  "concentration",row["high_rpm_median_concentration"],"top sweeps",row["sweeps"][:5],flush=True)
        except Exception as exc:
            row["status"]="failed";row["error"]=str(exc)
            print("REFERENCE FAILED",profile,repr(exc),flush=True)
        results.append(row)
        (args.output/"professional_references.json").write_text(json.dumps(results,indent=2)+"\n")
    return 0 if all(r["status"]=="downloaded_and_analyzed" for r in results) else 1

if __name__=="__main__":
    sys.exit(main())
