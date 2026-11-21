## Fixed-step, deterministic, lightweight civilian traffic. Completely independent of physics nodes.
extends RefCounted

const TrafficGraph = preload("traffic_graph.gd")
const FIXED_DT := 1.0 / 30.0
const ACCEL_MPS2 := 1.75
const BRAKE_MPS2 := 4.5
const EMERGENCY_BRAKE_MPS2 := 8.0
const STANDSTILL_GAP_M := 3.5
const HEADWAY_S := 1.35
const DEFAULT_CAR_LENGTH_M := 4.3
const SPAWN_ATTEMPTS := 90
const SPAWN_CELL_M := 80.0
const SPAWN_SAMPLE_M := 35.0
const DESPAWN_RADIUS_M := 235.0
const SPAWN_MIN_RADIUS_M := 30.0
const SPAWN_MAX_RADIUS_M := 170.0

var graph = TrafficGraph.new()
var seed_value: int = 20261121
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var agents: Array[Dictionary] = []
var pool: Array[Dictionary] = []
var commands: Dictionary = {}
var _spawn_cells: Dictionary = {}
var spawn_exclusions: Array[Dictionary] = []
var controls: Dictionary = {}
var population_target: int = 0
var tick_count: int = 0
var simulation_time_s: float = 0.0
var total_spawned: int = 0
var total_recycled: int = 0
var _accumulator_s: float = 0.0
var _next_id: int = 1


func _init(initial_seed: int = 20261121) -> void:
	set_seed(initial_seed)


func set_seed(value: int) -> void:
	seed_value = value
	rng.seed = value


func load_road_graph(source: Dictionary) -> bool:
	var ok: bool = graph.load_road_graph(source)
	if ok:
		clear()
		_build_spawn_index()
	return ok


func set_junction_controls(config: Dictionary) -> bool:
	# Purely optional lane-ID keyed companion data; does not extend the shared road graph schema.
	var approaches: Variant = config.get("approaches", {})
	var signals: Variant = config.get("signals", {})
	if typeof(approaches) != TYPE_DICTIONARY or typeof(signals) != TYPE_DICTIONARY:
		return false
	for lane_id in approaches:
		if not graph.has_lane(lane_id) or typeof(approaches[lane_id]) != TYPE_DICTIONARY:
			return false
		var rule: Dictionary = approaches[lane_id]
		if not ["signal", "stop", "yield"].has(rule.get("mode", "")):
			return false
		if typeof(rule.get("junction_id")) != TYPE_STRING or rule["junction_id"].is_empty():
			return false
		if float(rule.get("stop_distance_m", 4.0)) < 1.0 or float(rule.get("stop_distance_m", 4.0)) >= graph.lanes[lane_id]["length_m"]:
			return false
		if rule["mode"] == "signal":
			if not signals.has(rule["junction_id"]) or typeof(rule.get("group")) != TYPE_STRING:
				return false
	for junction_id in signals:
		var signal: Variant = signals[junction_id]
		if typeof(signal) != TYPE_DICTIONARY or typeof(signal.get("phases")) != TYPE_ARRAY:
			return false
		if signal["phases"].is_empty():
			return false
		for phase in signal["phases"]:
			if typeof(phase) != TYPE_DICTIONARY or typeof(phase.get("group")) != TYPE_STRING or float(phase.get("duration_s", 0.0)) <= 0.0:
				return false
	controls = config.duplicate(true)
	return true


func set_population_target(count: int) -> void:
	population_target = clampi(count, 0, 20)


func set_spawn_exclusions(zones: Array[Dictionary]) -> void:
	# Reserve player/garage/race grid areas. Entries: {position: Vector3, radius: float}.
	spawn_exclusions = zones.duplicate(true)


func clear() -> void:
	for agent in agents:
		pool.append(agent)
	agents.clear()
	commands.clear()
	tick_count = 0
	simulation_time_s = 0.0
	_accumulator_s = 0.0
	_next_id = 1
	total_spawned = 0
	total_recycled = 0
	rng.seed = seed_value


