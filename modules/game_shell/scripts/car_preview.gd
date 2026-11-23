extends SubViewportContainer
## Forza-style 3D Garage Showroom preview with studio HDRI IBL, 3-point softbox lighting,
## reflective circular turntable plinth, and fallback primitive preview.
const Catalog = preload("car_catalog.gd")
const STUDIO_HDRI_PATH := "res://assets/forza_env/hdri/garage_studio.hdr"

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
	viewport.size = Vector2i(800, 500)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)

	var env := Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.08
	env.ssao_enabled = true
	env.ssao_radius = 0.9
	env.ssao_intensity = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.14
	env.glow_hdr_threshold = 1.15

	var hdri: Texture2D = null
	if ResourceLoader.exists(STUDIO_HDRI_PATH):
		hdri = load(STUDIO_HDRI_PATH) as Texture2D
	if hdri != null:
		var sky := Sky.new()
		var sky_mat := PanoramaSkyMaterial.new()
		sky_mat.panorama = hdri
		sky.sky_material = sky_mat
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.background_energy_multiplier = 0.42
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 0.72
		env.ambient_light_energy = 0.85
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("#111922")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("#b8ccd9")
		env.ambient_light_energy = 0.85

	var environment := WorldEnvironment.new()
	environment.environment = env
	world.add_child(environment)

	var camera := Camera3D.new()
	camera.fov = 38.0
	camera.position = Vector3(5.05, 1.92, 5.85)
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.58, 0), Vector3.UP)
	camera.current = true

	# 3-Point Studio Softbox Lighting
	var key := DirectionalLight3D.new()
	key.name = "StudioKeyLight"
	key.rotation_degrees = Vector3(-48, -36, 0)
	key.light_color = Color(1.0, 0.97, 0.93)
	key.light_energy = 1.85
	key.shadow_enabled = true
	key.shadow_blur = 1.8
	world.add_child(key)

	var rim := SpotLight3D.new()
	rim.name = "StudioRimLight"
	rim.position = Vector3(-4.2, 3.2, -4.6)
	rim.light_color = Color(0.76, 0.88, 1.0)
	rim.light_energy = 3.2
	rim.spot_range = 16.0
	rim.spot_angle = 48.0
	world.add_child(rim)
	rim.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)

	var fill := OmniLight3D.new()
	fill.name = "StudioFillLight"
	fill.position = Vector3(3.8, 2.4, 2.6)
	fill.light_color = Color(1.0, 0.92, 0.82)
	fill.light_energy = 1.1
	fill.omni_range = 12.0
	world.add_child(fill)

	turntable = Node3D.new()
	world.add_child(turntable)

	_build_showroom_floor(world)
	set_car(current_id)

func _build_showroom_floor(world: Node3D) -> void:
	# Dark reflective showroom floor
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 12.0
	floor_mesh.bottom_radius = 12.0
	floor_mesh.height = 0.08
	floor_mesh.radial_segments = 48
	var floor_node := MeshInstance3D.new()
	floor_node.name = "ShowroomFloor"
	floor_node.mesh = floor_mesh
	floor_node.position = Vector3(0.0, -0.055, 0.0)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#12171d")
	floor_mat.metallic = 0.32
	floor_mat.roughness = 0.22
	floor_mat.clearcoat_enabled = true
	floor_mat.clearcoat = 0.65
	floor_mat.clearcoat_roughness = 0.12
	floor_node.material_override = floor_mat
	world.add_child(floor_node)

	# Sleek circular turntable plinth
	var plinth_mesh := CylinderMesh.new()
	plinth_mesh.top_radius = 3.05
	plinth_mesh.bottom_radius = 3.15
	plinth_mesh.height = 0.03
	plinth_mesh.radial_segments = 64
	var plinth := MeshInstance3D.new()
	plinth.name = "ShowroomPlinth"
	plinth.mesh = plinth_mesh
	plinth.position = Vector3(0.0, -0.015, 0.0)
	var plinth_mat := StandardMaterial3D.new()
	plinth_mat.albedo_color = Color("#182029")
	plinth_mat.metallic = 0.45
	plinth_mat.roughness = 0.16
	plinth_mat.clearcoat_enabled = true
	plinth_mat.clearcoat = 0.8
	plinth_mat.clearcoat_roughness = 0.08
	plinth.material_override = plinth_mat
	world.add_child(plinth)

	# Subtle glowing studio accent ring around plinth perimeter
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 3.04
	ring_mesh.outer_radius = 3.10
	ring_mesh.rings = 64
	ring_mesh.ring_segments = 12
	var ring := MeshInstance3D.new()
	ring.name = "ShowroomAccentRing"
	ring.mesh = ring_mesh
	ring.position = Vector3(0.0, -0.012, 0.0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color("#4db8d6")
	ring_mat.emission_enabled = true
	ring_mat.emission = Color("#48b8d8")
	ring_mat.emission_energy_multiplier = 1.6
	ring.material_override = ring_mat
	world.add_child(ring)

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
		turntable.rotate_y(delta * 0.14)
