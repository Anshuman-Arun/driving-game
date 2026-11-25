# Current-main map width integration

## Final scope — map-only handoff (2026-11-25)

Base: `ffb791f60afbbf9e8ef98af4c26038d7350bbc89` (main, PR #41). Selective geometry port from PR #38; no wholesale merge. The canonical 2 × 2 km map, 104 directed lanes, 16 corridors, 11.72 km centerlines, original heightfield, water, races, six-car roster, premium art, audio and all traffic source/test files remain identical to main.

- Corridor pavement targets 8.4–11.2 m; shoulders 2.0/1.6 m; junction buffer 1 m; bridge tapers and fourth, 105 m supported Meadow Causeway span. Existing legacy bridge widths and water retained.
- Length-weighted average paved width 7.023 → 9.865 m, approximately 33,309 m² added pavement and 12,129 m² added shoulders (geometric plan areas).
- Preserve triangle-based road clearance, signed metric marking UV2, concrete bridge shader and premium vegetation cache. Relocate only affected guardrails with true transformed clearance, original bearing/side, maximum 3 m displacement, height and grade constraints.
- Keep regression fixes for the real four-mode camera, missing-LOD negative fixture, and fuel-station standalone fixture/manifest. No production camera, car, audio, racing or traffic runtime edits.

## Verified evidence

[Run 45692184040](https://github.com/Anshuman-Arun/driving-game/actions/runs/45692184040) on 1b25a33: Godot root, standalone, data and strict production audio jobs all passed. All map/runtime and integration fixtures retained in the map-only revision.

| Gate | Observed |
| --- | --- |
| Full-width road collision | 1,782 edge rays; zero failures or seam rechecks |
| Lane collision | 2,450/2,450 |
| Bridge crossings | Four live chassis crossings |
| World driving | All 16 corridors, six vehicles |
| Vehicle integration | Three live road/grass/gravel routes, zero failures; camera modes and showcase pass |
| Vegetation | 230,076 baseline → 222,579 retained, all poses identical; all 7,497 removed explained by exact road clearance |
| Authored scenery | 3,482 render instances and 1,058 colliders, zero road overlaps |
| Guardrails | 130 accepted vs 124 baseline; 85 relocated, zero unresolved |
| Standalone, race/data, audio | Passed |

## Independent traffic follow-up

The baseline canonical queue stress suite has two inherited failures (990/984 ticks against the strict <900 limit; basic fixtures 48/48, advanced 83/85). The prior combined revision tested a mandatory stop-dwell correction (902/984 ticks, 87/89 advanced, safety and replay true), and rejected routing/convoy experiments after they worsened flow. Preserve the diagnostic history and candidate patch at [1b25a33](https://github.com/Anshuman-Arun/driving-game/commit/1b25a331bbe9209f3f859cc99fe2ee2bddc8ba4b); both traffic files are restored byte-for-byte from main for this map handoff. No traffic changes are included in the net PR diff.

The branch-specific map workflow still runs baseline traffic data and basic GDScript fixtures. Its independent canonical traffic stress suite requires the unmerged controls pack from #22 and is now a clearly labeled manual opt-in via workflow_dispatch input canonical_traffic. The same original test and strict thresholds remain unchanged, and a requested diagnostic still fails on failure. This is scope separation, not a claim that canonical traffic passed. Dedicated connector/throughput and live-world integration work belongs in a separate traffic PR.

## Remaining acceptance

Final isolated revision gets its own CI run. Windows graphical driving, controller hardware, guardrail visual continuity, FPS and subjective audio acceptance remain unverified; headless tests cannot establish those. Existing engine cleanup warnings are not fixed. No merge to main by the agent. For graphical acceptance compare against docs/WORLD_VISUAL_QA.md and docs/SCENIC_SUPERCARS_QA.md.
