# Aster Valley scenery runtime — Godot 4.7.2

Independent Godot Node3D component limited to modules/scenery/ and content/scenery/. No root project, terrain, vehicle physics, original asset library or other feature branch is modified. The data and GLB sources remain unmerged: World PR #3, Art PR #7, Race Content PR #10, and World Runtime fix PR #16.

## Delivered

- Runtime at src/scenery_runtime.gd: loads five canonical region packs, checks the metadata seed and source world graph counts, adjusts each pivot to the runtime's triangulated terrain height, and groups every asset into 128 m spatial-cell MultiMesh batches. Handles separate mesh components/material surfaces.
- Pine near/far LODs, low/medium/high deterministic density presets, 250 ms camera-distance culling, longer iconic landmark visibility distances, and selective coarse collision for structures and roadside barriers. Plants and loose rocks are deliberately render-only.
- A terrain-conforming Eastwater lake at 5.35 m, constructed only over a connected low R16 basin; no arbitrary rectangular water plane. The water is transparent, low-cost, and non-colliding.
- Eight original CC0 module-local town/landmark glTF models and curated original project GLBs staged read-only from the Art branch.
- Fly-around preview scene at demo/main.tscn; input WASD, Q/E up/down, Shift for fast travel and right mouse drag to look. The preview uses the actual heightfield and allows inspection of all five regions.
- Reproducible top-down SVG maps in content/scenery/previews/ (these are not in-engine screenshots).
- Independent road/terrain/race-zone validator and Godot smoke-test script.

## Reproduce

From repository root with Git, Node.js 20+ and Godot 4.7.2:

~~~sh
git fetch origin feat/worldgen feat/art-pipeline
node modules/scenery/tools/stage_dependencies.mjs origin/feat/worldgen origin/feat/art-pipeline
node content/scenery/tools/generate.mjs modules/scenery/.world_source --check
node content/scenery/tools/models.mjs --check
node content/scenery/tools/validate.mjs modules/scenery/.world_source
godot --headless --path modules/scenery --editor --quit
godot --headless --path modules/scenery --script res://tests/smoke.gd
godot --path modules/scenery
~~~

The staging utility reads exact Git objects without changing remote branches. Generated staging stays in gitignored .world_source/, staged_art/ and staged_models/ directories under the module. The source-only validation tests 16 physical corridors, 72 turns, 11 junctions, 102 real race gates/grids, terrain height, slope and architecture footprint relief. Generate and model --check commands require byte-for-byte identical output.

## Required root integration call

The root project needs the authored scenery assets and World PR #3 metadata/road graph available, Art PR #7 imported, and a World Runtime node with get_world_metadata, get_road_graph, and get_surface_height_at. The integrator owns the root project and should add the following after the world_built signal (not before). Keep both world and scenery at identity world transforms.

~~~gdscript
var script_resource: Script = load("res://modules/scenery/src/scenery_runtime.gd")
var scenery: Node3D = script_resource.new()
scenery.name = "Scenery"
scenery.set("build_on_ready", false)
world_root.add_child(scenery)
if not bool(scenery.call("build_scenery", world_runtime)):
    push_error(str(scenery.get("error_message")))
~~~

To inspect without WorldRuntime, call build_scenery(null, absolute_content_directory, absolute_world_data_directory). In the integrated root project the engine loads curated models from res://assets/curated/ and local new models from res://content/scenery/models/. The standalone inspector instead uses the gitignored staged source copies. Set camera_path if the viewport's current Camera3D is not the primary driving camera.

## Asset quality and performance caveats

This contribution deliberately reuses low-poly starter Art PR models; it is not photorealistic. Project-original module-local models are also intentionally inexpensive silhouette art. Estimate full-world near mesh source triangles and component batches in content/scenery/metrics.json; real draw calls depend on visible cells, GLB surfaces, materials, shadows, LOD and driver settings. Actual Forward+ GPU FPS, VRAM, pop-in, physics integration and graphic quality remain unverified because this execution environment has no Godot 4.7.2 binary. The standalone project is lightweight visual inspection, not a Forward+ benchmark.

Priority art upgrade plan: (P0) authored town garage/facade material and UV polish; (P1) survey shore-to-pier connection in running Godot and replace the placeholder platform; (P2) improve forest crown variations and bark/rock PBR under verified original/CC0 licenses; (P3) RTX 4050 benchmark with actual player-camera/traffic motion and refine LOD/cull distances.

Details: content/scenery/INTEGRATION_NOTES.md and content/scenery/VALIDATION_REPORT.md.
