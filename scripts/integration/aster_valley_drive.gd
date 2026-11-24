extends Node3D
## Free roam boot using the canonical map and the Core vehicle implementation.
## Optional presentation adapters may mount to the new chassis before camera rebinding.
signal vehicle_spawned(body: Vehicle, car_id: String)

const WorldRuntime = preload("res://modules/world_runtime/src/world_runtime.gd")
const Buildings = preload("valley_buildings.gd")
const Vegetation = preload("valley_vegetation.gd")
const SceneryRuntime = preload("res://modules/scenery/src/scenery_runtime.gd")
const CuratedCar = preload("curated_car_visual.gd")
const ValleyEnvironment = preload("aster_valley_environment.gd")
const ALDER_START := Vector3(-575.0, 0.0, 545.0)
const JUNCTION_CLEARANCE_M := 26.0
const SPAWN_HEIGHT_M := 0.58
const WHEEL_FOOTPRINT := [
	Vector3(-0.88, 0.0, -1.36), Vector3(0.88, 0.0, -1.36),
	Vector3(-0.88, 0.0, 1.35), Vector3(0.88, 0.0, 1.35),
]
const PARKED_LIMIT_MPS := 4.0 / 3.6

@onready var world: WorldRuntime = $WorldRuntime
var vehicle_body: Vehicle
var adapter: VehicleAdapter
var camera: Camera3D
var load_ms := 0
var active_vehicle_id := PlayerCarFactory.DEFAULT_CAR
var shell_managed := false
@export var scenery_enabled := true
var scenery: SceneryRuntime
var vegetation: Vegetation
var graphics_preset := "medium":
	set(value):
		graphics_preset = value
		if is_instance_valid(vegetation):
			vegetation.set_graphics(value)
var _pending_vehicle_id := ""

var _controls := DriveInput.new()
var steering_sensitivity: float:
	set(value):
		_controls.steering_sensitivity = clampf(value, 0.0, 1.0)
	get:
		return _controls.steering_sensitivity
var _lane_spans: Array[PackedVector3Array] = []
var _bounds: Rect2
var _reset_requested := false
var _camera_requested := false
var _reset_cooldown := 0.0

func _ready() -> void:
	var started := Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	DriveInput.install()
	ValleyEnvironment.apply_environment(self)
	ValleyEnvironment.apply_world_materials(world)
	var works := FileAccess.get_file_as_string("res://data/world/roadworks.json")
	var design: Variant = JSON.parse_string(works) if not works.is_empty() else null
	if design is Dictionary:
		world.roadworks = design
		if ResourceLoader.exists("res://assets/forza_env/materials/lake_water_forza.tres"):
			var water_mat = load("res://assets/forza_env/materials/lake_water_forza.tres")
			if water_mat != null:
				world.crossing_water_material = water_mat
	if not world.build_world():
		push_error("Aster Valley could not load: " + world.error_message)
		get_tree().quit(1)
		return

	if ResourceLoader.exists("res://modules/world_runtime/src/guardrail_spline_generator.gd"):
		var guardrail_gen = load("res://modules/world_runtime/src/guardrail_spline_generator.gd")
		if guardrail_gen != null and guardrail_gen.has_method("generate_all_corridors"):
			guardrail_gen.generate_all_corridors(world, self)

	var bounds: Dictionary = world.get_world_metadata()["bounds"]
	_bounds = Rect2(bounds["min_x"], bounds["min_z"],
		bounds["max_x"] - bounds["min_x"], bounds["max_z"] - bounds["min_z"])
	_collect_lane_spans(world.get_road_graph()["lanes"])
	if scenery_enabled:
		set_scenery_enabled(true)

	# Let the physics server register the generated bodies before querying the road.
	await get_tree().physics_frame
	var start: Variant = find_road_pose(ALDER_START, Vector3.RIGHT)
	if start == null:
		push_error("Aster Valley has no valid road spawn.")
		get_tree().quit(1)
		return
	if ResourceLoader.exists("res://scripts/vehicle/forza_chase_camera.gd"):
		var CamClass = load("res://scripts/vehicle/forza_chase_camera.gd")
		camera = CamClass.new()
	else:
		camera = DrivingChaseCamera.new()
	camera.name = "ChaseCamera"
	camera.process_mode = Node.PROCESS_MODE_PAUSABLE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var listener := AudioListener3D.new()
	listener.name = "AudioListener3D"
	camera.add_child(listener)
	listener.make_current()
	add_child(camera)
	_spawn_vehicle(active_vehicle_id, start)
	load_ms = Time.get_ticks_msec() - started
	print("Aster Valley ready in %d ms at %s" % [load_ms, start.origin])

