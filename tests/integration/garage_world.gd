extends SceneTree

const Drive = preload("res://scripts/integration/aster_valley_drive.gd")
const CuratedCar = preload("res://scripts/integration/curated_car_visual.gd")
const Save = preload("res://modules/game_shell/scripts/save_service.gd")
const Shell = preload("res://scripts/integration/valley_game_shell.gd")

var failures := 0
var capture_dir := ""
var mounted_ids: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS ", what)
	else:
		failures += 1
		push_error("FAIL " + what)

func _frames(count := 4) -> void:
	for frame in count:
		await process_frame

func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event)
	await _frames()
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await _frames()

func _capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png")) == OK, "capture " + name)

func _add_game(profile: String) -> Node:
	var main: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var instance := main.instantiate()
	instance.get_node("GameShell").save_path = profile
	root.add_child(instance)
	await _frames()
	return instance

func _select_next(shell: Shell, car_id: String) -> void:
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_check(shell.inspected_car == car_id, "garage focuses " + car_id)
	await _key(KEY_RIGHT)
	var button := root.gui_get_focus_owner() as Button
	_check(button != null and button.text == "SELECT VEHICLE", "keyboard can reach Select Vehicle")
	await _key(KEY_ENTER)
	_check(shell.save.selected_car() == car_id, "garage saves " + car_id)

func _assert_preview(shell: Shell, id: String) -> void:
	var preview := shell.find_child("CuratedCar", true, false)
	_check(preview != null and preview.scene_file_path.ends_with(id + ".glb")
		and preview.find_child("Wheel_FL_Pivot") != null, "garage renders authored " + id)

