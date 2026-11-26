"""Bounded verification. Data gates run without Godot or network access."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
ERROR = re.compile(r"SCRIPT ERROR|Parse Error|Shader Error|Failed to load script|(?m:^\s*ERROR:)", re.I)


def run(command, timeout, marker=None, engine=False):
    print("+", " ".join(command), flush=True)
    try:
        result = subprocess.run(command, cwd=ROOT, timeout=timeout, text=True,
                                encoding="utf-8", errors="replace", stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, check=False)
    except subprocess.TimeoutExpired as exc:
        partial = exc.stdout or ""
        if isinstance(partial, bytes):
            partial = partial.decode("utf-8", errors="replace")
        print(partial, end="", flush=True)
        raise RuntimeError(f"timed out after {timeout}s: {command}") from exc
    print(result.stdout, end="", flush=True)
    if result.returncode != 0 or (engine and ERROR.search(result.stdout)):
        raise RuntimeError(f"failed command ({result.returncode}): {command}")
    if marker and not any(re.fullmatch(marker, line.strip()) for line in result.stdout.splitlines()):
        raise RuntimeError(f"missing completion marker {marker!r}: {command}")
    return result.stdout


def validate_report(output):
    report = json.loads(output)
    names = {"fern", "reed", "sapling", "shrub", "wildflower"}
    if not isinstance(report, dict):
        raise RuntimeError("incomplete Node validation report")
    rejected = report.get("rejected")
    rows = report.get("report")
    if (report.get("negative_fixtures") != 30 or not isinstance(rejected, list)
            or not all(isinstance(x, str) and x for x in rejected) or len(set(rejected)) != 30
            or report.get("sha256_vectors") != 2 or report.get("determinism") is not True
            or report.get("lod_shared_scaffold") is not True
            or not isinstance(rows, list) or len(rows) != 5
            or not all(isinstance(x, dict) and x.get("species") in names
                       and type(x.get("lod0")) is int and type(x.get("lod1")) is int
                       and type(x.get("bytes")) is int and 0 < x["lod1"] <= x["lod0"] * 0.65
                       and 0 < x["bytes"] <= 1000000 for x in rows)
            or {x["species"] for x in rows} != names):
        raise RuntimeError("incomplete Node validation report")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--node", default="node")
    parser.add_argument("--data-only", action="store_true", help="run CPU checks; skip Godot explicitly")
    parser.add_argument("--existing", action="store_true", help="also check existing LFS scan assets")
    parser.add_argument("--regressions", action="store_true", help="also run baseline world regressions")
    args = parser.parse_args()
    if args.data_only and args.regressions:
        parser.error("--regressions requires Godot; omit --data-only")
    run([sys.executable, "tools/environment_assets/test_verify_headless.py"], 30)
    run([args.node, "tools/environment_assets/test_staging.mjs"], 60, r"Staging filesystem checks passed: [1-9]\d*")
    validate_report(run([args.node, "tools/environment_assets/generate.mjs", "--verify"], 120))
    run([sys.executable, "tools/environment_assets/test_audit_existing.py"], 60)
    run([sys.executable, "tools/environment_assets/test_projection.py"], 120,
        r"Vegetation CPU silhouette checks passed: 120/120")
    if args.existing:
        run([sys.executable, "tools/environment_assets/audit_existing.py"], 60)
    print("Agent B requested CPU/data gates passed", flush=True)
    if args.data_only:
        print("Godot gates NOT RUN (--data-only)")
        return
    version = run([args.godot, "--headless", "--version"], 30, engine=True)
    if not re.search(r"(?m)^4\.7\.2\.stable(?:[.\s]|$)", version):
        raise RuntimeError("requires Godot 4.7.2 stable")
    common = [args.godot, "--headless", "--path", "."]
    run(common + ["--editor", "--import"], 900, engine=True)
    run(common + ["--script", "res://tools/environment_assets/test_import.gd"], 180,
        r"Vegetation import: 10/10 scenes; failures=0", engine=True)
    if args.existing:
        run(common + ["--script", "res://tools/environment_assets/test_existing.gd"], 180,
            r"Premium foliage audit failures=0", engine=True)
    if args.regressions:
        for name in ["map_width_check", "roadworks_check", "world_visual_qa", "garage_world", "vehicle_world"]:
            script = ROOT / "tests" / "integration" / (name + ".gd")
            if name == "map_width_check" and not script.is_file():
                print("Skipping map_width_check: absent on checkout")
                continue
            run(common + ["--fixed-fps", "60", "--script", "res://tests/integration/" + name + ".gd"],
                420, engine=True)
    print("Agent B requested headless gates passed")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, KeyError, TypeError) as exc:
        print(f"Agent B gate FAILED: {exc}", file=sys.stderr)
        sys.exit(1)
