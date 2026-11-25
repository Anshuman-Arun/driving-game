#!/usr/bin/env python3
"""Local-only, source-native professional engine banks (no pitch flattening).
Use fetch to acquire original licensed takes, then build from reviewed windows.
Never commits or uploads licensed source audio or derived WAV files.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import tempfile
import wave
import array
import sys

RATE = 48000
STATUS = "local_source_native_audition"
SOURCES = {
    "aventador_svj": ("92986d10dd09f45cda5b57cca3805387e25c7235154741234f1aed60a5355a54", 900, 8700),
    "mclaren_senna": ("06b730e76a0987cf782bb47f472b3f87515ef7c00556b83cb3ef418a23fb24d2", 980, 8000),
}
LICENSE = "https://sonniss.com/gdc-bundle-license/"


def digest(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def external(path):
    path = path.resolve()
    repo = Path(__file__).resolve().parents[3]
    if path == repo or repo in path.parents:
        raise ValueError("Licensed audio must stay outside the repository")
    return path


def fetch(profile, folder):
    from professional_reference import SOURCES as configs, acquire
    folder = external(folder)
    folder.mkdir(parents=True, exist_ok=True)
    dest = folder / (profile + ".wav")
    if dest.exists():
        if digest(dest) != SOURCES[profile][0]:
            raise ValueError("Existing original has wrong SHA-256")
        return dest
    with tempfile.TemporaryDirectory(dir=folder) as tmp:
        source = Path(tmp) / "original.wav"
        acquire(configs[profile], source)
        if digest(source) != SOURCES[profile][0]:
            raise ValueError("Original SHA-256 mismatch")
        source.rename(dest)
    return dest


def validate(plan, idle, redline):
    rows = plan["anchors"]
    if not isinstance(rows, list) or not 12 <= len(rows) <= 40:
        raise ValueError("Need 12–40 distinct annotated windows")
    if not str(plan.get("rpm_basis", "")).strip():
        raise ValueError("Explain the RPM measurement or estimation method")
    groups = {"on": [], "off": []}
    seen = set()
    for a in rows:
        rpm, layer = a["rpm"], a["layer"]
        start, end = float(a["start_s"]), float(a["end_s"])
        if (type(rpm) is not int or not 600 <= rpm <= redline * 1.08
                or layer not in groups or (layer, rpm) in seen):
            raise ValueError("Invalid or duplicate RPM anchor")
        if not (math.isfinite(start) and math.isfinite(end)
                and 0 <= start and 0.45 <= end-start <= 4.0):
            raise ValueError("Each raw window must be 0.45–4 seconds")
        if not str(a.get("load_basis", "")).strip():
            raise ValueError("Explain actual load; RPM slope alone is insufficient")
        if not str(a.get("rpm_basis", "")).strip():
            raise ValueError("Explain per-window RPM measurement or estimate")
        seen.add((layer, rpm))
        groups[layer].append(rpm)
    for layer, values in groups.items():
        values.sort()
        low = idle * 1.3 if layer == "on" else 2200
        if (len(values) < 6 or values[0] > low or values[-1] < redline * 0.9
                or any(b-a > 1500 for a, b in zip(values, values[1:]))):
            raise ValueError("Incomplete " + layer + " coverage; no proxy fill")


def extract(source, target, start, end):
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("Install FFmpeg and put it on PATH")
    # No EQ, compressor, pitch correction, denoising, looping or per-window gain.
    subprocess.run([ffmpeg, "-nostdin", "-v", "error", "-ss", str(start),
                    "-i", str(source), "-t", str(end-start), "-map", "0:a:0",
                    "-ac", "1", "-ar", str(RATE), "-c:a", "pcm_s16le",
                    "-n", str(target)], check=True)
    with wave.open(str(target), "rb") as f:
        if (f.getnchannels(), f.getsampwidth(), f.getframerate()) != (1, 2, RATE):
            raise ValueError("Unexpected PCM format")
        n = f.getnframes()
        pcm = array.array("h", f.readframes(n))
    if sys.byteorder != "little":
        pcm.byteswap()
    if abs(n / RATE - (end-start)) > 0.025:
        raise ValueError("Truncated source window")
    peak = max(abs(v) for v in pcm)
    rms = math.sqrt(sum(v*v for v in pcm) / n)
    if peak >= 32767 or rms < 16:
        raise ValueError("Clipped or silent source; choose another window")
    return {"duration_s": n/RATE, "peak_dbfs": 20*math.log10(peak/32768),
            "rms_dbfs": 20*math.log10(rms/32768), "sha256": digest(target)}


def build(plan_path, source, root):
    from professional_reference import SOURCES as configs
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    profile = plan["profile"]
    expected, idle, redline = SOURCES[profile]
    validate(plan, idle, redline)
    if digest(source) != expected:
        raise ValueError("Source must match the verified original recording")
    root = external(root)
    root.mkdir(parents=True, exist_ok=True)
    dest = root / profile
    if dest.exists():
        raise ValueError("Bank already exists; move it aside before rebuilding")
    # Atomic publication: no partial manifest can be selected by the game.
    with tempfile.TemporaryDirectory(dir=root) as tmp:
        stage = Path(tmp) / "bank"
        stage.mkdir()
        loops = []
        for row in sorted(plan["anchors"], key=lambda a: (a["layer"], a["rpm"])):
            name = "%s_%d.wav" % (row["layer"], row["rpm"])
            metrics = extract(source, stage/name, float(row["start_s"]), float(row["end_s"]))
            loops.append(dict(row, file=name, gain=1.0, **metrics))
        # One shared downward trim for headroom, preserving relative load/RPM
        # dynamics. The WAV bytes remain unchanged.
        peak = max(x["peak_dbfs"] for x in loops)
        gain = min(1.0, 10**((-6.0-peak)/20))
        for row in loops:
            row["gain"] = gain
        manifest = dict(profile=profile, status=STATUS, source=configs[profile]["url"],
                        source_character=configs[profile]["car"], author="Pole Position Production",
                        source_file=configs[profile]["file"], source_sha256=expected,
                        license="Sonniss GDC EULA v2.0", license_url=LICENSE,
                        rpm_basis=plan["rpm_basis"], loops=loops,
                        changes="Time cuts, mono 48 kHz PCM16 only; common playback trim")
        (stage/"manifest.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
        stage.rename(dest)
    print("Local audition bank installed:", dest)
    return dest


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="command", required=True)
    f = sub.add_parser("fetch")
    f.add_argument("profile", choices=SOURCES)
    f.add_argument("folder", type=Path)
    b = sub.add_parser("build")
    b.add_argument("plan", type=Path)
    b.add_argument("source", type=Path)
    b.add_argument("root", type=Path)
    a = p.parse_args()
    if a.command == "fetch":
        print(fetch(a.profile, a.folder))
    else:
        build(a.plan, a.source, a.root)


if __name__ == "__main__":
    main()
