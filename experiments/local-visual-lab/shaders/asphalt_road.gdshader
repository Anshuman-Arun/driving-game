shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// UV.x in [0, 1] across total road+shoulder width (~10.4 m)
	// UV.y = distance along road in meters
	float u = UV.x;
	float v = UV.y;

	float aggregate = vnoise(vec2(u * 140.0, v * 14.0));
	float micro = vnoise(vec2(u * 380.0, v * 38.0));
	float patch_var = fbm(vec2(u * 7.5, v * 0.12));

	// Neutral-toned weathered asphalt base
	vec3 asphalt_base = mix(vec3(0.095, 0.098, 0.105), vec3(0.155, 0.158, 0.165), patch_var);
	asphalt_base *= (0.86 + 0.28 * aggregate);

	// Tire wear tracks in left and right lanes (slightly darker & smoother)
	float left_track = exp(-pow((u - 0.30) / 0.065, 2.0));
	float right_track = exp(-pow((u - 0.70) / 0.065, 2.0));
	float tracks = clamp(left_track + right_track, 0.0, 1.0);
	asphalt_base = mix(asphalt_base, asphalt_base * 0.78, tracks * 0.65);

	// Gravel shoulder feather on outer edges
	float edge_dist = min(u, 1.0 - u);
	float gravel_mask = 1.0 - smoothstep(0.065, 0.115, edge_dist + (patch_var - 0.5) * 0.025);
	vec3 gravel_col = vec3(0.27, 0.26, 0.23) * (0.82 + 0.36 * aggregate);

	// Road markings with realistic slight wear breakup
	float paint_wear = smoothstep(0.22, 0.75, fbm(vec2(u * 24.0, v * 0.75)) * 0.65 + aggregate * 0.35);

	// Double yellow center line
	float yellow_l = 1.0 - smoothstep(0.0055, 0.0085, abs(u - 0.487));
	float yellow_r = 1.0 - smoothstep(0.0055, 0.0085, abs(u - 0.513));
	float yellow_mask = clamp(yellow_l + yellow_r, 0.0, 1.0) * (0.72 + 0.28 * paint_wear);
	vec3 yellow_paint = vec3(0.78, 0.56, 0.11);

	// Solid white edge lines
	float white_l = 1.0 - smoothstep(0.0055, 0.009, abs(u - 0.135));
	float white_r = 1.0 - smoothstep(0.0055, 0.009, abs(u - 0.865));
	float white_mask = clamp(white_l + white_r, 0.0, 1.0) * (0.76 + 0.24 * paint_wear);
	vec3 white_paint = vec3(0.84, 0.83, 0.79);

	vec3 col = mix(asphalt_base, gravel_col, gravel_mask);
	col = mix(col, yellow_paint, yellow_mask * (1.0 - gravel_mask));
	col = mix(col, white_paint, white_mask * (1.0 - gravel_mask));

	// Roughness: tire tracks slightly glossier to catch golden-hour specular streak
	float rough = mix(0.78, 0.56, tracks);
	rough = mix(rough, 0.90, gravel_mask);
	rough = mix(rough, 0.62, max(yellow_mask, white_mask) * (1.0 - gravel_mask));
	rough += (micro - 0.5) * 0.08;

	// Subtle asphalt aggregate normal grain
	float bump = (aggregate * 0.6 + micro * 0.4) * 0.06;
	vec3 n_view = NORMAL;
	vec3 dpdx = dFdx(v_world_pos);
	vec3 dpdy = dFdy(v_world_pos);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(n_view, 0.0)).xyz);
	vec3 perturb = normalize(cross(dpdy, wn) * dFdx(bump) + cross(wn, dpdx) * dFdy(bump) + vec3(1e-5));
	vec3 final_wn = normalize(wn - perturb * 0.18);

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.35, 0.96);
	METALLIC = 0.0;
	SPECULAR = mix(0.45, 0.58, tracks);
	NORMAL = normalize((VIEW_MATRIX * vec4(final_wn, 0.0)).xyz);
}
