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
               "frame_ms": describe(frames), "mean_fps": n / duration if duration else None,
               "one_percent_low_fps": 1000 / statistics.mean(tail) if tail else None,
               "deadline_misses": sum(v > 1000/60 for v in frames)}
    for name in ("gpu_ms", "cpu_ms", "vram_mib", "draws", "triangles", "speed_mps", "grass_instances"):
        values = [x for row in rows if (x := valid(row.get(name), name in ("gpu_ms", "cpu_ms"))) is not None]
        summary[name] = describe(values)
        summary[name]["missing"] = len(rows) - len(values)
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
    if a.get("scenario") != "stationary":
        unresolved.append("moving runs require manual trajectory/speed matching before interpretation")
    if a.get("traffic") != "enabled" or a.get("audio") != "enabled":
        unresolved.append("production traffic/audio not confirmed")
    if b.get("grass_instances", None) is None and sb["grass_instances"]["n"] == 0:
        unresolved.append("candidate grass count unavailable")
    delta = None
    if not differences and not unresolved:
        delta = {k: sb["frame_ms"][k] - sa["frame_ms"][k] for k in ("p50", "p95", "p99")}
    return {"baseline": sa, "candidate": sb, "metadata_mismatches": differences,
            "unresolved": unresolved, "comparable": not differences and not unresolved,
            "frame_ms_delta": delta,
            "candidate_budget_met": (sb["frame_ms"]["p95"] <= 1000/60 and sb["frame_ms"]["p99"] <= 25)
                if delta is not None else None,
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
