class_name VehicleAdapter
extends RefCounted
## Stable public interface hiding GEVP-specific input and reset implementation.
var vehicle: Vehicle

func _init(body: Vehicle) -> void:
	vehicle = body

func set_drive_input(steer: float, throttle: float, brake: float, handbrake: bool) -> void:
	vehicle.steering_input = clampf(steer, -1.0, 1.0)
	var clamped_throttle := clampf(throttle, 0.0, 1.0)
	var clamped_brake := clampf(brake, 0.0, 1.0)
	if vehicle.current_gear == -1:
		# GEVP reverse uses swapped pedals, as in its shipped controller.
		vehicle.throttle_input = clamped_brake
		if clamped_throttle > 0.1 and get_forward_speed_mps() >= -0.8:
			# Ensure even partial analog throttle exits reverse cleanly past GEVP's 0.75 threshold.
			vehicle.brake_input = 1.0
		else:
			vehicle.brake_input = clamped_throttle
	else:
		vehicle.throttle_input = clamped_throttle
		if vehicle.current_gear <= 1 and clamped_brake > 0.25 and clamped_throttle < 0.05 and get_forward_speed_mps() <= 0.5:
			vehicle.brake_input = maxf(clamped_brake, 0.8)
		else:
			vehicle.brake_input = clamped_brake
	vehicle.handbrake_input = 1.0 if handbrake else 0.0
	vehicle.clutch_input = 0.0

func get_speed_mps() -> float:
	return vehicle.linear_velocity.length()

func get_forward_speed_mps() -> float:
	return -vehicle.linear_velocity.dot(vehicle.global_basis.z)

func get_gear_display() -> String:
	var gear: int = vehicle.current_gear
	if gear < 0:
		return "R"
	if gear == 0:
		return "N"
	return str(gear)

func reset_to(pose: Transform3D) -> void:
	vehicle.freeze = true
	vehicle.global_transform = pose
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.constant_force = Vector3.ZERO
	vehicle.constant_torque = Vector3.ZERO
	vehicle.local_velocity = Vector3.ZERO
	vehicle.previous_global_position = pose.origin
	vehicle.speed = 0.0
	vehicle.throttle_input = 0.0
	vehicle.steering_input = 0.0
	vehicle.brake_input = 0.0
	vehicle.handbrake_input = 0.0
	vehicle.throttle_amount = 0.0
	vehicle.brake_amount = 0.0
	vehicle.steering_amount = 0.0
	vehicle.true_steering_amount = 0.0
	vehicle.clutch_amount = 0.0
	vehicle.current_gear = 0
	vehicle.requested_gear = 0
	vehicle.is_shifting = false
	vehicle.is_up_shifting = false
	vehicle.motor_rpm = vehicle.idle_rpm
	vehicle.last_shift_delta_time = vehicle.delta_time - vehicle.shift_time
	for wheel in vehicle.wheel_array:
		wheel.steer(0.0, vehicle.max_steering_angle)
		wheel.spin = 0.0
		wheel.previous_compression = 0.0
		wheel.previous_global_position = wheel.global_position
	vehicle.freeze = false
	vehicle.sleeping = false
	vehicle.reset_physics_interpolation()
