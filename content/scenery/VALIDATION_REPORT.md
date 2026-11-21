# Scenery source-validation report

Date: 2026-11-21. Target Godot 4.7.2 / Windows / RTX 4050.

## Tests actually executed

- Fetched actual World PR #3 JSON plus 502002 R16 bytes from the connected GitHub repository; decoded unsigned LE centimeter heightfield and used real triangular terrain samples.
- Executed the committed pure JavaScript scenery generator **twice** in an isolated JavaScript runtime using actual world data and the pinned Race PR #10 exclusion snapshot; compared all **13 generated files byte-for-byte**. Result PASS.
- Executed the **independent** committed source validator against the regenerated packs, source graph, R16, metadata, lake mask, metrics and all **102 official race reservations**. Result PASS, **zero errors**.
- Independently inspected 13 original Art PR #7 GLBs' binary mesh/component/triangle headers, plus verified all eight generated original glTF files against their source generation function, internal embedded buffer lengths and accessor counts. Result PASS.
- Checked against **16 physical corridors, 72 turn paths, 11 junction centers** and six unique landmark identities. Source validated each of 2791 placements' road/turn distance, triangle-ground height, slope, architecture footprint, bounds and race-gate margins.
- Maximum pivot-to-R16 terrain height mismatch **0.00083m**; minimum distance to any directed physical lane **5.303m** (furniture outside deck footprint); minimum distance to turn path **27.292m**. Largest approved building/landmark footprint terrain relief **2.97m** (pier shoreline); 32 structural foundations checked.
- Connected Eastwater water: elevation **5.35m**, terrain-source minimum **5.00m**; **5143** cells / **10286 triangles**, each cell's four terrain corner elevations at/below water surface.

## Five pack counts and source-only render budgets

| Pack | Objects | Near mesh triangles (full source instances) | Minimum component/cell batches |
| --- | ---: | ---: | ---: |
| Alder Town | 200 | 117354 | 210 |
| Cedar Woods with Quarry district | 892 | 234896 | 512 |
| North Ridge | 725 | 175488 | 440 |
| Green Valley | 561 | 367638 | 466 |
| Eastwater Lake | 413 | 168788 | 241 |
| **Total** | **2791** | **1064164** | **1857 globally distinct; 1869 if region budgets summed** |

The all-near, all-world batch estimate is **not** actual visible GPU draw calls, because the real model has multiple surfaces and live per-cell and per-asset culling greatly affect on-screen components. One 3D transform per placement at 64 bytes gives **178624 bytes (~174 KiB)** before near/far duplicates, GPU alignment, mesh and driver costs. Lake triangles and model meshes/texture memory are additional. This is not an FPS, VRAM or measured runtime-memory claim.

## Unverified — engine gate still required

Godot 4.7.2 is **not installed in this execution environment**. Therefore the Godot import, GDScript parser, scene loading, smoke.gd, Forward+ graphic rendering, camera traversal, collider physics, FPS, VRAM, visual quality and RTX 4050 benchmark were **not performed**. Generated SVG previews are top-down maps from real inputs, **not** in-game screenshot evidence. CC0 parametric models and starter art remain low-poly and require the documented art-upgrade work to approach semi-realism.

Reproduce with stage, generate --check, models --check, validate, Godot import, Godot smoke and standalone inspection commands in modules/scenery/README.md. Any failure is a real blocker for engine sign-off; do not label this PR engine-verified before those gates succeed.
