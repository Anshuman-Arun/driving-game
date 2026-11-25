# Phase A Swarm Task Board — Aster Valley Environment Art Pass

- **Integration branch:** `feat/environment-realism-swarm` (branched from `feat/environment-asset-library` @ `c4ad068`, which sits on `origin/main` @ `c6602b6`)
- **Approved scope:** **Phase A ONLY** (first high-quality environmental showcase, focused on Cedar Woods 300–500 m corridor + valley-wide lighting/asphalt/terrain/foliage baseline; stop at Phase A checkpoint).
- **Hardware & Toolchain:**
  - OS: Windows 11
  - GPU: NVIDIA GeForce RTX 4050 Laptop GPU (6141 MiB VRAM, driver 592.82)
  - Engine: `Godot_v4.7.2-stable_win64_console.exe` (Forward+, on `PATH`)
  - 3D DCC: `C:\Users\anshu\AppData\Local\Programs\Blender4.5\blender-4.5.10-windows-x64\blender.exe` (Blender 4.5.10)
  - Python: `python` (Python 3.13)
  - External source cache (outside repo): `C:\Users\anshu\Documents\Coding\aster-valley-asset-source` (C:\ has ~71.5 GiB free; **Phase A new-download cap: 2 GiB / 2048 MiB**)
  - Showcase target corridor: Cedar Woods road around `Vector3(-870, 0, -154)` (300–500 m stretch) + all 5 biome reference viewpoints.
  - Display target: **3440×1440 native (100%)** and **75% internal 3D scale (2580×1080)**, keeping native HUD.

## Exclusive File Ownership & Contracts

