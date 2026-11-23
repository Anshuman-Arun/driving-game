shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Multi-biome triplanar anti-tiling terrain shader for Aster Valley.
// Blends shore, lush alpine meadow grass, highland/conifer forest floor, and craggy cliff rock.

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_roughness : filter_linear_mipmap_anisotropic, repeat_enable;

uniform sampler2D forest_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_roughness : filter_linear_mipmap_anisotropic, repeat_enable;

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap_anisotropic, repeat_enable;

uniform sampler2D shore_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shore_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shore_roughness : filter_linear_mipmap_anisotropic, repeat_enable;

uniform sampler2D leaf_litter : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float grass_scale : hint_range(0.02, 0.5) = 0.11;
uniform float forest_scale : hint_range(0.02, 0.5) = 0.13;
uniform float rock_scale : hint_range(0.02, 0.5) = 0.085;
uniform float shore_scale : hint_range(0.02, 0.5) = 0.16;

uniform float water_level_m = 5.35;
uniform float shore_height_m = 7.4;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.52;

uniform vec3 grass_tint : source_color = vec3(0.46, 0.68, 0.36);
uniform vec3 forest_tint : source_color = vec3(0.56, 0.58, 0.46);
uniform vec3 rock_tint : source_color = vec3(0.76, 0.78, 0.82);
uniform vec3 shore_tint : source_color = vec3(0.84, 0.80, 0.72);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float amp = 0.55;
	mat2 rot = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int i = 0; i < 3; i++) {
		v += amp * value_noise(p);
		p = rot * p * 2.07 + vec2(17.1, 31.7);
		amp *= 0.45;
	}
	return v;
}

// Dual-scale rotated anti-tiling sample for planar XZ ground layers.
// Eliminates visible grid repetition from both chase cam and high overlook.
vec3 sample_planar_albedo(sampler2D tex, vec2 xz, float scale, float blend_w) {
	vec2 uv_a = xz * scale;
	// Irrational rotation + scale ratio breaks periodicity completely.
	mat2 rot = mat2(vec2(0.815, -0.579), vec2(0.579, 0.815));
	vec2 uv_b = (rot * xz) * (scale * 0.37) + vec2(0.31, 0.67);
	vec3 col_a = texture(tex, uv_a).rgb;
	vec3 col_b = texture(tex, uv_b).rgb;
	return mix(col_a, col_b, blend_w);
}

float sample_planar_mono(sampler2D tex, vec2 xz, float scale, float blend_w) {
	vec2 uv_a = xz * scale;
	mat2 rot = mat2(vec2(0.815, -0.579), vec2(0.579, 0.815));
	vec2 uv_b = (rot * xz) * (scale * 0.37) + vec2(0.31, 0.67);
	return mix(texture(tex, uv_a).r, texture(tex, uv_b).r, blend_w);
}

vec3 unpack_normal_xy(vec3 enc) {
	vec2 xy = enc.xy * 2.0 - 1.0;
	float z = sqrt(max(1.0 - dot(xy, xy), 0.001));
	return vec3(xy, z);
}

// Returns world-space perturbed normal for a planar XZ normal map.
vec3 sample_planar_world_normal(sampler2D tex, vec2 xz, float scale, float blend_w, vec3 surf_n, float strength) {
	vec2 uv_a = xz * scale;
	mat2 rot = mat2(vec2(0.815, -0.579), vec2(0.579, 0.815));
	vec2 uv_b = (rot * xz) * (scale * 0.37) + vec2(0.31, 0.67);

	vec3 na = unpack_normal_xy(texture(tex, uv_a).rgb);
	vec3 nb_raw = unpack_normal_xy(texture(tex, uv_b).rgb);
	// Rotate secondary normal tangent XY back into world XZ frame.
	vec2 nb_xz = transpose(rot) * nb_raw.xy;
	vec2 d_xz = mix(na.xy, nb_xz, blend_w) * strength;

	return normalize(vec3(surf_n.x + d_xz.x, surf_n.y, surf_n.z + d_xz.y));
}

// Triplanar rock sampling with dual-scale anti-tiling on XZ and clean side projections.
vec3 sample_triplanar_albedo(sampler2D tex, vec3 p, vec3 w, float scale, float blend_w) {
	vec3 sp = p * scale;
	vec3 sp2 = p * (scale * 0.41) + vec3(1.7, 3.1, 2.3);
	vec3 cx = mix(texture(tex, sp.zy).rgb, texture(tex, sp2.zy).rgb, blend_w);
	vec3 cy = mix(texture(tex, sp.xz).rgb, texture(tex, sp2.xz).rgb, blend_w);
	vec3 cz = mix(texture(tex, sp.xy).rgb, texture(tex, sp2.xy).rgb, blend_w);
	return cx * w.x + cy * w.y + cz * w.z;
}

