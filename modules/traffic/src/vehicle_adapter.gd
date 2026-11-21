extends RefCounted
## Optional bridge for a nearby NPC that uses a real vehicle controller.
## Do not also apply traffic kinematic transforms to the same vehicle.


static func compute_drive_input(
		body_transform: Transform3D,
		body_forward_speed_mps: float,
		lookahead_position: Vector3,
		target_speed_mps: float,
		max_steer_angle_rad: float = 0.55
	) -> Dictionary:
	var forward: Vector3 = -body_transform.basis.z
	var right: Vector3 = body_transform.basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()
	var delta: Vector3 = lookahead_position - body_transform.origin
	delta.y = 0.0
	var desired: Vector3 = delta.normalized() if delta.length_squared() > 0.00001 else forward
	var heading_error: float = atan2(right.dot(desired), forward.dot(desired))
	var steer: float = clampf(heading_error / maxf(max_steer_angle_rad, 0.1), -1.0, 1.0)
	var speed_error: float = maxf(0.0, target_speed_mps) - body_forward_speed_mps
	return {"steer": steer,
		"throttle": clampf(speed_error * 0.28, 0.0, 1.0),
		"brake": clampf(-speed_error * 0.32, 0.0, 1.0),
		"handbrake": false}
