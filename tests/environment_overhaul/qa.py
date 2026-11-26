"""Wave-1 QA runner. Python 3.10+, standard library only."""
import argparse
import hashlib
import json
import math
import os
import signal
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
AGENT_TESTS = [
    ("modules/ground_cover/tests/run_tests.gd", ["@godot","--headless","--path",".","--fixed-fps","60","--script","res://modules/ground_cover/tests/run_tests.gd"]),
    ("modules/ground_cover/tests/real_world_smoke.gd", ["@godot","--headless","--path",".","--fixed-fps","60","--script","res://modules/ground_cover/tests/real_world_smoke.gd"]),
    ("tools/environment_assets/generate.mjs", ["node","tools/environment_assets/generate.mjs","--self-test"]),
    ("tools/environment_assets/generate.mjs", ["node","tools/environment_assets/generate.mjs","--verify"]),
    ("tools/environment_assets/test_import.gd", ["@godot","--headless","--path",".","--script","res://tools/environment_assets/test_import.gd"]),
    ("content/scenery/environment_overhaul/test_biomes.py", ["@python","-m","unittest","discover","-s","content/scenery/environment_overhaul","-p","test_biomes.py","-v"]),
    ("content/scenery/environment_overhaul/test_surface.gd", ["@godot","--headless","--path",".","--script","res://content/scenery/environment_overhaul/test_surface.gd"]),
    ("modules/environment_terrain/tests/run_tests.gd", ["@godot","--headless","--path",".","--script","res://modules/environment_terrain/tests/run_tests.gd"]),
    ("modules/environment_rendering/tests/render_profile_test.gd", ["@godot","--headless","--path",".","--script","res://modules/environment_rendering/tests/render_profile_test.gd"]),
    ("modules/environment_rendering/tests/live_root_test.gd", ["@godot","--headless","--path",".","--script","res://modules/environment_rendering/tests/live_root_test.gd"]),
]
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
    def unique_object(pairs):
        result={}
        for key,value in pairs:
            require(key not in result,f"duplicate JSON key: {key}")
            result[key]=value
        return result
    return json.loads(path.read_text(encoding="utf-8"),object_pairs_hook=unique_object,
                      parse_constant=lambda x: (_ for _ in ()).throw(ValueError(x)))

def payload(path):
    data = path.read_bytes()
    require(not data.startswith(b"version https://git-lfs.github.com/spec/v1"),
            f"LFS pointer, not payload: {path}")
    return data

def verify_mask(directory, root=ROOT, strict_sources=False):
    m = read_json(directory / "manifest.json")
    require(isinstance(m, dict), "mask manifest object")
    for k, v in {"schema_version": 1, "width": 1000, "height": 1000,
                 "cell_size_m": 2, "origin_x": -1000, "origin_z": -1000,
                 "byte_order": "RGBA"}.items():
        require(type(m.get(k)) is type(v) and m.get(k) == v, f"mask {k}: expected {v}")
    names = m.get("channels", m.get("channel_names"))
    if isinstance(names, dict):
        names = [names.get(k) for k in "RGBA"]
    require(isinstance(names, list) and len(names) == 4, "four ordered channels required")
    for value, allowed in zip(names, [("grass_suitability","grass"),("woodland_weight","woodland"),("moisture",),("exposed_rock_weight","rock")]):
        require(isinstance(value,str) and value in allowed,f"channel mismatch: {value}")
    if "row_order" in m:
        require(m["row_order"]=="z_ascending_x_ascending","mask row order")
    require(type(m.get("seed")) is int, "integer mask seed")
    sources = m.get("source_hashes")
    require(isinstance(sources, dict) and bool(sources), "source hashes required")
    for name, sha in sources.items():
        require(isinstance(sha, str) and bool(re.fullmatch("[0-9a-fA-F]{64}", sha)), f"invalid source SHA: {name}")
        p = (root / name.removeprefix("res://")).resolve()
        require(p.is_relative_to(root.resolve()), f"source path escapes project: {name}")
        if strict_sources or p.is_file():
            require(p.is_file(), f"source absent: {name}")
            require(digest(payload(p)) == sha.lower(), f"source hash mismatch: {name}")
    data = payload(directory / "biome_rgba8.bin")
    require(len(data) == 4_000_000, "mask byte count")
    require(digest(data) == m.get("sha256"), "mask SHA-256 mismatch")
    if strict_sources:
        for canonical in ("data/world/road_graph_v1.json","data/world/world_metadata_v1.json","data/world/terrain_height_r16le.bin","data/world/roadworks.json","data/world/terrain_roadworks_r16le.bin"):
            require(canonical in {k.removeprefix("res://") for k in sources}, f"unrecorded canonical source: {canonical}")
    if "statistics_sha256" in m:
        require(digest(payload(directory/"statistics.json"))==m["statistics_sha256"],"statistics SHA-256 mismatch")
    if "generator_sha256" in m and strict_sources:
        require(digest(payload(root/MASK.parent/"bake_biomes.py"))==m["generator_sha256"],"generator SHA-256 mismatch")
    if strict_sources and (directory/"understory.json").exists():
        require("understory_sha256" in m,"unhashed understory file")
    if "understory_sha256" in m:
        understory = directory / "understory.json"
        require(digest(payload(understory)) == m["understory_sha256"], "understory SHA-256 mismatch")
        u = read_json(understory)
        require(isinstance(u,dict) and u.get("seed")==m["seed"] and u.get("source_hashes")==sources, "understory provenance differs from mask")
        verify_understory(understory)
    return data

