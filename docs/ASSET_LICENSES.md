# Asset and dependency license ledger

**Status: candidates only.** No third-party models/textures or add-ons are currently committed. Never assume GitHub availability equals reuse permission.

| Source | Intended use | License / caveat |
|---|---|---|
| [Poly Haven](https://polyhaven.com/license) | PBR asphalt, rock, earth, HDRI, models | CC0 |
| [ambientCG](https://ambientcg.com/) | Gravel, grass, rock and pavement PBR | CC0 |
| [Kenney Car Kit](https://kenney.nl/assets/car-kit) | Starter vehicles and traffic | CC0; visual style may be too simple for hero cars |
| [Kenney Racing Kit](https://kenney.nl/assets/racing-kit) | Prototype barriers and roadside props | CC0; stylized |
| [Spectral GT RS](https://github.com/JaronKBragg7337/spectral-gt-rs) | Detailed fictional sports car candidate | Project advertises CC0; inspect model, materials and rig before adopting |
| [Terrain3D](https://github.com/TokisanGames/Terrain3D) | Terrain plugin | MIT; preserve license; sample assets require separate checks |
| [Godot Road Generator](https://github.com/TheDuckCow/godot-road-generator) | Roads and lanes | MIT; preserve license; pin v0.9.5 |
| [Godot Easy Vehicle Physics](https://github.com/DAShoe1/Godot-Easy-Vehicle-Physics) | Vehicle physics controller | MIT; preserve license; pin exact tested SHA |
| [OpenCity](https://github.com/webgl-games/opencity) | Optional traffic/city reference | MIT code; do not copy third-party assets without individual verification |

## Every imported asset record
```text
asset_id:
source_url:
author:
source_file_or_pack:
license:
license_notice_url_or_local_path:
downloaded_on:
installed_at:
modified:
notes:
```

For MIT dependencies include original copyright/permission notices. Prefer CC0 for game assets; for any CC BY assets, retain complete required attribution and change notes.

**Prohibited:** ripped Forza/commercial-game files; unlicensed car meshes; copyrighted manufacturer logos/textures without rights; commercial music; entire demo packs copied without license checking. If ownership is unclear, use original procedural placeholders or omit the asset.

Before export, inventory assets/, world_data/ and addons/, write THIRD_PARTY_NOTICES.md for applicable dependencies and ensure notices are included where required.

## Forza Fidelity Overhaul Imported Assets

Updated: 2026-11-22. Machine-readable ledger: `assets/forza_env/ASSET_LICENSES_FORZA.json`.

| Asset ID | Source URL | Author | License | Local Path(s) |
|---|---|---|---|---|
| `tex_asphalt` | https://polyhaven.com/a/asphalt_02 | Rob Tuytel | CC0 | `assets/forza_env/textures/asphalt/albedo.jpg (+3 more)` |
| `tex_gravel` | https://polyhaven.com/a/sandy_gravel_02 | Dario Barresi | CC0 | `assets/forza_env/textures/gravel/albedo.jpg (+3 more)` |
| `tex_shoulder` | https://polyhaven.com/a/brown_mud_03 | Rob Tuytel | CC0 | `assets/forza_env/textures/shoulder/albedo.jpg (+3 more)` |
| `tex_grass` | https://polyhaven.com/a/forrest_ground_01 | Rob Tuytel | CC0 | `assets/forza_env/textures/grass/albedo.jpg (+3 more)` |
| `tex_forest_floor` | https://polyhaven.com/a/forest_leaves_04 | Rob Tuytel | CC0 | `assets/forza_env/textures/forest_floor/albedo.jpg (+3 more)` |
| `tex_rock` | https://polyhaven.com/a/rock_face_03 | Dario Barresi, Rico Cilliers | CC0 | `assets/forza_env/textures/rock/albedo.jpg (+3 more)` |
| `tex_shore` | https://polyhaven.com/a/coast_sand_03 | Rob Tuytel | CC0 | `assets/forza_env/textures/shore/albedo.jpg (+3 more)` |
| `tex_bark` | https://polyhaven.com/a/pine_bark | Dimitrios Savva | CC0 | `assets/forza_env/textures/bark/albedo.jpg (+3 more)` |
| `tex_wood_planks` | https://polyhaven.com/a/wood_planks | Amal Kumar | CC0 | `assets/forza_env/textures/wood_planks/albedo.jpg (+3 more)` |
| `tex_roof_slate` | https://polyhaven.com/a/roof_slates_03 | Rob Tuytel | CC0 | `assets/forza_env/textures/roof_slate/albedo.jpg (+3 more)` |
| `tex_stone_wall` | https://polyhaven.com/a/patterned_cobblestone | Rob Tuytel | CC0 | `assets/forza_env/textures/stone_wall/albedo.jpg (+3 more)` |
| `tex_corrugated_metal` | https://polyhaven.com/a/corrugated_iron | Jenelle van Heerden, Dimitrios Savva | CC0 | `assets/forza_env/textures/corrugated_metal/albedo.jpg (+3 more)` |
| `tex_hay` | https://polyhaven.com/a/thatch_roof_angled | Rob Tuytel, Dimitrios Savva | CC0 | `assets/forza_env/textures/hay/albedo.jpg (+3 more)` |
| `hdri_outdoor_sky` | https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky | Greg Zaal, Jarod Guest | CC0 | `assets/forza_env/hdri/outdoor_sky.hdr` |
| `hdri_garage_studio` | https://polyhaven.com/a/studio_small_09 | Sergej Majboroda | CC0 | `assets/forza_env/hdri/garage_studio.hdr` |
| `model_boulder_01` | https://polyhaven.com/a/boulder_01 | Rico Cilliers | CC0 | `assets/curated/models/environment/boulder.glb` |
| `model_rock_07` | https://polyhaven.com/a/rock_07 | Jenelle van Heerden | CC0 | `assets/curated/models/environment/rock_cluster.glb` |
| `tex_water_normal` | local://tools/forza_assets/generate_water_normal.py | Project procedural FFT generator | CC0 | `assets/forza_env/textures/water/normal.png` |
| `scenery_procedural_models` | local://tools/forza_assets/{gen_nature,gen_roadside,gen_buildings}.py | Project procedural glTF/GLB generator (embedding Poly Haven CC0 PBR textures) | CC0 | `assets/curated/models/environment/pine_tree_lod0.glb (+20 more)` |
| `car_vela_gt` | https://raw.githubusercontent.com/achrefelouafi/GrassSystemThreeJS/main/public/porsche_911.glb | achrefelouafi/GrassSystemThreeJS contributors | MIT / CC-BY 4.0 | `assets/curated/models/vehicles/vela_gt.glb` |
| `car_orion_rs` | https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/CarConcept/glTF-Binary/CarConcept.glb | Eric Chadwick / Darmstadt Graphics Group GmbH (based on CC0 public domain concept car by Unity Fan) | CC-BY 4.0 International | `assets/curated/models/vehicles/orion_rs.glb` |
| `car_kestrel_xr` | https://raw.githubusercontent.com/ionathansideras/3d-configurator/main/public/models/porsche.glb | ionathansideras/3d-configurator contributors | MIT / CC-BY | `assets/curated/models/vehicles/kestrel_xr.glb` |

## Interface fonts

Barlow Condensed Bold Italic and Barlow Semi Condensed SemiBold by Jeremy Tribby are bundled under the SIL Open Font License 1.1. The fonts came from the [Google Fonts Barlow families](https://github.com/google/fonts/tree/main/ofl/barlowcondensed). The [license notice](../assets/ui/fonts/OFL.txt) ships beside them.

## Valley terrain and foliage

The textures below use the [Poly Haven CC0 license](https://polyhaven.com/license) and ship in `assets/valley_art/`.

| Use | Source | Author | Local files |
|---|---|---|---|
| Meadow ground | [Leafy Grass](https://polyhaven.com/a/leafy_grass) | Charlotte Baglioni | `meadow_albedo.jpg`, `meadow_normal.jpg` |
| Woodland ground and canopy detail | [Leaves Forest Ground](https://polyhaven.com/a/leaves_forest_ground) | Dario Barresi, Dimitrios Savva | `leaf_litter_albedo.jpg` |
| Mossy cliffs | [Mossy Rock](https://polyhaven.com/a/mossy_rock) | Rob Tuytel | `moss_rock_albedo.jpg` |
| Pine branches | [Pine Tree 01](https://polyhaven.com/a/pine_tree_01) | Rico Cilliers, Rob Tuytel | `pine_cutout.png` and `pine_bough.png`, assembled from twig diffuse and alpha |
| Broadleaf canopy | [Tree Small 02](https://polyhaven.com/a/tree_small_02) | Rico Cilliers | `broadleaf_spray.png`, assembled from leaf diffuse and alpha |
| Building walls | [White Plaster 02](https://polyhaven.com/a/white_plaster_02) | Rob Tuytel | `plaster.jpg`, `plaster_normal.jpg` |
| Grass tufts | [Grass Medium 01](https://polyhaven.com/a/grass_medium_01) | Rico Cilliers, Rob Tuytel | `grass_cutout.png`, cropped and packed from diffuse and alpha |

## Premium world and garage runtime conversions

The acquired source packs retain their catalogs and SHA-256 ledgers under `assets/premium_world/`, `assets/premium_garage_world/`, and `assets/audio/recorded/`. The Windows export uses the adopted visual runtime derivatives listed here.

| Runtime files | Source and license | Changes |
|---|---|---|
| `assets/premium_runtime/{fir,fern}.glb` | [Fir Sapling Medium](https://polyhaven.com/a/fir_sapling_medium) and [Fern 02](https://polyhaven.com/a/fern_02), Poly Haven CC0 | Simplified geometry, restored the original UV-matched opacity, applied alpha scissor, and fit to existing planting scale. |
| `assets/premium_runtime/{moss_rocks,rock_face}.glb` and `cliff_*.jpg` | [Rock Moss Set 02](https://polyhaven.com/a/rock_moss_set_02) and [Rock Face 02](https://polyhaven.com/a/rock_face_02), Poly Haven CC0 | Simplified scans, selected the largest individual mossy rock, and reused the matching cliff color, OpenGL normal, and packed ARM maps. |
| `assets/premium_runtime/{village_house,village_shop,wooden_garage,hay_barn}_1.glb` | [Village House](https://tevy.dev/models/village-house), [Village Shop](https://tevy.dev/models/village-shop), [Garage](https://tevy.dev/models/garage), [Hay Barn](https://tevy.dev/models/hay-barn), tevy CC0 | Converted published lower LODs to Godot-readable GLB and fit them to existing lots. |
| `assets/premium_runtime/solace_gt.glb` and `assets/ui/dashboard/solace_gt.png` | [Electric Grand Tourer](https://tevy.dev/models/electric-gt), tevy CC0 | Decoded meshopt geometry, preserved source textures, adapted the independent wheel and caliper nodes to GEVP, and captured a runtime thumbnail. |

Source authors and package hashes are recorded in the individual ledgers. The two opacity maps have a [separate acquisition record](../assets/premium_world/alpha_fix/README.md).

## Recorded Vehicle and Environment Audio Assets

Updated: 2026-11-23. Machine-readable catalog and hash ledger: `assets/audio/recorded/payload/LICENSES_AND_HASHES.json` and `assets/audio/recorded/catalog.json`.

| Subsystem / Profile | Source URL | Author / Provenance | License | Local Path |
|---|---|---|---|---|
| `engine_vela_gt` | [supercar-engine-sound / gt3rs](https://github.com/justinagaudelli-eng/supercar-engine-sound) | Supercars67, NEW CARS 2015, Automotion Media | CC BY 3.0 | `assets/audio/recorded/payload/engines/vela_gt/*.wav` (14 loops) |
| `engine_kestrel_xr` | [supercar-engine-sound / 765lt](https://github.com/justinagaudelli-eng/supercar-engine-sound) | Hungarian Supercar Spotters, FiExhaust, Supercars67 | CC BY 3.0 | `assets/audio/recorded/payload/engines/kestrel_xr/*.wav` (12 loops) |
| `engine_orion_rs` | [supercar-engine-sound / four-cyl](https://github.com/justinagaudelli-eng/supercar-engine-sound) | Upstream field recordings | CC BY 3.0 | `assets/audio/recorded/payload/engines/orion_rs/*.wav` (6 loops) |
| `ambience_wind` | Project recorded / curated field recordings | Aster Valley audio contributors | CC0 | `assets/audio/recorded/payload/ambience/mountain_wind_bed.wav` |
| `tires_roll_gravel` | Project recorded / curated field recordings | Aster Valley audio contributors | CC0 | `assets/audio/recorded/payload/tires/roll_gravel.wav` |
| `tires_screech` | Project recorded / curated field recordings | Aster Valley audio contributors | CC0 | `assets/audio/recorded/payload/tires/screech.wav` |

