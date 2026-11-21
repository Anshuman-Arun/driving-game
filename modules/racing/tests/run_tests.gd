extends SceneTree
## Run with: godot --headless --path modules/racing --script res://tests/run_tests.gd
const RaceEngine = preload("../race_engine.gd")
const RaceRoute = preload("../race_route.gd")
const RacerAI = preload("../racer_ai.gd")
const Adapter = preload("../vehicle_command_adapter.gd")
const EventCatalog = preload("../event_catalog.gd")
const KinematicCar = preload("../demo/kinematic_car.gd")

var graph: Dictionary = {}
var catalog = EventCatalog.new()
var checks: int = 0
var failures: Array[String] = []

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/road_graph_v1.json"))
	if not (parsed is Dictionary):
		printerr("FAIL: missing road graph fixture")
		quit(1)
		return
	graph = parsed
	_check(catalog.load_file("res://fixtures/events_v1.json"), "event catalog loads")
	_test_validation()
	_test_lifecycle_and_clock()
	_test_standings_timeout_and_quit()
	_test_sprint_results()
	_test_circuit_laps()
	_test_wrong_way_and_teleport()
	_test_shortcut_and_missing_checkpoint()
	_test_out_of_order_checkpoint()
	_test_reset_replay()
	_test_coarse_ticks_collision_and_altitude()
	_test_ai_controls()
	_test_ai_closed_course()
	if failures.is_empty():
		print("RACING TESTS PASSED: %d checks" % checks)
		quit(0)
	else:
		printerr("RACING TESTS FAILED: %d / %d" % [failures.size(), checks])
		quit(1)

func _engine(event_id: String, ids: Array = ["a", "b"], zero_countdown: bool = true):
	var e = RaceEngine.new()
	_check(e.load_road_graph(graph), "load graph for " + event_id)
	for id in ids:
		_check(e.register_racer(id, id == "a"), "register " + id)
	var def: Dictionary = catalog.get_event(event_id)
	if zero_countdown:
		def["grid_seconds"] = 0
		def["countdown_seconds"] = 0
	def["finish_grace_seconds"] = 2000
	_check(e.start_event(def), "start " + event_id + ": " + e.last_error)
	if zero_countdown:
		e.tick(0.001)
		_check(e.state == RaceEngine.State.RACING, "zero-length countdown enters racing")
	return e

func _drive(e, id: String, start_s: float, end_s: float, step_m: float = 2.5, dt: float = 0.10) -> void:
	var s := start_s
	var limit := 0
	while s < end_s - 0.001 and limit < 20000 and e.state == RaceEngine.State.RACING:
		s = minf(s + step_m, end_s)
		var p: Vector3 = e.route.sample(s)
		e.update_racer_state(id, p, Vector3.ZERO)
		e.tick(dt)
		limit += 1
	_check(limit < 20000, "drive helper bounded")

func _test_validation() -> void:
	_check(RaceRoute.validate_road_graph(graph).is_empty(), "road fixture obeys graph v1")
	var bad: Dictionary = graph.duplicate(true)
	bad["lanes"][0]["points"][1] = bad["lanes"][0]["points"][0].duplicate()
	_check(not RaceRoute.validate_road_graph(bad).is_empty(), "reject consecutive duplicate road points")
	bad = graph.duplicate(true)
	bad["lanes"][0]["next_lane_ids"] = ["missing_lane"]
	_check(not RaceRoute.validate_road_graph(bad).is_empty(), "reject unknown lane reference")
	bad = graph.duplicate(true)
	bad["lanes"][1]["id"] = bad["lanes"][0]["id"]
	_check(not RaceRoute.validate_road_graph(bad).is_empty(), "reject duplicate lane ID")
	bad = graph.duplicate(true)
	bad["lanes"][0]["width_m"] = -1
	_check(not RaceRoute.validate_road_graph(bad).is_empty(), "reject negative width")
	var e = RaceEngine.new()
	_check(e.load_road_graph(graph), "valid graph loads")
	_check(e.register_racer("a"), "register before event")
	var def: Dictionary = catalog.get_event("alder_street_circuit")
	def["lane_route"] = ["missing_lane"]
	_check(not e.start_event(def), "reject missing route lane")
	def = catalog.get_event("alder_street_circuit")
	def["checkpoints"].reverse()
	_check(not e.start_event(def), "reject wrong checkpoint order")
	def = catalog.get_event("alder_street_circuit")
	def["checkpoints"][1]["center"] = def["checkpoints"][0]["center"].duplicate()
	_check(not e.start_event(def), "reject overlapping checkpoint gates")
	def = catalog.get_event("north_ridge_climb")
	def["laps"] = 2
	_check(not e.start_event(def), "reject two-lap sprint")
	var other = EventCatalog.new()
	_check(not other.parse_text("garbage"), "reject invalid catalog JSON")
	_check(not other.parse_text('{"schema_version":1,"events":[{"id":"a","kind":"sprint","lane_route":[],"checkpoints":[]},{"id":"a","kind":"sprint","lane_route":[],"checkpoints":[]}]}'), "reject repeated event ID")

