extends SceneTree
## Phase A Visual Realism & Ultrawide Performance Benchmark Harness.
## Captures locked BEFORE/AFTER viewpoints across Cedar Woods (300-500 m corridor)
## and all 5 Aster Valley biomes, plus a repeatable ~65-90 mph Cedar Woods driving pass.
##
## Usage:
##   Godot_v4.7.2-stable_win64_console.exe --path . --resolution 3440x1440 --fullscreen --script res://tests/visual_realism/phase_a_benchmark.gd -- --capture-dir <dir> --scale 1.0 --preset medium
##
## Flags (after --):
##   --capture-dir <path>   Directory to save locked PNG screenshots (skipped if omitted)
##   --scale <float>        3D internal render scale (1.0 = native, 0.75 = 2580x1080)
##   --preset <str>         Graphics preset: low | medium | high (default: medium)
##   --aa <str>             AA/upscaler override: auto | taa | fxaa | fsr2 | none
##   --skip-captures        Skip still shots (benchmark driving pass only)
##   --skip-drive           Skip driving pass (still shots only)

const Drive = preload("res://scripts/integration/aster_valley_drive.gd")
const ValleyEnvironment = preload("res://scripts/integration/aster_valley_environment.gd")

const TARGET_SPEED_MPS := 36.0 # ~80.5 mph (within 65-90 mph / 29.1-40.2 m/s)
const CEDAR_LANE_ID := "lane_alder_cedar_ab"
const CEDAR_WARMUP_START_IDX := 20
const CEDAR_MEASURE_START_IDX := 95
const CEDAR_MEASURE_END_IDX := 155

var scene: Node3D
var car: Vehicle
var failures := 0

var _capture_dir := ""
var _scale := 1.0
var _preset := "medium"
var _aa_override := "auto"
var _skip_captures := false
var _skip_drive := false
var _graphical := false

var _frame_times := PackedFloat64Array()
var _gpu_times := PackedFloat64Array()
var _cpu_times := PackedFloat64Array()
var _draw_calls := PackedInt32Array()
var _primitives := PackedInt32Array()
var _speeds_mph := PackedFloat64Array()
var _last_frame_usec := 0
var _peak_static_bytes := 0
var _peak_video_bytes := 0
var _vp_rid: RID

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

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--capture-dir":
				if i + 1 < args.size():
					_capture_dir = args[i + 1]
					i += 1
			"--scale":
				if i + 1 < args.size():
					_scale = clampf(float(args[i + 1]), 0.25, 1.0)
					i += 1
			"--preset":
				if i + 1 < args.size():
					_preset = args[i + 1]
					i += 1
			"--aa":
				if i + 1 < args.size():
					_aa_override = args[i + 1]
					i += 1
			"--skip-captures":
				_skip_captures = true
			"--skip-drive":
				_skip_drive = true
		i += 1

func _apply_render_config() -> void:
	ValleyEnvironment.apply_quality(root, _preset)
	root.scaling_3d_scale = _scale
	if _scale < 0.999 and _aa_override == "auto":
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		root.use_taa = false
		root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	elif _aa_override == "fsr2":
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		root.use_taa = false
		root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	elif _aa_override == "taa":
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		root.use_taa = true
		root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	elif _aa_override == "fxaa":
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		root.use_taa = false
		root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	elif _aa_override == "none":
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		root.use_taa = false
		root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	else:
		root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR

