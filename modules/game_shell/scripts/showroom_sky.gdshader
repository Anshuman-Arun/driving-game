shader_type sky;

float softbox(vec3 ray, vec3 direction, float width, float height) {
	vec3 center = normalize(direction);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), center));
	vec3 up = cross(center, right);
	vec2 offset = abs(vec2(dot(ray, right), dot(ray, up)));
	vec2 size = vec2(width, height);
	vec2 edge = smoothstep(size * 0.64, size, offset);
	return (1.0 - edge.x) * (1.0 - edge.y) * smoothstep(0.15, 0.72, dot(ray, center));
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		vec3 base = mix(vec3(0.035, 0.045, 0.060), vec3(0.19, 0.22, 0.28), smoothstep(-0.15, 0.9, EYEDIR.y));
		float key = softbox(EYEDIR, vec3(-0.6, 0.86, 0.45), 0.83, 0.26);
		float rim = softbox(EYEDIR, vec3(0.58, 0.65, -0.65), 0.76, 0.17);
		float fill = softbox(EYEDIR, vec3(0.72, 0.42, 0.7), 0.43, 0.28);
		COLOR = base + key * vec3(1.8, 1.68, 1.51) + rim * vec3(0.84, 1.20, 1.70) + fill * vec3(0.6, 0.68, 0.83);
	} else {
		float glow = 1.0 - smoothstep(0.0, 0.83, length((SCREEN_UV - vec2(0.64, 0.63)) * vec2(1.0, 0.84)));
		COLOR = mix(vec3(0.014, 0.026, 0.044), vec3(0.073, 0.101, 0.140), glow);
	}
}