float sample_triplanar_mono(sampler2D tex, vec3 p, vec3 w, float scale, float blend_w) {
	vec3 sp = p * scale;
	vec3 sp2 = p * (scale * 0.41) + vec3(1.7, 3.1, 2.3);
	float cx = mix(texture(tex, sp.zy).r, texture(tex, sp2.zy).r, blend_w);
	float cy = mix(texture(tex, sp.xz).r, texture(tex, sp2.xz).r, blend_w);
	float cz = mix(texture(tex, sp.xy).r, texture(tex, sp2.xy).r, blend_w);
	return cx * w.x + cy * w.y + cz * w.z;
}

vec3 sample_triplanar_world_normal(sampler2D tex, vec3 p, vec3 n, vec3 w, float scale, float strength) {
	vec3 sp = p * scale;
	vec3 tnx = unpack_normal_xy(texture(tex, sp.zy).rgb);
	vec3 tny = unpack_normal_xy(texture(tex, sp.xz).rgb);
	vec3 tnz = unpack_normal_xy(texture(tex, sp.xy).rgb);

	tnx.xy *= strength;
	tny.xy *= strength;
	tnz.xy *= strength;

	// Whiteout-style world-space triplanar normal swizzle.
	vec3 wx = vec3(n.x, n.y + tnx.y, n.z + tnx.x * sign(n.x));
	vec3 wy = vec3(n.x + tny.x, n.y, n.z + tny.y);
	vec3 wz = vec3(n.x + tnz.x * sign(n.z), n.y + tnz.y, n.z);
	return normalize(wx * w.x + wy * w.y + wz * w.z);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec2 xz = world_pos.xz;
	float h = world_pos.y;

	// Multi-scale organic noise for anti-tiling blend & macro biome color variation.
	float anti_tile_w = smoothstep(0.25, 0.75, fbm2(xz * 0.018));
	float macro_n = fbm2(xz * 0.0055);
	float fields = value_noise(xz * 0.011 + vec2(12.0, 33.0));
	float detail_n = value_noise(xz * 0.045);

	// Distance-based blend favors coarser scale slightly in the far distance to avoid moire.
	float cam_dist = length(VERTEX);
	float dist_blend = clamp(anti_tile_w * 0.65 + smoothstep(45.0, 260.0, cam_dist) * 0.35, 0.15, 0.85);
	// Smoothly attenuate high-frequency normal detail over distance to eliminate shimmering grain.
	float eff_normal_strength = normal_strength * mix(1.0, 0.22, smoothstep(16.0, 90.0, cam_dist));

	// Biome weights:
	// 1) Shoreline sand/pebbles near Eastwater Lake (y < ~7.4m)
	float shore_h = h + (detail_n - 0.5) * 1.1;
	float shore_w = 1.0 - smoothstep(water_level_m + 0.3, shore_height_m + 0.8, shore_h);
	// Wet shoreline darkening right at water edge.
	float wet_w = 1.0 - smoothstep(water_level_m - 0.1, water_level_m + 0.85, shore_h);

	// 2) Forest floor: higher elevation + Cedar Woods northwest region + organic patches.
	float cedar_region = (1.0 - smoothstep(-280.0, 100.0, xz.x)) * (1.0 - smoothstep(-60.0, 220.0, xz.y));
	float elev_forest = smoothstep(56.0, 114.0, h + (macro_n - 0.5) * 18.0);
	float forest_w = clamp(max(elev_forest, cedar_region * 0.82) * smoothstep(0.22, 0.68, macro_n + 0.18), 0.0, 1.0);
	forest_w *= (1.0 - shore_w);

	// 3) Steep cliff / alpine rock: slope-driven (17..33 deg) + high North Ridge peaks.
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	float rock_slope = smoothstep(0.100, 0.295, slope + (detail_n - 0.5) * 0.13);
	float moss_bank = smoothstep(0.36, 0.68, fields) * (1.0 - smoothstep(102.0, 168.0, h));
	float rock_alpine = smoothstep(133.0, 196.0, h + (macro_n - 0.5) * 18.0) * 0.85;
	float rock_w = clamp(max(rock_slope, rock_alpine), 0.0, 1.0);

	// Triplanar weights for rock.
	vec3 tri_w = pow(abs(n), vec3(5.0));
	tri_w /= max(dot(tri_w, vec3(1.0)), 0.0001);

	// Meadow and woodland share the coarse biome blend, but keep separate materials up close.
	vec3 meadow_tone = mix(vec3(0.64, 0.87, 0.55), vec3(1.17, 0.99, 0.64), smoothstep(0.24, 0.79, fields));
	vec3 base_col = sample_planar_albedo(grass_albedo, xz, grass_scale, dist_blend) * grass_tint * meadow_tone;
	float base_rgh = sample_planar_mono(grass_roughness, xz, grass_scale, dist_blend);
	vec3 base_n = sample_planar_world_normal(grass_normal, xz, grass_scale, dist_blend, n, eff_normal_strength * 0.78);
	float autumn = smoothstep(0.48, 0.79, detail_n * 0.62 + fields * 0.38);
	float town_hedges = (1.0 - smoothstep(130.0, 410.0, distance(xz, vec2(-625.0, 510.0))));
	if (forest_w > 0.06 || autumn * town_hedges > 0.10) {
		vec3 woodland = sample_planar_albedo(forest_albedo, xz, forest_scale, dist_blend) * forest_tint;
		vec3 scattered_leaves = texture(leaf_litter, xz * 0.42).rgb * vec3(0.89, 0.83, 0.73);
		woodland = mix(woodland, scattered_leaves, 0.22 + autumn * 0.65);
		float blend_forest = max(forest_w * 0.90, autumn * town_hedges * 0.54);
		base_col = mix(base_col, woodland, blend_forest);
		base_rgh = mix(base_rgh, sample_planar_mono(forest_roughness, xz, forest_scale, dist_blend), blend_forest);
		base_n = normalize(mix(base_n, sample_planar_world_normal(forest_normal, xz, forest_scale, dist_blend, n, eff_normal_strength * 0.78), blend_forest));
	}

	// Blend shoreline when near lake elevation.
	if (shore_w > 0.005) {
		vec3 col_shore = sample_planar_albedo(shore_albedo, xz, shore_scale, dist_blend) * shore_tint;
		float rgh_shore = sample_planar_mono(shore_roughness, xz, shore_scale, dist_blend);
		vec3 n_shore = sample_planar_world_normal(shore_normal, xz, shore_scale, dist_blend, n, eff_normal_strength * 0.72);
		// Wet darkening & gloss near waterline.
		col_shore *= mix(1.0, 0.54, wet_w);
		rgh_shore = mix(rgh_shore, 0.28, wet_w);

		base_col = mix(base_col, col_shore, shore_w);
		base_rgh = mix(base_rgh, rgh_shore, shore_w);
		base_n = normalize(mix(base_n, n_shore, shore_w));
	}

	// Blend triplanar cliff rock on steep slopes & alpine ridges.
	if (rock_w > 0.005) {
		vec3 col_rock = sample_triplanar_albedo(rock_albedo, world_pos, tri_w, rock_scale, dist_blend) * rock_tint;
		// Subtle geological stratification & macro shading on mountain cliffs.
		float strata = 0.89 + 0.16 * sin(h * 0.33 + xz.x * 0.021 + macro_n * 8.0);
		if (moss_bank > 0.06) {
			vec3 lichen = sample_triplanar_albedo(moss_rock, world_pos, tri_w, 0.19, dist_blend);
			col_rock = mix(col_rock, lichen * vec3(0.78, 0.88, 0.77), moss_bank * 0.73);
		}
		col_rock *= strata * mix(0.92, 1.05, detail_n);
		float rgh_rock = sample_triplanar_mono(rock_roughness, world_pos, tri_w, rock_scale, dist_blend);
		vec3 n_rock = sample_triplanar_world_normal(rock_normal, world_pos, n, tri_w, rock_scale, eff_normal_strength * 1.15);

		base_col = mix(base_col, col_rock, rock_w);
		base_rgh = mix(base_rgh, rgh_rock, rock_w);
		base_n = normalize(mix(base_n, n_rock, rock_w));
	}

	// Subtle macro luminance breakup across the 2x2 km valley.
	base_col *= mix(0.84, 1.13, value_noise(xz * 0.0028));

	ALBEDO = base_col;
	ROUGHNESS = clamp(base_rgh * 0.78 + 0.18, 0.24, 0.98);
	METALLIC = 0.0;
	SPECULAR = mix(0.32, 0.55, wet_w * shore_w);
	NORMAL = normalize((VIEW_MATRIX * vec4(base_n, 0.0)).xyz);
}
