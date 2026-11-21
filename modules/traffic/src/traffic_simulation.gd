extends RefCounted
## Deterministic, lightweight civilian traffic; no physics bodies or scene-tree ownership.
## Fixed-step kinematic states may drive placeholder visuals or a future vehicle adapter.

const RoadGraph = preload("road_graph.gd")
const MAX_AGENTS := 20
const FIXED_STEP := 1.0 / 30.0
const ACCEL_MPS2 := 2.1
const BRAKE_MPS2 := 4.8
const EMERGENCY_BRAKE_MPS2 := 7.0
const FOLLOW_TIME_S := 1.4
const MIN_GAP_M := 5.5
const SPAWN_GAP_M := 12.0
const PLAYER_SPAWN_GAP_M := 24.0
const STOP_OFFSET_M := 2.5
const APPROACH_M := 16.0
const DESPAWN_RADIUS_M := 230.0
const SPAWN_RADIUS_M := 175.0

var graph = RoadGraph.new()
var graph_valid := false
var agents: Dictionary = {}
var pool: Array[Dictionary] = []
var next_agent_id := 1
var tick := 0
var elapsed_s := 0.0
var density_target := 12
var spawn_period_s := 1.0
var _spawn_clock := 0.0
var _accumulator := 0.0
var _rng := RandomNumberGenerator.new()
var _seed := 1
var player_position := Vector3.ZERO
var player_radius_m := 2.0
var player_enabled := false
var viewer_position := Vector3.ZERO
var junctions: Dictionary = {}
var inbound_junction: Dictionary = {}
var reservations: Dictionary = {}
var reused_agents := 0
var total_spawned := 0
var total_despawned := 0
var _obstacles: Array = []


func load_road_graph(data: Dictionary) -> bool:
	clear()
	junctions.clear()
	inbound_junction.clear()
	reservations.clear()
	graph_valid = graph.load_road_graph(data)
	if not graph_valid:
		return false
	# A merge needs exclusive ownership at its successor's entry even without
	# explicit junction authoring (no additional fields in the shared graph).
	var incoming: Dictionary = {}
	for lid in graph.lane_order:
		for nid in graph.lanes[lid]["next_lane_ids"]:
			if not incoming.has(nid):
				incoming[nid] = []
			incoming[nid].append(lid)
	for nid in incoming:
		if incoming[nid].size() < 2:
			continue
		var jid: String = "merge:%s" % nid
		junctions[jid] = {"id": jid, "inbound": incoming[nid], "clearance_m": 12.0,
			"mode": "yield", "period_s": 0.0, "green_s": 0.0, "phase_s": 0.0, "stop_s": 0.0}
		for lid in incoming[nid]:
			inbound_junction[lid] = jid
	return true


func configure_junctions(definitions: Array) -> bool:
	# An explicit junction overrides implicit merge controls for listed lanes.
	for raw in definitions:
		if not (raw is Dictionary) or not (raw.get("id") is String) or not (raw.get("incoming_lane_ids") is Array):
			return false
		var jid: String = raw["id"]
		var incoming: Array = raw["incoming_lane_ids"]
		if incoming.is_empty() or junctions.has(jid):
			return false
		var mode: String = raw.get("mode", "yield")
		if not ["yield", "stop", "signal"].has(mode):
			return false
		var period: float = float(raw.get("period_s", 16.0))
		var green: float = float(raw.get("green_s", 8.0))
		if mode == "signal" and (period <= 0.0 or green <= 0.0 or green > period):
			return false
		for lid in incoming:
			if not graph.lanes.has(lid):
				return false
		var j := {"id": jid, "inbound": incoming.duplicate(),
			"clearance_m": maxf(4.0, float(raw.get("clearance_m", 20.0))),
			"mode": mode, "period_s": period, "green_s": green,
			"phase_s": float(raw.get("phase_s", 0.0)),
			"stop_s": maxf(0.0, float(raw.get("stop_s", 0.9)))}
		junctions[jid] = j
		for lid in incoming:
			inbound_junction[lid] = jid
	return true


func reset(seed_value: int = 1) -> void:
	clear()
	_seed = seed_value
	_rng.seed = seed_value


