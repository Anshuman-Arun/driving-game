class_name AsterTireTelemetry
extends RefCounted
## Telemetry extraction and normalization for recorded tire audio.
## Supports both live GEVP Vehicle nodes and normalized telemetry dictionaries.

const SURFACE_ASPHALT := "asphalt"
const SURFACE_GRAVEL := "gravel"
const SURFACE_GRASS := "grass"

## Convert raw surface string into normalized category ("asphalt", "gravel", "grass").
static func normalize_surface(raw: String) -> String:
	match raw.to_lower().strip_edges():
		"gravel", "dirt", "sand", "rock", "offroad":
			return SURFACE_GRAVEL
		"grass", "mud", "turf", "vegetation":
			return SURFACE_GRASS
		_:
			return SURFACE_ASPHALT


## Extract tire telemetry from a GEVP Vehicle node (or any vehicle with wheel_array).
static func from_vehicle(vehicle: Node) -> Dictionary:
	if not is_instance_valid(vehicle):
		return fallback()

	var speed := 0.0
	var forward_speed := 0.0
	if vehicle is RigidBody3D:
		var rb := vehicle as RigidBody3D
		var vel := rb.linear_velocity
		speed = vel.length()
		forward_speed = -vel.dot(vehicle.global_basis.z)
	elif "linear_velocity" in vehicle:
		var vel: Variant = vehicle.get("linear_velocity")
		if vel is Vector3:
			speed = (vel as Vector3).length()
			forward_speed = -(vel as Vector3).dot(vehicle.global_basis.z)
	elif "speed" in vehicle:
		speed = float(vehicle.get("speed"))

	var wheel_list: Variant = vehicle.get("wheel_array") if "wheel_array" in vehicle else null
	if not (wheel_list is Array):
		return {
			"speed_mps": speed,
			"forward_speed_mps": forward_speed,
			"slip_amount": 0.0,
			"on_ground": true,
			"grounded_count": 4,
			"surface": SURFACE_ASPHALT,
			"surface_weights": {SURFACE_ASPHALT: 1.0, SURFACE_GRAVEL: 0.0, SURFACE_GRASS: 0.0},
		}

	var grounded_count := 0
	var surface_counts := {SURFACE_ASPHALT: 0, SURFACE_GRAVEL: 0, SURFACE_GRASS: 0}
	var max_slip := 0.0
	var sum_slip := 0.0

	for item in (wheel_list as Array):
		if not (item is Object) or not is_instance_valid(item):
			continue
		var wheel: Object = item
		var colliding := false
		if wheel.has_method("is_colliding"):
			colliding = bool(wheel.call("is_colliding"))
		elif "is_colliding" in wheel:
			colliding = bool(wheel.get("is_colliding"))

		if not colliding:
			continue

		grounded_count += 1
		var raw_surface := str(wheel.get("surface_type")) if "surface_type" in wheel else "Road"
		var surf := normalize_surface(raw_surface)
		surface_counts[surf] = int(surface_counts[surf]) + 1

		# Slip vector calculation
		# GEVP: slip_vector.x is lateral slip angle (radians, ~0.40 rad = ~23 deg for full slip)
		# GEVP: slip_vector.y is longitudinal slip ratio (~0.55 for full slip)
		var w_slip := 0.0
		var raw_slip: Variant = wheel.get("slip_vector") if "slip_vector" in wheel else null
		if raw_slip is Vector2:
			var s: Vector2 = raw_slip
			var lateral_norm := absf(s.x) / 0.40
			var long_norm := absf(s.y) / 0.55
			w_slip = clampf(maxf(lateral_norm, long_norm), 0.0, 1.0)
		elif "slip" in wheel:
			w_slip = clampf(float(wheel.get("slip")), 0.0, 1.0)

		max_slip = maxf(max_slip, w_slip)
		sum_slip += w_slip

	var on_ground := grounded_count > 0
	var avg_slip := (sum_slip / float(grounded_count)) if grounded_count > 0 else 0.0
	# Emphasize the highest slipping wheel (e.g. drive axle burnout or outside slide)
	var combined_slip := lerpf(avg_slip, max_slip, 0.70) if on_ground else 0.0

	# Calculate surface distribution
	var weights := {SURFACE_ASPHALT: 0.0, SURFACE_GRAVEL: 0.0, SURFACE_GRASS: 0.0}
	var primary_surface := SURFACE_ASPHALT
	if grounded_count > 0:
		for s in weights.keys():
			weights[s] = float(surface_counts[s]) / float(grounded_count)
		for s in [SURFACE_GRAVEL, SURFACE_GRASS]:
			if int(surface_counts[s]) > int(surface_counts[primary_surface]):
				primary_surface = s
	else:
		weights[SURFACE_ASPHALT] = 1.0

	return {
		"speed_mps": speed,
		"forward_speed_mps": forward_speed,
		"slip_amount": combined_slip,
		"on_ground": on_ground,
		"grounded_count": grounded_count,
		"surface": primary_surface,
		"surface_weights": weights,
	}


