## Directed, validated road_graph_v1 lane centerlines. No dependence on scene tree.
extends RefCounted

const MAX_JOIN_GAP_M := 2.5
const MIN_SEGMENT_M := 0.01

var lanes: Dictionary = {}
var roads: Dictionary = {}
var bounds: Dictionary = {}
var errors: PackedStringArray = PackedStringArray()


func load_road_graph(source: Dictionary) -> bool:
	# Parse into temporary maps. A failed reload must never leave a partial network.
	errors.clear()
	var parsed_lanes: Dictionary = {}
	var parsed_roads: Dictionary = {}
	if source.get("schema_version") != 1 or source.get("units") != "meters" or source.get("coordinate_system") != "godot_y_up":
		return _reject("Expected road_graph schema 1, meters, godot_y_up")
	if not _valid_bounds(source.get("bounds")):
		return _reject("Missing or invalid map bounds")
	if typeof(source.get("roads")) != TYPE_ARRAY or typeof(source.get("lanes")) != TYPE_ARRAY:
		return _reject("roads and lanes must be arrays")
	for item in source["roads"]:
		if typeof(item) != TYPE_DICTIONARY:
			return _reject("Road entry is not an object")
		var rid: Variant = item.get("id")
		if typeof(rid) != TYPE_STRING or rid.is_empty() or parsed_roads.has(rid):
			return _reject("Missing or duplicate road ID")
		if typeof(item.get("name")) != TYPE_STRING or typeof(item.get("region")) != TYPE_STRING:
			return _reject("Road %s missing name/region" % rid)
		if typeof(item.get("lane_ids")) != TYPE_ARRAY:
			return _reject("Road %s missing lane_ids" % rid)
		parsed_roads[rid] = item.duplicate(true)
	for item in source["lanes"]:
		if typeof(item) != TYPE_DICTIONARY:
			return _reject("Lane entry is not an object")
		var lid: Variant = item.get("id")
		var rid: Variant = item.get("road_id")
		if typeof(lid) != TYPE_STRING or lid.is_empty() or parsed_lanes.has(lid):
			return _reject("Missing or duplicate lane ID")
		if typeof(rid) != TYPE_STRING or not parsed_roads.has(rid):
			return _reject("Lane %s has undefined road" % lid)
		if typeof(item.get("points")) != TYPE_ARRAY or item["points"].size() < 2:
			return _reject("Lane %s needs at least two points" % lid)
		if not _nonnegative_number(item.get("speed_limit_kph")):
			return _reject("Lane %s has invalid speed limit" % lid)
		if not _positive_number(item.get("width_m")):
			return _reject("Lane %s has invalid width" % lid)
		if typeof(item.get("surface")) != TYPE_STRING:
			return _reject("Lane %s missing surface" % lid)
		if typeof(item.get("next_lane_ids")) != TYPE_ARRAY:
			return _reject("Lane %s missing next_lane_ids" % lid)
		var pts: Array[Vector3] = []
		var cumulative: PackedFloat32Array = PackedFloat32Array([0.0])
		var distance := 0.0
		for xyz in item["points"]:
			if typeof(xyz) != TYPE_ARRAY or xyz.size() != 3:
				return _reject("Lane %s has non-XYZ point" % lid)
			for value in xyz:
				if not _finite_number(value):
					return _reject("Lane %s has non-finite coordinate" % lid)
			var pos := Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
			if pos.x < float(source["bounds"]["min_x"]) - 0.1 or pos.x > float(source["bounds"]["max_x"]) + 0.1 or pos.z < float(source["bounds"]["min_z"]) - 0.1 or pos.z > float(source["bounds"]["max_z"]) + 0.1:
				return _reject("Lane %s point outside world bounds" % lid)
			if not pts.is_empty():
				var seg := pos.distance_to(pts.back())
				if seg < MIN_SEGMENT_M:
					return _reject("Lane %s has duplicate/zero-length segment" % lid)
				distance += seg
				cumulative.append(distance)
			pts.append(pos)
		var next_ids: Array[String] = []
		for next_id in item["next_lane_ids"]:
			if typeof(next_id) != TYPE_STRING or next_ids.has(next_id):
				return _reject("Lane %s has invalid/duplicate next_lane_ids" % lid)
			next_ids.append(next_id)
		next_ids.sort()
		parsed_lanes[lid] = {
			"id": lid, "road_id": rid, "points": pts, "cumulative": cumulative,
			"length_m": distance, "width_m": float(item["width_m"]),
			"speed_limit_mps": float(item["speed_limit_kph"]) / 3.6,
			"surface": item["surface"], "next_lane_ids": next_ids,
		}
	for rid in parsed_roads:
		var seen: Dictionary = {}
		for lid in parsed_roads[rid]["lane_ids"]:
			if typeof(lid) != TYPE_STRING or seen.has(lid) or not parsed_lanes.has(lid):
				return _reject("Road %s has repeated or missing lane" % rid)
			if parsed_lanes[lid]["road_id"] != rid:
				return _reject("Road %s lists lane on another road" % rid)
			seen[lid] = true
	for lid in parsed_lanes:
		if not parsed_roads[parsed_lanes[lid]["road_id"]]["lane_ids"].has(lid):
			return _reject("Road does not list lane %s" % lid)
		for target_id in parsed_lanes[lid]["next_lane_ids"]:
			if not parsed_lanes.has(target_id):
				return _reject("Lane %s refers to missing lane %s" % [lid, target_id])
			var a: Array = parsed_lanes[lid]["points"]
			var b: Array = parsed_lanes[target_id]["points"]
			if a.back().distance_to(b.front()) > MAX_JOIN_GAP_M:
				return _reject("Lane connection %s -> %s jumps more than %.1fm" % [lid, target_id, MAX_JOIN_GAP_M])
			var in_dir: Vector3 = (a.back() - a[a.size() - 2]).normalized()
			var out_dir: Vector3 = (b[1] - b.front()).normalized()
			if in_dir.dot(out_dir) < -0.26:
				return _reject("Lane connection %s -> %s reverses heading" % [lid, target_id])
	lanes = parsed_lanes
	roads = parsed_roads
	bounds = source["bounds"].duplicate(true)
	return true


