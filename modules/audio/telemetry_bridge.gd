class_name AsterAudioTelemetry
extends RefCounted
## Duck-typed bridge for Core PR #6's GEVP Vehicle and Wheel properties.
## No dependency on the core scripts, so the audio bench remains standalone.

static func from_gevp(vehicle: Node3D) -> Dictionary:
	if not is_instance_valid(vehicle):
		return _stationary()

	# A single property-list lookup per vehicle sample, rather than one per field.
	var properties := _property_names(vehicle)
	var raw_velocity: Variant = _read(vehicle, properties, "linear_velocity", Vector3.ZERO)
	var velocity: Vector3 = raw_velocity if raw_velocity is Vector3 else Vector3.ZERO
	var speed := velocity.length()
	var basis := vehicle.global_basis if vehicle.is_inside_tree() else vehicle.basis
	var lateral := absf(velocity.dot(basis.x))
	var gear := int(_read(vehicle, properties, "current_gear", 1))
	var throttle_input := clampf(float(_read(vehicle, properties, "throttle_input", 0.0)), 0.0, 1.0)
	var brake_input := clampf(float(_read(vehicle, properties, "brake_input", 0.0)), 0.0, 1.0)

	# VehicleAdapter deliberately swaps the GEVP pedals while in reverse.
	var throttle := brake_input if gear == -1 else throttle_input
	var brake := throttle_input if gear == -1 else brake_input
	var grounded := false
	var surface_counts := {"asphalt": 0, "gravel": 0, "grass": 0}
	var slip_amount := 0.0
	var wheel_list: Variant = _read(vehicle, properties, "wheel_array", [])
	if wheel_list is Array:
		for item in wheel_list:
			if not (item is Object) or not is_instance_valid(item):
				continue
			var wheel: Object = item
			if not wheel.has_method("is_colliding") or not bool(wheel.call("is_colliding")):
				continue
			grounded = true
			var wheel_props := _property_names(wheel)
			var surface := _surface(str(_read(wheel, wheel_props, "surface_type", "Road")))
			surface_counts[surface] = int(surface_counts[surface]) + 1
			var raw_slip: Variant = _read(wheel, wheel_props, "slip_vector", Vector2.ZERO)
			if raw_slip is Vector2:
				# GEVP's x is a slip angle in radians; y is longitudinal wheel slip.
				var slip: Vector2 = raw_slip
				slip_amount = maxf(slip_amount, clampf(maxf(absf(slip.x) / 0.40, absf(slip.y) / 0.55), 0.0, 1.0))

	var surface := "asphalt"
	for name in ["gravel", "grass"]:
		if int(surface_counts[name]) > int(surface_counts[surface]):
			surface = name
	var combined_slip := clampf(maxf(slip_amount, lateral / 9.0), 0.0, 1.0)
	return {
		"rpm": float(_read(vehicle, properties, "motor_rpm", 1000.0)),
		"idle_rpm": float(_read(vehicle, properties, "idle_rpm", 950.0)),
		"max_rpm": float(_read(vehicle, properties, "max_rpm", 7100.0)),
		"throttle": throttle,
		# Keep the legacy pedal contract, but GEVP's actual motor pedal is
		# throttle_input in both forward and reverse (adapter swaps it).
		"engine_throttle": throttle_input,
		"shift_active": bool(_read(vehicle, properties, "is_shifting", false)),
		"requested_gear": int(_read(vehicle, properties, "requested_gear", gear)),
		"load": clampf(throttle + brake * 0.07, 0.0, 1.0),
		"gear": gear,
		"speed_mps": speed,
		"vertical_speed_mps": velocity.y,
		"forward_speed_mps": -velocity.dot(basis.z),
		"lateral_slip": combined_slip if grounded else 0.0,
		"slip_amount": combined_slip if grounded else 0.0,
		"grip": clampf(1.0 - combined_slip * 0.8, 0.0, 1.0),
		"on_ground": grounded,
		"surface": surface,
		"surface_counts": surface_counts,
		"handbrake": float(_read(vehicle, properties, "handbrake_input", 0.0)) > 0.3,
		"engine_braking": throttle < 0.08 and speed > 3.0,
	}


static func _stationary() -> Dictionary:
	return {"rpm": 950.0, "throttle": 0.0, "load": 0.0,
		"gear": 0, "speed_mps": 0.0, "forward_speed_mps": 0.0,
		"lateral_slip": 0.0, "grip": 1.0, "surface": "asphalt",
		"on_ground": false, "handbrake": false, "engine_braking": false}


static func _surface(raw: String) -> String:
	match raw.to_lower():
		"dirt", "gravel": return "gravel"
		"grass": return "grass"
		_: return "asphalt"


static func _read(object: Object, names: Dictionary, name: String, fallback: Variant) -> Variant:
	return object.get(name) if names.has(name) else fallback


static func _property_names(object: Object) -> Dictionary:
	var names := {}
	for info in object.get_property_list():
		names[str(info.get("name", ""))] = true
	return names
