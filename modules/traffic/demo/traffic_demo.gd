extends Node3D
## Standalone Godot 4.7.2 scene: 19-lane road fixture, signal/yield junction, merge,
## and 14 autonomous low-poly cars. No global scene or vehicle plugin required.

const TrafficSimulation = preload("../src/traffic_simulation.gd")
const FIXTURE_PATH := "res://fixtures/intersection_v1.json"
const VEHICLE_COLORS := [Color(0.1, 0.55, 0.75), Color(0.8, 0.23, 0.18), Color(0.85, 0.8, 0.2)]

@export var seed_value := 20261121
@export_range(0, 20, 1) var target_cars := 14

var traffic = TrafficSimulation.new()
var car_nodes: Dictionary = {}
var hud: Label
var paused := false
var camera: Camera3D


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	if not (parsed is Dictionary) or not traffic.load_road_graph(parsed):
		push_error("Traffic fixture failed to load: %s" % str(traffic.graph.errors))
		return
	traffic.configure_junctions([{"id": "center", "incoming_lane_ids": ["eb_in", "wb_in", "sb_in", "nb_in"],
		"mode": "stop", "stop_s": 0.7, "clearance_m": 21.0},
		{"id": "feeder_crossing", "incoming_lane_ids": ["sb_out1", "nb_in_far"],
		"mode": "yield", "clearance_m": 13.0}])
	traffic.reset(seed_value)
	traffic.set_density(target_cars)
	_build_environment()
	_build_roads()
	for _i in range(target_cars):
		traffic.spawn_near(Vector3.ZERO, 80)
	_update_visuals()


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.65, 0.77, 0.81)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.82, 0.84)
	world.environment = env
	add_child(world)
	var ground := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(335, 335)
	ground.mesh = mesh
	ground.material_override = _material(Color(0.27, 0.37, 0.29))
	ground.position = Vector3(0, 0.8, 0)
	add_child(ground)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-60, -30, 0)
	sunlight.light_energy = 1.0
	add_child(sunlight)
	camera = Camera3D.new()
	camera.position = Vector3(0, 170, 125)
	camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	camera.fov = 72.0
	camera.current = true
	add_child(camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(18, 16)
	hud.add_theme_color_override("font_color", Color(1, 1, 1))
	hud.add_theme_font_size_override("font_size", 20)
	layer.add_child(hud)


func _build_roads() -> void:
	var asphalt := _material(Color(0.19, 0.22, 0.24))
	var yellow := _material(Color(0.87, 0.73, 0.30))
	for lid in traffic.graph.lane_order:
		var points: Array = traffic.graph.lanes[lid]["points"]
		for i in range(points.size() - 1):
			var start: Vector3 = points[i]
			var finish: Vector3 = points[i + 1]
			var midpoint := (start + finish) * 0.5
			var delta := finish - start
			var road_mesh := BoxMesh.new()
			road_mesh.size = Vector3(3.5, 0.12, delta.length() + 0.15)
			var road_node := MeshInstance3D.new()
			road_node.mesh = road_mesh
			road_node.material_override = asphalt
			road_node.position = Vector3(midpoint.x, 0.96, midpoint.z)
			road_node.rotation.y = atan2(-delta.x, -delta.z)
			add_child(road_node)
			# Centerline ticks help inspect heading, route transitions and merges.
			if delta.length() > 13.0:
				var stripe := MeshInstance3D.new()
				var strip_mesh := BoxMesh.new()
				strip_mesh.size = Vector3(0.1, 0.015, 2.0)
				stripe.mesh = strip_mesh
				stripe.material_override = yellow
				stripe.position = Vector3(midpoint.x, 1.04, midpoint.z)
				stripe.rotation.y = road_node.rotation.y
				add_child(stripe)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material


func _process(delta: float) -> void:
	if not paused:
		traffic.step(delta, Vector3.ZERO)
	_update_visuals()


func _update_visuals() -> void:
	var present := {}
	for a in traffic.get_states():
		var id: int = a["id"]
		present[id] = true
		if not car_nodes.has(id):
			var node := MeshInstance3D.new()
			var body := BoxMesh.new()
			body.size = Vector3(1.75, 0.85, 3.6)
			node.mesh = body
			node.material_override = _material(VEHICLE_COLORS[a["vehicle_type"]])
			add_child(node)
			car_nodes[id] = node
		var car: MeshInstance3D = car_nodes[id]
		car.position = a["position"] + Vector3(0, 0.57, 0)
		var tangent: Vector3 = a["tangent"]
		car.rotation.y = atan2(-tangent.x, -tangent.z)
	for id in car_nodes.keys():
		if not present.has(id):
			car_nodes[id].queue_free()
			car_nodes.erase(id)
	if hud != null:
		var stats: Dictionary = traffic.get_stats()
		hud.text = "ASTER VALLEY | TRAFFIC DEMO\n%d / %d cars | seed %d | %.1f s\nR reset  |  T toggle density  |  Space pause\nJunction: all-way stop  |  Merge: yield\n%s" % [stats["active"], traffic.density_target, seed_value, stats["seconds"], "PAUSED" if paused else "RUNNING"]


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_R:
		traffic.reset(seed_value)
		for _i in range(target_cars):
			traffic.spawn_near(Vector3.ZERO, 80)
	elif event.keycode == KEY_T:
		target_cars = 6 if target_cars > 6 else 14
		traffic.set_density(target_cars)
	elif event.keycode == KEY_SPACE:
		paused = not paused
