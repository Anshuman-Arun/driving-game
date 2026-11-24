#!/usr/bin/env python3
"""Prepare audition-only engine banks from legally obtained, annotated recordings.

Requires ffmpeg on PATH and Python 3. No network, no production asset writes.
RPM estimates are never inferred from an unlabeled recording and presented as
ground truth. Use inspect first, annotate real load / RPM windows, then build.
"""
import argparse
import array
import hashlib
import json
import math
import pathlib
import statistics
import subprocess
import sys
import wave

RATE = 48000
ANALYSIS_RATE = 6000
LICENSES = {"CC0-1.0", "CC-BY-3.0", "CC-BY-4.0"}
PROFILES = {"vela_gt", "kestrel_xr", "orion_rs"}


def decode(path, channel="mix"):
    command = ["ffmpeg", "-v", "error", "-i", str(path)]
    if channel != "mix":
        if channel not in ("left", "right"):
            raise ValueError("channel must be mix, left or right")
        command += ["-af", "pan=mono|c0=c" + ("0" if channel == "left" else "1")]
    command += ["-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"]
    data = subprocess.run(command, check=True, stdout=subprocess.PIPE).stdout
    samples = array.array("f")
    samples.frombytes(data)
    if sys.byteorder != "little":
        samples.byteswap()
    if not samples or not all(math.isfinite(v) for v in samples):
        raise ValueError("missing or invalid decoded audio")
    return samples


def rms(x):
    return math.sqrt(sum(v * v for v in x) / max(1, len(x)))


def db(x):
    return round(20 * math.log10(max(x, 1e-8)), 2)


def centered(x):
    mean = statistics.fmean(x)
    return [v - mean for v in x]


