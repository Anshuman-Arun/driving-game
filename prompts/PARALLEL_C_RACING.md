# Track C — Race engine, AI rivals and event logic

Build a production-minded, self-contained **racing systems module** for Aster Valley. Work should be real tested GDScript and demo scenes, not architectural pseudo-code. Another agent owns the core Godot project, and another owns the world road graph; integrate through the agreed interfaces.

## Isolation
- Canonical repo `Anshuman-Arun/driving-game`. Create `feat/racing-systems` from the current main in a separate worktree.
- **Write only within `modules/racing/`.** Do not edit `project.godot`, `AGENTS.md`, shared docs, `scenes/`, `scripts/`, `addons/`, `worldgen/`, `data/world/`, `modules/traffic/`, assets or main.
- Read `AGENTS.md`, `docs/GAME_DESIGN.md`, `docs/PARALLEL_EXECUTION.md`, and `docs/INTERFACES_V1.md` (read-only). Any proposed interface change must go into `modules/racing/INTEGRATION_NOTES.md`.
- Work independently with small schema-compliant fixtures; the canonical road_graph_v1.json may not yet exist on your branch.

## Deliverable
A reusable Godot 4.7.2 GDScript module with a **fully testable sprint/circuit race lifecycle and competent, deterministic AI opponent logic**. Use interfaces that can take positions, velocity, steering/throttle/brake commands, a road graph Dictionary and event data rather than depending on someone else's scene tree.

## Concrete work
1. Implement validated event data loading, checkpoint ordering, start countdown, race timer, laps, lap invalidation/anti-cut, finish positions, restart/quit and clean return-to-free-roam state. Provide explicit state transition diagram in module documentation and implement actual transitions.
2. Write race progress calculation based on route spline/projection or ordered checkpoints. Handle shortcuts, out-of-bounds resets, missed checkpoints, ties, looping circuits, reversing and large delta times robustly.
3. Create an AI opponent controller that outputs steering/throttle/brake targets based on road curvature, current speed, lookahead, ideal path, grip limits and basic obstacle-distance inputs. Do NOT build another vehicle physics engine; this should drive a vehicle via an adapter.
4. Supply test event fixtures for a town circuit and mountain sprint whose lane IDs and geometry exist in `modules/racing/fixtures/` matching the shared road schema. Validate race outcomes when competitors finish, collide/reset or skip checkpoints.
5. Build a tiny standalone Godot demo/test harness *inside `modules/racing/`* (a temporary project.godot may live at `modules/racing/demo/project.godot`), using primitive geometry or simplified kinematic vehicle adapters. Do not modify the root project.
6. Add automated/headless runnable tests covering lap counting, timer pause/restart, checkpoint misses, multiple racers, sudden teleports, AI driving lines and corner speed. Keep results/commands inside `modules/racing/TEST_REPORT.md`.
7. Give a narrow integration API (e.g. `load_road_graph(Dictionary)`, `start_event(Dictionary)`, `update_racer_state(id,position,velocity)`, `tick(delta)`), typed where helpful, with no global autoload required.

## Done means
- Full sprint and circuit state machine with tested correct ordering, timing, and finishing.
- AI can navigate at least one representative closed test course in the module demo when actual runtime execution is available.
- Module is importable into later Godot project without rewriting it or assuming fixed scene paths.
- Unit/integration tests run and pass where tools permit. Mark visual driving competence unverified if no interactive runtime.
- Implementation notes list any collision/vehicle adapter assumptions clearly.

## Don't stop early
Work continuously toward the complete scoped module; don't hand back after TODOs, generic APIs or one happy-path test. Use available tool calls to implement, test, debug and improve until exit criteria pass, or you hit a real dependency/tool/context limit. If limited, commit/push tested partial progress and report precisely what is incomplete. Don't claim game-wide integration before the other branches are merged.

## Git
Commit and push only `modules/racing/` to `feat/racing-systems`. Open an unmerged PR `Racing: events, checkpoints and AI rivals` if possible; provide PR, SHA, files and actual test outputs in the final report.
