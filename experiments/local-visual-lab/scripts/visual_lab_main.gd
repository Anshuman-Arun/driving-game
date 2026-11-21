extends Node3D

## Main orchestrator for the Aster Valley Local Visual Lab.
## Builds the procedural alpine lakeside vista, configures Forward+ lighting/presets,
## manages the interactive HUD, and dispatches automated CLI benchmarks.

var tm: TerrainMath
var presets: GraphicsPresets
var camera_rig: CameraRig
var benchmark_runner: BenchmarkRunner

var world_env: WorldEnvironment
var env: Environment
var sun: DirectionalLight3D
var camera: Camera3D

var grass_mmi: MultiMeshInstance3D
var hud_layer: CanvasLayer
var metrics_label: Label
var feature_checks: Dictionary = {}
var tier_buttons: Array[Button] = []
var tod_buttons: Array[Button] = []

var _hud_accum: float = 0.0
var _screenshot_idx: int = 0


func _ready() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	tm = TerrainMath.new()
	presets = GraphicsPresets.new()

	_setup_environment()
	_build_world_geometry()
	_setup_camera_and_rig()
	_populate_instanced_nature()
	_build_hud()

	var vp_rid: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)

	presets.apply_tier(GraphicsPresets.Tier.BALANCED, env, sun, get_viewport(), grass_mmi)
	presets.apply_time_of_day(GraphicsPresets.TimeOfDay.GOLDEN_HOUR, env, sun)
	_sync_hud_controls()

	benchmark_runner = BenchmarkRunner.new()
	benchmark_runner.name = "BenchmarkRunner"
	add_child(benchmark_runner)
	if benchmark_runner.parse_cli_args():
		benchmark_runner.start(camera_rig, presets, env, sun, grass_mmi, hud_layer)


func _setup_environment() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 1.25
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.22
	sun.directional_shadow_split_3 = 0.52
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)

	var sky := Sky.new()
	var sky_mat := PhysicalSkyMaterial.new()
	sky_mat.rayleigh_color = Color(0.24, 0.44, 0.72)
	sky_mat.mie_color = Color(0.86, 0.78, 0.68)
	sky_mat.mie_eccentricity = 0.82
	sky_mat.ground_color = Color(0.14, 0.16, 0.13)
	sky_mat.sun_disk_scale = 1.35
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# AgX filmic tonemapping for natural golden-hour highlight roll-off
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0

	# Atmospheric distance fog with aerial perspective
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.00072
	env.fog_aerial_perspective = 0.65
	env.fog_sky_affect = 0.18

	# Tasteful subtle color grading
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.01
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08

	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)


