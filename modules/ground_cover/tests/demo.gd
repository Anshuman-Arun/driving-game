extends Node3D
const Cover = preload("../ground_cover.gd")
const Fixture = preload("fixture_world.gd")
var cover: Node3D
var camera: Camera3D
var quality := 1
var vehicle_bend := false

func _ready() -> void:
	var world := Fixture.new()
	add_child(world)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(120,120)
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("53613a")
	floor_node.material_override = mat
	add_child(floor_node)
	for rect in [Rect2(-5,-60,10,120),Rect2(-60,-3,120,6)]:
		var road := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = rect.size
		road.mesh = plane
		road.position = Vector3(rect.get_center().x,0.06,rect.get_center().y)
		var asphalt := StandardMaterial3D.new()
		asphalt.albedo_color = Color("383b3c")
		road.material_override = asphalt
		add_child(road)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-47,-35,0)
	sun.light_energy = 1.3
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("91a9bf")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d2dbe7")
	env.environment.ambient_light_energy = 0.65
	add_child(env)
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(8,2.4,10)
	camera.rotation_degrees = Vector3(-12,0,0)
	camera.current = true
	cover = Cover.new()
	add_child(cover)
	var mask_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mask="):
			mask_path = arg.trim_prefix("--mask=")
	var options := {"pilot_bounds":Rect2(-60,-60,120,120)}
	if mask_path.is_empty():
		options["test_fixture"]=true
		options["fixture_sampler"]=Callable(world,"sample_mask")
	if not cover.build(world,"medium",mask_path,options):
		push_error(str(cover.get_stats()))

func _process(delta: float) -> void:
	var direction := Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),0,float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	var velocity := direction.normalized() * (45.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 8.0)
	camera.position += velocity*delta
	camera.position.x=clampf(camera.position.x,-55,55)
	camera.position.z=clampf(camera.position.z,-55,55)
	cover.update_focus(camera.global_position,velocity)
	cover.set_vehicle_interaction(camera.position-Vector3(0,2,0),velocity,vehicle_bend)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			quality=(quality+1)%3
			cover.set_graphics(["low","medium","high"][quality])
		elif event.keycode == KEY_V:
			vehicle_bend=not vehicle_bend
		elif event.keycode == KEY_T:
			camera.position=Vector3(-camera.position.x,2.4,-camera.position.z)
		elif event.keycode == KEY_I:
			print(cover.get_stats())
