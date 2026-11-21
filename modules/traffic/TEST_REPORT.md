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

## Follow-up: canonical junction safety repair (branch `fix/traffic-junction-safety`)

The original 48/48 standalone GDScript pass reported above was obtained **before**
this change. Do not describe it as a passing result for this repair until a new
Godot 4.7.2 run has completed.

### Source-level reproduction and fix

Inspected [Actions 44955678724](https://github.com/Anshuman-Arun/driving-game/actions/runs/44955678724)
(traffic-content job 137003136543) and the immutable World PR #3 graph blob
`9bba378d68879df3baed2c97a4885c0adde88406`. The earlier integrated
Godot import passed; traffic-content smoke had **42 pass / 8 fail**, full suite
**88 pass / 42 fail**. The content Node validator also fails its separate
`multi-approach control junction_overlook` predicate; no content file is
edited by this repair.

The PR #22 geometric audit identifies real late crossings, far beyond the
legacy global clearance. The six complex controls cover **62 turning
connectors** (Alder 20, Cedar 6, Ridge 12, Valley 12, Lake 6, Pine 6) and
record **130, 7, 44, 48, 31, and 7** crossings, respectively. There are
**66 controlled connectors** including Overlook and Orchard. Canonical
source inspection also confirmed the shortest connector in those six nodes
is **11.5–15.0 m**, whereas some turns are **64.7–68.5 m** long.

The new simulator indexes 3D connector-to-connector proximity once per authored
junction, maps each movement to its own final conflict arc length plus a
6 m exit buffer, and can release on the successor travel lane when a short
connector ends first. Independent reservation keys permit turns whose
connector paths do not conflict while preserving exclusive legacy implicit
merge/fixture controls. Active ownership is released on movement clearance,
despawn or reset. Spawn protection prevents materializing an unreserved NPC
inside a connector's live conflict region. Ordinary opposing travel lanes
are deliberately *not* treated as conflict connectors.

**Important test distinction:** The unchanged PR #22 stress runner counts
*every* center-to-center distance below 3.6 m, including legitimate cars
passing on distinct opposing directional travel lanes separated by about
3.4 m. Such findings cannot honestly be eliminated by changing junction
reservations; the runner must distinguish opposing lanes from genuine
overlaps in its own separate, authorized content change. Its point-distance
assertion has not been removed or disabled here.

### Regression coverage and validation status

`modules/traffic/tests/run_junction_safety.gd` requires an **integration
test worktree** containing PR #3 `data/world/road_graph_v1.json` and PR #22
`content/traffic/controls_v1.json` as read-only dependencies. It asserts
six canonical conflict configurations, late conflicts, short and long
connectors, compatible two-way passing, two conflicting routed cars per
complex junction, safe reservation release, teardown and reset cleanup,
a 20-agent cap, queue limits and 45-second repeated fixed-seed scenarios.

Commands to execute against the repair branch and those read-only inputs:

```sh
godot --headless --path modules/traffic --editor --quit
godot --headless --path modules/traffic --script res://tests/run_tests.gd
godot --headless --path . --script res://modules/traffic/tests/run_junction_safety.gd
godot --headless --path . --script res://content/traffic/tests/run_world_scenarios.gd -- --smoke
godot --headless --path . --script res://content/traffic/tests/run_world_scenarios.gd -- --full
```

**New-branch native execution: NOT RUN.** This ChatGPT execution environment
has no Godot executable and cannot access the repository through its container
network; the connected GitHub API provides source edits, but does not run a
new Godot binary locally. No native or full-world pass is claimed for the
patch. The prior Godot 4.7.2 test results are *baseline evidence only*.
The canonical graph/controls/audit sources were inspected directly through
the GitHub connection, and the branch-only file diff was checked.

This branch intentionally changes only `modules/traffic/`; it does not
change PR #22 validation rules, World data, shared docs, CI workflows or the
other agents' work.