func set_scenery_enabled(enabled: bool) -> bool:
	scenery_enabled = enabled
	if not enabled:
		if vegetation != null:
			remove_child(vegetation)
			vegetation.queue_free()
			vegetation = null
		if scenery != null:
			remove_child(scenery)
			scenery.queue_free()
			scenery = null
		var prem := get_node_or_null("PremiumFoliageRuntime")
		if prem != null:
			remove_child(prem)
			prem.queue_free()
		return true
	if scenery != null:
		return true
	if not is_inside_tree() or world == null:
		return true
	var layer := SceneryRuntime.new()
	layer.name = "Scenery"
	layer.generate_selective_colliders = true
	vegetation = Vegetation.new()
	vegetation.name = "ValleyVegetation"
	add_child(vegetation)
	vegetation.build(world, graphics_preset)
	layer.mesh_overrides = Buildings.new().assets()
	var oak_mesh := vegetation.broadleaf_mesh()
	if oak_mesh != null:
		layer.mesh_overrides["assets/curated/models/environment/broadleaf_tree.glb"] = oak_mesh
	var pine_mesh := vegetation.conifer_mesh()
	if pine_mesh != null:
		layer.mesh_overrides["assets/curated/models/environment/pine_tree_lod0.glb"] = pine_mesh
		layer.mesh_overrides["assets/curated/models/environment/pine_tree_lod1.glb"] = vegetation.conifer_mesh(true)
	add_child(layer)
	if ResourceLoader.exists("res://scripts/integration/premium_foliage_runtime.gd"):
		var FoliageClass = load("res://scripts/integration/premium_foliage_runtime.gd")
		if FoliageClass != null:
			var prem_foliage = FoliageClass.new()
			prem_foliage.name = "PremiumFoliageRuntime"
			add_child(prem_foliage)
			prem_foliage.build(world, graphics_preset)
	if not layer.build_scenery(world):
		scenery_enabled = false
		remove_child(layer)
		layer.queue_free()
		remove_child(vegetation)
		vegetation.queue_free()
		vegetation = null
		return false
	scenery = layer
	return true

func _process(_delta: float) -> void:
	if adapter == null:
		return
	if not shell_managed and Input.is_action_just_pressed("drive_pause"):
		get_tree().paused = not get_tree().paused
	if shell_managed and get_tree().paused:
		return
	if Input.is_action_just_pressed("drive_reset"):
		_reset_requested = true
	if not get_tree().paused and Input.is_action_just_pressed("drive_camera"):
		_camera_requested = true

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11:
		var window := get_window()
		window.mode = Window.MODE_WINDOWED if window.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		window.set_input_as_handled()

func _physics_process(delta: float) -> void:
	if adapter == null:
		return
	if not _pending_vehicle_id.is_empty():
		var next_id := _pending_vehicle_id
		_pending_vehicle_id = ""
		if next_id != active_vehicle_id and adapter.get_speed_mps() <= PARKED_LIMIT_MPS:
			_spawn_vehicle(next_id, vehicle_body.transform)
	if shell_managed and get_tree().paused:
		_stop_haptics()
		return
	_reset_cooldown = maxf(0.0, _reset_cooldown - delta)
	var p := vehicle_body.global_position
	if _reset_cooldown == 0.0 and (
		_reset_requested or not _bounds.has_point(Vector2(p.x, p.z)) or p.y < 0.0
	):
		respawn()
		_reset_cooldown = 0.5
	_reset_requested = false
	if get_tree().paused:
		_stop_haptics()
		return
	if _camera_requested:
		_camera_requested = false
		camera.cycle()
	var input := _controls.sample()
	adapter.set_drive_input(input["steer"], input["throttle"], input["brake"], input["handbrake"])
	if vehicle_body != null and not vehicle_body.freeze:
		camera.set_look_input(_controls.sample_look())
	else:
		camera.set_look_input(Vector2.ZERO)
	_update_haptics()

func _exit_tree() -> void:
	_stop_haptics()

func _update_haptics() -> void:
	var pads := _controls.connected_joypads
	if pads.is_empty() or vehicle_body == null:
		return
	var device := pads[0]
	var weak := 0.0
	var strong := 0.0
	var drift := adapter.drift_controller if adapter != null else null
	if drift != null and drift.is_drifting:
		var intensity := drift.drift_intensity
		weak = clampf(0.22 + intensity * 0.48, 0.0, 0.72)
		strong = clampf(intensity * 0.35, 0.0, 0.40)
	var speed := adapter.get_speed_mps()
	if speed > 4.0:
		var offroad := false
		for w in vehicle_body.wheel_array:
			if w.is_colliding() and (w.surface_type == "Dirt" or w.surface_type == "Grass"):
				offroad = true
				break
		if offroad:
			var speed_w := clampf(speed / 28.0, 0.15, 0.55)
			weak = maxf(weak, speed_w * 0.55)
			strong = maxf(strong, speed_w * 0.32)
	if weak > 0.02 or strong > 0.02:
		Input.start_joy_vibration(device, weak, strong, 0.12)
	else:
		Input.stop_joy_vibration(device)

