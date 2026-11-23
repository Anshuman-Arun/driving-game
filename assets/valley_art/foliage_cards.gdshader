shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D canopy : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D bark : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wind = 0.20;
uniform bool meadow = false;
varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
	float phase = dot(MODEL_MATRIX[3].xz, vec2(0.18, 0.12));
	float gust = sin(TIME * 1.95 + phase) + sin(TIME * 3.1 - phase * 1.71) * 0.26;
	float flex = COLOR.a;
	VERTEX.xz += vec2(gust, gust * 0.42) * wind * flex * flex;
}

void fragment() {
	vec4 texel = texture(canopy, UV);
	if (UV.x < 0.0) {
		float around = atan(local_position.z, local_position.x) / TAU;
		vec3 wood = texture(bark, vec2(around, local_position.y * 0.58)).rgb;
		texel = vec4(mix(vec3(0.68), wood * 1.75, 0.56), 1.0);
	}
	ALBEDO = pow(texel.rgb, vec3(meadow ? 0.68 : 0.83)) * COLOR.rgb;
	if (meadow) {
		vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		NORMAL = normalize(mix(NORMAL, up, 0.76));
		EMISSION = ALBEDO * 0.028;
	}
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = mix(0.41, 0.20, smoothstep(11.0, 130.0, length(VERTEX)));
	ROUGHNESS = 0.92;
	SPECULAR = 0.11;
	BACKLIGHT = ALBEDO * 0.18;
}
