# Racing systems test report — 2026-11-21

## Checks actually executed

| Evidence gate | Method | Observed result |
|---|---|---|
| Branch publishing | GitHub branch/ref/write/commit operations | Created feat/racing-systems from main; changes confined to modules/racing/ |
| Fixture parsing | Loaded committed JSON content from GitHub into an independent JavaScript validator | PASS: 2 roads, 8 directed lanes, 2 events |
| Geometry, gate order and closure | Independently projected JSON checkpoint centers onto the actual committed polyline segments | PASS: town circuit ~845 m, gate arclengths ~143/314/486/737 m, closed endpoint gap 0 m; ridge sprint ~685 m, gate arclengths ~127/286/455/624 m |
| Terrain grade | Measured absolute rise/run for all road fixture segments | PASS: max measured grade 7.84% on ridge_b |
| AI numerical pilot | Independent JavaScript reproduction of the steering, curvature-speed, throttle/brake and demo bicycle formulas (dt=0.05 s) on the committed town fixture | PASS **for the independent model only**: 1 closed lap, all 4 gate regions, ~59.7 simulated seconds, ~1.98 m maximum horizontal road-centerline error, no recovery |
| Source builtin argument inspection | Inspected all 8 existing Godot scripts for minf/maxf/clampf/atan2/absf/roundf/is_equal_approx invocation arity after correcting an earlier bug | PASS: no wrong-arity calls found |

These are **data and mathematical checks**, not actual execution of GDScript or the Godot scene. They are not evidence that the headless suite or interactive demo works.

## Authored but NOT executed: Godot headless/visual checks

~~~bash
godot --headless --path modules/racing --editor --quit
godot --headless --path modules/racing --script res://tests/run_tests.gd
godot --path modules/racing
~~~

**Blocker:** The execution container has no Godot executable; the local git clone also cannot access github.com via DNS/network. An attempt to locate/download the official Godot 4.7.2 Linux build yielded no runnable binary. As a result, there are **zero claimed passing GDScript tests, zero claimed scene imports, and zero claimed Godot screenshots/playtests**. No Test Report text should be interpreted as a pass for these commands.

The source of tests/run_tests.gd contains executable Godot tests intended to check:
- schema-v1 road IDs, lane/point validation and event rejection;
- GRID → COUNTDOWN → RACING timer splitting, pause/resume, restart and abort/return;
- complete sprint and multi-racer finish order, standings and results;
- circuit checkpoint order and three completed laps;
- reversing without progress, sudden teleports, cuts and missed/out-of-order gates;
- reset replay in a later lap, collision-related reset and airborne invalidation;
- a large physics step that crosses *two legitimate checkpoints in order*;
- steering sign on opposite sides of a road, curve speed reduction, obstacle braking and adapter behavior;
- the actual GDScript AI plus the demo kinematic vehicle completing one closed loop within a bounded deterministic simulation.

The suite has not been run in Godot. If an engine parser/runtime failure appears, fix it before treating this branch as a completed, verified racing implementation.

## Still unverified or outside isolated scope

- Godot 4.7.2 GDScript import/parser and runtime tests, and whether the standalone 3D demo renders/plays as intended.
- Integration with the Core Agent's actual physics, World Agent's canonical road graph, Traffic Agent's sensing/traffic, and real map event data.
- Production collisions, vehicle suspension/grip, keyboard/gamepad handling, Windows export, framerate and visual driving competence.
- The intended 1.5 km town circuit and 2.3 km mountain climb: local fixtures are deliberately smaller test courses.

**Next execution gate:** Run both Godot headless commands above, capture exit status/output, correct any parser/runtime errors and update this report under modules/racing/. Then play the demo and integrate only after the other branches have been reviewed/merged. Do not equate the independent JavaScript pilot with a Godot pass.