func spawn_vehicle(lane_id: String, distance_m: float, initial_speed_mps: float = 0.0, cruise_factor: float = 1.0, car_length_m: float = DEFAULT_CAR_LENGTH_M) -> int:
	if not graph.has_lane(lane_id):
		return -1
	var lane: Dictionary = graph.lanes[lane_id]
	if distance_m < 0.0 or distance_m >= lane["length_m"] or car_length_m <= 0.0:
		return -1
	var pos: Vector3 = graph.sample(lane_id, distance_m)["position"]
	if not _spawn_space_clear(pos, car_length_m):
		return -1
	var agent: Dictionary = pool.pop_back() if not pool.is_empty() else {}
	agent.clear()
	agent.assign({
		"id": _next_id, "lane_id": lane_id, "s": distance_m,
		"speed": clampf(initial_speed_mps, 0.0, lane["speed_limit_mps"]),
		"cruise": clampf(cruise_factor, 0.55, 1.15),
		"length": car_length_m, "type": 0,
		"next_lane": "", "bridge_s": 0.0, "bridge_len": 0.0,
		"route": [], "route_index": 0, "reservation": "",
		"clear_remaining": 0.0, "dwell": 0.0, "state": "FOLLOW_LANE", "stopped_time": 0.0,
	})
	_next_id += 1
	_select_next(agent)
	agents.append(agent)
	total_spawned += 1
	return agent["id"]


func set_destination(agent_id: int, destination_lane_id: String) -> bool:
	for agent in agents:
		if agent["id"] == agent_id:
			if agent["bridge_len"] > 0.0:
				return false
			var route: Array[String] = graph.find_route(agent["lane_id"], destination_lane_id)
			if route.is_empty():
				return false
			agent["route"] = route
			agent["route_index"] = 0
			if route.size() > 1:
				agent["next_lane"] = route[1]
			return true
	return false


func spawn_near(viewer_position: Vector3) -> int:
	# Compact spatial index avoids any full-graph scan in the update loop.
	var entries: Array = []
	var cell := _cell(viewer_position)
	for x in range(cell.x - 3, cell.x + 4):
		for y in range(cell.y - 3, cell.y + 4):
			var key := Vector2i(x, y)
			if _spawn_cells.has(key):
				entries.append_array(_spawn_cells[key])
	if entries.is_empty():
		return -1
	for attempt in range(SPAWN_ATTEMPTS):
		var entry: Array = entries[rng.randi_range(0, entries.size() - 1)]
		var lane_id: String = entry[0]
		var lane: Dictionary = graph.lanes[lane_id]
		var s: float = clampf(float(entry[1]) + rng.randf_range(-SPAWN_SAMPLE_M * 0.5, SPAWN_SAMPLE_M * 0.5), 0.0, lane["length_m"] - 0.01)
		var pos: Vector3 = graph.sample(lane_id, s)["position"]
		var from_viewer := _flat_distance(pos, viewer_position)
		if from_viewer < SPAWN_MIN_RADIUS_M or from_viewer > SPAWN_MAX_RADIUS_M:
			continue
		var excluded := false
		for zone in spawn_exclusions:
			if typeof(zone.get("position")) == TYPE_VECTOR3 and _flat_distance(pos, zone["position"]) <= float(zone.get("radius", 0.0)) + 3.0:
				excluded = true
				break
		if excluded:
			continue
		var cruise := rng.randf_range(0.74, 1.06)
		var car_len := rng.randf_range(3.7, 5.0)
		var id := spawn_vehicle(lane_id, s, 0.0, cruise, car_len)
		if id != -1:
			for agent in agents:
				if agent["id"] == id:
					agent["type"] = rng.randi_range(0, 2)
					break
			return id
	return -1


func _build_spawn_index() -> void:
	_spawn_cells.clear()
	var ids: Array = graph.lanes.keys()
	ids.sort()
	for lane_id in ids:
		var lane: Dictionary = graph.lanes[lane_id]
		var count: int = maxi(1, ceili(lane["length_m"] / SPAWN_SAMPLE_M))
		for i in range(count + 1):
			var s: float = lane["length_m"] * i / float(count)
			var key := _cell(graph.sample(lane_id, s)["position"])
			if not _spawn_cells.has(key):
				_spawn_cells[key] = []
			_spawn_cells[key].append([lane_id, s])


