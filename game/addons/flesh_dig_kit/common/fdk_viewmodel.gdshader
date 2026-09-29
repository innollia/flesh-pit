shader_type spatial;
// Flesh Dig Kit view-model shader: for things glued to the camera (hands,
// stomach mass). The vertex is pulled toward the eye along its own view ray,
// which keeps its exact screen position but makes its depth much smaller, so
// terrain right in front of the player never cuts through the hands.
// Lighting still uses the true position.
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

uniform float depth_squash = 0.18;
uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness_value = 0.55;
uniform float specular_value = 0.35;
uniform vec4 rim_color : source_color = vec4(0.45, 0.05, 0.05, 1.0);
uniform float rim_strength = 0.25;
uniform float wet = 0.0;

void vertex() {
    vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    v.xyz *= depth_squash;
    POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
    ALBEDO = COLOR.rgb * tint.rgb;
    ROUGHNESS = mix(roughness_value, 0.15, wet);
    SPECULAR = mix(specular_value, 0.8, wet);
    float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
    EMISSION = rim_color.rgb * rim * rim_strength;
}
