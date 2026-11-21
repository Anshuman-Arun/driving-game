extends Node3D
## Open this scene through the standalone modules/racing/project.godot.
## Autonomous local visualization of FOUR cars on schema-v1 course geometry.
const RaceEngine = preload("../race_engine.gd")
const RacerAI = preload("../racer_ai.gd")
const Adapter = preload("../vehicle_command_adapter.gd")
const EventCatalog = preload("../event_catalog.gd")
const KinematicCar = preload("kinematic_car.gd")

var engine = RaceEngine.new()
var catalog = EventCatalog.new()
var graph: Dictionary = {}
var cars: Dictionary = {}
var planners: Dictionary = {}
var labels: Label
var selected_event := "alder_street_circuit"
var max_error_m := 0.0

func _ready() -> void:
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/road_graph_v1.json"))
	if not (loaded is Dictionary):
		push_error("Missing or invalid road graph fixture")
		return
	graph = loaded
	if not catalog.load_file("res://fixtures/events_v1.json"):
		push_error(catalog.last_error)
		return
	if not engine.load_road_graph(graph):
		push_error(engine.last_error)
		return
	for id in ["player", "rival_a", "rival_b", "rival_c"]:
		if not engine.register_racer(id, id == "player"):
			push_error(engine.last_error)
			return
	_build_scene()
	_start(selected_event)

func _build_scene() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60.0, 25.0, 0.0)
	add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 520.0
	camera.position = Vector3(0, 380, 185)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.current = true
	add_child(camera)
	var ui := CanvasLayer.new()
	add_child(ui)
	labels = Label.new()
	labels.position = Vector2(16, 14)
	ui.add_child(labels)

func _build_road() -> void:
	for child in get_children():
		if child.is_in_group("local_test_road"):
			child.queue_free()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in engine.route.segments:
		var a: Vector3 = part["a"]
		var b: Vector3 = part["b"]
		var dir: Vector2 = part["dir"]
		var across := Vector3(-dir.y, 0.0, dir.x) * 4.0
		var lift := Vector3(0.0, 0.04, 0.0)
		var l1 := a - across + lift
		var r1 := a + across + lift
		var l2 := b - across + lift
		var r2 := b + across + lift
		for vertex in [l1, r1, l2, r1, r2, l2]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	var road := MeshInstance3D.new()
	road.mesh = surface.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.19, 0.20, 0.22)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	road.material_override = mat
	road.add_to_group("local_test_road")
	add_child(road)

func _start(id: String) -> void:
	for car in cars.values():
		car.queue_free()
	cars.clear()
	planners.clear()
	if engine.state != RaceEngine.State.IDLE and engine.state != RaceEngine.State.FREE_ROAM:
		engine.quit_event()
		engine.return_to_free_roam()
	if not engine.start_event(catalog.get_event(id)):
		push_error(engine.last_error)
		return
	selected_event = id
	max_error_m = 0.0
	_build_road()
	var colors := [Color(0.8, 0.25, 0.2), Color(0.25, 0.6, 0.95), Color(0.9, 0.8, 0.3), Color(0.4, 0.9, 0.5)]
	var ids := ["player", "rival_a", "rival_b", "rival_c"]
	for i in range(ids.size()):
		var name: String = ids[i]
		var car = KinematicCar.new()
		car.paint = colors[i]
		add_child(car)
		var base: Vector3 = engine.route.sample(0.0)
		var heading: Vector2 = engine.route.tangent(0.0)
		var forward := Vector3(heading.x, 0.0, heading.y)
		var across := Vector3(-heading.y, 0.0, heading.x)
		car.teleport_to(base - forward * (float(i) * 0.5) + across * (float(i) - 1.5) * 0.6, forward)
		cars[name] = car
		var ai = RacerAI.new()
		ai.preferred_speed_mps = 14.5 + float(i) * 1.0
		if not ai.configure(graph, engine.event["lane_route"], engine.event["kind"] == "circuit"):
			push_error(ai.last_error)
		planners[name] = ai

func _physics_process(delta: float) -> void:
	if engine.state == RaceEngine.State.RACING and not engine.paused:
		for id in cars.keys():
			var car: Node3D = cars[id]
			if engine.get_racer(id)["finished"]:
				Adapter.apply(car, {"steer": 0.0, "throttle": 0.0, "brake": 1.0})
				continue
			if engine.needs_reset(id):
				var pose: Dictionary = engine.reset_racer(id)
				car.teleport_to(pose["position"], pose["forward"])
				planners[id].reset_tracking()
			var state: Dictionary = Adapter.read_state(car)
			var control: Dictionary = planners[id].compute_controls(state["position"], state["forward"], state["speed_mps"], delta)
			if control["needs_reset"]:
				var pose: Dictionary = engine.reset_racer(id)
				car.teleport_to(pose["position"], pose["forward"])
				planners[id].reset_tracking()
				control = {"steer": 0.0, "throttle": 0.0, "brake": 1.0}
			Adapter.apply(car, control)
			car.advance(delta)
			var projected: Dictionary = engine.route.project(car.global_position)
			max_error_m = maxf(max_error_m, float(projected["distance_m"]))
			var nearest: Vector3 = projected["point"]
			car.global_position.y = nearest.y + 0.15
			engine.update_racer_state(id, car.global_position, car.get_drive_velocity())
	engine.tick(delta)
	if engine.state == RaceEngine.State.FINISHED:
		engine.show_results()
	if labels != null:
		var ranking := engine.standings()
		var lines := []
		for entry in ranking:
			lines.append("%s: lap %d, gate %d, %s" % [entry["id"], entry["lap"], entry["checkpoint_index"], "FIN" if entry["finished"] else "RUN"])
		labels.text = "%s | state %s | time %.1fs | max cross-track %.1fm\nSPACE pause  R restart  TAB swap course  Q free roam\n%s" % [selected_event, str(engine.state), engine.elapsed_seconds, max_error_m, "\n".join(lines)]

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			if engine.paused:
				engine.resume()
			else:
				engine.pause()
		KEY_R:
			_start(selected_event)
		KEY_TAB:
			_start("north_ridge_climb" if selected_event == "alder_street_circuit" else "alder_street_circuit")
		KEY_Q:
			if engine.quit_event():
				engine.return_to_free_roam()
			elif engine.state == RaceEngine.State.RESULTS:
				engine.return_to_free_roam()
