extends SceneTree

const GAME := preload("res://scenes/bootstrap/game.tscn")
const VIEWS := [
	["alder", Vector3(-575, 0, 545), Vector3.RIGHT],
	["cedar", Vector3(-870, 0, -154), Vector3(1, 0, -1)],
	["ridge", Vector3(549, 0, -779), Vector3(1, 0, 1)],
	["valley", Vector3(72, 0, 170), Vector3.RIGHT],
	["eastwater", Vector3(630, 0, 495), Vector3(1, 0, -1)],
]
var output := ""
var rid: RID
var view: SubViewport

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if OS.get_cmdline_user_args().is_empty():
		print("Pass an absolute screenshot output directory after --")
		quit(1)
		return
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	view = SubViewport.new()
	view.size = Vector2i(1920, 1080)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var preview := TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.texture = view.get_texture()
	root.add_child(preview)
	rid = view.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var game := GAME.instantiate()
	var shell = game.get_node("GameShell")
	shell.save_path = "user://visual-qa-%d.json" % Time.get_ticks_usec()
	view.add_child(game)
	await frames(20)
	shell.open_garage()
	await frames(40)
	await photo("garage")
	if PlayerCarFactory.PRESETS.has("solace_gt"):
		shell._inspect("solace_gt")
		await frames(38)
		await photo("garage-solace")
	for id in ["aventador_svj", "mclaren_senna"]:
		if PlayerCarFactory.PRESETS.has(id):
			shell._inspect(id)
			await frames(38)
			await photo("garage-" + id)
	shell._inspect("vela_gt")
	shell.enter_free_roam()
	var drive = shell.drive
	for i in 500:
		await process_frame
		if drive != null and drive.vehicle_body != null:
			break
	if drive == null or drive.vehicle_body == null:
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var medium_only := "--medium-only" in args
	if args.size() > 1 and not medium_only:
		audit_legacy(drive, args[1])
	var presets := ["medium"] if medium_only else ["medium", "low", "high"]
	for quality in presets:
		var applied: bool = shell._save_option("graphics_quality", quality)
		print("QUALITY ", quality, " applied=", applied, " viewport_scale=", view.scaling_3d_scale)
		if not applied:
			quit(1)
			return
		for shot in VIEWS:
			var pose = drive.find_road_pose(shot[1], shot[2])
			if pose == null:
				print("NO_POSE ", shot[0])
				continue
			drive.adapter.reset_to(pose)
			drive.camera.snap_to_vehicle()
			await frames(32)
			if quality == "medium":
				await photo(shot[0])
				Input.action_press("drive_throttle", 0.48)
			await measure(quality + "-" + shot[0], 120)
			Input.action_release("drive_throttle")
	shell._save_option("graphics_quality", "medium")
	var regions := [VIEWS[2], VIEWS[4]]
	for i in regions.size():
		var id: String = ["aventador_svj", "mclaren_senna"][i]
		if not PlayerCarFactory.PRESETS.has(id):
			continue
		var site: Array = regions[i]
		var pose = drive.find_road_pose(site[1], site[2])
		if pose != null:
			drive._spawn_vehicle(id, pose)
			await frames(42)
			await photo("road-" + id)
			Input.action_press("drive_throttle", 0.66)
			await measure("medium-" + id, 120)
			Input.action_release("drive_throttle")
	quit()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func photo(label: String) -> void:
	await RenderingServer.frame_post_draw
	var pic := view.get_texture().get_image()
	print("CAPTURE ", label, " ", pic.get_size(), " ", pic.save_png(output.path_join(label + ".png")))

func audit_legacy(drive: Node, path: String) -> void:
	var script := load(path) as Script
	if script == null:
		return
	var index = script.new()
	for node: MeshInstance3D in drive.world.find_children("*", "MeshInstance3D", true, false):
		if node.name.begins_with("Road_") or node.name.begins_with("Junction_"):
			for surface in node.mesh.get_surface_count():
				index.add_surface(node.mesh, surface, node.global_transform)
	var legacy := drive.get_node_or_null("PremiumFoliageRuntime")
	if legacy == null:
		return
	var overlaps := 0
	var on_pavement := 0
	var total := 0
	for node: MultiMeshInstance3D in legacy.find_children("*", "MultiMeshInstance3D", true, false):
		var mesh := node.multimesh
		for i in mesh.instance_count:
			var bounds := node.global_transform * mesh.get_instance_transform(i) * mesh.mesh.get_aabb()
			total += 1
			if index.overlaps(bounds):
				overlaps += 1
			if index.overlaps(bounds, 0.0, false):
				on_pavement += 1
	print("LEGACY_BOUNDS total=", total, " pavement=", on_pavement, " pavement_or_shoulder=", overlaps)

func quantile(data: Array[float], fraction: float) -> float:
	if data.is_empty():
		return -1.0
	data.sort()
	return data[floori((data.size() - 1) * fraction)]

func measure(label: String, frames_to_read: int) -> void:
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var present: Array[float] = []
	var start := Time.get_ticks_usec()
	var prev := start
	for i in frames_to_read:
		await process_frame
		var now := Time.get_ticks_usec()
		present.append((now - prev) / 1000.0)
		prev = now
		var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		var cpu_ms := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		if gpu_ms > 0:
			gpu.append(gpu_ms)
		if cpu_ms > 0:
			cpu.append(cpu_ms)
	print("PERF %s %s" % [label, JSON.stringify({
		"fps": 1000000.0 * frames_to_read / float(prev - start), "frame_p50": quantile(present, 0.50), "frame_p95": quantile(present, 0.95), "frame_p99": quantile(present, 0.99),
		"gpu_p50": quantile(gpu, 0.50), "gpu_p95": quantile(gpu, 0.95), "gpu_p99": quantile(gpu, 0.99), "cpu_p50": quantile(cpu, 0.50), "cpu_p95": quantile(cpu, 0.95), "cpu_p99": quantile(cpu, 0.99),
		"draws": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"vram_mib": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
	})])
