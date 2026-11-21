# Aster Valley — canonical traffic content v1

This directory contains **road-network-specific authoring**, not an alternative road graph or a replacement traffic simulator. It targets World PR #3 (104 directed lanes including 72 turn connectors) and Traffic PR #4 (TrafficSimulation.configure_junctions).

| File | Purpose |
|---|---|
| controls_v1.json | Versioned inventory of 11 real junctions; eight stop/yield runtime controls and three unimpeded continuations |
| traffic_content_loader.gd | Validates canonical graph, turn reachability, lane mapping, implicit merges, clearance, duplicates and two-way geometric crossings; applies v1 control array |
| scenarios_v1.json | Five real regions × 0, 5, 10, 20 density targets × three fixed seeds plus two crossing hotspots at 5/20, 90-second full mode |
| conflict_audit_v1.json | Actual 3D-height-filtered intersection of directed turn-centerline polylines, with release-distance risk estimates |
| previews/traffic_controls.svg | Top-down SVG traced from the authoritative World graph with the 11 junction markers |
| JUNCTION_INVENTORY.md | Per-node control decisions, speeds, connector lengths and bottlenecks |
| tests/validate_content.js | Node 20+ static graph/content validator, with negative mutation tests |
| tests/run_world_scenarios.gd | Godot 4.7.2 smoke/full suites, deterministic replay, modeled body occupancy, queue checks and separately logged close passes |
| tests/vehicle_clearance.gd | 4.5 m x 1.85 m oriented vehicle footprints and rear-end, turn and merge conflict classification |
| INTEGRATION_NOTES.md | API hookup, reservation safety caveats, commands and ownership handoff |
| VALIDATION_REPORT.md | Evidence and explicit unverified work |

**Important:** World PR #3 and Traffic PR #4 are separate open PRs. This content-only branch is based on main and deliberately does not vendor their source files. Until combined in a disposable integration checkout, the native scripts cannot run as a root Godot scene. The checked-in graph provenance is Git blob SHA 9bba378d68879df3baed2c97a4885c0adde88406.

## Control policy

- Alder, Ridge, Valley: 3 all-approach stop reservations.
- Cedar, Pine, Lake: 3 yield reservations.
- Overlook, Orchard: 2 additional long-clearance yields, because their two opposing turn centerlines cross geometrically despite a two-road topology.
- Market, Depot, Chapel: no runtime controls; these are genuinely non-crossing two-way continuations.
- 22 implicit successor-merge groups are left intact. Eight explicit controls map *incoming travel lanes*, disjoint from the 62 implicit connector-to-merge mappings.

**Safety limitation:** the original Traffic PR #4 simulator releases explicit intersection reservations on the entry turn connector after one common clearance distance. Six complex multi-arm nodes have actual crossings beyond what their shortest connector can safely protect. Longer clearances can deadlock permanently. Full collision-safe junction arbitration needs an upstream simulator change; do not mistake authored stops or point-agent spacing for physical collision certification.

**Native evidence:** Expanded CI retry 44955678724 executed Node/geometry validation and Godot 4.7.2 import, smoke (24 scenarios passed) and full soak (33/72 scenarios failed against the original Traffic PR #4 simulator). See VALIDATION_REPORT.md. The separate simulator fix branch is not the dependency hardcoded by the present CI runner.
