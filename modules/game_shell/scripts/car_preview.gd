extends Control
## Live showroom with an independent render target sized in window pixels.
const Catalog = preload("car_catalog.gd")
const StudioSky = preload("showroom_sky.gdshader")
const StudioFloor = preload("showroom_floor.gdshader")

var viewport: SubViewport
var turntable: Node3D
var current_id := "vela_gt"
var orbit_enabled := true
var _camera: Camera3D
var _quality := 1.15
var _heading := -0.28
var _elapsed := 0.0
var _car_span := 4.9
var _look_height := 0.65

func _ready() -> void:
	custom_minimum_size = Vector2(280, 280)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.size = Vector2i(2, 2)
	viewport.own_world_3d = true
	viewport.scaling_3d_scale = 1.0
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	var display := TextureRect.new()
	display.texture = viewport.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_sync_resolution)
	get_viewport().size_changed.connect(_sync_resolution)
	_sync_resolution.call_deferred()

	var world := Node3D.new()
	viewport.add_child(world)

	var env := Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.04
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.80
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var sky := Sky.new()
	var softboxes := ShaderMaterial.new()
	softboxes.shader = StudioSky
	sky.sky_material = softboxes
	env.sky = sky

	var environment := WorldEnvironment.new()
	environment.environment = env
	world.add_child(environment)

	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = 35.0
	_camera.near = 0.15
	_camera.far = 100.0
	world.add_child(_camera)
	_camera.current = true

	# 3-Point Studio Softbox Lighting
	var key := DirectionalLight3D.new()
	key.name = "StudioKeyLight"
	key.rotation_degrees = Vector3(-68, -33, 0)
	key.light_color = Color(1.0, 0.97, 0.93)
	key.light_energy = 1.10
	key.light_specular = 0.23
	key.shadow_enabled = true
	key.shadow_blur = 1.2
	key.directional_shadow_max_distance = 12.0
	world.add_child(key)

	var rim := SpotLight3D.new()
	rim.name = "StudioRimLight"
	rim.position = Vector3(-4.2, 3.2, -4.6)
	rim.light_color = Color(0.76, 0.88, 1.0)
	rim.light_energy = 2.15
	rim.light_specular = 0.3
	rim.spot_range = 16.0
	rim.spot_angle = 48.0
	world.add_child(rim)
	rim.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)

	var fill := OmniLight3D.new()
	fill.name = "StudioFillLight"
	fill.position = Vector3(3.8, 2.4, 2.6)
	fill.light_color = Color(1.0, 0.92, 0.82)
	fill.light_energy = 0.8
	fill.light_specular = 0.25
	fill.omni_range = 12.0
	world.add_child(fill)

	turntable = Node3D.new()
	world.add_child(turntable)

	_build_showroom_floor(world)
	set_car(current_id)

func _sync_resolution() -> void:
	if viewport == null or not is_inside_tree():
		return
	var scale := get_viewport().get_stretch_transform().get_scale().abs()
	var pixels := size * scale
	var quality := minf(_quality, 3840.0 / maxf(1.0, pixels.x))
	quality = minf(quality, 2160.0 / maxf(1.0, pixels.y))
	var target := Vector2i((pixels * quality).round()).max(Vector2i(2, 2))
	if viewport.size != target:
		viewport.size = target
	_frame_car()

func _frame_car() -> void:
	if _camera == null:
		return
	var aspect := size.x / maxf(size.y, 1.0)
	var distance := _car_span * maxf(1.68, 0.79 * aspect)
	var azimuth := deg_to_rad(33.0)
	_camera.position = Vector3(sin(azimuth) * distance, _look_height + distance * 0.20, cos(azimuth) * distance)
	_camera.look_at(Vector3(0.0, _look_height, 0.0))

func _build_showroom_floor(world: Node3D) -> void:
	var floor := MeshInstance3D.new()
	floor.name = "CycloramaFloor"
	var surface := PlaneMesh.new()
	surface.size = Vector2(54.0, 54.0)
	floor.mesh = surface
	floor.position.y = -0.101
	var backdrop := ShaderMaterial.new()
	backdrop.shader = StudioFloor
	floor.material_override = backdrop
	world.add_child(floor)

	var deck := MeshInstance3D.new()
	deck.name = "TurntableDeck"
	var plinth := CylinderMesh.new()
	plinth.top_radius = 3.35
	plinth.bottom_radius = 3.4
	plinth.height = 0.10
	plinth.radial_segments = 120
	deck.mesh = plinth
	deck.position.y = -0.051
	deck.material_override = _material(Color("#354854"), 0.12)
	deck.material_override.roughness = 0.72
	world.add_child(deck)

	var ring := MeshInstance3D.new()
	ring.name = "TurntableTrim"
	var trim := TorusMesh.new()
	trim.inner_radius = 3.18
	trim.outer_radius = 3.21
	trim.rings = 96
	trim.ring_segments = 8
	ring.mesh = trim
	ring.position.y = -0.002
	ring.material_override = _material(Color("#7f9294"), 0.0)
	world.add_child(ring)

func _clear_car() -> void:
	for child in turntable.get_children():
		turntable.remove_child(child)
		child.queue_free()

func set_model(model: Node3D) -> void:
	_clear_car()
	turntable.rotation.y = 0.0
	turntable.add_child(model)
	var studio_materials := {}
	var bounds := AABB()
	var has_bounds := false
	var world_to_stage := turntable.global_transform.affine_inverse()
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null:
			continue
		for surface in part.mesh.get_surface_count():
			var source := part.get_active_material(surface) as StandardMaterial3D
			if source == null:
				continue
			if not studio_materials.has(source):
				var material := source.duplicate() as StandardMaterial3D
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				material.roughness = maxf(material.roughness, 0.23)
				material.clearcoat_roughness = maxf(material.clearcoat_roughness, 0.22)
				if material.resource_name.begins_with("Glass_"):
					material.cull_mode = BaseMaterial3D.CULL_BACK
				studio_materials[source] = material
			part.set_surface_override_material(surface, studio_materials[source])
		var into_stage := world_to_stage * part.global_transform
		var part_bounds := into_stage * part.get_aabb()
		bounds = bounds.merge(part_bounds) if has_bounds else part_bounds
		has_bounds = true
	if has_bounds:
		var center := bounds.get_center()
		model.position -= Vector3(center.x, bounds.position.y, center.z)
		_car_span = Vector2(bounds.size.x, bounds.size.z).length()
		_look_height = bounds.size.y * 0.45
	_heading = 2.88
	_elapsed = 0.0
	turntable.rotation.y = _heading
	_frame_car()

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
	_clear_car()
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
	_heading = 2.88
	_elapsed = 0.0
	_car_span = Vector2(width, length).length()
	_look_height = 0.73
	turntable.rotation.y = _heading
	_frame_car()

func set_quality(scale: float) -> void:
	_quality = 1.0 if scale < 0.9 else (1.15 if scale <= 1.0 else 1.3)
	_sync_resolution()

func _process(delta: float) -> void:
	if orbit_enabled and turntable != null:
		_elapsed = fmod(_elapsed + delta * 0.49, TAU)
		turntable.rotation.y = _heading + sin(_elapsed) * 0.30