func _run() -> void:
	_parse_args()
	_graphical = DisplayServer.get_name() != "headless"
	if _graphical:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_vp_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)

	var main: PackedScene = load("res://scenes/free_roam/aster_valley.tscn")
	scene = main.instantiate()
	scene.set("scenery_enabled", true)
	scene.set("graphics_preset", _preset)
	root.add_child(scene)
	await _ticks(110)

	_apply_render_config()
	car = scene.get("vehicle_body") as Vehicle
	_check(car != null, "Aster Valley booted with vehicle")
	_check(scene.get("scenery") != null, "Scenery layer active")
	if car == null:
		quit(1)
		return

	var adapter_name := RenderingServer.get_video_adapter_name()
	var win_size := root.size
	var internal_size := Vector2i(roundi(win_size.x * _scale), roundi(win_size.y * _scale))
	print("BENCH_ENV gpu=\"%s\" driver=\"%s\" window=%s internal=%s scale=%.2f preset=%s aa=%s scaling_mode=%d taa=%s" % [
		adapter_name, OS.get_video_adapter_driver_info(), win_size, internal_size, _scale, _preset, _aa_override,
		root.scaling_3d_mode, str(root.use_taa)])

	if not _skip_captures and not _capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture_dir)
		await _capture_locked_shots()

	if not _skip_drive:
		await _run_cedar_corridor_drive()

	print("Phase A benchmark failures: ", failures)
	quit(0 if failures == 0 else 1)

