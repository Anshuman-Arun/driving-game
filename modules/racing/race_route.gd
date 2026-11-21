extends RefCounted
## Validated directed centerline route for both event progress and rival steering.
## All distance/projection math uses XZ meters; Y is retained for positioning.
const CONNECT_TOLERANCE_M := 6.0

var points: Array[Vector3] = []
var segments: Array[Dictionary] = []
var length_m: float = 0.0
var closed: bool = false
var lane_ids: Array[String] = []

static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))

static func valid_point(value: Variant) -> bool:
	if not (value is Array) or value.size() != 3:
		return false
	for component in value:
		if not _number(component):
			return false
	return true

static func point3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func validate_road_graph(graph: Dictionary) -> String:
	if graph.get("schema_version") != 1 or graph.get("units") != "meters" or graph.get("coordinate_system") != "godot_y_up":
		return "Road graph must use schema_version 1, meters, godot_y_up"
	var bounds: Variant = graph.get("bounds")
	if not (bounds is Dictionary):
		return "Missing bounds"
	for key in ["min_x", "max_x", "min_z", "max_z"]:
		if not bounds.has(key) or not _number(bounds[key]):
			return "Invalid bounds: " + key
	if bounds["min_x"] >= bounds["max_x"] or bounds["min_z"] >= bounds["max_z"]:
		return "Inverted bounds"
	var roads: Variant = graph.get("roads")
	var lanes: Variant = graph.get("lanes")
	if not (roads is Array) or not (lanes is Array) or roads.is_empty() or lanes.is_empty():
		return "Roads and lanes must be nonempty arrays"
	var road_ids := {}
	var lane_ids_seen := {}
	for road in roads:
		if not (road is Dictionary) or not (road.get("id") is String) or str(road.get("id")).is_empty():
			return "Invalid road ID"
		var rid: String = road["id"]
		if road_ids.has(rid) or not (road.get("lane_ids") is Array):
			return "Duplicate road ID or invalid road lanes: " + rid
		road_ids[rid] = road
	for lane in lanes:
		if not (lane is Dictionary) or not (lane.get("id") is String) or str(lane.get("id")).is_empty():
			return "Invalid lane ID"
		var lid: String = lane["id"]
		if lane_ids_seen.has(lid):
			return "Duplicate lane ID: " + lid
		if not road_ids.has(lane.get("road_id")):
			return "Unknown road_id for " + lid
		if not (lane.get("points") is Array) or lane["points"].size() < 2:
			return "Lane needs >=2 points: " + lid
		if not (lane.get("next_lane_ids") is Array):
			return "Missing next_lane_ids: " + lid
		if not _number(lane.get("width_m")) or float(lane["width_m"]) <= 0.0:
			return "Invalid lane width: " + lid
		if not _number(lane.get("speed_limit_kph")) or float(lane["speed_limit_kph"]) < 0.0:
			return "Invalid speed limit: " + lid
		if not (lane.get("surface") is String):
			return "Invalid surface: " + lid
		var prior := Vector3.ZERO
		var first := true
		for raw in lane["points"]:
			if not valid_point(raw):
				return "Invalid point: " + lid
			var p := point3(raw)
			if not first and prior.distance_to(p) < 0.001:
				return "Consecutive duplicate points: " + lid
			if p.x < bounds["min_x"] or p.x > bounds["max_x"] or p.z < bounds["min_z"] or p.z > bounds["max_z"]:
				return "Point outside bounds: " + lid
			prior = p
			first = false
		lane_ids_seen[lid] = lane
	for road_id in road_ids:
		for lid in road_ids[road_id]["lane_ids"]:
			if not lane_ids_seen.has(lid) or lane_ids_seen[lid]["road_id"] != road_id:
				return "Invalid road lane reference: " + road_id
	for lane_id in lane_ids_seen:
		if not (lane_id in road_ids[lane_ids_seen[lane_id]["road_id"]]["lane_ids"]):
			return "Lane not registered on road: " + lane_id
		for next_id in lane_ids_seen[lane_id]["next_lane_ids"]:
			if not lane_ids_seen.has(next_id):
				return "Unknown next lane: " + str(next_id)
	return ""

