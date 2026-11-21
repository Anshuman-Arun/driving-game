shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}
void fragment() {
	vec2 uv = UV * vec2(1.2, 0.9);
	vec3 asphalt = texture(asphalt_albedo, uv).rgb;
	float base_roughness = texture(asphalt_roughness, uv).r;
	float across = UV.x / 2.3333333;
	float edge_dust = smoothstep(0.32, 0.02, min(across, 1.0 - across));
	float wheel_polish = exp(-pow((across - 0.25) * 12.0, 2.0))
		+ exp(-pow((across - 0.75) * 12.0, 2.0));
	float fine = hash2(floor(world_position.xz * 7.0));
	float sparse_cracks = step(0.995, hash2(floor(world_position.xz * 0.33))) * 0.1;
	ALBEDO = asphalt * (0.93 + 0.075 * fine - 0.035 * wheel_polish - sparse_cracks);
	ALBEDO = mix(ALBEDO, vec3(0.19, 0.17, 0.14), edge_dust * 0.34);
	ROUGHNESS = clamp(base_roughness * 0.65 + 0.25 + edge_dust * 0.10, 0.6, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.26;
}