func _cell(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / SPAWN_CELL_M), floori(position.z / SPAWN_CELL_M))


func step(delta: float, viewer_position: Vector3 = Vector3.ZERO, obstacles: Array = []) -> void:
	if delta <= 0.0 or delta > 1.0:
		return
	_accumulator_s += delta
	var safety := 0
	while _accumulator_s + 0.00000001 >= FIXED_DT and safety < 30:
		_tick(FIXED_DT, viewer_position, obstacles)
		_accumulator_s -= FIXED_DT
		safety += 1


func get_agent_pose(agent_id: int) -> Dictionary:
	for agent in agents:
		if agent["id"] == agent_id:
			return _pose(agent)
	return {}


func get_agent_command(agent_id: int) -> Dictionary:
	return commands.get(agent_id, {}).duplicate(true)


func snapshot() -> Array:
	# Stable ordering/rounding for replay logs and deterministic fixture assertions.
	var result: Array = []
	for agent in agents:
		result.append([agent["id"], agent["lane_id"], snappedf(agent["s"], 0.0001), snappedf(agent["speed"], 0.0001), agent["next_lane"], snappedf(agent["bridge_s"], 0.0001), agent["reservation"], agent["state"]])
	return result


func _tick(dt: float, viewer_position: Vector3, obstacles: Array) -> void:
	tick_count += 1
	simulation_time_s = tick_count * FIXED_DT
	# Cull distant agents and dead ends, recycling dictionaries for later spawns.
	for i in range(agents.size() - 1, -1, -1):
		if _flat_distance(_pose(agents[i])["position"], viewer_position) > DESPAWN_RADIUS_M:
			_recycle_at(i)
	# Fixed-count, bounded population manager. No simulation outside its locality.
	var tries: int = mini(3, maxi(0, population_target - agents.size()))
	for _i in range(tries):
		if spawn_near(viewer_position) == -1:
			break
	var reserved: Dictionary = {}
	for agent in agents:
		if agent["reservation"] != "":
			reserved[agent["reservation"]] = agent["id"]
	# Decisions use current positions before any integration, preventing iteration-order bias.
	var decisions: Dictionary = {}
	for agent in agents:
		decisions[agent["id"]] = _decide(agent, obstacles, reserved)
	# Grant one new junction reservation at a time in stable ID order.
	for agent in agents:
		var decision: Dictionary = decisions[agent["id"]]
		if decision.get("request_reservation", false):
			var junction: String = decision["junction"]
			if not reserved.has(junction):
				reserved[junction] = agent["id"]
				agent["reservation"] = junction
				var lane: Dictionary = graph.lanes[agent["lane_id"]]
				agent["clear_remaining"] = lane["length_m"] - agent["s"] + 34.0
				decision["must_stop"] = false
				decision["target"] = minf(decision["free_target"], 8.5)
				decision["state"] = "CROSSING"
			else:
				# The second requester was not aware of the first grant during planning.
				# It must be stopped, never allowed to enter the junction in this tick.
				decision["must_stop"] = true
				decision["target"] = 0.0
				decision["state"] = "WAIT_AT_JUNCTION"
				decision["stop_s"] = graph.lanes[agent["lane_id"]]["length_m"] - float(controls["approaches"][agent["lane_id"]].get("stop_distance_m", 4.0))
	# Move with acceleration/deceleration caps and safety clamps.
	for agent in agents:
		var decision: Dictionary = decisions[agent["id"]]
		var desired: float = decision["target"]
		var previous_speed: float = agent["speed"]
		var maximum_delta: float = (ACCEL_MPS2 if desired >= previous_speed else (EMERGENCY_BRAKE_MPS2 if decision["emergency"] else BRAKE_MPS2)) * dt
		agent["speed"] = move_toward(previous_speed, desired, maximum_delta)
		var ds: float = (previous_speed + agent["speed"]) * 0.5 * dt
		if decision["must_stop"] and agent["bridge_len"] <= 0.0:
			var stop_s: float = decision["stop_s"]
			if agent["s"] + ds >= stop_s:
				ds = maxf(0.0, stop_s - agent["s"])
				agent["speed"] = 0.0
		# Hard non-overlap clamp supplements the anticipatory following controller.
		for other in agents:
			if other["id"] == agent["id"]:
				continue
			var bumper_space := INF
			if other["lane_id"] == agent["lane_id"] and other["s"] > agent["s"]:
				bumper_space = other["s"] - agent["s"] - (agent["length"] + other["length"]) * 0.5
			elif agent["bridge_len"] <= 0.0 and agent["next_lane"] != "" and other["lane_id"] == agent["next_lane"]:
				bumper_space = graph.lanes[agent["lane_id"]]["length_m"] - agent["s"] + other["s"] - (agent["length"] + other["length"]) * 0.5
			if ds > bumper_space - STANDSTILL_GAP_M:
				ds = maxf(0.0, bumper_space - STANDSTILL_GAP_M)
				agent["speed"] = minf(agent["speed"], ds / dt)
		_advance(agent, ds)
		if agent["reservation"] != "":
			agent["clear_remaining"] -= ds
			if agent["clear_remaining"] <= 0.0:
				agent["reservation"] = ""
				agent["clear_remaining"] = 0.0
		if agent["speed"] < 0.15:
			agent["stopped_time"] += dt
			if decision["must_stop"] and agent["s"] >= decision["stop_s"] - 0.15:
				agent["dwell"] += dt
		else:
			agent["stopped_time"] = 0.0
		if agent["reservation"] != "":
			agent["state"] = "CROSSING"
		else:
			agent["state"] = decision["state"]
		var pose: Dictionary = _pose(agent)
		var future_pose: Dictionary = graph.sample(agent["lane_id"], minf(graph.lanes[agent["lane_id"]]["length_m"], agent["s"] + 9.0))
		var turn: float = pose["tangent"].cross(future_pose["tangent"]).y
		commands[agent["id"]] = {
			"target_speed_mps": desired, "throttle": clampf((agent["speed"] - previous_speed) / (dt * ACCEL_MPS2), 0.0, 1.0),
			"brake": clampf((previous_speed - agent["speed"]) / (dt * BRAKE_MPS2), 0.0, 1.0),
			"steer": clampf(turn * 1.75, -1.0, 1.0), "state": agent["state"],
			"position": pose["position"], "forward": pose["tangent"],
		}
	for i in range(agents.size() - 1, -1, -1):
		if agents[i].get("ended", false):
			_recycle_at(i)


