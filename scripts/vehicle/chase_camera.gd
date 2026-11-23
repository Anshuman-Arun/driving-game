class_name DrivingChaseCamera
extends Camera3D
## Both views follow the rendered chassis. Chase clearance is sampled on physics ticks.
## Supports Forza-style right-stick look-around in Chase and Hood modes with smooth recenter.

const HOOD_MOUNT := Vector3(0.0, 0.86, -0.92)
const HOOD_FOCUS := Vector3(0.0, 0.70, -30.0)
const CHASE_PIVOT := Vector3.UP * 0.68
const LOOK_RECENTER_DELAY := 0.35

var target: RigidBody3D
var mode := 0
var _yaw := 0.0
var _previous_yaw := 0.0
var _speed := 0.0
var _previous_speed := 0.0
var _clearance := 1.0
var _previous_clearance := 1.0
var _snap_pending := true
var _hood_mount := Transform3D(Basis.IDENTITY, HOOD_MOUNT)

var _look_input := Vector2.ZERO
var _look_yaw := 0.0
var _previous_look_yaw := 0.0
var _look_pitch := 0.0
var _previous_look_pitch := 0.0
var _look_release_timer := 0.0

func setup(car: RigidBody3D) -> void:
	target = car
	var hood := car.get_node_or_null("CameraMounts/Hood") as Marker3D
	_hood_mount = hood.transform if hood != null else Transform3D(Basis.IDENTITY, HOOD_MOUNT)
	# The camera writes render-frame transforms in world space.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	current = true
	far = 900.0
	# Prime the chassis interpolation history before the first render or respawn.
	target.get_global_transform_interpolated()
	snap_to_vehicle()

