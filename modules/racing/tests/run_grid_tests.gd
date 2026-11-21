extends SceneTree
## Standalone staggered-grid regressions using only the existing tiny racing fixtures.
## godot --headless --path modules/racing --script res://tests/run_grid_tests.gd
const RaceEngine = preload("../race_engine.gd")
const RaceRoute = preload("../race_route.gd")
const RacerAI = preload("../racer_ai.gd")
const EventCatalog = preload("../event_catalog.gd")

var checks := 0
var failures: Array[String] = []

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var graph_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/road_graph_v1.json"))
	var catalog = EventCatalog.new()
	_check(graph_data is Dictionary, "legacy graph fixture loads")
	_check(catalog.load_file("res://fixtures/events_v1.json"), "legacy event fixture loads")
	if not (graph_data is Dictionary) or catalog.events.is_empty():
		quit(1)
		return
	var graph: Dictionary = graph_data
	var original: Dictionary = catalog.get_event("alder_street_circuit")
	var route = RaceRoute.new()
	_check(route.configure(graph, original["lane_route"], true).is_empty(), "local closed route configures")
	var grid: Array[Dictionary] = []
	var ids := ["player", "rival_1", "rival_2", "rival_3"]
	for i in range(ids.size()):
		var s: float = 7.0 + float(i) * 10.0
		var forward: Vector2 = route.tangent(s)
		var p: Vector3 = route.sample(s)
		grid.append({"id": ids[i], "route_s_m": s, "position": [p.x, p.y, p.z], "forward": [forward.x, 0.0, forward.y]})
	var event: Dictionary = original.duplicate(true)
	event["start_grid"] = grid
	var e = RaceEngine.new()
	_check(e.load_road_graph(graph), "load graph")
	for id in ids:
		_check(e.register_racer(id, id == "player"), "register " + id)
	_check(e.start_event(event), "staggered grid event starts: " + e.last_error)
	if e.state != RaceEngine.State.GRID:
		quit(1)
		return
	for i in range(ids.size()):
		var r: Dictionary = e.get_racer(ids[i])
		var s: float = float(grid[i]["route_s_m"])
		_check(absf(float(r["progress_m"]) - s) < 0.001, ids[i] + " has authored progress")
		_check(absf(float(r["continuous_s"]) - s) < 0.001, ids[i] + " has authored continuous progress")
		_check((r["position"] as Vector3).distance_to(route.sample(s)) < 0.001, ids[i] + " has physical grid position")
		_check((-e.get_starting_pose(ids[i])["transform"].basis.z).normalized().dot(r["start_forward"]) > 0.999, ids[i] + " starts facing forward")
	_check(e.standings()[0]["id"] == "rival_3", "farthest-ahead grid racer leads")
	_check(not e.synchronize_racer_spawn("player", route.sample(40)), "sync rejects displacement before start")
	_check(e.synchronize_racer_spawn("player", route.sample(7) + Vector3(0, 0.15, 0)), "sync accepts minor physical height offset")
	_check(e.update_racer_state("rival_1", route.sample(17), Vector3.ZERO), "countdown telemetry sync")
	_check(not e.update_racer_state("rival_1", route.sample(30), Vector3.ZERO), "countdown rejects grid movement")
	e.tick(float(event["grid_seconds"]))
	_check(e.state == RaceEngine.State.COUNTDOWN, "GRID to COUNTDOWN")
	e.tick(float(event["countdown_seconds"]))
	_check(e.state == RaceEngine.State.RACING, "COUNTDOWN to RACING")
	var history: Dictionary = {}
	for id in ids:
		history[id] = []
	e.checkpoint_passed.connect(func(id: String, gate: String, lap: int) -> void:
		(history[id] as Array).append("%d:%s" % [lap, gate])
	)
	var race_m: float = route.length_m * float(event["laps"])
	for frame in range(ceili(race_m / 2.5) + 6):
		for slot in grid:
			var id: String = slot["id"]
			if bool(e.get_racer(id)["finished"]):
				continue
			var s: float = minf(race_m, float(slot["route_s_m"]) + float(frame + 1) * 2.5)
			e.update_racer_state(id, route.sample(s), Vector3.ZERO)
		e.tick(0.15)
		if e.state == RaceEngine.State.FINISHED:
			break
	_check(e.state == RaceEngine.State.FINISHED, "staggered 3-lap circuit finishes")
	for id in ids:
		var racer: Dictionary = e.get_racer(id)
		_check(bool(racer["finished"]) and not bool(racer["needs_reset"]), id + " finished without invalid jumps")
		_check(int(racer["invalid_laps"]) == 0, id + " has zero invalid laps")
		var expected_history: Array[String] = []
		for lap in range(1, int(event["laps"]) + 1):
			for cp in event["checkpoints"]:
				expected_history.append("%d:%s" % [lap, cp["id"]])
		_check(history[id] == expected_history, id + " passed every checkpoint in order on every lap")
	_check(e.get_results()["standings"][0]["id"] == "rival_3", "authoritative results reflect grid")
	_check(e.restart_event(), "restart event from FINISHED")
	for slot in grid:
		var id: String = slot["id"]
		_check(absf(float(e.get_racer(id)["progress_m"]) - float(slot["route_s_m"])) < 0.001, id + " restart restores slot")
	_check(e.get_results().is_empty(), "results unavailable after restart")
	e.tick(float(event["grid_seconds"]) + float(event["countdown_seconds"]))
	_check(e.update_racer_state("rival_2", route.sample(250), Vector3.ZERO), "accept real-vehicle telemetry before validation")
	e.tick(0.016)
	_check(e.needs_reset("rival_2"), "racing teleport still rejected")
	var reset_pose: Dictionary = e.reset_racer("rival_2")
	_check((reset_pose["position"] as Vector3).distance_to(route.sample(27.0)) < 0.001, "first-lap reset returns authored slot")
	_check(absf(float(e.get_racer("rival_2")["progress_m"]) - 27.0) < 0.001, "first-lap reset restores progress")
	var invalid: Dictionary = event.duplicate(true)
	invalid["start_grid"][0]["id"] = "rival_3"
	e = RaceEngine.new()
	e.load_road_graph(graph)
	for id in ids:
		e.register_racer(id)
	_check(not e.start_event(invalid), "duplicate grid slot rejected")
	invalid = event.duplicate(true)
	invalid["start_grid"][0]["route_s_m"] = 100.0
	_check(not e.start_event(invalid), "wrong grid arclength rejected")
	invalid = event.duplicate(true)
	invalid["start_grid"][0]["forward"] = [1.0, 0.0, 0.0]
	invalid["start_grid"][0]["position"] = [900.0, 1.0, 900.0]
	_check(not e.start_event(invalid), "off-route grid rejected")
	var legacy = RaceEngine.new()
	legacy.load_road_graph(graph)
	legacy.register_racer("legacy")
	_check(legacy.start_event(original), "legacy event still loads without start_grid")
	_check(is_zero_approx(float(legacy.get_racer("legacy")["progress_m"])), "legacy spawn remains at route zero")
	var planner = RacerAI.new()
	_check(planner.configure(graph, original["lane_route"], true), "legacy AI configure remains available")
	_check(planner.speed_guidance.is_empty(), "legacy AI has no unexpected advisory cap")
	_check(planner.configure_event(graph, event), "AI event configure accepts absence of guidance")
	_check(planner.speed_guidance.is_empty(), "AI without advisory retains original planner")
	_check(not planner.set_speed_guidance([{"at_m": 0, "target_kph": 80, "speed_limit_kph": 50}]), "AI rejects advisory above its speed limit")
	if failures.is_empty():
		print("RACING GRID TESTS PASSED: %d checks" % checks)
		quit(0)
	else:
		printerr("RACING GRID TESTS FAILED: %d / %d checks" % [failures.size(), checks])
		quit(1)
