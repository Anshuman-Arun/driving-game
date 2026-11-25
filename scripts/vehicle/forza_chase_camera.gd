class_name ForzaChaseCamera
extends Camera3D
## Forza-style dynamic chase camera rig with spring-damped acceleration/cornering lag,
## dynamic FOV scaling, obstacle collision avoidance, and optional screen-space radial speed blur.

const HOOD_MOUNT := Vector3(0.0, 0.86, -0.92)
const HOOD_FOCUS := Vector3(0.0, 0.70, -30.0)
const CHASE_PIVOT := Vector3(0.0, 0.75, 0.0)

# Tuned Forza Horizon geometry:
# Generous follow distances so the car is well-framed with ample view of road and scenery.
const CHASE_DEFAULT_HEIGHT := 2.25
const CHASE_DEFAULT_DIST := 7.20

const CHASE_FAR_HEIGHT := 2.85
const CHASE_FAR_DIST := 9.60

const CHASE_CLOSE_HEIGHT := 1.85
const CHASE_CLOSE_DIST := 5.40

# FOV specifications:
const FOV_REST := 58.0
const FOV_TOP_SPEED := 74.0
const TOP_SPEED_MPS := 60.0 # ~216 km/h

const LOOK_RECENTER_DELAY := 0.35

@export var enable_radial_blur := false: # Disabled by default for maximum performance
	set(val):
		enable_radial_blur = val
		if is_instance_valid(_blur_layer):
			_blur_layer.visible = val

var target: RigidBody3D
var mode := 0 # 0: Chase Standard, 1: Chase Far, 2: Chase Close, 3: Hood

var _yaw := 0.0
var _previous_yaw := 0.0
var _speed := 0.0
var _previous_speed := 0.0
var _clearance := 1.0
var _previous_clearance := 1.0
var _snap_pending := true
var _hood_mount := Transform3D(Basis.IDENTITY, HOOD_MOUNT)

# Spring-damped lag state variables
var _pitch_compression := 0.0
var _previous_pitch_compression := 0.0
var _dist_compression := 0.0
var _previous_dist_compression := 0.0
var _lateral_lag := 0.0
var _previous_lateral_lag := 0.0
var _prev_forward_speed := 0.0

# Look-around controls
var _look_input := Vector2.ZERO
var _look_yaw := 0.0
var _previous_look_yaw := 0.0
var _look_pitch := 0.0
var _previous_look_pitch := 0.0
var _look_release_timer := 0.0

var _ray_params := PhysicsRayQueryParameters3D.new()

# Post-processing blur overlay
var _blur_layer: CanvasLayer
var _blur_rect: ColorRect
var _blur_mat: ShaderMaterial

func _ready() -> void:
	if enable_radial_blur:
		_setup_blur_overlay()

func setup(car: RigidBody3D) -> void:
	target = car
	_ray_params.collision_mask = 1 # Static world only
	
	# Exclude vehicle and all attached collision objects
	var excludes: Array[RID] = [car.get_rid()]
	for child in car.find_children("*", "CollisionObject3D", true, false):
		if child is CollisionObject3D:
			excludes.append(child.get_rid())
	_ray_params.exclude = excludes
	
	var hood := car.get_node_or_null("CameraMounts/Hood") as Marker3D
	_hood_mount = hood.transform if hood != null else Transform3D(Basis.IDENTITY, HOOD_MOUNT)
	
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	current = true
	far = 4600.0
	
	target.get_global_transform_interpolated()
	snap_to_vehicle()

func set_look_input(look: Vector2) -> void:
	_look_input = look.limit_length(1.0)

func cycle() -> void:
	mode = (mode + 1) % 4
	snap_to_vehicle()

func get_mode_name() -> String:
	match mode:
		0:
			return "FORZA CHASE (STANDARD)"
		1:
			return "FORZA CHASE (FAR / SCENIC)"
		2:
			return "FORZA CHASE (CLOSE)"
		_:
			return "HOOD / BONNET"

func snap_to_vehicle() -> void:
	_look_input = Vector2.ZERO
	_look_yaw = 0.0
	_previous_look_yaw = 0.0
	_look_pitch = 0.0
	_previous_look_pitch = 0.0
	_look_release_timer = 0.0
	_pitch_compression = 0.0
	_previous_pitch_compression = 0.0
	_dist_compression = 0.0
	_previous_dist_compression = 0.0
	_lateral_lag = 0.0
	_previous_lateral_lag = 0.0
	_clearance = 1.0
	_previous_clearance = 1.0
	if is_instance_valid(target):
		_prev_forward_speed = _planar_speed()
		_snap_to_pose(target.global_transform)

