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
