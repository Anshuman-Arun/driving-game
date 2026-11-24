class_name DeterministicTelemetryTestBench
extends RefCounted
## Deterministic telemetry test bench for Aster Valley vehicle audio QA.
## Generates repeatable, frame-by-frame physics/telemetry vectors across all driving regimes:
## - Simulates 3 car profiles: Vela GT (flat-six), Kestrel XR (V8), Orion RS (4-cylinder fallback)
## - Sweeps RPM from idle to redline
## - Tests throttle transitions (tip-in, steady, lift-off, overrun triggers)
## - Tests gear shifts (1st -> 2nd -> 3rd -> 4th with torque-cut envelopes)
## - Tests reverse gear maneuver and pedal inversion
## - Tests surface transitions (asphalt -> gravel -> grass -> asphalt)
## - Tests jumps and landings (airborne roll fade, landing thump & compression)
## - Tests acoustic wall proximity & raycast reflections (tunnel/canyon clearance)
## - Tests high speed wind ramp (onset >22 m/s)
## - Tests tire scrub (slip 0.15-0.45), screech (>0.45), and stationary gating
## - Tests camera perspective switching (chase -> cockpit -> chase)

# --- Car Profile Constants ---
const CAR_PROFILES := {
	"aventador_svj": {
		"name": "Aventador SVJ", "engine_type": "v12", "idle_rpm": 900.0,
		"max_rpm": 8700.0, "top_speed_mps": 95.0,
		"gears": [-1, 0, 1, 2, 3, 4, 5, 6, 7],
		"gear_ratios": [3.2, 0.0, 3.75, 2.38, 1.72, 1.34, 1.11, 0.96, 0.84],
		"final_drive": 3.52, "mass_kg": 1670.0
	},
	"mclaren_senna": {
		"name": "McLaren Senna", "engine_type": "twin_turbo_v8", "idle_rpm": 980.0,
		"max_rpm": 8000.0, "top_speed_mps": 90.0,
		"gears": [-1, 0, 1, 2, 3, 4, 5, 6, 7],
		"gear_ratios": [3.2, 0.0, 3.75, 2.38, 1.72, 1.34, 1.11, 0.96, 0.84],
		"final_drive": 3.31, "mass_kg": 1380.0
	},
	"vela_gt": {
		"name": "Vela GT",
		"engine_type": "flat_six",
		"idle_rpm": 950.0,
		"max_rpm": 8500.0,
		"top_speed_mps": 85.0,
		"gears": [-1, 0, 1, 2, 3, 4, 5, 6, 7],
		"gear_ratios": [3.2, 0.0, 3.75, 2.38, 1.72, 1.34, 1.11, 0.96, 0.84],
		"final_drive": 3.44,
		"mass_kg": 1430.0
	},
	"kestrel_xr": {
		"name": "Kestrel XR",
		"engine_type": "v8",
		"idle_rpm": 800.0,
		"max_rpm": 7800.0,
		"top_speed_mps": 95.0,
		"gears": [-1, 0, 1, 2, 3, 4, 5, 6, 7],
		"gear_ratios": [3.4, 0.0, 3.98, 2.61, 1.90, 1.48, 1.16, 0.91, 0.76],
		"final_drive": 3.31,
		"mass_kg": 1380.0
	},
	"orion_rs": {
		"name": "Orion RS",
		"engine_type": "four_cyl",
		"idle_rpm": 1000.0,
		"max_rpm": 8000.0,
		"top_speed_mps": 65.0,
		"gears": [-1, 0, 1, 2, 3, 4, 5, 6],
		"gear_ratios": [3.1, 0.0, 3.42, 2.14, 1.48, 1.12, 0.89, 0.73],
		"final_drive": 4.10,
		"mass_kg": 1240.0
	}
}

# --- Scenario Schedule (seconds) ---
const SCENARIO_IDLE_END := 1.0
const SCENARIO_RPM_SWEEP_END := 5.0
const SCENARIO_THROTTLE_END := 8.0
const SCENARIO_GEAR_SHIFTS_END := 11.5
const SCENARIO_REVERSE_END := 14.0
const SCENARIO_SURFACES_END := 17.5
const SCENARIO_JUMP_LANDING_END := 20.5
const SCENARIO_WALL_PROXIMITY_END := 23.5
const SCENARIO_HIGH_SPEED_WIND_END := 26.5
const SCENARIO_SLIP_BRAKING_END := 29.5
const SCENARIO_CAMERA_PERSPECTIVE_END := 31.0

