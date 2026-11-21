extends RefCounted
## Aster Valley road_graph_v1 reader. Owns no world geometry or Godot scene nodes.

const MIN_SEGMENT_M := 0.05
const MAX_CONNECTION_GAP_M := 3.5
const MIN_CONNECTION_DOT := -0.35

var lanes: Dictionary = {}
var roads: Dictionary = {}
var lane_order: Array[String] = []
var errors: Array[String] = []
var bounds: Dictionary = {}


func load_road_graph(data: Dictionary) -> bool:
	errors.clear()
	lanes.clear()
	roads.clear()
	lane_order.clear()
	bounds.clear()
	if data.get("schema_version") != 1:
		_fail("schema_version must be 1")
	if data.get("units") != "meters" or data.get("coordinate_system") != "godot_y_up":
		_fail("expected meters and godot_y_up")
	if not (data.get("roads") is Array) or not (data.get("lanes") is Array):
		_fail("roads and lanes must be arrays")
		return false
	if not (data.get("bounds") is Dictionary):
		_fail("bounds must be an object")
		return false
	var raw_bounds: Dictionary = data["bounds"]
	for key in ["min_x", "max_x", "min_z", "max_z"]:
		if not _number(raw_bounds.get(key)):
			_fail("invalid bounds.%s" % key)
	if not errors.is_empty():
		return false
	bounds = raw_bounds.duplicate(true)
	if float(bounds["min_x"]) >= float(bounds["max_x"]) or float(bounds["min_z"]) >= float(bounds["max_z"]):
		_fail("bounds have reversed extent")
	for item in data["roads"]:
		if not (item is Dictionary) or not (item.get("id") is String) or item.get("id", "").is_empty():
			_fail("road has no valid id")
			continue
		var rid: String = item["id"]
		if roads.has(rid):
			_fail("duplicate road %s" % rid)
			continue
		if not (item.get("lane_ids") is Array) or not (item.get("name") is String) or not (item.get("region") is String):
			_fail("road %s missing name, region or lane_ids" % rid)
			continue
		roads[rid] = item.duplicate(true)
	for item in data["lanes"]:
		if not (item is Dictionary):
			_fail("lane must be an object")
			continue
		if not (item.get("id") is String) or item.get("id", "").is_empty():
			_fail("lane has no valid id")
			continue
		var lid: String = item["id"]
		if lanes.has(lid):
			_fail("duplicate lane %s" % lid)
			continue
		var rid: Variant = item.get("road_id")
		if not (rid is String) or not roads.has(rid):
			_fail("lane %s references missing road" % lid)
			continue
		if not _number(item.get("width_m")) or not _number(item.get("speed_limit_kph")):
			_fail("lane %s invalid width or speed" % lid)
			continue
		if float(item["width_m"]) <= 0.0 or float(item["speed_limit_kph"]) < 0.0:
			_fail("lane %s has negative speed or nonpositive width" % lid)
			continue
		if not (item.get("surface") is String) or not (item.get("next_lane_ids") is Array):
			_fail("lane %s missing surface or next_lane_ids" % lid)
			continue
		var raw: Variant = item.get("points")
		if not (raw is Array) or raw.size() < 2:
			_fail("lane %s needs at least two points" % lid)
			continue
		var points: Array[Vector3] = []
		var cumulative: Array[float] = [0.0]
		var valid := true
		for p in raw:
			if not (p is Array) or p.size() != 3 or not _number(p[0]) or not _number(p[1]) or not _number(p[2]):
				valid = false
				break
			var point := Vector3(float(p[0]), float(p[1]), float(p[2]))
			if point.x < float(bounds["min_x"]) - 0.1 or point.x > float(bounds["max_x"]) + 0.1 or point.z < float(bounds["min_z"]) - 0.1 or point.z > float(bounds["max_z"]) + 0.1:
				valid = false
				break
			if not points.is_empty():
				var delta: Vector3 = point - points.back()
				if delta.length() < MIN_SEGMENT_M or Vector2(delta.x, delta.z).length() < MIN_SEGMENT_M:
					valid = false
					break
				cumulative.append(cumulative.back() + delta.length())
			points.append(point)
		if not valid:
			_fail("lane %s invalid/out-of-bounds/duplicate points" % lid)
			continue
		lanes[lid] = {
			"id": lid, "road_id": rid, "points": points,
			"cumulative": cumulative, "length": cumulative.back(),
			"width_m": float(item["width_m"]),
			"speed_limit_mps": float(item["speed_limit_kph"]) / 3.6,
			"next_lane_ids": item["next_lane_ids"].duplicate()
		}
		lane_order.append(lid)
	lane_order.sort()
	var listed_lanes: Dictionary = {}
	for rid in roads:
		for lid in roads[rid]["lane_ids"]:
			if not lanes.has(lid) or lanes[lid]["road_id"] != rid:
				_fail("road %s has invalid lane_id %s" % [rid, str(lid)])
			elif listed_lanes.has(lid):
				_fail("lane %s listed in multiple road entries" % str(lid))
			else:
				listed_lanes[lid] = true
	for lid in lane_order:
		if not listed_lanes.has(lid):
			_fail("lane %s omitted from its road lane_ids" % lid)
	for lid in lane_order:
		var lane: Dictionary = lanes[lid]
		var seen := {}
		for nid in lane["next_lane_ids"]:
			if not (nid is String) or not lanes.has(nid) or seen.has(nid):
				_fail("lane %s has invalid/duplicate next_lane_id %s" % [lid, str(nid)])
				continue
			seen[nid] = true
			var successor: Dictionary = lanes[nid]
			var end: Vector3 = lane["points"].back()
			var start: Vector3 = successor["points"][0]
			var last: Vector3 = lane["points"][-2]
			var after: Vector3 = successor["points"][1]
			var d0: Vector3 = (end - last).normalized()
			var d1: Vector3 = (after - start).normalized()
			if end.distance_to(start) > MAX_CONNECTION_GAP_M or d0.dot(d1) < MIN_CONNECTION_DOT:
				_fail("lane %s -> %s teleports or reverses direction" % [lid, nid])
	return errors.is_empty()


