# Forward+ Graphics Overhaul Handoff Report (Swarm Pass 1)

**Target Fidelity:** Forza Horizon 6-grade visual benchmark  
**Branch:** `gfx-swarm-pass1` | **Godot Version:** 4.7.2.stable.official (Vulkan Forward+)  
**Render Verification:** 3x 1080p converged captures in `renders/`  
**Measured Performance:** 60.99 FPS (solid 60+ FPS on RTX 4050 Laptop GPU in full Aster Valley Free Roam)

---

## 1. Created & Modified Files

### Standalone Worker Deliverables (Created)
- **Worker 1 (Lighting & Sky):**
  - `assets/forza_env/materials/forza_environment.tres` (Forward+ AgX environment resource)
  - `scripts/integration/environment_config.gd` (High-perf lighting & renderer configuration helper)
- **Worker 2 (Car Grounding & Multi-Layer Automotive Paint):**
  - `shaders/car_paint.gdshader` (Dual-tone Fresnel clearcoat metallic lacquer shader, smooth micro-sheen)
  - `scenes/vehicles/under_car_contact_shadow.tscn` (Dynamic suspension-fading ground shadow scene)
  - `scripts/vehicle/under_car_contact_shadow.gd` (Procedural gradient texture & raycast grounding script)
  - `scripts/integration/car_material_spec.gd` (PBR material assignment spec for paint, glass, rubber, diffuser, lamps)
- **Worker 3 (Camera, Motion Blur & Verification):**
  - `scripts/vehicle/forza_chase_camera.gd` (Forza-style chase rig with 7.2m standard/9.6m far follow, dynamic FOV)
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
  - `scripts/integration/premium_foliage_runtime.gd` (MultiMesh manager: 25,025 instances, 216 batches, 27 cell-chunked colliders)
  - `data/world/premium_foliage.bin` (25,025 baked foliage placements)

### Orchestrator Integrated Files (Modified)
- `project.godot` (4096 shadow atlas, Soft Medium, 16x aniso, TAA + debanding, 1080p display)
- `scenes/free_roam/aster_valley.tscn` (Wired `forza_environment.tres` and calibrated raking Sun)
- `scripts/integration/aster_valley_environment.gd` (Wired `EnvironmentConfig` and PBR road/terrain materials)
- `scripts/integration/aster_valley_drive.gd` (Wired `ForzaChaseCamera`, `GuardrailSplineGenerator`, `PremiumFoliageRuntime`, selective colliders)
- `modules/scenery/src/scenery_runtime.gd` (Added 1,073 solid tree/rock colliders to scenery pipeline)

---

## 2. Key Visual & Performance Parameters

| Parameter Category | Field / Setting | Calibrated Value |
|---|---|---|
| **Directional Sun** | Orientation (Raking) | `rotation = Vector3(-0.52, -1.45, 0.0)` (~30° elevation) |
| | Color & Energy | `#FFF5E4` (warm afternoon), `energy = 2.8`, `specular = 1.0` |
| | Shadow Cascades | `PARALLEL_4_SPLITS` (splits: `0.08, 0.22, 0.52`), `blend_splits = true` |
| | Shadow Filter & Bias | `directional_shadow/size = 4096`, `soft_shadow_filter_quality = 2`, `bias = 0.04` |
| **Tonemap & Sky** | Tonemapping Mode | Filmic `AgX` (Mode 4), `exposure = 1.05`, `white = 6.0` |
| | HDRI Panorama Sky | `outdoor_sky.hdr` with `sky_rotation = Vector3(0, 0.42, 0)` (aligned with Sun) |
| **Post-Processing** | Screen-Space Ambient Occ. | `SSAO` enabled, `radius = 1.3m`, `intensity = 1.1` |
| | Anti-Aliasing | `TAA` enabled, `MSAA 3D` disabled (prevents multi-pass VRAM stall), `debanding = true` |
| | Atmospheric Depth Fog | Exponential, `density = 0.00045`, `aerial_perspective = 1.0`, `sky_affect = 0.0` |
| | HDR Bloom / Glow | Softlight blend, `intensity = 0.22`, `bloom = 0.10`, `hdr_threshold = 1.1` |
| **Automotive Paint** | Dual-Tone Fresnel Lacquer | Face-on: `#7A0A10` (deep red), Grazing: `#FF4520` (warm glow), no noise speckles |
| | Clearcoat Layer | `CLEARCOAT = 1.0`, `CLEARCOAT_ROUGHNESS = 0.05` |
| | Base Metal & Flakes | `metallic = 0.75`, `roughness = 0.22`, smooth pearlescent micro-sheen |
| **Grounding Shadow** | Chassis Decal / Quad | Procedural exponential feathered oval texture (`2.4 x 4.8m`) |
| | Dynamic Ground Clearance | `opacity = 0.85` grounded, fading to `0.0` when airborne > 0.6m |
| **Forza Chase Camera**| Follow Rig Geometry | Standard `7.2m` (ht `2.25m`), Far `9.6m` (ht `2.85m`), Close `5.4m`, Bumper exclusion |
| | Dynamic Velocity FOV | Resting `58°` scaling smoothly up to `74°` at top speed |
| | Spring-Damped Inertia | Smooth pitch squat, lateral sway trailing; camera raycast offset behind bumper |
| **Obstacle Collisions**| Solid World Colliders | 1,100+ collidable trunks/boulders (1,073 scenery + 27 cell-chunked static bodies) |
| **Road PBR & Verge** | Macro Anti-Tiling Noise | Roughness bounded to `[0.35, 0.85]`; dual bitumen wheel tracks; dirt skirt |
| **Spline Guardrail** | Tangent-Parallel Alignment | Continuous Catmull-Rom spline, lateral offset `4.75m`, posts raycast-grounded |
| **Terrain & Foliage** | Triplanar Cliff Strata | World-space slope threshold `0.65`, strata strength `0.16`, 2K Poly Haven rock PBR |
| | 3-Tier MultiMesh Scatter | 25,025 instances across 216 batches; primitives reduced from 856M to 1.8M (61 FPS) |

---

## 3. Playable & Verification Commands

### Playable Live Free Roam Command
```powershell
& "C:\Users\anshu\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\anshu\Documents\Coding\Driving-Game\driving-game" "res://scenes/free_roam/aster_valley.tscn"
```

### Full Game Shell Command (Dashboard / Garage / Free Roam)
```powershell
& "C:\Users\anshu\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe" --path "C:\Users\anshu\Documents\Coding\Driving-Game\driving-game"
```

### Deterministic Screenshot Verification Command
```powershell
& "C:\Users\anshu\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe" --rendering-driver vulkan --path "C:\Users\anshu\Documents\Coding\Driving-Game\driving-game" -s tools/capture_shots.gd
```
Outputs: `driving-game/renders/shot_1_chase.png`, `shot_2_low_rear_angle.png`, `shot_3_wide_road_hills.png`.