## Normalize arbitrary telemetry dictionary (from AsterAudioTelemetry, QA harness, etc.).
static func from_dictionary(t: Dictionary) -> Dictionary:
	var speed := 0.0
	if t.has("speed_mps"):
		speed = maxf(0.0, float(t["speed_mps"]))
	elif t.has("speed"):
		speed = maxf(0.0, float(t["speed"]))

	var forward_speed := float(t.get("forward_speed_mps", speed))
	var on_ground := bool(t.get("on_ground", t.get("grounded", true)))

	# Determine slip amount
	var slip := 0.0
	if t.has("slip_amount"):
		slip = clampf(float(t["slip_amount"]), 0.0, 1.0)
	elif t.has("lateral_slip"):
		slip = clampf(float(t["lateral_slip"]), 0.0, 1.0)
	elif t.has("slip"):
		slip = clampf(float(t["slip"]), 0.0, 1.0)
	elif t.has("slip_vector") and t["slip_vector"] is Vector2:
		var v: Vector2 = t["slip_vector"]
		slip = clampf(maxf(absf(v.x) / 0.40, absf(v.y) / 0.55), 0.0, 1.0)
	elif t.has("grip"):
		slip = clampf(1.0 - float(t["grip"]), 0.0, 1.0)

	# Surface handling
	var surface_str := str(t.get("surface", SURFACE_ASPHALT))
	var primary_surface := normalize_surface(surface_str)

	var weights := {SURFACE_ASPHALT: 0.0, SURFACE_GRAVEL: 0.0, SURFACE_GRASS: 0.0}
	if t.has("surface_weights") and t["surface_weights"] is Dictionary:
		var raw_w: Dictionary = t["surface_weights"]
		for s in weights.keys():
			weights[s] = clampf(float(raw_w.get(s, 0.0)), 0.0, 1.0)
	elif t.has("surface_counts") and t["surface_counts"] is Dictionary:
		var counts: Dictionary = t["surface_counts"]
		var total := 0.0
		for s in weights.keys():
			total += maxf(0.0, float(counts.get(s, 0)))
		if total > 0.0:
			for s in weights.keys():
				weights[s] = maxf(0.0, float(counts.get(s, 0))) / total
		else:
			weights[primary_surface] = 1.0
	else:
		weights[primary_surface] = 1.0

	var grounded_count := int(t.get("grounded_count", 4 if on_ground else 0))

	return {
		"speed_mps": speed,
		"forward_speed_mps": forward_speed,
		"slip_amount": slip if on_ground else 0.0,
		"on_ground": on_ground,
		"grounded_count": grounded_count,
		"surface": primary_surface,
		"surface_weights": weights,
	}


## Default stationary / offline telemetry.
static func fallback() -> Dictionary:
	return {
		"speed_mps": 0.0,
		"forward_speed_mps": 0.0,
		"slip_amount": 0.0,
		"on_ground": true,
		"grounded_count": 4,
		"surface": SURFACE_ASPHALT,
		"surface_weights": {SURFACE_ASPHALT: 1.0, SURFACE_GRAVEL: 0.0, SURFACE_GRASS: 0.0},
	}
