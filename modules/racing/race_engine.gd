extends RefCounted
## Standalone race state machine. Caller owns movement, collisions, UI, input and spawns.
## Order each physics frame: update_racer_state(...) for every car, then tick(delta).
signal state_changed(old_state: int, new_state: int)
signal checkpoint_passed(racer_id: String, checkpoint_id: String, lap: int)
signal lap_completed(racer_id: String, completed_lap: int)
signal racer_finished(racer_id: String, finish_time: float)
signal invalid_progress(racer_id: String, reason: String)

const RaceRoute = preload("race_route.gd")
enum State {IDLE, GRID, COUNTDOWN, RACING, FINISHED, RESULTS, ABORTED, FREE_ROAM}

var state: int = State.IDLE
var paused: bool = false
var road_graph: Dictionary = {}
var event: Dictionary = {}
var route: RefCounted
var checkpoints: Array[Dictionary] = []
var racers: Dictionary = {}
var elapsed_seconds: float = 0.0
var grid_remaining: float = 0.0
var countdown_remaining: float = 0.0
var first_finish_time: float = -1.0
var last_error: String = ""

const DEFAULT_MAX_SPEED_MPS := 90.0
const DEFAULT_CORRIDOR_M := 14.0
const FINISH_TOLERANCE_M := 2.5

func _fail(error: String) -> bool:
	last_error = error
	return false

func _set_state(next: int) -> void:
	if state == next:
		return
	var prior := state
	state = next
	state_changed.emit(prior, state)

func load_road_graph(graph: Dictionary) -> bool:
	if state != State.IDLE and state != State.FREE_ROAM:
		return _fail("Cannot replace road graph during an event")
	var problem: String = RaceRoute.validate_road_graph(graph)
	if not problem.is_empty():
		return _fail(problem)
	road_graph = graph.duplicate(true)
	last_error = ""
	return true

func register_racer(id: String, is_player: bool = false) -> bool:
	if id.is_empty() or racers.has(id):
		return _fail("Racer ID is empty or already registered")
	if state != State.IDLE and state != State.FREE_ROAM:
		return _fail("Register racers before starting the event")
	racers[id] = {"id": id, "is_player": is_player}
	return true

func unregister_all_racers() -> void:
	if state == State.IDLE or state == State.FREE_ROAM:
		racers.clear()

func start_event(definition: Dictionary) -> bool:
	if state != State.IDLE and state != State.FREE_ROAM:
		return _fail("Exit the previous event before starting another")
	if road_graph.is_empty() or racers.is_empty():
		return _fail("Load road graph and register racers first")
	if definition.get("schema_version", 1) != 1:
		return _fail("Unsupported event schema")
	if not (definition.get("id") is String) or str(definition["id"]).is_empty():
		return _fail("Missing event ID")
	var kind: String = str(definition.get("kind", ""))
	if kind != "sprint" and kind != "circuit":
		return _fail("Event kind must be sprint or circuit")
	var raw_laps: Variant = definition.get("laps")
	if typeof(raw_laps) != TYPE_INT or int(raw_laps) < 1 or (kind == "sprint" and int(raw_laps) != 1):
		return _fail("Sprint requires one lap; circuit requires positive integer laps")
	if not (definition.get("lane_route") is Array):
		return _fail("Missing lane_route")
	var candidate = RaceRoute.new()
	var problem: String = candidate.configure(road_graph, definition["lane_route"], kind == "circuit")
	if not problem.is_empty():
		return _fail(problem)
	if candidate.length_m < 40.0:
		return _fail("Race route must be at least 40 meters")
	var start: Variant = definition.get("start_position")
	if not RaceRoute.valid_point(start):
		return _fail("Invalid start_position")
	if RaceRoute.point3(start).distance_to(candidate.sample(0.0)) > 12.0:
		return _fail("Start position must be near route start")
	var raw_checkpoints: Variant = definition.get("checkpoints")
	if not (raw_checkpoints is Array) or raw_checkpoints.is_empty():
		return _fail("Race requires ordered checkpoints")
	var prepared: Array[Dictionary] = []
	var seen := {}
	var prev_s := 0.0
	for item in raw_checkpoints:
		if not (item is Dictionary) or not (item.get("id") is String) or str(item["id"]).is_empty() or seen.has(item["id"]):
			return _fail("Invalid or repeated checkpoint ID")
		if not RaceRoute.valid_point(item.get("center")):
			return _fail("Invalid checkpoint center")
		if not RaceRoute._number(item.get("radius_m")) or float(item["radius_m"]) < 2.0 or float(item["radius_m"]) > 30.0:
			return _fail("Checkpoint radius must be between 2 and 30 meters")
		var center := RaceRoute.point3(item["center"])
		var projected: Dictionary = candidate.project(center)
		var arc: float = projected["s"]
		if projected["distance_m"] > float(item["radius_m"]) or arc <= prev_s + 4.0 or arc >= candidate.length_m - 4.0:
			return _fail("Checkpoints must be on route, increasing and outside the finish gate")
		prepared.append({"id": item["id"], "center": center, "radius_m": float(item["radius_m"]), "s": arc})
		prev_s = arc
		seen[item["id"]] = true
	for optional in ["grid_seconds", "countdown_seconds", "finish_grace_seconds", "max_race_seconds", "max_speed_mps", "corridor_m", "collision_reset_speed_mps"]:
		if definition.has(optional) and (not RaceRoute._number(definition[optional]) or float(definition[optional]) < 0.0):
			return _fail("Invalid event parameter: " + optional)
	route = candidate
	event = definition.duplicate(true)
	checkpoints = prepared
	_restart_racers()
	last_error = ""
	_set_state(State.GRID)
	return true

