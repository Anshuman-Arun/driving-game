shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec2 p = UV;
	float sweep = smoothstep(0.0, 1.0, p.x + p.y * 0.45);
	vec3 ink = mix(vec3(0.035, 0.16, 0.17), vec3(0.09, 0.085, 0.20), sweep);
	float glow = exp(-4.5 * length((p - vec2(0.09, 0.23)) * vec2(1.0, 1.45)));
	ink += glow * vec3(0.04, 0.31, 0.26);
	float light = exp(-5.0 * length(p - vec2(0.95, 0.75)));
	ink += light * vec3(0.28, 0.085, 0.24);
	float line = abs(fract((p.x + 0.43 * p.y) * 17.0) - 0.5);
	ink += (1.0 - smoothstep(0.008, 0.028, line)) * vec3(0.05, 0.075, 0.08);
	COLOR = vec4(ink, 1.0);
}
