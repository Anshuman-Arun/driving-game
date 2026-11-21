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
