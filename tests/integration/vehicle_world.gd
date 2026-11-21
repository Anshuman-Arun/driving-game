extends SceneTree
## Real vehicle + full world. Use --fixed-fps 60 for headless QA, without it for GPU timing.
## Graphical capture: -- --capture-dir <existing directory> [--expect-ultrawide].

var scene: Node3D
var car: Vehicle
var failures := 0
var _capture_dir := ""
var _graphical := false
var _expect_ultrawide := false
var _frame_times := PackedFloat64Array()
var _last_frame_usec := 0
var _peak_draw_calls := 0
var _peak_primitives := 0
var _peak_static_bytes := 0
var _peak_video_bytes := 0
var _contact_image: Image

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func _step(ticks: int) -> void:
	for tick in ticks:
		await physics_frame

func _run() -> void:
	_graphical = DisplayServer.get_name() != "headless"
	var args := OS.get_cmdline_user_args()
	_expect_ultrawide = "--expect-ultrawide" in args
	var index := args.find("--capture-dir")
	if index >= 0 and index + 1 < args.size():
		_capture_dir = args[index + 1]
	if _graphical:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var started := Time.get_ticks_msec()
	var main: PackedScene = load("res://scenes/free_roam/aster_valley.tscn")
	scene = main.instantiate()
	root.add_child(scene)
	await _step(100)
	car = scene.get("vehicle_body") as Vehicle
	if car == null:
		_check(false, "Vela GT spawned")
		quit(1)
		return

	var runtime: Node3D = scene.get("world")
	var report: Dictionary = runtime.get("report")
	_check(report.get("full_world", false) and report["terrain_chunks"] == 256
		and report["physical_corridors"] == 16 and report["junction_pads"] == 11,
		"canonical full world and every corridor and junction loaded")
	var bodies := scene.find_children("*", "StaticBody3D", true, false)
	_check(report["shoulder_colliders"] == 27 and bodies.size() == 310
		and bodies.size() == report["static_colliders"]
		and scene.find_children("*", "CollisionShape3D", true, false).size() == 311,
		"one collider per terrain chunk, deck, shoulder or skirt plus the Vela chassis")
	for body in bodies:
		if not body.has_meta("world_surface") or body.get_child_count() != 1:
			_check(false, "all generated collisions come from the tagged World Runtime")
			break
	_check(_contacts("Road") == 4, "four asphalt wheel contacts at Alder spawn")
	print("LOAD boot_ms=%d first_settled_ms=%d static_bytes=%d video_bytes=%d" % [
		scene.get("load_ms"), Time.get_ticks_msec() - started,
		int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))])
	_check_ultrawide_projection()
	await _capture("01-alder-spawn")

	var graph: Dictionary = runtime.call("get_road_graph")
	var lanes := {}
	for lane: Dictionary in graph["lanes"]:
		lanes[lane["id"]] = lane
	var junction := PackedVector3Array()
	junction.append_array(_points(lanes["lane_alder_market_ba"]).slice(-7))
	junction.append_array(_points(lanes["turn_alder_alder_market_ba__alder_cedar_ab"]).slice(1))
	junction.append_array(_points(lanes["lane_alder_cedar_ab"]).slice(1, 8))
	var junction_stats: Dictionary = await _drive(junction, 5.6, "02-alder-junction")
	_check(junction_stats.get("pad", false), "Vela crosses the actual Alder junction pad")

	var mountain := _points(lanes["lane_pine_ridge_ab"]).slice(52, 71)
	var uphill_stats: Dictionary = await _drive(mountain, 10.0, "03-mountain-gravel")
	_check(uphill_stats.get("gain", 0.0) > 14.0 and uphill_stats.get("dirt", false),
		"Vela climbs the gravel grade under its own power")

	var coast := _points(lanes["lane_valley_lake_ab"]).slice(76, 92)
	var edge := PackedVector3Array()
	for i in coast.size():
		var forward := coast[mini(i + 1, coast.size() - 1)] - coast[maxi(0, i - 1)]
		var lateral := forward.cross(Vector3.UP).normalized()
		var offset := 5.6 * pow(sin(PI * float(i) / (coast.size() - 1)), 2.0)
		edge.append(coast[i] + lateral * offset)
	var edge_stats: Dictionary = await _drive(edge, 7.2, "04-road-grass-road")
	_check(edge_stats.get("grass", false) and edge_stats.get("road_reentry", false),
		"wheel contacts transition from actual asphalt to grass and back")
	_check(edge_stats.get("shoulder", false), "Vela wheels hit the separate dirt shoulder")
	_check(edge_stats.get("grip_step", INF) <= 0.15, "road reentry retains bounded tire grip steps")

	var route_end := car.global_position
	var wanted: Variant = scene.call("find_road_pose", route_end, -car.global_basis.z)
	_check(wanted != null, "nearby road respawn candidate found")
	car.global_position.y -= 12.0
	car.global_basis = Basis(Vector3.FORWARD, PI)
	car.linear_velocity = Vector3(0, -2, 0)
	await _tap("drive_reset")
	await _step(75)
	_check(car.global_basis.y.dot(Vector3.UP) > 0.9 and _contacts() == 4
		and car.global_position.distance_to(route_end) < 12.0 and car.linear_velocity.length() < 3.0,
		"R rights the vehicle on a nearby drivable surface")
	car.global_position.x = 1002.0
	await _step(100)
	_check(car.global_position.x < 1000.0 and _contacts() == 4, "leaving map bounds recovers to a valid road")
	var camera: DrivingChaseCamera = scene.get("camera")
	await _tap("drive_camera")
	_check(camera.mode == 1, "close chase mode responds to C")
	_check_ultrawide_projection()
	await _tap("drive_camera")
	_check(camera.mode == 2 and car.to_local(camera.global_position).distance_to(Vector3(0, 0.86, -0.92)) < 0.10,
		"hood mode stays attached to Vela")
	_check_ultrawide_projection()
	await _capture("05-hood-after-reset")
	_report_fps()
	if _expect_ultrawide:
		await _check_fullscreen_toggle()
	await _tap("drive_camera")
	await _stationary_camera()
	print("Vehicle/world integration failures: ", failures)
	quit(0 if failures == 0 else 1)