def sample(data, x, z):
    if not (-1000 <= x < 1000 and -1000 <= z < 1000):
        return None
    require(len(data)==4_000_000,"invalid sample buffer")
    # Addition can round the representable predecessor of +1000 to 2000.
    # The half-open domain test above remains authoritative.
    i,j=min(999,math.floor((x+1000)/2)),min(999,math.floor((z+1000)/2))
    return tuple(data[4 * (j * 1000 + i):4 * (j * 1000 + i) + 4])

def verify_assets(path, root=ROOT):
    m = read_json(path)
    require(isinstance(m,dict) and type(m.get("schema_version")) is int and m["schema_version"] == 1 and isinstance(m.get("assets"), list), "asset schema")
    require(bool(m["assets"]), "empty asset inventory")
    keys = set()
    for entry in m["assets"]:
        require(isinstance(entry,dict), "asset entry object")
        for field in ["species_id", "variant_id", "lod0", "lod1", "dimensions_m", "origin",
                      "source_url", "author", "license", "license_notice", "sha256_by_path"]:
            require(bool(entry.get(field)), f"missing asset {field}")
        for field in ("species_id","variant_id","lod0","lod1","source_url","author","license","license_notice"):
            require(isinstance(entry[field],str) and bool(entry[field].strip()), f"invalid asset {field}")
        require(isinstance(entry["sha256_by_path"],dict), "asset hashes object")
        key = (entry["species_id"], entry["variant_id"])
        require(key not in keys, f"duplicate asset {key}")
        keys.add(key)
        require(entry["origin"] == "ground_center", "asset origin")
        d = entry["dimensions_m"]
        require(isinstance(d,list) and len(d) == 3 and all(type(x) in (int,float) and math.isfinite(x) and x > 0 for x in d), "asset dimensions")
        for lod in ["lod0", "lod1", "lod2"]:
            if not entry.get(lod):
                continue
            resource = entry[lod]
            require(isinstance(resource,str) and resource.startswith("res://"), "LOD must be a project resource path")
            target = (root / resource.removeprefix("res://")).resolve()
            require(target.is_relative_to(root), "asset path escapes project")
            require(target.is_file(), f"missing asset payload {resource}")
            hashes = entry["sha256_by_path"]
            expected = hashes.get(resource, hashes.get(resource.removeprefix("res://")))
            require(bool(payload(target)) and digest(payload(target)) == expected, f"asset hash mismatch {resource}")
        notice=entry["license_notice"]
        if notice.startswith("res://"):
            p=(root/notice.removeprefix("res://")).resolve()
            require(p.is_relative_to(root.resolve()) and p.is_file() and bool(payload(p)), "license notice missing")

