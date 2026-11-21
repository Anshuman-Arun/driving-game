extends SceneTree
## Run from repository root:
## godot --headless --path modules/traffic --script res://tests/run_tests.gd

const RoadGraph = preload("../src/road_graph.gd")
const TrafficSimulation = preload("../src/traffic_simulation.gd")
const VehicleAdapter = preload("../src/vehicle_adapter.gd")
const DT := 1.0 / 30.0
const FIXTURE := "res://fixtures/intersection_v1.json"

var passed := 0
var failed := 0
var graph_data: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if not (parsed is Dictionary):
		printerr("FATAL: fixture not parseable")
		quit(1)
		return
	graph_data = parsed
	_test_graph()
	_test_validation()
	_test_spawn_and_follow()
	_test_density_lifecycle()
	_test_signal_and_stop()
	_test_obstacle()
	_test_merge_and_dead_end()
	_test_vehicle_adapter()
	_test_population_and_determinism()
	print("TRAFFIC TESTS: %d pass, %d fail" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _check(ok: bool, description: String) -> void:
	if ok:
		passed += 1
		print("PASS ", description)
	else:
		failed += 1
		printerr("FAIL ", description)


func _simulation(seed_value: int = 14):
	var sim = TrafficSimulation.new()
	if not sim.load_road_graph(graph_data):
		printerr("invalid test fixture: ", sim.graph.errors)
	sim.reset(seed_value)
	sim.set_density(0)
	return sim


func _test_graph() -> void:
	var graph = RoadGraph.new()
	_check(graph.load_road_graph(graph_data), "v1 roads and 20 lanes load")
	_check(graph.lane_order.size() == 20, "20 lane IDs unique")
	_check(graph.lane_length("eb_in") > 75.0, "3D arc length calculated")
	var gap := 0.0
	for lid in graph.lane_order:
		for target in graph.lanes[lid]["next_lane_ids"]:
			var a: Vector3 = graph.get_pose(lid, graph.lane_length(lid))["position"]
			var b: Vector3 = graph.get_pose(target, 0.0)["position"]
			gap = maxf(gap, a.distance_to(b))
	_check(gap < 0.01, "all directed lane transitions meet without jumps")
	_check(not graph.lanes["eb_in"]["next_lane_ids"].has("wb_in"), "no wrong-way reverse connection")
	var at_start: Dictionary = graph.get_pose("eb_in", -1.0)
	var at_end: Dictionary = graph.get_pose("eb_in", 9999.0)
	_check(at_start["distance_m"] == 0.0 and at_end["distance_m"] == graph.lane_length("eb_in"), "sample arc length clamps to range")
	var near: Dictionary = graph.nearest_lane(Vector3(-40, 1, 2), 3.0)
	_check(near["lane_id"] == "eb_in", "nearest lane has proper directed ID")
	var route: Array[String] = graph.find_route("sb_in", "east_turn")
	_check(route.size() > 2 and route[0] == "sb_in" and route.back() == "east_turn" and route.has("feeder"), "directed Dijkstra finds north-south to east-west merge path")
	_check(graph.find_route("missing", "east_turn").is_empty(), "routing rejects undefined origin")
	var straight: float = graph.curve_speed_mps("eb_in", 25.0)
	var corner: float = graph.curve_speed_mps("east_turn", 17.0)
	_check(corner < straight, "curvature reduces the safe target speed")


func _test_validation() -> void:
	var g = RoadGraph.new()
	var bad: Dictionary = graph_data.duplicate(true)
	bad["schema_version"] = 2
	_check(not g.load_road_graph(bad), "reject unknown schema version")
	bad = graph_data.duplicate(true)
	bad["lanes"][0]["points"][1] = bad["lanes"][0]["points"][0]
	_check(not g.load_road_graph(bad), "reject duplicate consecutive lane points")
	bad = graph_data.duplicate(true)
	bad["lanes"][0]["next_lane_ids"] = ["missing"]
	_check(not g.load_road_graph(bad), "reject missing successor IDs")
	bad = graph_data.duplicate(true)
	bad["lanes"][0]["next_lane_ids"] = ["wb_in"]
	_check(not g.load_road_graph(bad), "reject discontinuous/wrong-way transitions")
	bad = graph_data.duplicate(true)
	bad["lanes"][0]["speed_limit_kph"] = -1
	_check(not g.load_road_graph(bad), "reject negative speed limits")


func _test_spawn_and_follow() -> void:
	var sim = _simulation()
	var lead: int = sim.spawn_agent("eb_in", 42.0, 1.5, 0.85)
	var rejected: int = sim.spawn_agent("eb_in", 39.0, 0.0)
	var follower: int = sim.spawn_agent("eb_in", 14.0, 9.0, 1.05)
	_check(lead > 0 and follower > 0 and rejected == -1, "spawn rejects nearby-car overlap")
	var gap_ok := true
	var speed_limited := true
	for _i in range(125):
		sim.step(DT, Vector3.ZERO)
		var a: Dictionary = sim.get_state(follower)
		var b: Dictionary = sim.get_state(lead)
		if a.is_empty() or b.is_empty():
			break
		if a["lane_id"] == b["lane_id"] and b["s"] > a["s"]:
			gap_ok = gap_ok and b["s"] - a["s"] >= sim.MIN_GAP_M - 0.05
		var limit: float = sim.graph.lanes[a["lane_id"]]["speed_limit_mps"]
		speed_limited = speed_limited and a["speed_mps"] < limit * 1.05 + 0.1
	_check(gap_ok, "follower maintains bumper gap while front vehicle accelerates")
	_check(speed_limited, "follower obeys lane speed limit")
	sim.set_player_state(Vector3(-55, 1, 2), 2.2)
	_check(sim.spawn_agent("eb_in", 35.0) == -1, "no traffic spawn on player")
	_check(sim.get_control_output(follower).has("throttle"), "vehicle adapter command has normalized drive inputs")


func _test_density_lifecycle() -> void:
	var sim = _simulation()
	var manual_id: int = sim.spawn_agent("eb_in", 15.0)
	_check(manual_id > 0, "explicitly managed NPC spawns with zero auto density")
	for _i in range(90):
		sim.step(DT, Vector3.ZERO)
	_check(not sim.get_state(manual_id).is_empty(), "automatic density maintenance preserves manual NPCs")
	var auto_id: int = sim.spawn_near(Vector3.ZERO, 100)
	_check(auto_id > 0, "automatic spawn produces density-managed NPC")
	for _i in range(60):
		sim.step(DT, Vector3.ZERO)
	_check(sim.get_state(auto_id).is_empty() and not sim.get_state(manual_id).is_empty(),
		"zero auto density removes only automatically spawned NPCs")


func _test_signal_and_stop() -> void:
	var sim = _simulation()
	_check(sim.configure_junctions([{"id": "red", "incoming_lane_ids": ["eb_in"],
		"mode": "signal", "period_s": 100.0, "green_s": 1.0, "phase_s": 5.0}]), "signal junction configuration accepted")
	var id: int = sim.spawn_agent("eb_in", 63.0, 8.0)
	for _i in range(150):
		sim.step(DT, Vector3.ZERO)
	var a: Dictionary = sim.get_state(id)
	_check(a["lane_id"] == "eb_in" and a["s"] <= sim.graph.lane_length("eb_in") - 2.45,
		"red light stops car before conflict lane")
	_check(a["speed_mps"] < 0.5, "red signal reaches full stop")
	var stop_sim = _simulation()
	_check(stop_sim.configure_junctions([{"id": "four_way_stop", "incoming_lane_ids": ["eb_in", "wb_in", "sb_in", "nb_in"],
		"mode": "stop", "stop_s": 0.8, "clearance_m": 21.0}]), "explicit all-way stop accepted")
	var stop_id: int = stop_sim.spawn_agent("eb_in", 73.0, 0.0)
	var seen_stop := false
	var seen_cross := false
	for _i in range(230):
		stop_sim.step(DT, Vector3.ZERO)
		a = stop_sim.get_state(stop_id)
		if a.is_empty():
			break
		if a["state"] == "WAIT_AT_JUNCTION" and a["speed_mps"] < 0.45:
			seen_stop = true
		if a["lane_id"] == "eb_cross":
			seen_cross = true
	_check(seen_stop and seen_cross, "stop sign holds, then grants junction entry")


func _test_obstacle() -> void:
	var sim = _simulation()
	var id: int = sim.spawn_agent("eb_in", 11.0, 7.5)
	var obstacle: Vector3 = sim.graph.get_pose("eb_in", 47.0)["position"]
	for _i in range(160):
		sim.step(DT, Vector3.ZERO, [{"position": obstacle, "radius_m": 2.0}])
	var a: Dictionary = sim.get_state(id)
	_check(a["lane_id"] == "eb_in" and a["s"] < 43.0, "obstacle response prevents crossing occupied road")
	_check(a["speed_mps"] < 0.5, "obstacle causes full braking")


func _test_merge_and_dead_end() -> void:
	var sim = _simulation()
	_check(sim.inbound_junction.has("feeder") and sim.inbound_junction.has("eb_out1"), "implicit merge control inferred from v1 successor")
	var entry_a: int = sim.spawn_agent("eb_out1", 9.0, 7.0)
	var entry_b: int = sim.spawn_agent("feeder", 10.0, 8.0)
	var transitioned_a := false
	var transitioned_b := false
	var overlap := false
	for _i in range(400):
		sim.step(DT, Vector3.ZERO)
		var a: Dictionary = sim.get_state(entry_a)
		var b: Dictionary = sim.get_state(entry_b)
		if a.is_empty() or b.is_empty():
			break
		if a["lane_id"] == "eb_out2":
			transitioned_a = true
		if b["lane_id"] == "eb_out2":
			transitioned_b = true
		if a["position"].distance_to(b["position"]) < 3.0:
			overlap = true
	_check(transitioned_a and transitioned_b, "both inbound routes traverse controlled merge")
	_check(not overlap, "merge prevents overlapping car positions")
	var dead_data: Dictionary = graph_data.duplicate(true)
	for l in dead_data["lanes"]:
		if l["id"] == "eb_cross":
			l["next_lane_ids"] = []
	var dead_sim = TrafficSimulation.new()
	_check(dead_sim.load_road_graph(dead_data), "dead-end lane is valid v1 data")
	dead_sim.reset(10)
	dead_sim.set_density(0)
	var dead_id: int = dead_sim.spawn_agent("eb_cross", 17.0, 2.0)
	var finite_positions := true
	for _i in range(400):
		dead_sim.step(DT, Vector3.ZERO)
		var state: Dictionary = dead_sim.get_state(dead_id)
		if state.is_empty():
			break
		finite_positions = finite_positions and state["s"] <= dead_sim.graph.lane_length("eb_cross")
	_check(finite_positions and dead_sim.get_state(dead_id).is_empty(), "dead-end vehicles stop then recycle without leaving the lane")


func _test_vehicle_adapter() -> void:
	var pose := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var right: Dictionary = VehicleAdapter.compute_drive_input(pose, 3.0, Vector3(8, 0, -10), 12.0)
	var left: Dictionary = VehicleAdapter.compute_drive_input(pose, 3.0, Vector3(-8, 0, -10), 12.0)
	_check(right["steer"] > 0.1 and left["steer"] < -0.1, "real vehicle adapter steers toward lookahead left/right")
	_check(right["throttle"] > 0.0 and right["brake"] == 0.0, "vehicle adapter accelerates below target")
	var slow: Dictionary = VehicleAdapter.compute_drive_input(pose, 20.0, Vector3(0, 0, -10), 6.0)
	_check(slow["brake"] > 0.0 and slow["throttle"] == 0.0, "vehicle adapter brakes above target")


func _test_population_and_determinism() -> void:
	var a = _simulation(20261121)
	var b = _simulation(20261121)
	for sim in [a, b]:
		_check(sim.configure_junctions([{"id": "center", "incoming_lane_ids": ["eb_in", "wb_in", "sb_in", "nb_in"],
			"mode": "stop", "stop_s": 0.7, "clearance_m": 21.0},
			{"id": "feeder_crossing", "incoming_lane_ids": ["sb_out1", "nb_in_far"],
			"mode": "yield", "clearance_m": 13.0}]), "intersection control installed")
		sim.set_density(16)
	var max_cars := 0
	var transitions := 0
	var collisions := 0
	var last_lanes: Dictionary = {}
	var moving_car_steps := 0
	var equal := true
	for i in range(2700): # 90 seconds / 81,000 internal agent updates
		a.step(DT, Vector3.ZERO)
		b.step(DT, Vector3.ZERO)
		var cars_a: Array = a.get_states()
		var cars_b: Array = b.get_states()
		max_cars = maxi(max_cars, cars_a.size())
		if cars_a.size() != cars_b.size():
			equal = false
			break
		for j in range(cars_a.size()):
			var s: Dictionary = cars_a[j]
			var mirror: Dictionary = cars_b[j]
			if s["id"] != mirror["id"] or s["lane_id"] != mirror["lane_id"] or s["position"].distance_to(mirror["position"]) > 0.000001:
				equal = false
			if not last_lanes.has(s["id"]):
				last_lanes[s["id"]] = s["lane_id"]
			elif last_lanes[s["id"]] != s["lane_id"]:
				transitions += 1
				last_lanes[s["id"]] = s["lane_id"]
			if s["speed_mps"] > 0.5:
				moving_car_steps += 1
			for k in range(j + 1, cars_a.size()):
				if s["position"].distance_to(cars_a[k]["position"]) < 3.6:
					collisions += 1
	_check(max_cars >= 10 and max_cars <= 20, "90-second demo stress test populates 10-20 cars")
	_check(transitions > 15, "90-second multi-car simulation makes repeated lane transitions")
	_check(moving_car_steps > 6000, "90-second scenario has sustained moving traffic")
	_check(collisions == 0, "no center-point overlaps in 90-second test")
	_check(equal, "identical seeds and fixed ticks produce identical snapshots")
	for i in range(100):
		a.step(DT, Vector3(900, 1, 900))
	_check(a.get_states().is_empty(), "distant traffic is despawned")
	a.set_density(10)
	for i in range(90):
		a.step(DT, Vector3.ZERO)
	_check(a.get_stats()["active"] == 10 and a.get_stats()["reused"] >= 10, "recycled pool serves subsequent spawns")
