shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// =============================================================================
// Forza-Tier Weathered Alpine PBR Asphalt Corridor Shader
// =============================================================================
// Designed for seamless multi-kilometer road rendering in Godot 4.
// - PBR albedo, normal, roughness, ambient occlusion
// - Dual-octave world-space macro variation eliminating tile repetition
// - Dual wheel-track wearing along lane centers with realistic tire polish
// - Weathered off-white (#CFCFCF) and yellow markings with micro-noise chipping
// - Seamless verge/shoulder edge blend without harsh geometric razor edges
// =============================================================================

// --- Textures ---
uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_ao : filter_linear_mipmap_anisotropic, repeat_enable;

// --- UV Tiling & Geometry ---
uniform float road_uv_width : hint_range(0.1, 10.0) = 1.70; // 6.8m road width (half_width*2 / 4.0 = 1.70)
uniform float detail_tile_u : hint_range(0.1, 10.0) = 1.6;
uniform float detail_tile_v : hint_range(0.1, 10.0) = 2.6;
uniform float macro_tile_ratio : hint_range(0.1, 1.0) = 0.37;
uniform float normal_depth : hint_range(0.0, 3.0) = 0.55;

// --- Colors & Tints ---
uniform vec3 asphalt_tint : source_color = vec3(0.85, 0.86, 0.88);
uniform vec3 center_stripe_color : source_color = vec3(0.86, 0.65, 0.14); // Warm highway yellow
uniform vec3 edge_stripe_color : source_color = vec3(0.812, 0.812, 0.812); // #CFCFCF Weathered off-white
uniform vec3 verge_dirt_color : source_color = vec3(0.32, 0.28, 0.23); // Alpine verge dirt/gravel tone

// --- Macro Noise Variation (Breaking up tiling over km stretches) ---
uniform float macro_noise_scale_low : hint_range(0.005, 0.1) = 0.022;
uniform float macro_noise_scale_mid : hint_range(0.01, 0.3) = 0.075;
uniform float roughness_min : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_max : hint_range(0.0, 1.0) = 0.85;

// --- Wheel Track Wearing ---
uniform float wheel_track_darkening : hint_range(0.0, 0.5) = 0.18;
uniform float wheel_track_polish : hint_range(0.0, 0.3) = 0.09;
uniform float wheel_track_width : hint_range(0.01, 0.1) = 0.045;

// --- Lane Markings & Weathering ---
uniform float dash_cycle_length : hint_range(0.1, 5.0) = 1.0; // 8.0m cycle length (3.2m dash / 4.8m gap)
uniform float center_dash_ratio : hint_range(0.1, 0.9) = 0.40;
uniform float stripe_width : hint_range(0.002, 0.04) = 0.011;
uniform float edge_stripe_pos : hint_range(0.01, 0.2) = 0.055;
uniform float marking_wear_intensity : hint_range(0.0, 1.0) = 0.60;
uniform float marking_chipping_strength : hint_range(0.0, 1.0) = 0.50;

// --- Seamless Road-Verge Edge Blend ---
uniform float verge_blend_width : hint_range(0.01, 0.20) = 0.065;
uniform float verge_noise_scale : hint_range(0.05, 1.5) = 0.42;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

// Deterministic 2D hash for value noise
float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

// Smooth value noise
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

// World-space two-octave macro noise
float macro_two_octaves(vec2 p) {
	float o1 = value_noise(p * macro_noise_scale_low);
	float o2 = value_noise(p * macro_noise_scale_mid + vec2(19.3, 47.1));
	return mix(o1, o2, 0.42);
}

