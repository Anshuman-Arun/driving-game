shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

uniform vec3 shallow_color : source_color = vec3(0.07, 0.30, 0.31);
uniform vec3 deep_color : source_color = vec3(0.025, 0.095, 0.165);
uniform vec3 foam_color : source_color = vec3(0.84, 0.89, 0.92);
uniform float wave_speed = 0.65;
uniform float normal_strength = 0.11;
uniform float beer_factor = 0.34;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
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

// Organic multi-directional alpine ripples + smooth noise breakup (no regular striping)
vec2 wave_grad(vec2 p, float t) {
	vec2 g = vec2(0.0);

	vec2 d1 = vec2(0.86, 0.51);
	g += d1 * cos(dot(p, d1) * 0.38 + t * 1.10) * 0.12;

	vec2 d2 = vec2(-0.62, 0.78);
	g += d2 * cos(dot(p, d2) * 0.73 - t * 1.38) * 0.11;

	vec2 d3 = vec2(0.29, -0.95);
	g += d3 * cos(dot(p, d3) * 1.41 + t * 1.85) * 0.09;

	// Smooth organic dual-scrolling value noise gradient
	float eps = 0.25;
	vec2 p1 = p * 0.42 + vec2(t * 0.35, -t * 0.24);
	vec2 p2 = p * 0.88 + vec2(-t * 0.28, t * 0.41);
	float h0 = vnoise(p1) * 0.65 + vnoise(p2) * 0.35;
	float hx = vnoise(p1 + vec2(eps, 0.0)) * 0.65 + vnoise(p2 + vec2(eps, 0.0)) * 0.35;
	float hz = vnoise(p1 + vec2(0.0, eps)) * 0.65 + vnoise(p2 + vec2(0.0, eps)) * 0.35;
	g += vec2((hx - h0) / eps, (hz - h0) / eps) * 0.55;

	return g;
}

void fragment() {
	vec3 wp = v_world_pos;
	float cam_dist = length(CAMERA_POSITION_WORLD - wp);
	float t = TIME * wave_speed;

	// Attenuate high-frequency ripple strength with distance to eliminate grazing shimmer
	float dist_atten = mix(1.0, 0.28, smoothstep(20.0, 260.0, cam_dist));
	vec2 g = wave_grad(wp.xz, t) * normal_strength * dist_atten;
	vec3 wn = normalize(vec3(-g.x, 1.0, -g.y));
	vec3 vn = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// Reconstruct linear water depth
	float raw_depth = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_scene = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_scene.xyz /= view_scene.w;
	float water_depth = max(0.0, VERTEX.z - view_scene.z);

	float absorb = 1.0 - exp(-water_depth * beer_factor);
	vec3 water_tint = mix(shallow_color, deep_color, clamp(absorb, 0.0, 1.0));

	vec2 refract_uv = clamp(SCREEN_UV + vn.xy * 0.008 * clamp(water_depth * 0.4, 0.0, 1.0), vec2(0.002), vec2(0.998));
	vec3 under_col = texture(screen_texture, refract_uv).rgb;
	vec3 body_col = mix(under_col * vec3(0.76, 0.92, 0.90), water_tint, clamp(absorb * 0.85 + 0.15, 0.0, 1.0));

	// Subtle shoreline foam ripple
	float shore_wave = 0.5 + 0.5 * sin(wp.x * 1.4 + wp.z * 1.1 + t * 2.2);
	float foam_edge = (1.0 - smoothstep(0.04, 0.55, water_depth)) * smoothstep(0.35, 0.78, shore_wave + (0.32 - water_depth));
	body_col = mix(body_col, foam_color, clamp(foam_edge * 0.55, 0.0, 0.65));

	float ndotv = clamp(dot(vn, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 4.5);

	ALBEDO = mix(body_col, body_col * 0.55, fresnel * 0.55);
	ROUGHNESS = mix(0.035, 0.22, foam_edge);
	METALLIC = 0.04;
	SPECULAR = 0.90;
	NORMAL = vn;
}
