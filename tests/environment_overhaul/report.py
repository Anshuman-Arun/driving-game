"""Compare raw capture CSVs; no inferred GPU/CPU values or visual acceptance."""
import argparse
import csv
import json
import math
from pathlib import Path
import statistics
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
        return x if math.isfinite(x) and (x > 0 if positive else x >= 0) else None
    except (ValueError, TypeError):
        return None

def describe(values):
    if not values:
        return {"n": 0, "p50": None, "p95": None, "p99": None}
    return {"n": len(values), **{f"p{int(q*100)}": percentile(values, q) for q in (.5, .95, .99)}}

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
    for name in ("gpu_ms", "cpu_ms", "vram_mib", "draws", "triangles", "speed_mps", "grass_instances"):
        values = [x for row in rows if (x := valid(row.get(name), name in ("gpu_ms", "cpu_ms"))) is not None]
        summary[name] = describe(values)
        summary[name]["missing"] = len(rows) - len(values)
    # At most one trajectory sample per elapsed second; raw data remains in CSV.
    trajectory = {}
    for row in rows:
        t, speed = valid(row.get("elapsed_s"), False), valid(row.get("speed_mps"), False)
        try:
            xyz = [float(row[k]) for k in ("x", "y", "z")]
        except (ValueError, KeyError, TypeError):
            continue
        if t is None or speed is None or not all(math.isfinite(v) for v in xyz):
            continue
        sec = round(t)
        if abs(t-sec) <= .25 and (sec not in trajectory or abs(t-sec)<abs(trajectory[sec][0]-sec)):
            trajectory[sec] = [t, speed, *xyz]
    summary["trajectory"] = trajectory
    summary["moving_frame_fraction"] = (sum((valid(row.get("speed_mps"),False) or 0)>5 for row in rows)/len(rows)) if rows else 0
    return summary

MATCH = ("site", "scenario", "preset", "width", "height", "scale", "renderer",
         "gpu", "cpu", "driver", "car", "fov", "pose", "traffic", "audio", "warmup_s",
         "sample_s", "controls", "lighting", "vsync", "max_fps")
def load(path):
    meta = json.loads((path / "meta.json").read_text(encoding="utf-8"))
    with (path / "frames.csv").open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    return meta, summarize(rows)

def compare(baseline, candidate):
    a, sa = baseline
    b, sb = candidate
    differences = [k for k in MATCH if k not in a or k not in b or a[k] != b[k]]
    unresolved = []
    if a.get("mode") != "baseline" or b.get("mode") != "candidate":
        unresolved.append("incorrect A/B modes")
    for name, m, s in (("baseline", a, sa), ("candidate", b, sb)):
        if not m.get("commit") or m.get("complete") is not True:
            unresolved.append(name + " incomplete metadata")
        if s["duration_s"] < 60 or s["invalid_intervals"] or not s["frames"]:
            unresolved.append(name + " insufficient/invalid frame sample")
    trajectory = None
    if a.get("scenario") in ("manual", "route"):
        ta, tb = sa["trajectory"], sb["trajectory"]
        seconds = sorted(set(ta) & set(tb))
        positions = [math.dist(ta[t][2:], tb[t][2:]) for t in seconds]
        speeds = [abs(ta[t][1] - tb[t][1]) for t in seconds]
        trajectory = {"matched_seconds": len(seconds), "position_error_p95_m": percentile(positions,.95),
                      "speed_error_p95_mps": percentile(speeds,.95)}
        if len(seconds)<48 or trajectory["position_error_p95_m"]>10 or trajectory["speed_error_p95_mps"]>3:
            unresolved.append("moving trajectories or speeds not sufficiently matched")
        if min(sa["moving_frame_fraction"], sb["moving_frame_fraction"]) < .8:
            unresolved.append("less than 80% of capture above 5 m/s")
        if a.get("route_departed") or b.get("route_departed"):
            unresolved.append("scripted route departure")
    elif a.get("scenario") not in ("stationary","offroad"):
        unresolved.append("unknown scenario")
    if any(m.get("traffic") != "enabled" or m.get("audio") != "enabled" for m in (a,b)):
        unresolved.append("production traffic/audio not confirmed")
    if b.get("grass_instances", None) is None and sb["grass_instances"]["n"] == 0:
        unresolved.append("candidate grass count unavailable")
    if a.get("driver") in ("unavailable", "", None) or b.get("driver") in ("unavailable", "", None):
        unresolved.append("GPU driver metadata unavailable")
    # Preview deltas are useful but cannot be confused with the acceptance gate.
    delta = None
    if not differences and sa["frames"] and sb["frames"] and not sa["invalid_intervals"] and not sb["invalid_intervals"]:
        delta = {k: sb["frame_ms"][k] - sa["frame_ms"][k] for k in ("p50", "p95", "p99")}
    comparable = not differences and not unresolved
    sa = {k:v for k,v in sa.items() if k!="trajectory"}
    sb = {k:v for k,v in sb.items() if k!="trajectory"}
    return {"baseline": sa, "candidate": sb, "metadata_mismatches": differences,
            "unresolved": unresolved, "comparable": comparable, "trajectory": trajectory,
            "observed_frame_ms_delta": delta,
            "candidate_budget_met": (sb["frame_ms"]["p95"] <= 1000/60 and sb["frame_ms"]["p99"] <= 25)
                if comparable and delta is not None and b.get("preset")=="medium" and b.get("width")==1920 and b.get("height")==1080 and b.get("scale")==1.0 else None,
            "visual_acceptance": "not assessed"}

def main():
    p = argparse.ArgumentParser()
    p.add_argument("baseline", type=Path)
    p.add_argument("candidate", type=Path)
    p.add_argument("--out", type=Path)
    args = p.parse_args()
    report = compare(load(args.baseline), load(args.candidate))
    result = json.dumps(report, indent=2, allow_nan=False)
    if args.out:
        args.out.write_text(result, encoding="utf-8")
    print(result)
    return 0 if report["comparable"] else 1

if __name__ == "__main__":
    sys.exit(main())
