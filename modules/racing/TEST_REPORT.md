# Racing systems test report — 2026-11-21

## Executed Godot 4.7.2 checks — PASS

This report supersedes the pre-CI note that the Godot executable was unavailable. The official engine **4.7.2.stable.official.ed1daf0bf** ran on the GitHub-hosted Ubuntu 24.04 validation runner for branch `feat/racing-systems`.

| Gate | Actual execution | Observed result |
|---|---|---|
| Editor import and GDScript parser | `godot --headless --path modules/racing --editor --quit` (equivalent absolute path in runner) | **PASS** — no parser/import errors |
| Headless GDScript suite | `godot --headless --path modules/racing --script res://tests/run_tests.gd` | **PASS** — `RACING TESTS PASSED: 156 checks`; no engine error lines |
| AI + demo kinematic car closed-course simulation | Same Godot GDScript suite, with actual `Node3D` cars attached to active `SceneTree` | **PASS** — completed 1 lap, 4 ordered checkpoints, **0 resets**, **1.98 m** maximum horizontal centerline error, **14.41 m/s** final speed |
| Workflow racing job | GitHub Actions run `44947002599`, job `136980874355` | **success** against commit `c49e651b15c9ee1dd56e2255e3408b1166976c5b` |

- Job evidence: https://github.com/Anshuman-Arun/driving-game/actions/runs/44947002599/job/136980874355
- Original failed job: `136976544186` (two parser errors).
- The CI script uses a failure gate on log `ERROR:` lines as well as process status. The final successful test job had zero GDScript errors, zero runtime `ERROR:` lines and zero test failures.
- **Non-blocking infrastructure caveat:** GitHub Actions rejected the optional artifact upload due to storage quota. The Actions job was successful and the full test output remains available in the job log.

## Actual fixes and regression coverage

1. `race_engine.gd`: explicit `float` declaration for dynamically accessed route finish distance; valid integral JSON number acceptance for `laps`, rejecting fractional/invalid values.
2. `race_route.gd`: explicit `Vector3` typing at circuit endpoint heading computation.
3. `event_catalog.gd`: parse malformed event JSON through `JSON.new().parse()` and report a normal validation error, rather than having `JSON.parse_string()` emit an engine error for expected negative tests.
4. `tests/run_tests.gd`: corrected grid/countdown elapsed-time arithmetic, validated fractional lap rejection, deferred tests until the SceneTree root is active, attached test `Node3D` vehicles, and freed test nodes.

The suite exercises schema/graph validation, invalid events, sprint and circuit progression, timer and pause/restart/quit transitions, standings, ordered checkpoints, lap resets, reverse movement, teleport detection, shortcuts, missed/out-of-order gates, collisions and airborne/out-of-world recovery, coarse-tick crossing of multiple gates, AI steering, obstacle speed reduction, the adapter, and a full closed-course AI run in Godot.

## Earlier independent checks (not substituted for engine execution)

A separate static fixture/geometry analysis found two roads, eight directed lanes and two fixture events; ~845 m town circuit, ~685 m ridge sprint, non-overlapping route checkpoints and maximum ridge grade 7.84%. A JavaScript pilot had predicted one lap with ~1.98 m maximum route error. That pilot remains independent evidence only; the actual Godot GDScript AI simulation has now independently passed as reported above.

## Still unverified / out of isolated module scope

- **Manual interactive demo playtest:** No human inspected the rendered scene, driving visuals or AI behavior on a real viewport.
- **Game-wide integration:** Not yet connected to the Core Agent's actual physics/vehicle controller, canonical World Agent map, Traffic Agent data or production race content.
- **Hardware and Windows verification:** No measured FPS/performance, physical driving/grip/suspension/collisions, gamepad/keyboard input validation, packaged Windows build or export.
- Temporary town and ridge fixtures are not production-length events and use module-local lane IDs.