const TOTAL_BENCH_DURATION := SCENARIO_CAMERA_PERSPECTIVE_END

var profile_name: String = "vela_gt"
var profile_data: Dictionary = {}
var tick_rate: float = 60.0
var delta: float = 1.0 / 60.0
var current_time: float = 0.0
var current_frame: int = 0

# Telemetry internal states
var _current_gear: int = 1
var _current_rpm: float = 950.0
var _current_speed_mps: float = 0.0
var _current_throttle: float = 0.0
var _current_surface: String = "asphalt"
var _is_on_ground: bool = true
var _lateral_slip: float = 0.0
var _suspension_compression: float = 0.30
var _wall_distance: float = 20.0
var _camera_mode: String = "chase"


func _init(car_profile: String = "vela_gt", target_tick_rate: float = 60.0) -> void:
	init_profile(car_profile, target_tick_rate)


## Initializes or resets the bench for a specific car profile.
func init_profile(car_profile: String, target_tick_rate: float = 60.0) -> void:
	profile_name = car_profile if CAR_PROFILES.has(car_profile) else "vela_gt"
	profile_data = CAR_PROFILES[profile_name]
	tick_rate = maxf(target_tick_rate, 10.0)
	delta = 1.0 / tick_rate
	reset()


## Resets the simulation to t=0.
func reset() -> void:
	current_time = 0.0
	current_frame = 0
	_current_gear = 1
	_current_rpm = float(profile_data.get("idle_rpm", 950.0))
	_current_speed_mps = 0.0
	_current_throttle = 0.0
	_current_surface = "asphalt"
	_is_on_ground = true
	_lateral_slip = 0.0
	_suspension_compression = 0.30
	_wall_distance = 20.0
	_camera_mode = "chase"


