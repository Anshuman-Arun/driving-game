shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Mountain gravel & packed dirt road shader with dual tire ruts and anti-tiling.

uniform sampler2D gravel_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_ao : filter_linear_mipmap_anisotropic, repeat_enable;

uniform float road_uv_width = 1.70;
uniform float detail_tile_u = 1.8;
uniform float detail_tile_v = 2.8;
uniform float normal_depth : hint_range(0.0, 2.0) = 0.62;

uniform vec3 gravel_tint : source_color = vec3(0.66, 0.63, 0.58);
uniform vec3 rut_tint : source_color = vec3(0.68, 0.65, 0.60);
uniform vec3 edge_berm_color : source_color = vec3(0.32, 0.34, 0.22);

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
	float across = clamp(UV.x / max(road_uv_width, 0.001), 0.0, 1.0);

	vec2 uv_det = vec2(UV.x * detail_tile_u, UV.y * detail_tile_v);
	vec2 uv_mac = vec2(UV.x * (detail_tile_u * 0.41) + 0.23, UV.y * (detail_tile_v * 0.41) + 0.57);

	float macro_var = value_noise(world_pos.xz * 0.055);
	float fine_var = value_noise(world_pos.xz * 0.26);

	vec3 raw_col = mix(
		texture(gravel_albedo, uv_det).rgb,
		texture(gravel_albedo, uv_mac).rgb,
		0.32
	);
	float base_rgh = mix(
		texture(gravel_roughness, uv_det).r,
		texture(gravel_roughness, uv_mac).r,
		0.30
	);
	float base_ao = texture(gravel_ao, uv_det).r;
	vec3 tex_n = texture(gravel_normal, uv_det).rgb;

	// Desaturate warm sand toward natural crushed alpine mountain stone & boost pebble contrast.
	float lum = dot(raw_col, vec3(0.299, 0.587, 0.114));
	vec3 stone_col = mix(vec3(lum), raw_col, 0.42) * gravel_tint;
	float pebble_contrast = mix(0.76, 1.22, clamp(base_ao * 1.15, 0.0, 1.0));
	vec3 base_col = stone_col * pebble_contrast;

	// Compacted dual tire ruts along the gravel mountain track + lighter loose center crown.
	float rut_l = exp(-pow((across - 0.26) * 14.0, 2.0));
	float rut_r = exp(-pow((across - 0.74) * 14.0, 2.0));
	float ruts = clamp((rut_l + rut_r) * 0.85, 0.0, 1.0);
	float center_crown = exp(-pow((across - 0.50) * 11.0, 2.0));

	// Loose earthy/grassy verge along road edges.
	float edge_dist = min(across, 1.0 - across);
	float edge_berm = (1.0 - smoothstep(0.0, 0.10, edge_dist)) * (0.55 + 0.45 * fine_var);

	vec3 col = base_col * mix(0.84, 1.14, macro_var);
	col = mix(col, col * rut_tint, ruts * 0.58);
	col *= mix(1.0, 1.10, center_crown * (0.5 + 0.5 * fine_var));
	col = mix(col, edge_berm_color, edge_berm * 0.48);

	float cam_dist = length(VERTEX);
	float dist_n = mix(1.0, 0.22, smoothstep(16.0, 90.0, cam_dist));
	ALBEDO = col;
	ROUGHNESS = clamp(base_rgh * 0.65 + 0.30 - ruts * 0.06, 0.55, 0.98);
	METALLIC = 0.0;
	SPECULAR = 0.28;
	AO = mix(1.0, base_ao, 0.6);
	NORMAL_MAP = tex_n;
	NORMAL_MAP_DEPTH = mix(normal_depth, normal_depth * 0.75, ruts * 0.4) * dist_n;
}