| Role | Swarm Name | Model | Exclusive Write Paths | Must Not Touch |
|---|---|---|---|---|
| Coordinator | `coordinator` | Hydrogen 4 High | `docs/environment_assets/swarm/BOARD.md`, `docs/PROJECT_STATUS.md`, `docs/ASSET_LICENSES.md`, `scenes/free_roam/aster_valley.tscn`, `project.godot` | Specialist implementation files |
| W1 Asset Acquisition | `assets-pipeline` | Hydrogen 4 Medium | `tools/environment_assets/acquire.py`, `tools/environment_assets/blender_inspect.py`, `docs/environment_assets/INVENTORY_PHASE_A.md`, external cache `C:\Users\anshu\Documents\Coding\aster-valley-asset-source\` | `assets/**`, `scripts/**`, `content/**` |
| W2 Trees & Forest Art | `trees-art` | Hydrogen 4 High | `assets/environment_realism/trees/**`, `tools/environment_assets/build_trees.py`, `docs/environment_assets/TREES_PHASE_A.md` | `scripts/**`, `assets/forza_env/**`, `assets/valley_art/**` |
| W3 Grass & Undergrowth | `grass-art` | Hydrogen 4 High | `assets/environment_realism/undergrowth/**`, `tools/environment_assets/build_undergrowth.py`, `docs/environment_assets/UNDERGROWTH_PHASE_A.md` | `scripts/**`, `assets/forza_env/**`, `assets/valley_art/**` |
| W4 Vegetation Runtime & Placement | `veg-runtime` | Hydrogen 4 High | `scripts/integration/valley_vegetation.gd`, `scripts/integration/valley_tree_factory.gd`, `content/scenery/tools/bake_vegetation.py`, `data/world/vegetation.bin`, `docs/environment_assets/VEGETATION_RUNTIME_PHASE_A.md` | `assets/**`, `aster_valley_environment.gd`, `tests/**` |
| W5 Lighting, Surface & Foliage Shaders | `lighting-shaders` | Hydrogen 4 High | `scripts/integration/aster_valley_environment.gd`, `assets/forza_env/shaders/**`, `assets/forza_env/materials/**`, `assets/forza_env/textures/**`, `assets/valley_art/*.gdshader`, `assets/environment_realism/shaders/**`, `docs/environment_assets/LIGHTING_SHADERS_PHASE_A.md` | `valley_vegetation.gd`, `assets/environment_realism/{trees,undergrowth}/**` |
| Independent Verifier | `verifier` | Hydrogen 4 High (eval) / Medium (mechanical) | `tests/visual_realism/**`, `docs/environment_assets/swarm/QA_PHASE_A.md`, screenshots in own brain folder | Any production code or assets |

## Shared Interface Contracts (Lock Before Editing)

1. **Asset Coordinate & Mesh Contract (`trees-art`, `grass-art` -> `veg-runtime`, `lighting-shaders`):**
   - Format: `.glb` (glTF 2.0 binary), Y-up, meters, pivot at ground `(0, 0, 0)` with slight root flare extending `-0.15 m` for trees so hillside slopes never expose floating bases.
   - Tree variants in `assets/environment_realism/trees/`:
     - `conifer_tall_lod0.glb`, `conifer_tall_lod1.glb`, `conifer_tall_lod2.glb`
     - `conifer_medium_lod0.glb`, `conifer_medium_lod1.glb`, `conifer_medium_lod2.glb`
     - `broadleaf_oak_lod0.glb`, `broadleaf_oak_lod1.glb`, `broadleaf_oak_lod2.glb`
     - `broadleaf_birch_lod0.glb`, `broadleaf_birch_lod1.glb`, `broadleaf_birch_lod2.glb`
     - `sapling_conifer_lod0.glb` (or `sapling_lod0.glb` / `lod1.glb`)
     - Each tree GLB uses clear material slot naming (`bark` vs `canopy` / `foliage`) OR separate surfaces (Surface 0 = bark, Surface 1 = foliage cards) so `valley_vegetation.gd` / `lighting-shaders` can apply `ShaderMaterial` cleanly without breaking bark vs leaf textures. **Contract: Surface 0 = bark (opaque PBR), Surface 1 = foliage cards/twigs (alpha cutout/foliage shader) — OR embedded materials with `bark` / `foliage` names that `veg-runtime` can override or keep.**
   - Undergrowth variants in `assets/environment_realism/undergrowth/`:
     - `grass_short_lod0.glb` / `lod1.glb` (5–15 cm turf clump)
     - `grass_meadow_lod0.glb` / `lod1.glb` (15–40 cm meadow grass)
     - `grass_tall_verge_lod0.glb` / `lod1.glb` (40–80 cm roadside verge)
     - `fern_lod0.glb` / `lod1.glb` (derived from `fern_02`)
     - `wildflower_lod0.glb` / `lod1.glb` (derived from `celandine_01`)
     - `shrub_woodland_lod0.glb` / `lod1.glb` (woodland understory shrub/sapling)
   - **Vertex & Custom Data Contract (`lighting-shaders` <-> `trees-art`, `grass-art`, `veg-runtime`):**
     - `COLOR.a` (vertex color alpha) OR `UV2.y` encodes wind flex weight (`0.0` at trunk/root anchor, `1.0` at tips/outer canopy) — never put wind flex in `INSTANCE_CUSTOM` in a way that collides with MultiMesh tint!
     - MultiMesh `use_colors = true` carries per-instance RGB tint (`COLOR.rgb` in shader).
     - MultiMesh `use_custom_data = true` carries `INSTANCE_CUSTOM`:
       - `.r` = per-instance normalized random phase/seed (`0..1`)
       - `.g` = per-instance scale / wind stiffness modifier (`0..1`)
       - `.b` = local terrain/biome warmth or dryness blend (`0..1`)
       - `.a` = root AO / ground tint factor (`0..1`)
     - Wait: verify in Godot 4.7.2 `MultiMesh` shaders: `INSTANCE_CUSTOM` is available in `vertex()` and can pass `varying vec4 instance_data` to `fragment()`, while `COLOR` in `vertex()` carries vertex color (`COLOR.a` = flex weight, `COLOR.rgb` = vertex AO/tint) and `INSTANCE_COLOR` (wait: in Godot MultiMesh with `use_colors = true`, `COLOR` in `vertex()` is `vertex_color * instance_color`!). Therefore: keep vertex color RGB = `(1,1,1)` (or root AO baked into vertex RGB) and vertex color A = wind flex weight (`0..1`), and put per-instance tint or variation in `INSTANCE_CUSTOM` OR keep `instance_color` alpha = `1.0` so `COLOR.a` remains pure vertex wind flex!

2. **GPU Serialization Rule:**
   - **NEVER run Godot graphical captures or benchmarks concurrently.** `verifier` owns all GPU captures and 3440×1440 benchmarks. Other workers may run quick headless Godot `--import` / `--check-only` only when no GPU run is active, or coordinate on the board.

## Task Tracker (Phase A)

| ID | Task | Owner | Status | Notes |
|---|---|---|---|---|
| A0 | Preflight, branch `feat/environment-realism-swarm`, BOARD.md | `coordinator` | `done` | Branched from `c4ad068` |
| A1 | Inspect 4 staged sources, acquire <=2 GiB 4K core+foliage+trees+asphalt+HDRI to external cache, Drive archive check, Blender contact sheets | `assets-pipeline` | `pending` | |
| A2 | Author/convert 4–5 realistic tree species + 3 LODs + bark/foliage sheets | `trees-art` | `pending` | |
| A3 | Author/convert 5–6 grass/fern/wildflower/shrub variants + LODs + sheets | `grass-art` | `pending` | Starts immediately with `asset_library/environment_sources` |
| A4 | Foliage shader contract, daylight/sun/SSAO/AgX calibration, clean neutral-gray asphalt & matched terrain | `lighting-shaders` | `pending` | |
| A5 | Vegetation runtime LOD/culling/MultiMesh custom data + Cedar Woods 300–500 m dense layered bake | `veg-runtime` | `pending` | Coordinates contract with W2/W3/W5 |
| A6 | Baseline captures, 3440×1440 native & 75% benchmark, regression suite, Cycle 1 & Cycle 2 visual critique | `verifier` | `pending` | Runs baseline immediately |
