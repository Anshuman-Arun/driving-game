shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D canopy : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D bark : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wind = 0.20;
uniform bool meadow = false;
varying vec3 local_position;
varying float terrain_height;
varying vec3 crown_normal;

void vertex() {
	local_position = VERTEX;
	terrain_height = MODEL_MATRIX[3].y;
	crown_normal = MODELVIEW_NORMAL_MATRIX * normalize(vec3(VERTEX.x, 0.72, VERTEX.z));
	float phase = dot(MODEL_MATRIX[3].xz, vec2(0.18, 0.12));
	float gust = sin(TIME * 1.95 + phase) + sin(TIME * 3.1 - phase * 1.71) * 0.26;
	float flex = COLOR.a;
	VERTEX.xz += vec2(gust, gust * 0.42) * wind * flex * flex;
}

void fragment() {
	vec4 texel = texture(canopy, UV);
	vec3 tint = COLOR.rgb;
	if (meadow && UV.x < 0.0) {
		texel = vec4(mix(vec3(0.13, 0.17, 0.044), vec3(0.39, 0.42, 0.15), UV.y), 1.0);
	} else if (UV.x < 0.0) {
		float around = atan(local_position.z, local_position.x) / TAU;
		vec3 wood = texture(bark, vec2(around, local_position.y * 0.58)).rgb;
		texel = vec4(mix(vec3(0.19, 0.16, 0.12), wood, 0.76), 1.0);
		tint = vec3(0.65 + dot(tint, vec3(0.25, 0.60, 0.15)) * 0.25);
	}
	ALBEDO = pow(texel.rgb, vec3(meadow ? 0.83 : 0.88)) * tint;
	if (meadow) {
		vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		NORMAL = normalize(mix(NORMAL, up, 0.76));
		ALBEDO *= mix(vec3(0.78, 0.98, 0.73), vec3(1.02, 0.92, 0.77), smoothstep(48.0, 106.0, terrain_height));
	} else if (UV.x >= 0.0) {
		NORMAL = normalize(mix(NORMAL, crown_normal, 0.58));
	}
	ALPHA = texel.a;
	float distance_blend = smoothstep(11.0, 130.0, length(VERTEX));
	ALPHA_SCISSOR_THRESHOLD = meadow ? mix(0.43, 0.36, distance_blend) : mix(0.41, 0.24, distance_blend);
	ROUGHNESS = 0.92;
	SPECULAR = 0.11;
	BACKLIGHT = ALBEDO * (meadow ? 0.13 : 0.28);
}