func clear() -> void:
	for id in agents.keys():
		pool.append(agents[id])
	agents.clear()
	reservations.clear()
	next_agent_id = 1
	tick = 0
	elapsed_s = 0.0
	_spawn_clock = 0.0
	_accumulator = 0.0
	reused_agents = 0
	total_spawned = 0
	total_despawned = 0


func set_density(count: int) -> void:
	density_target = clampi(count, 0, MAX_AGENTS)


func set_player_state(position: Vector3, radius_m: float = 2.0, enabled: bool = true) -> void:
	player_position = position
	player_radius_m = maxf(0.0, radius_m)
	player_enabled = enabled


func spawn_agent(lane_id: String, s: float, initial_speed_mps: float = 0.0, speed_factor: float = -1.0) -> int:
	if not graph_valid or not graph.lanes.has(lane_id) or s < 0.0 or s >= graph.lane_length(lane_id) - 0.1:
		return -1
	if agents.size() >= MAX_AGENTS:
		return -1
	var pose: Dictionary = graph.get_pose(lane_id, s)
	var pos: Vector3 = pose["position"]
	if player_enabled and pos.distance_to(player_position) < PLAYER_SPAWN_GAP_M + player_radius_m:
		return -1
	# Do not materialize cars inside a reserved intersection/merge conflict zone.
	# This is checked only at spawn time, not during simulation ticks.
	for jid in junctions:
		var junction: Dictionary = junctions[jid]
		if s >= junction["clearance_m"] + 2.0:
			continue
		for incoming_lane in junction["inbound"]:
			if graph.lanes[incoming_lane]["next_lane_ids"].has(lane_id):
				return -1
	for id in agents:
		if pos.distance_to(agents[id]["position"]) < SPAWN_GAP_M:
			return -1
	var agent: Dictionary = {}
	if not pool.is_empty():
		agent = pool.pop_back()
		agent.clear()
		reused_agents += 1
	var id := next_agent_id
	next_agent_id += 1
	var multiplier: float = speed_factor if speed_factor > 0.0 else _rng.randf_range(0.75, 1.08)
	var options: Array = graph.lanes[lane_id]["next_lane_ids"]
	var next_lane: String = _choose_next(options)
	var vehicle_type: int = _rng.randi_range(0, 2)
	agent.assign({"id": id, "lane_id": lane_id, "s": s,
		"next_lane": next_lane, "route_locked": false, "route_queue": [], "speed_mps": maxf(0.0, initial_speed_mps),
		"target_speed_mps": 0.0, "speed_factor": multiplier, "vehicle_type": vehicle_type,
		"position": pos, "tangent": pose["tangent"], "state": "FOLLOW_LANE",
		"wait_s": 0.0, "stop_done": false, "reserved_junction": "",
		"entered_lane": "", "clearance_m": 0.0,
		"last_acceleration_mps2": 0.0, "dead_end_seconds": 0.0})
	agents[id] = agent
	total_spawned += 1
	return id


func assign_route(id: int, route: Array[String]) -> bool:
	if not agents.has(id) or route.is_empty() or route[0] != agents[id]["lane_id"]:
		return false
	for i in range(route.size() - 1):
		if not graph.lanes.has(route[i]) or not graph.lanes[route[i]]["next_lane_ids"].has(route[i + 1]):
			return false
	var a: Dictionary = agents[id]
	a["route_queue"] = route.slice(1)
	a["route_locked"] = true
	a["next_lane"] = a["route_queue"].pop_front() if not a["route_queue"].is_empty() else ""
	return true


func route_agent_to(id: int, destination_lane_id: String) -> bool:
	if not agents.has(id):
		return false
	var route: Array[String] = graph.find_route(agents[id]["lane_id"], destination_lane_id)
	return assign_route(id, route)


func despawn_agent(id: int) -> void:
	if not agents.has(id):
		return
	var a: Dictionary = agents[id]
	if a["reserved_junction"] != "":
		var jid: String = a["reserved_junction"]
		if reservations.get(jid, -1) == id:
			reservations.erase(jid)
	agents.erase(id)
	a.clear()
	pool.append(a)
	total_despawned += 1


