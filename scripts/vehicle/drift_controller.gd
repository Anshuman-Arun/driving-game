class_name DriftController
extends Node
## Forza Horizon-style simcade drift physics controller layered cleanly over GEVP.
## - Low speed (< 3.5 m/s) without throttle: handbrake parks/holds the vehicle.
## - Driving speed (>= 4.0 m/s) + handbrake (A / Space): kicks the tail out into a
##   controllable high-momentum 18-38 deg drift instead of braking the car to a stop.
## - Active steer + throttle sustains the slide after releasing handbrake; releasing
##   handbrake & steering cleanly recovers straight-line traction (< 4 deg slip).

var vehicle: Vehicle
var is_drifting: bool = false
var drift_intensity: float = 0.0
var slip_angle_deg: float = 0.0
var drift_direction: float = 0.0

var _drift_blend: float = 0.0
var _handbrake_entry_t: float = 0.0
var _base_stability_yaw: float = 5.2
var _base_tcs_slip: float = 6.0
var _base_countersteer: float = 0.75
var _rear_wheels: Array[Wheel] = []
var _initialized: bool = false


func _ready() -> void:
	name = "DriftController"
	vehicle = get_parent() as Vehicle
	if vehicle != null:
		_capture_baselines()


func _capture_baselines() -> void:
	if _initialized or vehicle == null:
		return
	_base_stability_yaw = vehicle.stability_yaw_strength
	_base_tcs_slip = vehicle.traction_control_max_slip
	_base_countersteer = vehicle.countersteer_assist
	_rear_wheels = [vehicle.rear_left_wheel, vehicle.rear_right_wheel]
	_initialized = true


func reset() -> void:
	is_drifting = false
	drift_intensity = 0.0
	slip_angle_deg = 0.0
	drift_direction = 0.0
	_drift_blend = 0.0
	_handbrake_entry_t = 0.0
	if vehicle != null and _initialized:
		vehicle.handbrake_force_scale = 1.0
		vehicle.stability_yaw_strength = _base_stability_yaw
		vehicle.traction_control_max_slip = _base_tcs_slip
		vehicle.countersteer_assist = _base_countersteer


