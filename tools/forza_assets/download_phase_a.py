"""Download Phase A 2K CC0 PBR textures and HDRIs from Poly Haven."""
import json
import os
from pathlib import Path
import requests

ROOT = Path(r"c:\Users\anshu\Documents\Coding\Driving-Game\driving-game")
TEX_DIR = ROOT / "assets" / "forza_env" / "textures"
HDRI_DIR = ROOT / "assets" / "forza_env" / "hdri"
META_PATH = ROOT / "assets" / "forza_env" / "ASSET_LICENSES_FORZA.json"
HEADERS = {"User-Agent": "DrivingGameAssetScout/1.0"}

TEXTURE_SLUGS = {
    "asphalt": "asphalt_02",
    "gravel": "sandy_gravel_02",
    "shoulder": "brown_mud_03",
    "grass": "forrest_ground_01",
    "forest_floor": "forest_leaves_04",
    "rock": "rock_face_03",
    "shore": "coast_sand_03",
    # Extra architectural PBR textures for Phase B buildings & props
    "bark": "pine_bark",
    "wood_planks": "wood_planks",
    "roof_slate": "roof_slates_03",
    "stone_wall": "patterned_cobblestone",
    "corrugated_metal": "corrugated_iron",
    "hay": "thatch_roof_angled",
}

HDRI_SLUGS = {
    "outdoor_sky.hdr": "kloofendal_48d_partly_cloudy_puresky",
    "garage_studio.hdr": "studio_small_09",
}


def download_file(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 1024:
        print(f"  [skip] {dest.relative_to(ROOT)} already exists")
        return
    with requests.get(url, headers=HEADERS, stream=True, timeout=60) as r:
        r.raise_for_status()
        with open(dest, "wb") as f:
            for chunk in r.iter_content(chunk_size=65536):
                f.write(chunk)
    print(f"  [ok]   {dest.relative_to(ROOT)} ({dest.stat().st_size // 1024} KB)")


def pick_map(files: dict, candidates: list[str], res: str = "2k", exts: tuple[str, ...] = ("png", "jpg")) -> tuple[str, str] | None:
    for key in candidates:
        if key in files and res in files[key]:
            for ext in exts:
                if ext in files[key][res]:
                    return files[key][res][ext]["url"], ext
    return None


def main():
    licenses = []
    all_textures = requests.get("https://api.polyhaven.com/assets?t=textures", headers=HEADERS, timeout=30).json()
    all_hdris = requests.get("https://api.polyhaven.com/assets?t=hdris", headers=HEADERS, timeout=30).json()

    for folder, slug in TEXTURE_SLUGS.items():
        print(f"Fetching texture {folder} <- {slug}")
        info = all_textures.get(slug, {})
        files = requests.get(f"https://api.polyhaven.com/files/{slug}", headers=HEADERS, timeout=30).json()
        out_dir = TEX_DIR / folder
        out_dir.mkdir(parents=True, exist_ok=True)

        downloaded = []
        # Albedo / Diffuse (prefer jpg or png; jpg is much smaller and standard for albedo, png for data maps)
        res = pick_map(files, ["Diffuse", "col", "albedo"], "2k", ("jpg", "png"))
        if res:
            url, ext = res
            dest = out_dir / f"albedo.{ext}"
            download_file(url, dest)
            downloaded.append(str(dest.relative_to(ROOT)).replace("\\", "/"))

        # Normal GL
        res = pick_map(files, ["nor_gl", "Normal"], "2k", ("png", "jpg"))
        if res:
            url, ext = res
            dest = out_dir / f"normal.{ext}"
            download_file(url, dest)
            downloaded.append(str(dest.relative_to(ROOT)).replace("\\", "/"))

        # Roughness
        res = pick_map(files, ["Rough", "roughness"], "2k", ("png", "jpg"))
        if res:
            url, ext = res
            dest = out_dir / f"roughness.{ext}"
            download_file(url, dest)
            downloaded.append(str(dest.relative_to(ROOT)).replace("\\", "/"))

        # AO
        res = pick_map(files, ["AO", "ao"], "2k", ("png", "jpg"))
        if res:
            url, ext = res
            dest = out_dir / f"ao.{ext}"
            download_file(url, dest)
            downloaded.append(str(dest.relative_to(ROOT)).replace("\\", "/"))

        authors = ", ".join(info.get("authors", {}).keys()) or "Poly Haven"
        licenses.append({
            "asset_id": f"tex_{folder}",
            "polyhaven_slug": slug,
            "source_url": f"https://polyhaven.com/a/{slug}",
            "author": authors,
            "license": "CC0",
            "license_url": "https://polyhaven.com/license",
            "local_files": downloaded,
            "resolution": "2048x2048",
        })

    for fname, slug in HDRI_SLUGS.items():
        print(f"Fetching HDRI {fname} <- {slug}")
        info = all_hdris.get(slug, {})
        files = requests.get(f"https://api.polyhaven.com/files/{slug}", headers=HEADERS, timeout=30).json()
        hdri_url = files["hdri"]["2k"]["hdr"]["url"]
        dest = HDRI_DIR / fname
        download_file(hdri_url, dest)
        authors = ", ".join(info.get("authors", {}).keys()) or "Poly Haven"
        licenses.append({
            "asset_id": f"hdri_{fname.replace('.hdr', '')}",
            "polyhaven_slug": slug,
            "source_url": f"https://polyhaven.com/a/{slug}",
            "author": authors,
            "license": "CC0",
            "license_url": "https://polyhaven.com/license",
            "local_files": [str(dest.relative_to(ROOT)).replace("\\", "/")],
            "resolution": "2k HDR",
        })

    META_PATH.parent.mkdir(parents=True, exist_ok=True)
    META_PATH.write_text(json.dumps({"assets": licenses}, indent=2), encoding="utf-8")
    print(f"Wrote {META_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
