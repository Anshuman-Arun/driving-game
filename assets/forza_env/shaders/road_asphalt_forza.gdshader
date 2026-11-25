shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Forza-tier weathered alpine asphalt corridor shader.
// mesh_builder.gd sets pavement UV.x from 0.0 to half_width*2/4.0 (1.70 for 6.8m road)
// and UV.y = cumulative_arc_length / 8.0.

uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_ao : filter_linear_mipmap_anisotropic, repeat_enable;

uniform float road_uv_width = 1.70;
uniform float detail_tile_u = 1.6;
uniform float detail_tile_v = 2.6;
uniform float normal_depth : hint_range(0.0, 2.0) = 0.45;

uniform vec3 asphalt_tint : source_color = vec3(1.26, 1.27, 1.29);
uniform vec3 center_stripe_color : source_color = vec3(0.86, 0.65, 0.14);
uniform vec3 edge_stripe_color : source_color = vec3(0.86, 0.87, 0.85);
uniform vec3 verge_dust_color : source_color = vec3(0.42, 0.40, 0.35);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

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

void fragment() {
	// Normalized 0..1 across the full two-lane pavement (0.5 = exact centerline).
	float across = clamp(UV.x / max(road_uv_width, 0.001), 0.0, 1.0);

	// Primary detail UV + secondary macro UV to break long-straight tiling.
	vec2 uv_det = vec2(UV.x * detail_tile_u, UV.y * detail_tile_v);
	vec2 uv_mac = vec2(UV.x * (detail_tile_u * 0.43) + 0.37, UV.y * (detail_tile_v * 0.43) + 0.19);

	float macro_var = value_noise(world_pos.xz * 0.065);
	float fine_var = value_noise(world_pos.xz * 0.32);
	float tar_patch = smoothstep(0.68, 0.86, value_noise(world_pos.xz * 0.14 + vec2(4.2, -2.7)));

	vec3 base_col = mix(
		texture(asphalt_albedo, uv_det).rgb,
		texture(asphalt_albedo, uv_mac).rgb,
		0.32
	) * asphalt_tint;

	float base_rgh = mix(
		texture(asphalt_roughness, uv_det).r,
		texture(asphalt_roughness, uv_mac).r,
		0.28
	);
	float base_ao = texture(asphalt_ao, uv_det).r;
	vec3 tex_n = texture(asphalt_normal, uv_det).rgb;

	// Dual lane tire-wear tracks (two wheel tracks per lane).
	float track_l = exp(-pow((across - 0.19) * 18.0, 2.0)) + exp(-pow((across - 0.34) * 18.0, 2.0));
	float track_r = exp(-pow((across - 0.66) * 18.0, 2.0)) + exp(-pow((across - 0.81) * 18.0, 2.0));
	float tire_wear = clamp((track_l + track_r) * 0.68, 0.0, 1.0);

	// Weathering, subtle darkened rubber tire tracks, and mild repair variation.
	vec3 col = base_col * mix(0.92, 1.07, macro_var);
	col *= mix(1.0, 0.90, tire_wear * 0.55);
	col *= mix(1.0, 0.90, tar_patch * 0.28);

	// Subtle dusty-gravel edge transition where asphalt meets the verge.
	float edge_dist = min(across, 1.0 - across);
	float edge_dust = (1.0 - smoothstep(0.0, 0.035, edge_dist)) * (0.45 + 0.55 * fine_var);
	col = mix(col, verge_dust_color, edge_dust * 0.36);

	// --- Crisp Highway Road Markings ---
	// Anti-aliased width using screen-space derivative so lines stay sharp without shimmer.
	float aa = max(fwidth(across) * 1.15, 0.0022);

	// Dashed yellow center stripe (UV.y is 8m per unit -> 3.2m dash, 4.8m gap).
	float center_dist = abs(across - 0.5);
	float center_band = 1.0 - smoothstep(0.011 - aa, 0.011 + aa, center_dist);
	float dash_cycle = fract(UV.y * 1.0);
	float dash_mask = smoothstep(0.0, 0.025, dash_cycle) * (1.0 - smoothstep(0.40, 0.425, dash_cycle));
	float center_paint = center_band * dash_mask;

	// Solid white outer edge lines at across = 0.055 and across = 0.945.
	float left_edge_line = 1.0 - smoothstep(0.0095 - aa, 0.0095 + aa, abs(across - 0.055));
	float right_edge_line = 1.0 - smoothstep(0.0095 - aa, 0.0095 + aa, abs(across - 0.945));
	float edge_paint = max(left_edge_line, right_edge_line);

	// Natural paint wear so asphalt aggregate subtly pokes through.
	float paint_wear = clamp(0.78 + 0.24 * fine_var - (1.0 - base_ao) * 0.22, 0.45, 0.96);
	col = mix(col, center_stripe_color, center_paint * paint_wear);
	col = mix(col, edge_stripe_color, edge_paint * paint_wear * 0.92);

	// Roughness: tire tracks slightly polished for subtle sun-glint sheen;
	// paint slightly satin; edges slightly dustier/rougher.
	float any_paint = clamp(center_paint + edge_paint, 0.0, 1.0);
	float rough = base_rgh * 0.68 + 0.24;
	rough -= tire_wear * 0.09;
	rough += edge_dust * 0.14;
	rough = mix(rough, 0.48, any_paint * 0.65);
	// Subtle damp micro-specular sheen variation.
	rough -= smoothstep(0.55, 0.85, macro_var) * 0.05;

	float cam_dist = length(VERTEX);
	float dist_n = mix(1.0, 0.22, smoothstep(16.0, 90.0, cam_dist));
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.36, 0.96);
	METALLIC = 0.0;
	SPECULAR = mix(0.42, 0.56, tire_wear * 0.6 + any_paint * 0.4);
	AO = mix(1.0, base_ao, 0.55);
	NORMAL_MAP = tex_n;
	NORMAL_MAP_DEPTH = mix(normal_depth, normal_depth * 0.55, any_paint * 0.5) * dist_n;
}
