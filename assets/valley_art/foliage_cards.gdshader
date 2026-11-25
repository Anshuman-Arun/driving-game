shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D canopy : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D bark : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wind = 0.20;
uniform bool meadow = false;
varying vec3 local_position;
varying float terrain_height;
varying vec3 crown_normal;
varying float v_flex;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void vertex() {
	local_position = VERTEX;
	terrain_height = MODEL_MATRIX[3].y;
	crown_normal = normalize(MODELVIEW_NORMAL_MATRIX * normalize(vec3(VERTEX.x, max(VERTEX.y * 0.45, 0.72), VERTEX.z)));
	vec2 world_xz = MODEL_MATRIX[3].xz;
	float inst_phase = hash21(world_xz);
	float wave = dot(world_xz, vec2(0.84, 0.54)) * 0.055 + inst_phase * 6.28318;
	float gust_env = 0.65 + 0.35 * sin(TIME * 0.45 + dot(world_xz, vec2(0.021, -0.017)));
	float gust = (sin(TIME * 1.65 + wave) + sin(TIME * 2.85 - wave * 1.41) * 0.32) * gust_env;
	float flex = clamp(COLOR.a, 0.0, 1.0);
	v_flex = flex;
	vec3 world_disp = vec3(0.84 * gust, 0.0, 0.54 * gust) * (wind * flex * flex);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * world_disp;
}

void fragment() {
	vec4 texel = texture(canopy, UV);
	vec3 tint = COLOR.rgb;
	if (meadow && UV.x < 0.0) {
		texel = vec4(mix(vec3(0.14, 0.16, 0.08), vec3(0.32, 0.34, 0.16), UV.y), 1.0);
	} else if (UV.x < 0.0) {
		float around = atan(local_position.z, local_position.x) / TAU;
		vec3 wood = texture(bark, vec2(around, local_position.y * 0.58)).rgb;
		texel = vec4(mix(vec3(0.45, 0.40, 0.34), wood, 0.72), 1.0);
		tint = vec3(0.65 + dot(tint, vec3(0.25, 0.60, 0.15)) * 0.25);
	}
	float root_ao = mix(0.72, 1.0, smoothstep(0.0, 0.35, v_flex));
	ALBEDO = pow(texel.rgb, vec3(meadow ? 0.88 : 0.90)) * tint * root_ao;
	if (meadow) {
		vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		NORMAL = normalize(mix(NORMAL, up, 0.72));
		ALBEDO *= mix(vec3(1.0), vec3(1.10, 0.90, 0.72), smoothstep(48.0, 106.0, terrain_height));
	} else if (UV.x >= 0.0) {
		NORMAL = normalize(mix(NORMAL, crown_normal, 0.60));
	}
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = mix(0.42, 0.22, smoothstep(12.0, 110.0, length(VERTEX)));
	ROUGHNESS = 0.88;
	SPECULAR = 0.14;
	BACKLIGHT = ALBEDO * (meadow ? 0.20 : 0.30);
}
