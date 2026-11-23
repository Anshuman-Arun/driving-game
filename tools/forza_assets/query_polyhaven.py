"""Query Poly Haven API for textures, HDRIs, and models matching our categories."""
import json
import requests

HEADERS = {"User-Agent": "DrivingGameAssetScout/1.0"}

def fetch_json(url: str) -> dict:
    r = requests.get(url, headers=HEADERS, timeout=30)
    r.raise_for_status()
    return r.json()

def search_assets(assets: dict, keywords: list[str], limit: int = 8) -> list[tuple[str, str, list[str]]]:
    matches = []
    for slug, info in assets.items():
        name = info.get("name", "")
        cats = info.get("categories", [])
        tags = info.get("tags", [])
        hay = f"{slug} {name} {' '.join(cats)} {' '.join(tags)}".lower()
        score = sum(1 for kw in keywords if kw.lower() in hay)
        if score > 0:
            matches.append((score, info.get("download_count", 0), slug, name, cats))
    matches.sort(key=lambda x: (x[0], x[1]), reverse=True)
    return [(m[2], m[3], m[4]) for m in matches[:limit]]

def main():
    textures = fetch_json("https://api.polyhaven.com/assets?t=textures")
    hdris = fetch_json("https://api.polyhaven.com/assets?t=hdris")
    models = fetch_json("https://api.polyhaven.com/assets?t=models")

    print(f"Total: {len(textures)} textures, {len(hdris)} hdris, {len(models)} models\n")

    tex_queries = {
        "asphalt": ["asphalt", "tarmac", "road"],
        "gravel": ["gravel", "pebble", "dirt_road"],
        "shoulder": ["dirt", "soil", "mud", "earth"],
        "grass": ["grass", "meadow", "lawn"],
        "forest_floor": ["forest", "pine", "leaves", "moss", "ground"],
        "rock": ["rock", "cliff", "stone", "granite"],
        "shore": ["sand", "beach", "pebble", "wet"],
        "wood_bark": ["bark", "pine_bark", "tree_bark"],
        "wood_plank": ["wood", "plank", "timber"],
        "roof_shingle": ["roof", "shingle", "slate", "tile"],
        "brick_stone": ["stone_wall", "brick", "cobble"],
        "metal": ["metal", "corrugated", "rust", "steel"],
        "hay": ["straw", "hay", "thatch"],
    }
    print("=== TEXTURES ===")
    for cat, kws in tex_queries.items():
        print(f"[{cat}]")
        for slug, name, cats in search_assets(textures, kws, 5):
            print(f"  {slug}: {name} ({cats})")

    print("\n=== HDRIS ===")
    for cat, kws in {
        "outdoor_sky": ["puresky", "afternoon", "cloudy", "kloofendal", "kloppenheim", "qwantani"],
        "garage_studio": ["studio", "autoshop", "garage"],
    }.items():
        print(f"[{cat}]")
        for slug, name, cats in search_assets(hdris, kws, 6):
            print(f"  {slug}: {name} ({cats})")

    print("\n=== MODELS ===")
    for cat, kws in {
        "rocks": ["rock", "boulder", "stone", "cliff"],
        "trees_shrubs": ["tree", "pine", "bush", "shrub", "plant", "fern"],
        "props_barriers": ["barrier", "fence", "lamp", "bollard", "sign", "barrel", "hay"],
    }.items():
        print(f"[{cat}]")
        for slug, name, cats in search_assets(models, kws, 8):
            print(f"  {slug}: {name} ({cats})")

if __name__ == "__main__":
    main()
