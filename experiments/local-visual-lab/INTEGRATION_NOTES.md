# Integration Recommendations for Aster Valley Main Game

Based on real Godot 4.7.2 Forward+ measurements on an NVIDIA GeForce RTX 4050 Laptop GPU (`1920 × 1080`), here are concrete, evidence-backed recommendations to port into the main game's Core, World, and Art branches after integration.

---

## 1. Recommended Default Graphics Baseline (`Balanced` Tier)

Target **60 FPS @ 1080p** with **~6.5 ms environment GPU budget**, leaving ~10 ms for vehicles, traffic, physics, and UI:

- **Tonemapper:** `Environment.TONE_MAPPER_AGX` (`exposure = 1.05`, `white = 6.0`) with subtle contrast (`1.06`) and saturation (`1.08`). AgX prevents late-afternoon sky and headlight blowouts far better than Linear or Filmic.
- **Sky & Sun:** `PhysicalSkyMaterial` (`radiance_size = 256`, `turbidity = 4.8`, `rayleigh = 2.0`, `mie = 0.0065`) + single `DirectionalLight3D` at a raking ~22° golden-hour angle.
- **Shadows:** `SHADOW_PARALLEL_4_SPLITS`, `max_distance = 220 m`, `blend_splits = true`, `atlas = 4096`, `shadow_normal_bias = 1.6`.
- **Anti-Aliasing:** `MSAA 2× + TAA On`. Visually eliminates road-line and pine-needle shimmer at a fraction of MSAA 4×'s VRAM/bandwidth cost.
- **Post-Processing:** Keep **SSAO** (`radius = 1.6`, `intensity = 1.35`), **SSR** (`32 steps` for lake & wet-asphalt reflections), and **Glow** (`threshold = 1.15`, subtle bloom for car headlights/taillights).
- **Atmosphere:** Use **Exponential Distance Fog with `fog_aerial_perspective = 0.65–0.68`** instead of Volumetric Fog on Balanced/Performance. It delivers strong mountain depth layering at near-zero GPU cost.

---

## 2. Features to Gate Behind Optional High/Photo-Mode Presets

- **Avoid SDFGI by default in fast driving gameplay:** Measured on RTX 4050 Laptop GPU, SDFGI + SSIL + Volumetric Fog added **+10–12 ms GPU**, **+562 MB VRAM**, and dropped moving-camera 1% low FPS to **30.7 FPS** due to cascade updates. For an open-world racing game moving at 150–250 km/h, `PhysicalSkyMaterial` ambient + SSAO + baked/lightmap or regional `ReflectionProbe`s will feel far smoother.
- **Volumetric Fog (`VP2` god-rays):** Looks striking in forested corridors (`high_vp2_pine_corridor.png`), so consider offering it as an independent **Volumetric Fog toggle** (without forcing SDFGI/SSIL) for players with extra GPU headroom.

---

## 3. World & Art Pipeline Recommendations (`feat/worldgen` & `feat/art-pipeline`)

- **Road Shader & UV Contract:** Authoring roads with `UV.x ∈ [0, 1]` across total paved + shoulder width and `UV.y` in meters along the spline enables procedural tire-wear roughness tracks, worn double-yellow/edge markings, and feathered gravel shoulders with **zero texture tiling seams** (`shaders/asphalt_road.gdshader`).
- **Terrain Normal Detail Without Screen-Space Artifacts:** Avoid `dFdx/dFdy` procedural bump mapping on steep cliffs and distant terrain (it causes severe stippling at grazing angles). Use distance-attenuated analytical or texture-sampled world-space normals (`shaders/terrain.gdshader`).
- **Distant Backdrop Ring:** Keep playable Terrain3D collision strictly within the 2×2 km envelope and surround it with a lightweight visual-only distant mountain ring (`cast_shadow = OFF`) blended with aerial-perspective fog.
- **Foliage & Grass Instancing (`MultiMeshInstance3D`):**
  - Batch trees, rocks, and grass per-region/chunk into `MultiMeshInstance3D` with `use_custom_data = true` for per-instance color/wind variation.
  - Disable shadow casting on grass (`cast_shadow = OFF`) and set `visibility_range_end = 120–140 m` with `VISIBILITY_RANGE_FADE_SELF`.
  - Scale grass density cleanly via `multimesh.visible_instance_count` (25% / 60% / 100%) so preset changes are instantaneous with zero scene reload.
- **Alpine Water (`Eastwater Lake`):** Analytical multi-directional waves blended with smooth dual-scrolling noise gradients (`shaders/lake_water.gdshader`) avoid parallel wave striping and grazing-angle aliasing while keeping water rendering under ~0.5 ms.
- **Vehicle Materials (`Vela GT` reference):** Metallic clearcoat (`metallic = 0.78`, `roughness = 0.17`, `clearcoat = 1.0`, `clearcoat_roughness = 0.06`) paired with emissive headlight/taillight bars (`emission_energy = 2.6–3.2`) reads clearly at both close and mid-distance under AgX + subtle Glow.

---

## 4. Reusable Files Ready to Port Later

When the main game is ready for visual polish (P2+), the following self-contained assets from `experiments/local-visual-lab/` can be adapted directly:
- `scripts/graphics_presets.gd` — 3-tier preset + runtime feature toggle controller
- `shaders/asphalt_road.gdshader` — weathered road + markings + tire-track roughness shader
- `shaders/lake_water.gdshader` — alpine lake water shader (depth tint, foam, smooth ripples)
- `shaders/grass_blade.gdshader` & `shaders/foliage_pine.gdshader` — wind-animated backlit foliage shaders
- `scripts/benchmark_runner.gd` — deterministic multi-viewpoint + flythrough GPU benchmark harness for regression testing future PRs
