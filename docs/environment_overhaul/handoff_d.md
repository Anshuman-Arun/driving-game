# Agent D — terrain and roadside handoff

Base: 67023539e56e5e80d5efcd3f3239be9650c6f462 (main at branch creation).
Branch: feat/env-d-terrain. Scope: modules/environment_terrain/ and this document only.
No root wiring, world data, shared shaders, other branches, or CI workflow changes.

## Production audit

Root scripts/integration/aster_valley_drive.gd calls ValleyEnvironment.apply_world_materials(world) before world.build_world(). scripts/integration/aster_valley_environment.gd prefers assets/forza_env/materials/terrain_triplanar_pbr.tres (shaders/terrain_triplanar.gdshader); terrain_forza.tres / terrain_forza.gdshader are fallback only. WorldRuntime passes terrain_material_override to mesh_builder; the latter assigns one material to each TerrainChunks mesh's surface zero. Road meshes have separate pavement and shoulder surfaces, with varying widths and raised bridge decks. The live road_clearance indexes transformed triangles, including shoulder geometry. Do not infer road edges from graph lane widths. The pinned world uses roadworks grading and exact centered bounds [-1000,1000] in X/Z; metadata confirms the coordinate convention.

The candidate derives from the primary shader, preserving its height/slope, rotated dual-scale world-space projection, normal mapping, shoreline, packed ARM, AO, tint and roughness bindings. New changes: modulated anti-tiling blend; distance-faded fine meadow color; mask-driven woodland/moisture/grass/exposed-rock influence; mild moss tint on forest soil; roughness bias; optional road-edge soil transition. No parallax or displacement. Missing/corrupt C mask means heuristic biome weights, not a blank texture. Existing primary texture resources are reused by reference (read-only); candidate ShaderMaterial instances are newly allocated per distinct original. Unknown/fallback material schemas and missing textures reject the whole transaction, leaving the original intact rather than synthesizing incompatible PBR inputs.

## Integration (coordinator only)

After WorldRuntime.build_world() succeeds, retain an adapter per world. Apply after any environment material setup. For the first Cedar pilot:

```gdscript
const TerrainPreview = preload("res://modules/environment_terrain/terrain_preview.gd")
var terrain_preview = TerrainPreview.new()
# After world.build_world() succeeds:
var pilot := Rect2(-810, -450, 220, 220)
var ok := terrain_preview.apply_candidate(world, {
    "pilot_bounds": pilot,
    "roadside_bounds": pilot,
    "mask_dir": "res://content/scenery/environment_overhaul/masks",
    "tuning": {"biome_strength": 0.7, "roadside_strength": 0.55}
})
print(terrain_preview.get_stats())
# To compare legacy, before rebuilding world, or during shutdown:
terrain_preview.restore()
```

Choose a confirmed on-road location within the pilot after checking the actual world; the above rect is near the Cedar metadata anchor, not a guaranteed camera pose. Green Valley example Rect2(-65, 60, 220, 220). One active application per adapter; restore before switching pilot/reapplying. Restore is idempotent, checks live references, and will not overwrite someone else's later material override. Chunk mesh and collision references, world.terrain_material_override, road surface materials, graph and heights remain untouched. Candidate-specific changes fade up to 8 m inside pilot_rect (adaptive for narrow pilots); pilot bounds must be at least 1 m across. Global base PBR tuning is rejected when pilot_bounds is supplied, so a strict geographic A/B cannot accidentally change the rest of the map. Without pilot_bounds the material is candidate everywhere; road band requires explicit roadside_bounds. Both rects use world X/Z and must fit canonical bounds. Shifted/rotated world roots, malformed metadata, unknown options, or invalid raster dimensions reject the transaction. Explicit empty mask_dir disables mask loading.

### Parameter table

