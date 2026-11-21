# Traffic module verification report — 2026-11-21

Branch: `feat/traffic-systems`; write scope: `modules/traffic/` only.

## Verified with actual Godot 4.7.2

[GitHub Actions run 44947002599](https://github.com/Anshuman-Arun/driving-game/actions/runs/44947002599), traffic-only successful job **136979977523**, checked out tested code commit `bd6c6af773b6f3755a7c80f42c03ad4ca1b00212`. Runner: Ubuntu 24.04, Python 3.12.12, **Godot v4.7.2.stable.official.ed1daf0bf** (official checksum-verified installation).

The following independent required gates all passed:

| Gate | Executed command (repository root; CI uses the absolute module path) | Result |
| --- | --- | --- |
| Python fixture/schema checks | `python -m unittest discover -s modules/traffic/tests -p fixture_checks.py -v` | **7/7 PASS** |
| Independent numerical flow reference | `python modules/traffic/tests/reference_flow_sim.py` | **3/3 seeded 90-second runs PASS**, with identical seeded replays |
| Godot project import/parser | `godot --headless --path modules/traffic --editor --quit` | **PASS**, no parser/import errors |
| Actual GDScript simulation suite | `godot --headless --path modules/traffic --script res://tests/run_tests.gd` | **48 PASS, 0 FAIL**; no GDScript parser/runtime errors |

Actual GDScript coverage includes road-graph schema validation and rejection, directed routing and lane continuity, arc-length/curvature sampling, safe spawning, rear-end following/braking, speed limits, player and obstacle avoidance, vehicle-adapter outputs, automatic-vs-manual density lifetimes, stop/signal behavior, merge reservations, dead ends, pooling, despawns, and fixed-seed determinism. The 90-second scene-data stress test covered a 10–20 car population, repeated lane transitions and no observed center-point overlaps. This is **headless simulation verification**: it is not proof of graphics FPS, physical vehicle collisions, controller behavior or integrated open-world correctness.

### Parser and engine failures found and fixed

1. Initial run 44947002599 could not compile `src/road_graph.gd` lines 166 and 170: Godot could not infer the `k` values from expressions involving variant array access. Both interpolation weights now have explicit `float` declarations (code commit `16b59f37122d7369a4ebb019412a79feed838cb8`).
2. After the parser fix, the GDScript tests reached runtime with **36 PASS / 2 FAIL** plus invalid dictionary accesses. The cause was the density manager despawning **explicitly spawned** NPCs on each one-second population sweep when `density_target == 0`. The module now marks cars created by `spawn_near()` as density-managed and only removes those during density reduction. Direct `spawn_agent()` cars remain until explicitly removed, dead-ended or distance-despawned. Added four focused regression assertions for both lifetimes (code/test commits `4d7d33e5a5a62581f56830583897ad1b791d9732`, `bd6c6af773b6f3755a7c80f42c03ad4ca1b00212`).
3. Reran the **real Godot 4.7.2 import and entire GDScript suite**, plus both Python suites, against the corrected branch. All required traffic gates passed.

### Numerical reference evidence

| Seed | Simulated duration | Cars | Lane transitions | Released reservations | Moving agent-steps | Closest center spacing | Replay |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 21 | 90 s | 16 | 92 | 29 | 27,418 | 4.00 m | identical |
| 20261121 | 90 s | 16 | 84 | 28 | 23,078 | 4.00 m | identical |
| 9181 | 90 s | 16 | 93 | 33 | 27,772 | 4.00 m | identical |

These are independent Python reference runs, **not** the Godot GDScript test results. Earlier reference failures also led to fixture fixes: an east/west turnaround crossed its own path, and a feeder/opposing-lane conflict needed a split northbound approach and explicit reservation. Those were already corrected before this CI repair.

### Evidence retention and remaining integration

GitHub Actions logged an artifact storage quota error when uploading evidence, but the traffic job conclusion is **success**, and the full run logs and job summary remain accessible via the linked run. Artifact upload availability did not affect test status.

The standalone Godot demo has not been visually played or FPS-profiled, and player contact/rigid-body promotion, actual World Agent graph integration, racing spawn suppression, and controller behavior remain integration tasks; see `INTEGRATION_NOTES.md`. Do not present the module as fully integrated with the main Godot project.
