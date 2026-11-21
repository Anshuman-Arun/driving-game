shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Scanned CC0 material channels, project-owned heightfield and zero collision.
uniform sampler2D ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 terrain_world_position;
varying vec3 terrain_world_normal;

void vertex() {
	terrain_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	terrain_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

vec3 triplanar_rgb(sampler2D sampler, vec3 p, vec3 blend) {
	return texture(sampler, p.zy).rgb * blend.x
		+ texture(sampler, p.xz).rgb * blend.y
		+ texture(sampler, p.xy).rgb * blend.z;
}

float triplanar_rough(sampler2D sampler, vec3 p, vec3 blend) {
	return texture(sampler, p.zy).r * blend.x
		+ texture(sampler, p.xz).r * blend.y
		+ texture(sampler, p.xy).r * blend.z;
}

void fragment() {
	vec3 n = normalize(terrain_world_normal);
	vec3 w = pow(abs(n), vec3(6.0));
	w /= max(w.x + w.y + w.z, 0.0001);
	vec3 p = terrain_world_position * 0.27;
	vec3 soil = triplanar_rgb(ground_albedo, p, w);
	vec3 stone = triplanar_rgb(rock_albedo, p * 0.78, w);
	float slope = 1.0 - abs(n.y);
	float rock_amount = smoothstep(0.22, 0.66, slope);
	float mottling = 0.045 * sin(terrain_world_position.x * 0.38 + terrain_world_position.z * 0.17);
	ALBEDO = mix(soil, stone, clamp(rock_amount + mottling, 0.0, 1.0));
	float rsoil = triplanar_rough(ground_roughness, p, w);
	float rstone = triplanar_rough(rock_roughness, p * 0.78, w);
	ROUGHNESS = clamp(mix(rsoil, rstone, rock_amount) * 0.6 + 0.36, 0.68, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.27;
}
