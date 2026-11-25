"""Wave-1 QA runner. Python 3.10+, standard library only."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BASE = "67023539e56e5e80d5efcd3f3239be9650c6f462"
MASK = Path("content/scenery/environment_overhaul/masks")
CANDIDATES = [
    "modules/ground_cover/ground_cover.gd",
    "modules/environment_terrain/terrain_preview.gd",
    "modules/environment_rendering/render_profile.gd",
    "assets/environment_overhaul/manifest.json",
    str(MASK / "manifest.json"), str(MASK / "biome_rgba8.bin"),
]
PROTECTED = ["data/world", "content/scenery/vegetation.bin",
             "content/scenery/premium_foliage.bin"]
ERROR = re.compile(r"SCRIPT ERROR|Parse Error|Failed to load script|Shader compilation failed|Shader error|^FAIL(?:ED)?(?:\s|:)", re.M | re.I)
ROOT_TESTS = [
    "tests/core/smoke.gd", "tests/core/steering_camera.gd",
    "tests/core/drift_and_controller.gd", "tests/integration/map_width_check.gd",
    "tests/integration/roadworks_check.gd", "tests/integration/garage_world.gd",
    "tests/integration/vehicle_world.gd", "modules/vehicle_visuals/tests/smoke.gd",
    "tests/integration/forza_showcase_qa.gd", "tests/integration/world_visual_qa.gd",
]

def require(condition, message):
    if not condition:
        raise ValueError(message)

def digest(data):
    return hashlib.sha256(data).hexdigest()

def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"),
                      parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))

def payload(path):
    data = path.read_bytes()
    require(not data.startswith(b"version https://git-lfs.github.com/spec/v1"),
            f"LFS pointer, not payload: {path}")
    return data

def verify_mask(directory):
    m = read_json(directory / "manifest.json")
    for k, v in {"schema_version": 1, "width": 1000, "height": 1000,
                 "cell_size_m": 2, "origin_x": -1000, "origin_z": -1000,
                 "byte_order": "RGBA"}.items():
        require(m.get(k) == v, f"mask {k}: expected {v}")
    names = m.get("channels", m.get("channel_names"))
    if isinstance(names, dict):
        names = [names.get(k) for k in "RGBA"]
    require(isinstance(names, list) and len(names) == 4, "four ordered channels required")
    for value, token in zip(names, ["grass", "woodland", "moisture", "rock"]):
        require(token in str(value).lower(), f"channel mismatch: {value}")
    require(type(m.get("seed")) is int, "integer mask seed")
    sources = m.get("source_hashes")
    require(isinstance(sources, dict) and bool(sources), "source hashes required")
    for name, sha in sources.items():
        require(isinstance(sha, str) and bool(re.fullmatch("[0-9a-fA-F]{64}", sha)), f"invalid source SHA: {name}")
        p = ROOT / name.removeprefix("res://")
        if p.is_file() and p.resolve().is_relative_to(ROOT):
            require(digest(payload(p)) == sha.lower(), f"source hash mismatch: {name}")
    data = payload(directory / "biome_rgba8.bin")
    require(len(data) == 4_000_000, "mask byte count")
    require(digest(data) == m.get("sha256"), "mask SHA-256 mismatch")
    return data

def sample(data, x, z):
    if not (-1000 <= x < 1000 and -1000 <= z < 1000):
        return None
    i, j = math.floor((x + 1000) / 2), math.floor((z + 1000) / 2)
    return tuple(data[4 * (j * 1000 + i):4 * (j * 1000 + i) + 4])

def verify_assets(path):
    m = read_json(path)
    require(m.get("schema_version") == 1 and isinstance(m.get("assets"), list), "asset schema")
    require(bool(m["assets"]), "empty asset inventory")
    keys = set()
    for entry in m["assets"]:
        for field in ["species_id", "variant_id", "lod0", "lod1", "dimensions_m", "origin",
                      "source_url", "author", "license", "license_notice", "sha256_by_path"]:
            require(bool(entry.get(field)), f"missing asset {field}")
        key = (entry["species_id"], entry["variant_id"])
        require(key not in keys, f"duplicate asset {key}")
        keys.add(key)
        require(entry["origin"] == "ground_center", "asset origin")
        d = entry["dimensions_m"]
        require(len(d) == 3 and all(math.isfinite(x) and x > 0 for x in d), "asset dimensions")
        for lod in ["lod0", "lod1", "lod2"]:
            if not entry.get(lod):
                continue
            resource = entry[lod]
            target = (ROOT / resource.removeprefix("res://")).resolve()
            require(target.is_relative_to(ROOT), "asset path escapes project")
            require(target.is_file(), f"missing asset payload {resource}")
            hashes = entry["sha256_by_path"]
            expected = hashes.get(resource, hashes.get(resource.removeprefix("res://")))
            require(digest(payload(target)) == expected, f"asset hash mismatch {resource}")

def verify_understory(path):
    m = read_json(path)
    require(m.get("schema_version") == 1 and type(m.get("seed")) is int
            and bool(m.get("source_hashes")), "understory metadata")
    require(isinstance(m.get("placements"), list), "understory placements")
    for p in m["placements"]:
        require(p["species_id"] in {"fern", "shrub", "sapling", "reed", "wildflower"}, "unknown species")
        require(all(math.isfinite(p[k]) for k in ("x", "z", "yaw_rad", "scale")), "non-finite placement")
        require(-1000 <= p["x"] < 1000 and -1000 <= p["z"] < 1000 and p["scale"] > 0, "invalid placement")
        require(type(p["seed"]) is int, "placement seed")

def run_command(command, log, seconds):
    with log.open("w", encoding="utf-8") as f:
        try:
            proc = subprocess.run(command, cwd=ROOT, stdout=f, stderr=subprocess.STDOUT,
                                  timeout=seconds, check=False)
            status = proc.returncode
        except subprocess.TimeoutExpired:
            status = 124
        except OSError as exc:
            f.write(str(exc))
            status = 127
    content = log.read_text(encoding="utf-8", errors="replace")
    print(content[-12000:], flush=True)
    return status or (1 if ERROR.search(content) else 0)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=["baseline", "integrated"], default="baseline")
    p.add_argument("--godot", default="godot")
    p.add_argument("--out", type=Path, default=Path(tempfile.gettempdir()) / "aster-env-qa")
    p.add_argument("--suite", choices=["all", "owned", "root"], default="all")
    p.add_argument("--agent-command", action="append", default=[], help="JSON argv array, repeat per agent")
    p.add_argument("--rebake-command", help="JSON argv; regenerate mask in place, must preserve exact bytes")
    args = p.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    results = {}
    def check(name, fn):
        try:
            fn()
            results[name] = "PASS"
        except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as exc:
            print(f"FAIL {name}: {exc}", flush=True)
            results[name] = f"FAIL: {exc}"
    def command(name, argv, timeout=420):
        check(name, lambda: require(run_command(argv, out / (name + ".log"), timeout) == 0,
                                    f"nonzero exit, timeout or script error: {name}.log"))
    def canonical():
        subprocess.run(["git", "diff", "--exit-code", BASE, "--", *PROTECTED], cwd=ROOT, check=True)
        for path in ("data/world/road_graph_v1.json", "data/world/terrain_height_r16le.bin",
                     "data/world/world_metadata_v1.json"):
            require(bool(payload(ROOT / path)), f"missing canonical payload {path}")
    check("canonical", canonical)
    check("candidate_discovery", lambda: require(args.mode == "baseline" or
          all((ROOT / p).is_file() for p in CANDIDATES),
          "missing candidate files: " + str([p for p in CANDIDATES if not (ROOT / p).is_file()])))
    for key, path, validator in [
        ("mask", ROOT / MASK / "manifest.json", lambda: verify_mask(ROOT / MASK)),
        ("assets", ROOT / CANDIDATES[3], lambda: verify_assets(ROOT / CANDIDATES[3])),
        ("understory", ROOT / MASK.parent / "understory.json",
         lambda: verify_understory(ROOT / MASK.parent / "understory.json")),
    ]:
        if path.exists():
            check(key, validator)
        else:
            results[key] = "N/A: absent optional data" if key == "understory" or args.mode == "baseline" else "FAIL: missing"
    if args.rebake_command:
        def rebake():
            before = verify_mask(ROOT / MASK)
            argv = json.loads(args.rebake_command)
            for i in range(2):
                require(run_command(argv, out / f"rebake-{i}.log", 600) == 0, "rebake failed")
                require(verify_mask(ROOT / MASK) == before, "mask is not byte deterministic")
        check("rebake", rebake)
    else:
        results["rebake"] = "N/A: explicit generator command not provided"
    command("python-fixtures", [sys.executable, "-m", "unittest", "discover", "-s",
                                 "tests/environment_overhaul", "-p", "test_*.py"], 90)
    command("engine-version", [args.godot, "--headless", "--version"], 20)
    check("engine-pin", lambda: require((out / "engine-version.log").read_text().startswith("4.7.2.stable"), "wrong Godot version"))
    command("root-import", [args.godot, "--headless", "--path", ".", "--editor", "--import"], 900)
    if results["root-import"] == "PASS":
        if args.suite in ("all", "owned"):
            command("environment-contract", [args.godot, "--headless", "--path", ".", "--fixed-fps", "60",
                "--script", "res://tests/environment_overhaul/environment_check.gd", "--", args.mode])
        if args.suite in ("all", "root"):
            for script in ROOT_TESTS:
                command(Path(script).stem, [args.godot, "--headless", "--path", ".", "--fixed-fps", "60", "--script", "res://" + script])
        for i, raw in enumerate(args.agent_command):
            command(f"agent-{i}", json.loads(raw))
    else:
        results["runtime"] = "NOT RUN: import failed"
    (out / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(json.dumps(results, indent=2))
    return int(any(v.startswith("FAIL") for v in results.values()))

if __name__ == "__main__":
    sys.exit(main())