func spawn_near(position: Vector3, attempts: int = 36) -> int:
	if not graph_valid or graph.lane_order.is_empty():
		return -1
	for _i in range(attempts):
		var lid: String = graph.lane_order[_rng.randi_range(0, graph.lane_order.size() - 1)]
		var length_m: float = graph.lane_length(lid)
		if length_m < 15.0:
			continue
		var s: float = _rng.randf_range(0.1, 0.85) * length_m
		var pos: Vector3 = graph.get_pose(lid, s)["position"]
		if pos.distance_to(position) > SPAWN_RADIUS_M or pos.distance_to(position) < PLAYER_SPAWN_GAP_M:
			continue
		var id: int = spawn_agent(lid, s, 0.0)
		if id != -1:
			return id
	return -1


func step(delta: float, view_position: Vector3, obstacles: Array = []) -> void:
	# Fixed internal 30 Hz state: reproducible across render-frame partitions.
	viewer_position = view_position
	_obstacles = obstacles
	_accumulator += clampf(delta, 0.0, 0.25)
	var loops := 0
	while _accumulator + 0.0000001 >= FIXED_STEP and loops < 8:
		_fixed_step(FIXED_STEP)
		_accumulator -= FIXED_STEP
		loops += 1


func _fixed_step(dt: float) -> void:
	tick += 1
	elapsed_s += dt
	var ids: Array = agents.keys()
	ids.sort()
	# Sample leading vehicles from pre-tick states; order cannot give an advantage.
	var commands: Dictionary = {}
	for id in ids:
		commands[id] = _calculate_command(agents[id], dt)
	for id in ids:
		if not agents.has(id):
			continue
		_integrate(agents[id], commands[id], dt)
	for id in ids:
		if agents.has(id) and (agents[id]["position"].distance_to(viewer_position) > DESPAWN_RADIUS_M or agents[id]["dead_end_seconds"] > 6.0):
			despawn_agent(id)
	_spawn_clock += dt
	if _spawn_clock >= spawn_period_s:
		_spawn_clock -= spawn_period_s
		while agents.size() > density_target:
			var remove_ids: Array = agents.keys()
			remove_ids.sort()
			despawn_agent(remove_ids.back())
		var failures := 0
		while agents.size() < density_target and failures < 3:
			if spawn_near(viewer_position) == -1:
				failures += 1


func _calculate_command(a: Dictionary, dt: float) -> Dictionary:
	var lid: String = a["lane_id"]
	var lane: Dictionary = graph.lanes[lid]
	var remaining: float = lane["length"] - a["s"]
	var desired: float = minf(lane["speed_limit_mps"] * a["speed_factor"],
		graph.curve_speed_mps(lid, a["s"]) * a["speed_factor"])
	var mode := "FOLLOW_LANE"
	if a["next_lane"] == "":
		desired = minf(desired, sqrt(2.0 * BRAKE_MPS2 * maxf(remaining - 0.5, 0.0)))
	# Followers anticipate current lane leaders and immediately connected lanes.
	var leader: Dictionary = _find_leader(a)
	if not leader.is_empty():
		var gap: float = leader["gap"]
		var leader_speed: float = leader["speed"]
		var desired_gap: float = MIN_GAP_M + a["speed_mps"] * FOLLOW_TIME_S
		desired = minf(desired, maxf(0.0, leader_speed + (gap - desired_gap) * 0.65))
		if gap < desired_gap:
			mode = "BRAKE_FOR_OBSTACLE"
	# Obstacles are caller-provided simplified circles; the player uses the same contract.
	var pose: Dictionary = graph.get_pose(lid, a["s"])
	var obstacle_gap: float = _obstacle_gap(a, pose)
	if obstacle_gap < INF:
		desired = minf(desired, sqrt(2.0 * BRAKE_MPS2 * maxf(obstacle_gap - MIN_GAP_M, 0.0)))
		mode = "BRAKE_FOR_OBSTACLE"
	var junction_id: String = inbound_junction.get(lid, "")
	if junction_id != "" and a["next_lane"] != "" and remaining < APPROACH_M and a["reserved_junction"] == "":
		var j: Dictionary = junctions[junction_id]
		var blocked := _junction_blocked(a, junction_id, j)
		if blocked:
			desired = minf(desired, sqrt(2.0 * BRAKE_MPS2 * maxf(remaining - STOP_OFFSET_M, 0.0)))
			mode = "WAIT_AT_JUNCTION"
		elif remaining < 3.4:
			# Reservation is granted in ID order and retained through the crossing.
			reservations[junction_id] = a["id"]
			a["reserved_junction"] = junction_id
			a["entered_lane"] = a["next_lane"]
			a["clearance_m"] = j["clearance_m"]
	if a["reserved_junction"] != "":
		mode = "FOLLOW_LANE"
	# Force stopping at the stop line without crossing it if another car owns it.
	if mode == "WAIT_AT_JUNCTION" and remaining <= STOP_OFFSET_M + 0.15:
		desired = 0.0
	return {"desired": maxf(0.0, desired), "mode": mode, "leader": leader,
		"obstacle_gap": obstacle_gap}


