shader_type canvas_item;
render_mode unshaded;

uniform sampler2D roads : filter_linear_mipmap, repeat_disable;
uniform vec2 map_center = vec2(0.19, 0.78);
uniform float heading;

void fragment() {
	vec2 point = UV - vec2(0.5);
	float radius = length(point);
	float width = max(fwidth(radius), 0.001);
	float mask = 1.0 - smoothstep(0.5 - width, 0.5, radius);
	float border = smoothstep(0.481 - width, 0.481 + width, radius);
	float cosine = cos(heading);
	float sine = sin(heading);
	vec2 world_offset = mat2(vec2(cosine, sine), vec2(-sine, cosine)) * point;
	vec2 map_uv = map_center + world_offset * 0.165;
	vec3 asphalt = texture(roads, map_uv).rgb;
	vec3 ground = mix(vec3(0.057, 0.105, 0.139), vec3(0.115, 0.203, 0.226), 1.0 - radius);
	vec3 color = mix(ground, vec3(0.15, 0.29, 0.31), asphalt.b * 0.62);
	color = mix(color, vec3(0.80, 0.88, 0.91), asphalt.r);
	color = mix(color, vec3(0.39, 0.95, 0.79), asphalt.g);
	color = mix(color, vec3(0.67, 0.82, 0.83), border * 0.62);
	COLOR = vec4(color, mask * max(0.84, max(asphalt.r, asphalt.g)));
}
