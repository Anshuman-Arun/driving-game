shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Terrain Triplanar PBR Rock & Multi-Biome Terrain Shader
// - World-space triplanar projection on steep rock cliffs (NORMAL.y < slope_threshold)
//   using crisp rock cliff textures (rock_face_02 / rock PBR) with unstretched vertical strata.
// - Smooth normal-angle slope blend to grass / forest dirt on flatter ground (NORMAL.y > 0.65).
// - Stochastic macro noise anti-tiling eliminating repetition across kilometer terrain scales.
// - Full PBR lighting with Albedo, Normal, Roughness, and Ambient Occlusion.

group_uniforms Slope_Blending;
uniform float slope_threshold : hint_range(0.3, 0.9) = 0.65;
uniform float slope_blend_margin : hint_range(0.02, 0.3) = 0.12;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.85;

group_uniforms Rock_Cliff_PBR;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_ao : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_rock_arm = true;
uniform float rock_scale : hint_range(0.01, 0.5) = 0.075;
uniform vec3 rock_tint : source_color = vec3(0.85, 0.84, 0.82);
uniform float rock_strata_strength : hint_range(0.0, 0.6) = 0.16;
uniform float rock_strata_freq : hint_range(0.05, 1.0) = 0.22;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 6.0;

group_uniforms Grass_PBR;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_ao : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_scale : hint_range(0.02, 0.5) = 0.22;
uniform vec3 grass_tint : source_color = vec3(0.68, 0.82, 0.52);

group_uniforms Forest_Dirt_PBR;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_ao : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float dirt_scale : hint_range(0.02, 0.5) = 0.13;
uniform vec3 dirt_tint : source_color = vec3(0.65, 0.62, 0.50);

group_uniforms Shoreline;
uniform sampler2D shore_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shore_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D shore_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float shore_scale : hint_range(0.02, 0.5) = 0.16;
uniform vec3 shore_tint : source_color = vec3(0.84, 0.80, 0.72);
uniform float water_level_m = 5.35;
uniform float shore_height_m = 7.4;

group_uniforms Macro_Variation;
uniform float macro_scale : hint_range(0.001, 0.05) = 0.0055;
uniform float macro_luminance_mod : hint_range(0.0, 0.5) = 0.18;

group_uniforms Candidate;
uniform bool use_biome_mask = false;
uniform sampler2D biome_mask : filter_linear, repeat_disable;
uniform float biome_strength : hint_range(0.0, 1.0) = 0.7;
uniform float meadow_micro_strength : hint_range(0.0, 0.3) = 0.08;
uniform float anti_tile_strength : hint_range(0.0, 1.0) = 1.0;
uniform float pilot_normal_multiplier : hint_range(0.5, 1.5) = 1.0;
// Linear RGB multipliers, not source_color swatches: 1.0 is exact identity.
uniform vec3 meadow_tint_multiplier = vec3(1.0);
uniform vec3 woodland_tint_multiplier = vec3(1.0);
uniform float moss_strength : hint_range(0.0, 0.5) = 0.18;
uniform float roughness_bias : hint_range(-0.2, 0.2) = 0.025;
uniform bool use_roadside = false;
uniform sampler2D roadside_mask : filter_linear, repeat_disable;
uniform vec4 roadside_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float roadside_strength : hint_range(0.0, 1.0) = 0.55;
uniform bool limit_pilot = false;
uniform vec4 pilot_rect = vec4(0.0, 0.0, 1.0, 1.0);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

// Procedural hash and noise primitives for macro variation & anti-tiling
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

float fbm3(vec2 p) {
	float v = 0.0;
	float amp = 0.52;
	mat2 rot = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int i = 0; i < 3; i++) {
		v += amp * value_noise(p);
		p = rot * p * 2.05 + vec2(17.1, 31.7);
		amp *= 0.46;
	}
	return v;
}

// Unpack tangent normal map
vec3 unpack_normal(vec3 enc) {
	vec2 xy = enc.xy * 2.0 - 1.0;
	float z = sqrt(max(1.0 - dot(xy, xy), 0.001));
	return vec3(xy, z);
}

