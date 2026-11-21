class_name DrivingChaseCamera
extends Camera3D
## Collision-aware, speed-responsive camera; physical ground prevents clipping.
var target: RigidBody3D
var steer_hint := 0.0
var mode := 0

func setup(car: RigidBody3D) -> void:
	target = car
	current = true
	fov = 72.0
	far = 900.0
	snap_to_vehicle()

func cycle() -> void:
	mode = (mode + 1) % 3
	snap_to_vehicle()

func snap_to_vehicle() -> void:
	if target == null:
		return
	global_position = _desired_position()
	look_at(_look_point(), Vector3.UP)

func _physics_process(delta: float) -> void:
	if target == null:
		return
	var desired := _desired_position()
	var focus := _look_point()
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(focus, desired)
	params.exclude = [target.get_rid()]
	params.collision_mask = 1
	var hit := space.intersect_ray(params)
	if not hit.is_empty():
		desired = focus.lerp(hit.position, 0.88)
	var alpha := 1.0 - exp(-6.0 * delta)
	global_position = global_position.lerp(desired, alpha)
	# Avoid pitching with vehicle roll; the horizon remains level on rough ground.
	if global_position.distance_squared_to(focus) > 0.05:
		var goal := global_transform.looking_at(focus, Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(goal.basis, 1.0 - exp(-9.0 * delta)).orthonormalized()
	var speed := target.linear_velocity.length()
	fov = lerpf(fov, 70.0 + 13.0 * clampf(speed / 45.0, 0.0, 1.0), 1.0 - exp(-2.6 * delta))

func _look_point() -> Vector3:
	var lead := -target.global_basis.z * clampf(target.linear_velocity.length() * 0.09, 0.0, 3.0)
	var turn := target.global_basis.x * steer_hint * 1.5
	return target.global_position + Vector3.UP * 0.68 + lead + turn

func _desired_position() -> Vector3:
	var distance := 6.3
	var height := 2.6
	if mode == 1:
		distance = 3.8
		height = 1.55
	elif mode == 2:
		distance = 0.7
		height = 0.90
	return target.global_position + target.global_basis.z * distance + Vector3.UP * height