func _assert_car(drive: Drive, id: String) -> void:
	var body := drive.vehicle_body
	var preset: Dictionary = PlayerCarFactory.PRESETS[id]
	_check(body != null and drive.active_vehicle_id == id and body.get_meta("vehicle_id") == id,
		"live chassis identity is " + id)
	if body == null:
		return
	_check(is_equal_approx(body.mass, preset["mass"]) and is_equal_approx(body.max_torque, preset["torque"])
		and is_equal_approx(body.front_torque_split, preset["front_split"])
		and is_equal_approx(body.final_drive, preset["final_drive"]), "GEVP applies physical preset " + id)
	_check(drive.camera.target == body and drive.adapter.vehicle == body, "one current physics and camera target")
	var fallback := body.get_node("FallbackBody") as Node3D
	_check(not fallback.visible and fallback.get_child_count() > 0, "fallback body hidden and available")
	var model := body.get_node_or_null("CuratedCar")
	_check(model != null and model.scene_file_path.ends_with(id + ".glb")
		and model.find_child("Wheel_FL_Pivot") == null, "real chassis model fitted and wheel geometry moved out")
	_check(body.get_node("CameraMounts/Cockpit") is Marker3D and body.get_node("CameraMounts/Hood") is Marker3D,
		"chassis camera mounts available")
	_check(body.wheel_array.size() == 4 and body.wheel_array.all(func(wheel: Wheel) -> bool:
		var rolling := wheel.wheel_node.get_child(2) as Node3D if wheel.wheel_node.get_child_count() == 3 else null
		return (wheel.wheel_node.get_parent() == wheel and rolling != null
			and rolling.position.is_zero_approx() and not wheel.wheel_node.get_node("Rubber").visible
			and not wheel.wheel_node.get_node("Hub").visible)),
		"all wheel visual pivots are driven by GEVP")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var capture := args.find("--capture-dir")
	if capture >= 0 and capture + 1 < args.size():
		capture_dir = args[capture + 1]
	var verify := args.find("--verify-profile")
	if verify >= 0 and verify + 1 < args.size():
		await _verify_reload(args[verify + 1])
		_finish()
		return

	var profile := "user://garage_world_qa_%d.json" % Time.get_ticks_usec()
	var instance := await _add_game(profile)
	var shell: Shell = instance.get_node("GameShell")
	shell.free_roam_created.connect(func(driver: Drive) -> void:
		driver.vehicle_spawned.connect(_observe_mounts))
	_check(shell.screen == "MENU" and shell.drive == null, "real game opens Shell menu before loading the world")

	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	_check(shell.screen == "GARAGE", "keyboard opens the garage from the main menu")
	_assert_preview(shell, "vela_gt")
	await _capture("garage-vela-gt")
	var fallback_car := PlayerCarFactory.create()
	_check(not CuratedCar.mount(fallback_car, "missing") and fallback_car.get_node("FallbackBody").visible
		and fallback_car.get_node("FrontLeft/WheelVisual/Rubber").visible, "missing art leaves original appearance intact")
	fallback_car.free()
	await _select_next(shell, "orion_rs")
	_assert_preview(shell, "orion_rs")
	await _capture("01-menu-garage-orion")
	await _key(KEY_ESCAPE)
	await _key(KEY_ENTER)
	await _ticks(125)
	var drive := shell.drive
	_check(shell.screen == "FREE_ROAM" and drive != null and not paused, "Play starts live full-world driving")
	if drive == null or drive.vehicle_body == null:
		_finish()
		return
	_assert_car(drive, "orion_rs")
	_assert_scenery(drive)
	await _capture("02-orion-free-roam")
	var start := drive.vehicle_body.global_position
	Input.action_press("drive_throttle")
	await _ticks(180)
	Input.action_release("drive_throttle")
	_check(drive.adapter.get_speed_mps() > 3.0 and drive.vehicle_body.global_position.distance_to(start) > 4.0,
		"real Orion moves on the world road")
	_check(absf(drive.vehicle_body.front_left_wheel.wheel_node.rotation.x) > 0.01,
		"wheel visual rolls with actual vehicle motion")
	await _key(KEY_G)
	_check(shell.screen == "FREE_ROAM" and not paused, "garage is blocked while moving")
	await _key(KEY_ESCAPE)
	await _key(KEY_G)
	_check(shell.screen == "PAUSE" and paused, "pausing while moving cannot bypass the garage gate")
	await _key(KEY_ESCAPE)

	await _tap("drive_camera")
	await _tap("drive_camera")
	_check(drive.camera.mode == 2, "close chase camera switches on the live car")
	await _tap("drive_camera")
	_check(drive.camera.mode == 3, "hood camera switches on the live car")
	await _tap("drive_reset")
	await _ticks(60)
	_check(drive.adapter.get_speed_mps() < 1.1 and drive.vehicle_body.current_gear == 0,
		"reset parks the active car and clears its gear")
	await _key(KEY_G)
	_check(shell.screen == "GARAGE" and paused, "parked G opens the real garage")
	var old := drive.vehicle_body
	var parked_at := old.global_position
	await _select_next(shell, "kestrel_xr")
	_assert_preview(shell, "kestrel_xr")
	await _ticks(12)
	_assert_car(drive, "kestrel_xr")
	_check(mounted_ids == ["orion_rs", "kestrel_xr"], "visual hook receives both production chassis")
	_check(not is_instance_valid(old) and drive.vehicle_body.global_position.distance_to(parked_at) < 0.02,
		"parked replacement removes the old body and keeps its position")
	await _capture("03-parked-garage-kestrel")
	await _key(KEY_BACKSPACE)
	await _ticks(60)
	_check(shell.screen == "FREE_ROAM" and not paused and drive.camera.mode == 3, "back resumes driving in the saved view")
	var hood := drive.vehicle_body.get_node("CameraMounts/Hood") as Marker3D
	_check(hood.global_position.distance_to(drive.camera.global_position) < 0.10, "hood follows the new chassis anchor")
	await _capture("04-kestrel-hood")
	await _tap("drive_camera")
	await _ticks(10)
	await _capture("05-kestrel-chase")

	_check(drive.vehicle_body.wheel_array.all(func(wheel: Wheel) -> bool: return wheel.is_colliding()),
		"replaced car settles onto all four wheels")
	await _capture_regions(drive)
	var reopened := Save.new(profile)
	reopened.load()
	_check(reopened.selected_car() == "kestrel_xr", "physical car selection persists to disk")
	print("GARAGE PROFILE ", profile)
	instance.queue_free()
	await _frames()
	_finish()

