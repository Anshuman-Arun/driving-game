class_name GraphicsPresets
extends RefCounted

## Manages the 3 rendering tiers (Performance, Balanced, High),
## individual runtime feature toggles, and time-of-day lighting presets.

enum Tier { PERFORMANCE = 0, BALANCED = 1, HIGH = 2 }
enum TimeOfDay { GOLDEN_HOUR = 0, ALPINE_NOON = 1, BLUE_DUSK = 2 }

const TIER_NAMES: Array[String] = ["Performance", "Balanced", "High"]
const TOD_NAMES: Array[String] = ["Golden Hour", "Alpine Noon", "Blue Dusk"]

var current_tier: int = Tier.BALANCED
var current_tod: int = TimeOfDay.GOLDEN_HOUR

# Active feature state (can be toggled individually at runtime)
var state: Dictionary = {
	"ssao": true,
	"ssil": false,
	"ssr": true,
	"sdfgi": false,
	"volumetric_fog": false,
	"glow": true,
	"taa": true,
	"msaa_mode": Viewport.MSAA_2X,
	"shadow_distance": 220.0,
	"shadow_splits": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
	"grass_ratio": 0.60,
}


func get_tier_config(tier: int) -> Dictionary:
	match tier:
		Tier.PERFORMANCE:
			return {
				"ssao": false,
				"ssil": false,
				"ssr": false,
				"sdfgi": false,
				"volumetric_fog": false,
				"glow": true,
				"taa": false,
				"msaa_mode": Viewport.MSAA_2X,
				"shadow_distance": 120.0,
				"shadow_splits": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
				"grass_ratio": 0.25,
			}
		Tier.HIGH:
			return {
				"ssao": true,
				"ssil": true,
				"ssr": true,
				"sdfgi": true,
				"volumetric_fog": true,
				"glow": true,
				"taa": true,
				"msaa_mode": Viewport.MSAA_4X,
				"shadow_distance": 320.0,
				"shadow_splits": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
				"grass_ratio": 1.0,
			}
		_:
			# BALANCED (default target for ~60+ FPS at 1080p on midrange laptop GPU)
			return {
				"ssao": true,
				"ssil": false,
				"ssr": true,
				"sdfgi": false,
				"volumetric_fog": false,
				"glow": true,
				"taa": true,
				"msaa_mode": Viewport.MSAA_2X,
				"shadow_distance": 220.0,
				"shadow_splits": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
				"grass_ratio": 0.60,
			}


func parse_tier_name(name_str: String) -> int:
	var low: String = name_str.strip_edges().to_lower()
	if low == "performance" or low == "low":
		return Tier.PERFORMANCE
	if low == "high" or low == "ultra":
		return Tier.HIGH
	return Tier.BALANCED


func apply_tier(
	tier: int,
	env: Environment,
	sun: DirectionalLight3D,
	viewport: Viewport,
	grass_mmi: MultiMeshInstance3D
) -> void:
	current_tier = tier
	state = get_tier_config(tier)
	apply_state(env, sun, viewport, grass_mmi)


func apply_state(
	env: Environment,
	sun: DirectionalLight3D,
	viewport: Viewport,
	grass_mmi: MultiMeshInstance3D
) -> void:
	if viewport != null:
		viewport.msaa_3d = state["msaa_mode"]
		viewport.use_taa = state["taa"]

	if sun != null:
		sun.directional_shadow_mode = state["shadow_splits"]
		sun.directional_shadow_max_distance = state["shadow_distance"]
		sun.directional_shadow_blend_splits = (state["shadow_splits"] == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)

	if env != null:
		env.ssao_enabled = state["ssao"]
		env.ssao_radius = 1.6
		env.ssao_intensity = 1.35

		env.ssil_enabled = state["ssil"]
		env.ssil_radius = 4.5
		env.ssil_intensity = 0.85

		env.ssr_enabled = state["ssr"]
		env.ssr_max_steps = 64 if current_tier == Tier.HIGH else 32
		env.ssr_fade_in = 0.15
		env.ssr_fade_out = 1.8
		env.ssr_depth_tolerance = 0.25

		env.sdfgi_enabled = state["sdfgi"]
		env.sdfgi_use_occlusion = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.6
		env.sdfgi_bounce_feedback = 0.45

		env.volumetric_fog_enabled = state["volumetric_fog"]
		env.volumetric_fog_density = 0.0038
		env.volumetric_fog_albedo = Color(0.88, 0.85, 0.80)
		env.volumetric_fog_anisotropy = 0.62
		env.volumetric_fog_length = 220.0
		env.volumetric_fog_sky_affect = 0.25

		env.glow_enabled = state["glow"]
		env.glow_intensity = 0.35
		env.glow_strength = 0.68
		env.glow_bloom = 0.08
		env.glow_hdr_threshold = 1.15

	if grass_mmi != null and grass_mmi.multimesh != null:
		var total: int = grass_mmi.multimesh.instance_count
		grass_mmi.multimesh.visible_instance_count = int(round(float(total) * float(state["grass_ratio"])))


func apply_time_of_day(tod: int, env: Environment, sun: DirectionalLight3D) -> void:
	current_tod = tod
	if env == null or sun == null:
		return

	var sky_mat := env.sky.sky_material as PhysicalSkyMaterial
	match tod:
		TimeOfDay.ALPINE_NOON:
			sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
			sun.light_color = Color(1.0, 0.97, 0.92)
			sun.light_energy = 2.4
			env.ambient_light_sky_contribution = 0.85
			env.ambient_light_energy = 0.95
			env.fog_light_color = Color(0.72, 0.82, 0.93)
			env.fog_density = 0.00055
			env.fog_aerial_perspective = 0.58
			if sky_mat != null:
				sky_mat.turbidity = 4.2
				sky_mat.rayleigh_coefficient = 1.8
				sky_mat.mie_coefficient = 0.004
				sky_mat.energy_multiplier = 1.15
		TimeOfDay.BLUE_DUSK:
			sun.rotation_degrees = Vector3(-7.5, -118.0, 0.0)
			sun.light_color = Color(1.0, 0.58, 0.34)
			sun.light_energy = 1.45
			env.ambient_light_sky_contribution = 0.9
			env.ambient_light_energy = 0.72
			env.fog_light_color = Color(0.46, 0.52, 0.66)
			env.fog_density = 0.0011
			env.fog_aerial_perspective = 0.72
			if sky_mat != null:
				sky_mat.turbidity = 7.5
				sky_mat.rayleigh_coefficient = 2.4
				sky_mat.mie_coefficient = 0.011
				sky_mat.energy_multiplier = 0.85
		_:
			# GOLDEN_HOUR (default signature Aster Valley late-afternoon sun)
			# Raking warm late-afternoon light illuminating the asphalt curve, coupe, lakeside trees & water
			sun.rotation_degrees = Vector3(-22.5, -48.0, 0.0)
			sun.light_color = Color(1.0, 0.87, 0.68)
			sun.light_energy = 2.75
			env.ambient_light_sky_contribution = 0.90
			env.ambient_light_energy = 1.18
			env.fog_light_color = Color(0.84, 0.80, 0.74)
			env.fog_density = 0.00062
			env.fog_aerial_perspective = 0.68
			if sky_mat != null:
				sky_mat.turbidity = 4.8
				sky_mat.rayleigh_coefficient = 2.0
				sky_mat.mie_coefficient = 0.0065
				sky_mat.energy_multiplier = 1.12