func _decide(agent: Dictionary, obstacles: Array, reserved: Dictionary) -> Dictionary:
	var lane: Dictionary = graph.lanes[agent["lane_id"]]
	var free_target: float = minf(lane["speed_limit_mps"] * agent["cruise"], graph.corner_speed_mps(agent["lane_id"], agent["s"]))
	# Look at the next lane as well; slow before turning, not only after entering.
	if agent["next_lane"] != "" and lane["length_m"] - agent["s"] < 20.0:
		free_target = minf(free_target, graph.corner_speed_mps(agent["next_lane"], 0.0) + 1.0)
	var target := free_target
	var emergency := false
	var state := "FOLLOW_LANE"
	var gap := INF
	var lead_speed := 0.0
	for other in agents:
		if agent["id"] == other["id"]:
			continue
		var distance_ahead := INF
		if other["lane_id"] == agent["lane_id"] and other["s"] > agent["s"]:
			distance_ahead = other["s"] - agent["s"]
		elif agent["next_lane"] != "" and other["lane_id"] == agent["next_lane"] and agent["bridge_len"] <= 0.0:
			distance_ahead = lane["length_m"] - agent["s"] + other["s"]
		if distance_ahead < INF:
			var clearance: float = distance_ahead - (agent["length"] + other["length"]) * 0.5
			if clearance < gap:
				gap = clearance
				lead_speed = other["speed"]
	if gap < INF:
		var desired_gap: float = STANDSTILL_GAP_M + agent["speed"] * HEADWAY_S
		if gap < desired_gap + 18.0:
			target = minf(target, maxf(0.0, lead_speed + (gap - desired_gap) * 0.7))
			state = "FOLLOWING"
			if gap < STANDSTILL_GAP_M + 1.0:
				emergency = true
	# Separate approaches to the same downstream lane yield by deterministic priority.
	if agent["next_lane"] != "" and lane["length_m"] - agent["s"] < 18.0:
		for other in agents:
			if other["id"] >= agent["id"] or other["lane_id"] == agent["lane_id"] or other["lane_id"] == agent["next_lane"]:
				continue
			if other["next_lane"] == agent["next_lane"]:
				var other_remaining: float = graph.lanes[other["lane_id"]]["length_m"] - other["s"]
				if other_remaining < 13.0 and other_remaining < lane["length_m"] - agent["s"] + 7.0:
					target = minf(target, sqrt(2.0 * BRAKE_MPS2 * maxf(0.0, lane["length_m"] - agent["s"] - 4.0)))
					state = "YIELD_AT_MERGE"
	# Obstacle is an external collider bound: {position: Vector3, radius: float}.
	for obstacle in obstacles:
		if typeof(obstacle) != TYPE_DICTIONARY or typeof(obstacle.get("position")) != TYPE_VECTOR3:
			continue
		var along_and_lateral: Vector2 = _project_on_lane(agent["lane_id"], obstacle["position"])
		var ahead: float = along_and_lateral.x - agent["s"] - agent["length"] * 0.5 - float(obstacle.get("radius", 1.0))
		if along_and_lateral.y <= lane["width_m"] * 0.6 + float(obstacle.get("radius", 1.0)) and ahead > -2.0 and ahead < 35.0:
			var safe_space := maxf(0.0, ahead - STANDSTILL_GAP_M)
			target = minf(target, sqrt(2.0 * BRAKE_MPS2 * safe_space))
			state = "BRAKE_FOR_OBSTACLE"
			if ahead < 5.0:
				emergency = true
	var must_stop := false
	var stop_s: float = lane["length_m"]
	var wants_lock := false
	var junction := ""
	var approaches: Dictionary = controls.get("approaches", {})
	if approaches.has(agent["lane_id"]) and agent["reservation"] == "" and agent["bridge_len"] <= 0.0:
		var rule: Dictionary = approaches[agent["lane_id"]]
		junction = rule["junction_id"]
		stop_s = maxf(0.0, lane["length_m"] - float(rule.get("stop_distance_m", 4.0)))
		var stop_distance: float = stop_s - agent["s"]
		var permitted := not reserved.has(junction)
		if rule["mode"] == "signal":
			permitted = permitted and _green(junction, rule["group"])
		if rule["mode"] == "stop":
			permitted = permitted and agent["dwell"] >= float(rule.get("dwell_s", 1.0))
		if permitted and stop_distance <= 1.5:
			wants_lock = true
		elif stop_distance < 40.0:
			must_stop = true
			target = minf(target, sqrt(2.0 * BRAKE_MPS2 * maxf(0.0, stop_distance - 0.6)))
			state = "WAIT_AT_JUNCTION"
	return {"target": target, "free_target": free_target, "must_stop": must_stop, "stop_s": stop_s,
		"emergency": emergency, "state": state, "request_reservation": wants_lock, "junction": junction}