func _capture_locked_shots() -> void:
	var photo := Camera3D.new()
	photo.name = "PhaseAPhotoCamera"
	photo.keep_aspect = Camera3D.KEEP_HEIGHT
	photo.far = 2500.0
	scene.add_child(photo)

	var world: Node3D = scene.get("world")
	var graph: Dictionary = world.call("get_road_graph")
	var cedar_pts := PackedVector3Array()
	for lane: Dictionary in graph["lanes"]:
		if lane["id"] == CEDAR_LANE_ID:
			for p: Array in lane["points"]:
				cedar_pts.append(Vector3(p[0], p[1], p[2]))
			break
	_check(cedar_pts.size() > 155, "Found Cedar Woods showcase lane")

	# 1. Cedar Woods close corridor shot WITH hero car (Vela GT) at idx 130 (-870.5, 86.3, -154.2)
	var p130 := cedar_pts[130]
	var p134 := cedar_pts[134]
	var dir130 := Vector3(p134.x - p130.x, 0.0, p134.z - p130.z).normalized()
	var cedar_pose: Variant = scene.call("find_road_pose", p130, dir130)
	_check(cedar_pose != null, "Cedar Woods hero road pose found")
	if cedar_pose != null:
		var adapter: VehicleAdapter = scene.get("adapter")
		adapter.reset_to(cedar_pose)
		Input.action_press("drive_handbrake", 1.0)
		await _ticks(45)
		car = scene.get("vehicle_body") as Vehicle
		photo.fov = 44.0
		var cam_pos := _clamp_cam_above_terrain(car.to_global(Vector3(-2.3, 1.85, 6.4)), 1.2)
		var look_at_pt := car.to_global(Vector3(0.0, 1.15, -22.0))
		await _snap_shot(photo, cam_pos, look_at_pt, "01_cedar_corridor_close")
		Input.action_release("drive_handbrake")

	# Park car away from road shots 02-06 so landscape shots are unobstructed
	if cedar_pts.size() > 10:
		var park_pose: Variant = scene.call("find_road_pose", cedar_pts[5], Vector3.RIGHT)
		if park_pose != null:
			(scene.get("adapter") as VehicleAdapter).reset_to(park_pose)
			await _ticks(15)

	# 2. Cedar Woods mid corridor view (idx 118 looking north-east down corridor past -870,-154)
	var p118 := cedar_pts[118]
	var c2_pos := _ground_offset(p118 + Vector3(-1.5, 0.0, 0.0), 2.8)
	var c2_look := _ground_offset(cedar_pts[136], 1.6)
	photo.fov = 48.0
	await _snap_shot(photo, c2_pos, c2_look, "02_cedar_corridor_mid")

	# 3. Cedar Woods elevated overview of the 300-500 m showcase corridor
	var c3_pos := Vector3(-895.0, 132.0, -12.0)
	var c3_look := Vector3(-842.0, 86.0, -188.0)
	photo.fov = 50.0
	await _snap_shot(photo, c3_pos, c3_look, "03_cedar_corridor_overview")

	# 4. Sunlit/shaded road asphalt + shoulder + verge grass close-up near idx 129
	var p129 := cedar_pts[129]
	var fwd129 := (cedar_pts[132] - cedar_pts[127]).normalized()
	var right129 := fwd129.cross(Vector3.UP).normalized()
	var c4_pos := _ground_offset(p129 + right129 * 4.4 - fwd129 * 2.5, 1.15)
	var c4_look := _ground_offset(p129 + right129 * 1.4 + fwd129 * 7.5, 0.15)
	photo.fov = 40.0
	await _snap_shot(photo, c4_pos, c4_look, "04_road_verge_asphalt_closeup")

	# 5. Tree canopy, trunk & woodland undergrowth close-up beside Cedar Woods corridor
	var c5_pos := _ground_offset(p130 + right129 * 5.2, 2.0)
	var c5_look := _ground_offset(p130 + right129 * 20.0 + fwd129 * 8.0, 4.5)
	photo.fov = 46.0
	await _snap_shot(photo, c5_pos, c5_look, "05_tree_canopy_undergrowth_closeup")

	# 6. Alder Creek Bridge / sunlit-to-forest transition (idx 75)
	var p75 := cedar_pts[75]
	var fwd75 := (cedar_pts[80] - cedar_pts[72]).normalized()
	var c6_pos := _ground_offset(p75 - fwd75 * 14.0, 3.0)
	var c6_look := _ground_offset(p75 + fwd75 * 28.0, 1.5)
	photo.fov = 48.0
	await _snap_shot(photo, c6_pos, c6_look, "06_cedar_bridge_transition")

	# 7-10. Reference shots across the other 4 biomes (matched world framing)
	var biome_shots := [
		{"name": "07_alder_town", "pos": Vector3(-575.0, 0.0, 545.0), "dir": Vector3.RIGHT, "cam": Vector3(-4.5, 2.2, 6.8), "look": Vector3(0.0, 0.8, -12.0)},
		{"name": "08_green_valley", "pos": Vector3(45.0, 0.0, 170.0), "dir": Vector3.RIGHT, "cam": Vector3(-3.5, 2.3, 7.0), "look": Vector3(0.0, 0.8, -14.0)},
		{"name": "09_north_ridge", "pos": Vector3(549.0, 0.0, -779.0), "dir": Vector3(1.0, 0.0, 1.0), "cam": Vector3(-3.0, 2.5, 7.2), "look": Vector3(0.0, 0.8, -14.0)},
		{"name": "10_eastwater_lake", "pos": Vector3(630.0, 0.0, 495.0), "dir": Vector3(1.0, 0.0, -1.0), "cam": Vector3(-18.0, 14.0, -8.0), "look": Vector3(16.0, -4.0, 6.0)},
	]
	photo.fov = 48.0
	for shot in biome_shots:
		var pose: Variant = scene.call("find_road_pose", shot["pos"], shot["dir"])
		_check(pose != null, "Biome pose found for " + shot["name"])
		if pose == null:
			continue
		(scene.get("adapter") as VehicleAdapter).reset_to(pose)
		await _ticks(50)
		car = scene.get("vehicle_body") as Vehicle
		var cpos: Vector3
		var clook: Vector3
		if shot["name"] == "10_eastwater_lake":
			cpos = _clamp_cam_above_terrain(car.global_position + shot["cam"], 1.5)
			clook = car.global_position + shot["look"]
		else:
			cpos = _clamp_cam_above_terrain(car.to_global(shot["cam"]), 1.5)
			clook = car.to_global(shot["look"])
		await _snap_shot(photo, cpos, clook, shot["name"])

	photo.queue_free()

func _snap_shot(photo: Camera3D, cam_pos: Vector3, look_target: Vector3, shot_name: String) -> void:
	photo.global_position = cam_pos
	photo.look_at(look_target, Vector3.UP)
	photo.make_current()
	# Allow vegetation cell sync + TAA history to settle at the new camera pose
	await _ticks(24)
	for _f in 6:
		await process_frame
	print("SHOT %s pos=%s look=%s fov=%.1f" % [shot_name, cam_pos, look_target, photo.fov])
	if _graphical and not _capture_dir.is_empty():
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		_check(img.save_png(_capture_dir.path_join(shot_name + ".png")) == OK, "capture " + shot_name)

