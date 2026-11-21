extends SceneTree
## Native, intentionally unexecuted until World PR #3 + Traffic PR #4 are present.
## From integrated Godot root:
## godot --headless --path . --script res://content/traffic/tests/run_world_scenarios.gd -- --smoke
## godot --headless --path . --script res://content/traffic/tests/run_world_scenarios.gd -- --full
const TrafficSimulation = preload("res://modules/traffic/src/traffic_simulation.gd")
const TrafficContentLoader = preload("res://content/traffic/traffic_content_loader.gd")
const VehicleClearance = preload("res://content/traffic/tests/vehicle_clearance.gd")
const GRAPH_FILE := "res://data/world/road_graph_v1.json"
const PACK_FILE := "res://content/traffic/controls_v1.json"
const SCENARIOS_FILE := "res://content/traffic/scenarios_v1.json"
const DT := 1.0 / 30.0
const LEGACY_POINT_THRESHOLD_M := 3.6  # Diagnostic only; never a collision rule.
const MAX_WAIT_S := 30.0
const MAX_RESERVATION_S := 30.0

var graph_data: Dictionary = {}
var pack_data: Dictionary = {}
var scenario_data: Dictionary = {}
var failed := 0
var passed := 0


func _initialize() -> void:
	call_deferred("_run")


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		printerr("Missing required integrated file: ", path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		printerr("Invalid JSON file: ", path)
		return {}
	return parsed


func _check(ok: bool, name: String) -> void:
	if ok:
		passed += 1
		print("PASS ", name)
	else:
		failed += 1
		printerr("FAIL ", name)


func _run() -> void:
	graph_data = _read_json(GRAPH_FILE)
	pack_data = _read_json(PACK_FILE)
	scenario_data = _read_json(SCENARIOS_FILE)
	if graph_data.is_empty() or pack_data.is_empty() or scenario_data.is_empty():
		quit(2)
		return
	var basic = TrafficSimulation.new()
	_check(basic.load_road_graph(graph_data), "canonical RoadGraph loads in native traffic simulator")
	if not basic.graph_valid:
		printerr("RoadGraph errors: ", basic.graph.errors)
		quit(2)
		return
	var loader = TrafficContentLoader.new()
	_check(loader.validate_pack(pack_data, basic), "loader validates canonical controls + implicit merge mapping")
	if not loader.errors.is_empty():
		printerr("Loader errors: ", loader.errors)
		quit(2)
		return
	_check(loader.native_definitions(pack_data).size() == 8, "eight runtime controls; three pass-through nodes excluded")
	_check(loader.apply_pack(pack_data, basic), "configure_junctions() accepts eight authored definitions")
	_check(basic.junctions.size() == 30, "22 implicit merges + 8 explicit junctions")
	_check(basic.inbound_junction.size() == 88, "62 implicit connector mappings plus 26 explicit travel approaches")
	_check(not loader.apply_pack(pack_data, basic), "double application rejected before mutation")
	var bad: Dictionary = pack_data.duplicate(true)
	bad["junctions"][0]["incoming_lane_ids"][0] = "not_a_lane"
	var invalid_sim = TrafficSimulation.new()
	invalid_sim.load_road_graph(graph_data)
	_check(not loader.validate_pack(bad, invalid_sim), "invalid lane reference rejected")
	bad = pack_data.duplicate(true)
	bad["junctions"][0]["clearance_m"] = 50.0
	_check(not loader.validate_pack(bad, invalid_sim), "nonreleasing reservation clearance rejected")
	bad = pack_data.duplicate(true)
	bad["junctions"][0]["mode"] = "signal"
	_check(not loader.validate_pack(bad, invalid_sim), "unsupported all-green signal configuration rejected")
	_clearance_regressions()
	var full: bool = OS.get_cmdline_user_args().has("--full")
	var duration_s: float = float(scenario_data["duration_s"]) if full else 15.0
	var seeds: Array = scenario_data["seeds"] if full else [scenario_data["seeds"][0]]
	var total_cases := 0
	var failed_cases := 0
	var sites: Array = scenario_data["regions"].duplicate()
	sites.append_array(scenario_data.get("hotspots", []))
	for region in sites:
		var densities: Array = region.get("populations", scenario_data["populations"])
		for population in densities:
			for seed in seeds:
				var first: Dictionary = _case(region, int(population), int(seed), duration_s)
				var second: Dictionary = _case(region, int(population), int(seed), duration_s)
				var label: String = "%s population=%d seed=%d" % [str(region["id"]), int(population), int(seed)]
				var ok: bool = bool(first.get("ok", false)) and bool(second.get("ok", false))
				_check(ok, label + " safety/directed routing")
				_check(first.get("fingerprint") == second.get("fingerprint") and first.get("errors") == second.get("errors") and first.get("conflicts") == second.get("conflicts"), label + " seed replay deterministic")
				if not ok:
					printerr("CASE FAILURE ", label, " first=", first.get("errors", []), " second=", second.get("errors", []))
					failed_cases += 1
				print("CASE METRICS ", label, " peak_active=", first.get("peak_active"),
					" min_point_gap_m=", first.get("min_gap_m"), " benign_close_samples=", first.get("benign_close_samples"),
					" genuine_conflicts=", first.get("conflicts"), " max_wait_s=", first.get("max_wait_s"),
					" max_held_s=", first.get("max_held_s"), " transitions=", first.get("transitions"))
				total_cases += 1
	print("WORLD TRAFFIC TESTS: %d pass, %d fail; %d cases, %d failed cases, mode=%s" % [
		passed, failed, total_cases, failed_cases, "full" if full else "smoke"])
	quit(0 if failed == 0 else 1)


func _case(region: Dictionary, population: int, seed_value: int, duration_s: float) -> Dictionary:
	var sim = TrafficSimulation.new()
	if not sim.load_road_graph(graph_data):
		return {"ok": false, "errors": ["graph import failed"]}
	var loader = TrafficContentLoader.new()
	if not loader.apply_pack(pack_data, sim):
		return {"ok": false, "errors": loader.errors}
	sim.reset(seed_value)
	sim.set_density(population)
	sim.set_player_state(Vector3.ZERO, 0.0, false)
	var xyz: Array = region["view_position"]
	var viewer := Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
	var previous_lane: Dictionary = {}
	var waits: Dictionary = {}
	var holds: Dictionary = {}
	var errors: Array[String] = []
	var conflicts: Dictionary = {}
	var conflict_events: Dictionary = {}
	var benign_close_samples := 0
	var fingerprint: int = 1
	var minimum_gap := INF
	var max_wait := 0.0
	var max_held := 0.0
	var peak_active := 0
	var total_transitions := 0
	var steps := int(ceilf(duration_s / DT))
	for tick in range(steps):
		sim.step(DT, viewer)
		var states: Array = sim.get_states()
		peak_active = maxi(peak_active, states.size())
		if states.size() > 20 or (population == 0 and states.size() > 0):
			_add_error(errors, "population cap or zero density violated")
		var now: Dictionary = {}
		for agent in states:
			var id: int = int(agent["id"])
			var lane_id: String = str(agent["lane_id"])
			if not sim.graph.lanes.has(lane_id):
				_add_error(errors, "agent on unknown lane")
				continue
			if previous_lane.has(id) and previous_lane[id] != lane_id:
				if not sim.graph.lanes[previous_lane[id]]["next_lane_ids"].has(lane_id):
					_add_error(errors, "wrong-way or nonadjacent lane transition %s -> %s" % [str(previous_lane[id]), lane_id])
				total_transitions += 1
			now[id] = lane_id
			var s: float = float(agent["s"])
			if s < -0.001 or s > sim.graph.lane_length(lane_id) + 0.001:
				_add_error(errors, "agent outside authored lane arc")
			if str(agent["state"]) == "WAIT_AT_JUNCTION":
				waits[id] = float(waits.get(id, 0.0)) + DT
				max_wait = maxf(max_wait, float(waits[id]))
			else:
				waits.erase(id)
			if str(agent["reserved_junction"]) != "":
				var holder: String = str(agent["reserved_junction"])
				holds[id] = float(holds.get(id, 0.0)) + DT
				max_held = maxf(max_held, float(holds[id]))
				if int(sim.reservations.get(holder, -1)) != id:
					_add_error(errors, "reservation ownership mismatch")
			else:
				holds.erase(id)
			if float(waits.get(id, 0.0)) > MAX_WAIT_S:
				_add_error(errors, "persistent intersection queue over 30s")
			if float(holds.get(id, 0.0)) > MAX_RESERVATION_S:
				_add_error(errors, "persistent un-released reservation over 30s")
			# Determinism includes lane choice, state, s, active IDs, and queueing.
			var snap: String = "%d:%s:%.3f:%s:%s" % [
				id, lane_id, s, str(agent["state"]), str(agent["reserved_junction"])]
			fingerprint = posmod(fingerprint * 131 + int(snap.hash()), 2147483647)
		previous_lane = now
		for i in range(states.size()):
			var a: Dictionary = states[i]
			for j in range(i + 1, states.size()):
				var b: Dictionary = states[j]
				var d: float = a["position"].distance_to(b["position"])
				minimum_gap = minf(minimum_gap, d)
				var finding: Dictionary = VehicleClearance.diagnose(a, b)
				if finding.is_empty():
					if d < LEGACY_POINT_THRESHOLD_M:
						benign_close_samples += 1
					continue
				var kind: String = str(finding["kind"])
				var pair_key: String = "%d:%d:%s" % [int(a["id"]), int(b["id"]), kind]
				if conflict_events.has(pair_key):
					continue
				conflict_events[pair_key] = true
				conflicts[kind] = int(conflicts.get(kind, 0)) + 1
				_add_error(errors, "%s: agents %d/%d at %s / %s, center=%.3fm, s=%.2f/%.2f" % [
					kind, int(a["id"]), int(b["id"]), str(a["lane_id"]), str(b["lane_id"]),
					d, float(a["s"]), float(b["s"])])
		if tick % 300 == 0 and not sim.reservations.is_empty():
			for jid in sim.reservations:
				if not sim.agents.has(sim.reservations[jid]):
					_add_error(errors, "orphan reservation at " + str(jid))
	if population > 0 and peak_active == 0:
		_add_error(errors, "density spawn failed throughout scenario")
	# Sparse local geography can mean fewer than requested 20 agents within 175m.
	# Report the realized peak; do not silently count requested density as achieved.
	return {"ok": errors.is_empty(), "errors": errors, "conflicts": conflicts,
		"benign_close_samples": benign_close_samples, "fingerprint": fingerprint,
		"min_gap_m": minimum_gap if minimum_gap < INF else -1.0,
		"max_wait_s": max_wait, "max_held_s": max_held,
		"peak_active": peak_active, "transitions": total_transitions}


func _clearance_regressions() -> void:
	# Independent fixtures: do not suppress opposing, turning or merge collisions.
	var a: Dictionary = VehicleClearance.fixture(0.0, 0.0, 1.0, 0.0, "lane_pair_ab", 10.0)
	var opposing: Dictionary = VehicleClearance.fixture(0.0, 3.4, -1.0, 0.0, "lane_pair_ba", 10.0)
	_check(VehicleClearance.diagnose(a, opposing).is_empty(), "legal 3.4m separated opposite lanes")
	var intruder: Dictionary = VehicleClearance.fixture(0.0, 1.2, -1.0, 0.0, "lane_pair_ba", 10.0)
	_check(not VehicleClearance.diagnose(a, intruder).is_empty(), "opposite-direction intrusion still fails")
	var follower: Dictionary = VehicleClearance.fixture(4.8, 0.0, 1.0, 0.0, "lane_pair_ab", 14.8)
	_check(VehicleClearance.diagnose(a, follower).get("kind") == "same_lane_rear_end", "same-lane rear-end clearance fails")
	var distant: Dictionary = VehicleClearance.fixture(5.6, 0.0, 1.0, 0.0, "lane_pair_ab", 15.6)
	_check(VehicleClearance.diagnose(a, distant).is_empty(), "safe same-lane headway passes")
	var loopback: Dictionary = VehicleClearance.fixture(0.8, 0.0, -1.0, 0.0, "lane_pair_ab", 40.0)
	_check(VehicleClearance.diagnose(a, loopback).get("kind") == "same_lane_body_overlap", "folded lane occupied by distant arc positions fails")
	var crossing: Dictionary = VehicleClearance.fixture(1.0, 0.0, 0.0, 1.0, "turn_crossing", 3.0)
	_check(VehicleClearance.diagnose(a, crossing).get("kind") == "turning_body_overlap", "crossing turn footprints fail")
	var adjacent: Dictionary = VehicleClearance.fixture(0.0, 2.4, -1.0, 0.0, "lane_pair_ba", 10.0)
	_check(VehicleClearance.diagnose(a, adjacent).is_empty(), "separated parallel footprints pass")
	var raised: Dictionary = VehicleClearance.fixture(0.0, 0.0, -1.0, 0.0, "lane_upper", 10.0, 4.0)
	_check(VehicleClearance.diagnose(a, raised).is_empty(), "grade-separated overlapping XZ paths pass")
	var merge_a: Dictionary = VehicleClearance.fixture(0.0, 0.0, 1.0, 0.0, "turn_merge_a", 3.0, 0.0, "lane_exit")
	var merge_b: Dictionary = VehicleClearance.fixture(1.0, 1.0, 1.0, 0.0, "turn_merge_b", 3.0, 0.0, "lane_exit")
	_check(VehicleClearance.diagnose(merge_a, merge_b).get("kind") == "unsafe_merge_body_overlap", "overlapping merge bodies fail")
	var bad_heading: Dictionary = VehicleClearance.fixture(0.0, 0.0, 0.0, 0.0, "lane_unknown", 2.0)
	_check(VehicleClearance.diagnose(a, bad_heading).get("kind") == "invalid_heading", "degenerate pose cannot silently pass")


func _add_error(errors: Array[String], message: String) -> void:
	if not errors.has(message) and errors.size() < 25:
		errors.append(message)