func _green(junction_id: String, group: String) -> bool:
	var signal: Dictionary = controls.get("signals", {}).get(junction_id, {})
	var phases: Array = signal.get("phases", [])
	var period := 0.0
	for phase in phases:
		period += float(phase["duration_s"])
	if period <= 0.0:
		return false
	var point := fposmod(simulation_time_s, period)
	var elapsed := 0.0
	var all_red: float = float(signal.get("all_red_s", 1.0))
	for phase in phases:
		var duration: float = float(phase["duration_s"])
		if point < elapsed + duration:
			return phase["group"] == group and point - elapsed < duration - all_red
		elapsed += duration
	return false


func _advance(agent: Dictionary, distance_m: float) -> void:
	var left := distance_m
	for _iteration in range(6):
		if agent["bridge_len"] > 0.0:
			var bridge_remaining: float = agent["bridge_len"] - agent["bridge_s"]
			var moved := minf(left, bridge_remaining)
			agent["bridge_s"] += moved
			left -= moved
			if agent["bridge_s"] < agent["bridge_len"] - 0.00001:
				return
			agent["bridge_len"] = 0.0
			agent["bridge_s"] = 0.0
			_complete_transition(agent)
			if left <= 0.00001:
				return
		var lane: Dictionary = graph.lanes[agent["lane_id"]]
		var lane_remaining: float = lane["length_m"] - agent["s"]
		if left < lane_remaining - 0.00001:
			agent["s"] += left
			return
		agent["s"] = lane["length_m"]
		left = maxf(0.0, left - lane_remaining)
		if agent["next_lane"] == "":
			agent["ended"] = true
			return
		var src_end: Vector3 = lane["points"].back()
		var next_start: Vector3 = graph.lanes[agent["next_lane"]]["points"].front()
		var gap := src_end.distance_to(next_start)
		if gap > 0.0001:
			agent["bridge_len"] = gap
			agent["bridge_s"] = 0.0
			if left <= 0.00001:
				return
		else:
			_complete_transition(agent)
			if left <= 0.00001:
				return
	# Cap pathological high-delta traversals on tiny lanes; regular ticks never reach here.