func _snap_to_pose(pose: Transform3D) -> void:
	_yaw = _target_yaw(pose)
	_previous_yaw = _yaw
	_speed = _planar_speed()
	_previous_speed = _speed
	_clearance = 1.0
	_previous_clearance = 1.0
	_snap_pending = true
	_place_camera(pose, _yaw, _speed, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var pose := target.global_transform
	_previous_yaw = _yaw
	_previous_speed = _speed
	_previous_look_yaw = _look_yaw
	_previous_look_pitch = _look_pitch
	_previous_pitch_compression = _pitch_compression
	_previous_dist_compression = _dist_compression
	_previous_lateral_lag = _lateral_lag

	var car_forward := -pose.basis.z
	var car_right := pose.basis.x
	var car_vel := target.linear_velocity
	var forward_speed := car_vel.dot(car_forward)
	var lateral_speed := car_vel.dot(car_right)
	var current_planar_speed := _planar_speed()

	# Longitudinal acceleration estimation for pitch/compression dynamics
	var accel := (forward_speed - _prev_forward_speed) / maxf(delta, 0.001)
	accel = clampf(accel, -24.0, 20.0)
	_prev_forward_speed = forward_speed

	var target_pitch_compression := -clampf(accel / 20.0, -1.0, 1.0) * deg_to_rad(2.5)
	var target_dist_compression := clampf(accel / 20.0, -1.0, 1.0) * 0.35
	_pitch_compression = lerpf(_pitch_compression, target_pitch_compression, 1.0 - exp(-7.5 * delta))
	_dist_compression = lerpf(_dist_compression, target_dist_compression, 1.0 - exp(-6.5 * delta))

	# Lateral cornering/drift lag
	var target_lateral := clampf(lateral_speed / 20.0, -1.0, 1.0) * 0.65
	_lateral_lag = lerpf(_lateral_lag, target_lateral, 1.0 - exp(-6.0 * delta))

	# Dynamic yaw chase
	var target_y := _target_yaw(pose)
	if current_planar_speed > 3.0 and absf(lateral_speed) > 2.5:
		var vel_yaw := atan2(-car_vel.x, -car_vel.z)
		var drift_weight := clampf((absf(lateral_speed) - 2.5) / 15.0, 0.0, 0.35)
		target_y = lerp_angle(target_y, vel_yaw, drift_weight)

	_yaw = lerp_angle(_yaw, target_y, 1.0 - exp(-9.5 * delta))
	_speed = lerpf(_speed, current_planar_speed, 1.0 - exp(-3.0 * delta))
	_update_look(delta)

	if mode == 3: # Hood mode
		return

	# Clearance raycasting against environment
	var world_3d := get_world_3d()
	if world_3d == null or world_3d.direct_space_state == null:
		return
	var pivot := pose.origin + CHASE_PIVOT
	var offset := _chase_offset(_yaw + _look_yaw, _look_pitch, _pitch_compression, _dist_compression, _lateral_lag)
	
	# Start ray outside the vehicle rear boundary to prevent self-collision
	var rear_start := pivot - pose.basis.z * 2.4 + Vector3.UP * 0.35
	_ray_params.from = rear_start
	_ray_params.to = pivot + offset
	var hit := world_3d.direct_space_state.intersect_ray(_ray_params)
	var limit := 1.0
	if not hit.is_empty():
		var hit_dist := pivot.distance_to(hit.position)
		limit = clampf(0.92 * hit_dist / maxf(offset.length(), 0.001), 0.70, 1.0)
	
	_previous_clearance = minf(_clearance, limit)
	_clearance = lerpf(_previous_clearance, limit, 1.0 - exp(-6.0 * delta))

func _update_look(delta: float) -> void:
	if _look_input.length_squared() > 0.0004:
		_look_release_timer = LOOK_RECENTER_DELAY
		var target_ly := 0.0
		var target_lp := 0.0
		if mode == 3:
			target_ly = -_look_input.x * deg_to_rad(75.0)
			target_lp = clampf(-_look_input.y * deg_to_rad(12.0), deg_to_rad(-12.0), deg_to_rad(12.0))
		else:
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

	var physics_fraction := Engine.get_physics_interpolation_fraction()
	var interpolated_yaw := lerp_angle(_previous_yaw, _yaw, physics_fraction)
	var interpolated_speed := lerpf(_previous_speed, _speed, physics_fraction)
	var interpolated_clearance := lerpf(_previous_clearance, _clearance, physics_fraction)
	var interpolated_look_yaw := lerpf(_previous_look_yaw, _look_yaw, physics_fraction)
	var interpolated_look_pitch := lerpf(_previous_look_pitch, _look_pitch, physics_fraction)
	var interpolated_pitch_comp := lerpf(_previous_pitch_compression, _pitch_compression, physics_fraction)
	var interpolated_dist_comp := lerpf(_previous_dist_compression, _dist_compression, physics_fraction)
	var interpolated_lat_lag := lerpf(_previous_lateral_lag, _lateral_lag, physics_fraction)

	var aim_weight := 1.0 - exp(-16.0 * delta)
	if _snap_pending:
		aim_weight = 1.0
		interpolated_clearance = _clearance

	_place_camera(
		target.get_global_transform_interpolated(),
		interpolated_yaw,
		interpolated_speed,
		interpolated_clearance,
		aim_weight,
		interpolated_look_yaw,
		interpolated_look_pitch,
		interpolated_pitch_comp,
		interpolated_dist_comp,
		interpolated_lat_lag
	)
	_snap_pending = false

	# Update post-processing speed radial blur if enabled
	if enable_radial_blur and is_instance_valid(_blur_mat):
		var norm_speed := clampf(interpolated_speed / TOP_SPEED_MPS, 0.0, 1.0)
		_blur_mat.set_shader_parameter("speed_intensity", norm_speed)

func _place_camera(
	pose: Transform3D,
	yaw: float,
	speed: float,
	clearance: float,
	aim_weight: float,
	look_yaw: float,
	look_pitch: float,
	pitch_compression: float,
	dist_compression: float,
	lateral_lag: float
) -> void:
	var speed_norm := clampf(speed / TOP_SPEED_MPS, 0.0, 1.0)
	var fov_t := smoothstep(0.0, 1.0, speed_norm)
	
	if mode == 3: # Hood mode
		fov = lerpf(72.0, 86.0, fov_t)
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

	fov = lerpf(FOV_REST, FOV_TOP_SPEED, fov_t)
	var pivot := pose.origin + CHASE_PIVOT
	var offset := _chase_offset(yaw + look_yaw, look_pitch, pitch_compression, dist_compression, lateral_lag)
	var position_3d := pivot + offset * clearance
	
	var look_active := absf(look_yaw) > 0.002 or absf(look_pitch) > 0.002
	var forward := Vector3.FORWARD.rotated(Vector3.UP, _target_yaw(pose))
	var focus := pivot + forward * 0.85 if look_active else pivot + forward * minf(speed * 0.10 + 1.2, 4.5)
	var look := focus - position_3d
	if Vector2(look.x, look.z).length_squared() < 0.0025:
		global_position = position_3d
		return
	
	var aim := Basis.looking_at(look, Vector3.UP)
	var final_weight := 1.0 if look_active else aim_weight
	global_transform = Transform3D(global_basis.slerp(aim, final_weight).orthonormalized(), position_3d)

func _chase_offset(
	yaw: float,
	pitch: float = 0.0,
	pitch_compression: float = 0.0,
	dist_compression: float = 0.0,
	lateral_lag: float = 0.0
) -> Vector3:
	var base_h := CHASE_DEFAULT_HEIGHT
	var base_d := CHASE_DEFAULT_DIST
	match mode:
		0: # Standard Forza Chase
			base_h = CHASE_DEFAULT_HEIGHT
			base_d = CHASE_DEFAULT_DIST
		1: # Far / Scenic Chase
			base_h = CHASE_FAR_HEIGHT
			base_d = CHASE_FAR_DIST
		2: # Close Sport Chase
			base_h = CHASE_CLOSE_HEIGHT
			base_d = CHASE_CLOSE_DIST
		_:
			base_h = CHASE_DEFAULT_HEIGHT
			base_d = CHASE_DEFAULT_DIST
	
	# Apply distance compression under braking / squat under acceleration
	base_d = maxf(4.2, base_d + dist_compression)
	
	# Rel vector from pivot
	var rel := Vector3(lateral_lag, base_h - CHASE_PIVOT.y, base_d)
	
	var total_pitch := pitch + pitch_compression
	if not is_zero_approx(total_pitch):
		rel = rel.rotated(Vector3.RIGHT, -total_pitch)
		rel.y = maxf(rel.y, 0.45)
	
	return rel.rotated(Vector3.UP, yaw)

func _target_yaw(pose: Transform3D) -> float:
	var back := pose.basis.z
	if Vector2(back.x, back.z).length_squared() < 0.01:
		return _yaw
	return atan2(back.x, back.z)

func _planar_speed() -> float:
	if not is_instance_valid(target):
		return 0.0
	return Vector2(target.linear_velocity.x, target.linear_velocity.z).length()

func _setup_blur_overlay() -> void:
	const SHADER_PATH := "res://shaders/speed_radial_blur.gdshader"
	if not ResourceLoader.exists(SHADER_PATH):
		return
	var shader := ResourceLoader.load(SHADER_PATH) as Shader
	if shader == null:
		return
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = shader
	_blur_layer = CanvasLayer.new()
	_blur_layer.layer = 10
	_blur_layer.name = "SpeedBlurLayer"
	_blur_rect = ColorRect.new()
	_blur_rect.name = "SpeedBlurRect"
	_blur_rect.material = _blur_mat
	_blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_layer.add_child(_blur_rect)
	add_child(_blur_layer)
