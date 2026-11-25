shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Multi-layer Automotive Lacquer Paint Shader (Godot 4 Forward+)
// Recreates Forza Horizon / Gran Turismo style multi-stage automotive paint:
// 1. Base metallic substrate with dual-tone Fresnel color shift
// 2. Pearlescent micro-flake luster layer (smooth metallic depth without white speckles)
// 3. Mirror-smooth top clearcoat lacquer layer with independent roughness

group_uniforms BaseCoat;
uniform vec4 base_color : source_color = vec4(0.50, 0.04, 0.07, 1.0); // Rich deep crimson (#800A12)
uniform vec4 grazing_color : source_color = vec4(0.95, 0.22, 0.10, 1.0); // Fiery warm specular grazing tone (#F2381A)
uniform float fresnel_power : hint_range(0.5, 8.0, 0.1) = 2.6;
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.80;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.70;

group_uniforms PearlescentFlake;
uniform float flake_intensity : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float flake_scale : hint_range(50.0, 800.0, 1.0) = 320.0;
uniform vec4 flake_color : source_color = vec4(0.85, 0.18, 0.10, 1.0); // Pearlescent warm metallic tint, not white!

group_uniforms ClearCoat;
uniform float clearcoat : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float clearcoat_roughness : hint_range(0.0, 1.0, 0.01) = 0.04;

group_uniforms Textures;
uniform sampler2D albedo_texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_scale : hint_range(0.0, 2.0, 0.01) = 0.0;

varying vec3 v_local_pos;
varying vec3 v_world_normal;

void vertex() {
	v_local_pos = VERTEX;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Base texture modulation (if present)
	vec4 tex_albedo = texture(albedo_texture, UV);

	// Normal mapping (if assigned)
	if (normal_scale > 0.001) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}

	// Dual-tone Fresnel color shift driven by dot(NORMAL, VIEW)
	// Normal and VIEW in Godot 4 fragment are in View Space (VIEW = normalize(-VERTEX))
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float n_dot_v = clamp(dot(n, v), 0.0, 1.0);
	float fresnel = pow(1.0 - n_dot_v, fresnel_power);

	// Deep base coat transitioning smoothly to warm grazing glow
	vec3 paint_color = mix(base_color.rgb, grazing_color.rgb, fresnel) * tex_albedo.rgb;

	// High-frequency pearlescent metallic micro-shimmer:
	// Uses high-speed sine-product coordinates to simulate fine metallic flake orientation
	// without any white speckles or heavy 3D lattice loops.
	if (flake_intensity > 0.001) {
		vec3 p = v_local_pos * flake_scale;
		float shimmer = sin(p.x * 2.3 + p.y * 3.1) * cos(p.y * 2.7 + p.z * 1.9) * sin(p.z * 3.7 + p.x * 1.4);
		shimmer = shimmer * 0.5 + 0.5; // normalize to [0, 1]
		float glint = pow(shimmer, 6.0) * n_dot_v;
		paint_color = mix(paint_color, flake_color.rgb, glint * flake_intensity);
	}

	// Output PBR channels
	ALBEDO = paint_color;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;

	// Automotive Clearcoat lacquer layer (Forward+ high-gloss topcoat)
	CLEARCOAT = clearcoat;
	CLEARCOAT_ROUGHNESS = clearcoat_roughness;
}
