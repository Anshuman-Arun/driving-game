# Racing module integration notes / handoff

No edits to the frozen docs/INTERFACES_V1.md are proposed. This module consumes that exact road graph v1 format. Only modules/racing/ is modified.

## Integrator checklist

1. Merge the World Agent's completed map separately. Load data/world/road_graph_v1.json and pass the Dictionary to RaceEngine.load_road_graph() and RacerAI.configure(). Check last_error and do not silently bypass disconnected routes.
2. Author race events using real **directed** lane IDs in travel order; choose ordered checkpoint centers on the road and nonoverlapping radii. For circuit routes the last lane must explicitly point back to the first. The local fixture IDs are not production IDs.
3. Wrap the Core Agent's actual Easy Vehicle Physics controller with set_drive_input(steer, throttle, brake, handbrake), plus accessors for world position, forward, velocity and physical reset. Do not replace its controller or edit vendor add-ons to suit the demo. RacerAI is a planner, not a physics implementation.
4. Every 60 Hz physics frame, gather each vehicle's normalized pose/velocity, apply AI commands for the AI vehicles, update_racer_state once per vehicle, then race.tick(delta) **once**. The authoritative player car can use the same progress feed, but inputs stay with InputRouter.
5. Project obstacle sensor outputs into forward distance_m (positive ahead) and lateral_m (signed offset). The planner brakes for obstacles in its lane. Passing, right-of-way, traffic lights and complex collision avoidance remain unimplemented and belong to the integration/traffic systems.
6. For engine.needs_reset(id), use engine.reset_racer(id) to get position/forward then reset the **physical** car and velocity; a recovery replays the current lap. Call report_collision(id, relative_impact_speed_mps) for vehicle collision information. The racing engine never teleports scene nodes itself.
7. Wire state_changed and other signals to HUD, menus, race grid and results. Handle FREE_ROAM by removing race-only rivals, restoring player input and preserving any external progression data. No global singleton is required.

## API expectations and assumptions

- Godot 4.7.2 standard GDScript. Internal script imports use relative preload paths. The standalone scene/project are for test purposes and are **not** the root-project scene tree.
- World uses X east, Z south, Y up, meters. The road graph is centerline geometry, not collision or scene instantiation. Heights are retained; race projection is principally XZ.
- Start all registered racers near the route start; countdown positions must remain stable, and race.tick() processes observations only once RACING is entered.
- Fixed-delta driving is recommended. A large tick can cross countdown boundaries and multiple *ordered* checkpoint gates; invalid jumps are denied based on speed, geometry and crossing order.
- Default lateral corridor is 14 m (event adjustable); 8 m maximum height deviation; speed plausibility max_speed_mps * delta + 5 m. Tolerances are game logic, not physical walls.
- AI wheelbase, steering sign, grip, braking/accel, safe corner speeds, and recovery thresholds must be calibrated against the genuine vehicle controller. Obstacle sensing is a supplied input, not a sensor implementation. The demo's kinematic car is not comparable to the final simcade vehicle.
- Event result standings are per-race only, not progression persistence. Consumer owns rewards, local save files, camera, controller input, free roam and UI.

## Validation before merge

~~~bash
godot --headless --path modules/racing --editor --quit
godot --headless --path modules/racing --script res://tests/run_tests.gd
godot --path modules/racing
~~~

Once standalone tests pass, import the scripts into the integrated root Godot project and test player/rivals with actual physics, world road data, lane assignments, slope/terrain collision, crashes, reset, gamepad and Windows build. None of those game-wide tests has been executed on this feature branch.

Ownership: shared docs/PROJECT_STATUS.md stays untouched under parallel-execution rules; integrator should update it after merging verified work.


## Production content readiness addendum

- Pass the **original** `content/races/events_v1.json` and `data/world/road_graph_v1.json` from the independently reviewed feature branches, not racing fixture JSON. Production tracks depend on directed turn connectors; World #3 and Race Content #10 are still separate unmerged sources.
- Register `player`, `rival_1`, `rival_2`, `rival_3` **before** `start_event()`. For an event with `start_grid`, an unknown/missing/duplicated racer slot is rejected instead of being silently mapped to route zero.
- At GRID, call `get_starting_grid()` and place **real rigid vehicles** from each returned `transform` (forward is Godot local -Z), reset their physics linear and angular velocities, and hold them stopped through GRID and COUNTDOWN. `synchronize_racer_spawn(id, position)` reconciles up to 2.5 m of spawn-height/placement difference; it cannot relocate a car onto another part of the course. While GRID/COUNTDOWN, `update_racer_state()` uses that bounded synchronization. Upon RACING, it resumes full anti-teleport, corridor, geometry and checkpoint checks.
- Each physics frame, update AI commands for rivals, move all physical cars, feed `update_racer_state(id, global_position, linear_velocity)` for every racer, and tick the engine **once**. There must not be a second `tick` on the first RACING frame: crossing the countdown boundary consumes only remaining real time.
- On `restart_event()`, re-place every physical car from `get_starting_grid()`; reinitialize AI tracking (and `configure_event` when changing courses). On `needs_reset(id)`, use the `reset_racer(id)` physical pose; on lap 1 that is the authored grid slot, on later laps route arclength zero. Reset physics velocities to zero in the host.
- After FINISHED, `get_results()` exposes the authoritative `event_id`, `elapsed_seconds`, state and sorted `standings()`; results are deliberately unavailable during an active race.
- Production `ai_speed_guidance` is advisory only; `RacerAI.configure_event()` combines it with the existing lane limits, curvature braking plan, obstacle response and target speed. The host still needs real vehicle-grip tuning and a collision/surface implementation.

No changes are made to the shared interface, world graph, production race content, player-car controller, scene, traffic or any other agent's files. Manual gameplay/viewport, Godot physics calibration and Windows build remain integration responsibilities.
