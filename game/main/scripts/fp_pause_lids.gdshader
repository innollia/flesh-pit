shader_type canvas_item;

// Esc pause as shut eyes (fp_pause_menu.gd): the lids close from above and
// below, and the room shows only as red light through the skin, with the
// lid's own capillaries and a slow heartbeat. The glow behind the focused
// item is the phosphene you get pressing on a closed eye. Drawn at a PS1
// pixel size with the same dither and grain as the other menus.

uniform float close : hint_range(0.0, 1.0) = 0.0;
uniform float beat = 0.0;
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform vec2 glow_pos = vec2(0.5, 0.5);
uniform float glow = 0.0;
uniform float pixel = 3.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
            mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float bayer(vec2 p) {
    int x = int(mod(p.x, 4.0));
    int y = int(mod(p.y, 4.0));
    float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
    return m[x + y * 4] / 16.0 - 0.5;
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * vnoise(p);
        p = p * 2.03 + vec2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

vec2 hash2(vec2 p) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

// Distance to the nearest cell border (F2 - F1): even-width threads.
float cell_edge(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float d1 = 8.0;
    float d2 = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 g = vec2(float(x), float(y));
            vec2 r = g + hash2(i + g) - f;
            float d = dot(r, r);
            if (d < d1) {
                d2 = d1;
                d1 = d;
            } else if (d < d2) {
                d2 = d;
            }
        }
    }
    return sqrt(d2) - sqrt(d1);
}

// Capillaries: the borders of a warped cell net, some segments faded out
// so it branches instead of tiling, and a finer, fainter net between.
float vessels(vec2 p, float swell) {
    vec2 w = vec2(fbm(p * 0.5), fbm(p * 0.5 + vec2(5.2, 1.3)));
    vec2 q = p + (w - 0.5) * 1.6;
    float main = 1.0 - smoothstep(0.03 * swell, 0.075 * swell, cell_edge(q));
    main *= smoothstep(0.3, 0.6, fbm(q * 0.7 + vec2(2.0, 4.0)));
    float fine = 1.0 - smoothstep(0.03, 0.07, cell_edge(q * 2.6 + vec2(7.1, 3.3)));
    fine *= smoothstep(0.45, 0.7, fbm(q * 1.4 + vec2(9.0, 1.0)));
    return max(main, fine * 0.5);
}

// lub-dub
float heart(float t) {
    float f = fract(t * 1.1);
    return exp(-f * 16.0) + 0.55 * step(0.17, f) * exp(-(f - 0.17) * 16.0);
}

void fragment() {
    vec2 cell = floor(UV * rect_size / pixel);
    vec2 uv = (cell + 0.5) * pixel / rect_size;
    float x = uv.x * 2.0 - 1.0;
    float arch = 1.0 - x * x;
    // Lid edges arch toward the middle; both pass it when shut.
    float top = mix(-0.25, 0.56, close) + 0.12 * arch * close;
    float bot = mix(1.25, 0.44, close) - 0.06 * arch * close;
    float soft = 0.03;
    float lid_t = 1.0 - smoothstep(top - soft, top + soft, uv.y);
    float lid_b = smoothstep(bot - soft, bot + soft, uv.y);
    float lid = max(lid_t, lid_b);

    // The room through the skin: blurred, only its brightness survives.
    vec3 scene = vec3(0.0);
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            scene += texture(screen_tex, uv + vec2(float(i), float(j)) * vec2(0.035, 0.06)).rgb;
        }
    }
    scene /= 9.0;
    float lum = dot(scene, vec3(0.3, 0.59, 0.11));
    float pulse = heart(beat);
    vec3 skin = vec3(0.5, 0.07, 0.05) * (0.3 + 1.2 * lum);
    // thicker, darker toward the outside of the lid
    vec2 q = (uv - 0.5) * vec2(1.2, 1.7);
    float vig = clamp(1.0 - 0.8 * pow(length(q), 1.5), 0.06, 1.0);
    skin *= vig * (0.88 + 0.2 * pulse);
    vec2 aspect = vec2(rect_size.x / rect_size.y, 1.0);
    float ves = vessels(uv * aspect * 3.0, 1.0 + 0.2 * pulse);
    skin = mix(skin, skin * vec3(0.34, 0.09, 0.16), ves * 0.65);
    vec2 gd = (uv - glow_pos) * aspect;
    float g = exp(-dot(gd * vec2(0.55, 1.0), gd * vec2(0.55, 1.0)) / 0.012) * glow;
    skin += vec3(0.5, 0.2, 0.07) * g * (0.8 + 0.35 * pulse);
    // the wet rim of each lid catches a little light
    float rim = (1.0 - smoothstep(0.0, 0.012, abs(uv.y - top))) * lid_t
            + (1.0 - smoothstep(0.0, 0.012, abs(uv.y - bot))) * lid_b;
    skin += vec3(0.35, 0.12, 0.1) * rim * (1.0 - close * close);

    // Still open: the room, darkened under the lashes near each edge.
    vec3 room = texture(screen_tex, SCREEN_UV).rgb;
    float lash = smoothstep(0.1, 0.0, uv.y - top) + smoothstep(0.1, 0.0, bot - uv.y);
    room *= (1.0 - 0.3 * close) * (1.0 - 0.5 * clamp(lash, 0.0, 1.0));
    // out-of-focus lashes: a soft, uneven dark fringe off each edge
    float fringe_t = smoothstep(0.07 * (0.5 + vnoise(vec2(uv.x * 26.0, 0.0))), 0.0, uv.y - top) * step(top, uv.y);
    float fringe_b = smoothstep(0.035 * (0.5 + vnoise(vec2(uv.x * 30.0, 5.0))), 0.0, bot - uv.y) * step(uv.y, bot);
    room *= 1.0 - 0.6 * clamp(fringe_t + fringe_b, 0.0, 1.0) * smoothstep(0.05, 0.25, close);

    vec3 c = mix(room, skin, lid);
    float n = hash(cell + floor(TIME * 12.0));
    c += ((n - 0.5) * 0.04 + bayer(cell) * 0.03) * lid;
    c = mix(c, floor(c * 31.0 + 0.5) / 31.0, lid);
    COLOR = vec4(c, 1.0);
}
