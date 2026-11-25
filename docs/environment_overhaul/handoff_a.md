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

Check build result and get_stats().state/fallback. Keep legacy cover until coordinated A/B replacement; don't stack both. Mask missing/corrupt, unavailable world API, clearance index empty or changed, nonidentity transform: fail closed. Fixture sampler is explicit debug-only. Mask uses center-aligned 2 m RGBA cells with SHA-256 verification. Real surface height sampled per tuft with slope rejection; every accepted candidate uses production triangle-index overlaps with shoulders enabled and conservative swept bounds of all LOD meshes, including 0.24 m maximum shader displacement and 0.12 m margin. The real clearance API deliberately permits ground beneath high bridge decks.

## Local starting values (not accepted performance)
| Preset | Near/mid/far radii (m) | Max candidate density (tufts/m²) | Active cap | Candidates/frame | Chunk uploads/frame | Chunk cap |
|---|---|---|---|---|---|---|
| Low | 20/45/80 | 4.8/1.92/0.56 | 18,000 | 1200 | 2 | 120 |
| Medium | 25/65/130 | 8.8/3.2/0.88 | 54,000 | 2400 | 3 | 300 |
| High | 32/80/150 | 13.6/4.8/1.28 | 90,000 | 3600 | 4 | 360 |

16 m cells, 64x64 jittered candidate lattice, keyed Feistel permutation, rank-prefix stable subsets, biome acceptance and slope filter. Meshes are 8 curved four-segment blades near, 5 two-segment mid, 3 triangular far; five original variants. Height bases 0.15/0.24/0.39/0.27/0.20 m, widths 0.012–0.018 m; tune in grass_mesh.gd. Per-tuft scale 0.78–1.20, yaw, terrain-normal orientation. Chunk culling uses conservative custom AABB; shadows off. Predictive prefetch 0.65 s and 5 m LOD hysteresis. Node pool retains at most 75 empty batch nodes, not old instance buffers. Hard instance and job caps; one chunk may use up to five MultiMeshes. Outer distance uses opaque shader discard; internal LOD boundaries use hysteresis and nested density rather than crossfade. Downgrades retire prior batches before regeneration to preserve hard caps; brief gaps are possible. Preset change rebuilds rather than blending. No whole-world dense cache, per-blade physics, threads or save files.

Tuning dictionary: density (three descending fractions of 16 candidates/m², max 1), radii (three ascending metres), cap/checks/uploads/chunks (hard maximum High limits), wind_enabled, wind_strength (0–0.16 m), fade_enabled, plain_material (build-time diagnostic StandardMaterial3D, no wind/fade). Wind and vehicle bend combined clamped to 0.24 m, anchored at UV.y=0. Vehicle interaction is opt-in. Start with 0.25/0.10/0.03 density on lower hardware, then sweep default and higher near density while collecting frame-time and visual data. No transparent cards; no external assets. Stats report cumulative CPU wall time in microseconds including upload, separate upload time, candidate count, rejects, active and queued chunks, per-LOD instances, estimated triangles and bytes (64 bytes per transform/custom data, mesh arrays estimate, excludes driver/allocator overhead). Chunk upload count is not a count of individual species buffers. No CPU or GPU benchmark measured yet.

## Reproduce
Use official Godot 4.7.2 standard build and checksum from .github/workflows/map-regression.yml. Fetch Git LFS first for canonical world smoke. From root:
```sh
git lfs pull
bash modules/ground_cover/tests/run_headless.sh
RUN_EXISTING=1 bash modules/ground_cover/tests/run_headless.sh
godot --path . res://modules/ground_cover/tests/demo.tscn
godot --path . res://modules/ground_cover/tests/demo.tscn -- --mask=res://content/scenery/environment_overhaul/masks
```
Demo keys WASD translate, Shift faster, P preset, V vehicle bend, T teleport, I stats. Demo uses fixture geometry/height with visual floor approximation, not the production world. Real-world smoke builds the canonical preview with the actual clearance API and a synthetic ecological mask. It requires real LFS payloads. Headless tests cover mesh indices/root/flex, wind expansion, RGBA mapping/checksum/missing, deterministic candidate permutation and nested accepted transforms, road and shoulder/bridge fixtures, bounds and budgets, traversal, teleport, repeated presets, invalid heights/slopes/clearance and shutdown. Test failures return nonzero. Root import and relevant existing regressions are explicitly scripted.

## Verification and limitations
Connector confirmed commits; source reviewed against actual pinned world runtime and road_clearance.gd. No local Godot executable found in the cloud container. The pinned map regression workflow only runs on its named push branch or manual dispatch; Agent F owns the shared environment-overhaul workflow. Do not modify workflow or claim tests passed. CI status must be checked on the PR. GPU shader compilation, actual demo appearance, CPU generation time, density/LOD transitions, shader discard and culling, road safety in live roadworks, water/biome suitability and frame-time/VRAM remain unverified. Internal LOD transition blending and adaptive time budgeting are not implemented; fixed candidate and upload budgets are initial constraints. Coordinator should run owned tests and real-world smoke and fix any failures before integration, then local agents perform matched captures. No graphical acceptance.

## Ledger/status entries for coordinator
ASSET_LICENSES: modules/ground_cover/grass_mesh.gd and grass.gdshader — original procedural assets authored for Aster Valley; no third-party source, texture or download; repository terms apply.
PROJECT_STATUS: isolated Agent A ground-cover candidate on feat/env-a-ground-cover; deterministic streamed opaque grass meshes, v1 mask reader, exact swept clearance, bounded LOD/pool/caps, shader wind and optional vehicle interaction, fixtures and demo committed; engine execution and local GPU acceptance pending. No root wiring.
