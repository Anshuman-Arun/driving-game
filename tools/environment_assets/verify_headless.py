"""Strict, bounded local gate. Run from any directory after obtaining Godot 4.7.2."""
import argparse
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
ERROR = re.compile(r"SCRIPT ERROR|Parse Error|Shader Error|Failed to load script|(?m:^\s*ERROR:)", re.I)


def run(command, timeout, marker=None, engine=False):
    print("+", " ".join(command), flush=True)
    result = subprocess.run(command, cwd=ROOT, timeout=timeout, text=True,
                            encoding="utf-8", errors="replace", stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, check=False)
    print(result.stdout, end="", flush=True)
    if result.returncode or (engine and ERROR.search(result.stdout)):
        raise RuntimeError(f"failed command ({result.returncode}): {command}")
    if marker and marker not in result.stdout:
        raise RuntimeError(f"missing completion marker {marker!r}: {command}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--node", default="node")
    parser.add_argument("--existing", action="store_true", help="also check existing LFS scan assets")
    parser.add_argument("--regressions", action="store_true", help="also run baseline world regressions")
    args = parser.parse_args()
    version = run([args.godot, "--headless", "--version"], 30, engine=True)
    if not re.search(r"(?m)^4\.7\.2\.stable(?:[.\s]|$)", version):
        raise RuntimeError("requires Godot 4.7.2 stable")
    run([args.node, "tools/environment_assets/test_staging.mjs"], 60, "Staging filesystem checks passed:")
    run([args.node, "tools/environment_assets/generate.mjs", "--verify"], 120, '"negative_fixtures": 24')
    run([sys.executable, "tools/environment_assets/test_audit_existing.py"], 60)
    if args.existing:
        run([sys.executable, "tools/environment_assets/audit_existing.py"], 60)
    common = [args.godot, "--headless", "--path", "."]
    run(common + ["--editor", "--import"], 900, engine=True)
    run(common + ["--script", "res://tools/environment_assets/test_import.gd"], 180,
        "Vegetation import: 10/10 scenes; failures=0", engine=True)
    if args.existing:
        run(common + ["--script", "res://tools/environment_assets/test_existing.gd"], 180,
            "Premium foliage audit failures=0", engine=True)
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
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(f"Agent B gate FAILED: {exc}", file=sys.stderr)
        sys.exit(1)
