class_name VehicleAdapter
extends RefCounted
## Stable public interface hiding GEVP-specific input and reset implementation.
var vehicle: Vehicle

func _init(body: Vehicle) -> void:
	vehicle = body

func set_drive_input(steer: float, throttle: float, brake: float, handbrake: bool) -> void:
	vehicle.steering_input = clampf(steer, -1.0, 1.0)
	vehicle.throttle_input = clampf(throttle, 0.0, 1.0)
	vehicle.brake_input = clampf(brake, 0.0, 1.0)
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
	for wheel in vehicle.wheel_array:
		wheel.spin = 0.0
		wheel.previous_compression = 0.0
		wheel.previous_global_position = wheel.global_position
	vehicle.freeze = false
	vehicle.sleeping = false
	vehicle.reset_physics_interpolation()
