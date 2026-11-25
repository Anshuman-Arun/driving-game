shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Pure early-Z opaque 3D grass blade shader (no ALPHA writes) for grass_short_lod0 & grass_meadow_lod0.
// Grounds roots into the terrain palette and breaks up uniform wind via gust waves + INSTANCE_CUSTOM.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 root_ground_color : source_color = vec3(0.19, 0.21, 0.12);
uniform vec3 blade_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 tip_tint : source_color = vec3(1.06, 1.04, 0.88);
uniform vec3 dry_tint : source_color = vec3(1.14, 0.96, 0.68);

uniform float root_blend_height : hint_range(0.05, 0.7) = 0.34;
uniform float root_ao_strength : hint_range(0.0, 0.8) = 0.38;
uniform float roughness_scale : hint_range(0.3, 1.4) = 0.84;
uniform float normal_depth : hint_range(0.0, 1.5) = 0.42;
uniform float backlight_strength : hint_range(0.0, 1.0) = 0.28;

uniform float wind_strength : hint_range(0.0, 0.8) = 0.15;
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
	v_inst_warmth = has_custom ? INSTANCE_CUSTOM.b : 0.20;
	v_inst_root_ao = has_custom ? INSTANCE_CUSTOM.a : 0.85;

	float flex = clamp(COLOR.a, 0.0, 1.0);
	v_flex = flex;
	v_up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);

	// Travelling valley wind wave + micro turbulence across individual grass clumps.
	vec2 w_dir = normalize(wind_direction);
	vec2 w_perp = vec2(-w_dir.y, w_dir.x);
	float gust_wave = sin(TIME * 1.45 - dot(world_pos.xz, w_dir) * 0.22 + inst_phase * 2.1);
	float ripple = sin(TIME * 3.15 - dot(world_pos.xz, vec2(0.51, -0.43)) + inst_phase * 6.283) * 0.34;
	float gust_amp = 0.55 + 0.45 * sin(TIME * 0.48 + dot(world_origin.xz, vec2(0.035, 0.025)));

	float bend = flex * flex * wind_strength * inst_stiff * gust_amp;
	vec3 world_disp = vec3(
		w_dir.x * (gust_wave + ripple) + w_perp.x * ripple * 0.45,
		0.0,
		w_dir.y * (gust_wave + ripple) + w_perp.y * ripple * 0.45
	) * bend;
	world_disp.y = -dot(world_disp.xz, world_disp.xz) * 0.28;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * world_disp;

	// Smooth distance sink-to-ground to eliminate hard pop-in without alpha-fade overdraw.
	float cam_dist = distance(world_origin, INV_VIEW_MATRIX[3].xyz);
	float dist_shrink = 1.0 - smoothstep(fade_start_m, max(fade_end_m, fade_start_m + 1.0), cam_dist);
	VERTEX.y *= dist_shrink;
	VERTEX.xz *= mix(0.45, 1.0, dist_shrink);
}

void fragment() {
	vec3 raw_col = texture(albedo_tex, UV).rgb * blade_tint * COLOR.rgb;
	// Blend biome dryness/warmth and sunlit tip warmth.
	raw_col *= mix(vec3(1.0), dry_tint, v_inst_warmth * 0.55);
	raw_col *= mix(vec3(1.0), tip_tint, smoothstep(0.35, 1.0, v_flex));

	// Ground root seam into terrain albedo + contact AO.
	float root_t = smoothstep(0.02, root_blend_height, v_flex);
	vec3 col = mix(root_ground_color, raw_col, root_t);
	float root_ao = mix(1.0 - root_ao_strength * (1.15 - v_inst_root_ao * 0.45), 1.0, smoothstep(0.0, 0.42, v_flex));
	col *= root_ao;

	float cam_dist = length(VERTEX);
	float rough = texture(roughness_tex, UV).g * roughness_scale;
	float tex_ao = texture(ao_tex, UV).r;

	ALBEDO = col;
	// Soften blade normals toward sky-up so back-lit and front-lit blades blend smoothly without harsh facets.
	NORMAL = normalize(mix(NORMAL, v_up_view, 0.65));
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth * mix(1.0, 0.20, smoothstep(8.0, 40.0, cam_dist));
	ROUGHNESS = clamp(mix(0.92, rough, root_t), 0.55, 0.96);
	METALLIC = 0.0;
	SPECULAR = mix(0.10, 0.24, root_t);
	AO = mix(1.0, tex_ao * root_ao, 0.65);
	BACKLIGHT = col * backlight_strength * (0.20 + 0.80 * v_flex);
}