func _test_lifecycle_and_clock() -> void:
	var e = _engine("north_ridge_climb", ["a"], false)
	_check(e.state == RaceEngine.State.GRID, "starts on GRID")
	e.tick(0.5)
	_check(is_equal_approx(e.grid_remaining, 0.5), "grid timer advances")
	_check(e.pause(), "pause available")
	e.tick(10.0)
	_check(is_equal_approx(e.grid_remaining, 0.5), "pause freezes grid")
	e.resume()
	e.tick(4.5)
	_check(e.state == RaceEngine.State.RACING, "large delta crosses GRID and COUNTDOWN")
	_check(is_equal_approx(e.elapsed_seconds, 0.5), "only remaining racing delta counts")
	e.tick(2.0)
	_check(is_equal_approx(e.elapsed_seconds, 2.5), "race timer advances")
	_check(e.pause(), "pause racing")
	e.tick(10.0)
	_check(is_equal_approx(e.elapsed_seconds, 2.5), "pause freezes racing")
	e.resume()
	_check(e.restart_event(), "restart from racing")
	_check(e.state == RaceEngine.State.GRID and e.elapsed_seconds == 0.0, "restart resets grid and clock")
	_check(e.quit_event() and e.state == RaceEngine.State.ABORTED, "quit transitions to ABORTED")
	_check(e.return_to_free_roam(), "abort returns to FREE_ROAM")
	_check(e.start_event(catalog.get_event("north_ridge_climb")), "start new race after abort")
	e.quit_event()
	e.return_to_free_roam()

func _test_standings_timeout_and_quit() -> void:
	var e = _engine("north_ridge_climb")
	var ranks: Array[Dictionary] = e.standings()
	_check(ranks[0]["id"] == "a" and ranks[1]["id"] == "b", "standings break exact progress tie by racer ID")
	_drive(e, "b", 0.0, 60.0)
	ranks = e.standings()
	_check(ranks[0]["id"] == "b" and ranks[0]["position"] == 1, "leader changes on validated progress")
	_check(e.quit_event(), "active event may be aborted")
	_check(e.return_to_free_roam(), "abort returns cleanly to free roam")
	var timeout = RaceEngine.new()
	_check(timeout.load_road_graph(graph), "timeout graph loaded")
	_check(timeout.register_racer("a"), "timeout racer registered")
	var definition: Dictionary = catalog.get_event("north_ridge_climb")
	definition["grid_seconds"] = 0
	definition["countdown_seconds"] = 0
	definition["max_race_seconds"] = 0.05
	_check(timeout.start_event(definition), "timeout event starts")
	timeout.tick(0.2)
	_check(timeout.state == RaceEngine.State.FINISHED, "race timeout transitions to FINISHED")
	_check(not timeout.get_racer("a")["finished"], "timeout does not invent a finisher")
	_check(timeout.show_results() and timeout.return_to_free_roam(), "timeout results return cleanly")

func _test_sprint_results() -> void:
	var e = _engine("north_ridge_climb")
	_drive(e, "a", 0.0, e.route.length_m)
	_check(e.get_racer("a")["finished"], "sprint racer finishes with ordered gates")
	_check(e.get_racer("a")["invalid_laps"] == 0, "clean sprint has no invalid attempts")
	_check(e.state == RaceEngine.State.RACING, "finish waits for other racers")
	var standings: Array[Dictionary] = e.standings()
	_check(standings[0]["id"] == "a", "finished racer ranks ahead")
	_drive(e, "b", 0.0, e.route.length_m)
	_check(e.get_racer("b")["finished"], "second racer finishes")
	_check(e.state == RaceEngine.State.FINISHED, "all finish transitions to FINISHED")
	standings = e.standings()
	_check(standings[0]["id"] == "a" and standings[1]["id"] == "b", "finish order uses race time")
	_check(e.show_results(), "FINISHED transitions to RESULTS")
	_check(e.return_to_free_roam(), "RESULTS transitions to FREE_ROAM")

