extends RefCounted
## Deterministic pure-pursuit rival planner. Produces inputs, NEVER integrates game physics.
## The host's vehicle adapter should implement set_drive_input(steer, throttle, brake, handbrake).
const RaceRoute = preload("race_route.gd")
var route: RefCounted
var last_error: String = ""
var last_s: float = -1.0
var stuck_seconds: float = 0.0
var preferred_speed_mps: float = 24.0
var wheelbase_m: float = 2.6
var max_steer_angle_rad: float = 0.55
var lateral_accel_mps2: float = 6.8
var comfortable_brake_mps2: float = 7.5
var lookahead_base_m: float = 6.0
var lookahead_speed_gain: float = 0.55
var max_off_route_m: float = 22.0

func configure(graph: Dictionary, lane_route: Array, closed: bool) -> bool:
	var new_route = RaceRoute.new()
	last_error = new_route.configure(graph, lane_route, closed)
	if not last_error.is_empty():
		route = null
		return false
	route = new_route
	reset_tracking()
	return true

func reset_tracking() -> void:
	last_s = -1.0
	stuck_seconds = 0.0

func _corner_speed(s: float) -> float:
	var k: float = route.curvature(s, 8.0)
	return minf(minf(preferred_speed_mps, sqrt(lateral_accel_mps2 / maxf(k, 0.0001))), route.speed_limit(s))

func _speed_plan(s: float, speed: float) -> float:
	var target := _corner_speed(s)
	# Forecast corners: upper bound current speed by distance required to brake for each bend.
	for distance in range(5, 81, 5):
		var future: float = float(distance)
		if not route.closed and s + future >= route.length_m:
			var remaining: float = maxf(0.0, route.length_m - s - 2.0)
			target = minf(target, sqrt(2.0 * comfortable_brake_mps2 * remaining))
			break
		var turn_speed := _corner_speed(s + future)
		var safe_now := sqrt(turn_speed * turn_speed + 2.0 * comfortable_brake_mps2 * future)
		target = minf(target, safe_now)
	# Overspeed in a bend should not produce a sudden unrealistic throttle spike.
	return clampf(target, 0.0, preferred_speed_mps)

func compute_controls(position: Vector3, forward: Vector3, speed_mps: float, delta: float, obstacles: Array = []) -> Dictionary:
	var neutral := {"steer": 0.0, "throttle": 0.0, "brake": 1.0, "handbrake": false,
		"target_speed_mps": 0.0, "lookahead_m": 0.0, "route_s": 0.0, "needs_reset": false}
	if route == null or delta < 0.0 or not is_finite(delta):
		neutral["needs_reset"] = true
		return neutral
	var projection: Dictionary = route.project(position, last_s)
	var s: float = projection["s"]
	last_s = s
	neutral["route_s"] = s
	if float(projection["distance_m"]) > max_off_route_m:
		neutral["needs_reset"] = true
		return neutral
	var speed := maxf(speed_mps, 0.0)
	var lookahead := clampf(lookahead_base_m + speed * lookahead_speed_gain, 7.0, 33.0)
	var target_point: Vector3 = route.sample(s + lookahead)
	var to_point := Vector2(target_point.x - position.x, target_point.z - position.z)
	var heading := Vector2(forward.x, forward.z)
	if heading.length_squared() < 0.0001:
		var t: Vector2 = route.tangent(s)
		heading = t
	heading = heading.normalized()
	if to_point.length() < 0.2:
		target_point = route.sample(s + lookahead + 4.0)
		to_point = Vector2(target_point.x - position.x, target_point.z - position.z)
	var aim := to_point.normalized()
	var theta := atan2(heading.cross(aim), heading.dot(aim))
	var pursuit_curvature := 2.0 * sin(theta) / maxf(to_point.length(), 1.0)
	var steering_angle := atan(wheelbase_m * pursuit_curvature)
	# Positive Godot Y rotation produces a NEGATIVE Vector2.cross of XZ headings.
	var steer := clampf(-steering_angle / max_steer_angle_rad, -1.0, 1.0)
	var target_speed := _speed_plan(s, speed)
	if absf(theta) > 1.2:
		target_speed = minf(target_speed, 6.0)
	# Obstacles are already projected into this car's heading: positive distance_m ahead,
	# lateral_m signed sideways; no scene-tree queries or collision assumptions here.
	for item in obstacles:
		if not (item is Dictionary):
			continue
		if not RaceRoute._number(item.get("distance_m")) or not RaceRoute._number(item.get("lateral_m")):
			continue
		var d: float = float(item["distance_m"])
		var lateral: float = absf(float(item["lateral_m"]))
		if d < 0.0 or lateral > 2.8:
			continue
		var clearance := maxf(0.0, d - 5.0)
		target_speed = minf(minf(target_speed, clearance / 1.3), sqrt(2.0 * comfortable_brake_mps2 * clearance))
	var error := target_speed - speed
	var throttle := clampf(error / 5.0 + 0.22, 0.0, 1.0)
	var brake := 0.0
	if error < -0.8:
		throttle = 0.0
		brake = clampf((-error - 0.8) / 5.0, 0.0, 1.0)
	if speed < 0.5 and throttle > 0.7 and target_speed > 4.0:
		stuck_seconds += delta
	else:
		stuck_seconds = 0.0
	return {
		"steer": steer, "throttle": throttle, "brake": brake, "handbrake": false,
		"target_speed_mps": target_speed, "lookahead_m": lookahead, "route_s": s,
		"needs_reset": stuck_seconds > 9.0
	}