func _ground_offset(xz: Vector3, height_above: float) -> Vector3:
	var vp := root.get_viewport()
	if vp != null and vp.world_3d != null:
		var space := vp.world_3d.direct_space_state
		if space != null:
			var query := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 500.0, xz.z), Vector3(xz.x, -100.0, xz.z))
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				return Vector3(xz.x, hit["position"].y + height_above, xz.z)
	return Vector3(xz.x, xz.y + height_above, xz.z)

func _clamp_cam_above_terrain(pos: Vector3, min_clearance := 1.4) -> Vector3:
	var vp := root.get_viewport()
	if vp != null and vp.world_3d != null:
		var space := vp.world_3d.direct_space_state
		if space != null:
			var query := PhysicsRayQueryParameters3D.create(Vector3(pos.x, 500.0, pos.z), Vector3(pos.x, -100.0, pos.z))
			if car != null:
				query.exclude = [car.get_rid()]
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				pos.y = maxf(pos.y, hit["position"].y + min_clearance)
	return pos

func _run_cedar_corridor_drive() -> void:
	var chase_cam: DrivingChaseCamera = scene.get("camera")
	if chase_cam != null:
		chase_cam.make_current()

	var world: Node3D = scene.get("world")
	var graph: Dictionary = world.call("get_road_graph")
	var cedar_pts := PackedVector3Array()
	for lane: Dictionary in graph["lanes"]:
		if lane["id"] == CEDAR_LANE_ID:
			for p: Array in lane["points"]:
				cedar_pts.append(Vector3(p[0], p[1], p[2]))
			break

	var path := cedar_pts.slice(CEDAR_WARMUP_START_IDX, CEDAR_MEASURE_END_IDX + 1)
	var forward := path[0].direction_to(path[1])
	var start_pose: Variant = scene.call("_road_pose", path[0], forward)
	_check(start_pose != null, "Cedar drive start pose valid")
	if start_pose == null:
		return

	var adapter: VehicleAdapter = scene.get("adapter")
	adapter.reset_to(start_pose)
	if chase_cam != null:
		chase_cam.snap_to_vehicle()
	await _ticks(45)

	var route := Curve3D.new()
	for p in path:
		route.add_point(Vector3(p.x, 0.0, p.z))
	var measure_start_m := 0.0
	for k in range(CEDAR_MEASURE_START_IDX - CEDAR_WARMUP_START_IDX):
		measure_start_m += Vector2(path[k + 1].x - path[k].x, path[k + 1].z - path[k].z).length()
	var total_len := route.get_baked_length()

	var measuring := false
	_frame_times.clear()
	_gpu_times.clear()
	_cpu_times.clear()
	_draw_calls.clear()
	_primitives.clear()
	_speeds_mph.clear()
	_last_frame_usec = 0

	var max_ticks := ceili((total_len / 20.0 + 10.0) * Engine.physics_ticks_per_second)
	for _t in max_ticks:
		await physics_frame
		var p := Vector3(car.global_position.x, 0.0, car.global_position.z)
		var progress := route.get_closest_offset(p)
		if not measuring and progress >= measure_start_m:
			measuring = true
			if _graphical:
				_last_frame_usec = 0
				process_frame.connect(_sample_frame)
		if progress >= total_len - 4.0:
			break

		var speed_mps := maxf(adapter.get_forward_speed_mps(), 0.0)
		var lookahead := clampf(5.0 + speed_mps * 0.36, 5.0, 22.0)
		var target := route.sample_baked(minf(progress + lookahead, total_len))
		var car_fwd := -car.global_basis.z
		car_fwd.y = 0.0
		var aim := target - p
		var yaw_error := car_fwd.signed_angle_to(aim, Vector3.UP)
		var wheel_angle := atan2(2.71 * 2.0 * sin(yaw_error), maxf(aim.length(), 1.0))
		var steer := clampf(signf(wheel_angle) * pow(absf(wheel_angle) / car.max_steering_angle, 1.0 / car.steering_exponent) * 1.12, -1.0, 1.0)
		var speed_err := TARGET_SPEED_MPS - speed_mps
		Input.action_release("drive_left")
		Input.action_release("drive_right")
		if absf(steer) > 0.005:
			Input.action_press("drive_left" if steer > 0.0 else "drive_right", absf(steer))
		var throttle_amt := clampf(0.55 + speed_err * 0.25, 0.0, 1.0)
		var brake_amt := clampf((-speed_err - 1.5) * 0.22, 0.0, 0.65)
		if throttle_amt > 0.01:
			Input.action_press("drive_throttle", throttle_amt)
		else:
			Input.action_release("drive_throttle")
		if brake_amt > 0.01:
			Input.action_press("drive_brake", brake_amt)
		else:
			Input.action_release("drive_brake")
		if measuring:
			_speeds_mph.append(adapter.get_speed_mps() * 2.236936)

	for action in ["drive_left", "drive_right", "drive_throttle", "drive_brake"]:
		Input.action_release(action)
	if _graphical and process_frame.is_connected(_sample_frame):
		process_frame.disconnect(_sample_frame)

	_report_cedar_metrics(total_len - measure_start_m)

