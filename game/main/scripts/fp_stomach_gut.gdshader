shader_type canvas_item;

// Stomach gauge (fp_stomach_hud.gd): a length of gut filling with chewed
// flesh from the left. Past capacity it swells unevenly, its wall stretches
// pale with stretch marks and it squeezes faster. Pixelated and dithered
// like the PS1 post, since the HUD sits above that pass.

uniform float fill = 0.0;
uniform float over = 0.0;
uniform float time = 0.0;
uniform vec2 rect_size = vec2(240.0, 48.0);
uniform float pixel = 2.0;

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

void fragment() {
    vec2 cell = floor(UV * rect_size / pixel);
    vec2 p = (cell + 0.5) * pixel;
    float r0 = rect_size.y * 0.22;
    float left = r0 + 4.0;
    float right = rect_size.x - r0 - 4.0;
    float u = clamp((p.x - left) / (right - left), 0.0, 1.0);
    float rate = 2.5 + 6.0 * over;
    float squeeze = sin(u * 16.0 - time * rate);
    float lumps = vnoise(vec2(u * 8.0, time * 0.4));
    // swells where it is full; overfull it bulges in lumps
    float full_here = smoothstep(fill + 0.04, fill - 0.04, u);
    // gut segments: pinched every so often, the pinches ride the squeeze
    float pinch = smoothstep(0.8, 1.0, cos((u * 7.0 - time * rate * 0.02) * 6.2832));
    float t = r0 * (0.85 + 0.15 * full_here + over * (0.5 + 0.7 * lumps) * full_here
            + 0.07 * squeeze * (0.3 + over));
    t *= 1.0 - 0.22 * pinch * (1.0 - 0.6 * over);
    t = min(t, rect_size.y * 0.46);
    float cy = rect_size.y * 0.5 + sin(u * 4.5 + time * 0.6) * 1.2;
    vec2 a = vec2(left, cy);
    vec2 b = vec2(right, cy);
    float d = length(p - mix(a, b, u)) - t;

    vec4 col = vec4(0.0);
    // soft shadow so it reads on white tile and dark flesh alike
    col = vec4(0.04, 0.0, 0.01, 0.55 * smoothstep(5.0, 0.0, d));
    if (d < 0.0) {
        float y = (p.y - cy) / t; // -1 top .. 1 bottom
        // chewed flesh, drifting toward the far end and squeezed along
        vec2 q = p * 0.22 + vec2(-time * 1.2, 0.0);
        float n = vnoise(q) * 0.65 + vnoise(q * 2.7) * 0.35;
        vec3 meat = mix(vec3(0.3, 0.02, 0.05), vec3(0.74, 0.13, 0.12), n);
        meat = mix(meat, vec3(0.86, 0.6, 0.45), step(0.83, vnoise(p * 0.45 + vec2(-time * 1.2 * 2.0, 3.0))) * 0.7);
        meat *= 0.82 + 0.18 * squeeze;
        meat = mix(meat, vec3(0.95, 0.2, 0.12), over * 0.35 * (0.5 + 0.5 * squeeze));
        vec3 empty = vec3(0.17, 0.045, 0.055) + vec3(0.06, 0.0, 0.0) * vnoise(p * 0.15);
        float front = fill + 0.018 * sin(p.y * 0.7 + time * 4.0);
        vec3 inside = u <= front && fill > 0.001 ? meat : empty;
        // rounder: darker toward the sides of the tube
        inside *= 1.0 - 0.45 * y * y;
        // the gut wall: pink membrane, stretched paler with marks when over
        float wall = smoothstep(-3.2, -1.6, d);
        vec3 wall_c = mix(vec3(0.72, 0.36, 0.36), vec3(0.95, 0.76, 0.7), over);
        float marks = smoothstep(0.82, 0.97, abs(sin(p.x * 0.55 + vnoise(p * 0.1) * 3.0))) * over * step(0.0, -y);
        inside = mix(inside, wall_c, max(wall, marks * 0.6));
        inside *= 1.0 - 0.3 * pinch;
        // wet highlight along the top
        inside += vec3(0.5, 0.4, 0.38) * smoothstep(0.25, 0.0, abs(y + 0.6)) * 0.35;
        col = vec4(inside, u <= front ? 1.0 : 0.9);
    }
    col.rgb += bayer(cell) * 0.035 + (hash(cell + floor(time * 10.0)) - 0.5) * 0.03;
    col.rgb = floor(col.rgb * 24.0 + 0.5) / 24.0;
    COLOR = col;
}
