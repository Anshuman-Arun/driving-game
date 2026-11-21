extends SceneTree
## Reusable Vehicle Visual-Quality Showcase & Benchmark Harness (Godot 4.7.2 / Forward+)
## Inspects one or more vehicle GLB/GLTF models under identical studio and outdoor road lighting,
## captures 6 standardized camera angles per model, audits hierarchy/wheels/interior/bounds,
## and benchmarks draw calls, VRAM, and frame times at 1920x1080 and 3440x1440.
##
## Usage:
##   godot --path . --resolution 1920x1080 --script res://tests/vehicle_showcase/vehicle_showcase.gd -- --out-dir=PATH
##   Optional flags:
##     --models=res://path/a.glb,res://path/b.glb
##     --skip-screenshots
##     --bench-only

const DEFAULT_MODELS: Array[String] = [
	"res://assets/curated/models/vehicles/vela_gt.glb",
	"res://assets/curated/models/vehicles/orion_rs.glb",
	"res://assets/curated/models/vehicles/kestrel_xr.glb",
	"res://assets/curated/models/vehicle/vela_gt.glb",
]

var model_paths: Array[String] = []
var out_dir: String = ""
var skip_screenshots: bool = false
var bench_only: bool = false
var target_res := Vector2i(1920, 1080)
var rotate_y_deg: float = 0.0

var stage_root: Node3D
var studio_group: Node3D
var outdoor_group: Node3D
var car_mount: Node3D
var camera: Camera3D
var world_env: WorldEnvironment

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--models="):
			var raw := arg.trim_prefix("--models=").strip_edges()
			for item in raw.split(","):
				var cleaned := item.strip_edges()
				if not cleaned.is_empty():
					model_paths.append(cleaned)
		elif arg.begins_with("--out-dir="):
			out_dir = arg.trim_prefix("--out-dir=").strip_edges()
		elif arg == "--skip-screenshots":
			skip_screenshots = true
		elif arg == "--bench-only":
			bench_only = true
			skip_screenshots = true
		elif arg.begins_with("--res="):
			var parts := arg.trim_prefix("--res=").split("x")
			if parts.size() == 2:
				target_res = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("--rotate-y="):
			rotate_y_deg = float(arg.trim_prefix("--rotate-y="))
	if model_paths.is_empty():
		model_paths = DEFAULT_MODELS.duplicate()
	call_deferred("_run")

func _run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var win := root.get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(target_res)
	var vp := root.get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)

	stage_root = Node3D.new()
	stage_root.name = "VehicleShowcaseRoot"
	root.add_child(stage_root)

	world_env = WorldEnvironment.new()
	stage_root.add_child(world_env)

	camera = Camera3D.new()
	camera.name = "ShowcaseCamera"
	camera.near = 0.05
	camera.far = 2000.0
	camera.fov = 38.0
	camera.current = true
	stage_root.add_child(camera)

	car_mount = Node3D.new()
	car_mount.name = "CarMount"
	stage_root.add_child(car_mount)

	_build_studio_stage()
	_build_outdoor_stage()

	if not out_dir.is_empty() and not skip_screenshots:
		DirAccess.make_dir_recursive_absolute(out_dir)

	await process_frame
	await process_frame

	var tex_sz := vp.get_texture().get_size()
	var report := {
		"gpu": RenderingServer.get_video_adapter_name(),
		"render_resolution": [tex_sz.x, tex_sz.y],
		"msaa": "4x",
		"models": []
	}

	for path in model_paths:
		var slug := _model_slug(path)
		var entry := await _evaluate_model(vp, path, slug)
		report["models"].append(entry)

	# 4-car grid benchmark (first model x4 in outdoor road setting)
	if not model_paths.is_empty():
		report["grid_4car_outdoor_bench"] = await _benchmark_4car_grid(vp, model_paths[0])

	print("[VEHICLE_SHOWCASE_JSON] ", JSON.stringify(report))
	quit(0)

func _model_slug(path: String) -> String:
	var parts := path.split("/")
	var fname := parts[-1].get_basename()
	var parent := parts[-2] if parts.size() >= 2 else "model"
	return parent + "_" + fname

