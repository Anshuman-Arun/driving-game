"""Raw telemetry validator and A/B report. No inferred rendering or visual acceptance."""
import argparse
import csv
import json
import math
from pathlib import Path
import re
import statistics
import struct
import sys

def percentile(values, q):
    if not values:
        return None
    ordered = sorted(values)
    pos = (len(ordered) - 1) * q
    lo, hi = math.floor(pos), math.ceil(pos)
    return ordered[lo] + (ordered[hi] - ordered[lo]) * (pos - lo)

def valid(value, positive=True):
    try:
        x = float(value)
        return x if not isinstance(value, bool) and math.isfinite(x) and (x > 0 if positive else x >= 0) else None
    except (ValueError, TypeError, OverflowError):
        return None

def describe(values):
    return {"n": len(values), **{f"p{int(q*100)}": percentile(values, q) for q in (.5,.95,.99)}}

def summarize(rows):
    frames = [x for row in rows if (x := valid(row.get("frame_ms"))) is not None]
    n = len(frames)
    duration = sum(frames) / 1000
    tail = sorted(frames, reverse=True)[:max(1, math.ceil(n * .01))]
    summary = {"frames": n, "invalid_intervals": len(rows) - n, "duration_s": duration,
               "longest_interval_ms": max(frames, default=None), "intervals_over_50ms": sum(v > 50 for v in frames),
               "frame_ms": describe(frames), "mean_fps": n / duration if duration else None,
               "one_percent_low_fps": 1000 / statistics.mean(tail) if tail else None,
               "deadline_misses": sum(v > 1000/60 for v in frames)}
    for name in ("gpu_ms","cpu_ms","vram_mib","draws","triangles","speed_mps","grass_instances","fov"):
        values = [x for row in rows if (x := valid(row.get(name), name in ("gpu_ms","cpu_ms","fov","vram_mib"))) is not None]
        summary[name] = describe(values)
        summary[name]["missing"] = len(rows) - len(values)
    trajectory = {}
    telemetry_errors = 0
    previous = 0.0
    moving_s = 0.0
    first_position = None
    max_displacement = 0.0
    for row in rows:
        t, speed, ms = valid(row.get("elapsed_s")), valid(row.get("speed_mps"),False), valid(row.get("frame_ms"))
        try:
            xyz = [float(row[k]) for k in ("x","y","z")]
        except (ValueError, KeyError, TypeError):
            xyz = []
        if t is None or speed is None or ms is None or len(xyz)!=3 or not all(math.isfinite(v) for v in xyz) or valid(row.get("fov")) is None or not str(row.get("gear","")).strip():
            telemetry_errors += 1
            continue
        # End-of-frame elapsed seconds must be strictly increasing and agree with
        # the independently logged frame interval (allow decimal serialization).
        if t <= previous or abs((t-previous)*1000-ms) > max(.05, ms*.001):
            telemetry_errors += 1
        previous = t
        if speed > 5:
            moving_s += ms/1000
        if first_position is None:
            first_position=xyz
        max_displacement=max(max_displacement, math.dist(first_position,xyz))
        sec=round(t)
        if abs(t-sec)<=.25 and (sec not in trajectory or abs(t-sec)<abs(trajectory[sec][0]-sec)):
            trajectory[sec]=[t,speed,*xyz,float(row["fov"]),str(row["gear"])]
    summary.update(trajectory=trajectory,telemetry_errors=telemetry_errors,elapsed_s=previous,
                   moving_time_fraction=moving_s/duration if duration else 0,
                   max_displacement_m=max_displacement)
    return summary

MATCH = ("site","scenario","preset","width","height","scale","renderer","gpu","cpu",
         "driver","car","fov","pose","traffic","audio","warmup_s","sample_s",
         "controls","lighting","vsync","max_fps","scene","route_hash","interaction")
REQUIRED_COLUMNS = {"elapsed_s","frame_ms","speed_mps","gear","x","y","z","fov",
                    "gpu_ms","cpu_ms","vram_mib","draws","triangles","grass_instances"}

