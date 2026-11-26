"""Run Agent C acceptance with retained logs; no network or workflow edits.

Run from a complete checkout after installing requirements.txt and fetching LFS.
--fixture-only is an offline smoke check, not canonical acceptance.
--data-only verifies the canonical package, but omits Godot runtime gates.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import numpy as np
import scipy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MASKS = HERE/"masks"
ERRORS = re.compile(r"SCRIPT ERROR|Parse Error|Failed to load script|Shader compilation failed|shader error|(?:^|\s)FAIL(?:\s|:)", re.I | re.M)
ROOT_SUITES = (
    "tests/integration/map_width_check.gd",
    "tests/integration/roadworks_check.gd",
    "tests/integration/world_visual_qa.gd",
    "tests/integration/garage_world.gd",
    "tests/integration/vehicle_world.gd",
)


def run(logdir, name, args, seconds=600, inspect_errors=False, cwd=ROOT, expected=()):
    path = logdir/(name+".log")
    print(f"RUN {name}: {path}", flush=True)
    try:
        with path.open("x", encoding="utf-8") as f:
            result = subprocess.run(args, cwd=cwd, stdout=f, stderr=subprocess.STDOUT,
                                    timeout=seconds, check=False)
        output = path.read_text(encoding="utf-8", errors="replace")
        ok = (result.returncode == 0 and not (inspect_errors and ERRORS.search(output))
              and all(marker in output for marker in expected))
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"ERROR {name}: {error}", file=sys.stderr)
        ok = False
    print(f"{'PASS' if ok else 'FAIL'} {name}", flush=True)
    return ok


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--fixture-only", action="store_true")
    mode.add_argument("--data-only", action="store_true")
    parser.add_argument("--godot", default="godot", help="Path to checksum-verified Godot 4.7.2")
    parser.add_argument("--seed", type=int, default=20261121)
    args = parser.parse_args()
    logdir = Path(tempfile.mkdtemp(prefix="aster-biome-qa-"))
    print(f"Logs: {logdir}")
    print(f"Python {sys.version.split()[0]}, NumPy {np.__version__}, SciPy {scipy.__version__}")
    tests = [sys.executable,"-m","unittest","discover","-s",str(HERE),"-p","test_biomes.py","-v"]
    if args.fixture_only:
        # Explicit classes avoid discovery of canonical tests without the data.
        ok = run(logdir,"fixture",[sys.executable,"-m","unittest","test_biomes.UnitTests","test_biomes.FixtureTests","-v"],cwd=HERE)
        print("Fixture-only mode; canonical and Godot gates NOT RUN")
        return 0 if ok else 1
    if (np.__version__,scipy.__version__) != ("2.2.6","1.15.3"):
        print("Install requirements.txt before canonical acceptance",file=sys.stderr)
        return 1
    if not run(logdir,"canonical-tests",tests):
        return 1
    if not run(logdir,"bake",[sys.executable,str(HERE/"bake_biomes.py"),"--project",str(ROOT),"--output",str(MASKS),"--seed",str(args.seed)]):
        return 1
    if not run(logdir,"package",[sys.executable,str(HERE/"verify_package.py"),"--project",str(ROOT),"--mask-dir",str(MASKS)]):
        return 1
    if not run(logdir,"world-data",["node","modules/world_runtime/tests/verify_world_data.mjs","data/world"]):
        return 1
    if args.data_only:
        print("Canonical data accepted; Godot gates NOT RUN")
        return 0
    try:
        version = subprocess.check_output([args.godot,"--headless","--version"],cwd=ROOT,text=True,timeout=20).strip()
    except (OSError,subprocess.SubprocessError) as error:
        print(f"Godot unavailable: {error}",file=sys.stderr)
        return 1
    if not version.startswith("4.7.2.stable"):
        print(f"Wrong Godot version: {version}",file=sys.stderr)
        return 1
    if not run(logdir,"godot-import",[args.godot,"--headless","--path",".","--editor","--import"],600,True):
        return 1
    suites = [str((HERE/"test_surface.gd").relative_to(ROOT)).replace(os.sep,"/"), *ROOT_SUITES]
    ok = True
    for script in suites:
        if not (ROOT/script).is_file():
            if script==ROOT_SUITES[0]:
                print(f"NOT APPLICABLE (absent): {script}")
                continue
            print(f"FAIL missing required suite: {script}",file=sys.stderr)
            ok = False
            continue
        expected = ("PASS: 9 RGBA probes", "PASS: 77 biome surface probes") if script==suites[0] else ()
        ok = run(logdir,Path(script).stem,[args.godot,"--headless","--path",".","--fixed-fps","60","--script","res://"+script],420,True,expected=expected) and ok
    print("Full headless acceptance passed; graphical acceptance remains local" if ok else "Headless acceptance failed")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