void fragment() {
	// Normalized 0..1 across the full two-lane pavement (0.0 = left edge, 0.5 = centerline, 1.0 = right edge).
	float across = clamp(UV.x / max(road_uv_width, 0.001), 0.0, 1.0);

	// Multi-scale detail & macro UV coordinates to break up repeating texture tiles over kilometers
	vec2 uv_det = UV2 * vec2(detail_tile_u, detail_tile_v);
	vec2 uv_mac = uv_det * macro_tile_ratio + vec2(0.371, 0.193);

	// World-space procedural variations
	float macro_var = macro_two_octaves(world_pos.xz);
	float fine_var = value_noise(world_pos.xz * 0.38);
	float micro_noise = value_noise(world_pos.xz * 3.4);
	float tar_patch = smoothstep(0.70, 0.88, value_noise(world_pos.xz * 0.11 + vec2(7.3, -4.9)));

	// PBR Base Texture Sampling (two-scale blend)
	vec3 base_tex_albedo = mix(
		texture(asphalt_albedo, uv_det).rgb,
		texture(asphalt_albedo, uv_mac).rgb,
		0.34
	) * asphalt_tint;

	float base_tex_roughness = mix(
		texture(asphalt_roughness, uv_det).r,
		texture(asphalt_roughness, uv_mac).r,
		0.30
	);
	float base_ao = texture(asphalt_ao, uv_det).r;
	vec3 tex_normal = texture(asphalt_normal, uv_det).rgb;

	// Macro tone variation across kilometer stretches
	vec3 col = base_tex_albedo * mix(0.88, 1.12, macro_var);
	// Subtle localized tar patch weathering
	col *= mix(1.0, 0.82, tar_patch * 0.35);

	// =========================================================================
	// Dual Wheel-Track Wearing along Lane Centers
	// =========================================================================
	// Two-lane highway: Lane 1 (0.0 to 0.5), Lane 2 (0.5 to 1.0)
	// Outer and inner tire tracks per lane
	float t_l1 = exp(-pow((across - 0.18) / wheel_track_width, 2.0));
	float t_l2 = exp(-pow((across - 0.35) / wheel_track_width, 2.0));
	float t_r1 = exp(-pow((across - 0.65) / wheel_track_width, 2.0));
	float t_r2 = exp(-pow((across - 0.82) / wheel_track_width, 2.0));
	float wheel_wear = clamp((t_l1 + t_l2 + t_r1 + t_r2) * 0.72, 0.0, 1.0);

	// Darken asphalt along traffic wheel paths (rubber build-up & bitumen burnish)
	col *= mix(1.0, 1.0 - wheel_track_darkening, wheel_wear);

	// =========================================================================
	// Weathered Lane Markings with Micro-Noise Chipping & Worn Patches
	// =========================================================================
	// Anti-aliased line width using screen-space derivatives to avoid distance shimmering
	float aa = max(fwidth(across) * 1.25, 0.0018);

	// Micro-noise edge chipping
	float chip_offset = (micro_noise - 0.5) * 0.0042 * marking_chipping_strength;

	// Dashed yellow center stripe
	float center_dist = abs(across - 0.5) + chip_offset;
	float center_band = 1.0 - smoothstep(stripe_width - aa, stripe_width + aa, center_dist);
	float dash_cycle = fract(UV.y * dash_cycle_length);
	float dash_mask = smoothstep(0.0, 0.03, dash_cycle) * (1.0 - smoothstep(center_dash_ratio - 0.03, center_dash_ratio, dash_cycle));
	float center_paint = center_band * dash_mask;

	// Solid off-white (#CFCFCF) outer edge stripes
	float left_dist = abs(across - edge_stripe_pos) + chip_offset;
	float right_dist = abs(across - (1.0 - edge_stripe_pos)) + chip_offset;
	float left_band = 1.0 - smoothstep(stripe_width * 0.85 - aa, stripe_width * 0.85 + aa, left_dist);
	float right_band = 1.0 - smoothstep(stripe_width * 0.85 - aa, stripe_width * 0.85 + aa, right_dist);
	float edge_paint = max(left_band, right_band);

	// Weathered paint wear (micro chipping and aggregate poking through)
	float wear_mask = clamp(smoothstep(0.25, 0.82, fine_var * 0.6 + micro_noise * 0.4) - (1.0 - base_ao) * 0.30, 0.12, 0.98);
	center_paint *= mix(1.0, wear_mask, marking_wear_intensity);
	edge_paint *= mix(1.0, wear_mask, marking_wear_intensity);

	// Blend road paint markings into surface albedo
	col = mix(col, center_stripe_color, center_paint);
	col = mix(col, edge_stripe_color, edge_paint * 0.96);

	// =========================================================================
	// Seamless Road-Verge / Shoulder Edge Blend
	// =========================================================================
	// UV x-distance falloff from both edges with organic noise modulation
	float edge_dist = min(across, 1.0 - across);
	float verge_noise = value_noise(world_pos.xz * verge_noise_scale) * 0.58 + value_noise(world_pos.xz * (verge_noise_scale * 3.2)) * 0.42;
	float modulated_verge_width = verge_blend_width * mix(0.65, 1.35, verge_noise);
	float verge_blend = 1.0 - smoothstep(0.0, modulated_verge_width, edge_dist);

	// Incorporate vertex color falloff if present on mesh vertices
	float vcolor_verge = (1.0 - COLOR.r) * COLOR.a;
	verge_blend = clamp(max(verge_blend, vcolor_verge), 0.0, 1.0);

	// Blend into gravel / dirt shoulder skirt color seamlessly
	col = mix(col, verge_dirt_color, verge_blend * 0.88);

	// =========================================================================
	// Roughness & Specular Modulation
	// =========================================================================
	// Macro noise breaks up roughness across the landscape between roughness_min (0.35) and roughness_max (0.85)
	float macro_rough = mix(roughness_min, roughness_max, macro_var);
	float rough = mix(base_tex_roughness, macro_rough, 0.52);

	// Wheel-track polish: traffic reduces roughness slightly for subtle sun-glint sheen
	rough -= wheel_wear * wheel_track_polish;

	// Paint markings: satin finish
	float any_paint = clamp(center_paint + edge_paint, 0.0, 1.0);
	rough = mix(rough, 0.46, any_paint * 0.65);

	// Verge edge: coarse aggregate dirt / gravel
	rough = mix(rough, 0.86, verge_blend * 0.75);

	// Strictly guarantee roughness bounds between 0.35 and 0.85
	rough = clamp(rough, roughness_min, roughness_max);

	// Distance normal map attenuation to avoid distant aliasing
	float cam_dist = length(VERTEX);
	float dist_normal_atten = mix(1.0, 0.22, smoothstep(18.0, 95.0, cam_dist));

	// Assign PBR outputs
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = mix(0.30, 0.39, wheel_wear * 0.65 + any_paint * 0.35);
	AO = mix(1.0, base_ao, 0.58);
	NORMAL_MAP = tex_normal;
	NORMAL_MAP_DEPTH = mix(normal_depth, normal_depth * 0.55, any_paint * 0.4 + verge_blend * 0.5) * dist_normal_atten;
}