This PR remains draft/unmerged. The validated scope is standalone **headless Godot 4.7.2 racing module execution**, not full-game acceptance.


## Production-readiness addendum — 2026-11-21

**New branch:** `feat/production-racing-readiness` (created from `feat/racing-systems`, only `modules/racing/` writes). The previously verified **156 GDScript checks** belong to the parent racing commit and are not a claim about this new branch. The original `tests/run_tests.gd` is unchanged.

**Read-only data inspected:** World #3 canonical graph blob `9bba378d68879df3baed2c97a4885c0adde88406` (104 directed lanes) and Race Content #10 event JSON blob `53f4af72609e3fc033bf90813c3d898b20f6798a`. An independent JavaScript source-data geometry audit was executed against these exact GitHub files. Measured directed-route lengths from the source polylines (XZ):

| Event | Lane IDs | Laps | Gates per lap | Measured lap distance | Authored grid offsets |
|---|---:|---:|---:|---:|---|
| Alder Street Circuit | 6 | 3 | 10 | 877.016326 m | 7, 17, 27, 37 m |
| North Ridge Climb | 3 | 1 | 18 | 2393.638867 m | 7, 17, 27, 37 m |
| Eastwater Lakeside Sprint | 3 | 1 | 16 | 2184.845651 m | 7, 17, 27, 37 m |
| Green Valley Tour | 10 | 1 | 34 | 4814.098819 m | 7, 17, 27, 37 m |

For each event, all authored starting positions projected onto their claimed route arclength within **0.0004 m** and all headings aligned with the sampled tangent (`dot > 0.9999`). Gate centers projected onto route lines within approximately **0.0006 m**. All 80 gate positions were checked against their respective route data, and each event's first gate is approximately 68 m along the route, after the final 37 m grid slot. These are independent **source-data geometry checks**, not engine tests.

**New runtime test suites (added, not yet executed in this environment):**
- `tests/run_grid_tests.gd`: isolated four-car 7/17/27/37 m regression using existing miniature fixture; checks countdown, grid order, 3-lap circuit completion and ordered gates, invalid grid rejection, collision/reset invariants, full restart and legacy compatibility.
- `tests/run_production_tests.gd`: requires graph and events via `--graph=...` and `--events=...` CLI flags; rejects missing inputs. Calls **actual EventCatalog, RaceRoute, RaceEngine, RacerAI GDScript** for each of the four production events, checks sequence, starting transforms, gates, countdown, race completion, restart, anti-teleport reset, AI guidance and results.

**Execution status:** The environment running this branch's GitHub connector has no Godot binary, and its container cannot resolve the private GitHub host. The pre-existing CI run was on **another branch/commit**, not these code changes. Therefore the four exact Godot 4.7.2 commands in README.md have **not** been executed on this branch. Do **not** count the new GDScript tests as passing until a native Godot 4.7.2 run or a correctly targeted CI workflow produces clean logs. No physical car, viewport, Windows build, gamepad or world-collision verification was performed.

**Next verification:** stage the two real external JSON sources as documented in README.md; run editor parser/import, original 156-check suite, new grid regression and all-four-event production harness using Godot 4.7.2, fix any concrete GDScript failure under `modules/racing/`, then integrate with the physics/world host and tune cars against rendered junction colliders.


**Independent behavioral pilot (source-based, not Godot execution):** A JavaScript geometry/progress model consuming the same two authoritative JSON sources simulated four 2.5 m/0.15 s route-following racers per event, with per-racer initial arclengths, the engine's XZ route projection, wrapped circuit progress, corridor and gate-order checks. All 16 simulated racers reached their finish thresholds without a modeled invalid-progress event: Alder 30/30 gates each (3 laps), Ridge 18/18, Eastwater 16/16, Green Valley 34/34. This does **not** validate GDScript parsing, signal emission, Godot timings, physics or graphical driving; the new GDScript test runners are authoritative only once executed under Godot 4.7.2.
