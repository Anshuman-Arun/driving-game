# Aster Valley offline world generator

This directory is the sole author of `data/world/`. The source topology is original and intentionally placed; the terrain texture and road/terrain grading are reproducibly synthesized from seed **20261121**. There are **no external packages or proprietary map inputs**.

## Regenerate and validate

Requires Node.js 20 or newer (tested with Node.js 22.16.0). From repository root:

```sh
node worldgen/generate.js
node worldgen/tests/test_world.js
node worldgen/tests/test_turns.js
```

The first command **overwrites only** the five generated files listed below (all inside the World Agent's exclusive scope). The second command independently builds the same world twice and asserts graph/terrain determinism, exact checked-in file match, topological and geometric validity. The generator itself refuses to export invalid geometry. It is safe to rerun on any operating system with modern Node.

## Generated files

- `data/world/road_graph_v1.json`: strict INTERFACES_V1 directed lane graph with 16 physical road corridors, two driving directions each, 11 explicit junctions and 72 low-speed turning connectors. Tight cubic turns are replaced by forward-only 9 m-radius Dubins maneuvers; the validator requires a minimum sampled 7 m turning radius. Each connector is itself a valid lane. Nominal road width is 6.8 m, two 3.4 m lanes.
- `data/world/world_metadata_v1.json`: five region definitions, landmark positions, generation seed, heightmap format, loop routes, exact measured centerline length and preview metadata.
- `data/world/terrain_height_r16le.bin`: 501×501 **unsigned little-endian 16-bit** raster, elevation in **centimeters**, 4 m XY spacing, rows southward (+Z), columns eastward (+X). Data source is 0.01 m quantized; road lane heights bilinearly sample that exact raster.
- `worldgen/previews/topographic_map.svg`: generated elevation color map and road centerlines.
- `worldgen/previews/road_network.svg`: region/road/landmark printable map.
- `worldgen/previews/junction_detail.svg`: 11-panel real junction turn-path contact sheet; shows directed paths and entry/exit endpoints.

The generator intentionally does **not** edit the Godot project. Terrain3D import and Road Generator mesh/collision integration remain separate tasks. See `INTEGRATION_NOTES.md`.

## Road design

The main touring loop connects Alder Town → Cedar Woods → North Ridge → Green Valley → Eastwater Lake → Alder Town. Needle Pass is the forest ascent, Serpentine Descent is the mountain switchback showcase, South Shore Parkway is the fast scenic lakeside return. The central farm and old-mill roads form an alternate loop. Quarry Gravel Cut, East Slope Road, Old Mill Road, and Lake View Drive provide 22.12% gravel mileage (77.88% asphalt) and distinct slower mixed-surface choices; a small town triangle adds tight low-speed roads. Intersections are authored as directed bezier turn lanes with exact positional endpoint joins, no U-turns.

The binary heightfield is a *source raster*, not a native Terrain3D resource. It also includes a flattened graded road corridor; the SVG water footprint is schematic and should be replaced by a properly shoreline-masked water mesh at engine integration.