def verify_understory(path):
    m = read_json(path)
    require(isinstance(m,dict) and type(m.get("schema_version")) is int and m["schema_version"] == 1 and type(m.get("seed")) is int
            and isinstance(m.get("source_hashes"), dict) and bool(m["source_hashes"]), "understory metadata")
    require(all(isinstance(v, str) and re.fullmatch("[0-9a-fA-F]{64}", v)
                for v in m["source_hashes"].values()), "understory source hashes")
    require(isinstance(m.get("placements"), list), "understory placements")
    seen=set()
    for p in m["placements"]:
        require(isinstance(p,dict), "placement object")
        require(p["species_id"] in {"fern", "shrub", "sapling", "reed", "wildflower"}, "unknown species")
        require(all(type(p[k]) in (int,float) and math.isfinite(p[k]) for k in ("x", "z", "yaw_rad", "scale")), "non-finite placement")
        require(-1000 <= p["x"] < 1000 and -1000 <= p["z"] < 1000 and p["scale"] > 0, "invalid placement")
        require(type(p["seed"]) is int, "placement seed")
        key=(p["x"],p["z"])
        require(key not in seen,"duplicate placement")
        seen.add(key)

def run_command(command, log, seconds):
    with log.open("w",encoding="utf-8") as f:
        process=None
        try:
            process=subprocess.Popen(command,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT,
                start_new_session=os.name!="nt",creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if os.name=="nt" else 0)
            status=process.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            # Kill descendant processes as well as their launcher. Otherwise a
            # timed-out agent script could continue mutating the test checkout.
            if os.name=="nt":
                try:
                    subprocess.run(["taskkill","/F","/T","/PID",str(process.pid)],stdout=f,stderr=subprocess.STDOUT,timeout=10,check=False)
                except (OSError,subprocess.SubprocessError):
                    pass
                if process.poll() is None:
                    process.kill()
            else:
                try:
                    os.killpg(process.pid,signal.SIGKILL)
                except ProcessLookupError:
                    pass
            process.wait(timeout=10)
            status=124
        except OSError as exc:
            f.write(str(exc))
            status=127
    content = log.read_text(encoding="utf-8", errors="replace")
    print(content[-12000:], flush=True)
    matches=[line for line in content.splitlines() if ERROR.search(line)]
    if matches:
        print("Matched failure diagnostics:", "\n".join(matches[:40]),flush=True)
    if status:
        print(f"Process exit status: {status}; log: {log}",flush=True)
    return status or (1 if matches else 0)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=["baseline", "integrated"], default="baseline")
    p.add_argument("--godot", default="godot")
    p.add_argument("--out", type=Path, default=None)
    p.add_argument("--suite", choices=["all", "owned", "root"], default="all")
    p.add_argument("--agent-command", action="append", default=[], help="JSON argv array, repeat per agent")
    p.add_argument("--rebake-command", help="JSON argv; regenerate mask in place, must preserve exact bytes")
    p.add_argument("--prepare-mask", action="store_true", help="Generate missing mask in disposable integrated checkout using C generator")
    p.add_argument("--agent-manifest", type=Path, help="JSON array of explicit agent test argv lists")
    p.add_argument("--bend-margin", type=float, default=0.36, help="Swept bound margin in metres (A: 0.24 displacement + 0.12 clearance)")
    p.add_argument("--stats-map", type=Path, help="Map semantic counters to A top-level keys")
    args = p.parse_args()
    out = args.out.resolve() if args.out else Path(tempfile.mkdtemp(prefix="aster-env-qa-"))
    out.mkdir(parents=True, exist_ok=True)
    if (out/"results.json").exists():
        p.error("output already contains a run; choose a fresh directory")
    print(f"QA logs: {out}",flush=True)
    results = {}
    def persist():
        temp=out/"results.tmp"
        temp.write_text(json.dumps(results,indent=2),encoding="utf-8")
        temp.replace(out/"results.json")
    def check(name, fn):
        try:
            fn()
            results[name] = "PASS"
        except (ValueError, OSError, KeyError, TypeError, AttributeError, OverflowError, subprocess.SubprocessError) as exc:
            print(f"FAIL {name}: {exc}", flush=True)
            results[name] = f"FAIL: {exc}"
        finally:
            persist()
    def command(name, argv, timeout=420):
        check(name, lambda: require(run_command(argv, out / (name + ".log"), timeout) == 0,
                                    f"nonzero exit, timeout or script error: {name}.log"))
    def canonical():
        subprocess.run(["git", "merge-base", "--is-ancestor", BASE, "HEAD"], cwd=ROOT, check=True)
        subprocess.run(["git", "diff", "--exit-code", BASE, "--", *PROTECTED], cwd=ROOT, check=True)
        untracked=subprocess.check_output(["git","ls-files","--others","--exclude-standard","--",*PROTECTED],cwd=ROOT,text=True)
        require(not untracked.strip(), "untracked canonical paths: "+untracked.strip())
        for path in ("data/world/road_graph_v1.json","data/world/terrain_height_r16le.bin",
                     "data/world/world_metadata_v1.json","data/world/roadworks.json","data/world/terrain_roadworks_r16le.bin",
                     "data/world/vegetation.bin"):
            require(bool(payload(ROOT / path)), f"missing canonical payload {path}")
    check("canonical", canonical)
    if args.mode=="integrated" and args.suite!="all":
        results["integrated-scope"]="FAIL: integrated verification requires --suite all"
    generator=ROOT/MASK.parent/"bake_biomes.py"
    if args.prepare_mask:
        def prepare():
            require(args.mode=="integrated","--prepare-mask requires integrated mode")
            require(generator.is_file(),"C generator missing")
            expected=[ROOT/MASK/name for name in ("manifest.json","biome_rgba8.bin","understory.json","statistics.json")]
            if any(p.exists() for p in expected):
                require(all(p.is_file() for p in expected),"partial mask package; refuse implicit overwrite")
                verify_mask(ROOT/MASK,strict_sources=True)
            else:
                require(run_command([sys.executable,str(generator),"--project",str(ROOT),"--output",str(ROOT/MASK),"--seed","20261121"],out/"prepare-mask.log",600)==0,"mask generation failed")
                verify_mask(ROOT/MASK,strict_sources=True)
        check("prepare-mask",prepare)
    missing = [p for p in CANDIDATES if not (ROOT / p).is_file()]
    if args.mode == "baseline" and missing:
        results["candidate_discovery"] = "N/A: baseline omits " + ", ".join(missing)
    else:
        check("candidate_discovery", lambda: require(not missing, "missing candidate files: " + str(missing)))
    for key, path, validator in [
        ("mask", ROOT / MASK / "manifest.json", lambda: verify_mask(ROOT / MASK, strict_sources=args.mode=="integrated")),
        ("assets", ROOT / CANDIDATES[3], lambda: verify_assets(ROOT / CANDIDATES[3])),
        ("understory", ROOT / MASK / "understory.json",
         lambda: verify_understory(ROOT / MASK / "understory.json")),
    ]:
        if path.exists():
            check(key, validator)
        else:
            results[key] = "N/A: absent optional data" if key == "understory" or args.mode == "baseline" else "FAIL: missing"
    if args.rebake_command or (args.mode=="integrated" and generator.is_file() and (ROOT/MASK/"manifest.json").is_file()):
        def rebake():
            before = verify_mask(ROOT / MASK, strict_sources=args.mode=="integrated")
            before_manifest = payload(ROOT / MASK / "manifest.json")
            before_understory = payload(ROOT / MASK / "understory.json") if (ROOT / MASK / "understory.json").exists() else None
            if args.rebake_command:
                argv=json.loads(args.rebake_command)
            else:
                meta=read_json(ROOT/MASK/"manifest.json")
                tuning=out/"rebake-tuning.json"
                tuning.write_text(json.dumps(meta["tuning"]),encoding="utf-8")
                argv=[sys.executable,str(generator),"--project",str(ROOT),"--output",str(ROOT/MASK),"--seed",str(meta["seed"]),"--tuning",str(tuning)]
            require(isinstance(argv,list) and argv and all(isinstance(x,str) for x in argv),"rebake argv must be nonempty string array")
            for i in range(2):
                require(run_command(argv, out / f"rebake-{i}.log", 600) == 0, "rebake failed")
                require(verify_mask(ROOT / MASK, strict_sources=args.mode=="integrated") == before, "mask is not byte deterministic")
                require(payload(ROOT / MASK / "manifest.json")==before_manifest,"manifest nondeterminism")
                if before_understory is not None:
                    require(payload(ROOT / MASK / "understory.json")==before_understory,"understory nondeterminism")
        check("rebake", rebake)
    else:
        results["rebake"] = "FAIL: integrated requires reproducibility command" if args.mode=="integrated" else "N/A: generator not available on baseline"
    command("python-fixtures", [sys.executable, "-m", "unittest", "discover", "-s",
                                 "tests/environment_overhaul", "-p", "test_*.py"], 90)
    command("engine-version", [args.godot, "--headless", "--version"], 20)
    check("engine-pin", lambda: require((out / "engine-version.log").read_text().startswith("4.7.2.stable"), "wrong Godot version"))
    command("root-import", [args.godot, "--headless", "--path", ".", "--editor", "--import"], 900)
    if results["root-import"] == "PASS" and results["engine-pin"] == "PASS":
        command("capture-parse",[args.godot,"--headless","--path",".","--check-only","--script","res://tests/environment_overhaul/capture.gd"],90)
        if args.suite in ("all","owned"):
            command("capture-self-test",[args.godot,"--headless","--path",".","--fixed-fps","60","--script","res://tests/environment_overhaul/capture.gd","--","--self-test"],180)
            def refuse_headless():
                target=out/"forbidden-headless-capture"
                log=out/"capture-refusal.log"
                status=run_command([args.godot,"--headless","--path",".","--script","res://tests/environment_overhaul/capture.gd","--","--out="+str(target)],log,60)
                require(status==1 and "Graphical renderer required" in log.read_text(encoding="utf-8"),"headless capture did not explicitly refuse")
                require(not target.exists(),"headless capture emitted output")
            check("capture-headless-refusal",refuse_headless)
        if args.suite in ("all", "owned"):
            runtime = [args.godot, "--headless", "--path", ".", "--fixed-fps", "60",
                "--script", "res://tests/environment_overhaul/environment_check.gd", "--", args.mode,
                f"--bend-margin={args.bend_margin}"]
            if args.stats_map:
                runtime.append(f"--stats-map={args.stats_map.resolve()}")
            command("environment-contract", runtime)
        if args.suite in ("all", "root"):
            for script in ROOT_TESTS:
                command(script.removesuffix(".gd").replace("/", "__"), [args.godot, "--headless", "--path", ".", "--fixed-fps", "60", "--script", "res://" + script])
        manifest = args.agent_manifest or ROOT / "tests/environment_overhaul/agent_commands.json"
        agent_commands = []
        def discover_commands():
            agent_commands.extend(json.loads(raw) for raw in args.agent_command)
            if args.agent_manifest or manifest.is_file():
                config=read_json(manifest)
                require(isinstance(config,list),"agent manifest must be a list")
                agent_commands.extend(config)
            for path, argv in AGENT_TESTS:
                if (ROOT/path).is_file():
                    cmd=[args.godot if x=="@godot" else sys.executable if x=="@python" else x for x in argv]
                    if cmd not in agent_commands:
                        agent_commands.append(cmd)
        check("agent-discovery",discover_commands)
        if args.mode=="integrated":
            check("agent-test-presence",lambda: require(all((ROOT/path).is_file() for path,_ in AGENT_TESTS),"missing owned agent tests"))
        if not agent_commands:
            results["agent_commands"] = "N/A: no explicit agent commands supplied"
        for i, argv in enumerate(agent_commands):
            if isinstance(argv, list) and argv and all(isinstance(v, str) and v for v in argv):
                command(f"agent-{i}", argv)
            else:
                results[f"agent-{i}"] = "FAIL: expected nonempty JSON argv array"
    else:
        results["runtime"] = "NOT RUN: import failed"
    check("canonical-after",canonical)
    persist()
    print(json.dumps(results, indent=2))
    return int(any(v.startswith("FAIL") for v in results.values()))

if __name__ == "__main__":
    sys.exit(main())
