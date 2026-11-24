shader_type canvas_item;
render_mode unshaded;

uniform sampler2D roads : filter_linear_mipmap, repeat_disable;
uniform vec2 map_center = vec2(0.19, 0.78);
uniform float heading;
uniform float map_span = 0.182;

void fragment() {
	vec2 local = UV - vec2(0.5);
	float radius = length(local);
	float pixel = max(fwidth(radius), 0.001);
	float mask = 1.0 - smoothstep(0.50 - pixel, 0.50, radius);
	float c = cos(heading);
	float s = sin(heading);
	vec2 map_uv = map_center + mat2(vec2(c, s), vec2(-s, c)) * (local - vec2(0.0, 0.121)) * map_span;
	vec4 atlas = texture(roads, map_uv);
	float altitude = atlas.a;
	float contour = abs(fract(altitude * 23.0 + 0.5) - 0.5);
	float contour_res = fwidth(altitude) * 23.0;
	float lines = (1.0 - smoothstep(0.048, 0.12 + contour_res, contour)) * (1.0 - smoothstep(0.12, 0.42, contour_res));
	float gradient = clamp(altitude * 1.24 + 0.10 - length(local + vec2(0.22, 0.24)) * 0.23, 0.0, 1.0);
	vec3 terrain = mix(vec3(0.071, 0.123, 0.140), vec3(0.253, 0.314, 0.263), gradient);
	terrain = mix(terrain, vec3(0.49, 0.58, 0.45), lines * 0.25);
	terrain = mix(terrain, vec3(0.105, 0.263, 0.371), atlas.b * 0.92);
	float edge_fade = 1.0 - 0.34 * smoothstep(0.31, 0.50, radius);
	vec3 color = terrain * edge_fade;
	color = mix(color, vec3(0.87, 0.86, 0.80), smoothstep(0.04, 0.52, atlas.r) * edge_fade);
	color = mix(color, vec3(0.48, 0.95, 0.81), smoothstep(0.07, 0.65, atlas.g) * edge_fade);
	COLOR = vec4(color, mask * mix(0.54 + lines * 0.16 + atlas.b * 0.30, 0.96, clamp(max(atlas.r, atlas.g) * 1.45, 0.0, 1.0)));
}