func _check_fullscreen_toggle() -> void:
	_check(root.mode == Window.MODE_FULLSCREEN, "native ultrawide starts in fullscreen")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F11
	key.pressed = true
	root.push_input(key)
	await _step(15)
	_check(root.mode == Window.MODE_WINDOWED, "F11 returns to windowed mode")
	root.push_input(key)
	await _step(15)
	_check(root.mode == Window.MODE_FULLSCREEN and root.size == Vector2i(3440, 1440),
		"F11 restores native 3440x1440 fullscreen")

func _check_ultrawide_projection() -> void:
	if not _expect_ultrawide:
		return
	var camera: DrivingChaseCamera = scene.get("camera")
	var size := root.get_visible_rect().size
	var center := size * 0.5
	var horizontal_fov := rad_to_deg(camera.project_local_ray_normal(Vector2(0.0, center.y))
		.angle_to(camera.project_local_ray_normal(Vector2(size.x, center.y))))
	var vertical_fov := rad_to_deg(camera.project_local_ray_normal(Vector2(center.x, 0.0))
		.angle_to(camera.project_local_ray_normal(Vector2(center.x, size.y))))
	var expected_horizontal := rad_to_deg(2.0 * atan(tan(deg_to_rad(camera.fov) * 0.5) * 3440.0 / 1440.0))
	print("ULTRAWIDE %s window=%s viewport=%s horizontal=%.2f vertical=%.2f" % [
		camera.get_mode_name(), root.size, size, horizontal_fov, vertical_fov])
	_check(root.size == Vector2i(3440, 1440) and absf(size.x / size.y - 3440.0 / 1440.0) < 0.002,
		"3440x1440 fills the viewport")
	_check(absf(vertical_fov - camera.fov) < 0.1 and absf(horizontal_fov - expected_horizontal) < 0.1,
		camera.get_mode_name() + " preserves vertical FOV and expands horizontal FOV")

func _stationary_camera() -> void:
	var camera: DrivingChaseCamera = scene.get("camera")
	car.set_physics_process(false)
	car.freeze = true
	car.reset_physics_interpolation()
	await _step(65)
	var before := -camera.global_basis.z
	var peak := 0.0
	for direction in ["drive_left", "drive_right", "drive_left"]:
		Input.action_press(direction)
		for tick in 24:
			await physics_frame
			peak = maxf(peak, rad_to_deg(before.angle_to(-camera.global_basis.z)))
		Input.action_release(direction)
	_check(peak < 0.1, "stationary A/D reversals do not pull chase aim")
	print("CAMERA stationary peak aim change = %.3f deg" % peak)

