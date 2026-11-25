shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Opaque PBR bark & woody stem shader (Surface 0) for Phase A realistic trees & shrubs.
// Matches tree_foliage.gdshader primary wind sway on COLOR.a so branches and canopy stay locked.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float normal_depth : hint_range(0.0, 2.0) = 0.85;
uniform float roughness_scale : hint_range(0.2, 1.5) = 0.92;
uniform vec3 albedo_tint : source_color = vec3(1.0, 1.0, 1.0);

uniform float wind_strength : hint_range(0.0, 1.0) = 0.085;
uniform vec2 wind_direction = vec2(0.84, 0.54);

uniform float root_ao_strength : hint_range(0.0, 1.0) = 0.45;
uniform float moss_strength : hint_range(0.0, 1.0) = 0.24;
uniform vec3 moss_color : source_color = vec3(0.21, 0.25, 0.14);

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_flex;
varying float v_inst_root_ao;
varying float v_inst_warmth;

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
	v_inst_warmth = has_custom ? INSTANCE_CUSTOM.b : 0.25;
	v_inst_root_ao = has_custom ? INSTANCE_CUSTOM.a : 0.85;

	float flex = clamp(COLOR.a, 0.0, 1.0);
	v_flex = flex;

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

	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 col = texture(albedo_tex, uv).rgb * albedo_tint * COLOR.rgb;
	float rough = texture(roughness_tex, uv).g * roughness_scale;
	float tex_ao = texture(ao_tex, uv).r;

	// Subtle moss & root grounding near base and upward-facing bark crevices.
	float base_mask = 1.0 - smoothstep(0.0, 0.16, v_flex);
	float up_mask = smoothstep(0.25, 0.85, v_world_normal.y);
	float moss_noise = fract(sin(dot(floor(v_world_pos.xz * 4.0), vec2(12.9898, 78.233))) * 43758.5453);
	float moss_w = moss_strength * clamp(base_mask * 0.85 + up_mask * 0.35, 0.0, 1.0) * mix(0.65, 1.15, moss_noise);
	col = mix(col, moss_color, clamp(moss_w, 0.0, 0.65));

	// Root & inner-trunk contact darkening.
	float root_ao = mix(1.0 - root_ao_strength * (1.15 - v_inst_root_ao * 0.5), 1.0, smoothstep(0.0, 0.22, v_flex));
	col *= root_ao;

	float cam_dist = length(VERTEX);
	float dist_n = mix(1.0, 0.25, smoothstep(14.0, 75.0, cam_dist));

	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.58, 0.98);
	METALLIC = 0.0;
	SPECULAR = 0.22;
	AO = mix(1.0, tex_ao * root_ao, 0.72);
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth * dist_n;
}
