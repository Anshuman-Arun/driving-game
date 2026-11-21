extends RefCounted
## The only required vehicle-side call is set_drive_input(steer, throttle, brake, handbrake).
## This module intentionally knows nothing about Easy Vehicle Physics internals.

static func apply(vehicle: Object, controls: Dictionary) -> bool:
	if vehicle == null or not vehicle.has_method("set_drive_input"):
		return false
	vehicle.call(
		"set_drive_input",
		clampf(float(controls.get("steer", 0.0)), -1.0, 1.0),
		clampf(float(controls.get("throttle", 0.0)), 0.0, 1.0),
		clampf(float(controls.get("brake", 0.0)), 0.0, 1.0),
		bool(controls.get("handbrake", false))
	)
	return true

static func read_state(vehicle: Node3D) -> Dictionary:
	if vehicle == null:
		return {}
	var v := Vector3.ZERO
	if vehicle.has_method("get_drive_velocity"):
		v = vehicle.call("get_drive_velocity")
	elif vehicle is RigidBody3D:
		v = vehicle.linear_velocity
	elif vehicle is CharacterBody3D:
		v = vehicle.velocity
	var facing: Vector3 = -vehicle.global_transform.basis.z.normalized()
	return {"position": vehicle.global_position, "velocity": v, "forward": facing, "speed_mps": v.length()}
