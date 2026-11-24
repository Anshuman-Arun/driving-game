class_name EnvironmentConfig
extends RefCounted
## Forza-tier Environment, Lighting, Sky, Shadows & Post-Processing Configuration.
##
## Manages Forward+ renderer settings, raking directional sunlight with 4-split cascade shadows,
## calibrated AgX tonemapping, IBL sky, screen-space effects (SSAO, SSIL, SSR), volumetric depth fog,
## and quality preset scaling (Ultra, High, Medium, Low).

# Resource paths
const HDRI_SKY_PATH := "res://assets/forza_env/hdri/outdoor_sky.hdr"
const FORZA_ENV_PATH := "res://assets/forza_env/materials/forza_environment.tres"

# Directional Sunlight Calibration
# Raking sun angle (~28-35 deg elevation, side-lit across road)
const SUN_ROTATION := Vector3(-0.52, -1.45, 0.0)
const SUN_COLOR := Color(1.0, 0.960784, 0.894118, 1.0) # #FFF5E4 warm afternoon sunlight
const SUN_ENERGY := 2.8
const SUN_ANGULAR_DISTANCE := 0.5
const SUN_SHADOW_BIAS := 0.04
const SUN_SHADOW_NORMAL_BIAS := 0.85
const SUN_SHADOW_BLUR := 2.0
const SUN_SHADOW_MAX_DISTANCE := 450.0
const SUN_SHADOW_SPLIT_1 := 0.08
const SUN_SHADOW_SPLIT_2 := 0.22
const SUN_SHADOW_SPLIT_3 := 0.52

# Sky alignment
const SKY_Y_ROTATION := 0.42 # ~24 degrees (aligned with sun azim/raking direction)

# Quality presets definitions
const QUALITY_ULTRA := "ultra"
const QUALITY_HIGH := "high"
const QUALITY_MEDIUM := "medium"
const QUALITY_LOW := "low"

## Main entry point to apply complete lighting, post-processing, and renderer specs.
static func apply_to_scene(world_env: WorldEnvironment, sun: DirectionalLight3D, quality: String = QUALITY_ULTRA) -> void:
	var viewport: Viewport = null
	if world_env != null and world_env.is_inside_tree():
		viewport = world_env.get_viewport()
	elif sun != null and sun.is_inside_tree():
		viewport = sun.get_viewport()

	if viewport != null:
		apply_viewport_renderer_config(viewport, quality)
	else:
		apply_rendering_server_config(quality)

	if world_env != null:
		var env := get_or_create_environment(quality)
		world_env.environment = env

	if sun != null:
		configure_sun(sun, quality)

## Applies lighting, environment, and viewport settings starting from a root Node3D.
static func apply_to_root(root: Node3D, quality: String = QUALITY_ULTRA) -> void:
	if root == null:
		return
	var world_env := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := root.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		# Search child nodes for any DirectionalLight3D
		for child in root.get_children():
			if child is DirectionalLight3D:
				sun = child
				break
	apply_to_scene(world_env, sun, quality)

## Configures the Viewport for Forward+ rendering, anti-aliasing (TAA/MSAA), and debanding.
static func apply_viewport_renderer_config(viewport: Viewport, quality: String = QUALITY_ULTRA) -> void:
	if viewport == null:
		return

	var q := quality.to_lower()
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"

	match q:
		QUALITY_ULTRA:
			viewport.scaling_3d_scale = 1.0
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			viewport.use_taa = forward_plus
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if viewport.use_taa else Viewport.SCREEN_SPACE_AA_FXAA
			viewport.use_debanding = true
		QUALITY_HIGH:
			viewport.scaling_3d_scale = 1.0
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			viewport.use_taa = forward_plus
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if viewport.use_taa else Viewport.SCREEN_SPACE_AA_FXAA
			viewport.use_debanding = true
		QUALITY_MEDIUM:
			viewport.scaling_3d_scale = 1.0
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			viewport.use_taa = forward_plus
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if viewport.use_taa else Viewport.SCREEN_SPACE_AA_FXAA
			viewport.use_debanding = false
		QUALITY_LOW, _:
			viewport.scaling_3d_scale = 0.85
			viewport.msaa_3d = Viewport.MSAA_DISABLED
			viewport.use_taa = false
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			viewport.use_debanding = false

	apply_rendering_server_config(q)

