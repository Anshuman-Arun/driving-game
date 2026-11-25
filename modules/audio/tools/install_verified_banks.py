#!/usr/bin/env python3
"""Install the exact professional samples that passed Godot live-drive QA.

Requires Python 3.11+ and FFmpeg on PATH. No numerical analysis dependency.
Licensed originals and cuts stay local. See docs/SOURCE_NATIVE_AUDIO.md.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import sys

import source_native_bank as bank

PLANS = Path(__file__).resolve().parent / "professional_plans"
PROJECT_NAME = "Aster Valley \u2014 Free Roam"


def default_dirs():
    if sys.platform == "win32":
        cache = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local"))
        data = Path(os.environ.get("APPDATA", Path.home() / "AppData/Roaming")) / "Godot"
    elif sys.platform == "darwin":
        cache = Path.home() / "Library/Caches"
        data = Path.home() / "Library/Application Support/Godot"
    else:
        cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
        data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "godot"
    return cache / "AsterAudioSources", data / "app_userdata" / PROJECT_NAME / "native_engine_banks"


def load_plan(profile):
    path = PLANS / (profile + ".json")
    plan = json.loads(path.read_text(encoding="utf-8"))
    expected, idle, redline = bank.SOURCES[profile]
    if plan["profile"] != profile or plan["source_sha256"] != expected:
        raise ValueError("Pinned plan identity mismatch")
    bank.validate(plan, idle, redline)
    return path, plan


def check_installed(dest, plan):
    data = json.loads((dest / "manifest.json").read_text(encoding="utf-8"))
    if data.get("profile") != plan["profile"] or data.get("status") != bank.STATUS or data.get("source_sha256") != plan["source_sha256"]:
        raise ValueError("Existing bank provenance differs")
    expected = {(a["layer"], a["rpm"]): a for a in plan["anchors"]}
    rows = data["loops"]
    if len(rows) != len(expected):
        raise ValueError("Existing bank coverage differs")
    seen = set()
    for row in rows:
        key = row["layer"], row["rpm"]
        a = expected[key]
        filename = "%s_%d.wav" % key
        if key in seen or row["file"] != filename or row["start_s"] != a["start_s"] or row["end_s"] != a["end_s"]:
            raise ValueError("Existing bank window differs")
        seen.add(key)
        if not 0 < float(row["gain"]) <= 1 or bank.digest(dest / filename) != row["sha256"]:
            raise ValueError("Existing bank file invalid")


def install(profile, source_dir, root):
    plan_path, plan = load_plan(profile)
    dest = root / profile
    if dest.exists():
        try:
            check_installed(dest, plan)
        except Exception as exc:
            raise ValueError(f"Move existing bank aside before installing: {dest}") from exc
        print("VERIFIED_BANK_ALREADY_INSTALLED", profile, dest, flush=True)
        return dest
    source = bank.fetch(profile, source_dir)
    result = bank.build(plan_path, source, root)
    check_installed(result, plan)
    print("VERIFIED_BANK_INSTALLED", profile, len(plan["anchors"]), result, flush=True)
    return result


def main():
    sources, root = default_dirs()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, default=sources)
    parser.add_argument("--bank-dir", type=Path, default=root)
    parser.add_argument("--profile", action="append", choices=sorted(bank.SOURCES))
    parser.add_argument("--accept-license", action="store_true")
    args = parser.parse_args()
    if not args.accept_license:
        parser.error("Read https://sonniss.com/gdc-bundle-license/ first; use --accept-license to install.")
    if not shutil.which("ffmpeg"):
        parser.error("FFmpeg must be on PATH.")
    source_dir, root = bank.external(args.source_dir), bank.external(args.bank_dir)
    failures = []
    for profile in args.profile or bank.SOURCES:
        try:
            install(profile, source_dir, root)
        except Exception as exc:
            print("VERIFIED_BANK_FAILED", profile, repr(exc), flush=True)
            failures.append(profile)
    if not failures:
        print("Professional source-native banks ready. Launch game normally; ASTER_NATIVE_AUDIO=0 selects the legacy A/B baseline.")
    return int(bool(failures))


if __name__ == "__main__":
    sys.exit(main())