func _sample_frame() -> void:
	var now := Time.get_ticks_usec()
	if _last_frame_usec != 0:
		_frame_times.append((now - _last_frame_usec) / 1000.0)
		_gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid))
		_cpu_times.append(RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid))
		_draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_primitives.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		_peak_static_bytes = maxi(_peak_static_bytes, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
		_peak_video_bytes = maxi(_peak_video_bytes, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	_last_frame_usec = now

func _percentile_f(sorted: PackedFloat64Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	var idx := clampi(int(floor(q * (sorted.size() - 1))), 0, sorted.size() - 1)
	return sorted[idx]

func _report_cedar_metrics(corridor_m: float) -> void:
	if _frame_times.is_empty():
		print("CEDAR_PERF headless or no frames measured (corridor_m=%.1f)" % corridor_m)
		return
	var ft := _frame_times.duplicate()
	ft.sort()
	var gt := _gpu_times.duplicate()
	gt.sort()
	var ct := _cpu_times.duplicate()
	ct.sort()
	var sp := _speeds_mph.duplicate()
	sp.sort()
	var dc := _draw_calls.duplicate()
	dc.sort()
	var pr := _primitives.duplicate()
	pr.sort()

	var total_ms := 0.0
	for v in ft:
		total_ms += v
	var slow_n := maxi(1, ceili(ft.size() * 0.01))
	var slow_ms := 0.0
	for i in slow_n:
		slow_ms += ft[-1 - i]

	print("CEDAR_PERF scale=%.2f preset=%s aa=%s window=%s corridor_m=%.1f frames=%d speed_mph=[%.1f..%.1f..%.1f] mean_fps=%.1f 1%%_low_fps=%.1f ft_ms=[med=%.2f p95=%.2f p99=%.2f] gpu_ms=[med=%.2f p95=%.2f p99=%.2f] cpu_ms=[med=%.2f p95=%.2f] draw_calls=[med=%d max=%d] prims=[med=%d max=%d] static_MiB=%.1f video_MiB=%.1f" % [
		_scale, _preset, _aa_override, root.size, corridor_m, ft.size(),
		sp[0] if not sp.is_empty() else 0.0,
		_percentile_f(sp, 0.5),
		sp[-1] if not sp.is_empty() else 0.0,
		ft.size() * 1000.0 / total_ms,
		slow_n * 1000.0 / slow_ms,
		_percentile_f(ft, 0.5), _percentile_f(ft, 0.95), _percentile_f(ft, 0.99),
		_percentile_f(gt, 0.5), _percentile_f(gt, 0.95), _percentile_f(gt, 0.99),
		_percentile_f(ct, 0.5), _percentile_f(ct, 0.95),
		dc[dc.size() / 2], dc[-1],
		pr[pr.size() / 2], pr[-1],
		_peak_static_bytes / 1048576.0, _peak_video_bytes / 1048576.0])