| Parameter | Default | Valid range / behavior |
|---|---:|---|
| biome_strength | 0.70 | 0–1; optional valid C mask influence |
| meadow_micro_strength | 0.08 | 0–0.30; fine variation, fades 25–110 m |
| moss_strength | 0.18 | 0–0.50; soil tint, moisture/woodland weighted |
| roughness_bias | 0.025 | −0.20–0.20; clamped final roughness |
| roadside_strength | 0.55 | 0–1; soil mix outside road |
| normal_strength | original 0.49 | 0–2 |
| grass_scale | original 0.22 | 0.02–0.50 cycles/m |
| dirt_scale | original 0.13 | 0.02–0.50 cycles/m |
| rock_scale | original 0.075 | 0.01–0.50 cycles/m |
| shore_scale | original 0.16 | 0.02–0.50 cycles/m |
| slope_threshold | original 0.76 | 0.3–0.9 (normal.y) |
| slope_blend_margin | original 0.14 | 0.02–0.30 |
| macro_scale | original 0.0055 | 0.001–0.05 |
| macro_luminance_mod | original 0.18 | 0–0.50 |

All original color/normal/roughness uniforms remain inspectable on each candidate ShaderMaterial; runtime tuning dictionary accepts finite bounded numeric values only. Original texture assets are unchanged. Set roadside_strength to 0 and omit roadside_bounds for an isolated biome comparison. Mask uses raw RGBA8, linear sampling, no source-color conversion, cell centers (-999+2*i,-999+2*j), X fastest, increasing Z south; coordinates outside the map use fallback. Schema, dimensions, origin, channel and row order, byte order, length, seed and SHA-256 are checked. Six allowlisted critical source hashes (metadata, canonical graph, canonical and roadworks heightfields, roadworks manifest and lake cells) must match the current project bytes; other provenance hashes are format-checked but not rehashed at runtime. Agent C's current read-only baker source was inspected and uses this exact manifest naming/channel order. Generated C payload is not on the pinned base; test builds a synthetic mask with real critical-source hashes. Hard-exclusion pixels with zero ecological channels smoothly fall back to heuristic terrain colors rather than bleaching coarse road edges. No dependency on A/B/C.

## Roadside and rock safety

roadside_band.gd rasterizes a bounded pilot using the actual clearance index, not the centerline. One-meter-or-finer cells, maximum 256×256, at most five clearance queries per cell (327,680 maximum), generated once on application, not every frame. R8 texture is at most 64 KiB raw; biome RGBA8 is 4,000,000 bytes raw. Estimates exclude engine overhead. A protected footprint expands by 1.5 cell widths in each direction before the query, preventing linear-filter blending into road/shoulder interiors. All vertical road/bridge columns excluded even where the live vehicle clearance deliberately allows under-deck objects. The conservative square-margin distance is approximate, not Euclidean; transition bands extend 1–4 m beyond the enlarged protected box, with a 5 m fade at raster edges. No mesh overlays, paint changes, new shoulders or roadwork edits. Raster queries are synchronous; profile boot cost on Windows and keep initial pilot small. If the actual clearance index is unavailable or the raster has no nonzero transition cells, roadside is disabled with status and no GPU texture is allocated. Keep the mask out of production outside the selected pilot; no full-world raster build in this wave.

