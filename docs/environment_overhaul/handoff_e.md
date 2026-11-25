# Agent E — lighting and rendering handoff

## Scope and status

Base: `67023539e56e5e80d5efcd3f3239be9650c6f462` (verified identical to main at branch creation). Branch: `feat/env-e-rendering`. No production wiring, global project settings, camera, car, shader, asset, physics, save, workflow or other-agent edits. Original implementation code only; no new external assets or dependencies. Headless and GPU verification are distinct gates.

## Live chain at the pinned base

- `scenes/free_roam/aster_valley.tscn` supplies WorldEnvironment and Sun, but the serialized sun energy 2.8/distance 450 m are not the active driving values. `aster_valley_drive.gd:_ready` invokes `ValleyEnvironment.apply_environment(self)` -> `EnvironmentConfig.apply_to_root` -> `apply_to_scene`. `get_or_create_environment` duplicates `forza_environment.tres` (existing HDR panorama) or creates a procedural fallback. The older `aster_valley_environment.gd:build_environment/configure_sun` helpers are not the live entry point.
- Actual baseline: sun rotation (-0.66,-1.96,0) rad, warm (1,.94,.82), energy 1.92, specular .78, angular distance .62 degrees; four blended cascades .08/.22/.52, 175/270/350 m Low/Medium/High, bias .027, normal bias .64, blur 1.25. HDR sky rotates .42 rad; reflection source SKY. AgX (loaded resource or fallback); exposure .96; color ambient (.61,.72,.90), energy .62, sky contribution .68. Existing fog density .00029, aerial perspective .44; saturation 1.12, contrast 1.09.
- Low: 85% 3D scale, FXAA, 1024 directional shadow atlas, no glow/AO/SSR/SSIL/SDFGI. Medium: native/TAA Forward+, 2048 atlas, glow .20/.045 bloom, AO off. High: native/TAA/deband, 4096 atlas, AO radius 1.3/intensity .82 and glow .24/.055 bloom. Ultra enables SSAO/SSIL/SSR and 8192 atlas; intentionally not a candidate preset. Existing quality initialization changes global RenderingServer shadow atlas/filter; root setter invokes live environment/sun and vegetation updates. Candidate never calls those helpers or changes any viewport/global setting. Camera-specific exposure overrides, if added in future, need separate coordinator review.
- `curated_car_visual.gd:_finish_source_materials` maps exact source CarPaint surfaces on Senna/Aventador to `CarMaterialSpec.create_car_paint` with flake .021, metallic .41, roughness .32, clearcoat .60, clearcoat roughness .20. Existing shader samples original texture/normal and uses PBR clearcoat. Keep glazing, tire, carbon, cabin and lamp materials untouched. Existing HDR reflections remain even without SSR. SSR is a whole-environment screen-space effect (not a per-paint switch); local comparison must use a dedicated preview world, not treat it as selective per-object SSR. Missing offscreen reflection content is inherent. No new probes or contact decals; use existing contact shadows and candidate SSAO.
- Actual `forza_chase_camera.gd` default height 2.25 m/distance 7.2 m, 58° rest to 74° at 60 m/s, radial blur off. Candidate camera numbers are data only: 2.35/7.4, 58–70°, 60 m/s, blur off. No camera mode/FOV/input mutation.

## Adapter usage

```gdscript
const RenderProfile = preload("res://modules/environment_rendering/render_profile.gd")
var rendering_preview := RenderProfile.new()

# After the real drive has initialized. Names match the production root.
var ok := rendering_preview.apply_candidate(drive, "medium")
print(rendering_preview.get_status())
# Before changing graphics preset, swapping scenes/cars, or dropping adapter:
rendering_preview.restore()
```

Explicit alternate nodes can be passed as `world_environment` and `sun` options; both must be descendants of the supplied live root. No implicit tree-wide discovery. Use a single instance per drive and call from the main thread. Restore before external quality changes (which mutate the live environment and sun), replacing meshes or unloading a scene. Reapply after the base graphics preset has settled, and after the real new car is mounted. Restore is idempotent and tolerates freed nodes. Invalid requests do not tear down a valid active candidate. Environment identity and previous surface override identity (including null) are restored. Shared Sky/Shader/Texture/Mesh resources are read-only; the candidate duplicates Environment and the selected Material instances. The adapter doesn't manage a global singleton or save settings.

