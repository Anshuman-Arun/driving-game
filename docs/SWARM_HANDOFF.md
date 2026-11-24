# Forward+ Graphics Overhaul Handoff Report (Swarm Pass 1)

**Target Fidelity:** Forza Horizon 6-grade visual benchmark  
**Branch:** `gfx-swarm-pass1` | **Godot Version:** 4.7.2.stable.official (Vulkan Forward+)  
**Render Verification:** 3x 1080p converged captures in `renders/`

---

## 1. Created & Modified Files

### Standalone Worker Deliverables (Created)
- **Worker 1 (Lighting & Sky):**
  - `assets/forza_env/materials/forza_environment.tres` (Forward+ AgX environment resource)
  - `scripts/integration/environment_config.gd` (Static lighting & renderer configuration helper)
- **Worker 2 (Car Grounding & Multi-Layer Automotive Paint):**
  - `shaders/car_paint.gdshader` (Dual-tone Fresnel clearcoat metallic lacquer shader)
  - `scenes/vehicles/under_car_contact_shadow.tscn` (Dynamic suspension-fading ground shadow scene)
  - `scripts/vehicle/under_car_contact_shadow.gd` (Procedural gradient texture & raycast grounding script)
  - `scripts/integration/car_material_spec.gd` (PBR material assignment spec for paint, glass, rubber, diffuser, lamps)
- **Worker 3 (Camera, Motion Blur & Verification):**
  - `scripts/vehicle/forza_chase_camera.gd` (Forza-style low/tight chase camera rig with spring damping)
  - `shaders/speed_radial_blur.gdshader` (Screen-space radial speed blur with hero car mask)
  - `tools/capture_shots.gd` (Deterministic 3-bookmark CLI capture harness)
- **Worker 4 (Road PBR, Shoulders & Guardrails):**
  - `shaders/asphalt_road.gdshader` (PBR road shader with dual wheel wear, anti-tiling macro noise, verge blend)
  - `assets/forza_env/materials/road_asphalt_pbr.tres` (ShaderMaterial wired with PBR textures)
  - `modules/world_runtime/src/guardrail_spline_generator.gd` (Continuous spline-parallel grounded guardrail generator)
