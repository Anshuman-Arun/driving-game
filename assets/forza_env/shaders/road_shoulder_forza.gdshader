shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Packed dirt / earth road verge shader with organic grass blending and anti-tiling.

uniform sampler2D shoulder_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shoulder_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shoulder_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shoulder_ao : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float world_tile_scale = 0.32;
uniform float normal_depth : hint_range(0.0, 2.0) = 0.50;
uniform vec3 shoulder_tint : source_color = vec3(0.74, 0.70, 0.62);
uniform vec3 grass_tint : source_color = vec3(0.46, 0.68, 0.36);

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
	vec2 uv_det = UV * 1.6;
	vec2 uv_mac = UV * 0.65 + vec2(0.41, 0.29);

	float macro_var = value_noise(world_pos.xz * 0.06);
	float tuft_mask = smoothstep(0.42, 0.78, value_noise(world_pos.xz * 0.38));

	vec3 dirt_col = mix(
		texture(shoulder_albedo, uv_det).rgb,
		texture(shoulder_albedo, uv_mac).rgb,
		0.32
	) * shoulder_tint;

	vec3 grass_col = texture(grass_albedo, world_pos.xz * 0.14).rgb * grass_tint;

	float base_rgh = mix(
		texture(shoulder_roughness, uv_det).r,
		texture(shoulder_roughness, uv_mac).r,
		0.30
	);
	float base_ao = texture(shoulder_ao, uv_det).r;
	vec3 tex_n = texture(shoulder_normal, uv_det).rgb;

	vec3 col = mix(dirt_col, grass_col, tuft_mask * 0.42);
	col *= mix(0.88, 1.10, macro_var);

	float cam_dist = length(VERTEX);
	float dist_n = mix(1.0, 0.22, smoothstep(16.0, 90.0, cam_dist));
	ALBEDO = col;
	ROUGHNESS = clamp(base_rgh * 0.65 + 0.30, 0.58, 0.98);
	METALLIC = 0.0;
	SPECULAR = 0.28;
	AO = mix(1.0, base_ao, 0.55);
	NORMAL_MAP = tex_n;
	NORMAL_MAP_DEPTH = normal_depth * dist_n;
}
