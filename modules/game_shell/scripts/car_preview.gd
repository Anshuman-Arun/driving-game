extends SubViewportContainer
## Original primitive 3D showcase model; not a physics mesh or the Art PR GLB.
const Catalog = preload("car_catalog.gd")
var viewport: SubViewport
var turntable: Node3D
var body_parts: Array[MeshInstance3D] = []
var current_id: String = "vela_gt"
var orbit_enabled: bool = true

func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(340, 290)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 400)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#172936")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#b6ccdc")
	environment.environment.ambient_light_energy = 0.8
	world.add_child(environment)
	var camera := Camera3D.new()
	camera.position = Vector3(6.2, 3.7, 7.2)
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.7, 0), Vector3.UP)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -32, 0)
	sun.light_energy = 2.5
	world.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-3, 3.5, -4)
	fill.light_energy = 950.0
	fill.omni_range = 13.0
	world.add_child(fill)
	turntable = Node3D.new()
	world.add_child(turntable)
	_part(world, Vector3(14.0, 0.08, 14.0), Vector3(0, -0.11, 0), Color("#243641"))
	for i in range(-6, 7):
		_part(world, Vector3(0.016, 0.004, 12.0), Vector3(float(i), -0.063, 0), Color("#35515b"))
		_part(world, Vector3(12.0, 0.004, 0.016), Vector3(0, -0.063, float(i)), Color("#35515b"))
	set_car(current_id)

func _material(tint: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.metallic = metallic
	m.roughness = 0.38 if metallic > 0.0 else 0.68
	return m

func _part(parent: Node3D, dimensions: Vector3, at: Vector3, tint: Color, metallic: float = 0.0) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	part.mesh = box
	part.material_override = _material(tint, metallic)
	part.position = at
	parent.add_child(part)
	return part

func _wheel(x: float, z: float) -> void:
	var tire := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.365
	cylinder.bottom_radius = 0.365
	cylinder.height = 0.23
	tire.mesh = cylinder
	tire.material_override = _material(Color("#11171b"))
	tire.position = Vector3(x, 0.35, z)
	tire.rotation_degrees.z = 90.0
	turntable.add_child(tire)
	var rim := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.215
	disc.bottom_radius = 0.215
	disc.height = 0.241
	rim.mesh = disc
	rim.material_override = _material(Color("#bcc4c7"), 0.75)
	rim.position = tire.position
	rim.rotation_degrees.z = 90.0
	turntable.add_child(rim)

func set_car(car_id: String) -> void:
	current_id = car_id if not Catalog.car(car_id).is_empty() else "vela_gt"
	if turntable == null:
		return
	for child in turntable.get_children():
		turntable.remove_child(child)
		child.queue_free()
	var spec := Catalog.car(current_id)
	var tint := Color(str(spec["accent"]))
	var length := 4.1 if current_id == "orion_rs" else (4.7 if current_id == "kestrel_xr" else 4.5)
	var width := 1.80 if current_id == "orion_rs" else (1.94 if current_id == "kestrel_xr" else 1.88)
	_part(turntable, Vector3(width, 0.36, length), Vector3(0, 0.73, 0), tint, 0.36)
	_part(turntable, Vector3(width * 0.81, 0.54, 1.95), Vector3(0, 1.13, 0.25), tint.lightened(0.08), 0.35)
	_part(turntable, Vector3(width * 0.74, 0.23, 1.4), Vector3(0, 1.43, 0.35), Color("#35515e"), 0.22)
	_part(turntable, Vector3(width * .86, .12, .24), Vector3(0, .73, -length * .48), Color("#d5e5e8"))
	_part(turntable, Vector3(width * .84, .13, .23), Vector3(0, .72, length * .48), Color("#5b1d27"))
	for x in [-width * .48, width * .48]:
		for z in [-length * .30, length * .30]:
			_wheel(x, z)
	for x in [-width * .32, width * .32]:
		_part(turntable, Vector3(.28,.08,.05), Vector3(x,.85,-length * .505), Color("#fff1cd"))
	turntable.rotation.y = -.28

func set_quality(scale: float) -> void:
	if viewport != null:
		viewport.scaling_3d_scale = clampf(scale, 0.5, 1.0)

func _process(delta: float) -> void:
	if orbit_enabled and turntable != null:
		turntable.rotate_y(delta * 0.13)