func _build_world_geometry() -> void:
	var terrain_shader: Shader = load("res://shaders/terrain.gdshader")
	var terrain_mat := ShaderMaterial.new()
	terrain_mat.shader = terrain_shader
	terrain_mat.set_shader_parameter("water_level", TerrainMath.WATER_Y)
	terrain_mat.set_shader_parameter("snow_start_height", 132.0)
	terrain_mat.set_shader_parameter("snow_blend_range", 44.0)

	# 1. Playable high-resolution terrain + collision
	var terrain_mesh: ArrayMesh = MeshBuilder.build_terrain_mesh(tm, 176)
	var terrain_mi := MeshInstance3D.new()
	terrain_mi.name = "AsterValleyTerrain"
	terrain_mi.mesh = terrain_mesh
	terrain_mi.material_override = terrain_mat
	add_child(terrain_mi)

	var terrain_body := StaticBody3D.new()
	terrain_body.name = "TerrainCollision"
	var terrain_col := CollisionShape3D.new()
	terrain_col.shape = terrain_mesh.create_trimesh_shape()
	terrain_body.add_child(terrain_col)
	add_child(terrain_body)

	# 2. Distant alpine mountain ring backdrop (visual only, high smoothness)
	var far_mesh: ArrayMesh = MeshBuilder.build_distant_mountains_mesh(tm, 64, 192)
	var far_mi := MeshInstance3D.new()
	far_mi.name = "DistantAlpineRing"
	far_mi.mesh = far_mesh
	far_mi.material_override = terrain_mat
	far_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_mi)

	# 3. Winding asphalt road + collision + scenic overlook turnout pad
	var road_shader: Shader = load("res://shaders/asphalt_road.gdshader")
	var road_mat := ShaderMaterial.new()
	road_mat.shader = road_shader

	var road_mesh: ArrayMesh = MeshBuilder.build_road_mesh(tm)
	var road_mi := MeshInstance3D.new()
	road_mi.name = "WindingAsphaltRoad"
	road_mi.mesh = road_mesh
	road_mi.material_override = road_mat
	add_child(road_mi)

	var road_body := StaticBody3D.new()
	road_body.name = "RoadCollision"
	var road_col := CollisionShape3D.new()
	road_col.shape = road_mesh.create_trimesh_shape()
	road_body.add_child(road_col)
	add_child(road_body)

	var turnout_mat := StandardMaterial3D.new()
	turnout_mat.albedo_color = Color(0.145, 0.148, 0.155)
	turnout_mat.roughness = 0.74
	var turnout_mi := MeshInstance3D.new()
	turnout_mi.name = "OverlookTurnoutPad"
	turnout_mi.mesh = MeshBuilder.build_overlook_turnout_pad(tm)
	turnout_mi.material_override = turnout_mat
	add_child(turnout_mi)

	# 4. Eastwater Lake water plane
	var water_shader: Shader = load("res://shaders/lake_water.gdshader")
	var water_mat := ShaderMaterial.new()
	water_mat.shader = water_shader
	var water_plane := PlaneMesh.new()
	water_plane.size = Vector2(1600.0, 1600.0)
	water_plane.subdivide_width = 16
	water_plane.subdivide_depth = 16
	var water_mi := MeshInstance3D.new()
	water_mi.name = "EastwaterLake"
	water_mi.mesh = water_plane
	water_mi.position = Vector3(260.0, TerrainMath.WATER_Y, 0.0)
	water_mi.material_override = water_mat
	water_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water_mi)

	# 5. Guardrails, timber overlook deck, and static reference coupe at the turnout
	add_child(MeshBuilder.build_guardrails(tm))
	add_child(MeshBuilder.build_overlook_deck(tm))

	var coupe: Node3D = MeshBuilder.build_showcase_coupe()
	var z_car: float = TerrainMath.OVERLOOK_Z + 2.5
	var c_pos: Vector3 = tm.road_point(z_car)
	var c_right: Vector3 = tm.road_right(z_car)
	var c_fwd: Vector3 = tm.road_tangent(z_car)
	# Park angled slightly toward the overlook vista inside the turnout pocket
	var car_basis := Basis(c_right, Vector3.UP, c_fwd).orthonormalized()
	car_basis = car_basis.rotated(Vector3.UP, deg_to_rad(-18.0))
	coupe.transform = Transform3D(car_basis, c_pos + c_right * (TerrainMath.ROAD_HALF_WIDTH + 3.2) + Vector3(0.0, 0.03, 0.0))
	add_child(coupe)


