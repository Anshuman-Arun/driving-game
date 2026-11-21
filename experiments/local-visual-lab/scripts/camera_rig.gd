class_name CameraRig
extends Node3D

## Reproducible stationary benchmark viewpoints, repeatable spline flythrough,
## and optional interactive free-camera controls.

var camera: Camera3D
var tm: TerrainMath

var viewpoints: Array[Dictionary] = []
var active_viewpoint_idx: int = 0
var is_flythrough: bool = false
var is_free_cam: bool = false

var flythrough_time: float = 0.0
const FLYTHROUGH_DURATION: float = 12.0

var _yaw: float = 0.0
var _pitch: float = 0.0
var _dragging: bool = false


func setup(p_camera: Camera3D, p_tm: TerrainMath) -> void:
	camera = p_camera
	tm = p_tm
	_build_viewpoints()
	select_viewpoint(0)


func _build_viewpoints() -> void:
	viewpoints.clear()

	# VP1: Hero Lakeside Curve — classic roadside angle looking north along the sweeping S-curve,
	# crisp asphalt markings, guardrails, parked Vela GT coupe at the overlook, Eastwater Lake & alpine peaks.
	var p1_road: Vector3 = tm.road_point(32.0)
	var r1: Vector3 = tm.road_right(32.0)
	var vp1_pos: Vector3 = p1_road - r1 * 1.4 + Vector3(0.0, 2.4, 0.0)
	var vp1_target: Vector3 = tm.road_point(-20.0) + tm.road_right(-20.0) * 16.0 + Vector3(0.0, 1.0, 0.0)
	viewpoints.append({
		"id": "VP1_Lakeside_Hero",
		"label": "VP1: Lakeside Hero Curve",
		"position": vp1_pos,
		"target": vp1_target,
		"fov": 56.0,
	})

	# VP2: Pine Canopy Corridor — driver-height road view looking along the sunlit northern S-bend,
	# testing road markings, dappled PSSM shadows, grass shoulders, and backlit conifer & birch foliage.
	var p2_road: Vector3 = tm.road_point(-112.0)
	var r2: Vector3 = tm.road_right(-112.0)
	var vp2_pos: Vector3 = p2_road - r2 * 0.4 + Vector3(0.0, 1.85, 0.0)
	var vp2_target: Vector3 = tm.road_point(-48.0) + Vector3(0.0, 2.0, 0.0)
	viewpoints.append({
		"id": "VP2_Pine_Corridor",
		"label": "VP2: Pine Canopy Road",
		"position": vp2_pos,
		"target": vp2_target,
		"fov": 60.0,
	})

	# VP3: Overlook Vista — unobstructed elevated panorama from just behind the overlook turnout,
	# showcasing the crimson coupe, timber deck, winding highway, Eastwater Lake, and snow-dusted peaks.
	var p3_road: Vector3 = tm.road_point(4.0)
	var r3: Vector3 = tm.road_right(4.0)
	var vp3_pos: Vector3 = p3_road - r3 * 2.5 + Vector3(0.0, 8.8, 0.0)
	var vp3_target: Vector3 = tm.road_point(-24.0) + tm.road_right(-24.0) * 42.0 + Vector3(0.0, 1.5, 0.0)
	viewpoints.append({
		"id": "VP3_Overlook_Vista",
		"label": "VP3: Overlook Panoramic Vista",
		"position": vp3_pos,
		"target": vp3_target,
		"fov": 62.0,
	})

	# VP4: Shoreline Detail — low water-level perspective testing alpine water ripples, depth tint,
	# shoreline foam, SSR/sky reflections, granite cliff strata, and foreground grass sway.
	var shore_x: float = tm.road_center_x(18.0) + 46.0
	var vp4_pos := Vector3(shore_x, 2.35, 22.0)
	var vp4_target := Vector3(tm.road_center_x(-22.0) + 22.0, 10.5, -34.0)
	viewpoints.append({
		"id": "VP4_Shoreline_Detail",
		"label": "VP4: Shoreline & Reflection Detail",
		"position": vp4_pos,
		"target": vp4_target,
		"fov": 58.0,
	})


