shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

varying vec3 local_data;
varying vec2 source_uv;
uniform sampler2D leaf_pattern : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

void vertex() {
	local_data = VERTEX;
	source_uv = UV;
	vec2 anchor = MODEL_MATRIX[3].xz;
	float gust = sin(TIME * 1.55 + dot(anchor, vec2(0.13, 0.19)));
	float ripple = sin(TIME * 2.8 + dot(anchor, vec2(-0.42, 0.52)));
	float flex = UV.y * UV.y;
	VERTEX.xz += vec2(gust + ripple * 0.23, gust * 0.48 + ripple * 0.45) * flex * 0.16;
}

void fragment() {
	float fibers = sin(local_data.y * 47.0 + local_data.x * 59.0 + local_data.z * 21.0);
	float resolved = 1.0 - smoothstep(0.1, 2.2, fwidth(local_data.y) * 47.0);
	ALBEDO = COLOR.rgb * (0.96 + fibers * 0.055 * resolved);
	if (source_uv.x < -0.5 && source_uv.y > 0.15) {
		vec3 leaves = texture(leaf_pattern, local_data.xz * 1.15 + local_data.y * vec2(0.41, 0.71)).rgb;
		ALBEDO *= 0.78 + 0.64 * dot(leaves, vec3(0.23, 0.68, 0.09));
	}
	ROUGHNESS = 0.86;
	SPECULAR = 0.18;
	BACKLIGHT = ALBEDO * 0.18 * source_uv.y;
}
