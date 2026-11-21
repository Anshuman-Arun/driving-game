extends Node3D
## Inspection-only fly camera. No vehicle, racing or traffic dependencies.
const WorldRuntime = preload("res://src/world_runtime.gd")

var runtime
var camera: Camera3D
var info: Label
var fly_speed := 75.0
var mouse_captured := false

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.61, 0.75, 0.87)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.82, 0.87)
	environment.ambient_light_energy = 0.6
	world_environment.environment = environment
	add_child(world_environment)
	camera = Camera3D.new()
	camera.name = "FlyCamera"
	camera.far = 3500.0
	camera.current = true
	add_child(camera)
	var hud := CanvasLayer.new()
	add_child(hud)
	info = Label.new()
	info.position = Vector2(18.0, 18.0)
	info.add_theme_color_override("font_color", Color.WHITE)
	info.add_theme_color_override("font_shadow_color", Color.BLACK)
	info.add_theme_constant_override("shadow_offset_x", 1)
	info.add_theme_constant_override("shadow_offset_y", 1)
	hud.add_child(info)
	runtime = WorldRuntime.new()
	runtime.name = "AsterValleyWorld"
	runtime.build_on_ready = false
	add_child(runtime)
	var ok: bool = runtime.build_world()
	var anchor := Vector2(-620.0, 560.0)
	var y: float = runtime.get_height_at(anchor.x, anchor.y) if ok else 40.0
	camera.position = Vector3(anchor.x + 160.0, y + 170.0, anchor.y + 220.0)
	camera.look_at(Vector3(anchor.x, y, anchor.y), Vector3.UP)
	if ok:
		var r: Dictionary = runtime.report
		info.text = "ASTER VALLEY - WORLD RUNTIME\nTerrain chunks: %s | Road corridors: %s | Junction pads: %s\nTriangles T/R/J: %s / %s / %s | Generation: %s ms\nWASD move, Q/E descend/ascend, Shift boost, mouse look (click), Esc release\nData: %s" % [
			r["terrain_chunks"], r["physical_corridors"], r["junction_pads"],
			r["terrain_triangles"], r["road_triangles"], r["junction_triangles"],
			r["generation_ms"], r["source_directory"]]
	else:
		info.text = "WORLD DATA NOT FOUND OR INVALID\n" + runtime.error_message + "\n\nStage World PR #3 data from feat/worldgen\nor run with -- --world-data-dir=/absolute/path/to/data/world"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_captured = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		mouse_captured = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseMotion and mouse_captured:
		camera.rotation.y -= event.relative.x * 0.0023
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * 0.0023, -1.45, 1.45)

func _process(delta: float) -> void:
	var input_x := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	var input_z := float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	var input_y := float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q))
	var horizontal_forward := -camera.global_basis.z
	horizontal_forward.y = 0.0
	horizontal_forward = horizontal_forward.normalized()
	var horizontal_right := camera.global_basis.x
	horizontal_right.y = 0.0
	horizontal_right = horizontal_right.normalized()
	var motion := horizontal_right * input_x + horizontal_forward * (-input_z) + Vector3.UP * input_y
	var speed := fly_speed * (4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	if motion.length_squared() > 0.0:
		camera.global_position += motion.normalized() * speed * delta
