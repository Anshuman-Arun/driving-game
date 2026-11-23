"""Download Poly Haven photogrammetry rock models (1k glTF) for Phase B."""
import json
from pathlib import Path
import requests

ROOT = Path(r"c:\Users\anshu\Documents\Coding\Driving-Game\driving-game")
RAW_DIR = ROOT / "tools" / "forza_assets" / "raw_models"
META_PATH = ROOT / "assets" / "forza_env" / "ASSET_LICENSES_FORZA.json"
HEADERS = {"User-Agent": "DrivingGameAssetScout/1.0"}

MODEL_SLUGS = ["boulder_01", "rock_07"]


def download_file(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 512:
        return
    with requests.get(url, headers=HEADERS, stream=True, timeout=60) as r:
        r.raise_for_status()
        with open(dest, "wb") as f:
            for chunk in r.iter_content(chunk_size=65536):
                f.write(chunk)


def main():
    all_models = requests.get("https://api.polyhaven.com/assets?t=models", headers=HEADERS, timeout=30).json()
    meta = json.loads(META_PATH.read_text(encoding="utf-8")) if META_PATH.exists() else {"assets": []}
    existing_ids = {a["asset_id"] for a in meta["assets"]}

    for slug in MODEL_SLUGS:
        print(f"Downloading model {slug} (1k gltf)...")
        files = requests.get(f"https://api.polyhaven.com/files/{slug}", headers=HEADERS, timeout=30).json()
        gltf_entry = files["gltf"]["1k"]["gltf"]
        out_dir = RAW_DIR / slug
        gltf_path = out_dir / f"{slug}_1k.gltf"
        download_file(gltf_entry["url"], gltf_path)
        for rel_path, finfo in gltf_entry.get("include", {}).items():
            download_file(finfo["url"], out_dir / rel_path)
        print(f"  [ok] {gltf_path.relative_to(ROOT)}")

        asset_id = f"model_{slug}"
        if asset_id not in existing_ids:
            info = all_models.get(slug, {})
            authors = ", ".join(info.get("authors", {}).keys()) or "Poly Haven"
            meta["assets"].append({
                "asset_id": asset_id,
                "polyhaven_slug": slug,
                "source_url": f"https://polyhaven.com/a/{slug}",
                "author": authors,
                "license": "CC0",
                "license_url": "https://polyhaven.com/license",
                "local_files": [
                    "assets/curated/models/environment/boulder.glb" if slug == "boulder_01"
                    else "assets/curated/models/environment/rock_cluster.glb"
                ],
                "notes": "Decimated in Blender 4.5 to ~1.5k-2.2k tris, normalized to manifest footprint & Y=0 base.",
            })

    META_PATH.write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print("Updated ASSET_LICENSES_FORZA.json")


if __name__ == "__main__":
    main()