## Configures global RenderingServer shadow atlas resolution and soft shadow filtering.
static func apply_rendering_server_config(quality: String = QUALITY_ULTRA) -> void:
	var q := quality.to_lower()
	match q:
		QUALITY_ULTRA:
			# Directional shadow atlas 8192 for razor-sharp multi-split cascades
			RenderingServer.directional_shadow_atlas_set_size(8192, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
		QUALITY_HIGH:
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
		QUALITY_MEDIUM:
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
		QUALITY_LOW, _:
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)

## Sets ProjectSettings specifications for Forward+ renderer fidelity.
static func apply_project_settings(quality: String = QUALITY_ULTRA) -> void:
	var q := quality.to_lower()
	var shadow_size := 8192
	var soft_quality := 4 # Soft Ultra
	var aniso_level := 4  # 16x

	match q:
		QUALITY_ULTRA:
			shadow_size = 8192
			soft_quality = 4
			aniso_level = 4
		QUALITY_HIGH:
			shadow_size = 4096
			soft_quality = 3 # Soft High
			aniso_level = 4
		QUALITY_MEDIUM:
			shadow_size = 2048
			soft_quality = 2 # Soft Medium
			aniso_level = 2 # 4x
		QUALITY_LOW, _:
			shadow_size = 1024
			soft_quality = 1 # Soft Low
			aniso_level = 0

	ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", shadow_size)
	ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", soft_quality)
	ProjectSettings.set_setting("rendering/textures/default_filters/anisotropic_filtering_level", aniso_level)

## Configures the primary DirectionalLight3D with 4-split raking sun specs.
static func configure_sun(sun: DirectionalLight3D, quality: String = QUALITY_ULTRA) -> void:
	if sun == null:
		return

	# Raking afternoon sun elevation (~30 deg) side-lighting the mountain roadway
	sun.rotation = SUN_ROTATION
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	sun.light_indirect_energy = 1.0
	sun.light_specular = 1.0
	sun.light_angular_distance = SUN_ANGULAR_DISTANCE

	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = SUN_SHADOW_BIAS
	sun.shadow_normal_bias = SUN_SHADOW_NORMAL_BIAS
	sun.shadow_blur = SUN_SHADOW_BLUR

	sun.directional_shadow_max_distance = SUN_SHADOW_MAX_DISTANCE
	sun.directional_shadow_split_1 = SUN_SHADOW_SPLIT_1
	sun.directional_shadow_split_2 = SUN_SHADOW_SPLIT_2
	sun.directional_shadow_split_3 = SUN_SHADOW_SPLIT_3

## Retrieves the pre-baked Environment resource or creates one on the fly.
static func get_or_create_environment(quality: String = QUALITY_ULTRA) -> Environment:
	var env: Environment = null
	if ResourceLoader.exists(FORZA_ENV_PATH):
		env = ResourceLoader.load(FORZA_ENV_PATH) as Environment
		if env != null:
			env = env.duplicate() as Environment

	if env == null:
		env = build_environment(quality)
	else:
		configure_environment(env, quality)

	return env

## Fully constructs a new calibrated Environment resource.
static func build_environment(quality: String = QUALITY_ULTRA) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = build_sky()
	env.sky_rotation = Vector3(0.0, SKY_Y_ROTATION, 0.0)

	# Ambient lighting and Image-Based Lighting (IBL)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.85
	env.ambient_light_color = Color(0.76, 0.84, 0.94, 1.0)
	env.ambient_light_energy = 0.65
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# Filmic AgX tonemapping calibrated for golden hour / afternoon raking sun
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0

	# Depth haze fog over valley floor and distant mountain ridges
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.66, 0.77, 0.90, 1.0)
	env.fog_light_energy = 0.92
	env.fog_sun_scatter = 0.22
	env.fog_density = 0.00045
	env.fog_aerial_perspective = 1.0
	env.fog_sky_affect = 0.0
	env.fog_height = 24.0
	env.fog_height_density = 0.0014

	# Subtle contrast & saturation curve
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.01
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.07

	# Quality-dependent screen-space and GI effects
	configure_environment(env, quality)
	return env

