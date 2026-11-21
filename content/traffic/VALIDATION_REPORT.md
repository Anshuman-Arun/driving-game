# Verification evidence — world traffic content v1

## Verified from World PR #3 and Traffic PR #4

Source snapshot from World PR #3: road_graph_v1.json, Git blob SHA 9bba378d68879df3baed2c97a4885c0adde88406. Traffic API read directly from Traffic PR #4's traffic_simulation.gd and road_graph.gd. Both dependency PRs were open/unmerged during authoring.

| Test / inspection | Actually executed? | Result |
|---|---|---|
| Read graph and enumerate physical/connector topology with connected GitHub tool + JavaScript assertions | Yes | **309/309 checks passed** on initially authored inventory of 11 nodes, 32 travel lanes, 72 turns, and 22 implicit merges |
| Exact directed topology audit after 2-way crossing correction | Yes | **315/315 fresh connector-side checks passed**; 11 nodes, 8 active controls, 3 pass-throughs, 26 controlled incoming travel lanes, and 22 implicit merge zones inspected |
| Geometric intersection audit from canonical 3D connector polylines | Yes | Crossings found and written to conflict_audit_v1.json; Overlook and Orchard each have four opposing-path XZ crossings at near-identical height |
| Regenerated visual top-down control preview from World data | Yes | SVG source produced from actual 104 directed lanes; manually adjusted label/control color for two extra crossing yield sites |
| Node CLI script tests/validate_content.js executed on Node with a local canonical graph | **No** | Reproducible command supplied; requires temp export/merged World PR file in executing checkout |
| Godot 4.7.2 root editor import | **No** | Godot executable unavailable and main does not yet include dependency source |
| Native GDScript smoke/full scenarios | **No** | Must run after World and Traffic branches integrated; explicitly pending |
| Actual collision shapes, car-to-car physics, controller feel, Windows FPS | **No** | Requires root game world and manual/engine integration |

**No native runtime PASS claim is made.** The 309 initial checks are source-level connector-side assertions, not execution of the committed Node test file. The later topological and geometry checks use the actual remote canonical JSON. The native tests also exercise additional Overlook/Orchard 5/20-density hotspots and are authored to detect (rather than hide) global point overlaps and long waits.

## Candidate crossing conflicts from real connector geometry

Pairs count **different inbound and different outgoing travel lanes** whose turn centerline segments intersect in XZ within 2.5 m of elevation. This is a potential conflict metric, not an exact body-contact count. Latest arc distance is measured on either conflicting turn.

| Junction | Crossing turn pairs | Pairs with at least one crossing after authored clearance | Furthest crossing along a turn |
|---|---:|---:|---:|
| Alder | 82 | 69 | 64.12 m |
| Cedar | 6 | 5 | 54.70 m |
| Ridge | 27 | 23 | 65.50 m |
| Valley | 28 | 23 | 63.74 m |
| Lake | 9 | 9 | 64.47 m |
| Pine | 4 | 4 | 60.46 m |
| Market | 0 | 0 | none |
| Overlook | 1 turn pair / 4 crossing points | 0 | 62.41 m |
| Orchard | 1 turn pair / 4 crossing points | 0 | 60.13 m |
| Depot | 0 | 0 | none |
| Chapel | 0 | 0 | none |

**Blocking risk:** The six multi-arm nodes have centerline conflicts after the common short reservation clearance, yet setting clearance to reach the far crossing would exceed at least one short turn and risk permanent lock. Only simulator API/algorithm changes can solve this completely. Avoid certifying no-intersection-overlap until native tests and an improved reservation model pass.

## Manual/natively executed follow-up

After World PR #3 and Traffic PR #4 are integrated in a throwaway branch/check-out: run the Node validator and both Godot commands in INTEGRATION_NOTES.md; collect per-region density peaks, waits, overlaps and logs. Review traffic at Alder, Valley, Ridge, and long opposing crossings at Overlook/Orchard. Use the real collisions/visual layer for chassis contact and performance separately. Do not merge until reviewer understands and accepts the uncovered intersection-conflict limitation.