def png_matches(path,width,height):
    if not path.is_file() or path.stat().st_size<45:
        return False
    with path.open("rb") as f:
        head=f.read(24)
        if len(head)!=24 or head[:8]!=b"\x89PNG\r\n\x1a\n" or head[12:16]!=b"IHDR" or struct.unpack(">I",head[8:12])[0]!=13:
            return False
        if struct.unpack(">II",head[16:24])!=(width,height):
            return False
        f.seek(-12,2)
        return f.read(12)==b"\x00\x00\x00\x00IEND\xaeB\x60\x82"

def vector(value):
    return value if isinstance(value,list) and len(value)==3 and all(type(x) in (float,int) and math.isfinite(x) for x in value) else None

def load(path):
    meta=json.loads((path/"meta.json").read_text(encoding="utf-8"))
    if not isinstance(meta,dict):
        raise ValueError("metadata must be an object")
    with (path/"frames.csv").open(newline="",encoding="utf-8") as f:
        reader=csv.DictReader(f)
        if not reader.fieldnames or len(set(reader.fieldnames))!=len(reader.fieldnames) or not REQUIRED_COLUMNS.issubset(reader.fieldnames):
            raise ValueError("missing or duplicate capture CSV columns")
        rows=list(reader)
    if any(None in row or None in row.values() for row in rows):
        raise ValueError("malformed CSV row")
    # A truncated capture must not pass on metadata alone.
    meta["_screenshots_present"]=all(png_matches(path/name,meta.get("width"),meta.get("height")) for name in ("start.png","end.png"))
    return meta,summarize(rows)

def features(meta):
    raw=meta.get("features")
    if not isinstance(raw,str):
        return None
    items=raw.split(",") if raw else []
    return set(items) if len(set(items))==len(items) and all(x in {"a","d","e"} for x in items) else None

