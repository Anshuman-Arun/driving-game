extends SceneTree
## Runs *real* production event JSON against the authoritative World PR #3 graph.
## No world files are copied into this module or committed in this branch.
## godot --headless --path modules/racing --script res://tests/run_production_tests.gd -- \
##   --graph=/absolute/path/road_graph_v1.json --events=/absolute/path/events_v1.json
const RaceEngine = preload("../race_engine.gd")
const RaceRoute = preload("../race_route.gd")
const EventCatalog = preload("../event_catalog.gd")
const RacerAI = preload("../racer_ai.gd")

const RACER_IDS := ["player", "rival_1", "rival_2", "rival_3"]
const EXPECTED := {
	"alder_street_circuit": {
		"kind": "circuit", "laps": 3, "distance_m": 877.016, "gates": 10,
		"lanes": ["lane_alder_depot_ab", "turn_depot_alder_depot_ab__depot_chapel_ab",
			"lane_depot_chapel_ab", "turn_chapel_depot_chapel_ab__chapel_alder_ab",
			"lane_chapel_alder_ab", "turn_alder_chapel_alder_ab__alder_depot_ab"]},
	"north_ridge_climb": {
		"kind": "sprint", "laps": 1, "distance_m": 2393.639, "gates": 18,
		"lanes": ["lane_valley_lake_ba", "turn_valley_valley_lake_ba__ridge_valley_ba",
			"lane_ridge_valley_ba"]},
	"eastwater_lakeside_sprint": {
		"kind": "sprint", "laps": 1, "distance_m": 2184.846, "gates": 16,
		"lanes": ["lane_valley_lake_ab", "turn_lake_valley_lake_ab__lake_alder_ab",
			"lane_lake_alder_ab"]},
	"green_valley_tour": {
		"kind": "circuit", "laps": 1, "distance_m": 4814.099, "gates": 34,
		"lanes": ["lane_alder_market_ab", "turn_market_alder_market_ab__market_valley_ab",
			"lane_market_valley_ab", "turn_valley_market_valley_ab__ridge_valley_ba",
			"lane_ridge_valley_ba", "turn_ridge_ridge_valley_ba__cedar_ridge_ba",
			"lane_cedar_ridge_ba", "turn_cedar_cedar_ridge_ba__alder_cedar_ba",
			"lane_alder_cedar_ba", "turn_alder_alder_cedar_ba__alder_market_ab"]}
}

var checks: int = 0
var failures: Array[String] = []

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("FAIL: " + description)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var graph_path := ""
	var events_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--graph="):
			graph_path = arg.trim_prefix("--graph=")
		elif arg.begins_with("--events="):
			events_path = arg.trim_prefix("--events=")
	if graph_path.is_empty() or events_path.is_empty() or not FileAccess.file_exists(graph_path) or not FileAccess.file_exists(events_path):
		printerr("Missing --graph=/path/to/road_graph_v1.json and --events=/path/to/events_v1.json")
		quit(2)
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(graph_path)) != OK or not (parser.data is Dictionary):
		printerr("Invalid authoritative road graph JSON")
		quit(2)
		return
	var graph: Dictionary = parser.data
	var catalog = EventCatalog.new()
	if not catalog.load_file(events_path):
		printerr("Production catalog: " + catalog.last_error)
		quit(2)
		return
	_check(RaceRoute.validate_road_graph(graph).is_empty(), "authoritative graph validates")
	_check(graph["lanes"].size() == 104, "canonical graph has 104 directed lanes")
	_check(catalog.events.size() == 4, "catalog contains exactly four production events")
	for id in EXPECTED.keys():
		_test_event(graph, catalog.get_event(id), EXPECTED[id])
	if failures.is_empty():
		print("PRODUCTION RACING TESTS PASSED: %d checks, all four events" % checks)
		quit(0)
	else:
		printerr("PRODUCTION RACING TESTS FAILED: %d / %d checks" % [failures.size(), checks])
		quit(1)