func _test_circuit_laps() -> void:
	var e = _engine("alder_street_circuit", ["a"])
	var lap_m: float = e.route.length_m
	_drive(e, "a", 0.0, lap_m + 5.0)
	_check(e.get_racer("a")["lap"] == 2, "circuit advances exactly one lap")
	_check(e.get_racer("a")["checkpoint_index"] == 0, "checkpoint order resets each lap")
	_drive(e, "a", lap_m + 5.0, lap_m * 2.0 + 5.0)
	_check(e.get_racer("a")["lap"] == 3, "second lap increments")
	_drive(e, "a", lap_m * 2.0 + 5.0, lap_m * 3.0)
	_check(e.get_racer("a")["finished"], "three-lap circuit completes")
	_check(e.get_racer("a")["invalid_laps"] == 0, "circuit accepts legal path")
	_check(e.state == RaceEngine.State.FINISHED, "single racer completion finishes event")

func _test_wrong_way_and_teleport() -> void:
	var e = _engine("alder_street_circuit", ["a"])
	_drive(e, "a", 0.0, 60.0)
	var prior: float = e.get_racer("a")["progress_m"]
	e.update_racer_state("a", e.route.sample(55.0), Vector3.ZERO)
	e.tick(0.2)
	_check(e.get_racer("a")["wrong_way"], "reverse movement marked wrong-way")
	_check(is_equal_approx(e.get_racer("a")["progress_m"], prior), "reversing cannot gain progress")
	e.update_racer_state("a", e.route.sample(280.0), Vector3.ZERO)
	e.tick(0.016)
	_check(e.needs_reset("a"), "sudden teleport requires recovery")
	_check(e.get_racer("a")["last_invalid_reason"] == "teleport_or_unphysical_speed", "teleport is classified")
	var pose: Dictionary = e.reset_racer("a")
	_check(pose.has("position") and not e.needs_reset("a"), "reset returns a spawn pose")
	_check(e.get_racer("a")["invalid_laps"] == 1, "invalid attempt counted")
	var rankings: Array[Dictionary] = e.standings()
	_check(rankings[0]["position"] == 1, "standings assign positions")

func _test_shortcut_and_missing_checkpoint() -> void:
	var e = _engine("alder_street_circuit", ["a"])
	e.update_racer_state("a", Vector3(0.0, 20.0, 0.0), Vector3.ZERO)
	e.tick(10.0)
	_check(e.needs_reset("a"), "cut through circuit interior rejected")
	_check(e.get_racer("a")["last_invalid_reason"] == "shortcut_or_off_route", "cut reason classified")
	e = _engine("alder_street_circuit", ["a"])
	var cp: Dictionary = e.checkpoints[0]
	var s: float = cp["s"] - 25.0
	_drive(e, "a", 0.0, s)
	while s < float(cp["s"]) + 18.0 and not e.needs_reset("a"):
		s += 2.0
		var tangent: Vector2 = e.route.tangent(s)
		var offset := Vector3(-tangent.y, 0.0, tangent.x) * 13.0
		e.update_racer_state("a", e.route.sample(s) + offset, Vector3.ZERO)
		e.tick(0.1)
	_check(e.needs_reset("a"), "crossing checkpoint arc outside volume invalidates lap")
	_check(e.get_racer("a")["last_invalid_reason"] == "missed_checkpoint", "missing gate classified")

func _test_out_of_order_checkpoint() -> void:
	var e = RaceEngine.new()
	e.load_road_graph(graph)
	e.register_racer("a")
	var definition: Dictionary = catalog.get_event("alder_street_circuit")
	definition["grid_seconds"] = 0
	definition["countdown_seconds"] = 0
	definition["max_speed_mps"] = 999.0
	definition["corridor_m"] = 1000.0
	_check(e.start_event(definition), "start permissive isolated ordering test")
	e.tick(0.001)
	e.update_racer_state("a", Vector3(165, 20, 0), Vector3.ZERO)
	e.tick(1.0)
	_check(e.needs_reset("a"), "out of order gate rejected even when teleport cap disabled")
	_check(e.get_racer("a")["last_invalid_reason"] == "out_of_order_checkpoint", "out of order classified")

