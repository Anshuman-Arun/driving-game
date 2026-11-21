# Aster Valley — civilian traffic module

An isolated, seed-reproducible Godot 4.7.2 GDScript traffic simulation. All code,
fixture data, tests, and the separate runnable Godot project are in
`modules/traffic/`; **the root game project is not changed**.

## Runtime API

In the eventual *root* Godot project:

```gdscript
const Traffic = preload("res://modules/traffic/src/traffic_simulation.gd")
const Adapter = preload("res://modules/traffic/src/vehicle_adapter.gd")
var traffic = Traffic.new()

func configure_traffic(road_graph_json: Dictionary) -> void:
    assert(traffic.load_road_graph(road_graph_json))
    traffic.configure_junctions([
        {"id": "town_crossing", "incoming_lane_ids": ["approach_a", "approach_b"],
         "mode": "stop", "stop_s": 0.8, "clearance_m": 20.0}
    ])
    traffic.reset(20261121)
    traffic.set_density(16) # 0..20

func _physics_process(delta: float) -> void:
    traffic.set_player_state(player.global_position, 2.0)
    traffic.step(delta, camera.global_position, [])
    for state in traffic.get_states():
        update_npc_visual(state["id"], state["position"], state["tangent"])
```

`load_road_graph(Dictionary) -> bool` validates exactly the shared
`road_graph_v1.json` fields: schema version, units, coordinates, bounds, road and
lane memberships, points, speed/width, directed links, seam proximity and
heading continuity. `graph.errors` contains reasons for rejection. The module
never writes the world agent's JSON.

`graph.get_pose(lane_id, distance_m)` returns interpolated `position` and
`tangent` on a 3D lane. `graph.curve_speed_mps()` limits corner speed;
`graph.find_route(start, destination)` uses bounded Dijkstra over **directed**
links, and returns an empty array for unreachable destinations.

`spawn_agent(lane_id, s, initial_speed_mps, speed_factor) -> int` returns an ID
or `-1` when unsafe/invalid. `route_agent_to(id, destination)` and
`assign_route(id, lane_ids)` give a car a defined directed route, after which it
stops and recycles at its destination. Normal civilian cars select next lanes
from seeded random routing. `despawn_agent()`, `spawn_near()`, `get_state()`,
`get_states()`, `get_stats()`, and `get_control_output()` expose progression and
recycling. `reset(seed)` restarts the reproducible simulation and RNG.

`step(delta, viewer_position, obstacles)` internally accumulates fixed 30 Hz
steps, independent of graphics frame rate. Cars use lane-tangent positions,
longitudinal acceleration/braking, speed-limit variation, curvature preview,
leader car gaps extending into the next lane, and point/circle obstacles. The
viewer is used only for density, spawn, and despawn; the **player** is a separate
physical obstacle via `set_player_state(position, radius_m, enabled)`.

### Intersection and traffic-light authoring

Junction controls are **module configuration**, not new fields inserted into
the shared road-graph contract:

```gdscript
traffic.configure_junctions([
    {"id": "downtown", "incoming_lane_ids": ["a_in", "b_in"],
     "mode": "signal", "period_s": 20.0, "green_s": 9.0, "phase_s": 0.0,
     "clearance_m": 20.0},
    {"id": "side_street", "incoming_lane_ids": ["c_in", "d_in"],
     "mode": "stop", "stop_s": 0.9, "clearance_m": 13.0}
])
```

Modes: `yield` (exclusive reservation before entering), `stop` (full stop +
dwell), `signal` (configured cyclic green window). Both stop and signal also
respect intersection reservations. `incoming_lane_ids` should end at a stop
line, with a successor connector that traverses the actual conflict zone.
`clearance_m` must carry the reservation past the last conflict point. A
junction defined too far from the physical crossing cannot guarantee safety.
If two incoming lanes merge into one successor, an implicit `yield` reservation
is inferred automatically, avoiding any v1 schema extension. Traffic may not
spawn inside a controlled connector until past its clearance zone.

### Lightweight vs physical NPCs

The normal traffic car is **kinematic state data**, not a `VehicleBody3D`; a
visible car can be a pooled `MeshInstance3D` driven by position/tangent. At
close range, the integrator can instantiate a collider/physical controller and
feed it `VehicleAdapter.compute_drive_input(transform, forward_speed,
lookahead_position, target_speed)`; this produces `steer`, `throttle`, `brake`,
`handbrake`. `get_control_output(id)` provides lookahead and desired speed.
Never drive the same body using both the kinematic position and rigid-body
physics at once. World collision geometry, physics contact with the hero car,
vehicle spawn suppression during a race, and near/far handoff are integrator
responsibilities, not claimed by this isolated module.

## Demo and tests

The **nested** `modules/traffic/project.godot` is a standalone project used
only to run its fixtures and demo. From the repository root:

```bash
godot --headless --path modules/traffic --editor --quit
godot --headless --path modules/traffic --script res://tests/run_tests.gd
godot --path modules/traffic
```

The demo shows a miniature 20-lane two-way network with an all-way stop,
feeder crossing, automatic merge yielding and **14** box-mesh civilian cars.
Keys: `R` reseed/restart, `T` toggle 6/14 cars, `Space` pause. No third-party
assets, engine addons or root project scene changes are required.

For a Python-only environment, the **fixture and numerical reference**
checks can run independently, but are not a substitute for testing the GDScript:

```bash
python -m unittest discover -s modules/traffic/tests -p 'fixture_checks.py' -v
python modules/traffic/tests/reference_flow_sim.py
```

See `TEST_REPORT.md` for exact executed results and outstanding Godot checks.
