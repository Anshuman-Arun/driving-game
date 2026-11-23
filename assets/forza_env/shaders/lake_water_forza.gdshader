shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

// Animated Eastwater Lake shader:
// Calm broad dual-scrolling normal swells with distance attenuation (zero speckle),
// Fresnel sky reflection, sun specular glints, deep-to-shallow alpine teal tint,
// and smooth depth-based shoreline edge fade.

uniform sampler2D water_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform vec3 shallow_color : source_color = vec3(0.05, 0.28, 0.32);
uniform vec3 deep_color : source_color = vec3(0.015, 0.08, 0.16);
uniform vec3 sky_tint : source_color = vec3(0.45, 0.66, 0.88);

uniform float ripple_scale_a = 0.012;
uniform float ripple_scale_b = 0.024;
uniform vec2 ripple_speed_a = vec2(0.010, 0.006);
uniform vec2 ripple_speed_b = vec2(-0.008, 0.012);
uniform float normal_strength : hint_range(0.0, 1.5) = 0.18;

uniform float depth_fade_m : hint_range(0.1, 4.0) = 0.85;
uniform float depth_color_m : hint_range(0.5, 12.0) = 4.0;
uniform float foam_depth_m : hint_range(0.05, 1.0) = 0.22;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 xz = world_pos.xz;
	float cam_dist = length(VERTEX);
	// Attenuate high-frequency ripple normals over distance so overlooks look silky, not speckled.
	float dist_att = mix(0.28, 1.0, 1.0 - smoothstep(35.0, 260.0, cam_dist));

	// Broad dual-scrolling normal map swells.
	vec2 uv_a = xz * ripple_scale_a + TIME * ripple_speed_a;
	vec2 uv_b = xz * ripple_scale_b + TIME * ripple_speed_b;
	vec3 na = texture(water_normal, uv_a).rgb * 2.0 - 1.0;
	vec3 nb = texture(water_normal, uv_b).rgb * 2.0 - 1.0;
	vec3 blended_n = normalize(vec3((na.xy + nb.xy) * 0.55, max(na.z * nb.z, 0.35)));

	// Depth reconstruction (Godot 4.3+ Vulkan / Forward+ reverse-Z safe via INV_PROJECTION_MATRIX).
	float depth_raw = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float scene_depth = -view_pos.z;
	float surface_depth = -VERTEX.z;
	float water_depth = max(scene_depth - surface_depth, 0.0);

	// Smooth Beer-Lambert depth absorption and shoreline edge fade.
	float edge_alpha = smoothstep(0.0, depth_fade_m, water_depth);
	float depth_t = 1.0 - exp(-water_depth / max(depth_color_m, 0.1));
	vec3 water_tint = mix(shallow_color, deep_color, depth_t);

	// Subtle refracted lakebed color in crystal-clear shallows.
	vec2 refr_uv = clamp(SCREEN_UV + blended_n.xy * 0.004 * edge_alpha * dist_att, vec2(0.001), vec2(0.999));
	vec3 under_col = texture(screen_texture, refr_uv).rgb;
	vec3 water_body = mix(under_col * mix(vec3(1.0), shallow_color * 2.1, 0.42), water_tint, clamp(0.36 + depth_t * 0.64, 0.0, 0.96));

	// Calm Schlick Fresnel reflection tint for alpine lake reflections.
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.6);
	vec3 final_col = mix(water_body, sky_tint, fresnel * 0.52);

	// Subtle delicate shoreline lap foam right where water meets sand.
	float foam_wave = sin(water_depth * 18.0 - TIME * 1.4) * 0.5 + 0.5;
	float foam = (1.0 - smoothstep(0.02, foam_depth_m, water_depth)) * edge_alpha * (0.22 + 0.18 * foam_wave);
	final_col = mix(final_col, vec3(0.84, 0.90, 0.92), clamp(foam, 0.0, 0.45));

	ALBEDO = final_col;
	ALPHA = clamp(edge_alpha * (0.88 + fresnel * 0.12), 0.0, 1.0);
	ROUGHNESS = mix(0.065, 0.022, fresnel);
	METALLIC = 0.05;
	SPECULAR = 0.85;
	NORMAL_MAP = blended_n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_strength * dist_att;
}