func configure(graph: Dictionary, route_ids: Array, is_closed: bool) -> String:
	points.clear()
	segments.clear()
	lane_ids.clear()
	length_m = 0.0
	closed = is_closed
	var error := validate_road_graph(graph)
	if not error.is_empty():
		return error
	if route_ids.is_empty():
		return "Route must contain at least one lane"
	var by_id := {}
	for lane in graph["lanes"]:
		by_id[lane["id"]] = lane
	var previous: Dictionary = {}
	var speed_segments: Array[float] = []
	for raw_id in route_ids:
		if not (raw_id is String) or not by_id.has(raw_id):
			return "Unknown route lane: " + str(raw_id)
		var lane: Dictionary = by_id[raw_id]
		if not previous.is_empty():
			if not (raw_id in previous["next_lane_ids"]):
				return "Lane adjacency missing: " + str(previous["id"]) + " -> " + str(raw_id)
			var gap := point3(previous["points"].back()).distance_to(point3(lane["points"][0]))
			if gap > CONNECT_TOLERANCE_M:
				return "Disconnected route lanes: " + str(raw_id)
		lane_ids.append(raw_id)
		var speed := float(lane["speed_limit_kph"]) / 3.6
		for raw_point in lane["points"]:
			var p := point3(raw_point)
			if not points.is_empty() and points.back().distance_to(p) < 0.001:
				continue
			if not points.is_empty():
				speed_segments.append(speed)
			points.append(p)
		previous = lane
	if closed:
		var first_lane: Dictionary = by_id[route_ids[0]]
		if not (route_ids[0] in previous["next_lane_ids"]):
			return "Circuit route does not connect last lane to first"
		if points.back().distance_to(points[0]) > CONNECT_TOLERANCE_M:
			return "Circuit endpoints are disconnected"
		if points.back().distance_to(points[0]) >= 0.001:
			speed_segments.append(float(first_lane["speed_limit_kph"]) / 3.6)
			points.append(points[0])
	if points.size() < 2 or speed_segments.size() != points.size() - 1:
		return "Route produced too few segments"
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var delta := Vector2(b.x - a.x, b.z - a.z)
		var dist := delta.length()
		if dist < 0.001:
			return "Route has a vertical/zero-horizontal segment"
		segments.append({"a": a, "b": b, "from": length_m, "length": dist, "dir": delta / dist, "speed_mps": speed_segments[i]})
		length_m += dist
	return ""

func _wrapped_distance(s: float) -> float:
	if length_m <= 0.0:
		return 0.0
	if closed:
		return fposmod(s, length_m)
	return clampf(s, 0.0, length_m)

func _segment_at(s: float) -> Dictionary:
	var distance := _wrapped_distance(s)
	for segment in segments:
		if distance <= float(segment["from"]) + float(segment["length"]) + 0.00001:
			return segment
	return segments.back()

func sample(s: float) -> Vector3:
	var segment := _segment_at(s)
	var part: float = clampf((_wrapped_distance(s) - float(segment["from"])) / float(segment["length"]), 0.0, 1.0)
	return (segment["a"] as Vector3).lerp(segment["b"] as Vector3, part)

func tangent(s: float) -> Vector2:
	return _segment_at(s)["dir"]

func speed_limit(s: float) -> float:
	return float(_segment_at(s)["speed_mps"])

func curvature(s: float, span_m: float = 9.0) -> float:
	var a := tangent(s - span_m)
	var b := tangent(s + span_m)
	var angle := absf(atan2(a.cross(b), a.dot(b)))
	return angle / maxf(2.0 * span_m, 0.1)

func project(position: Vector3, hint_s: float = -1.0) -> Dictionary:
	var target := Vector2(position.x, position.z)
	var best_score := INF
	var result := {}
	for segment in segments:
		var a: Vector3 = segment["a"]
		var b: Vector3 = segment["b"]
		var start := Vector2(a.x, a.z)
		var v := Vector2(b.x - a.x, b.z - a.z)
		var t := clampf((target - start).dot(v) / v.length_squared(), 0.0, 1.0)
		var nearest := start + v * t
		var dist_sq := target.distance_squared_to(nearest)
		var s: float = float(segment["from"]) + float(segment["length"]) * t
		var score := dist_sq
		if hint_s >= 0.0:
			var separation := absf(s - hint_s)
			if closed:
				separation = minf(separation, length_m - separation)
			score += separation * separation * 0.001
		if score < best_score:
			best_score = score
			result = {"s": s, "distance_m": sqrt(dist_sq), "point": a.lerp(b, t), "tangent": segment["dir"]}
	return result

func corridor_clear(a: Vector3, b: Vector3, corridor_m: float, hint_s: float = -1.0) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / 3.0))
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		if float(project(p, hint_s)["distance_m"]) > corridor_m:
			return false
	return true
