# Aster Valley — world runtime module

**Scope:** standalone Godot 4.7.2 world import and generated mesh/collision, under modules/world_runtime/ only. It consumes **World PR #3 (feat/worldgen)** read-only and can interoperate later with **Core PR #6**. It does not re-author the road graph or terrain, merge other PRs, or depend on an installed Terrain3D/Road Generator add-on.

## Run with authoritative map data

From repository root (Git, Node.js 20+ and Godot 4.7.2 required):

1. Fetch the unmerged World Agent source without merging it:

    git fetch origin feat/worldgen

2. Stage its exact three files in this module's ignored directory (binary safe on Windows):

    node modules/world_runtime/tools/stage_world_data.mjs origin/feat/worldgen

3. Validate the actual R16 and road graph:

    node modules/world_runtime/tests/verify_world_data.mjs modules/world_runtime/.world_source

4. Godot parse/import gate:

    godot --headless --path modules/world_runtime --editor --quit

5. Godot physics/collision smoke tests:

    godot --headless --path modules/world_runtime --script res://tests/smoke.gd
    godot --headless --path modules/world_runtime --script res://tests/smoke.gd -- --full-world

6. Launch the inspection project:

    godot --path modules/world_runtime

Godot executable may be named godot4 or Godot_v4.7.2-stable_win64_console.exe. The local staging script reads origin/feat/worldgen with git show; it **only** writes files under modules/world_runtime/.world_source/ and that directory is gitignored. No canonical world files are changed.

Alternatively, use an absolute path without staging:

    godot --path modules/world_runtime -- --world-data-dir=/path/to/authoritative/data/world --full-world

The preview defaults to an ~460 m radius around Alder Town. The --full-world option builds all 2×2 km (501×501 source samples). Mouse click captures look; WASD fly, E/Q vertically, Shift for fast motion, Escape releases the cursor. Terrain has 128 m chunks (32 cells), with a static mesh collider for each generated chunk. Rendering the full world is a costly diagnostic mode; the bounded preview is better for quick iteration.

## Integration contract

Load src/world_runtime.gd as a Node3D in the parent game, set build_on_ready=false if you must configure it first, then call build_world("/absolute/world-data-directory"). APIs:

- get_road_graph(): Dictionary — exact, unmodified directed INTERFACES_V1 graph, for traffic and racing.
- get_world_metadata(): Dictionary — source metadata including raster origin, spacing and scale.
- get_height_at(x,z): float — bilinear R16 height; get_surface_height_at(x,z) returns the precisely triangulated mesh height.
- get_physical_road_centerlines(): Array[Dictionary] — **16** AB/BA averaged physical corridor centerlines with names, width, surface and speed. No turn-strip duplication.
- create_height_image_rf(): Image — 501×501 FORMAT_RF, heights in meters, for a deliberate Terrain3D import workflow.
- world_built(report) / world_failed(reason) signals and report/error_message properties.
- Material override hooks for terrain, asphalt, gravel, shoulder. UVs tile in meter space and assets can later be assigned without changing mesh topology.

The component uses script-local dynamic loads so its source can be loaded from the root project at res://modules/world_runtime/src/world_runtime.gd as well as from its standalone project. It requires no changes to project.godot or other workstreams. Instantiate at global origin with default transform (the map uses absolute world coordinates in [-1000,+1000]); use an enclosing parent transform only if integrating with an explicit coordinate adapter.

### Geometry

- Terrain: a 501×501 unsigned little-endian R16 centimeter raster, 4 m sample spacing. Mesh chunks align exactly to source vertices, with consistent +Y winding and normals; triangle interpolation matches the mesh diagonal. Each chunk has a ConcavePolygonShape3D StaticBody3D.
- Physical roads: only roads with paired lane_<road_id>_ab and _ba lanes. Reverse the BA points, average the pair to reconstruct one centerline, and extrude a 6.8 m two-way deck with 1.35 m shoulders. The physical surface is never doubled by using separate directed lane meshes. Mesh and collider share the same geometry.
- Road grade: honor the authored center Y and local terrain surface; top of each road edge is at least 7.5 cm above terrain. Outer shoulder edge buries 8 cm into the actual terrain triangle surface to prevent exposed cracks; expect soil/pavement overlap at the feathered seam rather than topologically welding separate meshes.
- Intersections: group the 72 actual turn lanes by junction, widen their sampled centerlines by half-lane width + 3 m, build a convex hull pad for each of the 11 junctions, then clip a 2 m grid to the hull. Pads are terrain-conforming, have independent collision and cover all wide turns (~21 m lateral excursions); dense-grid clipping preserves pad boundary continuity. Mixed-surface junctions use asphalt where any turn is asphalt, otherwise gravel.
- Material: built-in neutral placeholders only, ready for licensed PBR materials. UV coordinates are based on world meters and longitudinal road distance.

## Verification and performance reporting

The Node preflight reads and checks **actual source files**: schema, metadata, LE decoding, byte length, lane links, source height agreement, travel grades, paired-lane geometry, consistent terrain/road seam construction, turn-path coverage and real junction hull area. It also prints **predicted** full-world terrain/road triangle counts; these are not a substitute for Godot runtime tests.

The Godot smoke script checks the real generated meshes and collision shapes, confirms terrain vertices and corridor widths, and raycasts against Alder turn pads. In the --full-world variant it checks 11 junction pads and all 72 turn paths. Each runtime build logs a report including actual generation wall time (ms), mesh vertex/triangle counts, static collider count, and Godot Performance.MEMORY_STATIC in bytes. VRAM, FPS and real vehicle tire contacts require a graphical scene with Core PR #6 after integration; these are **not** measured by the source-only validator.

See INTEGRATION_NOTES.md for Terrain3D 1.1.0, Road Generator 0.9.5 and Core PR #6 handoff. The standalone project must not be treated as a native Terrain3D/Road Generator installation or as proof of actual driving without running the listed Godot gates.
