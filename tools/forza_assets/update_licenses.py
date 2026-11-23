"""Update assets/forza_env/ASSET_LICENSES_FORZA.json and docs/ASSET_LICENSES.md."""
import datetime
import json
from pathlib import Path

ROOT = Path(r"c:\Users\anshu\Documents\Coding\Driving-Game\driving-game")
META_PATH = ROOT / "assets" / "forza_env" / "ASSET_LICENSES_FORZA.json"
MD_PATH = ROOT / "docs" / "ASSET_LICENSES.md"


def main():
    meta = json.loads(META_PATH.read_text(encoding="utf-8"))
    today = datetime.date.today().isoformat()
    existing_ids = {a["asset_id"] for a in meta["assets"]}
    if "tex_water_normal" not in existing_ids:
        meta["assets"].append({
            "asset_id": "tex_water_normal",
            "source_url": "local://tools/forza_assets/generate_water_normal.py",
            "author": "Project procedural FFT generator",
            "license": "CC0",
            "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
            "local_files": ["assets/forza_env/textures/water/normal.png"],
            "resolution": "2048x2048",
        })
    if "scenery_procedural_models" not in existing_ids:
        meta["assets"].append({
            "asset_id": "scenery_procedural_models",
            "source_url": "local://tools/forza_assets/{gen_nature,gen_roadside,gen_buildings}.py",
            "author": "Project procedural glTF/GLB generator (embedding Poly Haven CC0 PBR textures)",
            "license": "CC0",
            "license_url": "https://polyhaven.com/license",
            "local_files": [
                "assets/curated/models/environment/pine_tree_lod0.glb",
                "assets/curated/models/environment/pine_tree_lod1.glb",
                "assets/curated/models/environment/broadleaf_tree.glb",
                "assets/curated/models/environment/shrub_cluster.glb",
                "assets/curated/models/environment/boulder.glb",
                "assets/curated/models/environment/rock_cluster.glb",
                "assets/curated/models/environment/guardrail_4m.glb",
                "assets/curated/models/environment/concrete_barrier.glb",
                "assets/curated/models/environment/wood_fence.glb",
                "assets/curated/models/environment/street_lamp.glb",
                "assets/curated/models/environment/warning_sign.glb",
                "assets/curated/models/environment/bollard.glb",
                "assets/curated/models/environment/hay_bale.glb",
                "content/scenery/models/town_house.gltf",
                "content/scenery/models/barn.gltf",
                "content/scenery/models/garage.gltf",
                "content/scenery/models/windmill.gltf",
                "content/scenery/models/stone_arch.gltf",
                "content/scenery/models/overlook.gltf",
                "content/scenery/models/pier.gltf",
                "content/scenery/models/quarry_hopper.gltf",
            ],
            "notes": "All models use CC0 Poly Haven PBR textures & match content/scenery/manifest.json footprints.",
        })

    vehicle_entries = [
        {
            "asset_id": "car_vela_gt",
            "source_url": "https://raw.githubusercontent.com/achrefelouafi/GrassSystemThreeJS/main/public/porsche_911.glb",
            "author": "achrefelouafi/GrassSystemThreeJS contributors",
            "license": "MIT / CC-BY 4.0",
            "license_url": "https://creativecommons.org/licenses/by/4.0/",
            "local_files": ["assets/curated/models/vehicles/vela_gt.glb"],
            "notes": "Vela GT hero sports car.",
        },
        {
            "asset_id": "car_orion_rs",
            "source_url": "https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/CarConcept/glTF-Binary/CarConcept.glb",
            "author": "Eric Chadwick / Darmstadt Graphics Group GmbH (based on CC0 public domain concept car by Unity Fan)",
            "license": "CC-BY 4.0 International",
            "license_url": "https://creativecommons.org/licenses/by/4.0/",
            "local_files": ["assets/curated/models/vehicles/orion_rs.glb"],
            "notes": "Orion RS sports coupe.",
        },
        {
            "asset_id": "car_kestrel_xr",
            "source_url": "https://raw.githubusercontent.com/ionathansideras/3d-configurator/main/public/models/porsche.glb",
            "author": "ionathansideras/3d-configurator contributors",
            "license": "MIT / CC-BY",
            "license_url": "https://github.com/ionathansideras/3d-configurator",
            "local_files": ["assets/curated/models/vehicles/kestrel_xr.glb"],
            "notes": "Kestrel XR supercar (Porsche 918 Spyder Weissach).",
        },
    ]
    by_id = {a["asset_id"]: a for a in meta["assets"]}
    for ve in vehicle_entries:
        by_id[ve["asset_id"]] = ve
    meta["assets"] = list(by_id.values())

    META_PATH.write_text(json.dumps(meta, indent=2), encoding="utf-8")

    # Append/update imported Forza environment section in docs/ASSET_LICENSES.md
    orig = MD_PATH.read_text(encoding="utf-8")
    marker = "\n## Forza Fidelity Overhaul Imported Assets\n"
    if marker in orig:
        orig = orig.split(marker)[0]

    lines = [
        orig.rstrip(),
        "",
        "## Forza Fidelity Overhaul Imported Assets",
        "",
        f"Updated: {today}. Machine-readable ledger: `assets/forza_env/ASSET_LICENSES_FORZA.json`.",
        "",
        "| Asset ID | Source URL | Author | License | Local Path(s) |",
        "|---|---|---|---|---|",
    ]
    for a in meta["assets"]:
        files_preview = a["local_files"][0] if len(a["local_files"]) == 1 else f"{a['local_files'][0]} (+{len(a['local_files'])-1} more)"
        lines.append(f"| `{a['asset_id']}` | {a['source_url']} | {a['author']} | {a['license']} | `{files_preview}` |")
    lines.append("")
    MD_PATH.write_text("\n".join(lines), encoding="utf-8")
    print(f"Updated {META_PATH.relative_to(ROOT)} and {MD_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
