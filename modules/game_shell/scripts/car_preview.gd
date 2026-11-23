extends SubViewportContainer
## Live showroom viewport. The integrated game replaces the primitive fallback with a curated vehicle GLB.
const Catalog = preload("car_catalog.gd")
var viewport: SubViewport
var turntable: Node3D
var body_parts: Array[MeshInstance3D] = []
var current_id: String = "vela_gt"
var orbit_enabled: bool = true

func _ready() -> void:
	stretch = true
	custom_minimum_size = Vector2(420, 320)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = 1.0
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.use_debanding = true
	add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#0d1a26")
	sky_material.sky_horizon_color = Color("#34515b")
	sky_material.ground_bottom_color = Color("#0b1218")
	sky_material.ground_horizon_color = Color("#1c3039")
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.environment.background_mode = Environment.BG_SKY
	environment.environment.sky = sky
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#92aebb")
	environment.environment.ambient_light_energy = 0.62
	world.add_child(environment)

	var camera := Camera3D.new()
	camera.position = Vector3(5.0, 2.7, 6.2)
	camera.fov = 43.0
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	world.add_child(camera)
	camera.look_at(Vector3(0.0, 0.72, 0.0), Vector3.UP)
	camera.current = true

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	key.light_color = Color("#fff0dc")
	key.light_energy = 1.75
	key.shadow_enabled = true
	world.add_child(key)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-3.6, 2.8, 2.2)
	fill.light_color = Color("#9bcbd8")
	fill.light_energy = 1.15
	fill.omni_range = 13.0
	world.add_child(fill)

	var rim := OmniLight3D.new()
	rim.position = Vector3(3.5, 2.6, -3.8)
	rim.light_color = Color("#7ed8ce")
	rim.light_energy = 2.0
	rim.omni_range = 9.0
	world.add_child(rim)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(40.0, 40.0)
	floor.mesh = floor_mesh
	floor.position = Vector3(0.0, -0.145, 0.0)
	var floor_material := _material(Color("#101c22"), 0.12)
	floor_material.roughness = 0.62
	floor.material_override = floor_material
	world.add_child(floor)

	var plinth := MeshInstance3D.new()
	var plinth_mesh := CylinderMesh.new()
	plinth_mesh.top_radius = 5.6
	plinth_mesh.bottom_radius = 5.6
	plinth_mesh.height = 0.12
	plinth_mesh.radial_segments = 96
	plinth.mesh = plinth_mesh
	plinth.position = Vector3(0.0, -0.07, 0.0)
	var plinth_material := _material(Color("#1a3037"), 0.3)
	plinth_material.roughness = 0.38
	plinth.material_override = plinth_material
	world.add_child(plinth)

	turntable = Node3D.new()
	world.add_child(turntable)
	set_car(current_id)

func _material(tint: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = metallic
	material.roughness = 0.38 if metallic > 0.0 else 0.68
	return material

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
	_part(turntable, Vector3(width * 0.86, 0.12, 0.24), Vector3(0, 0.73, -length * 0.48), Color("#d5e5e8"))
	_part(turntable, Vector3(width * 0.84, 0.13, 0.23), Vector3(0, 0.72, length * 0.48), Color("#5b1d27"))
	for x in [-width * 0.48, width * 0.48]:
		for z in [-length * 0.30, length * 0.30]:
			_wheel(x, z)
	for x in [-width * 0.32, width * 0.32]:
		_part(turntable, Vector3(0.28, 0.08, 0.05), Vector3(x, 0.85, -length * 0.505), Color("#fff1cd"))
	turntable.rotation.y = -0.28

func set_quality(scale: float) -> void:
	if viewport == null:
		return
	var requested_scale := clampf(scale, 0.67, 1.25)
	# Keep the preview at native resolution at every preset; high adds gentle supersampling.
	viewport.scaling_3d_scale = maxf(1.0, requested_scale)
	viewport.msaa_3d = Viewport.MSAA_2X if requested_scale < 0.9 else Viewport.MSAA_4X

func _process(delta: float) -> void:
	if orbit_enabled and turntable != null:
		turntable.rotate_y(delta * 0.13)
