shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform vec4 paint_color : source_color = vec4(0.75, 0.73, 0.61, 1.0);
varying vec3 surface_p;
void vertex() {
    surface_p = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
}
float hash2(vec2 p) {
    return fract(sin(dot(p,vec2(91.4,247.3)))*45381.247);
}
float noise2(vec2 p) {
    vec2 i=floor(p), f=fract(p);
    f=f*f*(3.0-2.0*f);
    return mix(mix(hash2(i),hash2(i+vec2(1.0,0.0)),f.x),
               mix(hash2(i+vec2(0.0,1.0)),hash2(i+vec2(1.0,1.0)),f.x),f.y);
}
void fragment() {
    float worn = noise2(surface_p.xz * 1.8);
    float hairline = hash2(floor(surface_p.xz*21.0));
    float flake = smoothstep(0.66,0.83,worn) * smoothstep(0.54,0.89,hairline);
    ALBEDO = paint_color.rgb * (0.76 + 0.20*noise2(surface_p.xz*0.13));
    ROUGHNESS = 0.84;
    SPECULAR = 0.24;
    METALLIC = 0.0;
    ALPHA = 1.0 - flake;
    ALPHA_SCISSOR_THRESHOLD = 0.45;
}