func has_lane(lane_id: String) -> bool:
	return lanes.has(lane_id)


func sample(lane_id: String, distance_m: float) -> Dictionary:
	if not lanes.has(lane_id):
		return {}
	var lane: Dictionary = lanes[lane_id]
	var cumulative: PackedFloat32Array = lane["cumulative"]
	var points: Array = lane["points"]
	var s := clampf(distance_m, 0.0, lane["length_m"])
	# Binary search: sampling is logarithmic even for long detailed lanes.
	var lo := 0
	var hi := points.size() - 2
	while lo < hi:
		var mid: int = (lo + hi) >> 1
		if cumulative[mid + 1] < s:
			lo = mid + 1
		else:
			hi = mid
	var seg_len: float = cumulative[lo + 1] - cumulative[lo]
	var t := clampf((s - cumulative[lo]) / seg_len, 0.0, 1.0)
	var dir: Vector3 = (points[lo + 1] - points[lo]) / seg_len
	return {"position": points[lo].lerp(points[lo + 1], t), "tangent": dir, "distance_m": s}


func corner_speed_mps(lane_id: String, distance_m: float, lookahead_m: float = 24.0) -> float:
	# Sample the direction change in a forward window, then assume max 2.6 m/s² lateral acceleration.
	# Short windows near vertices keep right-angle city turns slow; straights keep lane speed.
	var lane: Dictionary = lanes[lane_id]
	var start: Vector3 = sample(lane_id, distance_m + 1.0)["tangent"]
	var look_s: float = minf(lane["length_m"], distance_m + lookahead_m)
	var end: Vector3 = sample(lane_id, look_s)["tangent"]
	var turn := acos(clampf(start.dot(end), -1.0, 1.0))
	if turn < 0.02:
		return 100.0
	var kappa := turn / maxf(3.0, look_s - distance_m)
	return sqrt(2.6 / maxf(kappa, 0.00001))


func find_route(from_lane_id: String, to_lane_id: String) -> Array[String]:
	# Bounded breadth-first path on the directed adjacency. Returns [] if unreachable.
	var path: Array[String] = []
	if not lanes.has(from_lane_id) or not lanes.has(to_lane_id):
		return path
	var queue: Array[String] = [from_lane_id]
	var previous: Dictionary = {from_lane_id: ""}
	var i := 0
	while i < queue.size():
		var current: String = queue[i]
		i += 1
		if current == to_lane_id:
			while current != "":
				path.push_front(current)
				current = previous[current]
			return path
		for next_id in lanes[current]["next_lane_ids"]:
			if not previous.has(next_id):
				previous[next_id] = current
				queue.append(next_id)
	return path


func _valid_bounds(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	for key in ["min_x", "max_x", "min_z", "max_z"]:
		if not _finite_number(value.get(key)):
			return false
	return float(value["max_x"]) > float(value["min_x"]) and float(value["max_z"]) > float(value["min_z"])


func _finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	var number := float(value)
	return number == number and absf(number) < 1000000.0


func _nonnegative_number(value: Variant) -> bool:
	return _finite_number(value) and float(value) >= 0.0


func _positive_number(value: Variant) -> bool:
	return _finite_number(value) and float(value) > 0.0


func _reject(reason: String) -> bool:
	errors.append(reason)
	return false
