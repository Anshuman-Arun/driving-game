extends Node3D
## Full 2x2 km context mesh, stylized lighting and fly-around inspection.
## All data and art come from gitignored read-only branch staging.
var camera: Camera3D
var pitch: float = -0.34
var yaw: float = 0.0
var speed_mps: float = 90.0
var scenery: Node3D
var terrain = null

func _ready() -> void:
	var staged: String = ProjectSettings.globalize_path("res://.world_source")
	terrain = load("res://src/scenery_terrain.gd").new()
	if not terrain.load_directory(staged):
		push_error("Stage PR #3 first: node modules/scenery/tools/stage_dependencies.mjs")
		return
	_setup_light()
	_build_terrain_preview()
	_build_road_preview(staged)
	camera = Camera3D.new()
	camera.name = "FlyCamera"
	camera.current = true
	camera.far = 2500.0
	camera.fov = 73.0
	camera.position = Vector3(-620.0, 245.0, 865.0)
	add_child(camera)
	camera.look_at(Vector3(-620.0, 45.0, 575.0))
	scenery = load("res://src/scenery_runtime.gd").new()
	scenery.name = "RuntimeScenery"
	scenery.build_on_ready = false
	scenery.quality = 2
	add_child(scenery)
	var content: String = ProjectSettings.globalize_path("res://").path_join("../../content/scenery").simplify_path()
	if not scenery.build_scenery(null, content, staged):
		push_error(scenery.error_message)
	else:
		print("[SceneryInspector] Move WASD, Q/E down/up, Shift sprint, drag right mouse to look. ", JSON.stringify(scenery.report))
	_setup_overlay()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _setup_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_energy = 1.9
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.62, 0.73, 0.79)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.70, 0.77, 0.76)
	environment.ambient_light_energy = 0.7
	env.environment = environment
	add_child(env)

func _build_terrain_preview() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pieces: int = 188
	var step_m: float = 2000.0 / float(pieces)
	for ix in range(pieces):
		for iz in range(pieces):
			var x: float = -1000.0 + float(ix) * step_m
			var z: float = -1000.0 + float(iz) * step_m
			var a := Vector3(x, terrain.sample_surface_height(x, z), z)
			var b := Vector3(x + step_m, terrain.sample_surface_height(x + step_m, z), z)
			var c := Vector3(x, terrain.sample_surface_height(x, z + step_m), z + step_m)
			var d := Vector3(x + step_m, terrain.sample_surface_height(x + step_m, z + step_m), z + step_m)
			for v in [a, c, b, b, c, d]:
				var grad_x: float = terrain.sample_surface_height(v.x - 4.0, v.z) - terrain.sample_surface_height(v.x + 4.0, v.z)
				var grad_z: float = terrain.sample_surface_height(v.x, v.z - 4.0) - terrain.sample_surface_height(v.x, v.z + 4.0)
				tool.set_normal(Vector3(grad_x, 8.0, grad_z).normalized())
				var t: float = clampf((v.y - 5.0) / 230.0, 0.0, 1.0)
				tool.set_color(Color(0.36 + t * 0.19, 0.48 - t * 0.1, 0.31 + t * 0.12))
				tool.add_vertex(v)
	var mesh: ArrayMesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	var ground := MeshInstance3D.new()
	ground.name = "RealHeightfieldInspectionMesh"
	ground.mesh = mesh
	ground.material_override = material
	add_child(ground)

