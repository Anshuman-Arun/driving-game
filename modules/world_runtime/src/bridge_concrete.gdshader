shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 concrete_color : source_color = vec3(0.49, 0.51, 0.51);
uniform bool footway = false;
varying vec3 world_point;
varying vec3 world_normal;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 xz = world_point.xz;
	float cast_tone = sin(dot(xz, vec2(1.19, 0.52))) * sin(dot(xz, vec2(-0.38, 1.61)));
	float runoff = smoothstep(0.13, 0.75, sin(dot(xz, vec2(3.93, 2.16)))) * (1.0 - abs(world_normal.y));
	float joints = 0.0;
	if (footway) {
		float station = (UV.x + 0.37) * 1.07;
		float edge = min(fract(station), 1.0 - fract(station));
		float aa = max(fwidth(station), 0.001);
		joints = 1.0 - smoothstep(0.006, 0.006 + aa, edge);
	}
	ALBEDO = concrete_color * (0.98 + cast_tone * 0.08 - runoff * 0.15 - joints * 0.48);
	ROUGHNESS = 0.88;
	SPECULAR = 0.23;
}
