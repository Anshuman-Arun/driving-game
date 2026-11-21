shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D asphalt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
// UV.x is across a 7m road / 3m repeat; UV.y follows route arc length / 3m.
varying vec3 road_world_p;
varying vec3 road_world_n;
varying vec3 road_world_t;
varying vec3 road_world_b;
void vertex() {
    road_world_p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    road_world_n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    road_world_t = normalize((MODEL_MATRIX * vec4(TANGENT, 0.0)).xyz);
    road_world_b = normalize(cross(road_world_n, road_world_t));
}
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise21(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i+vec2(1.0,0.0)), f.x),
               mix(hash21(i+vec2(0.0,1.0)), hash21(i+vec2(1.0,1.0)), f.x), f.y);
}
void fragment() {
    vec2 tiled = UV;
    vec3 base = texture(asphalt_albedo, tiled).rgb;
    float rough = texture(asphalt_roughness, tiled).r;
    float across = clamp(UV.x / (7.0 / 3.0), 0.0, 1.0);
    float edge = 1.0 - smoothstep(0.025, 0.20, min(across, 1.0-across));
    float traffic = exp(-pow((across-0.245)*12.0,2.0)) +
                    exp(-pow((across-0.755)*12.0,2.0));
    float stain = noise21(road_world_p.xz*0.09);
    float patches = smoothstep(0.63,0.82,noise21(road_world_p.xz*0.29));
    float chips = hash21(floor(road_world_p.xz*11.0));
    float aggregate = (chips-0.5)*0.065;
    vec3 worn = base * (0.88 + 0.19*stain + aggregate - 0.065*traffic);
    worn = mix(worn, worn*0.70, patches*0.28);
    ALBEDO = mix(worn, vec3(0.20,0.185,0.16),edge*0.21);
    ROUGHNESS = clamp(rough*0.60 + 0.28 + edge*0.11 - traffic*0.025 + patches*0.06,0.50,0.99);
    // Detail normal reconstructed from surviving CC0 roughness microstructure;
    // source asphalt normal is still NOT included in the asset manifest.
    float e = 1.0/1024.0;
    float dhx = texture(asphalt_roughness,tiled+vec2(e,0.0)).r
              - texture(asphalt_roughness,tiled-vec2(e,0.0)).r;
    float dhy = texture(asphalt_roughness,tiled+vec2(0.0,e)).r
              - texture(asphalt_roughness,tiled-vec2(0.0,e)).r;
    vec3 n = normalize(road_world_n - road_world_t*dhx*0.95 - road_world_b*dhy*0.95);
    NORMAL = normalize((VIEW_MATRIX * vec4(n,0.0)).xyz);
    METALLIC = 0.0;
    SPECULAR = 0.32;
}
