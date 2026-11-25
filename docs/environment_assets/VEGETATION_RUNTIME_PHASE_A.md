# Vegetation Runtime, Placement & Optimization — Phase A

**Owner:** W4 (`veg-runtime`)
**Scope:** Multi-species Cedar Woods 300–500 m showcase + world-wide vegetation placement, LOD/cell streaming, and shader/MultiMesh integration.

## Deliverables

1. **Deterministic Baker (`content/scenery/tools/bake_vegetation.py`)**
   - Outputs `data/world/vegetation.bin` (`STRIDE = 8` float32: `[x, y, z, yaw, scale, kind, seed, warmth]`) and `minimap.png`.
   - **Exact Vector Exclusions (`RoadClearanceModel`)**: Samples all 16 physical road corridors with `roadworks` widening + `1.35 m` shoulder, plus exact 2D convex hulls for all `turn_*` junction pads (matching `mesh_builder.gd`), bridge spans, water masks (`water_cells_v1.json` + `roadworks.waters`), buildings, `SceneryRuntime` props, and `race_gate_reservations_v1.json`. Verified `0` placements inside road/shoulder/junction bounds (`min edge_dist = 0.18 m`, `min bridge_dist = 6.06 m`).
   - **Cedar Woods Showcase (`Vector3(-870, 0, -154)` corridor)**:
     - Multi-species canopy (`conifer_tall`, `conifer_medium`, `broadleaf_oak`, `broadleaf_birch`) with minimum `4.7 m` trunk separation and organic grove/clearing modulation.
     - Multi-tier understory (`sapling_conifer`, `shrub_woodland`, `fern`, `wildflower`, slope-grounded `rock_moss`).
     - Distance-banded grass gradient: dense `0.35–0.55 m` roadside verge strips (`grass_short`, `grass_meadow`, `grass_tall_verge`), `0.74 m` near band (`0–35 m`), `1.65 m` mid band (`35–90 m`), and smooth fade out (`90–150 m`).
   - **Total baked placements:** `274,985` across 12 species (`46,391` within 150 m of `(-870, -154)`).

2. **Runtime Streaming & LOD (`scripts/integration/valley_vegetation.gd`)**
   - Loads all 28 GLBs from `assets/environment_realism/{trees,undergrowth}/` and binds W5's shaders (`tree_bark.gdshader`, `tree_foliage.gdshader`, `undergrowth_grass.gdshader`, `undergrowth_cutout.gdshader`) per surface while preserving each GLB's `albedo_tex`, `normal_tex`, `roughness_tex`, and `ao_tex`.
   - Populates `MultiMesh.use_custom_data = true` (`INSTANCE_CUSTOM`: `.r` phase, `.g` stiffness, `.b` biome warmth, `.a` root AO) and `use_colors = true` with `instance_color.a = 1.0` so `COLOR.a` remains pure vertex wind flex.
   - Implements 3-tier cell streaming & LOD hysteresis:
     - **Canopy (`96 m` cells):** LOD0 → LOD1 → LOD2 with `±14 m` / `±18 m` hysteresis and distance-gated shadow casting.
     - **Mid (`64 m` cells):** `shrub_woodland` & `rock_moss` streamed with LOD0/LOD1 hysteresis.
     - **Ground (`32 m` cells):** Frame-budgeted cell creation (`MAX_BATCHES_PER_TICK = 5`, closest-first) with LOD0 (3D grass blades) → LOD1 (crossed cards) switching and shader distance sink (`fade_start_m..fade_end_m`) to avoid frame hitches and pop-in.
   - Preserves `conifer_mesh(distant)` and `broadleaf_mesh()` overrides for `SceneryRuntime` in `aster_valley_drive.gd`.

## Verification
- `bake_vegetation.py`: Verified `0` road/shoulder/junction overlaps (`min edge_dist = 0.18 m`, `min bridge_dist = 6.06 m`).
- `Godot_v4.7.2-stable_win64_console.exe --headless --path driving-game --quit`: Clean compilation, 0 script errors.
- `Godot_v4.7.2-stable_win64_console.exe --headless --path driving-game --script res://tests/core/smoke.gd`: PASS.