func _drive(path: PackedVector3Array, speed: float, name: String) -> Dictionary:
	var forward := path[0].direction_to(path[1])
	var pose: Variant = scene.call("_road_pose", path[0], forward)
	if pose == null:
		_check(false, "valid starting road pose for " + name)
		return {}
	var adapter: VehicleAdapter = scene.get("adapter")
	var camera: DrivingChaseCamera = scene.get("camera")
	adapter.reset_to(pose)
	camera.snap_to_vehicle()
	await _step(75)
	var start_height := car.global_position.y
	var route := Curve3D.new()
	for point in path:
		route.add_point(Vector3(point.x, 0.0, point.z))
	var end := route.get_baked_length()
	var peak_speed := 0.0
	var ticks := 0
	var three_wheel_ticks := 0
	var max_no_contact := 0
	var no_contact := 0
	var peak_grip_step := 0.0
	var prior_grip: Array[float] = []
	for wheel in car.wheel_array:
		prior_grip.append(wheel.current_cof)
	var min_up := 1.0
	var peak_steer := 0.0
	var peak_steer_step := 0.0
	var prior_steer := car.steering_amount
	var max_cross_track := 0.0
	var progress := 0.0
	var pad := false
	var grass := false
	var dirt := false
	var road_reentry := false
	var shoulder := false
	_contact_image = null
	var contact_capture_queued := false
	if _graphical:
		_last_frame_usec = 0
		process_frame.connect(_measure_frame)
	for tick in range(ceili((end / speed + 12.0) * Engine.physics_ticks_per_second)):
		await physics_frame
		var p := Vector3(car.global_position.x, 0.0, car.global_position.z)
		progress = route.get_closest_offset(p)
		max_cross_track = maxf(max_cross_track, p.distance_to(route.sample_baked(progress)))
		if progress >= end - 2.0:
			break
		ticks += 1
		var speed_mps := maxf(adapter.get_forward_speed_mps(), 0.0)
		var target := route.sample_baked(minf(progress + 3.2 + speed_mps * 0.34, end))
		var car_forward := -car.global_basis.z
		car_forward.y = 0.0
		var aim := target - p
		var yaw_error := car_forward.signed_angle_to(aim, Vector3.UP)
		var wheel_angle := atan2(2.71 * 2.0 * sin(yaw_error), maxf(aim.length(), 1.0))
		var steer := clampf(signf(wheel_angle) * pow(absf(wheel_angle) / car.max_steering_angle, 1.0 / car.steering_exponent) * 1.16, -1.0, 1.0)
		_set_controls(steer, speed - speed_mps)
		peak_steer = maxf(peak_steer, absf(car.steering_amount))
		peak_steer_step = maxf(peak_steer_step, absf(car.steering_amount - prior_steer))
		prior_steer = car.steering_amount
		peak_speed = maxf(peak_speed, adapter.get_speed_mps() * 3.6)
		min_up = minf(min_up, car.global_basis.y.dot(Vector3.UP))
		var contact_count := _contacts()
		three_wheel_ticks += int(contact_count >= 3)
		no_contact = no_contact + 1 if contact_count == 0 else 0
		max_no_contact = maxi(max_no_contact, no_contact)
		grass = grass or _contacts("Grass") > 0
		dirt = dirt or _contacts("Dirt") > 0
		road_reentry = road_reentry or (grass and _contacts("Road") == 4)
		for i in car.wheel_array.size():
			var wheel: Wheel = car.wheel_array[i]
			peak_grip_step = maxf(peak_grip_step, absf(wheel.current_cof - prior_grip[i]))
			prior_grip[i] = wheel.current_cof
			if wheel.is_colliding():
				var collider: StaticBody3D = wheel.get_collider()
				pad = pad or str(collider.name).begins_with("Junction_")
				shoulder = shoulder or (collider.get_meta("world_surface", "") == "shoulder" and wheel.surface_type == "Dirt")
		if _graphical and not _capture_dir.is_empty() and not contact_capture_queued:
			if (name.begins_with("02") and pad) or (name.begins_with("04") and _contacts("Grass") >= 3):
				contact_capture_queued = true
				RenderingServer.frame_post_draw.connect(_remember_contact_frame, CONNECT_ONE_SHOT)
	if _graphical:
		process_frame.disconnect(_measure_frame)
	for action in ["drive_left", "drive_right", "drive_throttle", "drive_brake"]:
		Input.action_release(action)
	var gain := car.global_position.y - start_height
	var contact_percent := 100.0 * three_wheel_ticks / maxi(ticks, 1)
	print("DRIVE %s metres=%.1f/%.1f climb=%.2f m peak=%.1f km/h grounded=%.2f%% max_air_ticks=%d up=%.3f cross_track=%.2f m grip_step=%.3f steer_step=%.3f" % [
		name, progress, end, gain, peak_speed, contact_percent, max_no_contact, min_up, max_cross_track, peak_grip_step, peak_steer_step])
	_check(progress >= end - 2.1 and max_cross_track < 4.0, name + " completes the route")
	_check(contact_percent >= 97.0 and max_no_contact <= 8 and min_up > 0.90,
		name + " remains upright with stable suspension contact")
	_check(peak_steer > 0.02 and peak_steer_step < 0.06 and camera.global_transform.is_finite(),
		name + " steering is responsive and bounded, camera transform stays finite")
	if _contact_image != null:
		_check(_contact_image.save_png(_capture_dir.path_join(name + "-contact.png")) == OK,
			"screenshot during contact " + name)
	await _capture(name)
	return {"pad": pad, "dirt": dirt, "grass": grass, "road_reentry": road_reentry, "shoulder": shoulder,
		"gain": gain, "grip_step": peak_grip_step}

