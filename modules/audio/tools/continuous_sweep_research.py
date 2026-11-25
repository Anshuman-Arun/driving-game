#!/usr/bin/env python3
"""Audition-only continuous engine sweep inspection and pitch-synchronous preview.

Never replaces a production bank. Requires numpy, scipy and ffmpeg.
The firing-frequency track is an estimate, not measured tachometer telemetry.
A human must confirm the vehicle, acceleration/coast direction and microphone.
"""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import urllib.request

import numpy as np
from scipy import signal, ndimage
from scipy.io import wavfile

SR = 24000
SOURCES = {
    "aventador_svj": {
        "order": 6, "idle": 900, "redline": 8700,
        "author": "ePic eXhaust",
        "url": "https://upload.wikimedia.org/wikipedia/commons/5/5c/Lamborghini_Aventador_SVJ_-_engine_and_exhaust_sound_%28YouTube_zqv9zLtHsUM%29.opus",
        "page": "https://commons.wikimedia.org/wiki/File:Lamborghini_Aventador_SVJ_-_engine_and_exhaust_sound_(YouTube_zqv9zLtHsUM).opus",
    },
    "mclaren_senna": {
        "order": 4, "idle": 980, "redline": 8000,
        "author": "Hungarian Supercar Spotters",
        "url": "https://upload.wikimedia.org/wikipedia/commons/2/23/McLaren_765LT_-_engine_and_exhaust_sound_%28YouTube_5oSRv66QFW0%29.opus",
        "page": "https://commons.wikimedia.org/wiki/File:McLaren_765LT_-_engine_and_exhaust_sound_(YouTube_5oSRv66QFW0).opus",
    },
}


def decode(path):
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    data = subprocess.check_output([ffmpeg, "-v", "error", "-i", str(path), "-t", "120",
                                    "-ar", str(SR), "-ac", "1", "-f", "f32le", "-"])
    x = np.frombuffer(data, dtype="<f4").copy()
    if len(x) < SR or not np.isfinite(x).all():
        raise ValueError("short or invalid recording")
    return signal.sosfilt(signal.butter(2, 35, fs=SR, btype="highpass", output="sos"), x).astype(np.float32)


def track(x, order, idle, redline):
    # Track several harmonics jointly: the loudest FFT bin alone often
    # switches octave/order and makes an engine sound like separate notes.
    f, t, z = signal.stft(x, SR, nperseg=2048, noverlap=1808, nfft=8192,
                          boundary=None, padded=False)
    magnitude = np.abs(z)
    db = 20 * np.log10(np.maximum(magnitude, 1e-7))
    contrast = np.maximum(0, db - ndimage.uniform_filter1d(db, size=31, axis=0))
    grid = np.geomspace(idle * order / 60 * 0.75, redline * order / 60 * 1.05, 180)
    salience = np.zeros((len(grid), len(t)), dtype=np.float32)
    for h, weight in [(1, 1.0), (2, 0.72), (3, 0.54), (4, 0.42), (5, 0.30)]:
        bins = np.clip(np.rint(grid * h / f[1]).astype(int), 1, len(f) - 2)
        salience += weight * np.maximum.reduce([contrast[bins - 1], contrast[bins], contrast[bins + 1]])
    # Penalize isolated single-harmonic picks and implausible frame jumps.
    salience /= 2.98
    states = len(grid)
    back = np.zeros((len(t), states), dtype=np.int16)
    value = salience[:, 0].copy()
    indices = np.arange(states)
    for i in range(1, len(t)):
        best = value - 18.0
        parent = np.full(states, int(np.argmax(value)), dtype=np.int16)
        best[:] = float(value.max()) - 18.0
        for shift in range(-7, 8):
            previous = np.clip(indices + shift, 0, states - 1)
            candidate = value[previous] - abs(shift) * 0.65
            use = candidate > best
            best[use] = candidate[use]
            parent[use] = previous[use]
        value = best + salience[:, i]
        value -= value.max()
        back[i] = parent
    path = np.empty(len(t), dtype=int)
    path[-1] = int(np.argmax(value))
    for i in range(len(t) - 1, 0, -1):
        path[i - 1] = back[i, path[i]]
    hz = ndimage.median_filter(grid[path], size=7)
    confidence = salience[path, np.arange(len(t))]
    level = np.sqrt(np.mean(magnitude**2, axis=0))
    return t, hz, confidence, level