func _restart_racers() -> void:
	elapsed_seconds = 0.0
	first_finish_time = -1.0
	paused = false
	grid_remaining = float(event.get("grid_seconds", 1.0))
	countdown_remaining = float(event.get("countdown_seconds", 3.0))
	for id in racers.keys():
		var is_player: bool = racers[id].get("is_player", false)
		var start: Vector3 = route.sample(0.0)
		racers[id] = {
			"id": id, "is_player": is_player,
			"position": start, "pending_position": start, "velocity": Vector3.ZERO,
			"route_s": 0.0, "continuous_s": 0.0, "progress_m": 0.0,
			"lap": 1, "checkpoint_index": 0, "invalid_laps": 0,
			"needs_reset": false, "last_invalid_reason": "", "wrong_way": false,
			"finished": false, "finish_time": INF
		}

func restart_event() -> bool:
	if event.is_empty() or state == State.IDLE or state == State.FREE_ROAM:
		return _fail("No event to restart")
	_restart_racers()
	_set_state(State.GRID)
	return true

func update_racer_state(id: String, position: Vector3, velocity: Vector3) -> bool:
	if not racers.has(id):
		return _fail("Unknown racer: " + id)
	if not (state in [State.GRID, State.COUNTDOWN, State.RACING]):
		return false
	var r: Dictionary = racers[id]
	r["pending_position"] = position
	r["velocity"] = velocity
	return true

func pause() -> bool:
	if not (state in [State.GRID, State.COUNTDOWN, State.RACING]):
		return false
	paused = true
	return true

func resume() -> void:
	paused = false

func tick(delta: float) -> void:
	if delta < 0.0 or not is_finite(delta) or paused:
		return
	var remaining := delta
	if state == State.GRID:
		var used := minf(remaining, grid_remaining)
		grid_remaining -= used
		remaining -= used
		if grid_remaining <= 0.000001:
			_set_state(State.COUNTDOWN)
	if state == State.COUNTDOWN:
		var used := minf(remaining, countdown_remaining)
		countdown_remaining -= used
		remaining -= used
		if countdown_remaining <= 0.000001:
			_set_state(State.RACING)
	if state != State.RACING or remaining <= 0.0:
		return
	var before := elapsed_seconds
	elapsed_seconds += remaining
	var ids := racers.keys()
	ids.sort()
	for id in ids:
		_advance_racer(id, remaining, before)
	var all_finished := true
	for id in ids:
		if not racers[id]["finished"]:
			all_finished = false
			break
	if all_finished or (first_finish_time >= 0.0 and elapsed_seconds - first_finish_time >= float(event.get("finish_grace_seconds", 15.0))) or elapsed_seconds >= float(event.get("max_race_seconds", 1200.0)):
		_set_state(State.FINISHED)