- **Worker 5 (Terrain Triplanar & Foliage Scatterer):**
  - `shaders/terrain_triplanar.gdshader` (World-space triplanar cliff strata and stochastic meadow blend)
  - `assets/forza_env/materials/terrain_triplanar_pbr.tres` (Material wired with PR #30 Poly Haven 2K rock textures)
  - `tools/foliage_scatter.gd` (Multi-tier GPU foliage scatter baking tool)
  - `scripts/integration/premium_foliage_runtime.gd` (Runtime MultiMesh manager with 3 foliage layers & LOD culling)
  - `data/world/premium_foliage.bin` (25,025 baked foliage placements)

### Orchestrator Integrated Files (Modified)
- `project.godot` (Configured 8K shadow atlas, Soft High filtering, 16x aniso, TAA + MSAA 4x, debanding, 1080p display)
- `scenes/free_roam/aster_valley.tscn` (Wired `forza_environment.tres` and calibrated raking Sun)
- `scripts/integration/aster_valley_environment.gd` (Wired `EnvironmentConfig` and PBR road/terrain materials)
- `scripts/integration/aster_valley_drive.gd` (Integrated `ForzaChaseCamera`, `GuardrailSplineGenerator`, `PremiumFoliageRuntime`)
- `scripts/integration/curated_car_visual.gd` (Wired `CarMaterialSpec` automotive materials and dynamic contact shadow)

---

## 2. Key Visual Parameters

| Parameter Category | Field / Setting | Calibrated Value |
|---|---|---|
| **Directional Sun** | Orientation (Raking) | `rotation = Vector3(-0.52, -1.45, 0.0)` (~30° elevation) |
| | Color & Energy | `#FFF5E4` (warm afternoon), `energy = 2.8`, `specular = 1.0` |
| | Shadow Cascades | `PARALLEL_4_SPLITS` (splits: `0.08, 0.22, 0.52`), `blend_splits = true` |
| | Shadow Filter & Bias | `directional_shadow/size = 8192`, `soft_shadow_filter_quality = 3`, `bias = 0.04`, `blur = 2.0` |
| **Tonemap & Sky** | Tonemapping Mode | Filmic `AgX` (Mode 4), `exposure = 1.05`, `white = 6.0` |
| | HDRI Panorama Sky | `outdoor_sky.hdr` with `sky_rotation = Vector3(0, 0.42, 0)` (aligned with Sun) |
| **Post-Processing** | Screen-Space Ambient Occ. | `SSAO` enabled, `radius = 1.5m`, `intensity = 1.3` |
| | Screen-Space Indirect Light | `SSIL` enabled, `intensity = 0.45` |
| | Screen-Space Reflections | `SSR` enabled, `max_steps = 64`, `depth_tolerance = 0.2` |
| | Global Illumination (SDFGI) | `SDFGI` enabled, `cascades = 6`, `y_scale = 50%` |
| | Atmospheric Depth Fog | Exponential, `density = 0.00045`, `aerial_perspective = 1.0`, `sky_affect = 0.0` |
| | HDR Bloom / Glow | Softlight blend, `intensity = 0.26`, `bloom = 0.12`, `hdr_threshold = 1.1` |
| **Automotive Paint** | Dual-Tone Fresnel Lacquer | Face-on: `#7A0A10` (deep red), Grazing: `#FF4520` (warm metallic glow) |
| | Clearcoat Layer | `CLEARCOAT = 1.0`, `CLEARCOAT_ROUGHNESS = 0.05` |
| | Base Metal & Flakes | `metallic = 0.75`, `roughness = 0.22`, `flake_scale = 240.0`, `flake_intensity = 0.45` |
| **Grounding Shadow** | Chassis Decal / Quad | Procedural exponential feathered oval texture (`2.4 x 4.8m`) |
| | Dynamic Ground Clearance | `opacity = 0.85` grounded, fading to `0.0` when airborne > 0.6m |
| **Forza Chase Camera**| Follow Rig Geometry | Height `1.35m`, distance `4.2m` (hero car occupies 20–25% screen width) |
| | Dynamic Velocity FOV | Resting `52°` scaling smoothly up to `70°` at 60 m/s (216 km/h) |
| | Spring-Damped Inertia | Longitudinal braking/squat pitch compression; lateral drift trailing |
| **Road PBR Shader** | Macro Anti-Tiling Noise | Roughness bounded to `[0.35, 0.85]`; dual bitumen wheel tracks |
| | Lane Markings & Verge | Weathered `#CFCFCF` edge lines, highway yellow center, organic dirt edge blend |
| **Spline Guardrail** | Tangent-Parallel Alignment | Continuous Catmull-Rom spline, lateral offset `4.75m`, posts raycast-grounded |
| **Terrain & Foliage** | Triplanar Cliff Strata | World-space slope threshold `0.65`, strata strength `0.16`, 2K Poly Haven rock PBR |
| | 3-Tier MultiMesh Scatter | 25,025 GPU instances (4,950 conifer canopy, 6,651 understory, 13,424 verge grass) |

---

## 3. Asset Gaps & Fallbacks

1. **4K Asphalt Source Textures (`clean_asphalt`, `road_damaged_clean`):**
   - Source normal maps from Poly Haven exceeded 90 MB and were excluded from PR #30.
   - Handled cleanly via `@export` fallback slots in `road_asphalt_pbr.tres` using existing 2K PBR textures (`assets/forza_env/textures/asphalt/`) modulated by procedural macro noise.
2. **Dense Tree Mesh Geometry (`pine_tree_01`, `tree_small_02`):**
   - Source raw geometries exceeded game budget (>900 MB).
   - Extracted verified 2K PBR bark/twig maps and bound them to optimized curated tree meshes in `PremiumFoliageRuntime`.
3. **No Unresolved Errors:**
   - GDScript syntax checks and shader compilation: **0 errors**.
   - Physics driving, raycast suspension, and collisions: **100% preserved**.

---

## 4. Execution & Playable Commands

### Playable Live Free Roam Command
To boot directly into Aster Valley Free Roam with full Forward+ graphics, player car, and chase camera:

```powershell
& "C:\Users\anshu\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\anshu\Documents\Coding\Driving-Game\driving-game" "res://scenes/free_roam/aster_valley.tscn"
```

To launch the full game shell (dashboard / garage selection / free roam):

```powershell
& "C:\Users\anshu\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\anshu\Documents\Coding\Driving-Game\driving-game"
```

### Deterministic Verification Command
To re-run the 3-bookmark 1080p Forward+ capture suite:

```powershell
& "C:\Users\anshu\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --rendering-driver vulkan --path "C:\Users\anshu\Documents\Coding\Driving-Game\driving-game" --script res://tools/capture_shots.gd
```

Outputs:
- `driving-game/renders/shot_1_chase.png` (Forza chase angle, dynamic FOV, road PBR, contact shadow)
- `driving-game/renders/shot_2_low_rear_angle.png` (Low rear 3/4 angle, dual-tone clearcoat, tire & diffuser PBR)
- `driving-game/renders/shot_3_wide_road_hills.png` (Elevated panoramic view, grounded guardrails, triplanar cliffs, depth fog)
