class_name DrivingChaseCamera
extends Camera3D
## Both views follow the rendered chassis. Chase clearance is sampled on physics ticks.

const HOOD_MOUNT := Vector3(0.0, 0.86, -0.92)
const HOOD_FOCUS := Vector3(0.0, 0.70, -30.0)
const CHASE_PIVOT := Vector3.UP * 0.68

var target: RigidBody3D
var mode := 0
var _yaw := 0.0
var _previous_yaw := 0.0
var _speed := 0.0
var _previous_speed := 0.0
var _clearance := 1.0
var _previous_clearance := 1.0
var _snap_pending := true

func setup(car: RigidBody3D) -> void:
	target = car
	# The camera writes render-frame transforms in world space.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	current = true
	far = 900.0
	# Prime the chassis interpolation history before the first render or respawn.
	target.get_global_transform_interpolated()
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
	if is_instance_valid(target):
		_snap_to_pose(target.global_transform)

func _snap_to_pose(pose: Transform3D) -> void:
	_yaw = _target_yaw(pose)
	_previous_yaw = _yaw
	_speed = _planar_speed()
	_previous_speed = _speed
	_clearance = 1.0
	_snap_pending = true
	_previous_clearance = _clearance
	_place_camera(pose, _yaw, _speed, _clearance, 1.0)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var pose := target.global_transform
	_previous_yaw = _yaw
	_previous_speed = _speed
	_yaw = lerp_angle(_yaw, _target_yaw(pose), 1.0 - exp(-12.0 * delta))
	_speed = lerpf(_speed, _planar_speed(), 1.0 - exp(-2.6 * delta))
	if mode == 2:
		return
	var pivot := pose.origin + CHASE_PIVOT
	var offset := _chase_offset(_yaw)
	var params := PhysicsRayQueryParameters3D.create(pivot, pivot + offset, 1, [target.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	var limit := 1.0 if hit.is_empty() else 0.88 * pivot.distance_to(hit.position) / offset.length()
	# Clip both interpolation endpoints when obstructed. Ease the camera back out.
	_previous_clearance = minf(_clearance, limit)
	_clearance = lerpf(_previous_clearance, limit, 1.0 - exp(-6.0 * delta))

func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var fraction := Engine.get_physics_interpolation_fraction()
	var aim_weight := 1.0 if _snap_pending else 1.0 - exp(-9.0 * delta)
	_place_camera(
		target.get_global_transform_interpolated(),
		lerp_angle(_previous_yaw, _yaw, fraction),
		lerpf(_previous_speed, _speed, fraction),
		lerpf(_previous_clearance, _clearance, fraction),
		aim_weight
	)
	_snap_pending = false

func _place_camera(pose: Transform3D, yaw: float, speed: float, clearance: float, aim_weight: float) -> void:
	var base_fov := 76.0 if mode == 2 else 70.0
	fov = base_fov + 13.0 * clampf(speed / 45.0, 0.0, 1.0)
	if mode == 2:
		var mount := pose * HOOD_MOUNT
		var focus := pose * HOOD_FOCUS
		var up := pose.basis.y.lerp(Vector3.UP, 0.65).normalized()
		if absf(up.dot(mount.direction_to(focus))) > 0.98:
			up = pose.basis.y
		global_transform = Transform3D(Basis.IDENTITY, mount).looking_at(focus, up)
		return
	var pivot := pose.origin + CHASE_PIVOT
	var offset := _chase_offset(yaw)
	var position_3d := pivot + offset * clearance
	var forward := Vector3.FORWARD.rotated(Vector3.UP, _target_yaw(pose))
	var focus := pivot + forward * minf(speed * 0.09, 3.0)
	var look := focus - position_3d
	if Vector2(look.x, look.z).length_squared() < 0.0025:
		global_position = position_3d
		return
	var aim := Basis.looking_at(look, Vector3.UP)
	global_transform = Transform3D(global_basis.slerp(aim, aim_weight).orthonormalized(), position_3d)

func _chase_offset(yaw: float) -> Vector3:
	var offset := Vector3(0.0, 2.50, 6.30) if mode == 0 else Vector3(0.0, 1.85, 4.20)
	return offset.rotated(Vector3.UP, yaw) - CHASE_PIVOT

func _target_yaw(pose: Transform3D) -> float:
	var back := pose.basis.z
	if Vector2(back.x, back.z).length_squared() < 0.01:
		return _yaw
	return atan2(back.x, back.z)

func _planar_speed() -> float:
	return Vector2(target.linear_velocity.x, target.linear_velocity.z).length()