def compare(baseline,candidate):
    a,sa=baseline
    b,sb=candidate
    differences=[k for k in MATCH if k not in a or k not in b or a[k]!=b[k]]
    unresolved=[]
    af,bf=features(a),features(b)
    if a.get("mode")!="baseline" or b.get("mode")!="candidate" or af!=set() or not bf:
        unresolved.append("invalid A/B mode or feature flags")
    for name,m,s in (("baseline",a,sa),("candidate",b,sb)):
        if not re.fullmatch(r"[0-9a-f]{40}",str(m.get("commit",""))) or m.get("complete") is not True or m.get("_screenshots_present") is not True:
            unresolved.append(name+" incomplete metadata or screenshot evidence")
        requested=valid(m.get("sample_s"))
        if (requested is None or requested<60 or s["duration_s"]<requested-0.001 or
            s["duration_s"]>requested+max(1.0,(s["longest_interval_ms"] or 0)/1000) or
            s["invalid_intervals"] or s["telemetry_errors"] or abs(s["elapsed_s"]-s["duration_s"])>.05 or not s["frames"]):
            unresolved.append(name+" incomplete/invalid time series")
        if m.get("renderer")!="forward_plus" or not m.get("gpu") or not m.get("cpu") or m.get("driver") in ("unavailable","",None,[]):
            unresolved.append(name+" renderer/hardware unverified")
        if m.get("car")!="mclaren_senna" or m.get("vsync")!="disabled" or m.get("max_fps")!=0 or m.get("capture_conditions_changed") is not False or type(m.get("interaction")) is not bool or valid(m.get("warmup_s")) is None or float(m["warmup_s"])<5:
            unresolved.append(name+" capture conditions unverified or changed")
        if m.get("traffic")!="enabled" or m.get("audio")!="enabled":
            unresolved.append(name+" production traffic/audio not confirmed")
        if s["draws"]["missing"] or s["triangles"]["missing"]:
            unresolved.append(name+" missing rendering counters")
    if a.get("legacy_grass")!="enabled":
        unresolved.append("baseline legacy grass not confirmed")
    if bf and "a" in bf:
        if b.get("legacy_grass")!="disabled":
            unresolved.append("candidate grass stacked or legacy state unknown")
        if sb["grass_instances"]["missing"] or not sb["grass_instances"]["n"] or not (sb["grass_instances"]["p95"] or 0)>0:
            unresolved.append("candidate grass absent or count unavailable")
    elif b.get("legacy_grass")!="enabled":
        unresolved.append("non-grass candidate changed legacy grass")
    p,q=vector(a.get("camera_start_position")),vector(b.get("camera_start_position"))
    u,v=vector(a.get("camera_start_forward")),vector(b.get("camera_start_forward"))
    if p is None or q is None or u is None or v is None or math.dist(p,q)>.5 or math.dist(u,v)>.035:
        unresolved.append("initial camera pose missing or mismatched")
    if a.get("scenario")=="route" and (not re.fullmatch(r"[0-9a-f]{64}",str(a.get("route_hash",""))) or a.get("route_hash")!=b.get("route_hash")):
        unresolved.append("scripted route identity missing or mismatched")
    if a.get("commit")!=b.get("commit"):
        unresolved.append("use same integrated commit with opt-in flags")
    trajectory=None
    ta,tb=sa["trajectory"],sb["trajectory"]
    seconds=sorted(set(ta)&set(tb))
    pos=[math.dist(ta[t][2:5],tb[t][2:5]) for t in seconds]
    speed=[abs(ta[t][1]-tb[t][1]) for t in seconds]
    fov=[abs(ta[t][5]-tb[t][5]) for t in seconds]
    gears=sum(ta[t][6]!=tb[t][6] for t in seconds)
    trajectory={"matched_seconds":len(seconds),"position_error_p95_m":percentile(pos,.95),
                "speed_error_p95_mps":percentile(speed,.95),"fov_error_p95_deg":percentile(fov,.95),
                "gear_mismatch_fraction":gears/len(seconds) if seconds else None}
    scenario=a.get("scenario")
    moving=scenario in ("manual","route")
    minimum=math.ceil((valid(a.get("sample_s")) or 60)*.8)
    if len(seconds)<minimum or (trajectory["position_error_p95_m"] or 0)>(10 if moving else .5) or (trajectory["speed_error_p95_mps"] or 0)>(3 if moving else .5) or (trajectory["fov_error_p95_deg"] or 0)>1 or (trajectory["gear_mismatch_fraction"] or 0)>.1:
        unresolved.append("trajectories, speed, gear or FOV not sufficiently matched")
    if moving:
        if min(sa["moving_time_fraction"],sb["moving_time_fraction"])<.8:
            unresolved.append("less than 80% of capture time above 5 m/s")
        if scenario=="route" and (a.get("route_departed") is not False or b.get("route_departed") is not False):
            unresolved.append("scripted route departure or missing status")
    elif scenario in ("stationary","offroad"):
        if max(sa["max_displacement_m"],sb["max_displacement_m"])>.5 or max(sa["speed_mps"]["p99"] or 0,sb["speed_mps"]["p99"] or 0)>.5:
            unresolved.append("stationary capture moved")
    else:
        unresolved.append("unknown scenario")
    delta=None
    if not differences and sa["frames"] and sb["frames"] and not sa["invalid_intervals"] and not sb["invalid_intervals"] and not sa["telemetry_errors"] and not sb["telemetry_errors"]:
        delta={k:sb["frame_ms"][k]-sa["frame_ms"][k] for k in ("p50","p95","p99")}
    comparable=not differences and not unresolved
    budget=(sb["frame_ms"]["p95"]<=1000/60 and sb["frame_ms"]["p99"]<=25) if comparable and b.get("preset")=="medium" and b.get("width")==1920 and b.get("height")==1080 and b.get("scale")==1.0 else None
    return {"baseline":{k:v for k,v in sa.items() if k!="trajectory"},
            "candidate":{k:v for k,v in sb.items() if k!="trajectory"},
            "metadata_mismatches":differences,"unresolved":unresolved,"comparable":comparable,
            "trajectory":trajectory,"observed_frame_ms_delta":delta,"candidate_budget_met":budget,
            "visual_acceptance":"not assessed"}

def main():
    p=argparse.ArgumentParser()
    p.add_argument("baseline",type=Path)
    p.add_argument("candidate",type=Path)
    p.add_argument("--out",type=Path)
    args=p.parse_args()
    try:
        report=compare(load(args.baseline),load(args.candidate))
        result=json.dumps(report,indent=2,allow_nan=False)
    except (ValueError,OSError,TypeError,OverflowError) as exc:
        report={"comparable":False,"candidate_budget_met":None,"unresolved":[str(exc)]}
        result=json.dumps(report,indent=2)
    if args.out:
        args.out.write_text(result,encoding="utf-8")
    print(result)
    return 1 if not report["comparable"] else (2 if report["candidate_budget_met"] is False else 0)

if __name__=="__main__":
    sys.exit(main())