## Read-only preview of every real AB/BA physical corridor as an inspection ribbon.
## The authoritative collidable road mesh still belongs solely to World Runtime.
func _build_road_preview(staged: String) -> void:
	var file: FileAccess = FileAccess.open(staged.path_join("road_graph_v1.json"), FileAccess.READ)
	if file == null:
		push_error("[SceneryInspector] Cannot inspect authoritative road graph")
		return
	var raw: Variant = JSON.parse_string(file.get_as_text())
	if not (raw is Dictionary):
		push_error("[SceneryInspector] Malformed staged road graph")
		return
	var graph: Dictionary = raw
	var lookup: Dictionary = {}
	for entry in graph.get("lanes", []):
		if entry is Dictionary:
			lookup[str(entry.get("id", ""))] = entry
	var built: int = 0
	for raw_road in graph.get("roads", []):
		if not (raw_road is Dictionary):
			continue
		var road: Dictionary = raw_road
		var id: String = str(road.get("id", ""))
		var forward_id: String = "lane_%s_ab" % id
		var reverse_id: String = "lane_%s_ba" % id
		if not lookup.has(forward_id) or not lookup.has(reverse_id):
			continue
		var forward: Dictionary = lookup[forward_id]
		var reverse: Dictionary = lookup[reverse_id]
		var ab: Array = forward.get("points", [])
		var ba: Array = reverse.get("points", [])
		if ab.size() < 2 or ab.size() != ba.size():
			push_error("[SceneryInspector] Unpaired physical corridor: " + id)
			return
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(1, ab.size()):
			var a0: Array = ab[i - 1]
			var a1: Array = ab[i]
			var b0: Array = ba[ba.size() - i]
			var b1: Array = ba[ba.size() - 1 - i]
			var p := Vector3((float(a0[0]) + float(b0[0])) * 0.5, 0.0, (float(a0[2]) + float(b0[2])) * 0.5)
			var q := Vector3((float(a1[0]) + float(b1[0])) * 0.5, 0.0, (float(a1[2]) + float(b1[2])) * 0.5)
			var heading: Vector2 = Vector2(q.x - p.x, q.z - p.z).normalized()
			if heading.length_squared() < 0.001:
				continue
			var right := Vector2(heading.y, -heading.x) * 3.4
			var left0 := Vector3(p.x - right.x, 0.0, p.z - right.y)
			var right0 := Vector3(p.x + right.x, 0.0, p.z + right.y)
			var left1 := Vector3(q.x - right.x, 0.0, q.z - right.y)
			var right1 := Vector3(q.x + right.x, 0.0, q.z + right.y)
			for corner in [left0, left1, right0, right0, left1, right1]:
				var position: Vector3 = corner
				position.y = terrain.sample_surface_height(position.x, position.z) + 0.2
				tool.set_normal(Vector3.UP)
				tool.set_uv(Vector2(position.x / 8.0, position.z / 8.0))
				tool.add_vertex(position)
		var mesh: ArrayMesh = tool.commit()
		if mesh == null:
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.27, 0.27, 0.26) if str(forward.get("surface", "asphalt")) == "asphalt" else Color(0.41, 0.34, 0.24)
		mat.roughness = 0.98
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var node := MeshInstance3D.new()
		node.name = "RoadPreview_" + id
		node.mesh = mesh
		node.material_override = mat
		add_child(node)
		built += 1
	print("[SceneryInspector] Read-only physical road ribbons built: ", built, " / 16")

func _setup_overlay() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var info := Label.new()
	info.text = "Aster Valley | 5 regions / 6 landmarks / staged PR #3 + #7\nWASD fly | Q/E vertical | Shift fast | Right mouse drag look"
	info.position = Vector2(20.0, 18.0)
	info.add_theme_color_override("font_color", Color.WHITE)
	canvas.add_child(info)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.003
		pitch = clampf(pitch - event.relative.y * 0.003, -1.45, 1.45)
		camera.rotation = Vector3(pitch, yaw, 0.0)

func _process(delta: float) -> void:
	if camera == null:
		return
	var motion := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		motion.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		motion.z += 1.0
	if Input.is_key_pressed(KEY_A):
		motion.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		motion.x += 1.0
	if Input.is_key_pressed(KEY_E):
		motion.y += 1.0
	if Input.is_key_pressed(KEY_Q):
		motion.y -= 1.0
	var speed: float = speed_mps * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	camera.global_position += (camera.global_transform.basis * motion.normalized()) * speed * delta
