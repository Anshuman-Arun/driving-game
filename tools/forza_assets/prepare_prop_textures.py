"""Create compact 512x512 prop textures from our 2K Poly Haven textures for glTF/GLB embedding."""
from pathlib import Path
from PIL import Image

ROOT = Path(r"c:\Users\anshu\Documents\Coding\Driving-Game\driving-game")
SRC_DIR = ROOT / "assets" / "forza_env" / "textures"
DST_DIR = ROOT / "tools" / "forza_assets" / "prop_textures"

FOLDERS = [
    "asphalt", "rock", "bark", "wood_planks", "roof_slate",
    "stone_wall", "corrugated_metal", "hay"
]

def main():
    for folder in FOLDERS:
        sdir = SRC_DIR / folder
        ddir = DST_DIR / folder
        ddir.mkdir(parents=True, exist_ok=True)
        for name, ext in [("albedo", "jpg"), ("normal", "png"), ("roughness", "png")]:
            src = sdir / f"{name}.{ext}"
            if not src.exists():
                continue
            dst = ddir / f"{name}.jpg"
            if dst.exists():
                continue
            img = Image.open(src).convert("RGB")
            img = img.resize((512, 512), Image.Resampling.LANCZOS)
            img.save(dst, "JPEG", quality=85, optimize=True)
            print(f"  [ok] {dst.relative_to(ROOT)} ({dst.stat().st_size // 1024} KB)")

if __name__ == "__main__":
    main()
