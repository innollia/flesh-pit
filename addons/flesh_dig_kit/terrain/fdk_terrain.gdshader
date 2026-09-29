shader_type spatial;
// Flesh Dig Kit terrain shader: vertex colours, wet flesh (tight glossy
// highlights, sheen that drifts), and the chew press: vertices near
// press_center are first pushed in (dent) then pulled out toward the
// player (stretch) as press_amount goes 0 -> 1, with a tremble near the end.
// Normals stay per-face, so the facets keep their hard low-poly look.
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec3 press_center = vec3(0.0, -9999.0, 0.0);
uniform vec3 press_dir = vec3(0.0, 0.0, 1.0);
uniform float press_amount = 0.0;
uniform float press_radius = 0.75;
uniform float wetness : hint_range(0.0, 1.0) = 0.85;

varying vec3 wpos;

void vertex() {
    vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float d = distance(w, press_center);
    float f = smoothstep(press_radius, 0.0, d);
    float a = press_amount;
    float dent = sin(clamp(a / 0.55, 0.0, 1.0) * 1.5708) * (1.0 - smoothstep(0.55, 0.9, a));
    float pull = smoothstep(0.45, 1.0, a);
    vec3 off = press_dir * f * (-0.16 * dent + 0.26 * pull * f);
    // sideways stretch toward the grab point, then a tremble before the tear
    vec3 side = w - press_center;
    off -= side * f * 0.18 * pull;
    off += press_dir * f * pull * 0.02 * sin(TIME * 47.0 + d * 20.0);
    VERTEX += off;
    wpos = w + off;
}

void fragment() {
    ALBEDO = COLOR.rgb;
    float sheen = 0.5 + 0.5 * sin(wpos.x * 5.3 + wpos.y * 3.7 + TIME * 0.6) * sin(wpos.z * 4.1 - TIME * 0.4);
    ROUGHNESS = mix(0.62, 0.2, wetness * sheen);
    SPECULAR = mix(0.3, 0.6, wetness);
    float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
    EMISSION = COLOR.rgb * rim * 0.18 * wetness;
}
