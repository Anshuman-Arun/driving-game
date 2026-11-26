extends Node3D
const Fixture := preload("tests/fixture_world.gd")
const Preview := preload("terrain_preview.gd")
var fixture: Node3D
var adapter := Preview.new()
var active := false
var label: Label

func _ready() -> void:
	fixture = Fixture.new()
	add_child(fixture)
	fixture.call("build_fixture")
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.56, 0.70, 0.84)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.82, 0.92)
	env.ambient_light_energy = 0.55
	environment_node.environment = env
	add_child(environment_node)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(-20, 42, 23)
	camera.look_at(Vector3(3, 30, 0))
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	label = Label.new()
	layer.add_child(label)
	label.position = Vector2(16, 16)
	_refresh_label()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		if active:
			adapter.restore()
			active = false
		else:
			active = adapter.apply_candidate(fixture, {"roadside_bounds": Rect2(-48, -48, 96, 96)})
		print("[TerrainPreviewFixture] ", adapter.get_stats())
		_refresh_label()

func _refresh_label() -> void:
	label.text = "T: toggle terrain candidate | " + ("CANDIDATE" if active else "ORIGINAL") + "\nSynthetic fixture, not production visual acceptance"
