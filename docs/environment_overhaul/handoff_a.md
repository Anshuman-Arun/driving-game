# Agent A — procedural ground cover handoff

Base: 67023539e56e5e80d5efcd3f3239be9650c6f462, branch feat/env-a-ground-cover. Wave 1 isolated implementation; no production wiring, canonical data edits, or external art. All new assets are original procedural geometry and shader code.

## Integration
Attach a Node3D running res://modules/ground_cover/ground_cover.gd to an identity-transform world-aligned parent. After world runtime builds its real clearance index, call:

```gdscript
var cover = preload("res://modules/ground_cover/ground_cover.gd").new()
add_child(cover)
var ok: bool = cover.build(world, "medium", "res://content/scenery/environment_overhaul/masks", {
    "pilot_bounds": Rect2(-800, 250, 300, 300),
    "seed": 20261125
})
# Every frame after camera update:
cover.update_focus(camera.global_position, vehicle_velocity)
# Optional; disabled initially:
cover.set_vehicle_interaction(vehicle.global_position, vehicle_velocity, false)
# Settings change:
cover.set_graphics("low")
# Session exit:
cover.shutdown()
```

Check build result and get_stats().state/fallback. Keep legacy cover until coordinated A/B replacement; don't stack both. Mask missing/corrupt, unavailable world API, clearance index empty, replaced or triangle count changed, nonidentity transform: fail closed. Production builds with a known partial-preview runtime report are disabled; the real-world preview smoke explicitly uses the debug fixture sampler. Fixture sampler is explicit debug-only. Mask uses center-aligned 2 m RGBA cells with SHA-256 verification. Real surface height sampled per tuft with slope rejection; every accepted candidate uses production triangle-index overlaps with shoulders enabled and conservative swept bounds of all LOD meshes, including 0.24 m maximum shader displacement and 0.12 m margin. The real clearance API deliberately permits ground beneath high bridge decks.

## Local starting values (not accepted performance)
| Preset | Near/mid/far radii (m) | Max candidate density (tufts/m²) | Active cap | Candidates/frame | Chunk uploads/frame | Chunk cap |
|---|---|---|---|---|---|---|
| Low | 20/45/80 | 4.8/1.92/0.56 | 18,000 | 1200 | 2 | 120 |
| Medium | 25/65/130 | 8.8/3.2/0.88 | 54,000 | 2400 | 3 | 300 |
| High | 32/80/150 | 13.6/4.8/1.28 | 90,000 | 3600 | 4 | 360 |

16 m cells, 64x64 jittered candidate lattice, keyed Feistel permutation, rank-prefix stable subsets, biome acceptance and slope filter. Meshes are 8 curved four-segment blades near, 5 two-segment mid, 3 triangular far; five original variants. Height bases 0.15/0.24/0.39/0.27/0.20 m, widths 0.012–0.018 m; tune in grass_mesh.gd. Per-tuft scale 0.78–1.20, yaw, terrain-normal orientation. Chunk culling uses conservative custom AABB; shadows off. Predictive prefetch 0.65 s and 5 m LOD hysteresis. Node pool retains at most 75 empty batch nodes, not old instance buffers. Hard instance and job caps; one chunk may use up to five MultiMeshes. Budget allocation reserves 50% near, 32% mid and 18% far of the candidate and chunk limits, then redistributes unused capacity; per-chunk quotas quantized to 32 ranks above 64. Consequently realized density may be lower than the candidate maxima in the table, especially at far range. Outer distance uses opaque shader discard; internal LOD boundaries use hysteresis and nested density rather than crossfade. Old batches are retained if accepted count fits the new quota; otherwise retired before regeneration to preserve hard caps. In-flight jobs keep their deterministic prefix when detail or quota changes. Brief gaps are still possible. Preset change rebuilds rather than blending. No whole-world dense cache, per-blade physics, threads or save files.