func _junction_blocked(a: Dictionary, junction_id: String, j: Dictionary) -> bool:
	if reservations.has(junction_id) and reservations[junction_id] != a["id"]:
		return true
	var mode: String = j["mode"]
	if mode == "signal":
		var phase: float = fposmod(elapsed_s + j["phase_s"], j["period_s"])
		if phase >= j["green_s"]:
			return true
	if mode == "stop" and not a["stop_done"]:
		# Stop signs require full stop and a finite dwell, no instantaneous rolling stop.
		if graph.lane_length(a["lane_id"]) - a["s"] < 3.4 and a["speed_mps"] < 0.45:
			a["wait_s"] += FIXED_STEP
			if a["wait_s"] >= j["stop_s"]:
				a["stop_done"] = true
		return not a["stop_done"]
	return false


func _find_leader(a: Dictionary) -> Dictionary:
	var gap := INF
	var speed := 0.0
	var lane: Dictionary = graph.lanes[a["lane_id"]]
	for id in agents:
		if id == a["id"]:
			continue
		var other: Dictionary = agents[id]
		var distance := INF
		if other["lane_id"] == a["lane_id"] and other["s"] > a["s"]:
			distance = other["s"] - a["s"]
		elif a["next_lane"] != "" and other["lane_id"] == a["next_lane"]:
			distance = lane["length"] - a["s"] + other["s"]
		if distance < gap:
			gap = distance
			speed = other["speed_mps"]
	if gap < 80.0:
		return {"gap": gap, "speed": speed}
	return {}


func _obstacle_gap(a: Dictionary, pose: Dictionary) -> float:
	var best := INF
	var direction: Vector3 = pose["tangent"]
	var p: Vector3 = pose["position"]
	var obstacles: Array = _obstacles
	if player_enabled:
		obstacles = obstacles + [{"position": player_position, "radius_m": player_radius_m}]
	for item in obstacles:
		if not (item is Dictionary) or not (item.get("position") is Vector3):
			continue
		var offset: Vector3 = item["position"] - p
		var along: float = offset.dot(direction)
		if along < -2.0 or along > 65.0:
			continue
		var lateral: float = (offset - along * direction).length()
		var radius: float = maxf(0.0, float(item.get("radius_m", 1.8)))
		if lateral < graph.lanes[a["lane_id"]]["width_m"] * 0.5 + radius:
			best = minf(best, maxf(0.0, along - radius))
	return best


