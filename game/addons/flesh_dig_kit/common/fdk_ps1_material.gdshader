shader_type spatial;
// PS1-style material shader shared by terrain/hands/props: nearest-filtered
// low-res texture, per-vertex snapping to a coarse grid (the classic PS1
// integer-vertex wobble; no perspective-correct affine warp is simulated
// here on purpose -- Godot's rasterizer is already perspective-correct, so
// texture swim instead comes from vertex snapping moving the UVs slightly
// every frame), no mipmaps, and a fixed few-lights look (single hard key).
// NOTE: no world_vertex_coords -- VERTEX stays in model space so
// MODELVIEW_MATRIX below applies the model transform exactly once (with
// world_vertex_coords it was applied twice, scattering camera-attached
// meshes such as the hands).
render_mode cull_back, diffuse_lambert, specular_toon;

uniform sampler2D albedo_tex : filter_nearest, repeat_enable;
uniform float uv_scale = 1.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float snap_precision = 130.0; // higher = finer grid, lower = chunkier PS1 wobble
uniform float fog_distance = 11.0;
uniform vec3 fog_color : source_color = vec3(0.08, 0.01, 0.02);
uniform float roughness_value = 0.6;
uniform float wetness : hint_range(0.0, 1.0) = 0.4;
// Chew press deformation (design-core 3): dent then stretch toward the
// player as press_amount goes 0..1, matching the old fdk_terrain.gdshader
// behaviour but now on the shared PS1 material.
uniform vec3 press_center = vec3(0.0, -9999.0, 0.0);
uniform float press_amount = 0.0;
uniform float press_radius = 0.75;
// View-model squash (hands, stomach mass): pull vertices toward the eye along
// their view ray so they keep screen position but never clip into nearby
// walls. 1.0 = off (world geometry).
uniform float viewmodel_squash = 1.0;

varying float vfog;

void vertex() {
    vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float pd = distance(wpos, press_center);
    float pf = smoothstep(press_radius, 0.0, pd);
    float pa = press_amount;
    float dent = sin(clamp(pa / 0.55, 0.0, 1.0) * 1.5708) * (1.0 - smoothstep(0.55, 0.9, pa));
    float pull = smoothstep(0.45, 1.0, pa);
    vec3 side = wpos - press_center;
    vec3 off = -NORMAL * pf * (0.16 * dent - 0.26 * pull * pf);
    off -= side * pf * 0.18 * pull;
    off += NORMAL * pf * pull * 0.02 * sin(TIME * 47.0 + pd * 20.0);
    vec3 pushed = VERTEX + (inverse(mat3(MODEL_MATRIX)) * off);
    // Classic PS1 vertex jitter: transform to clip space, snap XY to a
    // coarse integer grid in NDC, transform back. Done here (not as a
    // post shader) so it moves with the object like the real console did.
    vec4 view_pos = MODELVIEW_MATRIX * vec4(pushed, 1.0);
    view_pos.xyz *= viewmodel_squash;
    vec4 clip = PROJECTION_MATRIX * view_pos;
    if (clip.w > 0.0001) {
        vec2 ndc = clip.xy / clip.w;
        float grid = max(snap_precision, 8.0);
        ndc = floor(ndc * grid + 0.5) / grid;
        clip.xy = ndc * clip.w;
    }
    POSITION = clip;
    vfog = clamp(-(MODELVIEW_MATRIX * vec4(pushed, 1.0)).z / max(fog_distance, 0.1), 0.0, 1.0);
}

void fragment() {
    vec2 uv = UV * uv_scale;
    vec3 tex = texture(albedo_tex, uv).rgb;
    vec3 col = use_vertex_color ? tex * COLOR.rgb : tex;
    ALBEDO = mix(col * tint.rgb, fog_color, vfog);
    ROUGHNESS = mix(roughness_value, 0.15, wetness);
    SPECULAR = mix(0.25, 0.7, wetness);
    float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
    EMISSION = tex * rim * 0.12 * wetness;
}
