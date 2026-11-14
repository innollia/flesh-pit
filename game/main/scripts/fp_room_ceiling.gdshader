shader_type spatial;
// The restroom's plain ceiling. Looks like the flat StandardMaterial3D it
// replaces (no texture, no tile grid), but its vertices go through the same
// screen-grid snap as the walls (fdk_ps1_material.gdshader). The walls
// snapped and the ceiling did not, so the two planes parted by up to half a
// grid step along their shared edge and whatever lies outside the room
// showed through as a dotted line. Shared corners must land on the same
// pixel: keep the snap below the same as the kit shader's
// (run_room_furniture_tests.gd compares the two).
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(0.92, 0.92, 0.90, 1.0);
uniform float snap_precision = 130.0;

void vertex() {
    vec4 view_pos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    vec4 clip = PROJECTION_MATRIX * view_pos;
    if (clip.w > 0.0001) {
        vec2 ndc = clip.xy / clip.w;
        float grid = max(snap_precision, 8.0);
        ndc = floor(ndc * grid + 0.5) / grid;
        clip.xy = ndc * clip.w;
    }
    POSITION = clip;
}

void fragment() {
    ALBEDO = albedo.rgb;
    ROUGHNESS = 1.0;
}
