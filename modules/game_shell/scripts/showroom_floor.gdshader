shader_type spatial;
render_mode unshaded, shadows_disabled;

varying vec3 studio_position;

void vertex() {
	studio_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float glow = 1.0 - smoothstep(0.0, 0.83, length((SCREEN_UV - vec2(0.64, 0.63)) * vec2(1.0, 0.84)));
	vec3 backdrop = mix(vec3(0.014, 0.026, 0.044), vec3(0.073, 0.101, 0.140), glow);
	float ground = 1.0 - smoothstep(3.0, 13.0, length(studio_position.xz));
	ALBEDO = mix(backdrop, vec3(0.045, 0.068, 0.086), ground);
}
