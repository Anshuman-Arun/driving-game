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
		status.grass = cover.build(drive.world, _cover_preset(), MASK, {"pilot_bounds": bounds})
		if not status.grass:
			push_warning("Environment pilot grass fallback: " + str(cover.get_stats().get("fallback", "")))
			cover.queue_free()
			cover = null
	if _switch("ASTER_ENV_TERRAIN"):
		terrain = Terrain.new()
		status.terrain = terrain.apply_candidate(drive.world, {"pilot_bounds": bounds, "roadside_bounds": bounds, "mask_dir": MASK})
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
			status.rendering = rendering.apply_candidate(_drive, _preset, {})
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