func _set_controls(steer: float, speed_error: float) -> void:
	Input.action_release("drive_left")
	Input.action_release("drive_right")
	if absf(steer) > 0.005:
		Input.action_press("drive_left" if steer > 0.0 else "drive_right", absf(steer))
	Input.action_press("drive_throttle", clampf(0.20 + speed_error * 0.24, 0.0, 1.0))
	Input.action_press("drive_brake", clampf((-speed_error - 1.2) * 0.24, 0.0, 0.72))

func _points(lane: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array()
	for xyz: Array in lane["points"]:
		points.append(Vector3(xyz[0], xyz[1], xyz[2]))
	return points

func _contacts(group := "") -> int:
	var count := 0
	for wheel in car.wheel_array:
		if wheel.is_colliding() and (group.is_empty() or wheel.get_collider().is_in_group(group)):
			count += 1
	return count

func _tap(action: StringName) -> void:
	await process_frame
	Input.action_press(action)
	await _step(10)
	Input.action_release(action)

func _capture(name: String) -> void:
	if not _graphical or _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if _expect_ultrawide:
		_check(image.get_size() == Vector2i(3440, 1440), "capture has 3440x1440 rendered pixels")
	_check(image.save_png(_capture_dir.path_join(name + ".png")) == OK, "screenshot " + name)

func _remember_contact_frame() -> void:
	_contact_image = root.get_texture().get_image()
	# Exclude the synchronous capture stall from the rolling render sample.
	_last_frame_usec = 0

func _measure_frame() -> void:
	var now := Time.get_ticks_usec()
	if _last_frame_usec != 0:
		_frame_times.append((now - _last_frame_usec) / 1000.0)
	_last_frame_usec = now
	_peak_draw_calls = maxi(_peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_peak_primitives = maxi(_peak_primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	_peak_static_bytes = maxi(_peak_static_bytes, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	_peak_video_bytes = maxi(_peak_video_bytes, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))

func _report_fps() -> void:
	if _frame_times.is_empty():
		return
	_frame_times.sort()
	var total := 0.0
	for msec in _frame_times:
		total += msec
	var slow_frames := maxi(1, ceili(_frame_times.size() * 0.01))
	var slow_total := 0.0
	for i in slow_frames:
		slow_total += _frame_times[-1 - i]
	print("PERF %s frames=%d mean_fps=%.1f 1%%_low_fps=%.1f p99_ms=%.2f peak_calls=%d peak_primitives=%d static_MiB=%.1f video_MiB=%.1f" % [
		root.size, _frame_times.size(), _frame_times.size() * 1000.0 / total,
		slow_frames * 1000.0 / slow_total, _frame_times[-slow_frames], _peak_draw_calls, _peak_primitives,
		_peak_static_bytes / 1048576.0, _peak_video_bytes / 1048576.0])