func _build_studio_stage() -> void:
	studio_group = Node3D.new()
	studio_group.name = "StudioStage"
	stage_root.add_child(studio_group)

	# Neutral matte studio floor with subtle grid reference
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.18, 0.19, 0.21)
	floor_mat.roughness = 0.72
	floor_mat.metallic = 0.05
	floor_mesh.material_override = floor_mat
	studio_group.add_child(floor_mesh)

	# 3-point studio lighting
	var key := DirectionalLight3D.new()
	key.name = "StudioKey"
	key.rotation_degrees = Vector3(-42.0, 32.0, 0.0)
	key.light_color = Color(1.0, 0.98, 0.95)
	key.light_energy = 1.65
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 35.0
	studio_group.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "StudioFill"
	fill.rotation_degrees = Vector3(-25.0, -135.0, 0.0)
	fill.light_color = Color(0.80, 0.88, 1.0)
	fill.light_energy = 0.65
	studio_group.add_child(fill)

	var rim := DirectionalLight3D.new()
	rim.name = "StudioRim"
	rim.rotation_degrees = Vector3(-20.0, 165.0, 0.0)
	rim.light_color = Color(0.95, 0.97, 1.0)
	rim.light_energy = 0.75
	studio_group.add_child(rim)

func _build_outdoor_stage() -> void:
	outdoor_group = Node3D.new()
	outdoor_group.name = "OutdoorRoadStage"
	outdoor_group.visible = false
	stage_root.add_child(outdoor_group)

	var sun := DirectionalLight3D.new()
	sun.name = "OutdoorSun"
	sun.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	outdoor_group.add_child(sun)

	# 6.8 m Aster Valley two-way asphalt strip + shoulders + grass apron
	var road := MeshInstance3D.new()
	var road_plane := PlaneMesh.new()
	road_plane.size = Vector2(6.8, 120.0)
	road.mesh = road_plane
	road.position = Vector3(0.0, 0.002, 0.0)
	var asphalt_mat: Material = load("res://assets/curated/materials/asphalt.tres") if ResourceLoader.exists("res://assets/curated/materials/asphalt.tres") else null
	if asphalt_mat == null:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.21, 0.23, 0.25)
		fallback.roughness = 0.8
		asphalt_mat = fallback
	road.material_override = asphalt_mat
	outdoor_group.add_child(road)

	var shoulder := MeshInstance3D.new()
	var sh_plane := PlaneMesh.new()
	sh_plane.size = Vector2(9.5, 120.0)
	shoulder.mesh = sh_plane
	shoulder.position = Vector3(0.0, 0.001, 0.0)
	var soil_mat: Material = load("res://assets/curated/materials/soil.tres") if ResourceLoader.exists("res://assets/curated/materials/soil.tres") else null
	if soil_mat == null:
		var fb_s := StandardMaterial3D.new()
		fb_s.albedo_color = Color(0.36, 0.33, 0.28)
		fb_s.roughness = 0.92
		soil_mat = fb_s
	shoulder.material_override = soil_mat
	outdoor_group.add_child(shoulder)

	var grass := MeshInstance3D.new()
	var gr_plane := PlaneMesh.new()
	gr_plane.size = Vector2(180.0, 180.0)
	grass.mesh = gr_plane
	var grass_mat: Material = load("res://assets/curated/materials/grass.tres") if ResourceLoader.exists("res://assets/curated/materials/grass.tres") else null
	if grass_mat == null:
		var fb_g := StandardMaterial3D.new()
		fb_g.albedo_color = Color(0.30, 0.42, 0.25)
		fb_g.roughness = 0.92
		grass_mat = fb_g
	grass.material_override = grass_mat
	outdoor_group.add_child(grass)

func _set_mode(outdoor: bool) -> void:
	studio_group.visible = not outdoor
	outdoor_group.visible = outdoor
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	if outdoor:
		sky_mat.sky_top_color = Color(0.24, 0.48, 0.80)
		sky_mat.sky_horizon_color = Color(0.74, 0.85, 0.95)
		sky_mat.ground_bottom_color = Color(0.20, 0.26, 0.18)
		sky_mat.ground_horizon_color = Color(0.54, 0.62, 0.55)
		env.ambient_light_energy = 0.70
	else:
		sky_mat.sky_top_color = Color(0.16, 0.18, 0.22)
		sky_mat.sky_horizon_color = Color(0.28, 0.30, 0.34)
		sky_mat.ground_bottom_color = Color(0.10, 0.11, 0.13)
		sky_mat.ground_horizon_color = Color(0.22, 0.23, 0.26)
		env.ambient_light_energy = 0.85
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	world_env.environment = env

func _clear_mount() -> void:
	for child in car_mount.get_children():
		car_mount.remove_child(child)
		child.free()