func _test_event(graph: Dictionary, definition: Dictionary, expected: Dictionary) -> void:
	var id: String = str(definition.get("id", "missing"))
	_check(not definition.is_empty(), id + " found in production catalog")
	if definition.is_empty():
		return
	_check(definition["kind"] == expected["kind"] and int(definition["laps"]) == int(expected["laps"]), id + " kind and lap count")
	_check(definition["lane_route"] == expected["lanes"], id + " directed lane sequence")
	_check(definition["checkpoints"].size() == expected["gates"], id + " authored checkpoint count")
	var engine = RaceEngine.new()
	_check(engine.load_road_graph(graph), id + " loads canonical graph")
	for racer_id in RACER_IDS:
		_check(engine.register_racer(racer_id, racer_id == "player"), id + " registers " + racer_id)
	_check(engine.start_event(definition), id + " engine accepts production event: " + engine.last_error)
	if engine.state != RaceEngine.State.GRID:
		return
	_check(absf(engine.route.length_m - float(expected["distance_m"])) < 0.02, id + " route distance matches production report")
	_check(absf(engine.route.length_m - float(definition["route_length_m"])) < 0.02, id + " catalog route_length_m verified")
	_check(absf(engine.route.length_m * float(definition["laps"]) - float(definition["total_race_distance_m"])) < 0.03, id + " total race distance")
	var previous_s := -1.0
	for cp in engine.checkpoints:
		_check(float(cp["s"]) > previous_s, id + " ordered gate " + str(cp["id"]))
		_check(float(engine.route.project(cp["center"], float(cp["s"]))["distance_m"]) <= float(cp["radius_m"]), id + " gate on route " + str(cp["id"]))
		previous_s = float(cp["s"])
	var slots: Array[Dictionary] = engine.get_starting_grid()
	_check(slots.size() == 4, id + " exposes four physical grid transforms")
	if slots.size() != 4:
		return
	for index in range(4):
		var slot: Dictionary = slots[index]
		var authored: Dictionary = definition["start_grid"][index]
		var arc: float = float(7 + 10 * index)
		var pose: Dictionary = engine.get_starting_pose(str(slot["id"]))
		var racer: Dictionary = engine.get_racer(str(slot["id"]))
		var transform: Transform3D = pose["transform"]
		_check(str(slot["id"]) == RACER_IDS[index] and str(slot["id"]) == str(authored["id"]), id + " authored racer/grid order " + str(index))
		_check(is_equal_approx(float(slot["route_s_m"]), arc) and absf(float(racer["progress_m"]) - arc) < 0.001, id + " racer initializes at " + str(arc) + "m")
		_check((slot["position"] as Vector3).distance_to(RaceRoute.point3(authored["position"])) < 0.001, id + " authoritative physical position " + str(index))
		_check((slot["position"] as Vector3).distance_to(engine.route.sample(arc)) < 0.02, id + " grid is on its lane " + str(index))
		_check((-transform.basis.z).normalized().dot(slot["forward"]) > 0.999, id + " physical transform follows road " + str(index))
		_check(not engine.needs_reset(str(slot["id"])), id + " starts without false reset " + str(index))
	_check(engine.standings()[0]["id"] == "rival_3" and engine.standings()[3]["id"] == "player", id + " initial order reflects actual staggered progress")
	_check(engine.get_results().is_empty(), id + " refuses premature results")
	_check(not engine.synchronize_racer_spawn("rival_3", engine.route.sample(70.0)), id + " rejects distant countdown spawn")
	_check(engine.synchronize_racer_spawn("player", slots[0]["position"] + Vector3(0, 0.15, 0)), id + " accepts small physical height offset")
	engine.tick(float(definition["grid_seconds"]))
	_check(engine.state == RaceEngine.State.COUNTDOWN, id + " GRID to COUNTDOWN")
	engine.tick(float(definition["countdown_seconds"]))
	_check(engine.state == RaceEngine.State.RACING, id + " COUNTDOWN to RACING")
	var gate_history: Dictionary = {}
	for racer_id in RACER_IDS:
		gate_history[racer_id] = []
	engine.checkpoint_passed.connect(func(racer_id: String, checkpoint_id: String, lap: int) -> void:
		(gate_history[racer_id] as Array).append("%d:%s" % [lap, checkpoint_id])
	)
	var expected_history: Array[String] = []
	for lap in range(1, int(definition["laps"]) + 1):
		for cp in definition["checkpoints"]:
			expected_history.append("%d:%s" % [lap, str(cp["id"])])
	var full_distance: float = engine.route.length_m * float(definition["laps"])
	var max_steps: int = ceili(full_distance / 2.5) + 4
	for step in range(1, max_steps + 1):
		for slot in slots:
			var racer_id: String = str(slot["id"])
			if bool(engine.get_racer(racer_id)["finished"]):
				continue
			var distance: float = minf(full_distance, float(slot["route_s_m"]) + float(step) * 2.5)
			if not engine.update_racer_state(racer_id, engine.route.sample(distance), Vector3.ZERO):
				_check(false, id + " physical position feed accepted for " + racer_id)
				return
		engine.tick(0.15)
		if engine.state == RaceEngine.State.FINISHED:
			break
		var reset_detected := false
		for racer_id in RACER_IDS:
			if engine.needs_reset(racer_id):
				_check(false, id + " unexpectedly requests " + racer_id + " reset: " + str(engine.get_racer(racer_id)["last_invalid_reason"]))
				reset_detected = true
		if reset_detected:
			return
	_check(engine.state == RaceEngine.State.FINISHED, id + " event finishes before timeout")
	for racer_id in RACER_IDS:
		var racer: Dictionary = engine.get_racer(racer_id)
		_check(bool(racer["finished"]), id + " finished racer " + racer_id)
		_check(int(racer["invalid_laps"]) == 0, id + " no false teleport/shortcut " + racer_id)
		_check(gate_history[racer_id] == expected_history, id + " exact checkpoint sequence all laps " + racer_id)
	var results: Dictionary = engine.get_results()
	_check(results["event_id"] == id and results["standings"].size() == 4, id + " authoritative race results")
	_check(results["standings"][0]["id"] == "rival_3", id + " staggered leader wins equal-speed run")
	_check(engine.show_results(), id + " shows results")
	_check(engine.restart_event(), id + " restarts from results")
	for slot in slots:
		var racer: Dictionary = engine.get_racer(str(slot["id"]))
		_check(int(racer["lap"]) == 1 and int(racer["checkpoint_index"]) == 0 and not racer["finished"], id + " restart clears race state " + str(slot["id"]))
		_check(absf(float(racer["progress_m"]) - float(slot["route_s_m"])) < 0.001, id + " restart restores progress " + str(slot["id"]))
		_check((racer["position"] as Vector3).distance_to(slot["position"]) < 0.001, id + " restart restores physical pose " + str(slot["id"]))
	engine.tick(float(definition["grid_seconds"]) + float(definition["countdown_seconds"]))
	_check(engine.state == RaceEngine.State.RACING, id + " restart countdown completes")
	_check(engine.update_racer_state("rival_1", engine.route.sample(200.0), Vector3.ZERO), id + " accepts untrusted real-vehicle telemetry")
	engine.tick(0.016)
	_check(engine.needs_reset("rival_1") and engine.get_racer("rival_1")["last_invalid_reason"] == "teleport_or_unphysical_speed", id + " keeps live teleport protection")
	var recovery: Dictionary = engine.reset_racer("rival_1")
	_check(absf(float(engine.get_racer("rival_1")["progress_m"]) - 17.0) < 0.001, id + " first-lap reset restores original offset")
	_check((recovery["position"] as Vector3).distance_to(slots[1]["position"]) < 0.001, id + " reset returns physical grid position")
	var planner = RacerAI.new()
	_check(planner.configure_event(graph, definition), id + " AI accepts production advisory profile: " + planner.last_error)
	_check(planner.speed_guidance.size() == definition["ai_speed_guidance"].size(), id + " AI uses all advisory samples")
	var recommended: float = float(definition["ai_speed_guidance"][0]["target_kph"]) / 3.6
	_check(planner._corner_speed(0.0) <= minf(recommended, engine.route.speed_limit(0.0)) + 0.01, id + " AI obeys guidance plus road limit")
	print("PRODUCTION EVENT: %s route=%.3fm total=%.3fm gates=%d laps=%d grids=7/17/27/37m" % [
		id, engine.route.length_m, full_distance, engine.checkpoints.size(), int(definition["laps"])])