rock_bank_recipe.gd is a fail-closed footprint eligibility helper, not a spawner. Optional local placement recipe:
1. Use the already licensed Poly Haven boulder_01 (Rico Cilliers, CC0, assets/curated/models/environment/boulder.glb). Do not duplicate current vegetation or existing premium rocks. Candidate locations should be dry steep banks (sample get_surface_height_at around position at 2 m offsets; choose roughly 25–45 degrees), away from routes/shortcuts. Choose deterministic yaw, restrained 0.7–1.5 scale, embed lower 20–35% visually in the bank. Preserve traversable terrain.
2. Compute the union of actual local mesh AABBs transformed by every nested GLB part transform relative to the placement root. Pass the final world Transform3D and this union to RockBankRecipe.prepare(world), then accepts(frame, bounds) for every candidate. Recheck any change in pose, scale or geometry. Gate rejects road/shoulder/bridge columns with a 0.5 m margin and rejects all lake/roadworks water cell columns using the same 4 m grid as rendered meshes. Missing or invalid source data fails closed. The gate checks the generated root, clearance identity and triangle count, and a snapshot of water cells on each acceptance; stale input is rejected. Prepare again after a world rebuild or water changes. Touching a grid boundary is conservatively excluded. Gate deliberately allows no placement without verified water data. It does not certify slope/asset overlap or guarantee art quality; coordinator must also check those.
3. Only after local review, mount a visual-only MeshInstance3D (or MultiMesh) under a disposable preview root, no physics shape, no new blocking prop, no terrain carving. Use exact same transform as validated. Cap a 220 m pilot to a small set (e.g. 16) and remove on restore. No instances are emitted in this branch. The fixture verifies transformed bounds rejection for road, elevated deck and water; no new live instance can overlap these because none is created.

## Tests and reproduction

From a real checkout of this branch, with git LFS materialized (verify real texture/model bytes, not pointer text), install the official standard Godot 4.7.2 using the pinned checksum and commands in .github/workflows/map-regression.yml (Linux x86_64 SHA-256 cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4). Then:

```bash
git lfs pull
godot --headless --version
bash modules/environment_terrain/tests/run_headless.sh --baseline
# Optional smaller synthetic-only gate:
godot --headless --path . --script res://modules/environment_terrain/tests/run_tests.gd
# Real world test (also run by run_headless.sh):
godot --headless --path . --script res://modules/environment_terrain/tests/run_tests.gd -- --production
# Existing CI is manual on this branch, if gh and Actions permission available:
gh workflow run map-regression.yml --ref feat/env-d-terrain
```

run_headless.sh checks source contracts and LFS payloads, engine version, exit statuses and script/shader error strings, with per-command logs and timeout. It also requires a nonzero-test, zero-failure final terrain summary (no silent early exits). Source-only mode needs no Godot: `bash modules/environment_terrain/tests/run_headless.sh --static-only`. The standalone fixture checks invalid world/options, missing texture fail-closed, finite shader params, texture binding identity, restoration of surface/global overrides, unchanged mesh/collision/road/clearance, validated mask channel/row ordering and corruption, deterministic roadside raster including protected deck columns and bounded work, rock gate, and optional real world graph/height/clearance preservation and restoration. It imports no unmerged agent code. No assertions in baseline tests were changed.

Cloud limitation: Godot is not installed in the execution container; direct GitHub DNS resolution failed, so checkout/LFS payloads and the checksum-pinned engine could not be retrieved. No GDScript execution, import or shader compilation is claimed. Existing map-regression workflow triggers push only on feat/map-width-current-main or manual workflow_dispatch; no workflow dispatch action in connected GitHub tools, and Agent F owns shared CI. No fabricated pass status or screenshots. Run the above before merge.

## Local A/B

Run the isolated synthetic fixture:
```bash
godot --path . res://modules/environment_terrain/preview_fixture.tscn
```
Press T to toggle candidate/restore from the same camera. Synthetic test patch is not production acceptance. Then use coordinator's actual matched production capture with native resolution, same Senna pose/FOV/speed/time, traffic/audio enabled; Cedar and Green Valley first. Check vegetation-ground color continuity, fine patching, steep banks, bridge edge readability and no markings washed out, and far terrain shimmer. Sweep meadow micro 0.04/0.08/0.12, moss 0.10/0.18/0.30, roadside 0.25/0.55/0.75; test biome 0/0.4/0.7/1.0. Avoid globally changing base tints or scales until pilot is approved. Record CPU/GPU p50/p95/p99 and 1% low and same baseline. No claimed FPS gain.