func _populate_instanced_nature() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261121

	var nature_root := Node3D.new()
	nature_root.name = "InstancedNature"
	add_child(nature_root)

	# Shared foliage shader
	var foliage_shader: Shader = load("res://shaders/foliage_pine.gdshader")

	# 1. Conifer Pines (~640 instances)
	var pine_meshes: Dictionary = MeshBuilder.build_pine_meshes()
	var pine_trunk_mat := StandardMaterial3D.new()
	pine_trunk_mat.albedo_color = Color(0.20, 0.14, 0.10)
	pine_trunk_mat.roughness = 0.92

	var pine_canopy_mat := ShaderMaterial.new()
	pine_canopy_mat.shader = foliage_shader
	pine_canopy_mat.set_shader_parameter("color_a", Color(0.055, 0.135, 0.062))
	pine_canopy_mat.set_shader_parameter("color_b", Color(0.11, 0.19, 0.082))
	pine_canopy_mat.set_shader_parameter("backlight_tint", Color(0.24, 0.34, 0.13))

	var pine_xforms: Array[Transform3D] = []
	var pine_customs: Array[Color] = []
	var attempts: int = 0
	while pine_xforms.size() < 640 and attempts < 6000:
		attempts += 1
		var x: float = rng.randf_range(-192.0, 195.0)
		var z: float = rng.randf_range(-192.0, 192.0)
		var y: float = tm.get_height(x, z)
		if y < TerrainMath.WATER_Y + 1.4:
			continue
		var n: Vector3 = tm.get_normal(x, z, 0.8)
		if n.y < 0.66:
			continue
		var prox: Dictionary = tm.query_road_proximity(x, z)
		var signed_x: float = prox["signed_x"]
		var extra: float = tm.get_overlook_extra_width(prox["z"]) if signed_x > 0.0 else 0.0
		var clearance: float = TerrainMath.SHOULDER_HALF_WIDTH + extra + 2.8
		if prox["dist"] < clearance:
			continue
		# Keep the overlook sightline & benchmark cameras unobstructed
		if signed_x > 0.0 and signed_x < 28.0 and absf(z - TerrainMath.OVERLOOK_Z) < 26.0:
			continue
		if camera_rig.is_blocking_viewpoint(x, z):
			continue

		var sc: float = rng.randf_range(0.72, 1.45)
		var rot_y: float = rng.randf_range(0.0, TAU)
		var tilt_x: float = rng.randf_range(-0.04, 0.04)
		var tilt_z: float = rng.randf_range(-0.04, 0.04)
		var b := Basis.from_euler(Vector3(tilt_x, rot_y, tilt_z)).scaled(Vector3(sc * rng.randf_range(0.88, 1.12), sc, sc * rng.randf_range(0.88, 1.12)))
		pine_xforms.append(Transform3D(b, Vector3(x, y - 0.15, z)))
		pine_customs.append(Color(rng.randf(), rng.randf(), rng.randf(), 1.0))

	_add_multimesh(nature_root, "PineTrunks", pine_meshes["trunk"], pine_trunk_mat, pine_xforms, pine_customs, true)
	_add_multimesh(nature_root, "PineCanopies", pine_meshes["canopy"], pine_canopy_mat, pine_xforms, pine_customs, true)

	# 2. Autumn-Accent Birch / Alder Trees (~120 instances near shoreline & forest edges)
	var birch_meshes: Dictionary = MeshBuilder.build_birch_meshes()
	var birch_trunk_mat := StandardMaterial3D.new()
	birch_trunk_mat.albedo_color = Color(0.76, 0.74, 0.70)
	birch_trunk_mat.roughness = 0.85

	var birch_canopy_mat := ShaderMaterial.new()
	birch_canopy_mat.shader = foliage_shader
	birch_canopy_mat.set_shader_parameter("color_a", Color(0.46, 0.34, 0.07))
	birch_canopy_mat.set_shader_parameter("color_b", Color(0.62, 0.28, 0.06))
	birch_canopy_mat.set_shader_parameter("backlight_tint", Color(0.78, 0.48, 0.12))
	birch_canopy_mat.set_shader_parameter("wind_strength", 0.11)

	var birch_xforms: Array[Transform3D] = []
	var birch_customs: Array[Color] = []
	attempts = 0
	while birch_xforms.size() < 120 and attempts < 3000:
		attempts += 1
		var x: float = rng.randf_range(-165.0, 185.0)
		var z: float = rng.randf_range(-180.0, 180.0)
		var y: float = tm.get_height(x, z)
		if y < TerrainMath.WATER_Y + 0.9 or y > 36.0:
			continue
		var n: Vector3 = tm.get_normal(x, z, 0.8)
		if n.y < 0.72:
			continue
		var prox: Dictionary = tm.query_road_proximity(x, z)
		var signed_x: float = prox["signed_x"]
		var extra: float = tm.get_overlook_extra_width(prox["z"]) if signed_x > 0.0 else 0.0
		if prox["dist"] < TerrainMath.SHOULDER_HALF_WIDTH + extra + 2.4:
			continue
		if signed_x > 0.0 and signed_x < 26.0 and absf(z - TerrainMath.OVERLOOK_Z) < 22.0:
			continue
		if camera_rig.is_blocking_viewpoint(x, z):
			continue

		var sc: float = rng.randf_range(0.75, 1.28)
		var b := Basis.from_euler(Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(0.0, TAU), rng.randf_range(-0.05, 0.05))).scaled(Vector3.ONE * sc)
		birch_xforms.append(Transform3D(b, Vector3(x, y - 0.12, z)))
		birch_customs.append(Color(rng.randf(), rng.randf(), rng.randf(), 1.0))

	_add_multimesh(nature_root, "BirchTrunks", birch_meshes["trunk"], birch_trunk_mat, birch_xforms, birch_customs, true)
	_add_multimesh(nature_root, "BirchCanopies", birch_meshes["canopy"], birch_canopy_mat, birch_xforms, birch_customs, true)

	# 3. Granite Boulders (~340 instances along cut-banks, rocky ridges & shoreline)
	var boulder_mesh: ArrayMesh = MeshBuilder.build_boulder_mesh()
	var boulder_mat := StandardMaterial3D.new()
	boulder_mat.albedo_color = Color(0.32, 0.32, 0.30)
	boulder_mat.roughness = 0.84

	var rock_xforms: Array[Transform3D] = []
	var rock_customs: Array[Color] = []
	attempts = 0
	while rock_xforms.size() < 340 and attempts < 4500:
		attempts += 1
		var x: float = rng.randf_range(-175.0, 175.0)
		var z: float = rng.randf_range(-180.0, 180.0)
		var y: float = tm.get_height(x, z)
		if y < TerrainMath.WATER_Y - 0.55:
			continue
		var prox: Dictionary = tm.query_road_proximity(x, z)
		var signed_x: float = prox["signed_x"]
		var extra: float = tm.get_overlook_extra_width(prox["z"]) if signed_x > 0.0 else 0.0
		if prox["dist"] < TerrainMath.SHOULDER_HALF_WIDTH + extra + 0.8:
			continue
		var n: Vector3 = tm.get_normal(x, z, 0.8)
		if n.y < 0.68:
			continue
		var is_shore: bool = absf(y - TerrainMath.WATER_Y) < 2.4
		var is_road_edge: bool = prox["dist"] < TerrainMath.SHOULDER_HALF_WIDTH + 9.0
		if not (is_shore or is_road_edge) and rng.randf() > 0.20:
			continue

		var sx: float = rng.randf_range(0.55, 2.3)
		var sy: float = sx * rng.randf_range(0.50, 0.95)
		var sz: float = sx * rng.randf_range(0.75, 1.25)
		var b := Basis.from_euler(Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(0.0, TAU), rng.randf_range(-0.25, 0.25))).scaled(Vector3(sx, sy, sz))
		rock_xforms.append(Transform3D(b, Vector3(x, y - sy * 0.44, z)))
		rock_customs.append(Color(rng.randf(), rng.randf(), rng.randf(), 1.0))

	_add_multimesh(nature_root, "GraniteBoulders", boulder_mesh, boulder_mat, rock_xforms, rock_customs, true)

	# 4. High-Density Wind-Animated Grass Tufts (32,000 instances, scaled by preset)
	var grass_mesh: ArrayMesh = MeshBuilder.build_grass_tuft_mesh()
	var grass_shader: Shader = load("res://shaders/grass_blade.gdshader")
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = grass_shader

	var grass_target: int = 32000
	var grass_xforms: Array[Transform3D] = []
	var grass_customs: Array[Color] = []
	grass_xforms.resize(grass_target)
	grass_customs.resize(grass_target)
	var g_count: int = 0
	attempts = 0
	while g_count < grass_target and attempts < 140000:
		attempts += 1
		# Concentrate 70% of grass within 58 m of the road corridor & shoreline for lush foreground density
		var x: float
		var z: float
		if rng.randf() < 0.72:
			z = rng.randf_range(-165.0, 155.0)
			var rx: float = tm.road_center_x(z)
			x = rx + rng.randf_range(-46.0, 62.0)
		else:
			x = rng.randf_range(-160.0, 155.0)
			z = rng.randf_range(-170.0, 170.0)

		var y: float = tm.get_height(x, z)
		if y < TerrainMath.WATER_Y + 0.9 or y > 48.0:
			continue
		var n: Vector3 = tm.get_normal(x, z, 0.7)
		if n.y < 0.74:
			continue
		var prox: Dictionary = tm.query_road_proximity(x, z)
		var signed_x: float = prox["signed_x"]
		var extra: float = tm.get_overlook_extra_width(prox["z"]) if signed_x > 0.0 else 0.0
		if prox["dist"] < TerrainMath.ROAD_HALF_WIDTH + extra + 1.35:
			continue
		# Keep the timber overlook deck footprint completely grass-free
		if signed_x > 0.0 and absf(z - TerrainMath.OVERLOOK_Z) < 16.0 and prox["dist"] < TerrainMath.ROAD_HALF_WIDTH + TerrainMath.OVERLOOK_EXTRA_EAST + 6.0:
			continue

		var sc: float = rng.randf_range(0.68, 1.42)
		var b := Basis.from_euler(Vector3(0.0, rng.randf_range(0.0, TAU), 0.0)).scaled(Vector3(sc, sc * rng.randf_range(0.85, 1.35), sc))
		grass_xforms[g_count] = Transform3D(b, Vector3(x, y - 0.04, z))
		grass_customs[g_count] = Color(rng.randf(), rng.randf(), rng.randf(), 1.0)
		g_count += 1

	grass_xforms.resize(g_count)
	grass_customs.resize(g_count)
	grass_mmi = _add_multimesh(nature_root, "RoadsideGrass", grass_mesh, grass_mat, grass_xforms, grass_customs, false)
	grass_mmi.visibility_range_end = 135.0
	grass_mmi.visibility_range_end_margin = 18.0
	grass_mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _add_multimesh(
	parent: Node3D,
	node_name: String,
	mesh: Mesh,
	mat: Material,
	xforms: Array[Transform3D],
	customs: Array[Color],
	cast_shadows: bool
) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, customs[i])
	mmi.multimesh = mm
	mmi.material_override = mat
	if not cast_shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