func _test_reset_replay() -> void:
	var e = _engine("alder_street_circuit", ["a"])
	var lap_m: float = e.route.length_m
	_drive(e, "a", 0.0, lap_m + 5.0)
	_check(e.get_racer("a")["lap"] == 2, "reset fixture reaches lap two")
	e.update_racer_state("a", Vector3(500, 20, 500), Vector3.ZERO)
	e.tick(0.01)
	_check(e.needs_reset("a"), "lap two cheat detected")
	var pose: Dictionary = e.reset_racer("a")
	_check(pose["lap"] == 2 and e.get_racer("a")["checkpoint_index"] == 0, "reset keeps completed laps only")
	_drive(e, "a", lap_m, lap_m * 2.0)
	_check(e.get_racer("a")["lap"] == 3, "reset can replay invalidated lap")
	_check(e.get_racer("a")["invalid_laps"] == 1, "invalid attempt survives reset")

func _test_coarse_ticks_collision_and_altitude() -> void:
	var g: Dictionary = {
		"schema_version": 1, "units": "meters", "coordinate_system": "godot_y_up",
		"bounds": {"min_x": -1000, "max_x": 1000, "min_z": -1000, "max_z": 1000},
		"roads": [{"id": "straight_road", "name": "Straight", "region": "test", "lane_ids": ["straight"]}],
		"lanes": [{"id": "straight", "road_id": "straight_road", "points": [[0, 0, 0], [100, 0, 0]],
			"width_m": 3.5, "speed_limit_kph": 90, "surface": "asphalt", "next_lane_ids": []}]
	}
	var e = RaceEngine.new()
	_check(e.load_road_graph(g), "straight road graph validates")
	_check(e.register_racer("a"), "straight test racer registers")
	var def: Dictionary = {
		"id": "coarse_tick_sprint", "kind": "sprint", "lane_route": ["straight"],
		"start_position": [0, 0, 0], "laps": 1, "grid_seconds": 0, "countdown_seconds": 0,
		"checkpoints": [{"id": "one", "center": [20, 0, 0], "radius_m": 5},
			{"id": "two", "center": [40, 0, 0], "radius_m": 5}]
	}
	_check(e.start_event(def), "coarse tick event loads")
	e.tick(0.001)
	e.update_racer_state("a", Vector3(50, 0, 0), Vector3(50, 0, 0))
	e.tick(1.0)
	_check(e.get_racer("a")["checkpoint_index"] == 2, "large delta can sweep two gates in correct order")
	_check(not e.needs_reset("a"), "coarse swept check is not a false positive")
	e.update_racer_state("a", Vector3(100, 0, 0), Vector3(50, 0, 0))
	e.tick(1.0)
	_check(e.get_racer("a")["finished"], "coarse tick completes valid sprint")
	e = _engine("north_ridge_climb", ["a"])
	_check(e.report_collision("a", 4.0) and not e.needs_reset("a"), "low-speed contact is tolerated")
	_check(e.report_collision("a", 18.0) and e.needs_reset("a"), "severe collision requires recovery")
	_check(e.get_racer("a")["last_invalid_reason"] == "collision_requires_reset", "severe collision classified")
	_check(e.reset_racer("a").has("position"), "collision reset returns valid pose")
	var airborne: Vector3 = e.route.sample(2.0) + Vector3(0, 10, 0)
	e.update_racer_state("a", airborne, Vector3.ZERO)
	e.tick(0.1)
	_check(e.needs_reset("a"), "vertical route shortcut rejected")
	e.reset_racer("a")
	e.update_racer_state("a", Vector3(2000, 20, 0), Vector3.ZERO)
	e.tick(0.1)
	_check(e.needs_reset("a") and e.get_racer("a")["last_invalid_reason"] == "out_of_bounds", "out-of-world reset detected")