Static shader lookup accounting (source-level upper bounds, not measured GPU instructions): original planar grass+soil = 16 lookups; shoreline adds 6; steep rock with ARM adds 15 (or 21 for separate roughness and AO). Candidate adds at most one biome and one roadside lookup where enabled, so common flat 16–18; worst 39 with ARM or 45 with separate channels, plus noise arithmetic. No new triplanar layer or texture lookup for micro/moss noise. Texture count stays bounded; existing flat planar projection retained. Actual compiler, dynamic branches and GPU cost unverified.

## Coordinator ledger / status entries

ASSET_LICENSES: no newly downloaded third-party payloads; original candidate shader and procedural raster/fixture/test code; reuses already-ledgered meadow, forest floor, shore, cliff PBR maps and optional boulder_01 geometry (Poly Haven CC0; no new copy). Preserve existing notices.

PROJECT_STATUS: Agent D delivered isolated opt-in PBR terrain adapter, optional validated biome and triangle-clearance roadside textures, rock footprint gate and tests on feat/env-d-terrain from 67023539e56e5e80d5efcd3f3239be9650c6f462. No production integration or visual sign-off. Source/geometry reference checks and mock runner gates passed; actual Godot/CI execution and local GPU acceptance outstanding; use handoff commands and integration recipe. No shared ledger/status edits during parallel wave.

## Second-pass audit — executed evidence and remaining gaps

- Corrected float32 tuning endpoint rounding, original uniform default/type validation, active/inactive rock texture requirements, invalid shoreline height ordering, exact per-material ownership and rollback after partial staging failure. Source defaults and every existing shader uniform are checked against the actual pinned shader and material. Strict geographic pilot tuning no longer leaks global changes. A freed/rebuilt or detached world prunes old transactions.
- World and clearance helpers now enforce the centered coordinate contract and actual road-clearance script, reject invalid/transformed/queued worlds, and distinguish empty bands from errors. Rock gate rejects singular/oversized transforms, stale generated root/index/water state and closed water-cell edge contact. Biome reader caps manifest size, validates row order/provenance and rejects stale critical world sources. The preview fixture now includes a steep bank.
- Headless tests additionally cover invalid metadata, shifted worlds, malformed/oversized options, documented exact numeric endpoints, active rock map requirements, safe defaults, foreign overrides, atomic multi-chunk failure, rebuild/reapply, empty raster, bilinear protected-region interpolation, water mutation/contact, singular transforms, corrupt manifest and stale world-source hashes. Production test snapshots every generated mesh resource, surface material, collision resource and transform; compares the graph, sample height, clearance count and report, then restores original materials.

Executed independently via the connector's JavaScript runtime, using the exact committed `tests/verify_contract.cjs` and freshly fetched branch source files: **36,112 checks passed**, including 35 original shader uniforms, all 16 original PBR texture bindings, 5,000 independent triangle-vs-box SAT/oracle comparisons, **24,509 protected-position bilinear samples with zero modeled leakage**, 1,774 positive raster cells and 6,481 validated real lake/crossing-water cells. 18 candidate sampler declarations were counted (16 original + 2 optional). These are source and numerical reference-model checks, not actual engine execution or GPU measurements.

Verified the exact remote runner script blob `af71e022f5f61eb16d96b31aa75bb372b791a3d7` with local `git hash-object` and `bash -n`. Exercised runner logic in a temporary repo with a synthetic engine and stub source verifier: good run accepted; missing summary, zero-test count, parse-error log, shader-error log, FAIL: log and nonzero engine exit all rejected; static-only mode works without an engine. These are harness self-tests only, not real Godot tests. The actual GDScript suite is committed but not executed. Actual GitHub branch-wide Actions listing returned zero runs; PR-specific run/status endpoints also returned none. The Agent F QA workflow exists on its unmerged branch, not this base; do not import it. Existing manual workflow requires a dispatch-capable user/runner. No changes outside Agent D ownership, no main writes, no merge.
