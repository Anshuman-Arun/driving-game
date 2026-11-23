shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Clean weathered asphalt shader for intersection junction pads (NO center/edge stripes).
// Color and roughness match road_asphalt_forza.gdshader seamlessly.

uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_ao : filter_linear_mipmap_anisotropic, repeat_enable;

uniform float world_tile_scale = 0.34;
uniform float normal_depth : hint_range(0.0, 2.0) = 0.45;
uniform vec3 asphalt_tint : source_color = vec3(0.84, 0.85, 0.87);

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
	vec2 uv_det = world_pos.xz * world_tile_scale;
	mat2 rot = mat2(vec2(0.815, -0.579), vec2(0.579, 0.815));
	vec2 uv_mac = (rot * world_pos.xz) * (world_tile_scale * 0.43) + vec2(0.37, 0.19);

	float macro_var = value_noise(world_pos.xz * 0.065);
	float tar_patch = smoothstep(0.68, 0.86, value_noise(world_pos.xz * 0.14 + vec2(4.2, -2.7)));
	float scuff = smoothstep(0.38, 0.72, value_noise(world_pos.xz * 0.11 + vec2(-3.1, 5.4)));

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

	vec3 col = base_col * mix(0.88, 1.10, macro_var);
	col *= mix(1.0, 0.88, scuff * 0.45);
	col *= mix(1.0, 0.78, tar_patch * 0.35);

	float rough = base_rgh * 0.68 + 0.24 - scuff * 0.05;
	rough -= smoothstep(0.55, 0.85, macro_var) * 0.05;

	float cam_dist = length(VERTEX);
	float dist_n = mix(1.0, 0.22, smoothstep(16.0, 90.0, cam_dist));
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.38, 0.96);
	METALLIC = 0.0;
	SPECULAR = 0.44;
	AO = mix(1.0, base_ao, 0.55);
	NORMAL_MAP = tex_n;
	NORMAL_MAP_DEPTH = normal_depth * dist_n;
}
