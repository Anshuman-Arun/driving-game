shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Alpha-cutout foliage card & twig shader (Surface 1) for Phase A realistic trees & shrubs.
// Locks branch-attachment wind to tree_bark.gdshader and adds subtle outer tip flutter + backlight.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;

uniform float alpha_scissor : hint_range(0.1, 0.8) = 0.42;
uniform float alpha_scissor_far : hint_range(0.08, 0.6) = 0.22;
uniform float normal_depth : hint_range(0.0, 1.5) = 0.45;
uniform float roughness_scale : hint_range(0.3, 1.4) = 0.88;
uniform float crown_normal_blend : hint_range(0.0, 1.0) = 0.62;

uniform vec3 albedo_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 warm_tint : source_color = vec3(1.10, 0.94, 0.74);
uniform vec3 sss_tint : source_color = vec3(0.58, 0.72, 0.24);
uniform float backlight_strength : hint_range(0.0, 1.0) = 0.34;

uniform float wind_strength : hint_range(0.0, 1.0) = 0.085;
uniform float leaf_flutter : hint_range(0.0, 0.25) = 0.032;
uniform vec2 wind_direction = vec2(0.84, 0.54);

varying vec3 v_crown_normal;
varying float v_flex;
varying float v_inst_warmth;
varying float v_inst_root_ao;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void vertex() {
	vec3 world_origin = MODEL_MATRIX[3].xyz;
	bool has_custom = dot(INSTANCE_CUSTOM, vec4(1.0)) > 0.0001;
	float inst_phase = has_custom ? INSTANCE_CUSTOM.r : hash21(world_origin.xz);
	float inst_stiff = has_custom ? mix(0.78, 1.22, INSTANCE_CUSTOM.g) : 1.0;
	v_inst_warmth = has_custom ? INSTANCE_CUSTOM.b : 0.22;
	v_inst_root_ao = has_custom ? INSTANCE_CUSTOM.a : 0.85;

	float flex = clamp(COLOR.a, 0.0, 1.0);
	v_flex = flex;

	// Outward/upward crown normal in view space for cohesive canopy volume shading.
	vec3 radial = vec3(VERTEX.x, max(VERTEX.y * 0.45, 0.65), VERTEX.z);
	if (dot(radial, radial) < 0.001) {
		radial = vec3(0.0, 1.0, 0.0);
	}
	v_crown_normal = normalize(MODELVIEW_NORMAL_MATRIX * normalize(radial));

	// Primary branch sway (must match tree_bark.gdshader so canopy stays anchored to limbs).
	vec2 w_dir = normalize(wind_direction);
	vec2 w_perp = vec2(-w_dir.y, w_dir.x);
	float wave = dot(world_origin.xz, w_dir) * 0.055 + inst_phase * 6.28318;
	float gust = 0.65 + 0.35 * sin(TIME * 0.42 + dot(world_origin.xz, vec2(0.021, -0.017)));
	float sway = (sin(TIME * 1.35 + wave) + 0.38 * sin(TIME * 2.45 - wave * 1.43)) * gust;
	float cross_sway = sin(TIME * 1.85 + wave * 1.30) * 0.32 * gust;

	float bend = flex * flex * wind_strength * inst_stiff;
	vec3 world_disp = vec3(w_dir.x * sway + w_perp.x * cross_sway, 0.0, w_dir.y * sway + w_perp.y * cross_sway) * bend;
	world_disp.y = -dot(world_disp.xz, world_disp.xz) * 0.10;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * world_disp;

	// Secondary fine leaf/spray flutter only beyond the branch anchor region.
	float tip_flex = max(flex - 0.22, 0.0) / 0.78;
	float flutter_p = dot(VERTEX, vec3(7.3, 11.1, 5.9)) + inst_phase * 12.566;
	float flutter = sin(TIME * 4.5 + flutter_p) * 0.55 + cos(TIME * 6.7 - flutter_p * 0.71) * 0.45;
	VERTEX += NORMAL * (flutter * tip_flex * tip_flex * leaf_flutter * gust);
}

void fragment() {
	vec4 texel = texture(albedo_tex, UV);
	float cam_dist = length(VERTEX);

	// Mip-compensating scissor prevents foliage crowns from thinning away at mid/far distance.
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = mix(alpha_scissor, alpha_scissor_far, smoothstep(14.0, 95.0, cam_dist));

	vec3 col = texel.rgb * albedo_tint * COLOR.rgb;
	col *= mix(vec3(1.0), warm_tint, v_inst_warmth * 0.45);
	col *= mix(0.84, 1.04, v_inst_root_ao);

	float rough = texture(roughness_tex, UV).g * roughness_scale;
	float tex_ao = texture(ao_tex, UV).r;

	ALBEDO = col;
	NORMAL = normalize(mix(NORMAL, v_crown_normal, crown_normal_blend));
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth * mix(1.0, 0.25, smoothstep(12.0, 65.0, cam_dist));
	ROUGHNESS = clamp(rough, 0.62, 0.96);
	METALLIC = 0.0;
	SPECULAR = 0.14;
	AO = mix(1.0, tex_ao, 0.55);
	// Warm-green subsurface translucency when backlit by the sun.
	BACKLIGHT = mix(col, col * sss_tint * 1.45, 0.45) * backlight_strength * (0.55 + 0.45 * v_flex);
}
