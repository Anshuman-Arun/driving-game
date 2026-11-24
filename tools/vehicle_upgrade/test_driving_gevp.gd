extends SceneTree
## Real GEVP driving-scale test for VehicleVisualAdapter + prepared Vela GT LODs.
## Verifies wheel pivot alignment, suspension compression, steering animation,
## wheel spin (with stationary brake calipers), LOD switching, and 1920x1080 driving perf.
##
## Run:
##   godot --path . --resolution 1920x1080 --script res://tools/vehicle_upgrade/test_driving_gevp.gd -- --out-dir=PATH

const ADAPTER_SCRIPT = preload("res://modules/vehicle_visuals/vehicle_visual_adapter.gd")

var out_dir := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			out_dir = arg.trim_prefix("--out-dir=").strip_edges()
	call_deferred("_run")

func _run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var win := root.get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var vp := root.get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)

	if not out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(out_dir)

	var stage := Node3D.new()
	stage.name = "DrivingQATestStage"
	root.add_child(stage)

	# Outdoor daylight environment
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.24, 0.48, 0.80)
	sky_mat.sky_horizon_color = Color(0.74, 0.85, 0.95)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	world_env.environment = env
	stage.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	stage.add_child(sun)

	# Flat road surface with physics collider (layer 1)
	var ground_body := StaticBody3D.new()
	ground_body.name = "Road"
	ground_body.collision_layer = 1
	ground_body.collision_mask = 0
	var ground_col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(240.0, 1.0, 240.0)
	ground_col.shape = box
	ground_col.position = Vector3(0.0, -0.5, 0.0)
	ground_body.add_child(ground_col)

	var road_mesh := MeshInstance3D.new()
	var road_plane := PlaneMesh.new()
	road_plane.size = Vector2(6.8, 240.0)
	road_mesh.mesh = road_plane
	road_mesh.position.y = 0.002
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.18, 0.19, 0.21)
	road_mat.roughness = 0.85
	road_mesh.material_override = road_mat
	ground_body.add_child(road_mesh)

	var grass_mesh := MeshInstance3D.new()
	var grass_plane := PlaneMesh.new()
	grass_plane.size = Vector2(240.0, 240.0)
	grass_mesh.mesh = grass_plane
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_color = Color(0.28, 0.40, 0.24)
	grass_mat.roughness = 0.92
	grass_mesh.material_override = grass_mat
	ground_body.add_child(grass_mesh)
	stage.add_child(ground_body)

	# Spawn real GEVP PlayerCarFactory vehicle (untouched physics)
	var car: Vehicle = PlayerCarFactory.create()
	car.position = Vector3(0.0, 0.65, 0.0)
	stage.add_child(car)

	var adapter: Node3D = ADAPTER_SCRIPT.attach_to(car)
	var status: Dictionary = adapter.get_visual_status()
	var vehicle_adapter := VehicleAdapter.new(car)

	var camera := Camera3D.new()
	camera.fov = 52.0
	camera.current = true
	stage.add_child(camera)

	# Let suspension settle for 45 physics frames
	for _i in range(45):
		await physics_frame
	await process_frame

	var rest_fl_y: float = car.front_left_wheel.wheel_node.position.y
	var rest_rl_y: float = car.rear_left_wheel.wheel_node.position.y
	var initial_spin_fl: float = car.front_left_wheel.wheel_node.rotation.x

	# Drive forward and execute a realistic left turn
	var dt_ms: Array[float] = []
	var prev_us := Time.get_ticks_usec()
	for step in range(150):
		var steer := 0.0
		if step >= 50 and step < 120:
			steer = 0.72
		elif step >= 120:
			steer = -0.45
		vehicle_adapter.set_drive_input(steer, 0.68, 0.0, false)
		await physics_frame
		# Position chase/quarter camera relative to moving car
		var car_pos := car.global_position
		var car_fwd := -car.global_basis.z
		var car_right := car.global_basis.x
		camera.global_position = car_pos - car_fwd * 4.9 + car_right * 2.1 + Vector3(0.0, 1.45, 0.0)
		camera.look_at(car_pos + Vector3(0.0, 0.35, 0.0), Vector3.UP)
		await process_frame
		var now_us := Time.get_ticks_usec()
		dt_ms.append(float(now_us - prev_us) / 1000.0)
		prev_us = now_us

		if step == 95 and not out_dir.is_empty():
			# Capture mid-turn shot showing front steering angle + suspension + road scale
			var img := vp.get_texture().get_image()
			var shot_path := out_dir.path_join("driving_turn_1080p.png")
			img.save_png(shot_path)
			print("[DRIVING_SHOT] ", shot_path)
			# Also capture front-left wheel close-up during steer
			var fl_world: Vector3 = car.front_left_wheel.wheel_node.global_position
			camera.global_position = fl_world - car_right * 1.45 + car_fwd * 1.15 + Vector3(0.0, 0.25, 0.0)
			camera.look_at(fl_world, Vector3.UP)
			await process_frame
			await process_frame
			var img2 := vp.get_texture().get_image()
			var shot2 := out_dir.path_join("driving_front_steer_wheel.png")
			img2.save_png(shot2)
			print("[DRIVING_SHOT] ", shot2)

	var steered_fl_yaw_deg: float = rad_to_deg(car.front_left_wheel.rotation.y)
	var steered_rl_yaw_deg: float = rad_to_deg(car.rear_left_wheel.rotation.y)
	var final_spin_fl: float = car.front_left_wheel.wheel_node.rotation.x
	var brake_fl: Node3D = car.front_left_wheel.find_child("Brake_FL", true, false) as Node3D
	var brake_spin_x: float = brake_fl.rotation.x if brake_fl != null else -999.0
	var brake_y_delta: float = absf(brake_fl.position.y - car.front_left_wheel.wheel_node.position.y) if brake_fl != null else -1.0
	var speed_mps: float = vehicle_adapter.get_speed_mps()

	# Verify LOD switching
	var lod1_ok: bool = adapter.request_lod(1)
	var lod2_ok: bool = adapter.request_lod(2)
	var lod0_ok: bool = adapter.request_lod(0)

	# Compute driving FPS & 1% lows
	var sorted := dt_ms.duplicate()
	sorted.sort()
	var n := sorted.size()
	var sum_dt := 0.0
	for v in dt_ms:
		sum_dt += v
	var avg_dt := sum_dt / float(max(n, 1))
	var p99_dt: float = sorted[mini(n - 1, int(ceil(float(n) * 0.99)) - 1)] if n > 0 else 0.0

	var hidden_factory_boxes := 0
	for c in car.get_children():
		if c is MeshInstance3D and not (c as Node3D).visible:
			hidden_factory_boxes += 1

	var report := {
		"adapter_status": status,
		"hidden_factory_boxes": hidden_factory_boxes,
		"rest_suspension_fl_y": snapped(rest_fl_y, 0.001),
		"rest_suspension_rl_y": snapped(rest_rl_y, 0.001),
		"final_speed_mps": snapped(speed_mps, 0.01),
		"front_steer_yaw_deg": snapped(steered_fl_yaw_deg, 0.01),
		"rear_steer_yaw_deg": snapped(steered_rl_yaw_deg, 0.01),
		"wheel_spin_delta_rad": snapped(absf(final_spin_fl - initial_spin_fl), 0.01),
		"brake_caliper_spin_x": snapped(brake_spin_x, 0.001),
		"brake_caliper_suspension_y_error": snapped(brake_y_delta, 0.001),
		"lod_switch_ok": [lod1_ok, lod2_ok, lod0_ok],
		"perf_1080p": {
			"avg_fps": snapped(1000.0 / maxf(avg_dt, 0.001), 0.1),
			"low_1pct_fps": snapped(1000.0 / maxf(p99_dt, 0.001), 0.1),
			"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"video_mem_mb": snapped(float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / (1024.0 * 1024.0), 0.01),
		}
	}
	print("[DRIVING_GEVP_JSON] ", JSON.stringify(report))
	quit(0)
