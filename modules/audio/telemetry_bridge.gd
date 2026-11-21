class_name AsterAudioTelemetry
extends RefCounted
## Convert PR #6's GEVP Vehicle/Wheel fields without importing its scripts.

static func from_gevp(vehicle: Node3D) -> Dictionary:
	var velocity: Vector3 = vehicle.get("linear_velocity") if _has(vehicle, "linear_velocity") else Vector3.ZERO
	var speed := velocity.length()
	var lateral := absf(velocity.dot(vehicle.global_basis.x))
	var grounded := false
	var surface := "asphalt"
	var wheel_slip := 0.0
	var wheels: Array = vehicle.get("wheel_array") if _has(vehicle, "wheel_array") else []
	for wheel in wheels:
		if not is_instance_valid(wheel):
			continue
		if wheel.is_colliding():
			grounded = true
			surface = _surface(str(wheel.get("surface_type")))
			if _has(wheel, "slip_vector"):
				var slip: Vector2 = wheel.get("slip_vector")
				wheel_slip = maxf(wheel_slip, absf(slip.x))
	var throttle := clampf(float(_value(vehicle, "throttle_input", 0.0)), 0.0, 1.0)
	var brake := clampf(float(_value(vehicle, "brake_input", 0.0)), 0.0, 1.0)
	return {
		"rpm": float(_value(vehicle, "motor_rpm", 1000.0)),
		"idle_rpm": float(_value(vehicle, "idle_rpm", 950.0)),
		"max_rpm": float(_value(vehicle, "max_rpm", 7100.0)),
		"throttle": throttle,
		"load": clampf(throttle + brake * 0.07, 0.0, 1.0),
		"gear": int(_value(vehicle, "current_gear", 1)),
		"speed_mps": speed,
		"lateral_slip": clampf(maxf(lateral, wheel_slip) / 9.0, 0.0, 1.0),
		"grip": clampf(1.0 - maxf(lateral, wheel_slip) / 16.0, 0.0, 1.0),
		"on_ground": grounded,
		"surface": surface,
		"handbrake": float(_value(vehicle, "handbrake_input", 0.0)) > 0.3,
		"engine_braking": throttle < 0.08 and speed > 3.0,
	}


static func _surface(raw: String) -> String:
	match raw.to_lower():
		"dirt", "gravel": return "gravel"
		"grass": return "grass"
		_: return "asphalt"


static func _value(object: Object, name: String, fallback: Variant) -> Variant:
	return object.get(name) if _has(object, name) else fallback


static func _has(object: Object, name: String) -> bool:
	for info in object.get_property_list():
		if str(info.get("name", "")) == name:
			return true
	return false
