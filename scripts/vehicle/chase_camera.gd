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

func get_mode_name() -> String:
	match mode:
		0:
			return "CHASE FAR"
		1:
			return "CHASE CLOSE"
		_:
			return "HOOD"

func snap_to_vehicle() -> void:
	if target == null:
		return
	global_position = _desired_position()
	look_at(_look_point(), _camera_up())

func _process(_delta: float) -> void:
	if target == null or mode != 2:
		return
	# Keep hood camera rigidly synced to the rendered vehicle transform with zero 1-frame lag.
	global_position = _desired_position()
	var focus := _look_point()
	if global_position.distance_squared_to(focus) > 0.05:
		look_at(focus, _camera_up())

func _physics_process(delta: float) -> void:
	if target == null:
		return
	var desired := _desired_position()
	var focus := _look_point()
	if mode == 2:
		# Hood view is rigidly mounted ahead of the windshield to prevent cabin clipping at speed.
		global_position = desired
		if global_position.distance_squared_to(focus) > 0.05:
			look_at(focus, _camera_up())
	else:
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
			var updated := global_transform
			updated.basis = updated.basis.slerp(goal.basis, 1.0 - exp(-9.0 * delta)).orthonormalized()
			global_transform = updated
	var speed := target.linear_velocity.length()
	var base_fov := 76.0 if mode == 2 else 70.0
	fov = lerpf(fov, base_fov + 13.0 * clampf(speed / 45.0, 0.0, 1.0), 1.0 - exp(-2.6 * delta))

func _camera_up() -> Vector3:
	if mode == 2:
		return target.global_basis.y.lerp(Vector3.UP, 0.65).normalized()
	return Vector3.UP

func _look_point() -> Vector3:
	if mode == 2:
		return target.to_global(Vector3(0.0, 0.70, -30.0))
	var lead := -target.global_basis.z * clampf(target.linear_velocity.length() * 0.09, 0.0, 3.0)
	var turn := target.global_basis.x * steer_hint * 1.5
	return target.global_position + Vector3.UP * 0.68 + lead + turn

func _desired_position() -> Vector3:
	if mode == 2:
		return target.to_global(Vector3(0.0, 0.86, -0.92))
	var distance := 6.3
	var height := 2.5
	if mode == 1:
		distance = 4.2
		height = 1.85
	return target.global_position + target.global_basis.z * distance + Vector3.UP * height
