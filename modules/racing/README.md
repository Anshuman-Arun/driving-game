# Aster Valley / Track C — standalone racing module

Godot 4.7.2 GDScript race engine and AI planner, entirely inside modules/racing/. No global autoload or dependency on the pending Core, World or Traffic branches.

## Commands (from repository root)

~~~bash
godot --headless --path modules/racing --editor --quit
godot --headless --path modules/racing --script res://tests/run_tests.gd
godot --path modules/racing
~~~

The standalone project file is modules/racing/project.godot. The last command opens demo/racing_demo.tscn, showing real fixture road ribbons and four autonomous simplified kinematic cars (one labeled player and three rivals). Tab changes the town/ridge fixture, Space pauses, R restarts, Q quits to free roam. Primitive meshes only: no external art dependencies. The demo car is **not** production vehicle physics.

## Public API

~~~gdscript
const RaceEngine = preload("res://modules/racing/race_engine.gd")
const RacerAI = preload("res://modules/racing/racer_ai.gd")
const Adapter = preload("res://modules/racing/vehicle_command_adapter.gd")
const EventCatalog = preload("res://modules/racing/event_catalog.gd")

var race = RaceEngine.new()
var ai = RacerAI.new()
assert(race.load_road_graph(graph_dict))
assert(race.register_racer("player", true))
assert(race.register_racer("rival_1", false))
assert(race.start_event(event_dict))
assert(ai.configure(graph_dict, event_dict["lane_route"], event_dict["kind"] == "circuit"))

# On each physics frame: compute and apply rival input, update all positions,
# then call race.tick(delta) EXACTLY ONCE.
var controls: Dictionary = ai.compute_controls(
    rival.global_position, -rival.global_transform.basis.z,
    rival_speed_mps, delta, [{"distance_m": 18.0, "lateral_m": 0.2}])
Adapter.apply(rival, controls)
race.update_racer_state("player", player_position, player_velocity)
race.update_racer_state("rival_1", rival_position, rival_velocity)
race.tick(delta)

if race.needs_reset("rival_1"):
    var pose: Dictionary = race.reset_racer("rival_1")
    # Host must call its own vehicle reset function with pose and forward.
~~~

Other methods: pause(), resume(), restart_event(), quit_event(), return_to_free_roam(), show_results(), get_racer(id), standings(), report_collision(id, impact_mps). The event catalog supports parse_text(json), load_file(path), get_event(id). Invalid calls return false with last_error where appropriate.

### State transition diagram

~~~text
IDLE -- start_event --> GRID -- timer --> COUNTDOWN -- timer --> RACING
                                                             |
                                     all finished / grace / timeout
                                                             v
                                                        FINISHED
                                                             | show_results
                                                             v
                                                         RESULTS -- return_to_free_roam --> FREE_ROAM

GRID / COUNTDOWN / RACING / FINISHED / RESULTS -- quit_event --> ABORTED -- return_to_free_roam --> FREE_ROAM
GRID / COUNTDOWN / RACING / FINISHED / RESULTS / ABORTED -- restart_event --> GRID
FREE_ROAM -- start_event --> GRID
~~~

Signals: state_changed(old,new), checkpoint_passed(racer_id,checkpoint_id,lap), lap_completed(racer_id,completed_lap), racer_finished(racer_id,finish_time), invalid_progress(racer_id,reason).

## Data & progress rules

- Both shared graph and event JSON use schema_version 1. Road lane centerlines are directed; next_lane_ids must connect the event route with compatible headings and close endpoints.
- Event definition requires id, kind (sprint/circuit), lane_route, start_position [x,y,z], nonoverlapping ordered checkpoints (id, center, radius_m), and laps (exactly one for sprint). Optional settings include grid_seconds, countdown_seconds, max_speed_mps, corridor_m, collision_reset_speed_mps, finish_grace_seconds and max_race_seconds.
- Positions use Godot world +Y-up **meters**, velocities and speed inputs use **m/s**, not km/h. The engine handles ordering, arc projection, timekeeping and rankings, not movement, HUD, scene changes or persistence.
- An observed movement exceeding max_speed_mps × delta + 5 m, a route corridor/vertical violation, an out-of-order or missed gate, an out-of-bounds point or a severe reported impact requests reset. Recovery returns a pose at the start of the **current lap**. Host must teleport its physical vehicle and stop/reset its velocity. Wrong-way movement never earns progress.
- The AI returns normalized steer [-1,1], throttle and brake [0,1], handbrake=false, target_speed_mps, lookahead_m, route_s, needs_reset. Obstacle inputs are dictionaries with positive forward distance_m and lateral_m offset, in meters. Planning considers local curvature, lateral acceleration, stopping distance, road speed limits and projected pursuit targets.

## Isolation and integration

fixtures/road_graph_v1.json and fixtures/events_v1.json are **not** the World Agent's canonical map. They model an approximately 845 m Alder town loop (3 laps) and 685 m North Ridge sprint with four gates each. They intentionally do not claim the full design-target route lengths or world integration.

