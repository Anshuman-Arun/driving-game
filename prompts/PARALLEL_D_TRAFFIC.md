# Track D — Traffic simulation, lanes and vehicle behavior

Implement a standalone, realistically useful **civilian traffic system** for Aster Valley. The core game and world map are being developed independently. Write functioning and testable GDScript in your own module, not edits to the root Godot project.

## Isolation
- Repo: `Anshuman-Arun/driving-game`; branch `feat/traffic-systems` from current main, using a separate checkout/worktree.
- **Exclusive write scope: `modules/traffic/`**. Do not change project.godot, scenes/, addons/, scripts/, worldgen/, data/world/, modules/racing/, assets/, README, AGENTS.md or shared docs.
- Read `AGENTS.md`, `docs/GAME_DESIGN.md`, `docs/PARALLEL_EXECUTION.md`, `docs/INTERFACES_V1.md`. Write interface proposals only to `modules/traffic/INTEGRATION_NOTES.md`, never edit the shared contract.
- Use self-contained fixtures conforming to road_graph_v1. Do not wait for World or Core agents.

## Deliverable
A GDScript traffic module for **10–20 active nearby civilian cars** (performance dependent), driven along directed lane centerlines with intersections, traffic yielding and basic safe obstacle response. Provide inexpensive distant-traffic simulation, deterministic spawning/despawning and a test scene.

## Build
1. Implement a robust directed lane graph loader/validator for `road_graph_v1.json` using `load_road_graph(Dictionary)`. Resolve next_lane_ids and longitudinal sampling along 3D lane polylines, including arc lengths, tangent direction and curve lookahead.
2. Implement agent behavior: target speed based on curvature and speed limits, car following with minimum gap, simple braking for slower lead vehicles, red light/stop decision at defined junctions, wrong-way prevention and sensible handling at dead ends. Separate behavior from physics motion; control outputs should adapt to actual vehicle later.
3. Create deterministic spawn/despawn logic near a viewer position, warm start on valid lanes, avoid car/car and car/player overlap, pool/reuse traffic agents, and optionally reduce simulation rate for far-away vehicles.
4. Provide optional randomized vehicle type/speed/route variation, but all randomness must support a seed for reproducible tests and bug repro.
5. Keep traffic vehicles lightweight compared to the hero car. A kinematic approximation is acceptable for normal cars; collision with the player should be supported via an adapter or documented bounds contract.
6. Build a standalone Godot 4.7.2 test scene inside `modules/traffic/demo/` with a miniature intersection, two-way street, merging flow and 10+ moving placeholder cars. No edits to root project.
7. Write automated tests for lane continuity, directed routing, lane selection, car following, avoid-overlap initialization, smooth path transitions, no out-of-bounds stalls, cleanup, and deterministic results on fixed seeds. Provide commands/output in `modules/traffic/TEST_REPORT.md`.

## Performance and accuracy
Do not claim measured frame rate without running the demo and profiling. Design for many cheap traffic agents, no per-frame full-graph scans, bounded search, and safe handling of zero-length segments or malformed lane data. Keep the behavior inspectable and adjustable.

## Acceptance
- The module parses shared road-schema fixtures and produces valid continuous routes.
- At least one intersection demo with 10 vehicles behaves coherently in executed tests, or exact unverified behavior is identified.
- Following/braking, lane transitions, spawn avoidance and recycling have actual tests.
- Public API and adapter contracts are documented so that the later integrator can attach meshes, rigid bodies, signals and player interactions without rewriting all logic.
- No files outside the owned directory were changed.

## Completion policy
Continue implementation and debugging with available tools until these scoped criteria are satisfied or a real external blocker/tool/context quota forces a stop. Do not return after a design-only response, empty classes or untested scripts. If limited, commit/push a coherent partial module and give honest blocking information. Never claim the full open-world traffic system is integrated before the Core and World branches are merged.

## Git deliverable
Commit and push to `feat/traffic-systems`, open PR `Traffic: civilian lane simulation` if possible, do not merge. Report SHA/PR, benchmark evidence if measured, passing tests, missing manual checks and integration requirements.