func _setup_camera_and_rig() -> void:
	camera = Camera3D.new()
	camera.name = "BenchmarkCamera"
	camera.near = 0.15
	camera.far = 2600.0
	camera.current = true
	add_child(camera)

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.setup(camera, tm)


func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "VisualLabHUD"
	add_child(hud_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(root)

	# Top-left telemetry card
	var left_panel := PanelContainer.new()
	left_panel.position = Vector2(18, 18)
	left_panel.custom_minimum_size = Vector2(360, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, 0.78)
	style.border_color = Color(0.32, 0.44, 0.58, 0.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	left_panel.add_theme_stylebox_override("panel", style)
	root.add_child(left_panel)

	metrics_label = Label.new()
	metrics_label.text = "Aster Valley Local Visual Lab — Initializing..."
	metrics_label.add_theme_font_size_override("font_size", 14)
	metrics_label.add_theme_color_override("font_color", Color(0.92, 0.95, 0.98))
	left_panel.add_child(metrics_label)

	# Top-right interactive controls card
	var right_panel := PanelContainer.new()
	right_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_panel.offset_left = -320
	right_panel.offset_right = -18
	right_panel.offset_top = 18
	right_panel.add_theme_stylebox_override("panel", style)
	root.add_child(right_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	right_panel.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "GRAPHICS TIER"
	hdr.add_theme_font_size_override("font_size", 12)
	hdr.add_theme_color_override("font_color", Color(0.65, 0.78, 0.92))
	vbox.add_child(hdr)

	var tier_row := HBoxContainer.new()
	vbox.add_child(tier_row)
	for i in range(GraphicsPresets.TIER_NAMES.size()):
		var btn := Button.new()
		btn.text = GraphicsPresets.TIER_NAMES[i]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tier_idx: int = i
		btn.pressed.connect(func() -> void:
			presets.apply_tier(tier_idx, env, sun, get_viewport(), grass_mmi)
			_sync_hud_controls()
		)
		tier_row.add_child(btn)
		tier_buttons.append(btn)

	var tod_hdr := Label.new()
	tod_hdr.text = "LIGHTING / TIME OF DAY"
	tod_hdr.add_theme_font_size_override("font_size", 12)
	tod_hdr.add_theme_color_override("font_color", Color(0.65, 0.78, 0.92))
	vbox.add_child(tod_hdr)

	var tod_row := HBoxContainer.new()
	vbox.add_child(tod_row)
	for i in range(GraphicsPresets.TOD_NAMES.size()):
		var btn := Button.new()
		btn.text = GraphicsPresets.TOD_NAMES[i].split(" ")[0]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tod_idx: int = i
		btn.pressed.connect(func() -> void:
			presets.apply_time_of_day(tod_idx, env, sun)
			_sync_hud_controls()
		)
		tod_row.add_child(btn)
		tod_buttons.append(btn)

	var vp_hdr := Label.new()
	vp_hdr.text = "BENCHMARK CAMERAS"
	vp_hdr.add_theme_font_size_override("font_size", 12)
	vp_hdr.add_theme_color_override("font_color", Color(0.65, 0.78, 0.92))
	vbox.add_child(vp_hdr)

	var vp_row := HBoxContainer.new()
	vbox.add_child(vp_row)
	for i in range(4):
		var btn := Button.new()
		btn.text = "VP%d" % [i + 1]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vp_i: int = i
		btn.pressed.connect(func() -> void: camera_rig.select_viewpoint(vp_i))
		vp_row.add_child(btn)
	var fly_btn := Button.new()
	fly_btn.text = "Fly"
	fly_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fly_btn.pressed.connect(func() -> void: camera_rig.start_flythrough())
	vp_row.add_child(fly_btn)

	var feat_hdr := Label.new()
	feat_hdr.text = "FEATURE TOGGLES"
	feat_hdr.add_theme_font_size_override("font_size", 12)
	feat_hdr.add_theme_color_override("font_color", Color(0.65, 0.78, 0.92))
	vbox.add_child(feat_hdr)

	var feat_grid := GridContainer.new()
	feat_grid.columns = 2
	vbox.add_child(feat_grid)
	var feature_list: Array[Array] = [
		["ssao", "SSAO"],
		["ssil", "SSIL"],
		["ssr", "SSR"],
		["sdfgi", "SDFGI"],
		["volumetric_fog", "Vol Fog"],
		["glow", "Glow"],
		["taa", "TAA"],
	]
	for item in feature_list:
		var key: String = item[0]
		var title: String = item[1]
		var cb := CheckBox.new()
		cb.text = title
		cb.toggled.connect(func(pressed: bool) -> void:
			presets.state[key] = pressed
			presets.apply_state(env, sun, get_viewport(), grass_mmi)
		)
		feat_grid.add_child(cb)
		feature_checks[key] = cb

	# Bottom hotkey legend
	var footer := PanelContainer.new()
	footer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	footer.offset_left = 18
	footer.offset_bottom = -16
	footer.offset_top = -52
	footer.add_theme_stylebox_override("panel", style)
	root.add_child(footer)

	var footer_lbl := Label.new()
	footer_lbl.text = "1-4: Viewpoints  |  F: Flythrough  |  P: Cycle Tier  |  T: Lighting  |  H: Toggle HUD  |  F12: Screenshot  |  WASD+RMB: Free Cam"
	footer_lbl.add_theme_font_size_override("font_size", 12)
	footer_lbl.add_theme_color_override("font_color", Color(0.80, 0.86, 0.92))
	footer.add_child(footer_lbl)


func _sync_hud_controls() -> void:
	for key in feature_checks.keys():
		var cb: CheckBox = feature_checks[key]
		cb.set_pressed_no_signal(bool(presets.state.get(key, false)))
	for i in range(tier_buttons.size()):
		tier_buttons[i].disabled = (i == presets.current_tier)
	for i in range(tod_buttons.size()):
		tod_buttons[i].disabled = (i == presets.current_tod)


func _unhandled_key_input(event: InputEvent) -> void:
	if benchmark_runner != null and benchmark_runner.active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		match k:
			KEY_1: camera_rig.select_viewpoint(0)
			KEY_2: camera_rig.select_viewpoint(1)
			KEY_3: camera_rig.select_viewpoint(2)
			KEY_4: camera_rig.select_viewpoint(3)
			KEY_F: camera_rig.start_flythrough()
			KEY_P:
				var next_t: int = (presets.current_tier + 1) % GraphicsPresets.TIER_NAMES.size()
				presets.apply_tier(next_t, env, sun, get_viewport(), grass_mmi)
				_sync_hud_controls()
			KEY_T:
				var next_tod: int = (presets.current_tod + 1) % GraphicsPresets.TOD_NAMES.size()
				presets.apply_time_of_day(next_tod, env, sun)
				_sync_hud_controls()
			KEY_H:
				hud_layer.visible = not hud_layer.visible
			KEY_F12:
				_save_manual_screenshot()


func _save_manual_screenshot() -> void:
	var dir_path: String = ProjectSettings.globalize_path("res://captures_tmp")
	DirAccess.make_dir_recursive_absolute(dir_path)
	_screenshot_idx += 1
	var fname: String = "manual_%03d.png" % _screenshot_idx
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(dir_path.path_join(fname))
	print("[VisualLab] Saved manual screenshot: %s" % dir_path.path_join(fname))


func _process(delta: float) -> void:
	if benchmark_runner != null and benchmark_runner.active:
		return

	camera_rig.step_interactive(delta)

	_hud_accum += delta
	if _hud_accum >= 0.2 and hud_layer.visible:
		_hud_accum = 0.0
		var vp_rid: RID = get_viewport().get_viewport_rid()
		var fps: float = Performance.get_monitor(Performance.TIME_FPS)
		var frame_ms: float = 1000.0 / maxf(fps, 0.1)
		var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		var cpu_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
		var dc: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var prims: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		var objs: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		var vram: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)
		var grass_vis: int = grass_mmi.multimesh.visible_instance_count if grass_mmi != null else 0
		var vp_sz: Vector2i = get_viewport().get_visible_rect().size

		metrics_label.text = (
			"ASTER VALLEY — LOCAL VISUAL LAB (Forward+)\n"
			+ "GPU: %s\n"
			+ "View: %s  (%dx%d)\n"
			+ "Tier: %s  |  Lighting: %s\n"
			+ "FPS: %.1f  (Frame: %.2f ms)\n"
			+ "Render GPU: %.2f ms  |  Render CPU: %.2f ms\n"
			+ "Draw Calls: %d  |  Objects: %d  |  Prims: %d\n"
			+ "Grass Visible: %d  |  VRAM: %.1f MB"
		) % [
			RenderingServer.get_video_adapter_name(),
			camera_rig.get_active_label(), vp_sz.x, vp_sz.y,
			GraphicsPresets.TIER_NAMES[presets.current_tier],
			GraphicsPresets.TOD_NAMES[presets.current_tod],
			fps, frame_ms, gpu_ms, cpu_ms, dc, objs, prims, grass_vis, vram
		]