def candidates(t, hz, confidence, level, order):
    # Find monotone, high-energy intervals without shifts. Do not stitch
    # different takes or cars together and call it a continuous sweep.
    smooth = ndimage.gaussian_filter1d(np.log(hz), 4)
    slope = np.gradient(smooth, t)
    active = (confidence > 4.0) & (level > np.max(level) * 0.025)
    results = []
    for direction in ("on", "off"):
        sign = 1 if direction == "on" else -1
        good = active & (sign * slope > 0.025) & (np.abs(slope) < 3.0)
        good = ndimage.binary_closing(good, structure=np.ones(13))
        labels, n = ndimage.label(good)
        for label in range(1, n + 1):
            ids = np.flatnonzero(labels == label)
            a, b = int(ids[0]), int(ids[-1])
            duration = t[b] - t[a]
            if duration < 0.65 or duration > 25:
                continue
            span = sign * (smooth[b] - smooth[a])
            if span < np.log(1.7):
                continue
            results.append({"layer": direction, "start_s": float(t[a]),
                            "end_s": float(t[b]), "start_rpm": float(hz[a]*60/order),
                            "end_rpm": float(hz[b]*60/order),
                            "span_ratio": float(np.exp(span)),
                            "median_confidence": float(np.median(confidence[ids])),
                            "score": float(span * np.median(confidence[ids])),
                            "a": a, "b": b})
    return sorted(results, key=lambda x: x["score"], reverse=True)


def preview(x, t, hz, item, seconds=6.0):
    # Time-domain pitch-synchronous overlap-add audition. Use whole source
    # waveform grains from ONE continuous take, retaining transient texture.
    # Snap centers to a local fundamental peak and align overlap phase.
    a, b = item["a"], item["b"]
    times, freqs = t[a:b+1], hz[a:b+1]
    ascending = item["layer"] == "on"
    if not ascending:
        times, freqs = times[::-1], freqs[::-1]
    freqs = np.maximum.accumulate(freqs)
    out = np.zeros(round(SR * seconds), dtype=np.float64)
    weights = np.zeros_like(out)
    cursor = 0.0
    while cursor < len(out):
        progress = cursor / len(out)
        if not ascending:
            progress = 1.0 - progress
        target = float(np.exp(np.log(freqs[0])*(1-progress) + np.log(freqs[-1])*progress))
        src = float(np.interp(target, freqs, times))*SR
        period = SR / target
        radius = max(8, round(period * 1.5))
        center = round(src)
        search = max(2, round(period * 0.5))
        if center-radius-search < 0 or center+radius+search >= len(x):
            cursor += period
            continue
        # Reference phase uses band-limited local firing frequency rather
        # than high-frequency transient peaks.
        segment = x[center-radius-search:center+radius+search+1]
        lo, hi = max(20, target*0.7), min(SR*0.45, target*1.3)
        tone = signal.sosfiltfilt(signal.butter(2,[lo,hi],fs=SR,btype="bandpass",output="sos"), segment)
        shift = int(np.argmax(tone[radius:radius+2*search+1]))-search
        grain = x[center+shift-radius:center+shift+radius+1]
        win = np.hanning(len(grain))
        c = round(cursor)
        left, right = max(0,c-radius), min(len(out),c+radius+1)
        g0 = left-(c-radius)
        g1 = g0+right-left
        out[left:right] += grain[g0:g1]*win[g0:g1]
        weights[left:right] += win[g0:g1]
        cursor += period
    out /= np.maximum(weights, 1e-5)
    return out


