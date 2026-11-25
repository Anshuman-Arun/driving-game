shader_type canvas_item;
render_mode unshaded;

// Screen texture sampler for post-processing in Godot 4
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// Master enable and dynamic intensity (driven by car speed 0.0 to 1.0)
uniform bool blur_enabled = true;
uniform float speed_intensity : hint_range(0.0, 1.0) = 0.0;

// Radial blur parameters
uniform float blur_strength : hint_range(0.0, 0.12) = 0.038;
uniform int sample_count : hint_range(4, 32) = 14;

// Elliptical center mask (keeps the hero car sharp and readable)
uniform vec2 blur_center = vec2(0.5, 0.58);
uniform vec2 mask_radius = vec2(0.24, 0.18);
uniform float mask_feather : hint_range(0.01, 0.5) = 0.14;

// Subtle high-speed chromatic aberration along streak lines
uniform float chromatic_aberration : hint_range(0.0, 0.02) = 0.0035;

void fragment() {
	if (!blur_enabled || speed_intensity <= 0.001) {
		COLOR = textureLod(screen_texture, SCREEN_UV, 0.0);
	} else {
		vec2 diff = SCREEN_UV - blur_center;
		
		// Elliptical normalized distance
		vec2 norm_diff = diff / max(mask_radius, vec2(0.001));
		float dist_sq = dot(norm_diff, norm_diff);
		float ellipse_dist = sqrt(dist_sq);
		
		// Masking: 0.0 inside the car bounds (sharp hero car), 1.0 outside (full blur)
		float mask = smoothstep(1.0, 1.0 + mask_feather, ellipse_dist);
		float effective_blur = blur_strength * speed_intensity * mask;
		
		if (effective_blur <= 0.0001) {
			COLOR = textureLod(screen_texture, SCREEN_UV, 0.0);
		} else {
			vec4 accum = vec4(0.0);
			float total_weight = 0.0;
			float step_size = 1.0 / float(sample_count - 1);
			float chroma_offset = chromatic_aberration * speed_intensity * mask;

			for (int i = 0; i < sample_count; i++) {
				float t = float(i) * step_size;
				// Quadratic weighting towards current pixel keeps high frequencies intact
				float weight = 1.0 - t * 0.4;
				vec2 sample_uv = SCREEN_UV - diff * (t * effective_blur);
				
				if (chroma_offset > 0.0001) {
					vec2 uv_r = sample_uv - diff * (chroma_offset * t);
					vec2 uv_b = sample_uv + diff * (chroma_offset * t);
					float r = textureLod(screen_texture, uv_r, 0.0).r;
					float g = textureLod(screen_texture, sample_uv, 0.0).g;
					float b = textureLod(screen_texture, uv_b, 0.0).b;
					accum += vec4(r, g, b, 1.0) * weight;
				} else {
					accum += textureLod(screen_texture, sample_uv, 0.0) * weight;
				}
				total_weight += weight;
			}

			COLOR = accum / total_weight;
		}
	}
}