func _assert_scenery(drive: Drive) -> void:
	var bodies := drive.world.find_children("*", "StaticBody3D", true, false)
	_check(bodies.size() == drive.world.report.get("static_colliders", 0), "world collider count matches the report")
	if drive.scenery != null:
		var placements: int = drive.scenery.report.get("placements", 0)
		var displaced: int = drive.scenery.report.get("displaced_by_roadworks", 0)
		var rejected := 0
		for count: int in drive.scenery.report.get("rejected_for_clearance", {}).values():
			rejected += count
		_check(drive.scenery.report.get("regions", 0) == 5 and placements + displaced + rejected == 2791
			and drive.scenery.report.get("height_mismatches", -1) == 0
			and drive.scenery.report.get("selective_colliders", -1) > 0, "five authored scenery packs built with selective colliders")
	else:
		_check(false, "five authored scenery packs built")
	if drive.scenery != null:
		print("SCENERY ", drive.scenery.report)
	_check(drive.set_scenery_enabled(false) and drive.scenery == null
		and drive.world.find_children("*", "StaticBody3D", true, false) == bodies, "toggle off keeps the same world colliders")
	_check(drive.set_scenery_enabled(true) and drive.scenery != null
		and drive.world.find_children("*", "StaticBody3D", true, false) == bodies, "toggle on keeps the same world colliders")

func _capture_regions(drive: Drive) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	# Road points chosen to show the forest stand, ridge guardrails, and lakeshore.
	var landmarks := {
		"cedar_woods": Vector3(-870, 0, -154),
		"north_ridge": Vector3(549, 0, -779),
		"eastwater_lake": Vector3(630, 0, 495),
	}
	var headings := [Vector3.RIGHT, Vector3(1, 0, -1), Vector3(1, 0, 1), Vector3.RIGHT, Vector3(1, 0, -1)]
	var regions: Array = drive.world.get_world_metadata()["regions"]
	for i in range(regions.size()):
		var region: Dictionary = regions[i]
		var center: Array = region["center"]
		var near: Vector3 = landmarks.get(region["id"], Vector3(center[0], 0, center[1]))
		var pose: Variant = drive.find_road_pose(near, headings[i])
		_check(pose != null, "road pose in " + region["name"])
		if pose == null:
			continue
		drive.adapter.reset_to(pose)
		drive.camera.snap_to_vehicle()
		await _ticks(72)
		_check(drive.vehicle_body.wheel_array.all(func(wheel: Wheel) -> bool: return wheel.is_colliding()),
			"all road wheel contacts in " + region["name"])
		await _capture("region-" + region["id"])
		if region["id"] == "eastwater_lake":
			# Elevated photo angle over the live chassis to show the basin below the road.
			var photo := Camera3D.new()
			drive.add_child(photo)
			var p := drive.vehicle_body.global_position
			photo.position = p + Vector3(-22, 18, -10)
			photo.look_at(p + Vector3(21, -5, 9))
			photo.make_current()
			await _capture("eastwater-overlook")
			drive.camera.make_current()
			photo.queue_free()

func _observe_mounts(body: Vehicle, id: String) -> void:
	if body.wheel_array.size() == 4 and body.has_node("FallbackBody") and body.has_node("CameraMounts/Hood"):
		mounted_ids.append(id)

func _verify_reload(profile: String) -> void:
	var instance := await _add_game(profile)
	var shell: Shell = instance.get_node("GameShell")
	_check(shell.save.selected_car() == "kestrel_xr", "fresh process reads Kestrel selection")
	await _key(KEY_ENTER)
	await _ticks(100)
	if shell.drive != null:
		_assert_car(shell.drive, "kestrel_xr")
	else:
		_check(false, "fresh process starts world")
	instance.queue_free()
	await _frames()

func _tap(action: StringName) -> void:
	await process_frame
	Input.action_press(action)
	await _ticks(10)
	Input.action_release(action)

func _finish() -> void:
	print("GARAGE WORLD failures: ", failures)
	quit(0 if failures == 0 else 1)
