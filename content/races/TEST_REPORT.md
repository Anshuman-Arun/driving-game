# Race content — verification report

Source inspected: authoritative World PR #3 graph (104 directed lanes: 32 travel + 72 turn lanes), Git blob `9bba378d68879df3baed2c97a4885c0adde88406`. Contract inspected: `docs/INTERFACES_V1.md`, Racing PR #5 event catalog, route configuration, progress/finish gate implementation.

## Executed through connected GitHub runtime / independent JavaScript evaluator

- Fetched and parsed the actual 408,985-character graph; generated the four events, four SVGs and report. Verified GitHub commit for all seven original files.
- Validated 100% of authored route lane IDs, directed transitions, <=6 m connector gaps, turn and closure heading constraints, XZ route lengths, grades, road surfaces and physical grid spacings.
- Validated gate projection/order against the Racing Agent's projected arclength criteria: 10/18/16/34 ordered gates per lap, 5.5–6 m radius, no nonlocal segment within gate radius +3 m, coverage gaps <=215 m.
- Ran independent discrete progress simulation using the Racing Agent's distance/ordered swept-gate/finish-threshold logic: all 4 events completed, 0 detected invalid progress. Alder's 3 laps produced 30 gate hits.
- Exercised malformed graph cases; graph hash mismatch, missing lane, broken directed successor, duplicate consecutive point, invalid bounds and removed turning successor were rejected.
- Recompiled committed `author.js` as JavaScript source and independently regenerated an event catalog identical to the committed JSON.
- Follow-up corrected a CLI blob-hash null-byte escaping issue; it was found before creating this report.

| Event | Course meters | Lap(s) | Checkpoint hits in pilot | Outcome |
|---|---:|---:|---:|---|
| Alder | 877.016 | 3 | 30 | PASS |
| Ridge | 2,393.639 | 1 | 18 | PASS |
| Eastwater | 2,184.846 | 1 | 16 | PASS |
| Green Valley | 4,814.099 | 1 | 34 | PASS |

The progress pilot traverses ideal lane geometry, not real vehicle physics and not the actual Godot GDScript runtime. A separate test file exists for rerunning independent offline Node assertions in a worktree with the World graph.

## Not executed / outside scope

- Godot 4.7.2 import/parse and `RaceEngine.start_event` in a live running engine.
- The `node content/races/tests/test_author.js` command in a local worktree with the full World dataset (private GitHub cannot be cloned by the available local container's DNS/network connection). The JavaScript generator and progress pilot **were** executed against the exact connected graph.
- Scene roads/junction collider coverage, physical cars and their staggered start grid, manual checkpoint cutting, AI steering/vehicle handling, user input, GPU/Windows export, progression.
- PR #3 and PR #5 remain unmerged. The direct loader/route compatibility is checked at code/geometry level, not established by an integrated Godot boot test.

**Do not claim game-wide or Godot runtime test success from this report.**
