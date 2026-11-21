shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float water_level = 0.0;
uniform float snow_start_height = 128.0;
uniform float snow_blend_range = 48.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_shoulder_weight;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p = rot * p * 2.04 + vec2(17.1, 31.7);
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_shoulder_weight = COLOR.r;
}

void fragment() {
	vec3 wp = v_world_pos;
	vec3 wn = normalize(v_world_normal);
	float cam_dist = length(CAMERA_POSITION_WORLD - wp);

	float n_macro = fbm(wp.xz * 0.018);
	float n_mid = fbm(wp.xz * 0.095);
	float n_fine = vnoise(wp.xz * 0.85);

	// Stratified alpine rock detail
	float strata = fbm(vec2((wp.x + wp.z) * 0.045, wp.y * 0.26));
	float rock_var = fbm(wp.xz * 0.14 + vec2(wp.y * 0.12, -wp.y * 0.09));

	// Lush temperate meadow grass & mossy forest floor
	vec3 grass_lush = vec3(0.14, 0.24, 0.085);
	vec3 grass_warm = vec3(0.26, 0.29, 0.105);
	vec3 forest_floor = vec3(0.15, 0.135, 0.08);
	vec3 grass_col = mix(grass_lush, grass_warm, smoothstep(0.28, 0.72, n_macro));
	grass_col = mix(grass_col, forest_floor, smoothstep(0.54, 0.86, n_mid) * 0.42);
	grass_col *= (0.90 + 0.20 * n_fine);

	// Stratified alpine granite cliff rock
	vec3 rock_dark = vec3(0.19, 0.20, 0.215);
	vec3 rock_light = vec3(0.40, 0.39, 0.36);
	vec3 rock_col = mix(rock_dark, rock_light, smoothstep(0.25, 0.78, strata * 0.68 + rock_var * 0.32));
	rock_col *= (0.92 + 0.16 * n_fine);

	// Lakeside wet pebble / sand shore
	vec3 shore_dry = vec3(0.38, 0.35, 0.28);
	vec3 shore_wet = vec3(0.16, 0.15, 0.125);
	float wet_band = 1.0 - smoothstep(water_level - 0.4, water_level + 1.25, wp.y);
	float shore_mask = 1.0 - smoothstep(water_level + 0.6, water_level + 3.0, wp.y + (n_mid - 0.5) * 1.4);
	vec3 shore_col = mix(shore_dry, shore_wet, wet_band) * (0.90 + 0.20 * n_fine);

	// Road gravel shoulder
	vec3 gravel_col = vec3(0.29, 0.28, 0.25) * (0.88 + 0.24 * n_fine);

	// Slope-based rock blending
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	float rock_mask = smoothstep(0.16, 0.38, slope + (n_mid - 0.5) * 0.12);

	// High-altitude alpine snow on distant peaks
	float snow_mask = smoothstep(snow_start_height, snow_start_height + snow_blend_range, wp.y + (n_macro - 0.5) * 30.0);
	snow_mask *= smoothstep(0.38, 0.68, wn.y + 0.15);
	vec3 snow_col = vec3(0.86, 0.89, 0.94);

	vec3 albedo = mix(grass_col, rock_col, rock_mask);
	albedo = mix(albedo, shore_col, shore_mask * (1.0 - rock_mask * 0.55));
	albedo = mix(albedo, gravel_col, clamp(v_shoulder_weight, 0.0, 1.0));
	albedo = mix(albedo, snow_col, snow_mask);

	float roughness = mix(0.88, 0.76, rock_mask);
	roughness = mix(roughness, mix(0.82, 0.24, wet_band), shore_mask);
	roughness = mix(roughness, 0.92, clamp(v_shoulder_weight, 0.0, 1.0));
	roughness = mix(roughness, 0.50, snow_mask);

	// Clean analytical world-space normal perturbation (zero dFdx/dFdy screen-space blockiness)
	float detail_fade = 1.0 - smoothstep(35.0, 210.0, cam_dist);
	vec3 final_world_n = wn;
	if (detail_fade > 0.01) {
		float eps = 0.28;
		float h0 = fbm(wp.xz * 0.32);
		float hx = fbm((wp.xz + vec2(eps, 0.0)) * 0.32);
		float hz = fbm((wp.xz + vec2(0.0, eps)) * 0.32);
		float strength = mix(0.16, 0.42, rock_mask) * detail_fade * (1.0 - snow_mask * 0.75);
		vec3 bump_n = vec3((h0 - hx) * strength / eps, 0.0, (h0 - hz) * strength / eps);
		final_world_n = normalize(wn + bump_n);
	}

	ALBEDO = albedo;
	ROUGHNESS = clamp(roughness, 0.18, 0.98);
	METALLIC = 0.0;
	SPECULAR = mix(0.30, 0.52, wet_band * shore_mask);
	NORMAL = normalize((VIEW_MATRIX * vec4(final_world_n, 0.0)).xyz);
}