func _complete_transition(agent: Dictionary) -> void:
	var new_lane: String = agent["next_lane"]
	agent["lane_id"] = new_lane
	agent["s"] = 0.0
	agent["dwell"] = 0.0
	var route: Array = agent["route"]
	if not route.is_empty() and agent["route_index"] + 1 < route.size() and route[agent["route_index"] + 1] == new_lane:
		agent["route_index"] += 1
	_select_next(agent)


func _select_next(agent: Dictionary) -> void:
	var exits: Array = graph.lanes[agent["lane_id"]]["next_lane_ids"]
	var route: Array = agent["route"]
	if not route.is_empty() and agent["route_index"] + 1 < route.size():
		var desired: String = route[agent["route_index"] + 1]
		if exits.has(desired):
			agent["next_lane"] = desired
			return
	agent["next_lane"] = exits[rng.randi_range(0, exits.size() - 1)] if not exits.is_empty() else ""


func _pose(agent: Dictionary) -> Dictionary:
	var from_pose: Dictionary = graph.sample(agent["lane_id"], agent["s"])
	if agent["bridge_len"] > 0.0 and agent["next_lane"] != "":
		var next_pose: Dictionary = graph.sample(agent["next_lane"], 0.0)
		var across: Vector3 = next_pose["position"] - from_pose["position"]
		return {"position": from_pose["position"].lerp(next_pose["position"], clampf(agent["bridge_s"] / agent["bridge_len"], 0.0, 1.0)),
			"tangent": across.normalized() if across.length() > 0.0001 else next_pose["tangent"]}
	return from_pose


func _spawn_space_clear(position: Vector3, car_length_m: float) -> bool:
	for other in agents:
		if _flat_distance(position, _pose(other)["position"]) < (car_length_m + other["length"]) * 0.5 + STANDSTILL_GAP_M + 1.0:
			return false
	return true


func _project_on_lane(lane_id: String, position: Vector3) -> Vector2:
	var lane: Dictionary = graph.lanes[lane_id]
	var points: Array = lane["points"]
	var cumulative: PackedFloat32Array = lane["cumulative"]
	var closest_d2 := INF
	var best := Vector2(-1.0, INF)
	for i in range(points.size() - 1):
		var a := Vector2(points[i].x, points[i].z)
		var b := Vector2(points[i + 1].x, points[i + 1].z)
		var p := Vector2(position.x, position.z)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(0.0001, ab.length_squared()), 0.0, 1.0)
		var nearest := a + ab * t
		var d2 := p.distance_squared_to(nearest)
		if d2 < closest_d2:
			closest_d2 = d2
			best = Vector2(lerpf(cumulative[i], cumulative[i + 1], t), sqrt(d2))
	return best


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _recycle_at(index: int) -> void:
	var agent: Dictionary = agents[index]
	commands.erase(agent["id"])
	pool.append(agent)
	agents.remove_at(index)
	total_recycled += 1
