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
uniform float press_radius = 1.0;
// Direction from the wall toward the player. The press moves every vertex
// along this one shared direction (never its own NORMAL): flat-shaded faces
// don't share normals, so per-normal offsets tore the mesh open at every
// edge while pressing (2026-09-30). Same position -> same offset, no gaps.
uniform vec3 press_toward = vec3(0.0, 0.0, 1.0);
// Tear snap (2026-11-03 "살이 뿅 뿅 사라짐"): for a moment after a real tear
// the flesh round the fresh hole springs back from the pull and wobbles.
// Only an additive offset of the real published faces: it opens outward
// from the hole and along the same shared direction, never over the hole.
uniform vec3 snap_center = vec3(0.0, -9999.0, 0.0);
uniform vec3 snap_toward = vec3(0.0, 0.0, 1.0);
uniform float snap_age = 99.0;
uniform float snap_radius = 0.9;
// Fresh wounds: the last few real tear holes, wet with blood round their
// rim (xyz = tear centre, w = 0..1 freshness; 0 = unused slot).
uniform vec4 wounds[6];
uniform float wound_radius = 0.6;
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
    // The pull is the grip: the centre is drawn out toward the hand in a
    // tight cone (pf^2) while the skin round it is gathered in, trembling
    // harder as it nears the tear.
    vec3 grip = -pn * pf * (0.16 * dent - 0.34 * pull * pf);
    grip -= side * pf * 0.24 * pull;
    grip += pn * pf * pull * (0.02 + 0.03 * pull) * sin(TIME * 47.0 + pd * 20.0);
    if (snap_age < 0.9) {
        vec3 sn = normalize(snap_toward + vec3(0.0, 1e-5, 0.0));
        vec3 sv = wpos - snap_center;
        float sd = length(sv);
        float sf = smoothstep(snap_radius, 0.12, sd);
        vec3 radial = sv - sn * dot(sv, sn);
        float rl = length(radial);
        radial = rl > 0.0001 ? radial / rl : vec3(0.0);
        float env = exp(-snap_age * 6.5);
        float wob = sin(snap_age * 36.0 - sd * 10.0);
        // rim flaps toward/away along the shared direction and peels open
        grip += sf * env * (sn * 0.09 * wob + radial * 0.06 * (0.65 + 0.35 * wob));
    }
    vec3 off = vec3(0.0);
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
    // The grip/snap only happens at arm's reach in front of the eater, so it
    // gets its own cap: a vertex moves at most so far that it stays 0.45 m
    // from the eye (it can come no nearer than its offset length). The old
    // shared 5.5 cm cap flattened the whole pull at reach distance.
    float grip_limit = clamp(eye_distance - 0.45, 0.0, 0.32);
    grip *= min(1.0, grip_limit / max(length(grip), 0.000001));
    off += grip;
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
    // Fresh wound rims: blood pooled on the torn faces and run down under
    // the hole in uneven drips; glossier than the dry flesh round it.
    float wound = 0.0;
    if (!tile_mode) {
        for (int i = 0; i < 6; i++) {
            vec4 w = wounds[i];
            if (w.w <= 0.0) {
                continue;
            }
            vec3 d = vwpos - w.xyz;
            float drip = fract(sin(floor(vwpos.x * 26.0 + w.x * 7.0) * 91.7) * 4375.85);
            // below the centre the reach stretches into drip streaks
            d.y = d.y < 0.0 ? d.y * mix(0.85, 0.32, drip * drip) : d.y;
            vec3 cell = floor(vwpos * 16.0);
            float blot = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
            float r = wound_radius * (0.8 + 0.35 * blot);
            wound = max(wound, w.w * smoothstep(r, r * 0.45, length(d)));
        }
    }
    // Strain of the grip: the skin round the hands goes taut and pale and
    // its fibres stand out red in rings drawn toward the grip, so the pull
    // reads even where the fists cover the gripped spot itself.
    float tension = 0.0;
    if (press_amount > 0.0 && !tile_mode) {
        vec3 pv = vwpos - press_center;
        float pdist = length(pv);
        tension = smoothstep(0.3, 1.0, press_amount) * smoothstep(press_radius, 0.05, pdist);
        vec3 pnf = normalize(press_toward + vec3(0.0, 1e-5, 0.0));
        vec3 ta = normalize(cross(pnf, abs(pnf.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
        vec3 tb = cross(pnf, ta);
        float ang = atan(dot(pv, tb), dot(pv, ta));
        // uneven fibres: wavering, of mixed width, broken up along their length
        float wav = ang * 17.0 + 1.7 * sin(ang * 5.0 + pdist * 7.0) + pdist * 9.0;
        float seg = fract(sin(floor(wav / 6.2832) * 17.3 + floor(pdist * 7.0) * 3.1) * 4375.85);
        float fib = 0.5 + 0.5 * sin(wav);
        col = mix(col, col * 1.8 + vec3(0.14, 0.03, 0.04), tension * 0.6);
        col = mix(col, vec3(0.42, 0.015, 0.04), tension * tension * smoothstep(0.5, 0.92, fib) * (0.45 + 0.4 * seg));
    }
    col = mix(col, vec3(0.46, 0.02, 0.04), wound * 0.85);
    ALBEDO = mix(col * tint.rgb, fog_color, vfog);
    ROUGHNESS = mix(mix(roughness_value, 0.15, wetness), 0.08, max(wound, tension * 0.7));
    // matte materials (roughness ~1, e.g. restroom tiles) get almost no toon
    // highlight, so the white room stops glaring off every wall
    SPECULAR = mix(mix(0.25, 0.7, wetness) * (1.0 - 0.85 * smoothstep(0.8, 1.0, roughness_value)), 0.9, wound);
    float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
    EMISSION = tex * rim * 0.12 * wetness + vec3(0.09, 0.0, 0.006) * rim * wound;
}
