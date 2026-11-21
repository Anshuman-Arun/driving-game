shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 color_a : source_color = vec3(0.075, 0.175, 0.072);
uniform vec3 color_b : source_color = vec3(0.135, 0.235, 0.095);
uniform vec3 backlight_tint : source_color = vec3(0.32, 0.42, 0.16);
uniform float wind_strength = 0.07;
uniform float wind_speed = 1.25;

varying vec4 v_custom;
varying float v_tip_t;
varying vec3 v_world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_tip_t = clamp(UV.y, 0.0, 1.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_pos = wp;

	float sway = sin(wp.x * 0.11 + wp.z * 0.09 + TIME * wind_speed + v_custom.y * 6.28);
	float amp = wind_strength * v_tip_t * clamp(VERTEX.y * 0.14, 0.0, 1.8);
	VERTEX.x += sway * amp;
	VERTEX.z += sway * amp * 0.6;
}

void fragment() {
	float organic = vnoise(v_world_pos.xz * 1.4 + vec2(v_world_pos.y * 0.9, -v_world_pos.y * 0.6));
	vec3 col = mix(color_a, color_b, v_custom.x);
	col *= mix(0.70, 1.18, smoothstep(0.0, 1.0, v_tip_t));
	col *= (0.88 + 0.24 * organic);

	ALBEDO = col;
	AO = mix(0.62, 1.0, v_tip_t);
	ROUGHNESS = 0.76;
	METALLIC = 0.0;
	SPECULAR = 0.20;
	BACKLIGHT = backlight_tint * (0.34 + 0.36 * v_tip_t);
}
