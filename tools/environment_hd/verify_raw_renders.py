#!/usr/bin/env python3
"""Validate byte-level raw PNG evidence; never alters captures or claims art quality."""
import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHOW = ROOT / "showcase" / "environment_hd"
SHOTS = json.loads((SHOW / "data" / "camera_shots_v2.json").read_text())["shots"]

def png_info(path):
    blob = path.read_bytes()
    if blob[:8] != b"\x89PNG\r\n\x1a\n" or blob[12:16] != b"IHDR":
        raise ValueError(f"Invalid PNG image: {path}")
    width, height = struct.unpack(">II", blob[16:24])
    if (width, height) != (1600, 900):
        raise ValueError(f"Unexpected {width}x{height} image: {path}")
    if len(blob) < 120:
        raise ValueError(f"Truncated PNG image: {path}")
    return {"file": str(path.relative_to(ROOT)), "bytes": len(blob),
            "width": width, "height": height,
            "sha256": hashlib.sha256(blob).hexdigest()}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("renderer", choices=("blender", "godot"))
    parser.add_argument("--write-manifest", action="store_true")
    args = parser.parse_args()
    folder = SHOW / ("renders" if args.renderer == "blender" else "renders_godot")
    frames = []
    for shot in SHOTS:
        fn = folder / f"view_{shot['id']}.png"
        if not fn.exists():
            raise SystemExit(f"RENDER BLOCKED: Missing genuine frame {fn}")
        frames.append({"shot": shot["id"], "camera": shot["camera"],
                       "target": shot["target"], "frame": png_info(fn)})
    try:
        revision = subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"],
            text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        revision = "unknown"
    data = {"renderer": args.renderer,
            "claim": "PNG file/hash validation only, not proof of visual acceptance",
            "git_head": revision,
            "shots": frames}
    if args.write_manifest:
        (folder / "capture_manifest.json").write_text(json.dumps(data, indent=2) + "\n")
    print(json.dumps(data, indent=2))

if __name__ == "__main__":
    main()