func is_blocking_viewpoint(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	for vp in viewpoints:
		var cp: Vector3 = vp["position"]
		var tp: Vector3 = vp["target"]
		var c2 := Vector2(cp.x, cp.z)
		if p.distance_to(c2) < 11.5:
			return true
		var dir: Vector2 = (Vector2(tp.x, tp.z) - c2).normalized()
		var rel: Vector2 = p - c2
		var proj: float = rel.dot(dir)
		if proj > 0.0 and proj < 32.0:
			var perp: float = absf(rel.x * dir.y - rel.y * dir.x)
			if perp < 6.5:
				return true
	return false


func select_viewpoint(idx: int) -> void:
	active_viewpoint_idx = wrapi(idx, 0, viewpoints.size())
	is_flythrough = false
	is_free_cam = false
	var vp: Dictionary = viewpoints[active_viewpoint_idx]
	camera.fov = vp["fov"]
	camera.global_position = vp["position"]
	camera.look_at(vp["target"], Vector3.UP)
	_sync_free_cam_angles()


func start_flythrough() -> void:
	is_flythrough = true
	is_free_cam = false
	flythrough_time = 0.0
	camera.fov = 60.0
	set_flythrough_progress(0.0)


func set_flythrough_progress(progress_01: float) -> void:
	var t: float = clampf(progress_01, 0.0, 1.0)
	# Smooth deterministic sweep along the road from z=+115 up to the overlook crest and out over Eastwater Lake
	var z_cam: float = lerpf(115.0, -95.0, t)
	var rp: Vector3 = tm.road_point(z_cam)
	var rr: Vector3 = tm.road_right(z_cam)
	var lateral: float = lerpf(1.2, 16.0, smoothstep(0.55, 1.0, t)) - 3.5 * sin(t * PI)
	var height_off: float = lerpf(3.2, 13.5, sin(t * PI * 0.85))
	var cam_pos: Vector3 = rp + rr * lateral + Vector3(0.0, height_off, 0.0)

	var look_z: float = clampf(z_cam - 48.0, TerrainMath.ROAD_Z_MIN + 10.0, TerrainMath.ROAD_Z_MAX)
	var look_rp: Vector3 = tm.road_point(look_z)
	var look_rr: Vector3 = tm.road_right(look_z)
	var look_east: float = lerpf(6.0, 38.0, smoothstep(0.35, 0.95, t))
	var target: Vector3 = look_rp + look_rr * look_east + Vector3(0.0, 1.5, 0.0)

	camera.global_position = cam_pos
	camera.look_at(target, Vector3.UP)


func get_active_label() -> String:
	if is_flythrough:
		return "Flythrough (%.0f%%)" % [(flythrough_time / FLYTHROUGH_DURATION) * 100.0]
	if is_free_cam:
		return "Free Camera (WASD + RMB)"
	return viewpoints[active_viewpoint_idx]["label"]


func _sync_free_cam_angles() -> void:
	var euler: Vector3 = camera.rotation
	_pitch = euler.x
	_yaw = euler.y


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
			if _dragging:
				is_flythrough = false
				is_free_cam = true
				_sync_free_cam_angles()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.0032
		_pitch = clampf(_pitch - mm.relative.y * 0.0032, -1.35, 1.35)
		camera.rotation = Vector3(_pitch, _yaw, 0.0)


func step_interactive(delta: float) -> void:
	if is_flythrough:
		flythrough_time = fmod(flythrough_time + delta, FLYTHROUGH_DURATION)
		set_flythrough_progress(flythrough_time / FLYTHROUGH_DURATION)
		return

	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move -= camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_S): move += camera.global_transform.basis.z
	if Input.is_key_pressed(KEY_A): move -= camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_D): move += camera.global_transform.basis.x
	if Input.is_key_pressed(KEY_E): move += Vector3.UP
	if Input.is_key_pressed(KEY_Q): move -= Vector3.UP

	if move.length_squared() > 1e-4:
		is_free_cam = true
		var speed: float = 34.0 if Input.is_key_pressed(KEY_SHIFT) else 14.0
		camera.global_position += move.normalized() * speed * delta