def estimate_period(x, lo=35.0, hi=600.0):
    # Downsample by averaging, only for analysis (never for output audio).
    ratio = RATE // ANALYSIS_RATE
    a = centered([sum(x[i:i + ratio]) / ratio
                  for i in range(0, len(x) - ratio + 1, ratio)])
    if rms(a) < 1e-5:
        return 0.0, 0.0
    lower = max(2, math.floor(ANALYSIS_RATE / hi))
    upper = min(len(a) // 3, math.ceil(ANALYSIS_RATE / lo))
    candidates = []
    for lag in range(lower, upper + 1):
        dot = sum(a[i] * a[i - lag] for i in range(lag, len(a)))
        left = sum(v * v for v in a[lag:])
        right = sum(v * v for v in a[:-lag])
        candidates.append((lag, dot / max(1e-12, math.sqrt(left * right))))
    if not candidates:
        return 0.0, 0.0
    best = max(c for _, c in candidates)
    # Prefer the first strong local peak to reduce octave-down errors. Harmonic
    # ambiguity still exists; inspection output is periodicity, NOT verified RPM.
    peaks = [(lag, c) for i, (lag, c) in enumerate(candidates)
             if c >= best - 0.06 and c >= 0.45
             and (i == 0 or c >= candidates[i - 1][1])
             and (i == len(candidates) - 1 or c >= candidates[i + 1][1])]
    lag, score = peaks[0] if peaks else max(candidates, key=lambda p: p[1])
    return ANALYSIS_RATE / lag, score


def inspect(path, channel):
    samples = decode(path, channel)
    print(f"{path.name}: {len(samples) / RATE:.2f}s, RMS {db(rms(samples))} dBFS,"
          f" peak {db(max(abs(v) for v in samples))} dBFS")
    span = RATE // 2
    rows = []
    for i in range(0, len(samples) - span + 1, span):
        segment = samples[i:i + span]
        hz, score = estimate_period(segment)
        rows.append({"start_s": i / RATE, "end_s": (i + span) / RATE,
                     "periodic_hz_estimate": round(hz, 2),
                     "correlation": round(score, 3), "rms_dbfs": db(rms(segment))})
    strong = sum(row["correlation"] >= 0.65 for row in rows)
    print(f"Periodic 0.5s windows: {strong}/{len(rows)} (not RPM/load certification)")
    print(json.dumps(rows, indent=2))
    return rows


def resample_ratio(x, ratio):
    if not 0.8 <= ratio <= 1.25:
        raise ValueError("refuse more than 25% pitch correction; select a closer source")
    length = int((len(x) - 1) / ratio)
    y = []
    for i in range(length):
        p = i * ratio
        j = int(p)
        frac = p - j
        y.append(x[j] * (1 - frac) + x[j + 1] * frac)
    return y


def loop_overlap(x, hz):
    # Find the end offset with the best head/tail correlation, then overlap
    # those windows. Output starts at the former tail and ends immediately
    # before it, removing the original wrap discontinuity.
    period = RATE / hz
    overlap = max(192, int(round(period * max(2, round(0.025 * hz)))))
    if len(x) < overlap * 4:
        raise ValueError("segment too short for phase-matched overlap")
    head = x[:overlap]
    head_energy = sum(v * v for v in head)
    search = max(1, round(period))
    end_best, score_best = len(x), -2.0
    # Search a full period at the tail, using a decimated correlation.
    for end in range(len(x) - search, len(x) + 1, 2):
        tail = x[end - overlap:end]
        dot = sum(head[i] * tail[i] for i in range(0, overlap, 4))
        ea = sum(head[i] ** 2 for i in range(0, overlap, 4))
        eb = sum(tail[i] ** 2 for i in range(0, overlap, 4))
        score = dot / max(1e-12, math.sqrt(ea * eb))
        if score > score_best:
            end_best, score_best = end, score
    if head_energy < 1e-8 or score_best < 0.35:
        raise ValueError(f"no coherent seam (correlation {score_best:.3f})")
    tail = x[end_best - overlap:end_best]
    y = []
    for i in range(overlap):
        w = 0.5 - 0.5 * math.cos(math.pi * i / (overlap - 1))
        y.append(tail[i] * (1 - w) + head[i] * w)
    return y + x[overlap:end_best - overlap], score_best


def make_loop(samples, anchor, firing_per_rev):
    a, b = round(float(anchor["start_s"]) * RATE), round(float(anchor["end_s"]) * RATE)
    if a < 0 or b > len(samples) or not 0.45 * RATE <= b - a <= 4 * RATE:
        raise ValueError("anchor requires a 0.45–4 second in-bounds window")
    raw = centered(samples[a:b])
    expected = float(anchor["source_rpm"]) * firing_per_rev / 60
    target = float(anchor["rpm"]) * firing_per_rev / 60
    hz, confidence = estimate_period(raw, expected * 0.85, expected * 1.15)
    if confidence < 0.45 or hz <= 0:
        raise ValueError("anchor lacks a credible periodic signal")
    # A steady window must remain near its annotated frequency in both halves.
    half = len(raw) // 2
    for portion in (raw[:half], raw[half:]):
        h, c = estimate_period(portion, expected * 0.85, expected * 1.15)
        if c < 0.35 or abs(h - hz) / hz > 0.08:
            raise ValueError("RPM is not sufficiently steady in selected window")
    y, seam_score = loop_overlap(resample_ratio(raw, target / hz), target)
    peak = max(abs(v) for v in y)
    energy = rms(y)
    if energy < 1e-5:
        raise ValueError("silent anchor")
    target_db = -21.0 if anchor["layer"] == "on" else -25.0
    scale = min(10 ** (target_db / 20) / energy, 10 ** (-4 / 20) / peak, 4.0)
    y = [v * scale for v in y]
    return y, {"source_periodic_hz_estimate": round(hz, 3),
               "source_periodicity": round(confidence, 3),
               "seam_correlation": round(seam_score, 3),
               "rms_dbfs": db(rms(y)), "peak_dbfs": db(max(abs(v) for v in y)),
               "duration_s": round(len(y) / RATE, 6),
               "seam_delta_pcm16": round(abs(y[0] - y[-1]) * 32767)}


def write_wav(path, samples):
    pcm = array.array("h", (max(-32768, min(32767, round(v * 32767))) for v in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(pcm.tobytes())


def build(plan_path, out):
    plan = json.loads(plan_path.read_text())
    if plan["profile"] not in PROFILES or plan["license"] not in LICENSES:
        raise ValueError("unknown profile or non-approved redistribution license")
    if not all(str(plan[k]).strip() for k in ("author", "source_url", "license_url", "rpm_basis", "recording_session")):
        raise ValueError("source, license, session and RPM annotation basis required")
    firing = float(plan["firing_per_rev"])
    if not 1 <= firing <= 8:
        raise ValueError("invalid firing order multiplier")
    if out.exists():
        raise ValueError("output must be a new folder, never overwrite an existing bank")
    # Reject production path even if currently empty.
    if "payload" in out.resolve().parts:
        raise ValueError("build to audition folder, not the production payload")
    seen = set()
    rendered = []
    source_cache = {}
    for anchor in plan["anchors"]:
        rpm, layer = int(anchor["rpm"]), anchor["layer"]
        if layer not in ("on", "off") or rpm < 500 or rpm > 16000 or (layer, rpm) in seen:
            raise ValueError("invalid or duplicate anchor")
        if not str(anchor.get("load_basis", "")).strip():
            raise ValueError("annotate how load was identified; RPM slope alone is insufficient")
        seen.add((layer, rpm))
        source = (plan_path.parent / anchor["source_file"]).resolve()
        channel = anchor.get("channel", "mix")
        key = (source, channel)
        if key not in source_cache:
            source_cache[key] = decode(source, channel)
        y, metrics = make_loop(source_cache[key], anchor, firing)
        rendered.append((f"{layer}_{rpm}.wav", anchor, source, y, metrics))
    for layer in ("on", "off"):
        if sum(a["layer"] == layer for _, a, _, _, _ in rendered) < 3:
            raise ValueError("audition bank requires at least three anchors per load layer")
    out.mkdir(parents=True)
    loops = []
    for file, anchor, source, y, metrics in rendered:
        target = out / file
        write_wav(target, y)
        loops.append({"file": file, "rpm": int(anchor["rpm"]), "layer": anchor["layer"],
                      "gain": 1.0, **metrics, "source_annotation": anchor,
                      "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                      "sha256": hashlib.sha256(target.read_bytes()).hexdigest()})
    manifest = {"profile": plan["profile"], "source": plan["source_url"], "license": plan["license"],
                "license_url": plan["license_url"], "author": plan["author"],
                "recording_session": plan["recording_session"], "rpm_basis": plan["rpm_basis"],
                "status": "audition_only_not_production",
                "changes": "Mono 48k PCM16; steady-window pitch alignment, phase-matched loop overlap, peak/RMS level matching.",
                "loops": sorted(loops, key=lambda a: (a["layer"], a["rpm"]))}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared {len(loops)} audition loops in {out}; listen and verify coverage before promotion.")


def self_test():
    # Test-only harmonic signal, not a shipping asset.
    hz = 100.0
    x = [0.2 * math.sin(2 * math.pi * hz * i / RATE) +
         0.05 * math.sin(4 * math.pi * hz * i / RATE) for i in range(RATE)]
    y, m = make_loop(x, {"start_s": 0, "end_s": 0.93, "source_rpm": 3000,
                        "rpm": 3000, "layer": "on"}, 2)
    assert abs(m["source_periodic_hz_estimate"] - 100) < 3
    assert m["seam_correlation"] > 0.95 and m["peak_dbfs"] <= -4
    assert m["seam_delta_pcm16"] < 200
    assert len(y) > RATE // 2
    try:
        make_loop([0.0] * RATE, {"start_s": 0, "end_s": 0.93, "source_rpm": 3000,
                                 "rpm": 3000, "layer": "on"}, 2)
    except ValueError:
        pass
    else:
        raise AssertionError("silent source accepted")
    print("Recorded-bank preparation self-test passed")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="mode", required=True)
    i = sub.add_parser("inspect")
    i.add_argument("recording", type=pathlib.Path)
    i.add_argument("--channel", default="mix", choices=["mix", "left", "right"])
    b = sub.add_parser("build")
    b.add_argument("plan", type=pathlib.Path)
    b.add_argument("output", type=pathlib.Path)
    sub.add_parser("self-test")
    a = p.parse_args()
    if a.mode == "inspect":
        inspect(a.recording, a.channel)
    elif a.mode == "build":
        build(a.plan, a.output)
    else:
        self_test()


if __name__ == "__main__":
    main()
