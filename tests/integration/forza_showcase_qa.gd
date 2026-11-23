extends SceneTree
## Forza-fidelity showcase QA & screenshot capture script.
## Run: Godot --path . --resolution 1600x900 --script res://tests/integration/forza_showcase_qa.gd -- --capture-dir <dir>

var scene: Node3D
var failures := 0
var _capture_dir := ""
var _graphical := false
var _frame_times := PackedFloat64Array()
var _last_frame_usec := 0
var _peak_draw_calls := 0
var _peak_primitives := 0
var _peak_static_bytes := 0
var _peak_video_bytes := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func _ticks(count: int) -> void:
	for i in count:
		await physics_frame

func _run() -> void:
	_graphical = DisplayServer.get_name() != "headless"
	var args := OS.get_cmdline_user_args()
	var idx := args.find("--capture-dir")
	if idx >= 0 and idx + 1 < args.size():
		_capture_dir = args[idx + 1]
	if _graphical:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var main: PackedScene = load("res://scenes/free_roam/aster_valley.tscn")
	scene = main.instantiate()
	scene.set("scenery_enabled", true)
	root.add_child(scene)
	await _ticks(100)

	var car := scene.get("vehicle_body") as Vehicle
	_check(car != null, "Aster Valley booted with vehicle")
	_check(scene.get("scenery") != null, "Scenery layer active for showcase")
	if car == null:
		quit(1)
		return

	var photo := Camera3D.new()
	photo.name = "ShowcasePhotoCamera"
	photo.keep_aspect = Camera3D.KEEP_HEIGHT
	photo.fov = 40.0
	photo.far = 2500.0
	scene.add_child(photo)

	# 1. Hero car close-ups on sunlit road with front wheels turned & brake lights active
	var hero_pose: Variant = scene.call("find_road_pose", Vector3(-520.0, 0.0, 490.0), Vector3(1.0, 0.0, -0.3))
	if hero_pose == null:
		hero_pose = scene.call("find_road_pose", Vector3(-575.0, 0.0, 545.0), Vector3.RIGHT)
	_check(hero_pose != null, "Hero road pose found")

	if hero_pose != null:
		for car_id in ["vela_gt", "orion_rs", "kestrel_xr"]:
			await _switch_car(car_id, hero_pose)
			car = scene.get("vehicle_body") as Vehicle
			_check(car != null and scene.get("active_vehicle_id") == car_id, "Switched to " + car_id)
			if car == null:
				continue

			# Turn front wheels left, hold handbrake so car stays parked, and briefly apply brake for brake lights
			Input.action_press("drive_handbrake", 1.0)
			Input.action_press("drive_left", 0.85)
			await _ticks(30)
			Input.action_press("drive_brake", 0.8)
			await _ticks(2)

			photo.fov = 38.0
			photo.global_position = _clamp_cam_above_terrain(car.to_global(Vector3(-3.4, 1.25, -4.4)), 0.9)
			photo.look_at(car.global_position + Vector3(0.0, 0.52, 0.0), Vector3.UP)
			photo.make_current()
			await _ticks(2)
			await process_frame
			await _capture("hero-%s-front34" % car_id)

			photo.global_position = _clamp_cam_above_terrain(car.to_global(Vector3(3.3, 1.30, 4.3)), 0.9)
			photo.look_at(car.global_position + Vector3(0.0, 0.52, 0.0), Vector3.UP)
			await process_frame
			await _capture("hero-%s-rear34" % car_id)

			if car_id == "vela_gt":
				photo.fov = 34.0
				photo.global_position = _clamp_cam_above_terrain(car.to_global(Vector3(-2.25, 0.48, -1.55)), 0.35)
				photo.look_at(car.to_global(Vector3(-0.82, 0.36, -1.35)), Vector3.UP)
				await process_frame
				await _capture("hero-vela_gt-wheel-caliper")

			Input.action_release("drive_brake")
			Input.action_release("drive_left")
			Input.action_release("drive_handbrake")
			await _ticks(5)

	# 2. Scenic region & shoreline shots with Vela GT
	await _switch_car("vela_gt", hero_pose if hero_pose != null else car.global_transform)
	var world: Node3D = scene.get("world")
	var regions: Array = world.call("get_world_metadata")["regions"]
	var region_centers := {}
	for r: Dictionary in regions:
		region_centers[r["id"]] = Vector3(r["center"][0], 0.0, r["center"][1])

	var scenic_shots := [
		{"name": "scenic-alder-town", "pos": Vector3(-575.0, 0.0, 545.0), "dir": Vector3.RIGHT, "cam": Vector3(-4.5, 2.2, 6.8), "look": Vector3(0.0, 0.8, -12.0)},
		{"name": "scenic-cedar-woods", "pos": Vector3(-870.0, 0.0, -154.0), "dir": Vector3(1.0, 0.0, -1.0), "cam": Vector3(-2.2, 2.5, 6.8), "look": Vector3(0.0, 0.8, -14.0)},
		{"name": "scenic-north-ridge", "pos": Vector3(549.0, 0.0, -779.0), "dir": Vector3(1.0, 0.0, 1.0), "cam": Vector3(-3.0, 2.5, 7.2), "look": Vector3(0.0, 0.8, -14.0)},
		{"name": "scenic-green-valley", "pos": region_centers.get("green_valley", Vector3(0.0, 0.0, 0.0)), "dir": Vector3.RIGHT, "cam": Vector3(-3.5, 2.3, 7.0), "look": Vector3(0.0, 0.8, -14.0)},
		{"name": "scenic-eastwater-shoreline", "pos": Vector3(630.0, 0.0, 495.0), "dir": Vector3(1.0, 0.0, -1.0), "cam": Vector3(-18.0, 14.0, -8.0), "look": Vector3(16.0, -4.0, 6.0)},
	]

	photo.fov = 48.0
	for shot in scenic_shots:
		var pose: Variant = scene.call("find_road_pose", shot["pos"], shot["dir"])
		_check(pose != null, "Scenic pose found for " + shot["name"])
		if pose == null:
			continue
		var adapter: VehicleAdapter = scene.get("adapter")
		adapter.reset_to(pose)
		await _ticks(60)
		car = scene.get("vehicle_body") as Vehicle
		if shot["name"] == "scenic-eastwater-shoreline":
			photo.global_position = _clamp_cam_above_terrain(car.global_position + shot["cam"], 1.5)
			photo.look_at(car.global_position + shot["look"], Vector3.UP)
		else:
			photo.global_position = _clamp_cam_above_terrain(car.to_global(shot["cam"]), 1.5)
			photo.look_at(car.to_global(shot["look"]), Vector3.UP)
		photo.make_current()
		await _capture(shot["name"])

	# 3. Measure live Forward+ performance with scenery on (180 frames driving)
	var chase_cam: DrivingChaseCamera = scene.get("camera")
	if chase_cam != null:
		chase_cam.make_current()
	photo.queue_free()

	if hero_pose != null:
		var adapter: VehicleAdapter = scene.get("adapter")
		adapter.reset_to(hero_pose)
		if chase_cam != null:
			chase_cam.snap_to_vehicle()
		await _ticks(30)

	if _graphical:
		_last_frame_usec = 0
		process_frame.connect(_measure_frame)
	Input.action_press("drive_throttle", 0.75)
	for i in 180:
		await process_frame
	Input.action_release("drive_throttle")
	if _graphical:
		process_frame.disconnect(_measure_frame)
	_report_fps()

	print("Forza showcase QA failures: ", failures)
	quit(0 if failures == 0 else 1)