Root project integration must consume actual data/world/road_graph_v1.json from the World Agent, author real event lane IDs and connect VehicleAdapter's set_drive_input to the Core Agent's genuine vehicle controller. The standalone primitive demo does not test real collision, gamepad, Windows export, traffic or performance. See INTEGRATION_NOTES.md and TEST_REPORT.md.


## Production race-grid and results interface (feat/production-racing-readiness)

Production `content/races/events_v1.json` contains an optional `start_grid` array (one slot **per registered racer**). Each slot has `id`, `position: [x,y,z]`, `forward: [x,y,z]` and `route_s_m`. `RaceEngine.start_event()` validates unique registered IDs, unit travel headings, route-consistent pose/progress and a start before the first checkpoint. All four production events author `player=7 m`, `rival_1=17 m`, `rival_2=27 m` and `rival_3=37 m`; all racers are seeded at these **independent** physical positions, not at route zero. A missing `start_grid` preserves legacy zero-meter spawns for the existing 156-check suite/demo.

**Host integration contract:**

~~~gdscript
# Load external world graph and production event catalog first. Register the
# exact four IDs present in event.start_grid; start_event enters GRID.
assert(race.start_event(catalog.get_event("alder_street_circuit")))
for slot in race.get_starting_grid(): # authored order
    # slot: id, position (Vector3), forward (Vector3), route_s_m, transform (Transform3D)
    # Vehicle integration owns physically placing and stopping the car.
    var vehicle: Node3D = cars_by_id[slot["id"]]
    vehicle.global_transform = slot["transform"]
    # Host's actual physics-controller velocity must also be reset to ZERO.
    assert(race.synchronize_racer_spawn(slot["id"], vehicle.global_position))

# One host physics frame (state checked BEFORE tick):
if race.state == RaceEngine.State.RACING:
    # Run the physical vehicles and AI first, then feed all their observations.
    race.update_racer_state("player", player.global_position, player.linear_velocity)
    # Repeat for all rivals with actual world positions and velocities.
else:
    # Hold/brake all vehicles through GRID and COUNTDOWN.
    # Near-spawn observations may be synchronized here if needed.
    pass
race.tick(delta) # Exactly ONCE per physics frame, advancing all state timers.
# When a crash or invalid movement requires recovery:
if race.needs_reset("rival_1"):
    var recovery: Dictionary = race.reset_racer("rival_1")
    # Physically apply recovery.position / recovery.forward and clear velocity.
    # Reset the corresponding RacerAI tracking after teleporting the car.

# After FINISHED or RESULTS, obtain authoritative sorted per-race results:
var results: Dictionary = race.get_results() # {} before finish
# {event_id, elapsed_seconds, state, standings}
~~~

Use a **single** host physics loop rather than copying the two illustrative `tick` calls above: run state-dependent physics/AI, feed one observation per vehicle, then call `race.tick(delta)` exactly once. GRID/COUNTDOWN physical cars should remain held at their authored start positions (up to 2.5 m sync tolerance, not arbitrary relocation). When the engine enters RACING, live progress and teleport/shortcut checks are enforced at their previous thresholds. On `restart_event()`, the host must physically respawn every car from `get_starting_grid()` and clear velocities/planner tracking. First-lap resets return a racer's authored grid slot; later-lap resets return to route arclength zero for that lap.

Use `RacerAI.configure_event(graph, event_definition)` to retain the existing geometry planner and optionally apply `ai_speed_guidance` as an **additional upper speed cap**. It never raises the speed above curvature-based, lane speed-limit or obstacle-based restrictions. `configure(graph, lane_route, closed)` remains compatible with legacy callers.

## Reproducible tests with authoritative external files

From a local checkout with access to both unmerged source branches, stage the external dependencies into a temporary directory **outside the repository**; do not commit duplicate datasets:

~~~bash
git fetch origin feat/worldgen feat/race-content
mkdir -p /tmp/aster-racing-inputs
git show origin/feat/worldgen:data/world/road_graph_v1.json > /tmp/aster-racing-inputs/road_graph_v1.json
git show origin/feat/race-content:content/races/events_v1.json > /tmp/aster-racing-inputs/events_v1.json

godot --headless --path modules/racing --editor --quit
godot --headless --path modules/racing --script res://tests/run_tests.gd
godot --headless --path modules/racing --script res://tests/run_grid_tests.gd
godot --headless --path modules/racing --script res://tests/run_production_tests.gd -- --graph=/tmp/aster-racing-inputs/road_graph_v1.json --events=/tmp/aster-racing-inputs/events_v1.json
~~~

Production test inputs must be the **real** graph and event catalog. The production harness refuses to run when either is missing and asserts route sequence, distance, gate count/order, laps, authored grid transforms, countdown, four-car simulated progress through all gates/laps, finish/result ordering, restart, first-lap recovery, teleport protection and advisory AI speed caps. This is a headless *kinematic route-following* regression, not evidence that real production vehicles, terrain and collision meshes are drivable. See TEST_REPORT.md for what was actually executed.