func _invalidate(id: String, reason: String) -> void:
	var r: Dictionary = racers[id]
	if r["needs_reset"]:
		return
	r["needs_reset"] = true
	r["last_invalid_reason"] = reason
	r["invalid_laps"] = int(r["invalid_laps"]) + 1
	invalid_progress.emit(id, reason)

static func _segment_distance_xz(a: Vector3, b: Vector3, center: Vector3) -> float:
	var u := Vector2(a.x, a.z)
	var v := Vector2(b.x, b.z)
	var p := Vector2(center.x, center.z)
	var d := v - u
	if d.length_squared() < 0.000001:
		return u.distance_to(p)
	var t := clampf((p - u).dot(d) / d.length_squared(), 0.0, 1.0)
	return (u + d * t).distance_to(p)

func _hits_gate(a: Vector3, b: Vector3, cp: Dictionary) -> bool:
	return _segment_distance_xz(a, b, cp["center"]) <= float(cp["radius_m"])

func _advance_racer(id: String, delta: float, elapsed_before: float) -> void:
	var r: Dictionary = racers[id]
	if r["finished"] or r["needs_reset"]:
		return
	var a: Vector3 = r["position"]
	var b: Vector3 = r["pending_position"]
	var movement := a.distance_to(b)
	if movement < 0.00001:
		return
	var max_speed: float = float(event.get("max_speed_mps", DEFAULT_MAX_SPEED_MPS))
	if movement > max_speed * delta + 5.0:
		_invalidate(id, "teleport_or_unphysical_speed")
		return
	var corridor: float = float(event.get("corridor_m", DEFAULT_CORRIDOR_M))
	if not route.corridor_clear(a, b, corridor, float(r["route_s"])):
		_invalidate(id, "shortcut_or_off_route")
		return
	var projection: Dictionary = route.project(b, float(r["route_s"]))
	var s: float = projection["s"]
	var old_cont: float = r["continuous_s"]
	var continuous := s
	if route.closed:
		continuous += roundf((old_cont - s) / route.length_m) * route.length_m
	var arc_delta := continuous - old_cont
	if absf(arc_delta) > movement * 1.7 + 3.0:
		_invalidate(id, "impossible_route_jump")
		return
	r["position"] = b
	r["route_s"] = s
	r["continuous_s"] = continuous
	r["wrong_way"] = arc_delta < -0.5
	if arc_delta <= 0.001:
		return
	var old_progress: float = r["progress_m"]
	var progress := maxf(old_progress, continuous)
	r["progress_m"] = progress
	var lap: int = r["lap"]
	var index: int = r["checkpoint_index"]
	var lap_offset: float = float(lap - 1) * route.length_m
	while index < checkpoints.size():
		var cp: Dictionary = checkpoints[index]
		var target: float = lap_offset + float(cp["s"])
		var radius: float = cp["radius_m"]
		if progress < target - radius * 0.5:
			break
		if old_progress <= target + radius and _hits_gate(a, b, cp):
			index += 1
			r["checkpoint_index"] = index
			checkpoint_passed.emit(id, cp["id"], lap)
		else:
			# A coarse tick may cross several checkpoints in order; test the
			# expected gate first, THEN classify contact with a later gate.
			for later_index in range(index + 1, checkpoints.size()):
				var later: Dictionary = checkpoints[later_index]
				if progress >= lap_offset + float(later["s"]) - float(later["radius_m"]) * 0.5 and _hits_gate(a, b, later):
					_invalidate(id, "out_of_order_checkpoint")
					return
			if progress > target + radius + 2.0:
				_invalidate(id, "missed_checkpoint")
			return
			break
	var finish_threshold := float(lap) * route.length_m - FINISH_TOLERANCE_M
	if progress >= finish_threshold:
		if index != checkpoints.size():
			_invalidate(id, "missed_checkpoint_before_finish")
			return
		lap_completed.emit(id, lap)
		if lap >= int(event["laps"]):
			r["finished"] = true
			var fraction := clampf((finish_threshold - old_progress) / maxf(progress - old_progress, 0.00001), 0.0, 1.0)
			r["finish_time"] = elapsed_before + delta * fraction
			if first_finish_time < 0.0:
				first_finish_time = r["finish_time"]
			racer_finished.emit(id, r["finish_time"])
		else:
			r["lap"] = lap + 1
			r["checkpoint_index"] = 0