For Senna, coordinator/local UI must explicitly select verified paint surfaces; no automatic paint mutation. Example after the car is mounted:

```gdscript
var paint: Array[Dictionary] = []
if drive.active_vehicle_id == "mclaren_senna":
    for node in drive.vehicle_body.find_children("*", "MeshInstance3D", true, false):
        var mesh := node as MeshInstance3D
        if mesh.mesh == null or mesh.material_override != null:
            continue
        for surface in range(mesh.mesh.get_surface_count()):
            var material := mesh.get_active_material(surface) as ShaderMaterial
            if material != null and material.shader != null and material.shader.resource_path == RenderProfile.PAINT_SHADER:
                paint.append({"mesh": mesh, "surface": surface})
rendering_preview.apply_candidate(drive, "medium", {"paint_surfaces": paint})
```

Explicitly supplied StandardMaterial3D surfaces are also supported; caller must identify body paint correctly, since generic material type alone cannot identify paint. Unknown shaders, whole-mesh overrides, repeated target entries, invalid indices and out-of-root nodes are rejected. The adapter cannot change other systems' materials. Restore does not overwrite an externally replaced environment/paint override. Sun properties are restored to the captured values, so restore before a separate quality controller modifies them.

`validate_profile(preset, options)` returns ok/values or error; unknown keys, bad types, non-finite numbers, out-of-range settings and non-increasing split ratios are rejected. `get_status()` reports active preset, renderer, headless flag, requested values, enabled effects, unavailable feature reasons, paint count, and last_error for a rejected request. A successful headless apply is property/lifecycle evidence only. Headless, non-Forward+ AO/SSR requests are disabled and reported. Glow is off in headless and conservatively disabled in Compatibility. Existing disabled sun shadows are never enabled. Sky absence is reported; no invented HDRI. Existing sky rotation, sun orientation/angular diameter, shadow mode, reflection source, fog switch and camera attributes remain unchanged. SDFGI, SSIL and volumetric fog are off in every candidate; SSR off unless explicitly requested.

## Local tuning sheet

All proposed values are hypotheses, not visual results. Set underlying quality before applying; render scale and shadow atlas must be held equal for A/B.

| Knob | Existing Medium | Candidate | Sweep / rationale |
|---|---:|---:|---|
| sun_energy | 1.92 | 1.75 | 1.55, 1.75, 1.92; less hot road/paint |
| sun color | 1,.94,.82 | 1,.96,.89 | fixed warm but less orange |
| ambient_energy | .62 | .60 | .50,.60,.68; keep woods legible |
| ambient color | .61,.72,.90 | .68,.78,.94 | fixed cooler fill without extreme blue |
| exposure | .96 | 1.0 | .90,.96,1.0,1.06; avoid clipping |
| contrast/saturation | 1.09/1.12 | 1.04/1.02 | 1.0–1.09 / 1.0–1.08 |
| shadow_distance | 270 m | 220 m (Low 135, High 300) | 160/220/270; improve near texel density |
| split_1/2/3 | .08/.22/.52 | .08/.23/.52 | .06–.12/.18–.30/.45–.65; maintain order |
| shadow_bias/normal_bias | .027/.64 | .027/.64 | .015/.027/.04 and .4/.64/.9; acne vs detached contact |
| shadow_blur | 1.25 | 1.0 | .7/1/1.25; edge quality vs cost |
| ssao | off | off Medium/Low; on High Forward+ | explicitly true on Medium for one A/B |
| ao_radius/intensity | not active | 1.0/.65 | .6/1.0/1.3 and .35/.65/.82; avoid black halos |
| glow | .20/.045 | .16/.025 | toggle false first; not a substitute for art |
| fog_density | .00029 | .00029 | .0002/.00029/.0004; preserve depth |
| ssr | off | off; explicit true | 16/32/48 steps, compare GPU and offscreen artifacts |
| paint_metallic | .41 | .48 | .35/.41/.48; avoid bare-metal response |
| paint_roughness | .32 | .24 | .20/.24/.32 |
| paint_clearcoat | .60 | .82 | .60/.75/.82 |
| paint_clearcoat_roughness | .20 | .12 | .10/.12/.18 |

