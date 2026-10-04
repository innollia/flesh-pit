shader_type spatial;
// Terrain-only PS1 material: nearest-filtered
// low-res texture, per-vertex snapping to a coarse grid (the classic PS1
// integer-vertex wobble; no perspective-correct affine warp is simulated
// here on purpose -- Godot's rasterizer is already perspective-correct, so
// texture swim instead comes from vertex snapping moving the UVs slightly
// every frame), no mipmaps, and a fixed few-lights look (single hard key).
// NOTE: no world_vertex_coords -- VERTEX stays in model space so
// MODELVIEW_MATRIX below applies the model transform exactly once (with
// world_vertex_coords it was applied twice, scattering camera-attached
// meshes such as the hands).
// Only terrain has a solid interior: a near eye or a bent facet can see its
// reverse side. Props, hands and title retain the shared one-sided shader.
render_mode cull_disabled, diffuse_lambert, specular_toon;

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
// Direction from the wall toward the player. The press moves every vertex
// along this one shared direction (never its own NORMAL): flat-shaded faces
// don't share normals, so per-normal offsets tore the mesh open at every
// edge while pressing (2026-09-30). Same position -> same offset, no gaps.
uniform vec3 press_toward = vec3(0.0, 0.0, 1.0);
// View-model squash (hands, stomach mass): pull vertices toward the eye along
// their view ray so they keep screen position but never clip into nearby
// walls. 1.0 = off (world geometry).
uniform float viewmodel_squash = 1.0;

// Flat tile mode (restroom walls/floor): the wall is a few big planes and the
// tile grid -- grout lines, bevelled raised tiles, per-tile tint -- comes from
// a procedurally baked normal+grout texture sampled in world space
// (tile_tex: RG = tangent normal xy, B = grout/edge shade, A unused).
uniform bool tile_mode = false;
uniform sampler2D tile_tex : filter_linear, repeat_enable;
uniform float tile_size = 0.3;
uniform vec2 tile_dimensions = vec2(0.0);
uniform vec3 tile_offset = vec3(0.0);
uniform vec3 grout_color : source_color = vec3(0.52, 0.55, 0.58);

// Shared living-tissue deformation: terrain and title use this same motion.
uniform float organic_motion = 0.0;
uniform float motion_clock = -1.0;
uniform bool fit_room_seams = false;
uniform vec3 room_half = vec3(1.1, 1.3, 1.5);
varying float vfog;
varying vec3 vwpos;
varying vec3 vwnrm;

void vertex() {
    vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float pd = distance(wpos, press_center);
    float pf = smoothstep(press_radius, 0.0, pd);
    float pa = press_amount;
    float dent = sin(clamp(pa / 0.55, 0.0, 1.0) * 1.5708) * (1.0 - smoothstep(0.55, 0.9, pa));
    float pull = smoothstep(0.45, 1.0, pa);
    vec3 side = wpos - press_center;
    vec3 pn = normalize(press_toward + vec3(0.0, 1e-5, 0.0));
    vec3 off = -pn * pf * (0.16 * dent - 0.26 * pull * pf);
    off -= side * pf * 0.18 * pull;
    off += pn * pf * pull * 0.02 * sin(TIME * 47.0 + pd * 20.0);
    if (organic_motion > 0.0) {
        float clock = motion_clock < 0.0 ? TIME : motion_clock;
        float moving = organic_motion;
        if (fit_room_seams && !(wpos.z > room_half.z - 0.25 && abs(wpos.x) < 0.57 && wpos.y > 0.1 && wpos.y < 1.97)) {
            vec3 q = abs(wpos - vec3(0.0, room_half.y, 0.0)) - room_half;
            moving *= smoothstep(0.07, 0.4, max(q.x, max(q.y, q.z)));
        }
        off += moving * vec3(0.055 * sin(wpos.y * 4.0 + clock * 0.8) + 0.035 * sin(wpos.x * 3.0 + clock * 0.4),
            0.05 * sin(wpos.x * 4.0 + clock * 0.7),
            0.10 * sin(wpos.x * 2.3 + clock * 0.45) * cos(wpos.y * 3.4 - clock * 0.3));
    }
    // The eye sits inside the capsule near its upper cap, while these
    // visual offsets are absent from the CPU collider. Keep nearby motion
    // within that physical clearance. This uses positions (not flat face
    // normals), so tissue/chunk duplicates receive exactly the same cap.
    float eye_distance = distance(wpos, CAMERA_POSITION_WORLD);
    float motion_limit = mix(0.055, 0.5, smoothstep(1.5, 2.0, eye_distance));
    off *= min(1.0, motion_limit / max(length(off), 0.000001));
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
    vwpos = wpos;
    vwnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
    vfog = clamp(-(MODELVIEW_MATRIX * vec4(pushed, 1.0)).z / max(fog_distance, 0.1), 0.0, 1.0);
}

void fragment() {
    vec2 uv = UV * uv_scale;
    vec3 tex = texture(albedo_tex, uv).rgb;
    vec3 col = use_vertex_color ? tex * COLOR.rgb : tex;
    if (tile_mode) {
        vec3 an = abs(vwnrm);
        vec3 wp = vwpos + tile_offset;
        // dominant axis, then a right-handed (ta, tb, n) frame so the bevel
        // lights the same way on every wall
        vec3 nax = an.y > an.x && an.y > an.z ? vec3(0.0, sign(vwnrm.y), 0.0)
            : (an.x > an.z ? vec3(sign(vwnrm.x), 0.0, 0.0) : vec3(0.0, 0.0, sign(vwnrm.z)));
        vec3 tb = abs(nax.y) > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
        vec3 ta = cross(tb, nax);
        vec2 tuv = vec2(dot(wp, ta), dot(wp, tb));
        vec2 g = tuv / (tile_dimensions.x > 0.0 ? tile_dimensions : vec2(tile_size));
        vec2 cell = floor(g);
        vec4 t = texture(tile_tex, g);
        vec2 nxy = t.rg * 2.0 - 1.0;
        vec3 wn = normalize(ta * nxy.x + tb * nxy.y + vwnrm * sqrt(max(0.0, 1.0 - dot(nxy, nxy))));
        NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
        float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
        col = mix(vec3(0.88, 0.87, 0.84) * (1.0 - h * 0.025), grout_color, t.b);
    }
    ALBEDO = mix(col * tint.rgb, fog_color, vfog);
    ROUGHNESS = mix(roughness_value, 0.15, wetness);
    // matte materials (roughness ~1, e.g. restroom tiles) get almost no toon
    // highlight, so the white room stops glaring off every wall
    SPECULAR = mix(0.25, 0.7, wetness) * (1.0 - 0.85 * smoothstep(0.8, 1.0, roughness_value));
    float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
    EMISSION = tex * rim * 0.12 * wetness;
}
