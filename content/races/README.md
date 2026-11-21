# Aster Valley — production race content

Four authored launch events against the **actual** World Agent's 2×2 km `road_graph_v1.json` on `feat/worldgen` (PR #3), not the Racing Agent's test fixtures. Everything here lives under `content/races/`. The world graph remains read-only.

| Event | Type / laps | One-lap distance | Race distance | Gates | Driving character |
|---|---|---:|---:|---:|---|
| Alder Street Circuit | circuit / 3 | 877.016 m | 2,631.049 m | 10 per lap | High Street / station / chapel; low-speed intersections |
| North Ridge Climb | sprint / 1 | 2,393.639 m | 2,393.639 m | 18 | Continuous +132.019 m ascent from Eastwater toward ridge switchbacks |
| Eastwater Lakeside Sprint | sprint / 1 | 2,184.846 m | 2,184.846 m | 16 | Fast meadow / shoreline asphalt; lake-junction braking |
| Green Valley Tour | circuit / 1 | 4,814.099 m | 4,814.099 m | 34 | Town, gravel farm link (531.841 m), ridge and cedar forest |

Distances use **XZ horizontal meters**, the same route segment metric as `modules/racing/race_route.gd`; ascent/descent use separate Y height differences. Unlike undirected world network mileage, individual events count directed turn-lane geometry and any lane revisits.

## File layout

- `events_v1.json` — ready-to-parse `{schema_version:1,events:[...]}` event catalog with exact **directed** lane IDs, ordered checkpoint spheres, finish and grid poses, laps, difficulty and advisory per-65-m AI targets.
- `author.js` — deterministic, dependency-free Node.js 20+ author / verifier. Its route specs are short primary travel-lane lists; it resolves their unique directed turn connectors from the authoritative graph.
- `previews/*.svg` — top-down previews with the entire real physical road network faintly visible under the selected route and checkpoint sequence.
- `route_report.json` — computed mileages, grade and surface stats, exact lane sequences and the JS progress-pilot result.
- `tests/test_author.js` — independent generated-artifact checks and invalid-graph regression cases.
- `INTEGRATION_NOTES.md` and `TEST_REPORT.md` — host adapter requirements and honest verification boundary.

## Regenerate or validate without touching World Agent files

Since the world PR is not yet on main, use a **separate read-only worldgen worktree** (or another existing checkout of that branch):

```bash
git fetch origin feat/worldgen
git worktree add --detach ../aster-world origin/feat/worldgen
node content/races/author.js --graph ../aster-world/data/world/road_graph_v1.json --check
node content/races/tests/test_author.js ../aster-world/data/world/road_graph_v1.json
```

`--check` is the default mode. It recomputes all events, previews and report, and fails if a tracked artifact differs byte-for-byte. `--write` regenerates **only** the files inside `content/races/` and only after the explicit option is supplied. The tool pins the verified world graph blob SHA-1 `9bba378d68879df3baed2c97a4885c0adde88406` so upstream map edits cannot silently change production courses. If the World PR evolves, review the changes and intentionally update this pin and authored courses; do **not** alter the world graph here.

Once branches are integrated, the same commands work using `--graph data/world/road_graph_v1.json`.

## Runtime consumption

Racing Agent's catalog from PR #5 accepts the event JSON directly:

```gdscript
const Catalog = preload("res://modules/racing/event_catalog.gd")
const RaceEngine = preload("res://modules/racing/race_engine.gd")

var catalog = Catalog.new()
assert(catalog.load_file("res://content/races/events_v1.json"))
var graph = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/road_graph_v1.json"))
var race = RaceEngine.new()
assert(race.load_road_graph(graph))
assert(race.register_racer("player", true))
for id in ["rival_1", "rival_2", "rival_3"]:
    assert(race.register_racer(id))
assert(race.start_event(catalog.get_event("alder_street_circuit")))
```

The Racing Agent's event loader and `RaceEngine.start_event` use `id`, `kind`, `lane_route`, `start_position`, `laps` and `checkpoints`. Extra event fields (grid, finish pose, metadata and AI profile) are **host-owned advisory content**, not automatically consumed by that engine. In particular, its current `_restart_racers` puts **every racer at route arclength zero**, so individual physical grid poses need an upstream engine/bootstrap enhancement before gameplay. Never apply those 7/17/27/37 m grid poses directly to the engine's 60 Hz progress feed without first synchronizing its racer state.

No Godot 4.7.2 runtime, production road colliders, vehicle physics, four-car launch or manual driving test has been run in this race-content branch. See `INTEGRATION_NOTES.md` and `TEST_REPORT.md`.
