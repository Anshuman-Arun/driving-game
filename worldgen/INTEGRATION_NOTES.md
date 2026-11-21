# World integration notes (read-only shared contract)

**Owned paths:** `worldgen/`, `data/world/`. Do not edit `docs/INTERFACES_V1.md` or the 500×500 m core driving test scene. These assets are a standalone future-world dataset; no Terrain3D/Godot import or runtime physics test was performed here.

## Coordinate convention and units

**This interface contract takes precedence over the earlier design document.** All emitted points are `[x,y,z]`, meters, +Y up, with X/Z in **[-1000,+1000]** (the earlier game-design anchor table used [0,2000]). Do **not** add 1000 again unless an explicit integration adapter requires it. Raster grid origin is (-1000,-1000), stride 4 m, 501×501 samples, rows +Z, index `iz*501+ix`, and little-endian `uint16` in centimeters. Conversion is `y_m = uint16_le * 0.01`.

## Suggested Terrain3D adapter

1. Read `world_metadata_v1.json` and `terrain_height_r16le.bin` offline, verify byte length **502002** and metadata origin/spacing; convert to float32 height samples using `sample*0.01`. Do not reinterpret R16 bytes as float or big-endian.
2. Resample/build a supported Terrain3D import resource in editor tooling after checking actual Terrain3D 1.1.0 import requirements. Its internal storage and tile resolution may require padding/resampling from this source grid. Maintain correct X/Z origin and Y scale, with a sample-to-world comparison at corners, center and road points.
3. Material/water placement is future art content; the preview ellipse is symbolic, not a collision or shoreline polygon. Lake basin elevations exist in the raster. Add foliage blockers along the outer boundary and distant visual-only silhouettes.
4. The road shoulders were softened in the source heightfield over 13–75 m from the centerline; a final editor road/terrain connector may refine this grading. Do not grade the terrain a second time without sampling before/after heights.

## Suggested Road Generator adapter

1. Parse `data/world/road_graph_v1.json` using schema v1: `roads` contain lane IDs; `lanes` include **directed** lane positions, width, speed, surface, `next_lane_ids`.
2. For every `lane_*_ab` and matching `lane_*_ba`, reconstruct the physical road centerline by averaging corresponding paired lateral offsets (reverse BA sample order). Corridor names/regions/speeds come from their parent `roads` entries; use a total carriageway width of **6.8 m** plus shoulders. `turn_*` lanes are **AI intersection paths, not separate collision strips**.
3. Use Road Generator 0.9.5 meshes and colliders for physical corridor segments, creating explicit junction meshes/collision where necessary. Graph lanes do not themselves guarantee an intersection mesh. Keep the authored node junction center areas open and mesh continuous to avoid gaps/raised edges.
4. Hand off graph directly to racing and traffic loaders. The connector-to-connector graph supports exact point joins; at intersections, an incoming lane transitions to a turn lane, then to the outgoing lane. The exporter excludes same-road immediate U-turns. Cap turn speed to 20–25 kph.
5. Set spawn/respawn points by querying lane positions and road surface raycasts; do not spawn directly at a junction gap. Verify bridge/water/terrain elevations in the Godot editor.

## Verified geometry and limits

The generated 16 undirected physical corridors have **11,976.963 m** total centerline; do **not** double-count reverse lanes or add turn connector lengths. There are **104 directed lanes** (32 traveling + 72 connectors) and **144 directed links**, with strongly connected lane topology, no endpoint gap, and local centerline curvature radius ≥21.89 m for travel lanes. Maximum measured travel-lane grade is **13.61%** on mountain/gravel features (short sections; use advisory speed signs). Quantized terrain height spans **5–240.449 m**. The exact checks live in `worldgen/tests/test_world.js`.

**Not verified:** collision/meshing, Terrain3D native import, user driving smoothness, actual playable road grading after Godot conversion, GPU performance, controller tests, watermesh fidelity. Those require a separate Godot integration and manual playtest.

## Junction curve correction and collider pads

An audit found sharp cubic turning maneuvers with sub-meter effective radius. The exporter now uses a curvature-constrained forward-only **9 m Dubins path** when a compact cubic turn would be unsafe; all 72 connector lanes pass a **minimum 7 m sampled turning radius** validation. Directed endpoints and headings remain continuous. This change requires **no v1 interface schema modification**.

**Integrator requirement:** turn centerlines can travel approximately **21 m away from physical corridor centerlines**. Reconstruct/widen intersection surface pads and collision around actual turn paths; a 6.8 m corridor mesh alone will not support these trajectories. Check junction collider coverage, curbs, NPC tracking and elevation in Godot. Native Terrain3D / Road Generator imports and driving tests remain unverified in this independent PR.

The generated preview `worldgen/previews/junction_detail.svg` overlays all 72 directed turn paths on the actual corridor geometry, with one zoomed panel per junction. Use it to plan collision pads; do not confuse it with a validated Road Generator mesh.
