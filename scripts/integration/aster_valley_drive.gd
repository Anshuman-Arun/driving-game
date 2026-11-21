extends Node3D
## Free roam boot using the canonical map and the Core vehicle implementation.

const WorldRuntime = preload("res://modules/world_runtime/src/world_runtime.gd")
const ALDER_START := Vector3(-575.0, 0.0, 545.0)
const JUNCTION_CLEARANCE_M := 26.0
const SPAWN_HEIGHT_M := 0.58
const WHEEL_FOOTPRINT := [
	Vector3(-0.88, 0.0, -1.36), Vector3(0.88, 0.0, -1.36),
	Vector3(-0.88, 0.0, 1.35), Vector3(0.88, 0.0, 1.35),
]
const SURFACE_GROUPS := {"terrain": "Grass", "asphalt": "Road", "gravel": "Dirt"}

@onready var world: WorldRuntime = $WorldRuntime
var vehicle_body: Vehicle
var adapter: VehicleAdapter
var camera: DrivingChaseCamera
var load_ms := 0

var _controls := DriveInput.new()
var _lane_spans: Array[PackedVector3Array] = []
var _bounds: Rect2
var _reset_requested := false
var _camera_requested := false
var _reset_cooldown := 0.0

func _ready() -> void:
	var started := Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	DriveInput.install()
	if not world.build_world():
		push_error("Aster Valley could not load: " + world.error_message)
		get_tree().quit(1)
		return

	for node in world.generated_root.find_children("*", "StaticBody3D", true, false):
		node.add_to_group(SURFACE_GROUPS[node.get_meta("world_surface")])
	var bounds: Dictionary = world.get_world_metadata()["bounds"]
	_bounds = Rect2(bounds["min_x"], bounds["min_z"],
		bounds["max_x"] - bounds["min_x"], bounds["max_z"] - bounds["min_z"])
	_collect_lane_spans(world.get_road_graph()["lanes"])

	# Let the physics server register the generated bodies before querying the road.
	await get_tree().physics_frame
	var start: Variant = find_road_pose(ALDER_START, Vector3.RIGHT)
	if start == null:
		push_error("Aster Valley has no valid road spawn.")
		get_tree().quit(1)
		return
	vehicle_body = PlayerCarFactory.create()
	vehicle_body.process_mode = Node.PROCESS_MODE_PAUSABLE
	vehicle_body.transform = start
	add_child(vehicle_body)
	adapter = VehicleAdapter.new(vehicle_body)
	adapter.reset_to(start)

	camera = DrivingChaseCamera.new()
	camera.name = "ChaseCamera"
	camera.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(camera)
	camera.setup(vehicle_body)
	camera.far = 3000.0
	load_ms = Time.get_ticks_msec() - started
	print("Aster Valley ready in %d ms at %s" % [load_ms, start.origin])

func _process(_delta: float) -> void:
	if adapter == null:
		return
	if Input.is_action_just_pressed("drive_pause"):
		get_tree().paused = not get_tree().paused
	if Input.is_action_just_pressed("drive_reset"):
		_reset_requested = true
	if not get_tree().paused and Input.is_action_just_pressed("drive_camera"):
		_camera_requested = true

func _physics_process(delta: float) -> void:
	if adapter == null:
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
		return
	if _camera_requested:
		_camera_requested = false
		camera.cycle()
	var input := _controls.sample()
	adapter.set_drive_input(input["steer"], input["throttle"], input["brake"], input["handbrake"])

func respawn() -> void:
	var pose: Variant = find_road_pose(vehicle_body.global_position, -vehicle_body.global_basis.z)
	if pose != null:
		adapter.reset_to(pose)
		camera.snap_to_vehicle()

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
	if hit.collider.is_in_group("Road") or hit.collider.is_in_group("Dirt"):
		return hit
	return {}