// Stochastic dual-scale sample for planar textures
vec3 sample_stochastic_albedo(sampler2D tex, vec2 uv, float scale, float blend_w) {
	vec2 uv_a = uv * scale;
	mat2 rot = mat2(vec2(0.815, -0.579), vec2(0.579, 0.815));
	vec2 uv_b = (rot * uv) * (scale * 0.38) + vec2(0.31, 0.67);
	vec3 ca = texture(tex, uv_a).rgb;
	vec3 cb = texture(tex, uv_b).rgb;
	return mix(ca, cb, blend_w);
}

float sample_stochastic_mono(sampler2D tex, vec2 uv, float scale, float blend_w) {
	vec2 uv_a = uv * scale;
	mat2 rot = mat2(vec2(0.815, -0.579), vec2(0.579, 0.815));
	vec2 uv_b = (rot * uv) * (scale * 0.38) + vec2(0.31, 0.67);
	return mix(texture(tex, uv_a).r, texture(tex, uv_b).r, blend_w);
}

vec3 sample_stochastic_world_normal(sampler2D tex, vec2 uv, float scale, float blend_w, vec3 surf_n, float str) {
	vec2 uv_a = uv * scale;
	mat2 rot = mat2(vec2(0.815, -0.579), vec2(0.579, 0.815));
	vec2 uv_b = (rot * uv) * (scale * 0.38) + vec2(0.31, 0.67);
	vec3 na = unpack_normal(texture(tex, uv_a).rgb);
	vec3 nb_raw = unpack_normal(texture(tex, uv_b).rgb);
	vec2 nb_rot = transpose(rot) * nb_raw.xy;
	vec2 d_xz = mix(na.xy, nb_rot, blend_w) * str;
	return normalize(vec3(surf_n.x + d_xz.x, surf_n.y, surf_n.z + d_xz.y));
}

// Triplanar sampling functions for steep cliff rock
// Projects cleanly along X, Y, Z world axes with unstretched vertical strata along ZY and XY
vec3 sample_triplanar_albedo(sampler2D tex, vec3 p, vec3 weights, float scale, float blend_w) {
	vec2 uv_x = p.zy * scale;
	vec2 uv_y = p.xz * scale;
	vec2 uv_z = p.xy * scale;

	mat2 rot = mat2(vec2(0.815, -0.579), vec2(0.579, 0.815));
	vec2 uv_x2 = (rot * p.zy) * (scale * 0.41) + vec2(1.7, 3.1);
	vec2 uv_y2 = (rot * p.xz) * (scale * 0.41) + vec2(2.4, 1.2);
	vec2 uv_z2 = (rot * p.xy) * (scale * 0.41) + vec2(0.9, 2.8);

	vec3 cx = mix(texture(tex, uv_x).rgb, texture(tex, uv_x2).rgb, blend_w);
	vec3 cy = mix(texture(tex, uv_y).rgb, texture(tex, uv_y2).rgb, blend_w);
	vec3 cz = mix(texture(tex, uv_z).rgb, texture(tex, uv_z2).rgb, blend_w);

	return cx * weights.x + cy * weights.y + cz * weights.z;
}

vec3 sample_triplanar_arm(sampler2D tex, vec3 p, vec3 weights, float scale, float blend_w) {
	vec2 uv_x = p.zy * scale;
	vec2 uv_y = p.xz * scale;
	vec2 uv_z = p.xy * scale;

	mat2 rot = mat2(vec2(0.815, -0.579), vec2(0.579, 0.815));
	vec2 uv_x2 = (rot * p.zy) * (scale * 0.41) + vec2(1.7, 3.1);
	vec2 uv_y2 = (rot * p.xz) * (scale * 0.41) + vec2(2.4, 1.2);
	vec2 uv_z2 = (rot * p.xy) * (scale * 0.41) + vec2(0.9, 2.8);

	vec3 cx = mix(texture(tex, uv_x).rgb, texture(tex, uv_x2).rgb, blend_w);
	vec3 cy = mix(texture(tex, uv_y).rgb, texture(tex, uv_y2).rgb, blend_w);
	vec3 cz = mix(texture(tex, uv_z).rgb, texture(tex, uv_z2).rgb, blend_w);

	return cx * weights.x + cy * weights.y + cz * weights.z;
}

