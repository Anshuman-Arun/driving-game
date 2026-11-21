shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.12, 0.19, 0.06);
uniform vec3 tip_color : source_color = vec3(0.32, 0.40, 0.13);
uniform vec3 dry_tip_color : source_color = vec3(0.48, 0.42, 0.16);
uniform float wind_strength = 0.14;
uniform float wind_speed = 1.65;

varying float v_height_t;
varying vec4 v_custom;

void vertex() {
	// UV.y = 0 at root, 1 at tip
	v_height_t = clamp(UV.y, 0.0, 1.0);
	v_custom = INSTANCE_CUSTOM;

	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = sin(wp.x * 0.18 + wp.z * 0.12 + TIME * wind_speed)
		+ 0.5 * cos(wp.x * 0.42 - wp.z * 0.35 + TIME * wind_speed * 1.7);
	float bend = v_height_t * v_height_t * wind_strength * (0.7 + 0.6 * v_custom.y);
	VERTEX.x += gust * bend;
	VERTEX.z += gust * bend * 0.55;

	// Tilt normal upward for lush soft shading across crossed blades
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.72));
}

void fragment() {
	vec3 tip = mix(tip_color, dry_tip_color, v_custom.x);
	vec3 col = mix(base_color, tip, smoothstep(0.05, 0.95, v_height_t));
	col *= (0.78 + 0.38 * v_custom.z);

	// Root ambient occlusion
	float ao = mix(0.48, 1.0, smoothstep(0.0, 0.65, v_height_t));

	ALBEDO = col;
	AO = ao;
	ROUGHNESS = 0.68;
	METALLIC = 0.0;
	SPECULAR = 0.22;
	BACKLIGHT = tip * 0.42 * v_height_t;
}