func _physics_process(delta: float) -> void:
	if vehicle == null or not vehicle.is_ready or vehicle.freeze:
		return
	_capture_baselines()

	var local_vel := vehicle.global_basis.inverse() * vehicle.linear_velocity
	var fwd_speed := -local_vel.z
	var planar_speed := Vector2(local_vel.x, local_vel.z).length()
	var slip_rad := atan2(local_vel.x, maxf(fwd_speed, 0.5)) if fwd_speed > 0.5 else 0.0
	slip_angle_deg = rad_to_deg(slip_rad)
	var abs_slip := absf(slip_angle_deg)

	var hb_held := vehicle.handbrake_input > 0.35
	var throttle := vehicle.throttle_input
	var steer := vehicle.steering_input
	var grounded := vehicle.get_wheel_contact_count() >= 3

	# 1. Low-speed / parked handbrake holds the car cleanly.
	if planar_speed < 3.5 and throttle < 0.15:
		vehicle.handbrake_force_scale = 1.0
		is_drifting = false
		_handbrake_entry_t = 0.0
		_blend_drift(0.0, delta)
		return

	# 2. Driving-speed handbrake initiates a true Forza drift (light rear tap, never a full stop).
	if hb_held and grounded and fwd_speed >= 3.8:
		_handbrake_entry_t = minf(_handbrake_entry_t + delta, 1.0)
		if throttle > 0.12:
			vehicle.handbrake_force_scale = 0.14 if _handbrake_entry_t < 0.16 else 0.06
		else:
			vehicle.handbrake_force_scale = 0.34
		if absf(steer) > 0.10 or abs_slip > 6.5:
			is_drifting = true
			if absf(steer) > 0.10:
				drift_direction = signf(steer)
			elif abs_slip > 4.0:
				drift_direction = signf(slip_angle_deg)
	else:
		_handbrake_entry_t = 0.0
		vehicle.handbrake_force_scale = 1.0
		# Sustain drift ONLY while player actively steers + applies throttle at drift slip angle.
		# Releasing both handbrake and steering exits drift immediately for crisp recovery!
		if is_drifting:
			var sustain := grounded and fwd_speed > 5.0 and throttle > 0.15 and absf(steer) > 0.10 and abs_slip > 9.0
			if not sustain:
				is_drifting = false

	# 3. Smoothly blend rear grip & GEVP stability/TCS parameters (front wheels stay untouched!).
	var target_blend := 1.0 if is_drifting else 0.0
	_blend_drift(target_blend, delta)

	if not grounded or fwd_speed < 3.0:
		drift_intensity = lerpf(drift_intensity, 0.0, 1.0 - exp(-8.0 * delta))
		return

	# 4. Forza-style drift yaw initiation, momentum preservation, angle governor, and clean recovery.
	var inertia_y := maxf(vehicle.vehicle_inertia.y, 1800.0)
	var up := vehicle.global_basis.y
	var yaw_rate := vehicle.angular_velocity.dot(up)

	if is_drifting:
		if abs_slip > 4.0:
			drift_direction = signf(slip_angle_deg)
		var speed_factor := clampf((fwd_speed - 3.5) / 13.0, 0.35, 1.35)

		# (a) Crisp yaw initiation torque when handbrake + steer are applied (reaches 18-32 deg cleanly!)
		if hb_held and absf(steer) > 0.08:
			var angle_headroom := clampf(1.0 - abs_slip / 36.0, 0.12, 1.0)
			var init_torque := steer * 6.8 * inertia_y * speed_factor * angle_headroom
			vehicle.apply_torque(up * init_torque)

		# (b) Throttle-sustained power-slide assist when actively steering into the corner
		if throttle > 0.15 and absf(steer) > 0.10 and abs_slip >= 7.0 and abs_slip <= 38.0:
			var same_dir := 1.0 if signf(steer) == drift_direction else -0.35
			if same_dir > 0.0:
				var sustain_torque := signf(steer) * throttle * 2.2 * inertia_y * clampf(1.0 - abs_slip / 40.0, 0.0, 1.0)
				vehicle.apply_torque(up * sustain_torque)

		# (c) Preserve forward momentum during high-angle power slides so drifting feels fast & fluid
		if throttle > 0.15:
			var forward_dir := -vehicle.global_basis.z
			var push_strength := vehicle.mass * 3.6 * throttle * clampf(maxf(abs_slip / 20.0, 0.35 if hb_held else 0.0), 0.25, 1.0)
			vehicle.apply_central_force(forward_dir * push_strength)

		# (d) Forza Drift Angle Governor: cap/damp yaw past 34-46 deg to prevent spinouts
		if abs_slip > 34.0:
			var excess := (abs_slip - 34.0) / 14.0
			var restore_torque := -signf(slip_angle_deg) * excess * 5.4 * inertia_y
			vehicle.apply_torque(up * restore_torque)
		if abs_slip > 22.0 and signf(yaw_rate) == signf(slip_angle_deg):
			var damp := -yaw_rate * clampf((abs_slip - 22.0) / 18.0, 0.0, 1.0) * 2.4 * inertia_y
			vehicle.apply_torque(up * damp)

		var target_intensity := clampf(maxf(abs_slip / 24.0, 0.55 if hb_held else 0.0), 0.0, 1.0)
		drift_intensity = lerpf(drift_intensity, target_intensity, 1.0 - exp(-10.0 * delta))
	else:
		# Clean, decisive straight-line recovery when handbrake & steering are released!
		if abs_slip > 2.5 and absf(steer) <= 0.12:
			var align_torque := -signf(slip_angle_deg) * clampf(abs_slip / 14.0, 0.0, 1.5) * 3.6 * inertia_y
			var damp_torque := -yaw_rate * 3.4 * inertia_y
			vehicle.apply_torque(up * (align_torque + damp_torque))
		drift_intensity = lerpf(drift_intensity, 0.0, 1.0 - exp(-12.0 * delta))


func _blend_drift(target: float, delta: float) -> void:
	# Enter crisp (~0.15s), recover fast (~0.20s) while keeping front wheels 100% untouched.
	var rate := 6.5 if target > _drift_blend else 5.0
	_drift_blend = move_toward(_drift_blend, target, rate * delta)

	vehicle.stability_yaw_strength = lerpf(_base_stability_yaw, 0.45, _drift_blend)
	vehicle.traction_control_max_slip = -1.0 if _drift_blend > 0.20 else _base_tcs_slip
	vehicle.countersteer_assist = lerpf(_base_countersteer, 0.92, _drift_blend)

	# Drop REAR lateral grip & stiffness during drift; restore smoothly on exit.
	if _drift_blend > 0.001:
		for w in _rear_wheels:
			if w == null or w.surface_type.is_empty():
				continue
			var base_cof: float = vehicle.coefficient_of_friction.get(w.surface_type, 2.0)
			var base_stiff: float = 1000000.0 + 8000000.0 * float(vehicle.tire_stiffnesses.get(w.surface_type, 5.0))
			var target_cof := base_cof * lerpf(1.0, 0.36, _drift_blend)
			var target_stiff := base_stiff * lerpf(1.0, 0.22, _drift_blend)
			w.current_cof = move_toward(w.current_cof, target_cof, 8.0 * delta)
			w.current_tire_stiffness = lerpf(w.current_tire_stiffness, target_stiff, 1.0 - exp(-14.0 * delta))
			w.current_lateral_grip_assist = lerpf(float(vehicle.lateral_grip_assist.get(w.surface_type, 0.0)), 0.0, _drift_blend)
