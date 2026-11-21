# Verification evidence — world traffic content v1

## Canonical, read-only sources

- World PR #3 `feat/worldgen` Git commit `306d0be4a1fe72d8c529a1ab2b44e29a911da3a4`; road-graph blob `9bba378d68879df3baed2c97a4885c0adde88406`.
- Traffic PR #4 `feat/traffic-systems` Git commit `487efc69a0564a32ac150e5bf6d811838ecf6cbe` (original simulator used by expanded CI).
- Simulator agent's separate `fix/traffic-junction-safety` branch commit `da5f5dde0066eb3ab29cb05af739cf5970fe7468` is **not tested by this CI**. Its code is never copied into this PR.
- Source is [PR #22](https://github.com/Anshuman-Arun/driving-game/pull/22), write scope `content/traffic/` only. All PRs remain unmerged.

## Real executed CI evidence

Runner: [Expanded CI run 44955678724](https://github.com/Anshuman-Arun/driving-game/actions/runs/44955678724), rerun attempt 3 (traffic job `137010949792`, content SHA `be3aab6d9f53235822f72afa7e68b6de847a9ea1`), Node 22.16.0 and Godot 4.7.2.stable.official.ed1daf0bf. The runner checked out the live content branch and staged the world and original traffic simulator as **read-only dependencies**, not as commits in this branch.

| Executable gate | Result against original simulator |
|---|---|
| `node content/traffic/tests/validate_content.js <canonical World graph>` | **PASS**, topology/content audit, **14 negative mutations** and SVG provenance; 11 real nodes, 8 controls, 22 implicit merges, unchanged canonical lane IDs |
| Godot `--headless --editor --quit` import | **PASS** in disposable standalone traffic-native project |
| Godot native `--smoke` (15 seconds/case) | **PASS**, **24/24 cases**, **68 pass / 0 fail** checks; deterministic replay included |
| Godot native `--full` (90 seconds/case) | **FAIL**, **33 of 72 cases** have real modeled occupancy or persistent queues; **131 pass / 33 fail** checks; replay deterministic |

The first expanded CI attempt ran an older content commit and failed the static `multi-approach control junction_overlook` assertion plus old blanket `<3.6m` point-gap checks. Its static topology mismatch is fixed in the branch. The third CI rerun passed the additional folded-lane geometry regression and verified the revised diagnostic classification; its full suite still fails 33 of 72 scenarios against the original simulator. **Do not report a pass for the simulator safety/full gate.**

## Real 90-second scenario failures vs harmless lane proximity

The helper `tests/vehicle_clearance.gd` compares conservative **4.5 m × 1.85 m** XZ oriented rectangles (four SAT axes), **1.7 m vertical** occupancy, and **5.0 m same-directed-lane arc headway**. The simulator provides state positions/tangents; this is an explicit approximate body-occupancy test, not a rigid-body collision measurement. Opposing road lane centerlines ~3.4 m apart produce many Euclidean point gaps below the old 3.6 m rule **without** footprints touching. Those close pair-tick samples are counted, not automatically failed. Same-lane headway, body contact on turns, converging merge contact, grade-consistent different-lane body overlap, and waits/held reservations over 30 seconds remain hard failures.

| Scenario site | 90 s cases failed / run | Benign close pair-tick samples | Distinct modeled body conflicts | Other hard failures |
|---|---:|---:|---|---|
| Alder town | **6 / 12** | 1,524 | 32 turning, 3 cross-lane, 2 merging | None |
| Cedar woods | **8 / 12** | 507 | 18 turning, 4 same-lane occupancy | None |
| North Ridge | **0 / 12** | 107 | 0 | None |
| Green Valley | **8 / 12** | 1,207 | 48 turning, 12 cross-lane, 4 merging, 3 same-lane occupancy | None |
| Eastwater Lake | **8 / 12** | 915 | 23 turning, 11 merging, 2 same-lane occupancy | None |
| Overlook crossing | **0 / 6** | 265 | 0 | None |
| Orchard crossing | **3 / 6** | 813 | 0 | Queue wait exceeded 30 s (max ~48.63 s) |
| **Total** | **33 / 72** | **5,338** | **162** distinct body-overlap pair/type events | **3** queue-failing cases |

`Benign close` counts are pair-timeslice samples, not distinct vehicle pairs and not all located at the junction itself. Body conflict counts are de-duplicated per agent ID pair and conflict type **within each scenario**, not unique physical crash incidents across seeds. The final full rerun records 121 turning + 15 cross-lane + 17 merging + 9 same-lane **body occupancy** events; the arc-based rear-end guard is independently tested. These same-lane body hits can occur across spatially folded connectors and should not be mislabeled as rear-end incidents. Different density and seed replays can revisit the same geometry; these metrics do not prove crash frequency in gameplay.

Representative verified cases: Alder's chapel-to-market turn overlaps a depot lane at ~4.253 m center distance (long body diagonal), Cedar's hairpin/return connector can occupy itself with cars at far-separated arc coordinates (not necessarily a rear-end), Valley turning movements intersect outgoing/approaching lanes, Lake's different turn paths overlap, and Orchard traffic develops >30-second queues at high density. Ridge and Overlook passed their native 90-second cases despite close opposite-lane center points.

**Interpretation:** The point-gap false positives are now filtered by actual modeled body geometry; the 33 full failures must not be waived. The original short common reservation release at multi-arm nodes and long-held Orchard yield are likely contributors, but the simulator owner must verify whether the isolated repair removes every conflict and queue. In the absence of a successful full rerun against the repaired simulator, this pack is **not integration-safe/collision-certified**.


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

**Original simulator blocker:** The six multi-arm nodes have centerline conflicts after the common short reservation clearance, yet setting clearance to reach the far crossing would exceed at least one short turn and risk permanent lock. Only simulator API/algorithm changes can solve this completely. Avoid certifying no-intersection-overlap until native tests and an improved reservation model pass.

## Unresolved dependency and precise next verification

The expanded CI workflow on `feat/ci-expansion` currently hardcodes a checkout of `feat/traffic-systems` for traffic-native tests. It **does not** stage `fix/traffic-junction-safety`, so we cannot truthfully claim it verified the simulator owner's patch. Staging a different simulator checkout would require a CI-owner change (outside the exclusive `content/traffic/` scope), or a **disposable uncommitted integration workspace** in which the fix branch is used as a read-only source. Do not modify `modules/traffic/`, `data/world/` or `.github/workflows/` in this PR.

Re-execute the same Node check, Godot 4.7.2 editor import, 15-second smoke (24 seeded scenarios × two deterministic replays) and 90-second full (72 seeded scenarios × two replays) with the repaired simulator. Review every modeled body conflict, lane transition, queue >=30 seconds, reservation hold >=30 seconds and replay discrepancy before declaring green. Real chassis contact, dynamic vehicle graphics, player driving, Windows export and FPS remain **unverified**; these kinematic rectangles are diagnostic proxies only.

Ownership policy supersedes the general `AGENTS.md` recommendation to edit `docs/PROJECT_STATUS.md`: the integration owner must update shared status and stage the repaired simulator, not this content-only PR.
