shader_type canvas_item;

// The mouse-only vomit button (vomit_button.gd): a puckered wet mouth at
// the end of the stomach gauge. It gags open as the stomach overfills and
// bile runs out of it. Pixelated and dithered like the gauge.

uniform float open = 0.0;
uniform float alpha = 1.0;
uniform float time = 0.0;
uniform float hover = 0.0;
uniform vec2 rect_size = vec2(60.0, 60.0);
uniform float pixel = 2.0;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float bayer(vec2 p) {
    int x = int(mod(p.x, 4.0));
    int y = int(mod(p.y, 4.0));
    float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
    return m[x + y * 4] / 16.0 - 0.5;
}

void fragment() {
    vec2 cell = floor(UV * rect_size / pixel);
    vec2 p = (cell + 0.5) * pixel - rect_size * 0.5;
    float R = min(rect_size.x, rect_size.y) * 0.42;
    float gag = max(0.0, sin(time * 5.0)) * open;
    R *= 1.0 + 0.05 * gag + 0.04 * hover;
    vec2 q = p / vec2(1.0, 0.9);
    float r = length(q);
    float ang = atan(q.y, q.x);
    // the opening: a wobbly slit that opens toward round
    float ow = mix(0.5, 0.62, open) * R;
    float oh = mix(0.06, 0.38, open) * R * (1.0 + 0.2 * gag);
    float hole = length(q / vec2(ow, oh)) - 1.0;
    vec4 col = vec4(0.04, 0.0, 0.01, 0.5 * smoothstep(R + 5.0, R, r));
    if (r < R) {
        // lips: puckered, creased toward the hole
        float crease = smoothstep(0.55, 1.0, abs(sin(ang * 7.0 + r * 0.15)));
        vec3 lip = mix(vec3(0.62, 0.2, 0.22), vec3(0.88, 0.5, 0.48), smoothstep(R, R * 0.35, r));
        lip *= 1.0 - 0.35 * crease * smoothstep(R * 0.2, R * 0.8, r);
        lip += vec3(0.4, 0.3, 0.28) * smoothstep(0.3, 0.0, abs(q.y / R + 0.45)) * 0.35;
        lip *= 1.0 - 0.5 * smoothstep(R * 0.75, R, r);
        col = vec4(lip, 1.0);
        if (hole < 0.0) {
            col.rgb = mix(vec3(0.07, 0.0, 0.01), vec3(0.2, 0.03, 0.04), smoothstep(-1.0, 0.0, hole));
        }
    }
    // bile out of the bottom of the mouth, down past the lip
    float drip_len = R * (0.5 + 0.7 * fract(time * 0.7)) * open;
    float dx = abs(p.x + sin(p.y * 0.2) * 1.5);
    float tip = oh + drip_len;
    float in_drip = step(0.0, p.y - oh * 0.3) * step(p.y, tip) * step(dx, 3.4)
            + step(length(p - vec2(0.0, tip)), 4.6);
    if (in_drip > 0.5 && open > 0.05) {
        col = vec4(vec3(0.6, 0.68, 0.16) + 0.2 * step(dx, 1.2) * step(p.y, tip - 2.0), 1.0);
    }
    col.rgb += bayer(cell) * 0.035 + (hash(cell + floor(time * 10.0)) - 0.5) * 0.03;
    col.rgb = floor(col.rgb * 24.0 + 0.5) / 24.0;
    col.a *= alpha;
    COLOR = col;
}
