shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
// Canonical terrain: photographic CC0 albedo/roughness; roughness-derived
// micro-bump is a shading approximation, NOT a missing supplied normal map.
uniform sampler2D ground_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_p;
varying vec3 world_n;

void vertex() {
    world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
vec3 tricolor(sampler2D tex, vec3 p, vec3 w) {
    return texture(tex, p.zy).rgb * w.x
         + texture(tex, p.xz).rgb * w.y
         + texture(tex, p.xy).rgb * w.z;
}
float trimono(sampler2D tex, vec3 p, vec3 w) {
    return texture(tex, p.zy).r * w.x
         + texture(tex, p.xz).r * w.y
         + texture(tex, p.xy).r * w.z;
}
float aggregate_height(vec3 p, vec3 w, float rock) {
    return mix(trimono(ground_roughness, p, w),
               trimono(rock_roughness, p * 0.78, w), rock);
}
float random2(vec2 q) {
    return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
    vec3 n = normalize(world_n);
    vec3 w = pow(abs(n), vec3(5.0));
    w /= max(dot(w, vec3(1.0)), 0.00001);
    vec3 p = world_p * 0.27;
    float slope = 1.0 - abs(n.y);
    float rock = smoothstep(0.18, 0.52, slope);
    float mask = random2(floor(world_p.xz * 0.11));
    rock = clamp(rock + (mask - 0.5) * 0.13, 0.0, 1.0);
    vec3 soil = tricolor(ground_albedo, p, w);
    vec3 stone = tricolor(rock_albedo, p * 0.78, w);
    float duff = 0.5 + 0.5 * sin(world_p.x * 0.16 + sin(world_p.z * 0.08))
                             * sin(world_p.z * 0.20);
    float moss = (1.0 - rock) * smoothstep(0.62, 0.9, duff) * 0.11;
    vec3 base = mix(soil, stone, rock);
    ALBEDO = mix(base, base * vec3(0.52, 0.64, 0.45), moss);
    ALBEDO *= mix(0.92, 1.04, mask);
    float rsoil = trimono(ground_roughness, p, w);
    float rstone = trimono(rock_roughness, p * 0.78, w);
    ROUGHNESS = clamp(mix(rsoil, rstone, rock) * 0.66 + 0.28, 0.58, 1.0);
    // Sample the CC0 surface roughness as small-scale height for shading only.
    // Triplanar world-space gradients avoid requiring a nonexistent tangent map.
    float e = 0.025;
    vec3 g = vec3(
        aggregate_height(p + vec3(e, 0.0, 0.0), w, rock) -
        aggregate_height(p - vec3(e, 0.0, 0.0), w, rock),
        aggregate_height(p + vec3(0.0, e, 0.0), w, rock) -
        aggregate_height(p - vec3(0.0, e, 0.0), w, rock),
        aggregate_height(p + vec3(0.0, 0.0, e), w, rock) -
        aggregate_height(p - vec3(0.0, 0.0, e), w, rock)
    ) / (2.0 * e);
    g -= n * dot(g, n);
    vec3 bumped = normalize(n - g * 0.36);
    NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);
    METALLIC = 0.0;
    SPECULAR = 0.32;
}
