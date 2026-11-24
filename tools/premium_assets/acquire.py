"""Acquire a curated CC0 Poly Haven asset pack; no runtime network dependency.
Run from any directory with Python 3.10+. Only writes assets/premium_world/payload.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import tempfile
import time
from urllib.parse import urlsplit, unquote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "assets" / "premium_world"
DEST = PACK / "payload"
MANIFEST = PACK / "catalog.json"
UA = "AsterValleyPremiumAssetAcquisition/1.0"
MAX_FILE = 85 * 1024 * 1024
MAX_TOTAL = 450 * 1024 * 1024
HOSTS = {"api.polyhaven.com", "dl.polyhaven.org", "dl.polyhaven.com"}
MAPS = {
    "albedo": (("Diffuse", "diff", "col", "albedo"), ("jpg", "png")),
    "normal": (("nor_gl", "Normal"), ("png", "jpg")),
    "roughness": (("Rough", "roughness", "rough"), ("png", "jpg")),
}

def safe_rel(value):
    value = unquote(value)
    p = PurePosixPath(value)
    if not value or p.is_absolute() or any(x in ("", ".", "..") for x in value.split("/")) or any(x in value for x in ("\\", ":", "\x00", "?", "#")):
        raise ValueError("Unsafe relative path: " + repr(value))
    return Path(*p.parts)

def retry(fn):
    for i in range(3):
        try:
            return fn()
        except (OSError, ValueError) as exc:
            print(f"Attempt {i+1}/3: {exc}", flush=True)
            if i == 2:
                raise
            time.sleep(2 ** i)

def request(url):
    def check(value):
        u = urlsplit(value)
        if u.scheme != "https" or u.hostname not in HOSTS or u.username or u.password or u.port not in (None, 443):
            raise ValueError("Unexpected URL: " + value)
    check(url)
    result = urlopen(Request(url, headers={"User-Agent": UA}), timeout=90)
    try:
        check(result.geturl())
    except Exception:
        result.close()
        raise
    return result

def api(endpoint):
    def get():
        with request("https://api.polyhaven.com/" + endpoint) as response:
            return json.load(response)
    return retry(get)

def file_hash(path, algorithm):
    h = hashlib.new(algorithm)
    with path.open("rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""):
            h.update(b)
    return h.hexdigest()

def fetch(entry, dest, root, records):
    size = int(entry["size"])
    md5 = entry["md5"].lower()
    if size <= 0 or size > MAX_FILE or not re.fullmatch("[0-9a-f]{32}", md5):
        raise ValueError(f"Invalid/oversized source: {dest.name}, {size} bytes")
    if sum(x["size"] for x in records) + size > MAX_TOTAL:
        raise ValueError("Pack exceeds configured total byte budget")
    if dest.exists():
        raise ValueError("Duplicate output path: " + str(dest))
    dest.parent.mkdir(parents=True, exist_ok=True)
    partial = dest.with_name(dest.name + ".part")
    def get():
        count = 0
        try:
            with request(entry["url"]) as response, partial.open("wb") as f:
                while True:
                    chunk = response.read(1024 * 1024)
                    if not chunk:
                        break
                    count += len(chunk)
                    if count > size:
                        raise ValueError("Download exceeds declared byte size")
                    f.write(chunk)
            if count != size or file_hash(partial, "md5") != md5:
                raise ValueError("Upstream byte count or MD5 mismatch: " + dest.name)
            os.replace(partial, dest)
        finally:
            partial.unlink(missing_ok=True)
    retry(get)
    records.append({"path": dest.relative_to(root).as_posix(), "url": entry["url"],
                    "size": size, "md5": md5, "sha256": file_hash(dest, "sha256")})
    print("  verified", records[-1]["path"], size, flush=True)

def pick(files, resolution, names, formats):
    for name in names:
        for fmt in formats:
            candidate = files.get(name, {}).get(resolution, {}).get(fmt)
            if isinstance(candidate, dict) and "url" in candidate:
                return candidate, fmt
    raise ValueError(f"Missing {names} at {resolution}")

def check_gltf(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("asset", {}).get("version") != "2.0" or not data.get("meshes"):
        raise ValueError("Not a glTF 2.0 mesh: " + str(path))
    for section in ("buffers", "images"):
        for item in data.get(section, []):
            uri = item.get("uri")
            if uri and not uri.startswith("data:"):
                dep = path.parent / safe_rel(uri)
                if not dep.is_file():
                    raise ValueError("Missing glTF dependency: " + str(dep))
    triangles = sum(data["accessors"][p["indices"]]["count"] // 3
                    if "indices" in p else data["accessors"][p["attributes"]["POSITION"]]["count"] // 3
                    for mesh in data["meshes"] for p in mesh["primitives"] if p.get("mode", 4) == 4)
    return {"mesh_count": len(data["meshes"]), "source_triangles": triangles,
            "material_count": len(data.get("materials", []))}

def acquire():
    if DEST.exists():
        verify()
        print("Existing verified payload; no changes made.")
        return
    catalog = json.loads(MANIFEST.read_text(encoding="utf-8"))
    all_meta = api("assets")
    with tempfile.TemporaryDirectory(prefix=".premium-", dir=PACK) as tmp:
        root = Path(tmp) / "payload"
        root.mkdir()
        all_files, entries = [], []
        for asset in catalog["assets"]:
            slug, res, kind = asset["id"], asset["resolution"], asset["kind"]
            if not re.fullmatch("[a-z0-9_]+", slug) or slug not in all_meta:
                raise ValueError("Unknown asset: " + slug)
            print("Poly Haven:", slug, res, flush=True)
            files = api("files/" + slug)
            folder = root / ("models" if kind == "model" else "textures") / slug
            start = len(all_files)
            stats = {}
            try:
                if kind == "model":
                    entry, _ = pick(files, res, ("gltf",), ("gltf",))
                    deps = entry.get("include", {})
                    source_size = int(entry["size"]) + sum(int(d["size"]) for d in deps.values())
                    # Geometry is resolution-independent; lowering texture resolution
                    # does not rescue multi-hundred-MB geometry buffers.
                    oversize = any(int(d["size"]) > MAX_FILE for d in [entry, *deps.values()])
                    if oversize or source_size > 90 * 1024 * 1024:
                        stats = {"status": "texture_only", "source_package_bytes": source_size,
                                 "reason": "Source geometry/package exceeds game repository source budget"}
                        print("  geometry omitted:", source_size, "bytes", flush=True)
                        for rel, dep in sorted(deps.items()):
                            relpath = safe_rel(rel)
                            if relpath.suffix.lower() not in (".png", ".jpg", ".jpeg", ".webp"):
                                continue
                            if int(dep["size"]) > MAX_FILE or sum(x["size"] for x in all_files[start:]) + int(dep["size"]) > 45 * 1024 * 1024:
                                print("  texture omitted by per-asset budget:", rel, flush=True)
                                continue
                            fetch(dep, folder / relpath, root, all_files)
                        if len(all_files) == start:
                            raise ValueError("Oversized model has no usable separate textures")
                        stats["maps"] = [x["path"] for x in all_files[start:]]
                    else:
                        name = safe_rel(urlsplit(entry["url"]).path.rsplit("/", 1)[-1])
                        model = folder / name
                        fetch(entry, model, root, all_files)
                        for rel, dep in sorted(deps.items()):
                            fetch(dep, folder / safe_rel(rel), root, all_files)
                        stats = check_gltf(model)
                        stats.update(status="complete", entrypoint=model.relative_to(root).as_posix())
                elif kind == "texture":
                    for role, (names, formats) in MAPS.items():
                        entry, fmt = pick(files, res, names, formats)
                        fetch(entry, folder / (role + "." + fmt), root, all_files)
                    stats = {"status": "complete", "maps": [x["path"] for x in all_files[start:]]}
                else:
                    raise ValueError("Unknown kind: " + kind)
            except (ValueError, OSError, KeyError) as exc:
                shutil.rmtree(folder, ignore_errors=True)
                del all_files[start:]
                stats = {"status": "unavailable", "reason": str(exc)}
                print("  asset unavailable:", slug, str(exc), flush=True)
            entries.append({**asset, **stats, "source_url": "https://polyhaven.com/a/" + slug,
                            "authors": all_meta[slug].get("authors", {}),
                            "license": "CC0-1.0", "files": all_files[start:]})
        if not all_files:
            raise ValueError("No usable assets downloaded; refusing to install an empty pack")
        lock = {"provider": "Poly Haven", "license_url": catalog["license_url"],
                "assets": entries, "bytes": sum(f["size"] for f in all_files)}
        (root / "LICENSES_AND_HASHES.json").write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")
        verify(root)
        root.rename(DEST)
    print("Installed verified source pack at", DEST)

def verify(root=DEST):
    lock = json.loads((root / "LICENSES_AND_HASHES.json").read_text(encoding="utf-8"))
    catalog = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if [(x["id"], x["resolution"], x["kind"]) for x in lock["assets"]] != [(x["id"], x["resolution"], x["kind"]) for x in catalog["assets"]]:
        raise ValueError("Lock does not match catalog")
    paths = set()
    total = 0
    for asset in lock["assets"]:
        for item in asset["files"]:
            path = root / safe_rel(item["path"])
            if item["path"] in paths or not path.is_file() or path.stat().st_size != item["size"] or file_hash(path, "sha256") != item["sha256"]:
                raise ValueError("Missing, duplicate or changed file: " + str(path))
            paths.add(item["path"])
            total += item["size"]
        if asset["kind"] == "model" and asset["status"] == "complete":
            check_gltf(root / safe_rel(asset["entrypoint"]))
        if asset["status"] == "unavailable" and asset["files"]:
            raise ValueError("Unavailable asset contains files")
    if total != lock["bytes"]:
        raise ValueError("Lock total differs")
    counts = {state: sum(a["status"] == state for a in lock["assets"]) for state in ("complete", "texture_only", "unavailable")}
    print(f"Verified {counts} / {len(paths)} files / {total:,} bytes")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true", help="Verify installed assets without network")
    parser.add_argument("--plan", action="store_true", help="Print the curated catalog without network")
    args = parser.parse_args()
    if args.plan:
        print(MANIFEST.read_text(encoding="utf-8"))
    elif args.verify:
        verify()
    else:
        acquire()

if __name__ == "__main__":
    main()
