shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Natural road verge shader: blends subtle crushed earth/gravel right beside the pavement
// seamlessly into the world-space terrain turf & forest floor to eliminate hard shoulder seams.

uniform sampler2D shoulder_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shoulder_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shoulder_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shoulder_ao : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float grass_scale = 0.22;
uniform float normal_depth : hint_range(0.0, 2.0) = 0.48;
uniform vec3 shoulder_tint : source_color = vec3(0.82, 0.80, 0.74);
uniform vec3 grass_tint : source_color = vec3(0.60, 0.72, 0.54);

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
	vec2 xz = world_pos.xz;
	vec2 uv_det = xz * 0.45;
	mat2 rot = mat2(vec2(0.815, -0.579), vec2(0.579, 0.815));
	vec2 uv_mac = (rot * xz) * 0.19 + vec2(0.41, 0.29);

	float macro_var = value_noise(xz * 0.055);
	float fields = value_noise(xz * 0.011 + vec2(12.0, 33.0));
	float tuft_noise = value_noise(xz * 0.42);
	float clump_noise = value_noise(xz * 1.15);

	vec3 soil_col = mix(
		texture(shoulder_albedo, uv_det).rgb,
		texture(shoulder_albedo, uv_mac).rgb,
		0.35
	) * shoulder_tint;

	// Sample terrain grass in identical world-space coordinates & dual-scale anti-tiling as terrain_forza.
	vec2 g_uv_a = xz * grass_scale;
	vec2 g_uv_b = (rot * xz) * (grass_scale * 0.37) + vec2(0.31, 0.67);
	vec3 meadow_tone = mix(vec3(0.86, 0.92, 0.84), vec3(1.06, 1.02, 0.88), smoothstep(0.24, 0.79, fields));
	vec3 grass_col = mix(texture(grass_albedo, g_uv_a).rgb, texture(grass_albedo, g_uv_b).rgb, 0.45) * grass_tint * meadow_tone;

	// Heavy organic grass encroachment (68-92%) so shoulder looks like natural overgrown verge, not a brown stripe.
	float turf_w = clamp(0.58 + tuft_noise * 0.34 + clump_noise * 0.14, 0.45, 0.94);
	vec3 col = mix(soil_col, grass_col, turf_w);
	col *= mix(0.86, 1.11, value_noise(xz * 0.0028));

	float base_rgh = mix(
		texture(shoulder_roughness, uv_det).r,
		texture(shoulder_roughness, uv_mac).r,
		0.35
	);
	float base_ao = texture(shoulder_ao, uv_det).r;
	vec3 tex_n = mix(texture(shoulder_normal, uv_det).rgb, texture(grass_normal, g_uv_a).rgb, turf_w);

	float cam_dist = length(VERTEX);
	float dist_n = mix(1.0, 0.22, smoothstep(16.0, 90.0, cam_dist));
	ALBEDO = col;
	ROUGHNESS = clamp(base_rgh * 0.65 + 0.30, 0.60, 0.98);
	METALLIC = 0.0;
	SPECULAR = 0.28;
	AO = mix(1.0, base_ao, 0.40);
	NORMAL_MAP = tex_n;
	NORMAL_MAP_DEPTH = normal_depth * dist_n;
}