func _evaluate_model(vp: Viewport, path: String, slug: String) -> Dictionary:
	_clear_mount()
	var packed = load(path)
	if packed == null or not (packed is PackedScene):
		return {"path": path, "slug": slug, "error": "Failed to load PackedScene"}

	var instance: Node3D = packed.instantiate()
	if not is_zero_approx(rotate_y_deg):
		instance.rotation_degrees.y = rotate_y_deg
	car_mount.add_child(instance)
	await process_frame

	var audit := _audit_hierarchy(instance)
	var aabb: AABB = audit["aabb"]
	var center := aabb.get_center()
	var size := aabb.size
	var max_dim := maxf(size.x, maxf(size.y, size.z))

	# Capture 5 standardized studio shots + 1 outdoor road shot
	_set_mode(false)
	camera.fov = 36.0
	if not skip_screenshots and not out_dir.is_empty():
		# 1. Front-quarter (-Z is forward, +X is right)
		await _snap_angle(vp, center + Vector3(max_dim * 0.82, max_dim * 0.34, -max_dim * 0.92),
			center + Vector3(0.0, -size.y * 0.06, 0.0), slug + "_01_front_quarter.png")
		# 2. Rear-quarter
		await _snap_angle(vp, center + Vector3(-max_dim * 0.82, max_dim * 0.36, max_dim * 0.92),
			center + Vector3(0.0, -size.y * 0.04, 0.0), slug + "_02_rear_quarter.png")
		# 3. Side profile (+X looking toward -X)
		camera.fov = 26.0
		await _snap_angle(vp, Vector3(center.x + max_dim * 1.55, center.y + 0.08, center.z),
			Vector3(center.x, center.y, center.z), slug + "_03_side_profile.png")
		# 4. Wheel detail (Front-Left wheel close-up)
		camera.fov = 34.0
		var fl_pos: Vector3 = audit["fl_wheel_pos"]
		await _snap_angle(vp, fl_pos + Vector3(-1.35, 0.22, -0.78),
			fl_pos + Vector3(0.0, 0.04, 0.0), slug + "_04_wheel_detail.png")
		# 5. Cockpit / windshield angle
		camera.fov = 36.0
		await _snap_angle(vp, center + Vector3(-1.65, 1.35, -1.75),
			center + Vector3(0.0, size.y * 0.22, 0.15), slug + "_05_cockpit_angle.png")

		# 6. Outdoor road chase-like framing
		_set_mode(true)
		camera.fov = 58.0
		await _snap_angle(vp, Vector3(1.15, 1.85, 5.4),
			Vector3(0.0, 0.72, -1.5), slug + "_06_outdoor_road.png")

	# Steady-state performance benchmark (120 frames, studio front-quarter)
	_set_mode(false)
	camera.fov = 36.0
	camera.position = center + Vector3(max_dim * 0.82, max_dim * 0.34, -max_dim * 0.92)
	camera.look_at(center, Vector3.UP)
	for _w in range(15):
		await process_frame
	var perf := await _measure_frames(vp, 120)

	return {
		"path": path,
		"slug": slug,
		"triangles": audit["triangles"],
		"vertices": audit["vertices"],
		"mesh_nodes": audit["mesh_nodes"],
		"surfaces": audit["surfaces"],
		"unique_materials": audit["unique_materials"],
		"textured_materials": audit["textured_materials"],
		"bounds_m": [snapped(size.x, 0.001), snapped(size.y, 0.001), snapped(size.z, 0.001)],
		"min_y_m": snapped(aabb.position.y, 0.001),
		"wheel_pivots_found": audit["wheel_pivots"],
		"interior_nodes_found": audit["interior_nodes"],
		"has_separate_4_wheels": audit["wheel_pivots"].size() >= 4,
		"has_interior_nodes": not audit["interior_nodes"].is_empty(),
		"perf": perf
	}

func _benchmark_4car_grid(vp: Viewport, path: String) -> Dictionary:
	_clear_mount()
	_set_mode(true)
	var packed = load(path)
	if packed == null:
		return {}
	var offsets := [Vector3(-1.6, 0.0, 0.0), Vector3(1.6, 0.0, -5.5), Vector3(-1.6, 0.0, -11.0), Vector3(1.6, 0.0, -16.5)]
	for off in offsets:
		var inst: Node3D = packed.instantiate()
		inst.position = off
		car_mount.add_child(inst)
	camera.fov = 60.0
	camera.position = Vector3(0.0, 2.3, 6.2)
	camera.look_at(Vector3(0.0, 0.8, -8.0), Vector3.UP)
	for _w in range(15):
		await process_frame
	return await _measure_frames(vp, 120)

