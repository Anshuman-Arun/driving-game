shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Alpha-cutout undergrowth shader for fern, wildflower, tall_verge seed heads, and LOD1 clump cards.
// Uses distance-compensated alpha scissor to preserve silhouette density without TAA shimmer.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;

uniform float alpha_scissor : hint_range(0.1, 0.8) = 0.42;
uniform float alpha_scissor_far : hint_range(0.08, 0.6) = 0.22;
uniform vec3 root_ground_color : source_color = vec3(0.18, 0.19, 0.12);
uniform vec3 blade_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 dry_tint : source_color = vec3(1.12, 0.94, 0.70);

uniform float root_blend_height : hint_range(0.05, 0.7) = 0.28;
uniform float root_ao_strength : hint_range(0.0, 0.8) = 0.36;
uniform float roughness_scale : hint_range(0.3, 1.4) = 0.85;
uniform float normal_depth : hint_range(0.0, 1.5) = 0.45;
uniform float backlight_strength : hint_range(0.0, 1.0) = 0.34;
uniform float up_normal_blend : hint_range(0.0, 1.0) = 0.58;

uniform float wind_strength : hint_range(0.0, 0.8) = 0.13;
uniform vec2 wind_direction = vec2(0.84, 0.54);
uniform float fade_start_m : hint_range(20.0, 300.0) = 95.0;
uniform float fade_end_m : hint_range(30.0, 350.0) = 145.0;

varying float v_flex;
varying float v_inst_warmth;
varying float v_inst_root_ao;
varying vec3 v_up_view;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_origin = MODEL_MATRIX[3].xyz;
	bool has_custom = dot(INSTANCE_CUSTOM, vec4(1.0)) > 0.0001;
	float inst_phase = has_custom ? INSTANCE_CUSTOM.r : hash21(world_origin.xz);
	float inst_stiff = has_custom ? mix(0.75, 1.25, INSTANCE_CUSTOM.g) : 1.0;
	v_inst_warmth = has_custom ? INSTANCE_CUSTOM.b : 0.18;
	v_inst_root_ao = has_custom ? INSTANCE_CUSTOM.a : 0.85;

	float flex = clamp(COLOR.a, 0.0, 1.0);
	v_flex = flex;
	v_up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);

	vec2 w_dir = normalize(wind_direction);
	vec2 w_perp = vec2(-w_dir.y, w_dir.x);
	float gust_wave = sin(TIME * 1.40 - dot(world_pos.xz, w_dir) * 0.20 + inst_phase * 2.1);
	float ripple = sin(TIME * 2.95 - dot(world_pos.xz, vec2(0.49, -0.41)) + inst_phase * 6.283) * 0.30;
	float gust_amp = 0.55 + 0.45 * sin(TIME * 0.48 + dot(world_origin.xz, vec2(0.035, 0.025)));

	float bend = flex * flex * wind_strength * inst_stiff * gust_amp;
	vec3 world_disp = vec3(
		w_dir.x * (gust_wave + ripple) + w_perp.x * ripple * 0.45,
		0.0,
		w_dir.y * (gust_wave + ripple) + w_perp.y * ripple * 0.45
	) * bend;
	world_disp.y = -dot(world_disp.xz, world_disp.xz) * 0.24;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * world_disp;

	// Smooth distance sink-to-ground to eliminate hard pop-in without alpha-fade overdraw.
	float cam_dist = distance(world_origin, INV_VIEW_MATRIX[3].xyz);
	float dist_shrink = 1.0 - smoothstep(fade_start_m, max(fade_end_m, fade_start_m + 1.0), cam_dist);
	VERTEX.y *= dist_shrink;
	VERTEX.xz *= mix(0.45, 1.0, dist_shrink);
}

void fragment() {
	vec4 texel = texture(albedo_tex, UV);
	float cam_dist = length(VERTEX);

	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = mix(alpha_scissor, alpha_scissor_far, smoothstep(10.0, 75.0, cam_dist));

	vec3 raw_col = texel.rgb * blade_tint * COLOR.rgb;
	raw_col *= mix(vec3(1.0), dry_tint, v_inst_warmth * 0.45);

	float root_t = smoothstep(0.02, root_blend_height, v_flex);
	vec3 col = mix(root_ground_color, raw_col, root_t);
	float root_ao = mix(1.0 - root_ao_strength * (1.15 - v_inst_root_ao * 0.45), 1.0, smoothstep(0.0, 0.40, v_flex));
	col *= root_ao;

	float rough = texture(roughness_tex, UV).g * roughness_scale;
	float tex_ao = texture(ao_tex, UV).r;

	ALBEDO = col;
	NORMAL = normalize(mix(NORMAL, v_up_view, up_normal_blend));
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth * mix(1.0, 0.20, smoothstep(10.0, 50.0, cam_dist));
	ROUGHNESS = clamp(mix(0.92, rough, root_t), 0.56, 0.96);
	METALLIC = 0.0;
	SPECULAR = mix(0.10, 0.22, root_t);
	AO = mix(1.0, tex_ao * root_ao, 0.65);
	BACKLIGHT = col * backlight_strength * (0.25 + 0.75 * v_flex);
}