## Advances the bench by one step and returns the comprehensive telemetry dictionary.
func step() -> Dictionary:
	var t := current_time
	var idle_rpm: float = float(profile_data["idle_rpm"])
	var max_rpm: float = float(profile_data["max_rpm"])
	var top_speed: float = float(profile_data["top_speed_mps"])

	var scenario_name := ""
	var scenario_index := 0
	var brake_input := 0.0
	var handbrake_input := false
	var impact_velocity := 0.0
	var spring_delta := 0.0
	var vertical_speed := 0.0

	# -------------------------------------------------------------
	# 1. IDLE STATIONARY (0.0s -> 1.0s)
	# -------------------------------------------------------------
	if t < SCENARIO_IDLE_END:
		scenario_name = "idle_stationary"
		scenario_index = 1
		_current_gear = 0
		_current_throttle = 0.0
		_current_rpm = idle_rpm
		_current_speed_mps = 0.0
		_current_surface = "asphalt"
		_is_on_ground = true
		_lateral_slip = 0.0
		_wall_distance = 20.0
		_camera_mode = "chase"

	# -------------------------------------------------------------
	# 2. RPM SWEEP IDLE TO REDLINE (1.0s -> 5.0s)
	# -------------------------------------------------------------
	elif t < SCENARIO_RPM_SWEEP_END:
		scenario_name = "rpm_sweep_idle_to_redline"
		scenario_index = 2
		_current_gear = 2
		var p: float = (t - SCENARIO_IDLE_END) / (SCENARIO_RPM_SWEEP_END - SCENARIO_IDLE_END)
		_current_throttle = 1.0
		_current_rpm = lerpf(idle_rpm, max_rpm, p)
		_current_speed_mps = lerpf(5.0, top_speed * 0.45, p)
		_current_surface = "asphalt"
		_is_on_ground = true
		_lateral_slip = 0.0
		_wall_distance = 20.0

	# -------------------------------------------------------------
	# 3. THROTTLE TRANSITIONS (5.0s -> 8.0s)
	# -------------------------------------------------------------
	elif t < SCENARIO_THROTTLE_END:
		scenario_name = "throttle_transitions"
		scenario_index = 3
		_current_gear = 3
		var rel_t: float = t - SCENARIO_RPM_SWEEP_END
		if rel_t < 0.6:
			# Sudden lift-off at high RPM (overrun backfire trigger)
			_current_throttle = 0.0
			_current_rpm = lerpf(max_rpm * 0.85, max_rpm * 0.60, rel_t / 0.6)
		elif rel_t < 1.4:
			# Sudden tip-in (throttle 0 -> 1)
			_current_throttle = 1.0
			_current_rpm = lerpf(max_rpm * 0.60, max_rpm * 0.88, (rel_t - 0.6) / 0.8)
		elif rel_t < 2.0:
			# Rapid lift-off again
			_current_throttle = 0.0
			_current_rpm = lerpf(max_rpm * 0.88, max_rpm * 0.55, (rel_t - 1.4) / 0.6)
		else:
			# Rapid blips
			var blip: float = sin((rel_t - 2.0) * PI * 4.0)
			_current_throttle = clampf(blip, 0.0, 1.0)
			_current_rpm = lerpf(max_rpm * 0.55, max_rpm * 0.75, _current_throttle)
		_current_speed_mps = top_speed * 0.40

	# -------------------------------------------------------------
	# 4. GEAR SHIFTS (8.0s -> 11.5s)
	# -------------------------------------------------------------
	elif t < SCENARIO_GEAR_SHIFTS_END:
		scenario_name = "gear_shifts"
		scenario_index = 4
		var rel_t: float = t - SCENARIO_THROTTLE_END
		if rel_t < 1.1:
			_current_gear = 2
			_current_throttle = 1.0
			_current_rpm = lerpf(idle_rpm + 2000.0, max_rpm * 0.95, rel_t / 1.1)
		elif rel_t < 1.25:
			# Shift to 3rd (torque cut clunk)
			_current_gear = 3
			_current_throttle = 0.1
			_current_rpm = max_rpm * 0.65
		elif rel_t < 2.3:
			_current_gear = 3
			_current_throttle = 1.0
			_current_rpm = lerpf(max_rpm * 0.65, max_rpm * 0.92, (rel_t - 1.25) / 1.05)
		elif rel_t < 2.45:
			# Shift to 4th (torque cut clunk)
			_current_gear = 4
			_current_throttle = 0.1
			_current_rpm = max_rpm * 0.68
		else:
			_current_gear = 4
			_current_throttle = 1.0
			_current_rpm = lerpf(max_rpm * 0.68, max_rpm * 0.88, (rel_t - 2.45) / 1.05)
		_current_speed_mps = lerpf(top_speed * 0.35, top_speed * 0.65, rel_t / 3.5)

	# -------------------------------------------------------------
	# 5. REVERSE MANEUVER (11.5s -> 14.0s)
	# -------------------------------------------------------------
	elif t < SCENARIO_REVERSE_END:
		scenario_name = "reverse_maneuver"
		scenario_index = 5
		var rel_t: float = t - SCENARIO_GEAR_SHIFTS_END
		if rel_t < 0.6:
			# Braking to stop
			_current_gear = 1
			_current_throttle = 0.0
			brake_input = 1.0
			_current_speed_mps = lerpf(20.0, 0.0, rel_t / 0.6)
			_current_rpm = lerpf(3000.0, idle_rpm, rel_t / 0.6)
		else:
			# Reverse gear engaged
			_current_gear = -1
			var rev_p: float = (rel_t - 0.6) / 1.9
			_current_throttle = clampf(rev_p * 1.2, 0.0, 0.85)
			_current_rpm = lerpf(idle_rpm, max_rpm * 0.55, rev_p)
			_current_speed_mps = lerpf(0.0, 14.0, rev_p)

	# -------------------------------------------------------------
	# 6. SURFACE TRANSITIONS (14.0s -> 17.5s)
	# -------------------------------------------------------------
	elif t < SCENARIO_SURFACES_END:
		scenario_name = "surface_transitions"
		scenario_index = 6
		_current_gear = 3
		_current_throttle = 0.6
		_current_rpm = idle_rpm + 3200.0
		_current_speed_mps = 24.0
		var rel_t: float = t - SCENARIO_REVERSE_END
		if rel_t < 1.0:
			_current_surface = "asphalt"
		elif rel_t < 2.0:
			_current_surface = "gravel"
		elif rel_t < 2.8:
			_current_surface = "grass"
		else:
			_current_surface = "asphalt"

	# -------------------------------------------------------------
	# 7. JUMPS AND LANDINGS (17.5s -> 20.5s)
	# -------------------------------------------------------------
	elif t < SCENARIO_JUMP_LANDING_END:
		scenario_name = "jumps_and_landings"
		scenario_index = 7
		_current_gear = 4
		_current_speed_mps = 36.0
		var rel_t: float = t - SCENARIO_SURFACES_END
		if rel_t < 0.4:
			# Ramp approach
			_is_on_ground = true
			_current_throttle = 0.9
			_current_rpm = max_rpm * 0.70
			_suspension_compression = 0.35
		elif rel_t < 1.8:
			# In the air (wheels unloaded, roll loops fade out)
			_is_on_ground = false
			_current_throttle = 0.2
			_current_rpm = lerpf(max_rpm * 0.70, idle_rpm + 1500.0, (rel_t - 0.4) / 1.4)
			_suspension_compression = 0.05
			spring_delta = -0.30
			vertical_speed = lerpf(5.0, -8.5, (rel_t - 0.4) / 1.4)
		elif rel_t < 2.1:
			# Heavy touchdown impact!
			_is_on_ground = true
			_current_throttle = 0.5
			_current_rpm = idle_rpm + 2500.0
			_suspension_compression = 0.95
			spring_delta = 1.2
			impact_velocity = 8.5
		else:
			# Settling back
			_is_on_ground = true
			_current_throttle = 0.7
			_current_rpm = idle_rpm + 3500.0
			_suspension_compression = lerpf(0.95, 0.30, (rel_t - 2.1) / 0.9)

	# -------------------------------------------------------------
	# 8. WALL PROXIMITY & ACOUSTIC REFLECTIONS (20.5s -> 23.5s)
	# -------------------------------------------------------------
	elif t < SCENARIO_WALL_PROXIMITY_END:
		scenario_name = "wall_proximity"
		scenario_index = 8
		_current_gear = 3
		_current_throttle = 0.75
		_current_rpm = idle_rpm + 3800.0
		_current_speed_mps = 28.0
		_is_on_ground = true
		_current_surface = "asphalt"
		var rel_t: float = t - SCENARIO_JUMP_LANDING_END
		if rel_t < 0.6:
			# Approaching wall: 20m down to 2.0m
			_wall_distance = lerpf(20.0, 2.0, rel_t / 0.6)
		elif rel_t < 1.8:
			# Driving along concrete tunnel/wall at 2.0m
			_wall_distance = 2.0 + 0.3 * sin(rel_t * 6.0)
		elif rel_t < 2.4:
			# Exiting wall into open canyon: 2.0m up to 20m
			_wall_distance = lerpf(2.0, 20.0, (rel_t - 1.8) / 0.6)
		else:
			_wall_distance = 20.0

	# -------------------------------------------------------------
	# 9. HIGH SPEED WIND (23.5s -> 26.5s)
	# -------------------------------------------------------------
	elif t < SCENARIO_HIGH_SPEED_WIND_END:
		scenario_name = "high_speed_wind"
		scenario_index = 9
		_current_gear = 6
		_current_throttle = 1.0
		_is_on_ground = true
		_wall_distance = 20.0
		var rel_t: float = t - SCENARIO_WALL_PROXIMITY_END
		var p: float = rel_t / 3.0
		# Speed accelerates from 20 m/s past the 22 m/s wind onset up to 72 m/s
		_current_speed_mps = lerpf(20.0, top_speed * 0.85, p)
		_current_rpm = lerpf(idle_rpm + 3000.0, max_rpm * 0.95, p)

	# -------------------------------------------------------------
	# 10. LATERAL SLIP AND BRAKING (26.5s -> 29.5s)
	# -------------------------------------------------------------
	elif t < SCENARIO_SLIP_BRAKING_END:
		scenario_name = "lateral_slip_and_braking"
		scenario_index = 10
		_current_gear = 3
		var rel_t: float = t - SCENARIO_HIGH_SPEED_WIND_END
		if rel_t < 0.8:
			# Moderate slip: 0.28 (tire scrub band 0.15 - 0.45)
			_current_throttle = 0.4
			_current_speed_mps = 25.0
			_lateral_slip = 0.28
			_current_rpm = idle_rpm + 2800.0
		elif rel_t < 2.0:
			# Severe slip: 0.65 (screech band > 0.45)
			_current_throttle = 0.8
			_current_speed_mps = 28.0
			_lateral_slip = 0.65
			_current_rpm = idle_rpm + 4800.0
		else:
			# Hard braking to stationary (< 1.5 m/s) to verify zero stationary squeal
			_current_throttle = 0.0
			brake_input = 1.0
			var decel_p: float = (rel_t - 2.0) / 1.0
			_current_speed_mps = lerpf(28.0, 0.0, decel_p)
			_lateral_slip = lerpf(0.65, 0.0, decel_p)
			_current_rpm = lerpf(idle_rpm + 4800.0, idle_rpm, decel_p)

	# -------------------------------------------------------------
	# 11. CAMERA PERSPECTIVE SWITCHING (29.5s -> 31.0s)
	# -------------------------------------------------------------
	else:
		scenario_name = "camera_perspective_switching"
		scenario_index = 11
		_current_gear = 2
		_current_throttle = 0.5
		_current_rpm = idle_rpm + 2500.0
		_current_speed_mps = 18.0
		_is_on_ground = true
		_lateral_slip = 0.0
		_wall_distance = 20.0
		var rel_t: float = t - SCENARIO_SLIP_BRAKING_END
		if rel_t < 0.5:
			_camera_mode = "chase"
		elif rel_t < 1.0:
			# Switch to cockpit view (muffles exterior, emphasizes intake)
			_camera_mode = "cockpit"
		else:
			# Return to chase view
			_camera_mode = "chase"

	# Construct normalized surface weights
	var surf_weights := {"asphalt": 0.0, "gravel": 0.0, "grass": 0.0}
	surf_weights[_current_surface] = 1.0 if _is_on_ground else 0.0

	var forward_speed := -_current_speed_mps if _current_gear == -1 else _current_speed_mps
	var load_val: float = clampf(_current_throttle + brake_input * 0.1, 0.0, 1.0)
	var grip_val: float = clampf(1.0 - _lateral_slip * 0.85, 0.0, 1.0)

	var telemetry := {
		"time": t,
		"frame": current_frame,
		"scenario": scenario_name,
		"scenario_index": scenario_index,
		"car_profile": profile_name,
		"rpm": _current_rpm,
		"idle_rpm": idle_rpm,
		"max_rpm": max_rpm,
		"throttle": _current_throttle,
		"load": load_val,
		"brake": brake_input,
		"gear": _current_gear,
		"speed_mps": _current_speed_mps,
		"vertical_speed_mps": vertical_speed,
		"forward_speed_mps": forward_speed,
		"lateral_slip": _lateral_slip,
		"slip_amount": _lateral_slip,
		"grip": grip_val,
		"on_ground": _is_on_ground,
		"surface": _current_surface,
		"surface_weights": surf_weights,
		"handbrake": handbrake_input,
		"engine_braking": (_current_throttle < 0.05 and _current_speed_mps > 5.0),
		"wall_distance": _wall_distance,
		"raycast_left_dist": _wall_distance,
		"raycast_right_dist": 20.0,
		"raycast_distances": [_wall_distance, 20.0, 20.0],
		"suspension_compression": _suspension_compression,
		"spring_delta": spring_delta,
		"impact_velocity": impact_velocity,
		"collision_force": impact_velocity * float(profile_data["mass_kg"]),
		"camera_mode": _camera_mode,
		"is_cockpit": (_camera_mode == "cockpit")
	}

	current_time += delta
	current_frame += 1

	return telemetry


## Checks if the entire bench duration has elapsed.
func is_finished() -> bool:
	return current_time >= TOTAL_BENCH_DURATION


## Returns the total duration of the test bench run in seconds.
func get_total_duration() -> float:
	return TOTAL_BENCH_DURATION


## Returns the total number of frames in a complete run.
func get_total_frames() -> int:
	return int(round(TOTAL_BENCH_DURATION * tick_rate))