func _integrate(a: Dictionary, command: Dictionary, dt: float) -> void:
	var speed: float = a["speed_mps"]
	var desired: float = command["desired"]
	var acceleration := clampf((desired - speed) / dt, -BRAKE_MPS2, ACCEL_MPS2)
	var next_speed: float = maxf(0.0, speed + acceleration * dt)
	var distance: float = (speed + next_speed) * 0.5 * dt
	var leader: Dictionary = command["leader"]
	if not leader.is_empty():
		# Swept bumper clearance: no discrete-timestep leap into an NPC leader.
		distance = minf(distance, maxf(0.0, leader["gap"] - MIN_GAP_M))
	if command["obstacle_gap"] < INF:
		distance = minf(distance, maxf(0.0, command["obstacle_gap"] - MIN_GAP_M))
	if command["mode"] == "WAIT_AT_JUNCTION":
		distance = minf(distance, maxf(0.0, graph.lane_length(a["lane_id"]) - a["s"] - STOP_OFFSET_M))
	if distance <= 0.0001 and speed > 0.01:
		next_speed = maxf(0.0, speed - EMERGENCY_BRAKE_MPS2 * dt)
	a["last_acceleration_mps2"] = (next_speed - speed) / dt
	a["speed_mps"] = next_speed
	a["target_speed_mps"] = desired
	a["state"] = command["mode"]
	a["s"] += distance
	var transitions := 0
	while a["s"] >= graph.lane_length(a["lane_id"]) - 0.00001 and transitions < 2:
		var old_length: float = graph.lane_length(a["lane_id"])
		var next_lane: String = a["next_lane"]
		if next_lane == "":
			a["s"] = maxf(0.0, old_length - 0.01)
			a["speed_mps"] = 0.0
			a["state"] = "DEAD_END"
			break
		var previous_end: Vector3 = graph.get_pose(a["lane_id"], old_length)["position"]
		var next_start: Vector3 = graph.get_pose(next_lane, 0.0)["position"]
		# Validation already constrains this; no discontinuous teleport allowed.
		if previous_end.distance_to(next_start) > RoadGraph.MAX_CONNECTION_GAP_M:
			a["s"] = maxf(0.0, old_length - 0.01)
			a["speed_mps"] = 0.0
			a["state"] = "INVALID_CONNECTION"
			break
		a["s"] = maxf(0.0, a["s"] - old_length)
		a["lane_id"] = next_lane
		if a["route_locked"]:
			a["next_lane"] = a["route_queue"].pop_front() if not a["route_queue"].is_empty() else ""
		else:
			a["next_lane"] = _choose_next(graph.lanes[next_lane]["next_lane_ids"])
		a["stop_done"] = false
		a["wait_s"] = 0.0
		transitions += 1
	if a["reserved_junction"] != "" and a["lane_id"] == a["entered_lane"] and a["s"] >= a["clearance_m"]:
		var jid: String = a["reserved_junction"]
		if reservations.get(jid, -1) == a["id"]:
			reservations.erase(jid)
		a["reserved_junction"] = ""
		a["entered_lane"] = ""
	var pose: Dictionary = graph.get_pose(a["lane_id"], a["s"])
	a["position"] = pose["position"]
	a["tangent"] = pose["tangent"]
	if a["next_lane"] == "" and graph.lane_length(a["lane_id"]) - a["s"] < 0.95 and a["speed_mps"] < 0.45:
		a["state"] = "DEAD_END"
		a["dead_end_seconds"] += dt
	else:
		a["dead_end_seconds"] = 0.0


func _choose_next(options: Array) -> String:
	if options.is_empty():
		return ""
	# Keep authored next_lane_ids order; seed provides reproducible junction choice.
	return str(options[_rng.randi_range(0, options.size() - 1)])


func get_state(id: int) -> Dictionary:
	if not agents.has(id):
		return {}
	return agents[id].duplicate(true)


func get_states() -> Array:
	var ids: Array = agents.keys()
	ids.sort()
	var result: Array = []
	for id in ids:
		result.append(get_state(id))
	return result


func get_control_output(id: int) -> Dictionary:
	# For future rigid-body adapters. apply steering/throttle in the vehicle layer;
	# the kinematic simulation's position is not simultaneously applied to that body.
	if not agents.has(id):
		return {}
	var a: Dictionary = agents[id]
	var ahead: Dictionary = graph.get_pose(a["lane_id"], a["s"] + 9.0)
	var delta_speed: float = a["target_speed_mps"] - a["speed_mps"]
	return {"lookahead_position": ahead["position"], "forward": a["tangent"],
		"target_speed_mps": a["target_speed_mps"],
		"throttle": clampf(delta_speed * 0.4, 0.0, 1.0),
		"brake": clampf(-delta_speed * 0.3, 0.0, 1.0),
		"handbrake": false, "traffic_state": a["state"]}


func get_stats() -> Dictionary:
	return {"active": agents.size(), "pooled": pool.size(), "reused": reused_agents,
		"spawned": total_spawned, "despawned": total_despawned,
		"tick": tick, "seconds": elapsed_s}
