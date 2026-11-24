shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Multi-layer Automotive Lacquer Paint Shader (Godot 4 Forward+)
// Recreates Forza Horizon / Gran Turismo style multi-stage automotive paint:
// 1. Base metallic substrate with dual-tone Fresnel color shift
// 2. High-frequency procedural metallic micro-flake sparkle glitter layer
// 3. Mirror-smooth top clearcoat layer with independent roughness

group_uniforms BaseCoat;
uniform vec4 base_color : source_color = vec4(0.478, 0.039, 0.063, 1.0); // Rich deep crimson (#7A0A10)
uniform vec4 grazing_color : source_color = vec4(1.0, 0.271, 0.125, 1.0); // Warm fiery specular grazing tone (#FF4520)
uniform float fresnel_power : hint_range(0.5, 8.0, 0.1) = 2.8;
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.75;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.65;

group_uniforms MicroFlakes;
uniform float flake_intensity : hint_range(0.0, 2.0, 0.01) = 0.45;
uniform float flake_scale : hint_range(50.0, 600.0, 1.0) = 240.0;
uniform float flake_jitter : hint_range(0.0, 1.0, 0.01) = 0.65;
uniform vec4 flake_color : source_color = vec4(1.0, 0.92, 0.85, 1.0);

group_uniforms ClearCoat;
uniform float clearcoat : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float clearcoat_roughness : hint_range(0.0, 1.0, 0.01) = 0.05;

group_uniforms Textures;
uniform sampler2D albedo_texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_scale : hint_range(0.0, 2.0, 0.01) = 1.0;

varying vec3 v_local_pos;
varying vec3 v_local_normal;
varying vec3 v_world_normal;
varying vec3 v_local_view;

// Pseudo-random 3D hash for lattice cellular noise
vec3 hash33(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195));
	p += dot(p, p.yxz + 19.19);
	return fract((p.xxy + p.yxx) * p.zyx) * 2.0 - 1.0;
}

// Micro-flake glitter sparkle calculation in surface local coordinates
float evaluate_micro_flakes(vec3 pos, vec3 surf_normal, vec3 view_dir) {
	vec3 p = pos * flake_scale;
	vec3 ip = floor(p);
	vec3 fp = fract(p);

	float max_sparkle = 0.0;
	// Sample 2x2x2 lattice points
	for (int z = 0; z <= 1; z++) {
		for (int y = 0; y <= 1; y++) {
			for (int x = 0; x <= 1; x++) {
				vec3 cell_offset = vec3(float(x), float(y), float(z));
				vec3 cell = ip + cell_offset;
				vec3 rnd = hash33(cell);

				// Perturb flake normal based on pseudo-random facet orientation
				vec3 flake_norm = normalize(surf_normal + rnd * flake_jitter);

				// View-dependent glint: sparkles flash as view angle sweeps across flake facet
				float ndv = clamp(dot(flake_norm, view_dir), 0.0, 1.0);
				float glint = pow(ndv, 28.0);

				// Soft radial distance falloff within cell
				vec3 center_vec = cell_offset + rnd * 0.35 - fp;
				float dist_sq = dot(center_vec, center_vec);
				float cell_mask = clamp(1.0 - dist_sq * 1.5, 0.0, 1.0);

				float sparkle = glint * cell_mask;
				if (sparkle > max_sparkle) {
					max_sparkle = sparkle;
				}
			}
		}
	}
	return max_sparkle;
}

void vertex() {
	v_local_pos = VERTEX;
	v_local_normal = NORMAL;

	// Compute world normal and view direction in local model space
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 cam_pos_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	v_local_view = normalize(cam_pos_local - VERTEX);
}

void fragment() {
	// Base texture modulation (if present)
	vec4 tex_albedo = texture(albedo_texture, UV);

	// Normal mapping (if assigned)
	if (normal_scale > 0.001) {
		vec3 n_map = texture(normal_texture, UV).rgb * 2.0 - 1.0;
		NORMAL_MAP = n_map;
		NORMAL_MAP_DEPTH = normal_scale;
	}

	// Dual-tone Fresnel color shift driven by dot(NORMAL, VIEW)
	// Normal and VIEW in Godot 4 fragment are in View Space (VIEW = normalize(-VERTEX))
	float n_dot_v = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - n_dot_v, fresnel_power);

	// Blend deep face-on red with bright warm grazing specular tone
	vec3 paint_color = mix(base_color.rgb, grazing_color.rgb, fresnel) * tex_albedo.rgb;

	// Procedural metallic micro-flake sparkle glitter layer
	float flake_sparkle = 0.0;
	if (flake_intensity > 0.001) {
		vec3 local_norm = normalize(v_local_normal);
		vec3 local_view = normalize(v_local_view);
		flake_sparkle = evaluate_micro_flakes(v_local_pos, local_norm, local_view);
	}

	// Add sparkling flake glints to the base layer
	paint_color += flake_color.rgb * (flake_sparkle * flake_intensity);

	// Output PBR channels:
	ALBEDO = paint_color;
	METALLIC = metallic;
	// Micro-flakes slightly perturb the surface roughness at glint centers
	ROUGHNESS = clamp(roughness - flake_sparkle * 0.08, 0.04, 1.0);
	SPECULAR = specular + flake_sparkle * 0.15;

	// Automotive Clearcoat lacquer layer (Forward+ high-gloss topcoat)
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
}
