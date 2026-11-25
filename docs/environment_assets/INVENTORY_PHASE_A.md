# Phase A Source Asset Inventory

- **Phase A New-Download Budget:** `1873.3 MiB / 2048 MiB` cap (`91.5%` utilized)
- **External Source Cache:** `../aster-valley-asset-source/` (outside Godot import tree)
- **Google Drive Backup Status:** **Unavailable / Pending** — Google Drive for Desktop is not mounted locally on this Windows host (only `C:\` is present; no DriveFS mount or `ASTER_ASSET_SOURCE_ROOT` configured). All verified source masters and `PROVENANCE.json` manifests are preserved intact in the local external cache.

---

## 1. Existing Staged 4K Sources (`asset_library/environment_sources/`)

All 4 staged Poly Haven CC0 4K sources (`50.6 MiB` total) were verified against their `PROVENANCE.json` SHA-256 checksums:
- All `.bin` geometry buffers and 4K `.jpg` textures (`diff`, `nor_gl`, `arm`) match `PROVENANCE.json` SHA-256 **100%**.
- The `.gltf` JSON files match `PROVENANCE.json` SHA-256 **100%** after LF normalization (Windows Git `core.autocrlf` converts `\n` to `\r\n` on checkout).

| Asset ID | Provider / License | Triangles | Mesh Objects | Bounds (m, X×Y×Z Blender) | Notes |
|---|---|---:|---:|---|---|
| `grass_medium_01` | Poly Haven (CC0-1.0) | 24,730 | 20 | `5.61 × 0.33 × 0.34` | Multi-clump grass pack |
| `grass_medium_02` | Poly Haven (CC0-1.0) | 7,842 | 12 | `1.31 × 0.43 × 0.41` | Multi-clump meadow grass |
| `fern_02` | Poly Haven (CC0-1.0) | 6,232 | 12 | `1.97 × 1.72 × 0.43` | Forest floor fern clumps |
| `celandine_01` | Poly Haven (CC0-1.0) | 8,966 | 16 | `2.24 × 0.31 × 0.19` | Wildflower / verge clusters |

---

## 2. Phase A Poly Haven 4K Models & HDRIs (`1062.9 MiB`)

Acquired via `tools/environment_assets/acquire.py` with MD5/SHA-256 and glTF 2.0 dependency verification:

| Asset ID | Kind | Res | Size (MiB) | Triangles | Bounds (m, X×Y×Z Blender) | Role |
|---|---|---|---:|---:|---|---|
| `fir_tree_01` | models | 4k | 556.7 | 6,982,937 | `18.78 × 6.51 × 18.94` | 3-variant tall conifer master (decimate/card for LOD0-2) |
| `tree_small_02` | models | 4k | 153.5 | 2,062,487 | `2.92 × 4.29 × 4.56` | Small broadleaf tree / branching reference |
| `pine_sapling_small` | models | 4k | 60.5 | 398,144 | `2.64 × 0.77 × 1.30` | Conifer sapling understory |
| `fir_sapling` | models | 4k | 58.2 | 433,021 | `2.74 × 0.83 × 1.30` | Fir sapling understory |
| `shrub_01` | models | 4k | 22.7 | 156,012 | `2.59 × 0.22 × 0.40` | Low woodland shrub |
| `shrub_02` | models | 4k | 13.4 | 27,254 | `6.57 × 2.54 × 2.55` | 4-variant woodland shrub pack |
| `shrub_03` | models | 4k | 12.6 | — | — | Shrub variant |
| `shrub_04` | models | 4k | 11.6 | — | — | Shrub variant |
| `grass_bermuda_01` | models | 4k | 15.2 | — | — | Verge/meadow grass |
| `dandelion_01` | models | 4k | 16.1 | — | — | Roadside wildflower |
| `nettle_plant` | models | 4k | 17.2 | — | — | Understory weed/plant |
| `moss_01` | models | 4k | 11.1 | — | — | Forest floor moss clump |
| `boulder_01` | models | 4k | 41.2 | 66,122 | `1.27 × 1.83 × 1.00` | Hero boulder |
| `rock_07` | models | 4k | 19.4 | 14,844 | `0.17 × 0.32 × 0.14` | Small verge/slope rock |
| `rock_moss_set_01` | models | 4k | 7.8 | — | — | Mossy rock set 1 |
| `rock_moss_set_02` | models | 4k | 9.0 | — | — | Mossy rock set 2 |
| `kloofendal_48d_partly_cloudy_puresky` | hdris | 4k | 19.7 | — | — | Daylight sky / reflection IBL |
| `qwantani_noon_puresky` | hdris | 4k | 17.0 | — | — | Noon sky / reflection IBL |

> [!NOTE]
> `pine_tree_01` was measured at `1011.2 MiB` (4K) / `936.7 MiB` (2K) via `--plan-only` due to its ~900 MiB raw glTF geometry buffer. Including it would consume ~50% of the 2048 MiB Phase A cap and crowd out ground/asphalt textures and shrubs, so it is deferred to Phase B (with `fir_tree_01`, `tree_small_02`, `pine_sapling_small`, `fir_sapling`, and `pine_bark` covering Phase A).

---

## 3. Phase A Poly Haven 2K PBR Textures (`711.6 MiB`)

4K texture sets on Poly Haven average `320–370 MiB` each (largely due to uncompressed 4K EXR/PNG displacement and normal maps). All 9 priority textures were explicitly acquired at **2K** (`--resolution 2k`) so the full road/terrain/bark set fits cleanly inside the 2048 MiB cap (`tools/environment_assets/acquire.py` was also updated with `MAP_ALIASES` to support Poly Haven's capitalized API keys `Diffuse`, `Rough`, `AO`, `Displacement`, `Mask`).

| Asset ID | Res | Size (MiB) | Maps Included | Purpose |
|---|---:|---:|---|---|
| `clean_asphalt` | 2k | 81.2 | diff, nor_gl, rough, ao, arm, disp | Neutral-gray asphalt road surface |
| `leafy_grass` | 2k | 96.3 | diff, nor_gl, rough, ao, arm, disp, opacity (Mask) | Meadow/verge grass terrain |
| `grass_ground` | 2k | 83.2 | diff, nor_gl, rough, ao, arm, disp | General grass terrain |
| `leaves_forest_ground` | 2k | 84.4 | diff, nor_gl, rough, ao, arm, disp | Forest floor leaf litter |
| `forest_ground_06` | 2k | 83.1 | diff, nor_gl, rough, ao, arm, disp | Cedar Woods forest floor |
| `mossy_rock` | 2k | 36.2 | diff, nor_gl, rough, ao, arm, disp | Rock / mossy cliff face |
| `farm_soil` | 2k | 82.4 | diff, nor_gl, rough, ao, arm, disp | Farmland / dirt shoulder |
| `sandy_gravel_02` | 2k | 82.5 | diff, nor_gl, rough, ao, arm, disp | Road shoulder / gravel |
| `pine_bark` | 2k | 82.3 | diff, nor_gl, rough, ao, arm, disp | Conifer trunk bark |

---

## 4. Complementary ambientCG CC0 Assets (`98.8 MiB`)

Poly Haven lacks broadleaf oak/birch tree 3D models. Five complementary **CC0-1.0** (`https://docs.ambientcg.com/license/`) 2K-JPG PBR materials and leaf atlases were acquired from ambientCG with `PROVENANCE.json` + archive SHA-256 verification:

| Asset ID | Kind | Res | Size (MiB) | Purpose |
|---|---|---|---:|---|
| `Bark012` | Material | 2K-JPG | 32.1 | Oak bark PBR (`broadleaf_oak`) |
| `Bark004` | Material | 2K-JPG | 27.0 | Smooth light bark PBR (`broadleaf_birch`) |
| `LeafSet016` | Atlas | 2K-JPG | 12.2 | Green oak leaf spray atlas (`broadleaf_oak`) |
| `LeafSet024` | Atlas | 2K-JPG | 14.5 | Light green broadleaf atlas (`broadleaf_birch` / shrubs) |
| `PineNeedles001` | Atlas | 2K-JPG | 13.0 | Conifer needle spray atlas (`conifer_tall` / `conifer_medium`) |

---

## 5. Inspection Tooling

- `tools/environment_assets/blender_inspect.py`: Headless Blender 4.5.10 script that imports `.gltf`/`.glb`, dumps polycount/bounds/materials/UVs/textures to `*_stats.json`, and renders a 2×2 AgX contact sheet (`front`, `side`, `three_quarter`, `top`) to `*_sheet.png`.