Tuning dictionary: density (three descending fractions of 16 candidates/m², max 1), radii (three ascending metres), cap/checks/uploads/chunks/upload_instances/work_usec (hard maximum High limits), wind_enabled, wind_strength (0–0.16 m), fade_enabled, plain_material (build-time diagnostic StandardMaterial3D, no wind/fade). Wind and vehicle bend combined clamped to 0.24 m, anchored at UV.y=0. Vehicle interaction is opt-in. Start with 0.25/0.10/0.03 density on lower hardware, then sweep default and higher near density while collecting frame-time and visual data. No transparent cards; no external assets. Stats report cumulative CPU wall time in microseconds including upload, separate upload time, candidate count, rejects, active and queued chunks, per-LOD instances, estimated triangles and bytes (64 bytes per transform/custom data, mesh arrays estimate, excludes driver/allocator overhead). Chunk upload count is not a count of individual species buffers. Actual per-frame upload instance caps are 1800/2800/4200. Soft CPU work budgets are 1800/2200/3000 microseconds; timers are checked every 32 candidates, and a single chunk upload can exceed the soft budget. Planning time and cancelled/retargeted jobs are reported separately. No CPU or GPU engine benchmark measured yet.

## Reproduce
Use official Godot 4.7.2 standard build and checksum from .github/workflows/map-regression.yml. Fetch Git LFS first for canonical world smoke. From root:
```sh
node modules/ground_cover/tests/reference_budget.mjs
git lfs pull
bash modules/ground_cover/tests/run_headless.sh
RUN_EXISTING=1 bash modules/ground_cover/tests/run_headless.sh
godot --path . res://modules/ground_cover/tests/demo.tscn
godot --path . res://modules/ground_cover/tests/demo.tscn -- --mask=res://content/scenery/environment_overhaul/masks
```
Demo keys WASD translate, Shift faster, P preset, V vehicle bend, T teleport, I stats. Demo uses fixture geometry/height with visual floor approximation, not the production world. Real-world smoke builds the canonical preview with the actual clearance API and a synthetic ecological mask. It requires real LFS payloads. Headless tests cover mesh indices/root/flex, wind expansion, RGBA mapping/checksum/missing, deterministic candidate permutation and nested accepted transforms, road and shoulder/bridge fixtures, bounds and budgets, traversal, teleport, repeated presets, invalid heights/slopes/clearance and shutdown. Test failures return nonzero. Root import and relevant existing regressions are explicitly scripted. Fixture-only CPU pose capture avoids treating dummy-renderer readback as a successful GPU upload. Test extensions cover retargeted prefix equivalence, cap fairness, actual per-frame instance uploads, invalid focus and clearance mutation.

## Verification and limitations
Connector confirmed commits; source reviewed against actual pinned world runtime and road_clearance.gd. No local Godot executable or GDScript linter found in the cloud container (command lookup); git ls-remote failed with DNS resolution for github.com. No GitHub workflow dispatch action is exposed by the connected tools. The pinned map regression workflow only runs on its named push branch or manual dispatch; Agent F owns the shared environment-overhaul workflow. Do not modify workflow or claim tests passed. CI status must be checked on the PR. GPU shader compilation, actual demo appearance, CPU generation time, density/LOD transitions, shader discard and culling, road safety in live roadworks, water/biome suitability and frame-time/VRAM remain unverified. Internal geometry LOD crossfading is not implemented. Fixed hard candidate and upload budgets plus a soft time budget are initial constraints; actual frame time remains unmeasured. Coordinator should run owned tests and real-world smoke and fix any failures before integration, then local agents perform matched captures. No graphical acceptance.

## Ledger/status entries for coordinator
ASSET_LICENSES: modules/ground_cover/grass_mesh.gd and grass.gdshader — original procedural assets authored for Aster Valley; no third-party source, texture or download; repository terms apply.
PROJECT_STATUS: isolated Agent A ground-cover candidate on feat/env-a-ground-cover; deterministic streamed opaque grass meshes, v1 mask reader, exact swept clearance, bounded LOD/pool/caps, shader wind and optional vehicle interaction, fixtures and demo committed; engine execution and local GPU acceptance pending. No root wiring.

## Follow-up numerical verification (2026-11-25)
Independent JavaScript reference of the cap allocator was executed in the cloud against the actual committed preset constants (not the Godot implementation): 10,800 cases, 43,920 assertions, no failures. Cases cover varied cap/chunk limits, map boundaries, cell crossings, stationary and moving predictive focus; no hysteresis or real engine calls. At centered stationary focus: Low reserves 17,656 candidates (4/20/56 chunks, 1216/480/57 ranks per chunk); Medium 52,424 (4/48/156, 2240/704/62); High 84,480 (12/68/196, 3456/448/64). These are worst-case rank allocations, not accepted instances or FPS. Reproduce with node modules/ground_cover/tests/reference_budget.mjs. All GDScript and shader checks remain pending. PR #48 remains draft, unmerged.