def save(path, x):
    peak = max(1e-8, np.max(np.abs(x)))
    gain = min(1.0, 0.80/peak)
    wavfile.write(path, SR, np.round(np.clip(x*gain, -1, 1)*32767).astype(np.int16))


def inspect(path, cfg, output):
    x = decode(path)
    t, hz, confidence, level = track(x, cfg["order"], cfg["idle"], cfg["redline"])
    rows = candidates(t, hz, confidence, level, cfg["order"])
    result = {"source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
              "duration_s": len(x)/SR, "rpm_basis": "harmonic estimate, not tachometer",
              "status": "audition_only", "source": cfg, "candidates": rows[:12]}
    for layer in ("on", "off"):
        chosen = [row for row in rows if row["layer"] == layer][:3]
        for i, row in enumerate(chosen):
            clip = x[round(row["start_s"]*SR):round(row["end_s"]*SR)]
            save(output / f"{layer}_{i}_original.wav", clip)
            save(output / f"{layer}_{i}_granular_preview.wav", preview(x,t,hz,row))
    np.savetxt(output / "estimated_rpm.csv", np.column_stack((t,hz*60/cfg["order"],confidence)),
               delimiter=",", header="seconds,estimated_rpm,harmonic_contrast", comments="")
    (output / "report.json").write_text(json.dumps(result, indent=2)+"\n")
    print(output.name, "candidate sweeps:", [(r["layer"], round(r["start_s"],2),
          round(r["end_s"],2),round(r["start_rpm"]),round(r["end_rpm"])) for r in rows[:6]])


def self_test():
    # Algorithm fixture only, not a shipping sound.
    t = np.arange(SR*5)/SR
    f = 100+80*t
    phase = 2*np.pi*np.cumsum(f)/SR
    x = .15*np.sin(phase)+.08*np.sin(phase*2)+.04*np.sin(phase*3)
    times,hz,c,l = track(x,4,1400,7800)
    expected = 100+80*times
    err = np.median(abs(hz-expected)/expected)
    assert err < 0.05, f"pitch track error {err:.3f}"
    rows = candidates(times,hz,c,l,4)
    assert any(r["layer"]=="on" for r in rows), "no sweep"
    p = preview(x,times,hz,next(r for r in rows if r["layer"]=="on"),seconds=1.0)
    assert np.isfinite(p).all() and np.sqrt(np.mean(p*p))>0.01
    print(f"Continuous sweep fixture PASS: median frequency error {err:.2%}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--local", type=pathlib.Path, help="Analyze a user-supplied recording without network access")
    parser.add_argument("--profile", choices=sorted(SOURCES), default="aventador_svj")
    args = parser.parse_args()
    self_test()
    if args.self_test:
        return
    if args.local:
        if not args.output or args.download:
            parser.error("provide --local FILE --profile ID --output DIR, without --download")
        args.output.mkdir(parents=True, exist_ok=True)
        cfg = dict(SOURCES[args.profile], url=str(args.local), source_type="local candidate, identity not confirmed")
        inspect(args.local, cfg, args.output)
        return
    if not args.output or not args.download:
        parser.error("provide --output and explicit --download or --local")
    args.output.mkdir(parents=True,exist_ok=True)
    successful = 0
    for profile,cfg in SOURCES.items():
        output = args.output/profile
        output.mkdir(exist_ok=True)
        path = output/"source.opus"
        try:
            request = urllib.request.Request(cfg["url"],headers={"User-Agent":"AsterValleyAudioResearch/1.0 (private audio audition)"})
            with urllib.request.urlopen(request,timeout=60) as response:
                raw=response.read(24*1024*1024+1)
            if len(raw)>24*1024*1024 or not raw.startswith(b"OggS"):
                raise ValueError("source is not a bounded Ogg file")
            path.write_bytes(raw)
            inspect(path,cfg,output)
            successful += 1
        except Exception as exc:
            (output/"error.txt").write_text(str(exc)+"\n")
            print(profile,"source unavailable or analysis failed:",exc)
    if successful != len(SOURCES):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
