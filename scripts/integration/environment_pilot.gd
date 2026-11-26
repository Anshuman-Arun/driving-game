extends Node3D
## Reversible opt-in coordinator. No save/settings mutation or gameplay edits.
const Cover := preload("res://modules/ground_cover/ground_cover.gd")
const Terrain := preload("res://modules/environment_terrain/terrain_preview.gd")
const Render := preload("res://modules/environment_rendering/render_profile.gd")
const Understory := preload("environment_understory.gd")
const MASK := "res://content/scenery/environment_overhaul/masks"
# Anchored to the QA's actual centered Cedar and Valley route starts.
const REGIONS := {"cedar": Rect2(-990, -274, 240, 240), "valley": Rect2(-48, 50, 240, 240)}
var bounds := Rect2()
var cover: Cover
var terrain: Terrain
var rendering: Render
var understory: Understory
var _drive: Node
var _preset := "medium"
var _render_enabled := false
var _render_attempted := false
var _interaction := false
var _running := false
var status: Dictionary = {}

func _switch(name: String, default_on: bool = true) -> bool:
	var value := OS.get_environment(name).strip_edges().to_lower()
	return default_on if value.is_empty() else value in ["1", "true", "on"]

func start(drive: Node, region: String) -> bool:
	region = region.strip_edges().to_lower()
	if not REGIONS.has(region):
		push_warning("Environment pilot: unknown region " + region)
		return false
	_drive = drive
	bounds = REGIONS[region]
	_preset = str(drive.graphics_preset)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# Run after cover's default-priority publish/evict for same-frame legacy handoff.
	process_priority = 10
	status = {"region": region, "grass": false, "terrain": false, "rendering": false}
	_interaction = _switch("ASTER_ENV_BEND", false)
	if _switch("ASTER_ENV_GRASS"):
		cover = Cover.new()
		cover.name = "PilotGroundCover"
		add_child(cover)
		status.grass = cover.build(drive.world, _cover_preset(), MASK, {"pilot_bounds": bounds, "tuning": _grass_tuning(_cover_preset())})
		if not status.grass:
			push_warning("Environment pilot grass fallback: " + str(cover.get_stats().get("fallback", "")))
			cover.queue_free()
			cover = null
	if _switch("ASTER_ENV_TERRAIN"):
		terrain = Terrain.new()
		status.terrain = terrain.apply_candidate(drive.world, {"pilot_bounds": bounds, "roadside_bounds": bounds, "mask_dir": MASK, "tuning": _terrain_tuning()})
		if not status.terrain:
			push_warning("Environment pilot terrain fallback: " + str(terrain.get_stats()))
	status.understory = false
	if _switch("ASTER_ENV_UNDERSTORY"):
		understory = Understory.new()
		understory.name = "PilotUnderstory"
		add_child(understory)
		status.understory = understory.build(drive, bounds, MASK)
		if not status.understory:
			push_warning("Environment pilot understory skipped: " + str(understory.report))
			understory.queue_free()
			understory = null
	_render_enabled = _switch("ASTER_ENV_RENDERING")
	_running = true
	set_process(true)
	print("Environment pilot: ", status)
	return true

func _cover_preset() -> String:
	return _preset if _preset in ["low", "medium", "high"] else "high"

func _grass_tuning(preset: String) -> Dictionary:
	if preset == "low":
		return {"radii": [22.0, 50.0, 90.0], "density": [0.55, 0.22, 0.06], "cap": 30000, "checks": 1800, "uploads": 3, "upload_instances": 2400, "wind_strength": 0.10}
	if preset == "high":
		return {"radii": [38.0, 88.0, 154.0], "density": [1.0, 0.58, 0.22], "cap": 90000, "checks": 3600, "uploads": 4, "upload_instances": 4200, "work_usec": 3000, "wind_strength": 0.11}
	return {"radii": [34.0, 82.0, 148.0], "density": [0.95, 0.52, 0.18], "cap": 80000, "checks": 3400, "uploads": 4, "upload_instances": 3800, "work_usec": 2600, "wind_strength": 0.11}

