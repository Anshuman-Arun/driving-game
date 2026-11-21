# Race-content integration notes (PR handoff)

## Authoritative inputs and compatibility

- World source: unmerged **PR #3**, `feat/worldgen:data/world/road_graph_v1.json`, Git blob `9bba378d68879df3baed2c97a4885c0adde88406`. The world metadata and road graph use Godot `[x,y,z]`, Y-up, X/Z in [-1000,1000]. No coordinate translation.
- Race API: unmerged, draft **PR #5**, `modules/racing/event_catalog.gd`, `race_route.gd`, `race_engine.gd` and `racer_ai.gd`. Catalog parses `content/races/events_v1.json` without changing code. Every lane route explicitly includes turn connectors, and the last lane of both circuits links to the first.
- Source terrain, road graph, racing module, root Godot project and shared docs are **untouched**. Do not merge a dependency PR implicitly as part of this feature.
- No new assets or outside licenses; SVGs are locally generated from original data.

## Host implementation responsibilities

1. Merge/rebase World and Racing work through the normal integration process. Load graph once and use it for RaceEngine and RacerAI, including turn lanes, not standalone racing fixtures.
2. `RaceEngine.start_event(event)` accepts core fields and applies `corridor_m=12`, `max_speed_mps=65`, countdown, finish grace and max race duration. `finish.position` is informative: the engine determines finish from the route arclength, not a separate trigger. Course completion tolerance in PR #5 is 2.5 m.
3. `start_grid` supplies single-file four-car positions at 7, 17, 27 and 37 m into the first road lane; physical spacing is 10 m and headings are sampled. **Current RaceEngine initializes all racer progress and internal positions at arclength 0**. Merely teleporting four actual cars to this grid during countdown causes a large first update for cars beyond ~5 m, triggering teleport/progress invalidation. The integrator must first add per-racer initial arclength/pose support to the racing engine or use a deliberate staged starting mechanic, then re-test progress. No racing-module files were modified to fake a fix.
4. The `ai_speed_guidance` records are advisory target speeds by arclength (65 m samples, speed limits, curvature, grade, surface). Current `RacerAI` only uses road graph limits + its own curvature estimator and **does not consume** these records. Add an explicit adapter for overrides if desired, calibrated to the actual car.
5. Render physical junction pads/colliders that contain World Agent's entire forward-only turn paths. Some extend approximately 21 m from centerline; the present world data is lane geometry, not a validated road collision mesh. Mark the finish/start line on actual roadway rather than placing props across connector collisions.
6. Gate radius 5.5–6 m, dense ordered gates, an event corridor of 12 m, and the engine's swept checks resist shortcuts. They do not prove a physical player cannot bypass a checkpoint on nearby roads; manual driving and reverse/teleport/off-road tests remain necessary.
7. Reset/collision mechanics belong to the Racing/Core integrator; do not use this data pack to overwrite the world or change vehicle controls.

## Course intent & exact primary lanes

Every transition includes its *unique* matching `turn_*` connector in the JSON/report.

- **Alder Street Circuit**: `alder_depot_ab → depot_chapel_ab → chapel_alder_ab → alder_depot_ab` (closed). Three laps of 877.016 m; tight town layout, three turning connectors.
- **North Ridge Climb**: `valley_lake_ba → ridge_valley_ba` (sprint). 2,393.639 m, ~132 m ascent and 8.882% max absolute sampled segment grade; from lake elevation ~30 m to ridge elevation ~162 m.
- **Eastwater Lakeside Sprint**: `valley_lake_ab → lake_alder_ab` (sprint). 2,184.846 m on asphalt, descending toward Eastwater before the long shore-road run.
- **Green Valley Tour**: `alder_market_ab → market_valley_ab → ridge_valley_ba → cedar_ridge_ba → alder_cedar_ba → alder_market_ab` (closed). 4,814.099 m; 531.841 m gravel at Old Mill Road, 122.004 m ascent/descent and four distinct road regions.

## Validation gates for integrator

```bash
node content/races/author.js --graph data/world/road_graph_v1.json --check
node content/races/tests/test_author.js data/world/road_graph_v1.json
godot --headless --path modules/racing --editor --quit
godot --headless --path modules/racing --script res://tests/run_tests.gd
```

The last two commands are not run by this branch; they are the Racing Agent's standalone tests (with its own fixtures). Add an integrated root-project test that loads all four production events and simulates racing with physical cars; record actual frame rates, controls, collision, gate crossing, reset, finish and AI speed tuning before declaring gameplay production-ready.
