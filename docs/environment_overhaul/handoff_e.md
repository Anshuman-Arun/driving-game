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

Explicit alternate nodes can be passed as `world_environment` and `sun`; targets must be live descendants of the supplied root in the same viewport, with no queued deletion in their ancestry up to the root. The supplied environment must be the sole non-null WorldEnvironment in its World3D; sharing the same resource with another node does not establish ownership. This is a scene-tree traversal on explicit apply, never per frame. All ancestors, including those above the preview root, must not be queued for deletion. Scene access is main-thread only. No implicit tree-wide discovery. Only one active preview per World3D (independent owned SubViewports are independent). Use the main thread. Restore before external quality changes or replacing meshes; the entire preview also restores automatically when any watched target or root exits the tree. Reapply after base graphics and car mounting settle. Invalid requests leave the current preview intact. Restore is idempotent. Environment identity and prior surface override identity, including null, are restored unless superseded externally. Shared Sky/Shader/Texture/Mesh resources are read-only; copy one Environment and one Material per distinct selected source, preserving shared-material batching. The module holds a strong active lease until restore or target exit; dropping the caller handle does not abandon mutated resources. Recover a lost handle with `RenderProfile.restore_for_root(drive)` (exact owning root only). This avoids relying on RefCounted PREDELETE instance methods, which have a documented crash history (https://github.com/godotengine/godot/issues/80834). No global rendering settings or persistence. Lost-handle recovery resolves by root identity even after a viewport world change.

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

Explicitly supplied StandardMaterial3D surfaces are also supported; caller must identify body paint correctly, since generic material type alone cannot identify paint. Unknown shaders, whole-mesh overrides, repeated target entries, invalid indices and out-of-root nodes are rejected. The adapter cannot change other systems' materials. Restore does not overwrite an externally replaced environment/paint override. Sun restoration compares against the values actually applied and only restores properties still owned by the preview; later differing values are preserved. If a mesh resource has changed while our override is attached, restore clears that stale override instead of installing the original override from old geometry. Restore before external edits: equal-valued concurrent changes cannot be distinguished, and in-place external edits of candidate resources are discarded on restore.

`validate_profile(preset, options)` returns ok/values or error; unknown keys, bad types, non-finite numbers, out-of-range settings and non-increasing split ratios are rejected. `get_status()` reports active preset, renderer, headless flag, requested values, effective effect flags, unavailable reasons, paint surface/material counts, attached count, environment attachment, detectable environment/sun/paint attachment drift, and last_error. Camera environment overrides are reported, not modified. Shared subresource and paint uniform edits are not exhaustively monitored. `sun_color` and `ambient_color` accept finite Color RGB in [0,1] and alpha 1. Numeric bounds are inclusive 64-bit scalar values rather than Vector2 components. Adjacent shadow splits require 0.01 minimum separation (one percent of the shadow range). Paint previews accept at most 512 explicitly selected surfaces. Known paint shader uniforms are copied explicitly in addition to Resource.duplicate(), so untuned base/grazing colors, flakes, normal scale, texture bindings and other parameters do not depend on renderer uniform enumeration. A skyless environment receives color-only ambient fill. The current camera environment override flag updates when queried. A successful headless apply is property/lifecycle evidence only. Headless, non-Forward+ AO/SSR requests are disabled and reported. Glow is off in headless and conservatively disabled in Compatibility. Existing disabled sun shadows are never enabled. Sky absence is reported; no invented HDRI. Existing sky rotation, sun orientation/angular diameter, shadow mode, reflection source, fog switch and camera attributes remain unchanged. SDFGI, SSIL and volumetric fog are off in every candidate; SSR off unless explicitly requested.

## Local tuning sheet

All proposed values are hypotheses, not visual results. Set underlying quality before applying; render scale and shadow atlas must be held equal for A/B.

| Knob | Existing Medium | Candidate | Sweep / rationale |
|---|---:|---:|---|
| sun_energy | 1.92 | 1.75 | 1.55, 1.75, 1.92; less hot road/paint |
| sun_color | 1,.94,.82 | 1,.96,.89 | less orange; Color RGB override |
| ambient_energy | .62 | .60 | .50,.60,.68; keep woods legible |
| ambient_color | .61,.72,.90 | .68,.78,.94 | cooler fill; Color RGB override |
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

GDScript suites written but not executed (Godot unavailable). Shell runner independently verified with mocked processes:
- `modules/environment_rendering/tests/render_profile_test.gd`: synthetic fixture, all presets, invalid values/nodes, original shared resources, repeated applies, shader and standard paint copy/restore, explicit unsupported feature reporting, disabled shadow preservation, viewport/settings unchanged, freed-root lifecycle, inclusive numeric bounds and color validation, queued/freed targets, cross-viewport rejection, overlapping and independent world leases, external replacements/drift, shared material reuse, mesh swap, lost-handle recovery, camera override reporting, and target/root exit; competing WorldEnvironment nodes with identical resources, degenerate cascade separation, bounded paint requests, skyless fallback, changing camera override state, and untuned shader uniform preservation.
- `modules/environment_rendering/tests/live_root_test.gd`: actual free-roam scene and selected imported Senna paint, checks actual shared sky/material identity, light and camera isolation; requires real LFS assets. The live test also checks all four tuned shader uniforms, preserves the explicit untouched shader parameters, and checks non-paint material identities before and after restore.
- `modules/environment_rendering/tests/run_headless.sh`: pinned engine version check, timeout with kill grace, isolated fixture import, explicit nonempty success markers, failure-log scanning, LFS fsck/pointer checks and all five relevant existing suites in full mode, including map_width_check (network_upgrade confirmed on the pinned base). Each existing suite must emit its actual pinned completion message exactly once, in addition to zero exit and error-log checks. `--owned` stages only the fixture, adapter and text shader into a temporary project; no binary world assets or root import needed.

- `modules/environment_rendering/tests/test_runner.sh`: **20/20 mock-process cases passed** (including wrong version, zero-exit parse/shader errors, missing/duplicate/empty/inconsistent completion markers, assertion, nonzero exit, simulated timeout exit, LFS errors/pointers, empty live paint count and continued regression execution after a failure; added malformed version-prefix, missing/duplicate existing-suite terminal output, and ERROR-prefixed FAIL with zero exit). Bash syntax checks passed. Exact Git blobs tested: runner d0a45095e7335551866ff91710f08e6923f90684 and mock test 536719d8f93b6e7b50a54bfde23beb7bae644549. This proves shell runner control flow only.

Without LFS:
```bash
bash modules/environment_rendering/tests/test_runner.sh
GODOT_BIN=/absolute/path/to/godot bash modules/environment_rendering/tests/run_headless.sh --owned
```

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
Existing map workflow includes branch-specific width checks; inspect any inherited failures against the identical base. It does not invoke our tests; use the owned runner or F's later integrated workflow. No workflow edits permitted. Connector has no workflow dispatch action. Local search found neither Godot nor gh; official engine release download failed DNS resolution (curl exit 6, reproduced on this review); alternate binary download was also unavailable. Shell mock tests ran locally, but no headless import, GDScript parser or CI pass is claimed. Actual Windows graphical acceptance, shader/GPU compilation, shadows, Senna paint appearance and performance remain unverified. No generated screenshots.

## Coordinator ledger entries

ASSET_LICENSES: no additions (original GDScript/shell; references existing assets and shaders without modifying them).

PROJECT_STATUS proposed entry: Agent E `feat/env-e-rendering` from pinned 67023539 implements opt-in reversible daylight/quality and explicitly selected paint preview adapter, owned synthetic/real-root regression scripts and headless runner. Production root/global settings unchanged. Connector published code; hardened edge cases and verified 20/20 shell runner fault-injection cases. Godot import, GDScript runtime tests, CI and real GPU acceptance not yet executed. Next: run owned and base regression suites, integrate feature flag and compare matched local captures before accepting.