float sample_triplanar_mono(sampler2D tex, vec3 p, vec3 weights, float scale, float blend_w) {
	vec2 uv_x = p.zy * scale;
	vec2 uv_y = p.xz * scale;
	vec2 uv_z = p.xy * scale;

	mat2 rot = mat2(vec2(0.815, -0.579), vec2(0.579, 0.815));
	vec2 uv_x2 = (rot * p.zy) * (scale * 0.41) + vec2(1.7, 3.1);
	vec2 uv_y2 = (rot * p.xz) * (scale * 0.41) + vec2(2.4, 1.2);
	vec2 uv_z2 = (rot * p.xy) * (scale * 0.41) + vec2(0.9, 2.8);

	float cx = mix(texture(tex, uv_x).r, texture(tex, uv_x2).r, blend_w);
	float cy = mix(texture(tex, uv_y).r, texture(tex, uv_y2).r, blend_w);
	float cz = mix(texture(tex, uv_z).r, texture(tex, uv_z2).r, blend_w);

	return cx * weights.x + cy * weights.y + cz * weights.z;
}

// World-space triplanar normal mapping
vec3 sample_triplanar_world_normal(sampler2D tex, vec3 p, vec3 n, vec3 weights, float scale, float str) {
	vec3 tnx = unpack_normal(texture(tex, p.zy * scale).rgb);
	vec3 tny = unpack_normal(texture(tex, p.xz * scale).rgb);
	vec3 tnz = unpack_normal(texture(tex, p.xy * scale).rgb);

	tnx.xy *= str;
	tny.xy *= str;
	tnz.xy *= str;

	// Project tangent coordinates into world space
	vec3 wx = vec3(n.x, n.y + tnx.y, n.z + tnx.x * sign(n.x));
	vec3 wy = vec3(n.x + tny.x, n.y, n.z + tny.y);
	vec3 wz = vec3(n.x + tnz.x * sign(n.z), n.y + tnz.y, n.z);

	return normalize(wx * weights.x + wy * weights.y + wz * weights.z);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec2 xz = world_pos.xz;
	float h = world_pos.y;
	float candidate_w = 1.0;
	if (limit_pilot) {
		vec2 edge = min(xz - pilot_rect.xy, pilot_rect.xy + pilot_rect.zw - xz);
		float fade_m = min(8.0, 0.5 * min(pilot_rect.z, pilot_rect.w));
		candidate_w = smoothstep(0.0, fade_m, min(edge.x, edge.y));
	}
	vec4 biome = vec4(0.0);
	float ecological_w = 0.0;
	vec2 biome_uv = (xz + vec2(1000.0)) / 2000.0;
	if (use_biome_mask && candidate_w > 0.0 && biome_uv.x >= 0.0 && biome_uv.y >= 0.0 && biome_uv.x < 1.0 && biome_uv.y < 1.0) {
		// Raw, non-mipmapped raster: explicit LOD avoids implicit derivatives in a divergent branch.
		biome = textureLod(biome_mask, biome_uv, 0.0);
		// C deliberately zeros grass/woodland/rock in hard-excluded cells.
		// Do not read those zeros as a different terrain biome along coarse road
		// or reserved-area edges. Exact roadside data controls the soil band.
		float ecological_coverage = max(biome.r, max(biome.g, biome.a));
		ecological_w = biome_strength * candidate_w * smoothstep(0.01, 0.12, ecological_coverage);
	}

	// Distance from camera for LOD / anti-shimmering
	float cam_dist = length(VERTEX);
	float eff_normal_str = normal_strength * mix(1.0, 0.35, smoothstep(20.0, 150.0, cam_dist));
	eff_normal_str = min(2.0, eff_normal_str * mix(1.0, pilot_normal_multiplier, candidate_w));

	// Multi-octave stochastic noise
	float anti_tile_w = smoothstep(0.25, 0.75, fbm3(xz * 0.02));
	float macro_noise = fbm3(xz * macro_scale);
	float detail_noise = value_noise(xz * 0.045);

	// Macro distance anti-tiling blend
	float dist_blend = clamp(anti_tile_w * 0.65 + smoothstep(50.0, 300.0, cam_dist) * 0.35, 0.15, 0.85);
	// Use existing organic detail to modulate the rotated secondary projection at a finer scale.
	dist_blend = clamp(dist_blend + (detail_noise - 0.5) * 0.18 * candidate_w * anti_tile_strength, 0.15, 0.85);

	// Slope Calculation:
	// n.y is 1.0 for completely horizontal ground, 0.0 for vertical cliff.
	// When n.y < slope_threshold (e.g. 0.65), it transitions into cliff rock.
	// Modulate with detail noise for natural jagged transition boundary.
	float jittered_ny = n.y + (detail_noise - 0.5) * 0.09;
	float flat_weight = smoothstep(slope_threshold - slope_blend_margin, slope_threshold + slope_blend_margin, jittered_ny);
	float rock_weight = 1.0 - flat_weight;
	// Mask can reinforce exposed banks, but does not erase slope-driven rock.
	rock_weight = max(rock_weight, biome.a * ecological_w * smoothstep(0.02, 0.25, 1.0 - n.y));

	// Triplanar projection weights for cliff rock
	vec3 tri_weights = pow(abs(n), vec3(triplanar_sharpness));
	tri_weights /= max(dot(tri_weights, vec3(1.0)), 0.0001);

	// Sample Flat Layer: Blend Meadow Grass and Forest Dirt
	// Forest dirt dominates higher elevation and northwestern woodland
	float cedar = (1.0 - smoothstep(110.0, 450.0, length(xz - vec2(-772.0, -256.0))));
	float forest_w = max(cedar * 0.86, smoothstep(66.0, 134.0, h + (macro_noise - 0.5) * 20.0) * 0.68);

	forest_w = mix(forest_w, biome.g, ecological_w);
	vec3 col_grass = sample_stochastic_albedo(grass_albedo, xz, grass_scale, dist_blend) * grass_tint;
	// Windward shaded meadow and sun-dried hay banks have distinct mid-scale tones.
	float pasture = 1.0 - smoothstep(90.0, 520.0, distance(xz, vec2(115.0, 240.0)));
	float meadow_break = smoothstep(0.26, 0.73, 0.63 * detail_noise + 0.37 * macro_noise);
	float dry_bank = meadow_break * max(pasture * 0.86, smoothstep(118.0, 185.0, h));
	col_grass *= mix(vec3(0.83, 1.025, 0.79), vec3(1.26, 1.07, 0.70), dry_bank);
	if (candidate_w > 0.0 && cam_dist < 110.0) {
		float micro = value_noise(xz * 0.72);
		col_grass *= 1.0 + (micro - 0.5) * meadow_micro_strength * candidate_w * (1.0 - smoothstep(25.0, 110.0, cam_dist));
	}
	col_grass *= mix(vec3(1.0), mix(vec3(1.07, 0.96, 0.82), vec3(0.94, 1.04, 0.94), biome.r), ecological_w);
	col_grass *= mix(vec3(1.0), meadow_tint_multiplier, candidate_w);
	vec3 col_dirt = sample_stochastic_albedo(dirt_albedo, xz, dirt_scale, dist_blend) * dirt_tint;
	col_dirt *= mix(vec3(1.0), vec3(0.77, 0.90, 0.78), cedar);
	col_dirt *= mix(vec3(1.0), vec3(0.81, 1.07, 0.80), moss_strength * candidate_w * forest_w * mix(0.5, biome.b, ecological_w));
	col_dirt *= mix(vec3(1.0), woodland_tint_multiplier, candidate_w);
	float ground_forest = forest_w * 0.65;
	if (use_roadside && candidate_w > 0.0) {
		vec2 ruv = (xz - roadside_rect.xy) / roadside_rect.zw;
		if (ruv.x >= 0.0 && ruv.y >= 0.0 && ruv.x < 1.0 && ruv.y < 1.0) {
			float band = textureLod(roadside_mask, ruv, 0.0).r * roadside_strength * candidate_w;
			ground_forest = mix(ground_forest, 1.0, band * (0.7 + 0.3 * detail_noise));
		}
	}
	vec3 flat_col = mix(col_grass, col_dirt, ground_forest);

	float rgh_grass = sample_stochastic_mono(grass_roughness, xz, grass_scale, dist_blend);
	float rgh_dirt = sample_stochastic_mono(dirt_roughness, xz, dirt_scale, dist_blend);
	float flat_rgh = mix(rgh_grass, rgh_dirt, ground_forest);

	float ao_grass = sample_stochastic_mono(grass_ao, xz, grass_scale, dist_blend);
	float ao_dirt = sample_stochastic_mono(dirt_ao, xz, dirt_scale, dist_blend);
	float flat_ao = mix(ao_grass, ao_dirt, ground_forest);

	vec3 n_grass = sample_stochastic_world_normal(grass_normal, xz, grass_scale, dist_blend, n, eff_normal_str * 0.75);
	vec3 n_dirt = sample_stochastic_world_normal(dirt_normal, xz, dirt_scale, dist_blend, n, eff_normal_str * 0.75);
	vec3 flat_n = normalize(mix(n_grass, n_dirt, ground_forest));

	// Shoreline handling near lake waterline
	float shore_h = h + (detail_noise - 0.5) * 1.0;
	float shore_w = 1.0 - smoothstep(water_level_m + 0.3, shore_height_m + 0.8, shore_h);
	float wet_w = 1.0 - smoothstep(water_level_m - 0.1, water_level_m + 0.85, shore_h);
	if (shore_w > 0.005) {
		vec3 col_shore = sample_stochastic_albedo(shore_albedo, xz, shore_scale, dist_blend) * shore_tint;
		float rgh_shore = sample_stochastic_mono(shore_roughness, xz, shore_scale, dist_blend);
		vec3 n_shore = sample_stochastic_world_normal(shore_normal, xz, shore_scale, dist_blend, n, eff_normal_str * 0.70);
		col_shore *= mix(1.0, 0.55, wet_w);
		rgh_shore = mix(rgh_shore, 0.28, wet_w);

		flat_col = mix(flat_col, col_shore, shore_w);
		flat_rgh = mix(flat_rgh, rgh_shore, shore_w);
		flat_n = normalize(mix(flat_n, n_shore, shore_w));
	}

	if (rock_weight > 0.008) {
		vec3 rock_col = sample_triplanar_albedo(rock_albedo, world_pos, tri_weights, rock_scale, dist_blend) * rock_tint;
		float mineral_band = sin(h * rock_strata_freq + xz.x * 0.019 + macro_noise * 5.0);
		rock_col *= 1.0 + rock_strata_strength * mineral_band;
		float rock_rgh = 0.85;
		float rock_ao_val = 1.0;
		if (use_rock_arm) {
			vec3 arm = sample_triplanar_arm(rock_arm, world_pos, tri_weights, rock_scale, dist_blend);
			rock_ao_val = arm.r;
			rock_rgh = arm.g;
		} else {
			rock_rgh = sample_triplanar_mono(rock_roughness, world_pos, tri_weights, rock_scale, dist_blend);
			rock_ao_val = sample_triplanar_mono(rock_ao, world_pos, tri_weights, rock_scale, dist_blend);
		}
		vec3 rock_n = sample_triplanar_world_normal(rock_normal, world_pos, n, tri_weights, rock_scale, eff_normal_str);
		flat_col = mix(flat_col, rock_col, rock_weight);
		flat_rgh = mix(flat_rgh, rock_rgh, rock_weight);
		flat_ao = mix(flat_ao, rock_ao_val, rock_weight);
		flat_n = normalize(mix(flat_n, rock_n, rock_weight));
	}

	// Stochastic macro luminance variation eliminating tiling on distant hills
	float macro_lum = 1.0 + (macro_noise - 0.5) * (macro_luminance_mod * 2.0);
	ALBEDO = flat_col * macro_lum;
	ROUGHNESS = clamp(flat_rgh * 0.85 + 0.12 + roughness_bias * candidate_w * (1.0 - wet_w * shore_w), 0.22, 0.98);
	METALLIC = 0.0;
	SPECULAR = mix(0.35, 0.55, wet_w * shore_w);
	AO = clamp(flat_ao, 0.3, 1.0);
	AO_LIGHT_AFFECT = 0.65;
	NORMAL = normalize((VIEW_MATRIX * vec4(flat_n, 0.0)).xyz);
}