## Updates quality-dependent properties on an Environment resource.
static func configure_environment(env: Environment, quality: String = QUALITY_ULTRA) -> void:
	if env == null:
		return

	var q := quality.to_lower()
	match q:
		QUALITY_ULTRA:
			# SSAO
			env.ssao_enabled = true
			env.ssao_radius = 1.5
			env.ssao_intensity = 1.3
			env.ssao_power = 1.5
			env.ssao_detail = 0.5
			env.ssao_sharpness = 0.98

			# SSIL
			env.ssil_enabled = true
			env.ssil_radius = 5.0
			env.ssil_intensity = 0.45
			env.ssil_sharpness = 0.98

			# SSR
			env.ssr_enabled = true
			env.ssr_max_steps = 64
			env.ssr_fade_in = 0.15
			env.ssr_fade_out = 2.0
			env.ssr_depth_tolerance = 0.2

			# Glow & Bloom
			env.glow_enabled = true
			env.glow_normalized = true
			env.glow_intensity = 0.26
			env.glow_strength = 0.85
			env.glow_bloom = 0.12
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.glow_hdr_threshold = 1.1
			env.glow_hdr_scale = 1.8

			# SDFGI disabled by default for smooth 60+ FPS real-time driving
			env.sdfgi_enabled = false
			env.sdfgi_cascades = 4
			env.sdfgi_min_cell_size = 0.2
			env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT
			env.sdfgi_use_occlusion = false

		QUALITY_HIGH:
			env.ssao_enabled = true
			env.ssao_radius = 1.3
			env.ssao_intensity = 1.1

			env.ssil_enabled = false

			env.ssr_enabled = false

			env.glow_enabled = true
			env.glow_normalized = true
			env.glow_intensity = 0.24
			env.glow_bloom = 0.10
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.glow_hdr_threshold = 1.15

			env.sdfgi_enabled = false

		QUALITY_MEDIUM:
			env.ssao_enabled = true
			env.ssao_radius = 1.2
			env.ssao_intensity = 1.0

			env.ssil_enabled = false
			env.ssr_enabled = false

			env.glow_enabled = true
			env.glow_normalized = true
			env.glow_intensity = 0.20
			env.glow_bloom = 0.08
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.glow_hdr_threshold = 1.2

			env.sdfgi_enabled = false

		QUALITY_LOW, _:
			env.ssao_enabled = false
			env.ssil_enabled = false
			env.ssr_enabled = false
			env.sdfgi_enabled = false

			env.glow_enabled = false

## Builds the Sky resource using the HDRI panorama with procedural fallback.
static func build_sky() -> Sky:
	var sky := Sky.new()
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	if ResourceLoader.exists(HDRI_SKY_PATH):
		var tex := ResourceLoader.load(HDRI_SKY_PATH) as Texture2D
		if tex != null:
			var pano := PanoramaSkyMaterial.new()
			pano.panorama = tex
			pano.filter = true
			pano.energy_multiplier = 1.0
			sky.sky_material = pano
			return sky

	# Fallback procedural sky
	var proc := ProceduralSkyMaterial.new()
	proc.sky_top_color = Color(0.24, 0.47, 0.78, 1.0)
	proc.sky_horizon_color = Color(0.76, 0.84, 0.92, 1.0)
	proc.sky_curve = 0.14
	proc.ground_bottom_color = Color(0.18, 0.22, 0.18, 1.0)
	proc.ground_horizon_color = Color(0.56, 0.63, 0.66, 1.0)
	proc.sun_angle_max = 28.0
	proc.sun_curve = 0.12
	sky.sky_material = proc
	return sky
