#!/usr/bin/env python3
"""Prepare real, minimally cut onboard audio for a local driving audition.

RPM and load inferred by deterministic signal analysis, not measured telemetry.
No source WAV, cut bank, or isolated audio is published by CI. No model training.
"""
import argparse
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile

import numpy as np
from scipy import signal, ndimage

import source_native_bank as bank
from professional_reference import SOURCES
from continuous_sweep_research import track, SR


def decode(source):
    x = np.frombuffer(subprocess.check_output([
        "ffmpeg", "-nostdin", "-v", "error", "-i", str(source),
        "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]), dtype="<f4")
    if len(x) < SR or not np.isfinite(x).all():
        raise ValueError("invalid original")
    return x


def tracks(x, cfg):
    # On a single exhaust outlet, the half-order can dominate. Evaluate both
    # hypotheses instead of taking the loudest FFT bin as measured RPM.
    for start in range(0, len(x), 40*SR):
        y = x[start:start+40*SR]
        if len(y) < 2*SR:
            continue
        half = cfg["order"]/2
        t, hz, conf, level = track(y, half, cfg["idle"], cfg["redline"])
        _, full, full_conf, _ = track(y, cfg["order"], cfg["idle"], cfg["redline"])
        # Prefer agreement; when the trackers select octave-separated
        # hypotheses, require actual energy at the half-order and its double.
        rpm = hz*60/half
        full_rpm = full*60/cfg["order"]
        agreement = abs(np.log(np.maximum(rpm, 1)/np.maximum(full_rpm, 1))) < .12
        yield start/SR, y, t, rpm, full_rpm, conf, full_conf, level, agreement


def windows(x, cfg):
    rows = []
    for offset, y, t, rpm, full_rpm, conf, fc, level, agreement in tracks(x, cfg):
        # Analysis uses a 10 ms trace. Cuts preserve original waveform and
        # natural RPM fluctuation; never pitch flatten or resynthesize it.
        slope = np.gradient(ndimage.gaussian_filter1d(np.log(rpm), 8), t)
        for center in range(60, len(t)-60, 15):
            for width in (45, 30):  # .90 or .60 seconds
                a, b = center-width, center+width
                if a < 0 or b >= len(t):
                    continue
                raw = y[round(t[a]*SR):round(t[b]*SR)]
                if len(raw) < SR*.45 or np.max(np.abs(raw)) >= .995:
                    continue
                rms = float(np.sqrt(np.mean(raw*raw)))
                if rms < .002:
                    continue
                local = rpm[a:b+1]
                mid = float(np.median(local))
                spread = float((np.percentile(local, 90)-np.percentile(local, 10))/mid)
                if not cfg["idle"]*.8 <= mid <= cfg["redline"]*1.06 or spread > .17:
                    continue
                # An idle/low load window needs no artificial oscillator; at
                # high RPM look for the full firing order as well as half.
                f, p = signal.welch(raw, SR, nperseg=min(4096,len(raw)), noverlap=2048)
                expected = mid*cfg["order"]/60
                def line(hz):
                    band = abs(f-hz) <= max(12, hz*.045)
                    bg = (abs(f-hz) <= max(55, hz*.16)) & ~band
                    return float(np.max(p[band])/max(float(np.median(p[bg])), 1e-15)) if band.any() and bg.any() else 0.
                full_line, half_line = line(expected), line(expected/2)
                agree = float(np.mean(agreement[a:b+1]))
                c = float(np.median(conf[a:b+1]))
                if c < 4 or full_line < 3 or (agree < .35 and half_line < 4):
                    continue
                # Two independent observations: directional RPM trend and
                # relative RMS at the same RPM. Load remains an estimate.
                trend = float(np.median(slope[a:b+1]))
                rows.append(dict(start_s=round(offset+float(t[a]),4),
                                 end_s=round(offset+float(t[b]),4),
                                 measured_rpm=round(mid,2), spread=round(spread,4),
                                 trend=round(trend,4), rms_dbfs=round(20*math.log10(rms),2),
                                 half_line=round(half_line,2), full_line=round(full_line,2),
                                 agreement=round(agree,3), confidence=round(c,2)))
    return rows


def choose(rows, cfg):
    idle, redline = cfg["idle"], cfg["redline"]
    # Enough adjacent anchors to avoid note-like large pitch jumps. Use the
    # actual estimated source RPM, not a nominal bin center.
    targets = [int(round(idle/100)*100)] + list(range(1800, int(redline)-450, 900))
    if redline-targets[-1] > 1100:
        targets.append(int(redline*.94))
    elif targets[-1] < redline*.91:
        targets.append(int(redline*.96))
    anchors, misses = [], []
    for layer in ("on", "off"):
        for target in targets:
            if layer == "off" and target < 1700:
                continue
            pool = [row for row in rows
                    if abs(row["measured_rpm"]-target) <= (350 if target < 1500 else 500)
                    and not any(min(row["end_s"], a["end_s"])-max(row["start_s"], a["start_s"]) > .1 for a in anchors)]
            if not pool:
                misses.append([layer,target,"no credible window"])
                continue
            levels = np.array([a["rms_dbfs"] for a in pool])
            median = float(np.median(levels))
            # Select plausible load/coast using direction and comparative
            # signal level. At steady RPM use the stronger/weaker recording.
            # This is an audition proxy, not proof of throttle position.
            sign = 1 if layer == "on" else -1
            def score(a):
                return (sign*np.clip(a["trend"]*30,-5,5)
                        + sign*np.clip((a["rms_dbfs"]-median)*.35,-4,4)
                        + 2*a["agreement"] + .1*a["confidence"]
                        + .5*math.log1p(min(a["full_line"],100))
                        - 13*a["spread"] - abs(a["measured_rpm"]-target)/180
                        + .5*(a["end_s"]-a["start_s"]))
            if target >= 1500:
                valid = [a for a in pool if sign*a["trend"] > .015 or
                         (abs(a["trend"]) < .10 and sign*(a["rms_dbfs"]-median) >= 1.0)]
                if not valid:
                    misses.append([layer,target,"load proxy ambiguous"])
                    continue
                pool = valid
            row = max(pool,key=score)
            rpm = int(round(row["measured_rpm"]/25)*25)
            anchors.append(dict(row, rpm=rpm, layer=layer,
                                rpm_basis="Half-order harmonic tracker; full-order spectral corroboration; estimated, not tachometer.",
                                load_basis=("Idle/low RPM reference; actual throttle unknown" if target < 1500 else
                                            "Inferred from RPM direction and relative RMS; actual throttle unknown.")))
    return anchors, misses


def install(profile, source_dir, root, report_dir):
    source = bank.fetch(profile, source_dir)
    cfg = SOURCES[profile]
    x = decode(source)
    rows = windows(x, cfg)
    anchors, misses = choose(rows,cfg)
    plan = dict(profile=profile, rpm_basis="Deterministic half/full firing-order spectral analysis; load labels are provisional auditory proxies, not measured throttle.",
                anchors=anchors)
    report_dir.mkdir(parents=True, exist_ok=True)
    plan_path = report_dir/(profile+"_plan.json")
    plan_path.write_text(json.dumps(plan,indent=2)+"\n")
    report = dict(profile=profile, source_sha256=bank.digest(source),
                  source_duration_s=len(x)/SR, candidate_count=len(rows),
                  anchors=[{k:a[k] for k in ("layer","rpm","start_s","end_s","spread","trend","rms_dbfs","agreement")} for a in anchors], misses=misses)
    (report_dir/(profile+"_selection.json")).write_text(json.dumps(report,indent=2)+"\n")
    print("NATIVE_SELECTION",json.dumps(report),flush=True)
    # Never install a partial or silently proxy-filled bank.
    bank.validate(plan,cfg["idle"],cfg["redline"])
    dest = bank.build(plan_path,source,root)
    print("NATIVE_INSTALLED",profile,len(anchors),dest,flush=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-dir",type=Path,required=True)
    p.add_argument("--bank-dir",type=Path,required=True)
    p.add_argument("--report-dir",type=Path,required=True)
    p.add_argument("--profile",choices=sorted(SOURCES),action="append")
    p.add_argument("--accept-license",action="store_true",
                   help="Confirm you have read the Sonniss GDC license; source assets stay local")
    a = p.parse_args()
    if not a.accept_license:
        p.error("Read https://sonniss.com/gdc-bundle-license/ first; pass --accept-license to install")
    for path in (a.source_dir,a.bank_dir,a.report_dir):
        bank.external(path)
    failures = []
    for profile in a.profile or SOURCES:
        try:
            install(profile,a.source_dir,a.bank_dir,a.report_dir)
        except Exception as exc:
            print("NATIVE_FAILED",profile,repr(exc),flush=True)
            failures.append(profile)
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
