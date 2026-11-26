shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords;
uniform bool wind_enabled = true;
uniform float wind_strength : hint_range(0.0, 0.16) = 0.08;
uniform vec2 wind_direction = vec2(0.85, 0.53);
uniform bool vehicle_enabled = false;
uniform vec3 vehicle_position = vec3(0.0);
uniform vec3 vehicle_velocity = vec3(0.0);
uniform bool fade_enabled = true;
uniform bool lod_blade_fade_enabled = true;
uniform bool lod_density_fade_enabled = true;
uniform float mid_rank_limit = 4096.0;
uniform float far_rank_limit = 4096.0;
uniform float lod_hysteresis = 5.0;
uniform float near_radius = 25.0;
uniform float mid_radius = 65.0;
uniform float fade_start = 105.0;
uniform float fade_end = 130.0;
varying flat vec3 tuft_root;
varying float flex;
varying flat float tuft_seed;
varying flat float density_keep;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	flex = clamp(UV.y, 0.0, 1.0);
	tuft_seed = INSTANCE_CUSTOM.r;
	vec2 dir = wind_direction / max(length(wind_direction), 0.001);
	float phase = dot(root.xz, dir) * 0.16;
	float gust = 0.55 + 0.30 * sin(TIME * 1.55 - phase) + 0.15 * sin(TIME * 0.78 - phase * 0.41);
	vec2 bend = vec2(0.0);
	if (wind_enabled) {
		bend += dir * gust * clamp(wind_strength, 0.0, 0.16);
		bend += vec2(-dir.y, dir.x) * sin(TIME * 3.8 + tuft_seed * 6.283 + dot(root.xz, vec2(0.31, -0.27))) * 0.032;
	}
	if (vehicle_enabled) {
		vec2 away = root.xz - vehicle_position.xz;
		float d = length(away);
		float influence = (1.0 - smoothstep(0.35, 2.6, d)) * smoothstep(0.0, 8.0, length(vehicle_velocity.xz));
		influence *= 1.0 - smoothstep(0.5, 2.0, abs(root.y - vehicle_position.y));
		bend += away / max(d, 0.1) * influence * 0.18;
	}
	bend *= min(1.0, 0.24 / max(length(bend), 0.001));
	// No second batch: extra blades shrink before a chunk can switch LOD.
	float blade_weight = 1.0;
	vec2 chunk_center = root.xz + (INSTANCE_CUSTOM.gb - vec2(0.5)) * 16.0;
	float chunk_distance = length(chunk_center - CAMERA_POSITION_WORLD.xz);
	density_keep = 1.0;
	if (lod_density_fade_enabled) {
		float rank = INSTANCE_CUSTOM.a * 4096.0;
		float near_end = max(1.0, near_radius - lod_hysteresis);
		float mid_end = max(1.0, mid_radius - lod_hysteresis);
		if (rank >= mid_rank_limit) {
			density_keep *= 1.0 - smoothstep(max(0.0, near_end - 8.0), near_end, chunk_distance);
		}
		if (rank >= far_rank_limit) {
			density_keep *= 1.0 - smoothstep(max(0.0, mid_end - 8.0), mid_end, chunk_distance);
		}
	}
	if (lod_blade_fade_enabled && UV.x >= 3.0) {
		float boundary = UV.x >= 5.0 ? near_radius : mid_radius;
		float fade_to = max(1.0, boundary - lod_hysteresis);
		float fade_from = max(0.0, fade_to - 6.0);
		blade_weight = 1.0 - smoothstep(fade_from, fade_to, chunk_distance);
	}
	vec3 blade_root = (MODEL_MATRIX * vec4(UV2.x, 0.0, UV2.y, 1.0)).xyz;
	VERTEX = blade_root + (VERTEX - blade_root) * blade_weight;
	vec2 horiz_disp = bend * flex * flex * blade_weight;
	VERTEX.xz += horiz_disp;
	VERTEX.y -= dot(horiz_disp, horiz_disp) * 0.22;
	tuft_root = root;
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.58));
}

void fragment() {
	// Stable whole-tuft density fade, with no second buffer or blending.
	if (density_keep <= 0.0 || (density_keep < 1.0 && tuft_seed >= density_keep)) { discard; }
	// Stable spatial cutout at outer range, no alpha-blended overdraw.
	if (fade_enabled) {
		float d = length(tuft_root.xz - CAMERA_POSITION_WORLD.xz);
		float keep = 1.0 - smoothstep(fade_start, fade_end, d);
		if (keep <= 0.0 || (keep < 1.0 && tuft_seed >= keep)) { discard; }
	}
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(NORMAL, up, 0.72));
	// Convert sRGB vertex color to linear PBR space so grass matches terrain albedo naturally.
	vec3 base_lin = pow(max(COLOR.rgb, vec3(0.0001)), vec3(2.2));
	vec3 meadow_var = mix(vec3(0.90, 1.00, 0.80), vec3(1.24, 1.06, 0.70), tuft_seed);
	vec3 blade_col = base_lin * meadow_var;
	blade_col *= mix(vec3(1.0), vec3(1.24, 1.18, 0.80), smoothstep(0.42, 1.0, flex));
	vec3 root_ground = vec3(0.042, 0.056, 0.020);
	float root_t = smoothstep(0.0, 0.34, flex);
	vec3 col = mix(root_ground, blade_col, root_t);
	float root_ao = mix(0.42, 1.0, smoothstep(0.0, 0.46, flex));
	ALBEDO = col * root_ao;
	ROUGHNESS = mix(0.94, 0.74, flex);
	SPECULAR = mix(0.06, 0.16, flex);
	BACKLIGHT = ALBEDO * 0.34 * (0.20 + 0.80 * flex);
}
