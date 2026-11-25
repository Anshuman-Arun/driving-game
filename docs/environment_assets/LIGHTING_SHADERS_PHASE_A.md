# Phase A Lighting, Terrain, Asphalt & Foliage Shaders (`lighting-shaders`)

## 1. Daylight, Sky Alignment & Post-Processing (`scripts/integration/aster_valley_environment.gd`)
- **HDRI & Sun Alignment:** Aligned `env.sky_rotation = Vector3(0.0, 0.45, 0.0)` (`kloofendal_48d_partly_cloudy_puresky`, sun elevation `48.0°`) with `DirectionalLight3D` (`rotation = (-48.0°, -59.9°, 0.0)`, WSW afternoon key light) so sky reflections/IBL and directional shadows share one physical sun disc.
- **Contact Shadows & SSAO:**
  - Enabled `ssao_enabled = true` (`radius = 1.15`, `intensity = 1.35`, `power = 1.6`, `detail = 0.55`, `horizon = 0.06`, `sharpness = 0.98`, `light_affect = 0.15`) to ground trees, undergrowth, guardrails, and vehicle tires/underbody.
  - Kept `ssil_enabled = false` for 3440×1440 performance headroom.
  - Set `light_angular_distance = 0.72°` for natural soft shadow penumbras and tuned 4-split cascades (`max_distance = 360.0`, `split_1 = 0.048`, `split_2 = 0.17`, `split_3 = 0.46`, `shadow_bias = 0.018`, `shadow_normal_bias = 0.65`, `shadow_blur = 1.05`).
- **Tonemapping & Atmosphere:** Calibrated AgX (`tonemap_exposure = 1.04`, `tonemap_white = 6.5`), `ambient_light_energy = 0.56`, subtle exponential aerial perspective (`fog_density = 0.00038`, `fog_aerial_perspective = 0.46`, `fog_sun_scatter = 0.28`), and `use_debanding = true`.
- **Render Scale & Presets (`apply_quality`):**
  - Native 100% (`medium` / `high`): `scaling_3d_scale = 1.0`, `SCALING_3D_MODE_BILINEAR`, `use_taa = true` on Forward+ (`MSAA_2X` on `high`).
  - 75% Internal Scale (`low`, `scaled`, `performance`): `scaling_3d_scale = 0.75`, `SCALING_3D_MODE_FSR2`, `fsr_sharpness = 0.2`.

## 2. Clean Neutral-Gray Asphalt & Road Verge
- **Acquired CC0 Textures (`assets/forza_env/textures/clean_asphalt/`):** Poly Haven `clean_asphalt` (2K, CC0, Dimitrios Savva, `albedo.jpg` source SHA-256 `8531aa831e6346e7d5a20711454a32588f56013de41156b18cce30bb4c6edcf5`).
- **Road & Junction Shaders (`road_asphalt_forza.gdshader`, `road_junction_asphalt_forza.gdshader`):** Calibrated `asphalt_tint = (1.26, 1.27, 1.29)` for clean neutral-gray alpine tarmac across both road strips and junction pads, subtle tire wear (`0.90`), mild repair variation, and crisp derivative-AA lane markings.
- **Road Shoulder (`road_shoulder_forza.gdshader` + `farm_soil` / `grass_ground`):** Replaced the dark `brown_mud_03` ribbon with world-space turf/soil mottling (`58–94%` grass encroachment matched to `terrain_forza.gdshader`) to eliminate the hard shoulder seam.

## 3. Terrain Ground Cohesion (`terrain_forza.gdshader` + `terrain_forza.tres`)
- **Acquired CC0 Textures:**
  - `assets/forza_env/textures/grass_ground/` — Poly Haven `grass_ground` (2K, CC0, Charlotte Baglioni, `diff` SHA-256 `711341bcef8c1e7317a70e6bb39e1e63878e3946e26c93b78e3835f26bd26620`).
  - `assets/forza_env/textures/forest_ground_06/` — Poly Haven `forest_ground_06` (2K, CC0, Charlotte Baglioni, `diff` SHA-256 `453311543d952b75116f6f40f92d229173ea7df0b74240ad1a44d3f83ee8a87b`).
  - `assets/forza_env/textures/farm_soil/` — Poly Haven `farm_soil` (2K, CC0, Amal Kumar, `diff` SHA-256 `5b2aa6ce68bf82c1ae3b3433eeefc2a4ec6aae441740b6fbc42db16a2e2597b0`).
- **Color Calibration:** Eliminated saturated lime/yellow carpet; matched `grass_tint = (0.60, 0.72, 0.54)` on `grass_ground` to W3's `grass_medium_01` root palette (`~[0.26, 0.27, 0.13]`) and strengthened Cedar Woods `forest_ground_06` + `leaf_litter` woodland floor (`forest_tint = (0.84, 0.80, 0.72)`).

## 4. Foliage Shaders & Wind (`assets/environment_realism/shaders/` + `assets/valley_art/`)
- `tree_bark.gdshader` (Surface 0 opaque PBR): anchored roots (`COLOR.a = 0`), world-space travelling gust + `INSTANCE_CUSTOM` phase/stiffness, moss/root AO.
- `tree_foliage.gdshader` (Surface 1 cutout + `BACKLIGHT`): synchronized branch sway with `tree_bark.gdshader` + outer tip flutter, blended crown normals (`0.62`), mip-compensating `ALPHA_SCISSOR_THRESHOLD` (`0.42 -> 0.22`).
- `undergrowth_grass.gdshader` (early-Z opaque 3D grass blades, zero alpha discard): travelling wind wave, root-to-terrain color blend, distance sink-to-ground (`fade_start_m..fade_end_m`), `BACKLIGHT`.
- `undergrowth_cutout.gdshader` (alpha cutout for `fern`, `wildflower`, `tall_verge` seed heads, and LOD1 cards): same contract + mip-aware `ALPHA_SCISSOR_THRESHOLD`.
- Updated `assets/valley_art/{foliage_cards,vegetation}.gdshader` for legacy/rock/leaf fallback coherence.