func _clamp_cam_above_terrain(pos: Vector3, min_clearance := 1.4) -> Vector3:
	var vp := root.get_viewport()
	if vp != null and vp.world_3d != null:
		var space := vp.world_3d.direct_space_state
		if space != null:
			var query := PhysicsRayQueryParameters3D.create(Vector3(pos.x, 500.0, pos.z), Vector3(pos.x, -100.0, pos.z))
			var car := scene.get("vehicle_body") as CollisionObject3D
			if car != null:
				query.exclude = [car.get_rid()]
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				pos.y = maxf(pos.y, hit["position"].y + min_clearance)
	return pos

func _switch_car(car_id: String, pose: Transform3D) -> void:
	if scene.get("active_vehicle_id") != car_id:
		scene.call("queue_vehicle_selection", car_id)
		await _ticks(12)
	var adapter: VehicleAdapter = scene.get("adapter")
	if adapter != null:
		adapter.reset_to(pose)
	await _ticks(50)

func _capture(name: String) -> void:
	if not _graphical or _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.save_png(_capture_dir.path_join(name + ".png")) == OK, "capture " + name)
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
	print("SHOWCASE_PERF %s frames=%d mean_fps=%.1f 1%%_low_fps=%.1f p99_ms=%.2f peak_calls=%d peak_primitives=%d static_MiB=%.1f video_MiB=%.1f" % [
		root.size, _frame_times.size(), _frame_times.size() * 1000.0 / total,
		slow_frames * 1000.0 / slow_total, _frame_times[-slow_frames], _peak_draw_calls, _peak_primitives,
		_peak_static_bytes / 1048576.0, _peak_video_bytes / 1048576.0])