func report_collision(id: String, relative_impact_speed_mps: float) -> bool:
	## Optional notification from real vehicle/collision adapter.
	## Soft contacts do not invalidate a lap; severe impacts request physical recovery.
	if state != State.RACING or not racers.has(id) or not is_finite(relative_impact_speed_mps) or relative_impact_speed_mps < 0.0:
		return false
	if relative_impact_speed_mps >= float(event.get("collision_reset_speed_mps", 13.0)):
		_invalidate(id, "collision_requires_reset")
	return true

func needs_reset(id: String) -> bool:
	return racers.has(id) and bool(racers[id].get("needs_reset", false))

func reset_racer(id: String) -> Dictionary:
	## Caller MUST teleport its own physical vehicle to returned position/forward.
	## Reset restarts the current lap; prior completed laps remain counted.
	if not racers.has(id) or route == null:
		return {}
	var r: Dictionary = racers[id]
	if r["finished"]:
		return {}
	var lap: int = r["lap"]
	var p: Vector3 = route.sample(0.0)
	var tang: Vector2 = route.tangent(0.0)
	r["position"] = p
	r["pending_position"] = p
	r["velocity"] = Vector3.ZERO
	r["route_s"] = 0.0
	r["continuous_s"] = float(lap - 1) * route.length_m
	r["progress_m"] = r["continuous_s"]
	r["checkpoint_index"] = 0
	r["needs_reset"] = false
	r["wrong_way"] = false
	r["last_invalid_reason"] = ""
	return {"position": p, "forward": Vector3(tang.x, 0.0, tang.y).normalized(), "lap": lap}

func get_racer(id: String) -> Dictionary:
	return racers[id].duplicate(true) if racers.has(id) else {}

func standings() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for id in racers.keys():
		var r: Dictionary = racers[id]
		list.append({
			"id": id, "finished": r.get("finished", false),
			"finish_time": r.get("finish_time", INF),
			"lap": r.get("lap", 1),
			"checkpoint_index": r.get("checkpoint_index", 0),
			"progress_m": r.get("progress_m", 0.0),
			"needs_reset": r.get("needs_reset", false)
		})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["finished"] != b["finished"]:
			return a["finished"]
		if a["finished"]:
			if absf(float(a["finish_time"]) - float(b["finish_time"])) > 0.000001:
				return a["finish_time"] < b["finish_time"]
		else:
			if a["lap"] != b["lap"]:
				return a["lap"] > b["lap"]
			if a["checkpoint_index"] != b["checkpoint_index"]:
				return a["checkpoint_index"] > b["checkpoint_index"]
			if a["needs_reset"] != b["needs_reset"]:
				return not a["needs_reset"]
			if absf(float(a["progress_m"]) - float(b["progress_m"])) > 0.000001:
				return a["progress_m"] > b["progress_m"]
		return str(a["id"]) < str(b["id"])
	)
	for i in range(list.size()):
		list[i]["position"] = i + 1
	return list

func show_results() -> bool:
	if state != State.FINISHED:
		return _fail("Results available only after race finished")
	_set_state(State.RESULTS)
	return true

func quit_event() -> bool:
	if state in [State.IDLE, State.FREE_ROAM, State.ABORTED]:
		return false
	paused = false
	_set_state(State.ABORTED)
	return true

func return_to_free_roam() -> bool:
	if state != State.RESULTS and state != State.ABORTED:
		return _fail("Return requires results or abort")
	paused = false
	_set_state(State.FREE_ROAM)
	return true