Every numeric option has hard bounds in `RANGES`. Foliage calibration for Agent A/coordinator: judge against this sun/fill first, preserve natural leaf hues, compare sunny and shaded reference swatches, avoid emissive-looking transmission, keep backlight modest (suggest starting transmission weight .10–.20 if shader offers an equivalent normalized control), no saturation compensation until lighting is stable. No foliage shader edits.

Local tuning sequence: baseline fixed pose Senna in Cedar Woods and Green Valley, then matched candidate lighting without paint/SSR; tune exposure/fill, then shadows, then isolated AO, then paint, then SSR last. Use the existing `tests/integration/visual_compare.gd` as baseline capture and Agent F/coordinator feature discovery for matched candidate capture. Compare same camera pose, FOV, vehicle, time, preset, viewport 1920×1080, traffic/audio, native scale; stationary, 40–60 mph and safe high-speed route, off-road, then other regions. Collect real CPU/GPU p50/p95/p99, 1% low, VRAM and visual artifact notes. Do not treat headless values as timing or screenshot evidence. Retain rollback if candidate regresses.

## Tests and reproducible commands

Written but not executed in connector-only environment:
- `modules/environment_rendering/tests/render_profile_test.gd`: synthetic fixture, all presets, invalid values/nodes, original shared resources, repeated applies, shader and standard paint copy/restore, explicit unsupported feature reporting, disabled shadow preservation, viewport/settings unchanged, freed-root lifecycle.
- `modules/environment_rendering/tests/live_root_test.gd`: actual free-roam scene and selected imported Senna paint, checks actual shared sky/material identity, light and camera isolation; requires real LFS assets.
- `modules/environment_rendering/tests/run_headless.sh`: pinned engine version check, timeout, import and failure-log scanning, both owned tests and relevant existing suites in full mode. Does not weaken tests.

On complete checkout (Linux/WSL with timeout):
```bash
git checkout feat/env-e-rendering
git lfs pull
git lfs fsck
# Install exact official 4.7.2-stable standard build using map-regression.yml
# SHA256 cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4
godot --headless --version
bash modules/environment_rendering/tests/run_headless.sh --full
```

Direct commands:
```bash
godot --headless --path . --editor --import
godot --headless --path . --script res://modules/environment_rendering/tests/render_profile_test.gd
godot --headless --path . --fixed-fps 60 --script res://modules/environment_rendering/tests/live_root_test.gd
```

Baseline CI is manual on this feature branch. With authorized GitHub CLI:
```bash
gh workflow run map-regression.yml --ref feat/env-e-rendering
gh run list --branch feat/env-e-rendering --workflow map-regression.yml
```
Existing map workflow includes branch-specific width checks; inspect any inherited failures against the identical base. It does not invoke our tests; use the owned runner or F's later integrated workflow. No workflow edits permitted. Connector has no dispatch or shell/LFS execution action, so no headless import, GDScript parser or CI pass is claimed. Actual Windows graphical acceptance, shader/GPU compilation, shadows, Senna paint appearance and performance remain unverified. No generated screenshots.

## Coordinator ledger entries

ASSET_LICENSES: no additions (original GDScript/shell; references existing assets and shaders without modifying them).

PROJECT_STATUS proposed entry: Agent E `feat/env-e-rendering` from pinned 67023539 implements opt-in reversible daylight/quality and explicitly selected paint preview adapter, owned synthetic/real-root regression scripts and headless runner. Production root/global settings unchanged. Connector published code; Godot import, tests, CI and real GPU acceptance not yet executed. Next: run owned and base regression suites, integrate feature flag and compare matched local captures before accepting.