func set_look_input(look: Vector2) -> void:
	_look_input = look.limit_length(1.0)

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
	_look_input = Vector2.ZERO
	_look_yaw = 0.0
	_previous_look_yaw = 0.0
	_look_pitch = 0.0
	_previous_look_pitch = 0.0
	_look_release_timer = 0.0
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
	_place_camera(pose, _yaw, _speed, _clearance, 1.0, 0.0, 0.0)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var pose := target.global_transform
	_previous_yaw = _yaw
	_previous_speed = _speed
	_previous_look_yaw = _look_yaw
	_previous_look_pitch = _look_pitch

	_yaw = lerp_angle(_yaw, _target_yaw(pose), 1.0 - exp(-12.0 * delta))
	_speed = lerpf(_speed, _planar_speed(), 1.0 - exp(-2.6 * delta))
	_update_look(delta)

	if mode == 2:
		return
	var pivot := pose.origin + CHASE_PIVOT
	var offset := _chase_offset(_yaw + _look_yaw, _look_pitch)
	var params := PhysicsRayQueryParameters3D.create(pivot, pivot + offset, 1, [target.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	var limit := 1.0 if hit.is_empty() else 0.88 * pivot.distance_to(hit.position) / offset.length()
	# Clip both interpolation endpoints when obstructed. Ease the camera back out.
	_previous_clearance = minf(_clearance, limit)
	_clearance = lerpf(_previous_clearance, limit, 1.0 - exp(-6.0 * delta))

func _update_look(delta: float) -> void:
	if _look_input.length_squared() > 0.0004:
		_look_release_timer = LOOK_RECENTER_DELAY
		var target_ly := 0.0
		var target_lp := 0.0
		if mode == 2:
			# Hood head-pan (±75 deg yaw, ±12 deg pitch)
			target_ly = -_look_input.x * deg_to_rad(75.0)
			target_lp = clampf(-_look_input.y * deg_to_rad(12.0), deg_to_rad(-12.0), deg_to_rad(12.0))
		else:
			# Forza Chase orbit: right stick X orbits smoothly up to ±180 deg;
			# pulling straight back looks directly behind the car.
			if absf(_look_input.x) < 0.22 and _look_input.y > 0.70:
				target_ly = PI
				target_lp = 0.0
			else:
				target_ly = -_look_input.x * PI
				target_lp = clampf(_look_input.y * deg_to_rad(22.0), deg_to_rad(-6.0), deg_to_rad(26.0))
		var weight := 1.0 - exp(-9.0 * delta)
		_look_yaw = lerpf(_look_yaw, target_ly, weight)
		_look_pitch = lerpf(_look_pitch, target_lp, weight)
	else:
		if _look_release_timer > 0.0:
			_look_release_timer = maxf(0.0, _look_release_timer - delta)
		else:
			var recenter := 1.0 - exp(-6.0 * delta)
			_look_yaw = lerpf(_look_yaw, 0.0, recenter)
			_look_pitch = lerpf(_look_pitch, 0.0, recenter)
			if absf(_look_yaw) < 0.0005:
				_look_yaw = 0.0
			if absf(_look_pitch) < 0.0005:
				_look_pitch = 0.0

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
		aim_weight,
		lerpf(_previous_look_yaw, _look_yaw, fraction),
		lerpf(_previous_look_pitch, _look_pitch, fraction)
	)
	_snap_pending = false

func _place_camera(pose: Transform3D, yaw: float, speed: float, clearance: float, aim_weight: float, look_yaw: float, look_pitch: float) -> void:
	var base_fov := 76.0 if mode == 2 else 70.0
	fov = base_fov + 13.0 * clampf(speed / 45.0, 0.0, 1.0)
	if mode == 2:
		var view := pose * _hood_mount
		var mount := view.origin
		var focus := view * (HOOD_FOCUS - HOOD_MOUNT)
		var up := view.basis.y.lerp(Vector3.UP, 0.65).normalized()
		if absf(up.dot(mount.direction_to(focus))) > 0.98:
			up = view.basis.y
		var base_xform := Transform3D(Basis.IDENTITY, mount).looking_at(focus, up)
		if not is_zero_approx(look_yaw) or not is_zero_approx(look_pitch):
			var pan_basis := Basis(Vector3.UP, look_yaw) * Basis(Vector3.RIGHT, look_pitch)
			base_xform.basis = (base_xform.basis * pan_basis).orthonormalized()
		global_transform = base_xform
		return
	var pivot := pose.origin + CHASE_PIVOT
	var offset := _chase_offset(yaw + look_yaw, look_pitch)
	var position_3d := pivot + offset * clearance
	var look_active := absf(look_yaw) > 0.002 or absf(look_pitch) > 0.002
	var forward := Vector3.FORWARD.rotated(Vector3.UP, _target_yaw(pose))
	var focus := pivot if look_active else pivot + forward * minf(speed * 0.09, 3.0)
	var look := focus - position_3d
	if Vector2(look.x, look.z).length_squared() < 0.0025:
		global_position = position_3d
		return
	var aim := Basis.looking_at(look, Vector3.UP)
	var final_weight := 1.0 if look_active else aim_weight
	global_transform = Transform3D(global_basis.slerp(aim, final_weight).orthonormalized(), position_3d)

func _chase_offset(yaw: float, pitch: float = 0.0) -> Vector3:
	var base := Vector3(0.0, 2.50, 6.30) if mode == 0 else Vector3(0.0, 1.85, 4.20)
	var rel := base - CHASE_PIVOT
	if not is_zero_approx(pitch):
		rel = rel.rotated(Vector3.RIGHT, -pitch)
		rel.y = maxf(rel.y, 0.45)
	return rel.rotated(Vector3.UP, yaw)

func _target_yaw(pose: Transform3D) -> float:
	var back := pose.basis.z
	if Vector2(back.x, back.z).length_squared() < 0.01:
		return _yaw
	return atan2(back.x, back.z)

func _planar_speed() -> float:
	return Vector2(target.linear_velocity.x, target.linear_velocity.z).length()