func _terrain_tuning() -> Dictionary:
	return {
		"biome_strength": 0.85,
		"meadow_micro_strength": 0.18,
		"moss_strength": 0.32,
		"roadside_strength": 0.28,
		"pilot_normal_multiplier": 1.28,
		"meadow_tint_multiplier": Vector3(0.84, 0.96, 0.78),
		"woodland_tint_multiplier": Vector3(0.76, 0.88, 0.72),
	}

func _render_options() -> Dictionary:
	var opts: Dictionary = {
		"sun_energy": 2.05,
		"sun_color": Color(1.0, 0.95, 0.85),
		"ambient_energy": 0.58,
		"ambient_color": Color(0.62, 0.76, 0.95),
		"exposure": 1.02,
		"contrast": 1.08,
		"saturation": 1.12,
		"shadow_distance": 150.0 if _preset == "low" else (250.0 if _preset == "medium" else 310.0),
		"split_1": 0.07,
		"split_2": 0.22,
		"split_3": 0.52,
		"shadow_bias": 0.034,
		"shadow_normal_bias": 0.76,
		"shadow_blur": 1.15,
		"ssao": _preset == "high",
		"ao_radius": 1.05,
		"ao_intensity": 0.78,
		"paint_metallic": 0.48,
		"paint_roughness": 0.20,
		"paint_clearcoat": 0.92,
		"paint_clearcoat_roughness": 0.09,
	}
	if is_instance_valid(_drive) and is_instance_valid(_drive.vehicle_body) and str(_drive.get("active_vehicle_id")) == "mclaren_senna":
		var paint: Array[Dictionary] = []
		for node in _drive.vehicle_body.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh == null or mesh.mesh == null or mesh.material_override != null:
				continue
			for surface in range(mesh.mesh.get_surface_count()):
				var material := mesh.get_active_material(surface) as ShaderMaterial
				if material != null and material.shader != null and material.shader.resource_path == Render.PAINT_SHADER:
					paint.append({"mesh": mesh, "surface": surface})
		if not paint.is_empty():
			opts["paint_surfaces"] = paint
	return opts

func before_quality_change() -> void:
	if rendering != null:
		rendering.restore()
		rendering = null
	status.rendering = false
	_render_attempted = false

func set_graphics(preset: String) -> void:
	_preset = preset
	if is_instance_valid(cover):
		cover.set_graphics(_cover_preset())
		if is_instance_valid(_drive) and is_instance_valid(_drive.vegetation):
			_drive.vegetation.set_pilot_coverage(bounds, cover.get_coverage_chunks())

func _process(_delta: float) -> void:
	if not _running or not is_instance_valid(_drive):
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var body: RigidBody3D = _drive.vehicle_body
	if cam == null or not is_instance_valid(body):
		return
	if is_instance_valid(cover):
		if cover.get_stats().state == "ready":
			cover.update_focus(cam.global_position, body.linear_velocity)
			cover.set_vehicle_interaction(body.global_position, body.linear_velocity, _interaction)
			if is_instance_valid(_drive.vegetation):
				_drive.vegetation.set_pilot_coverage(bounds, cover.get_coverage_chunks())
		else:
			status.grass = false
			if is_instance_valid(_drive.vegetation):
				_drive.vegetation.set_pilot_coverage(Rect2(), {})
			push_warning("Environment pilot restored legacy grass: " + str(cover.get_stats().fallback))
			cover.queue_free()
			cover = null
	var inside := bounds.has_point(Vector2(body.global_position.x, body.global_position.z))
	if _render_enabled and inside and not _render_attempted:
		_render_attempted = true
		if _preset in ["low", "medium", "high"]:
			rendering = Render.new()
			status.rendering = rendering.apply_candidate(_drive, _preset, _render_options())
			if not status.rendering:
				push_warning("Environment pilot rendering fallback: " + str(rendering.get_status()))
	elif not inside and _render_attempted:
		before_quality_change()

func stop() -> void:
	_running = false
	set_process(false)
	before_quality_change()
	if is_instance_valid(_drive) and is_instance_valid(_drive.vegetation):
		_drive.vegetation.set_pilot_coverage(Rect2(), {})
	if is_instance_valid(cover):
		cover.shutdown()
		cover.queue_free()
		cover = null
	if is_instance_valid(understory):
		understory.hide()
		understory.queue_free()
		understory = null
	if terrain != null:
		terrain.restore()
		terrain = null
	_drive = null

func _exit_tree() -> void:
	stop()
