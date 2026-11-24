extends RefCounted
## Configures Forza-tier golden-afternoon sky, IBL lighting, post-processing,
## and PBR material overrides for Aster Valley Free Roam.

const HDRI_SKY_PATH := "res://assets/forza_env/hdri/outdoor_sky.hdr"
const MAT_TERRAIN_PATH := "res://assets/forza_env/materials/terrain_forza.tres"
const MAT_ASPHALT_PATH := "res://assets/forza_env/materials/road_asphalt_forza.tres"
const MAT_JUNCTION_ASPHALT_PATH := "res://assets/forza_env/materials/road_junction_asphalt_forza.tres"
const MAT_GRAVEL_PATH := "res://assets/forza_env/materials/road_gravel_forza.tres"
const MAT_SHOULDER_PATH := "res://assets/forza_env/materials/road_shoulder_forza.tres"

static func apply_environment(root: Node3D) -> void:
	if not root.get("shell_managed"):
		apply_quality(root.get_viewport(), "medium")
	var world_env := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null:
		world_env.environment = build_environment()
	var sun := root.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		configure_sun(sun)

static func apply_quality(viewport: Viewport, preset: String) -> void:
	var low := preset == "low"
	viewport.scaling_3d_scale = 0.85 if low else 1.0
	viewport.msaa_3d = Viewport.MSAA_2X if preset == "high" else Viewport.MSAA_DISABLED
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	viewport.use_taa = forward_plus and not low
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if viewport.use_taa else Viewport.SCREEN_SPACE_AA_FXAA
	viewport.use_debanding = false

static func build_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = _build_sky()
	env.sky_rotation = Vector3(0.0, 0.42, 0.0)
	env.background_energy_multiplier = 0.97

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.85
	env.ambient_light_color = Color(0.76, 0.84, 0.94)
	env.ambient_light_energy = 0.60
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# Filmic AgX tonemapping with calibrated exposure for golden afternoon.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0

	env.ssao_enabled = false
	env.ssil_enabled = false

	# Subtle HDR bloom for sunlight glints, headlights, and brake lights.
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.26
	env.glow_strength = 0.82
	env.glow_bloom = 0.10
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.15
	env.glow_hdr_scale = 1.8

	# Exponential + aerial-perspective distance haze across the 2x2 km valley.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.66, 0.77, 0.90)
	env.fog_light_energy = 0.92
	env.fog_sun_scatter = 0.22
	env.fog_density = 0.00052
	env.fog_aerial_perspective = 0.58
	env.fog_sky_affect = 0.30
	env.fog_height = 24.0
	env.fog_height_density = 0.0014

	# Keep the afternoon warmth without flattening the forest canopy.
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.01
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.07
	return env

static func _build_sky() -> Sky:
	var sky := Sky.new()
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	if ResourceLoader.exists(HDRI_SKY_PATH):
		var tex := ResourceLoader.load(HDRI_SKY_PATH) as Texture2D
		if tex != null:
			var pano := PanoramaSkyMaterial.new()
			pano.panorama = tex
			pano.filter = true
			pano.energy_multiplier = 1.12
			sky.sky_material = pano
			return sky

	# Graceful procedural sky fallback if HDRI is unavailable.
	var proc := ProceduralSkyMaterial.new()
	proc.sky_top_color = Color(0.24, 0.47, 0.78)
	proc.sky_horizon_color = Color(0.76, 0.84, 0.92)
	proc.sky_curve = 0.14
	proc.ground_bottom_color = Color(0.18, 0.22, 0.18)
	proc.ground_horizon_color = Color(0.56, 0.63, 0.66)
	proc.sun_angle_max = 28.0
	proc.sun_curve = 0.12
	sky.sky_material = proc
	return sky

static func configure_sun(sun: DirectionalLight3D) -> void:
	# Warm golden-afternoon elevation (~32 deg) casting sculptural valley shadows.
	sun.rotation = Vector3(-0.60, -1.46, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.86)
	sun.light_energy = 2.08
	sun.light_indirect_energy = 1.0
	sun.light_specular = 1.0
	sun.light_angular_distance = 0.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 345.0
	sun.directional_shadow_split_1 = 0.065
	sun.directional_shadow_split_2 = 0.21
	sun.directional_shadow_split_3 = 0.52
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.15
	sun.shadow_bias = 0.024
	sun.shadow_normal_bias = 0.82

static func apply_world_materials(world: Node) -> void:
	if world == null:
		return
	var terrain_mat := _load_material(MAT_TERRAIN_PATH)
	if terrain_mat != null:
		world.set("terrain_material_override", terrain_mat)
	var asphalt_mat := _load_material(MAT_ASPHALT_PATH)
	if asphalt_mat != null:
		world.set("asphalt_material_override", asphalt_mat)
	var junction_mat := _load_material(MAT_JUNCTION_ASPHALT_PATH)
	if junction_mat != null:
		world.set_meta("junction_asphalt_material_override", junction_mat)
	var gravel_mat := _load_material(MAT_GRAVEL_PATH)
	if gravel_mat != null:
		world.set("gravel_material_override", gravel_mat)
	var shoulder_mat := _load_material(MAT_SHOULDER_PATH)
	if shoulder_mat != null:
		world.set("shoulder_material_override", shoulder_mat)

static func _load_material(path: String) -> Material:
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Material