func lane_length(lane_id: String) -> float:
	if not lanes.has(lane_id):
		return 0.0
	return lanes[lane_id]["length"]


func get_pose(lane_id: String, s: float) -> Dictionary:
	if not lanes.has(lane_id):
		return {}
	var lane: Dictionary = lanes[lane_id]
	var lengths: Array = lane["cumulative"]
	var points: Array = lane["points"]
	var distance: float = clampf(s, 0.0, lane["length"])
	var seg := 0
	while seg + 2 < lengths.size() and lengths[seg + 1] < distance:
		seg += 1
	var seg_length: float = lengths[seg + 1] - lengths[seg]
	var t: float = clampf((distance - lengths[seg]) / seg_length, 0.0, 1.0)
	var pos: Vector3 = points[seg].lerp(points[seg + 1], t)
	var tangent: Vector3 = (points[seg + 1] - points[seg]).normalized()
	# Smooth heading at vertices; position always remains on the authored lane.
	var blend_distance := minf(2.5, seg_length * 0.4)
	if seg > 0 and distance - lengths[seg] < blend_distance:
		var prev: Vector3 = (points[seg] - points[seg - 1]).normalized()
		var k: float = 0.5 + 0.5 * (distance - lengths[seg]) / blend_distance
		tangent = prev.lerp(tangent, k).normalized()
	if seg + 2 < points.size() and lengths[seg + 1] - distance < blend_distance:
		var following: Vector3 = (points[seg + 2] - points[seg + 1]).normalized()
		var k: float = 0.5 - 0.5 * (lengths[seg + 1] - distance) / blend_distance
		tangent = tangent.lerp(following, k).normalized()
	return {"position": pos, "tangent": tangent, "lane_id": lane_id, "distance_m": distance}


func curve_speed_mps(lane_id: String, s: float, lateral_accel_mps2: float = 3.2) -> float:
	if not lanes.has(lane_id):
		return 0.0
	var speed: float = lanes[lane_id]["speed_limit_mps"]
	# Scan a bounded lookahead, controlling early braking before sharp vertices.
	var start: Dictionary = get_pose(lane_id, s)
	for ahead in [6.0, 12.0, 20.0, 30.0]:
		var actual: float = minf(ahead, lane_length(lane_id) - s)
		if actual < 0.25:
			continue
		var sample: Dictionary = get_pose(lane_id, s + actual)
		var angle: float = acos(clampf(start["tangent"].dot(sample["tangent"]), -1.0, 1.0))
		var curvature: float = angle / maxf(actual, 0.25)
		if curvature > 0.0001:
			var corner_speed: float = sqrt(lateral_accel_mps2 / curvature)
			# Add physical braking distance to previewed curvature.
			speed = minf(speed, sqrt(corner_speed * corner_speed + 2.0 * 3.5 * maxf(actual - 4.0, 0.0)))
	return maxf(0.0, speed)


func nearest_lane(position: Vector3, max_distance_m: float = 10.0) -> Dictionary:
	var best := {"lane_id": "", "distance_m": max_distance_m, "s": 0.0}
	for lid in lane_order:
		var lane: Dictionary = lanes[lid]
		var points: Array = lane["points"]
		var cum: Array = lane["cumulative"]
		for i in range(points.size() - 1):
			var ab: Vector3 = points[i + 1] - points[i]
			var t: float = clampf((position - points[i]).dot(ab) / ab.length_squared(), 0.0, 1.0)
			var gap: float = position.distance_to(points[i] + ab * t)
			if gap < best["distance_m"]:
				best = {"lane_id": lid, "distance_m": gap, "s": lerpf(cum[i], cum[i + 1], t)}
	return best


func find_route(start_lane: String, destination_lane: String, max_expansions: int = 512) -> Array[String]:
	# Bounded Dijkstra over directed lane connections. Run on route assignment,
	# never every frame; edge cost is the next lane's physical arc length.
	var empty: Array[String] = []
	if not lanes.has(start_lane) or not lanes.has(destination_lane):
		return empty
	var frontier: Array[String] = [start_lane]
	var best: Dictionary = {start_lane: 0.0}
	var parent: Dictionary = {}
	var expansions := 0
	while not frontier.is_empty() and expansions < max_expansions:
		var idx := 0
		for i in range(1, frontier.size()):
			if best[frontier[i]] < best[frontier[idx]]:
				idx = i
		var current: String = frontier.pop_at(idx)
		if current == destination_lane:
			var route: Array[String] = [current]
			while parent.has(current):
				current = parent[current]
				route.push_front(current)
			return route
		expansions += 1
		for successor in lanes[current]["next_lane_ids"]:
			var distance: float = best[current] + lanes[successor]["length"]
			if distance < float(best.get(successor, INF)):
				best[successor] = distance
				parent[successor] = current
				if not frontier.has(successor):
					frontier.append(successor)
	return empty


func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))


func _fail(message: String) -> void:
	errors.append(message)