func _snap_angle(vp: Viewport, pos: Vector3, look: Vector3, filename: String) -> void:
	camera.position = pos
	camera.look_at(look, Vector3.UP)
	for _k in range(3):
		await process_frame
	var img := vp.get_texture().get_image()
	var full_path := out_dir.path_join(filename)
	img.save_png(full_path)
	print("[SHOWCASE_SHOT] ", full_path)

func _audit_hierarchy(root_node: Node3D) -> Dictionary:
	var tris := 0
	var verts := 0
	var mesh_nodes := 0
	var surfaces := 0
	var mat_ids := {}
	var textured_mats := {}
	var wheel_pivots: Array[String] = []
	var interior_nodes: Array[String] = []
	var combined_aabb := AABB()
	var has_aabb := false
	var fl_pos := Vector3(-0.85, 0.36, -1.35)

	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var lname := node.name.to_lower()
		if (lname.contains("wheel") and (lname.contains("pivot") or lname.contains("fl") or lname.contains("fr") or lname.contains("rl") or lname.contains("rr"))):
			if not wheel_pivots.has(node.name):
				wheel_pivots.append(node.name)
			if lname.contains("fl") and node is Node3D:
				fl_pos = (node as Node3D).global_position
		if lname.contains("interior") or lname.contains("seat") or lname.contains("dash") or lname.contains("cockpit") or lname.contains("steering"):
			interior_nodes.append(node.name)
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			var m := mi.mesh
			if m != null:
				mesh_nodes += 1
				var local_aabb := m.get_aabb()
				var xf := mi.global_transform
				var world_aabb := xf * local_aabb
				if not has_aabb:
					combined_aabb = world_aabb
					has_aabb = true
				else:
					combined_aabb = combined_aabb.merge(world_aabb)
				for s in range(m.get_surface_count()):
					surfaces += 1
					var arr := m.surface_get_arrays(s)
					var v_arr: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var i_arr = arr[Mesh.ARRAY_INDEX]
					verts += v_arr.size()
					if i_arr != null and i_arr.size() > 0:
						tris += i_arr.size() / 3
					else:
						tris += v_arr.size() / 3
					var mat: Material = mi.get_active_material(s)
					if mat != null:
						var mid := mat.get_instance_id()
						mat_ids[mid] = true
						if mat is StandardMaterial3D:
							var sm := mat as StandardMaterial3D
							if sm.albedo_texture != null or sm.normal_texture != null or sm.roughness_texture != null:
								textured_mats[mid] = true
		for child in node.get_children():
			stack.append(child)

	return {
		"triangles": tris,
		"vertices": verts,
		"mesh_nodes": mesh_nodes,
		"surfaces": surfaces,
		"unique_materials": mat_ids.size(),
		"textured_materials": textured_mats.size(),
		"aabb": combined_aabb,
		"wheel_pivots": wheel_pivots,
		"interior_nodes": interior_nodes,
		"fl_wheel_pos": fl_pos
	}

func _measure_frames(vp: Viewport, frames: int) -> Dictionary:
	var dt_ms: Array[float] = []
	var cpu_ms: Array[float] = []
	var gpu_ms: Array[float] = []
	var rid := vp.get_viewport_rid()
	var prev := Time.get_ticks_usec()
	for _i in range(frames):
		await process_frame
		var now := Time.get_ticks_usec()
		dt_ms.append(float(now - prev) / 1000.0)
		cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		prev = now
	var sorted: Array[float] = dt_ms.duplicate()
	sorted.sort()
	var n := sorted.size()
	var sum_dt := 0.0
	var sum_cpu := 0.0
	var sum_gpu := 0.0
	for i in range(n):
		sum_dt += dt_ms[i]
		sum_cpu += cpu_ms[i]
		sum_gpu += gpu_ms[i]
	var avg_dt: float = sum_dt / float(n)
	var p99_dt: float = sorted[mini(n - 1, int(ceil(float(n) * 0.99)) - 1)]
	return {
		"avg_fps": snapped(1000.0 / maxf(avg_dt, 0.001), 0.1),
		"low_1pct_fps": snapped(1000.0 / maxf(p99_dt, 0.001), 0.1),
		"avg_ms": snapped(avg_dt, 0.02),
		"p99_ms": snapped(p99_dt, 0.02),
		"avg_cpu_ms": snapped(sum_cpu / float(n), 0.02),
		"avg_gpu_ms": snapped(sum_gpu / float(n), 0.02),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"video_mem_mb": snapped(float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / (1024.0 * 1024.0), 0.01),
		"memory_static_mb": snapped(float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0), 0.01)
	}