func _test_ai_controls() -> void:
	var ai = RacerAI.new()
	var e = _engine("alder_street_circuit", ["a"])
	_check(ai.configure(graph, e.event["lane_route"], true), "AI loads same contract route")
	var s := 75.0
	var p: Vector3 = e.route.sample(s)
	var t: Vector2 = e.route.tangent(s)
	var forward := Vector3(t.x, 0, t.y)
	var normal := Vector3(-t.y, 0, t.x)
	var left: Dictionary = ai.compute_controls(p + normal * 4.0, forward, 10.0, 0.016)
	var right: Dictionary = ai.compute_controls(p - normal * 4.0, forward, 10.0, 0.016)
	_check(left["steer"] * right["steer"] < 0.0, "steering corrects opposite sides of driving line")
	_check(left["steer"] > 0.0 and right["steer"] < 0.0, "steering yaw sign turns toward line from both sides")
	var yaw_car = KinematicCar.new()
	yaw_car.teleport_to(p, forward)
	var car_heading: Vector3 = -yaw_car.global_transform.basis.z
	_check(car_heading.dot(forward.normalized()) > 0.999, "demo car faces the supplied road tangent")
	yaw_car.speed_mps = 8.0
	yaw_car.set_drive_input(0.5, 0.2, 0.0, false)
	yaw_car.advance(0.1)
	var turned_heading: Vector3 = -yaw_car.global_transform.basis.z
	_check(Vector2(forward.x, forward.z).cross(Vector2(turned_heading.x, turned_heading.z)) < 0.0, "positive Godot yaw yields negative XZ cross")
	var baseline: Dictionary = ai.compute_controls(p, forward, 15.0, 0.016)
	var with_obstacle: Dictionary = ai.compute_controls(p, forward, 15.0, 0.016, [{"distance_m": 12.0, "lateral_m": 0.0}])
	_check(with_obstacle["target_speed_mps"] < baseline["target_speed_mps"], "obstacle lowers target speed")
	_check(with_obstacle["brake"] >= baseline["brake"], "obstacle does not decrease braking")
	var off_lane: Dictionary = ai.compute_controls(p, forward, 15.0, 0.016, [{"distance_m": 12.0, "lateral_m": 10.0}])
	_check(is_equal_approx(off_lane["target_speed_mps"], baseline["target_speed_mps"]), "off-lane obstacles ignored")
	var offroad: Dictionary = ai.compute_controls(Vector3(900, 20, 900), forward, 4.0, 0.016)
	_check(offroad["needs_reset"], "AI reports grossly off-route condition")
	var straight_speed := ai._corner_speed(75.0)
	var most_curved := INF
	for i in range(5, 125):
		most_curved = minf(most_curved, ai._corner_speed(float(i) * 6.0))
	_check(most_curved < straight_speed, "curvature reduces safe corner speed")
	var invalid_adapter = Adapter.apply(Node.new(), {"throttle": 1.0})
	_check(not invalid_adapter, "adapter rejects vehicles without input API")

func _test_ai_closed_course() -> void:
	# Actual Godot KinematicCar and RacerAI code; deterministic visual competence still
	# needs a human viewport playtest, independent from this completion assertion.
	var e = RaceEngine.new()
	e.load_road_graph(graph)
	e.register_racer("ai")
	var def: Dictionary = catalog.get_event("alder_street_circuit")
	def["laps"] = 1
	def["grid_seconds"] = 0
	def["countdown_seconds"] = 0
	def["finish_grace_seconds"] = 300.0
	_check(e.start_event(def), "one-lap AI simulation event starts")
	e.tick(0.001)
	var ai = RacerAI.new()
	_check(ai.configure(graph, def["lane_route"], true), "simulation AI route configured")
	ai.preferred_speed_mps = 14.5
	var car = KinematicCar.new()
	var first: Vector3 = e.route.sample(0.0)
	var dir: Vector2 = e.route.tangent(0.0)
	car.teleport_to(first, Vector3(dir.x, 0, dir.y))
	var resets := 0
	var max_error := 0.0
	for frame in range(4500):
		if e.get_racer("ai")["finished"]:
			break
		if e.needs_reset("ai"):
			var reset_pose: Dictionary = e.reset_racer("ai")
			car.teleport_to(reset_pose["position"], reset_pose["forward"])
			ai.reset_tracking()
			resets += 1
		var state: Dictionary = Adapter.read_state(car)
		var control: Dictionary = ai.compute_controls(state["position"], state["forward"], state["speed_mps"], 0.05)
		if control["needs_reset"]:
			var reset_pose: Dictionary = e.reset_racer("ai")
			car.teleport_to(reset_pose["position"], reset_pose["forward"])
			ai.reset_tracking()
			resets += 1
			continue
		if frame == 0:
			_check(Adapter.apply(car, control), "kinematic car implements real adapter")
		else:
			Adapter.apply(car, control)
		car.advance(0.05)
		var projection: Dictionary = e.route.project(car.global_position)
		car.global_position.y = (projection["point"] as Vector3).y
		max_error = maxf(max_error, float(projection["distance_m"]))
		e.update_racer_state("ai", car.global_position, car.get_drive_velocity())
		e.tick(0.05)
	_check(e.get_racer("ai")["finished"], "AI completes representative closed course")
	_check(resets <= 2, "AI needs at most two recoveries")
	_check(max_error < 22.0, "AI stays within recovery corridor")