func _stop_haptics() -> void:
	for device in Input.get_connected_joypads():
		Input.stop_joy_vibration(device)

func queue_vehicle_selection(car_id: String) -> void:
	if not PlayerCarFactory.PRESETS.has(car_id):
		return
	if adapter == null:
		active_vehicle_id = car_id
	else:
		_pending_vehicle_id = car_id

func _spawn_vehicle(car_id: String, pose: Transform3D) -> void:
	if vehicle_body != null:
		remove_child(vehicle_body)
		vehicle_body.queue_free()
	vehicle_body = PlayerCarFactory.create(car_id)
	active_vehicle_id = str(vehicle_body.get_meta("vehicle_id"))
	vehicle_body.process_mode = Node.PROCESS_MODE_PAUSABLE
	vehicle_body.transform = pose
	add_child(vehicle_body)
	adapter = VehicleAdapter.new(vehicle_body)
	adapter.reset_to(pose)
	CuratedCar.mount(vehicle_body, active_vehicle_id)
	vehicle_spawned.emit(vehicle_body, active_vehicle_id)
	camera.setup(vehicle_body)
	camera.far = 1800.0
	var audio := vehicle_body.get_node_or_null("VehicleAudio")
	if audio != null and audio.has_method("bind_camera"):
		audio.call("bind_camera", camera)

func respawn() -> void:
	var pose: Variant = find_road_pose(vehicle_body.global_position, -vehicle_body.global_basis.z)
	if pose != null:
		adapter.reset_to(pose)
		camera.snap_to_vehicle()
		var audio := vehicle_body.get_node_or_null("VehicleAudio")
		if audio != null and audio.has_method("snap_to_idle"):
			audio.call("snap_to_idle")

func _collect_lane_spans(lanes: Array) -> void:
	for lane: Dictionary in lanes:
		if not String(lane["id"]).begins_with("lane_"):
			continue
		var points := PackedVector3Array()
		var offsets := PackedFloat32Array()
		var length := 0.0
		for xyz: Array in lane["points"]:
			var point := Vector3(xyz[0], xyz[1], xyz[2])
			if not points.is_empty():
				length += points[-1].distance_to(point)
			points.append(point)
			offsets.append(length)
		for i in range(points.size() - 1):
			var begin := maxf(offsets[i], JUNCTION_CLEARANCE_M)
			var end := minf(offsets[i + 1], length - JUNCTION_CLEARANCE_M)
			if begin >= end:
				continue
			var span := offsets[i + 1] - offsets[i]
			_lane_spans.append(PackedVector3Array([
				points[i].lerp(points[i + 1], (begin - offsets[i]) / span),
				points[i].lerp(points[i + 1], (end - offsets[i]) / span),
			]))

func find_road_pose(near: Vector3, preferred_heading: Vector3) -> Variant:
	var heading_xz := Vector3(preferred_heading.x, 0.0, preferred_heading.z).normalized()
	var best_score := INF
	var best_pose: Variant = null
	for span in _lane_spans:
		var delta := span[1] - span[0]
		var flat := Vector3(delta.x, 0.0, delta.z)
		var offset := Vector3(near.x - span[0].x, 0.0, near.z - span[0].z)
		var t := clampf(offset.dot(flat) / flat.length_squared(), 0.0, 1.0)
		var heading := flat.normalized()
		# Nearby same-direction lanes win when the candidates are otherwise close.
		var score := (offset - flat * t).length_squared() + 9.0 * (1.0 - heading.dot(heading_xz))
		if score >= best_score:
			continue
		var pose: Variant = _road_pose(span[0].lerp(span[1], t), heading)
		if pose != null:
			best_pose = pose
			best_score = score
	return best_pose

func _road_pose(point: Vector3, heading: Vector3) -> Variant:
	var hit := _cast_road(point)
	if hit.is_empty():
		return null
	var normal: Vector3 = hit.normal
	var origin: Vector3 = hit.position
	var basis := Basis.looking_at(heading.slide(normal), normal)
	for wheel_offset: Vector3 in WHEEL_FOOTPRINT:
		var wheel_point := origin + basis * wheel_offset
		var wheel_hit := _cast_road(wheel_point)
		if wheel_hit.is_empty() or absf(wheel_hit.position.y - wheel_point.y) > 0.18:
			return null
	return Transform3D(basis, origin + normal * SPAWN_HEIGHT_M)

func _cast_road(point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3.0,
		point + Vector3.DOWN * 3.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < 0.94:
		return {}
	if hit.collider.get_meta("world_surface", "") in ["asphalt", "gravel"]:
		return hit
	return {}
