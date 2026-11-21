# Track B — Original 2×2 km world generator, map and road data

You own the original *Aster Valley* world layout and offline generation pipeline. This is a substantial, implementation-first software task; produce an actual reproducible world-generation system and authoritative road data, not a design essay.

## Isolation
- Repository: `Anshuman-Arun/driving-game`, branch `feat/worldgen` created from current main in an isolated worktree.
- **Exclusive write scope:** `worldgen/` and `data/world/` only. Do not edit `project.godot`, `addons/`, `scenes/`, other modules, common docs, README or main.
- Read `AGENTS.md`, `docs/GAME_DESIGN.md`, `docs/PARALLEL_EXECUTION.md`, and especially `docs/INTERFACES_V1.md`. The interface file is read-only; propose changes in `worldgen/INTEGRATION_NOTES.md`, not by editing that file.
- The Core Agent is separately building a 500×500 m driving test area. Do not wait for it and do not alter it.

## Goal and output
Produce a reproducible, human-auditable offline generator for an **original fictional 2×2 km world**: Alder Town, Cedar Woods, North Ridge, Green Valley and Eastwater Lake. Target 8–12 km of connected drivable roads with an intentional main loop and shortcuts, realistic grades, technical mountain switchbacks, broad fast curves, town streets and at least one gravel shortcut.

## Implementation
1. In `worldgen/`, implement one documented command that regenerates all map data deterministically from a fixed seed. Python standard library preferred; modest dependency allowed if pinned and justified. Do not depend on proprietary maps or paid data.
2. Generate a coherent heightfield with ridges, valley, sloped forest and lake basin. Provide lossless or high precision height source plus preview images; include coordinates, height range, scale, sampling resolution and Terrain3D import guidance. Do not assume an image is already an importable Godot terrain without testing.
3. Hand-author or procedurally solve a drivable topology: useful long roads, consistent gradients, minimum curve radii, town grid and at least four scenic landmarks. Build a connected directed graph with at least two reasonable routes between major regions when feasible.
4. Export exact `data/world/road_graph_v1.json` conforming to `docs/INTERFACES_V1.md`: roads, directed lane centerlines, next_lane_ids, speed limits, surface, unique IDs, meter coordinates and bounds. Lane points must match intended terrain heights; include intersection connections. Provide representative path examples and track actual road length accurately (do not double-count both lane directions).
5. Produce `data/world/world_metadata_v1.json` with region boundaries/landmarks and useful visual previews under `worldgen/previews/` (SVG or PNG top-down elevation/regions/roads). Include an optional clear printable map.
6. Add deterministic validators/tests under `worldgen/tests/` checking JSON schema, connectedness, lane links, 2×2 km bounds, consecutive point distances, unrealistic slopes/curvature, lane-to-height separation, region coverage, map reproducibility and total distinct road length. Repair issues automatically or document justified exceptions.
7. Provide a concise integration guide `worldgen/INTEGRATION_NOTES.md` detailing how Godot Road Generator/Terrain3D can consume the data via adapters later, without changing the actual Godot project.

## Acceptance
- Generation command runs successfully and produces/reproduces the same data from seed.
- Road graph meets the exact shared v1 schema and passes automated graph/geometry validation.
- The world is meaningfully planned (not random spaghetti), with 5 distinctive regions, valid main loop and race-worthy routes.
- Height source is internally consistent with lane elevations and 2×2 km coordinates.
- Previews depict the *actual output data*, not invented concept art.
- A developer can clone this branch, run the generator and inspect the resulting map/graph without any other workstream.

## Completion rule
Keep working through design, implementation, generation, numerical checks and fixes **until the owned deliverable passes all executable acceptance checks**, or a genuine blocker/tool/context quota prevents more work. No early handback after a rough design. Test commands and outputs must be included; do not claim Terrain3D import was tested if Godot import wasn't executed. When constrained, commit/push a usable partial state and list the blockers clearly.

## Git deliverable
Commit/push only owned files to `feat/worldgen`, open a PR `World: generated Aster Valley terrain and road graph` if authorized, do not merge. Report branch, commit SHA, PR URL, road length, number of lanes, heightfield metrics, tests executed and integration caveats.
