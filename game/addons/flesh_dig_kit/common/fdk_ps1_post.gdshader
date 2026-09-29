shader_type canvas_item;
// PS1 screen post-process, reading the already-rendered 3D frame via
// SCREEN_TEXTURE (Godot canvas_item built-in) -- no separate SubViewport
// needed. Order: pixelate to a low internal resolution (nearest, chunky),
// reduce colour depth with 4x4 Bayer ordered dithering, add a little grain.
uniform float internal_height : hint_range(60.0, 480.0) = 240.0;
uniform float dither_levels : hint_range(2.0, 256.0) = 40.0;
uniform float grain_amount : hint_range(0.0, 0.3) = 0.05;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest_mipmap;
uniform float time_seed = 0.0;

float hash12(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
    float aspect = screen_size.x / max(screen_size.y, 1.0);
    vec2 low_res = vec2(max(internal_height * aspect, 8.0), max(internal_height, 8.0));
    vec2 pixel_uv = floor(SCREEN_UV * low_res) / low_res;
    vec3 col = textureLod(screen_tex, pixel_uv, 0.0).rgb;

    ivec2 px = ivec2(mod(FRAGCOORD.xy, 4.0));
    float bayer_vals[16] = float[16](
        0.0, 8.0, 2.0, 10.0,
        12.0, 4.0, 14.0, 6.0,
        3.0, 11.0, 1.0, 9.0,
        15.0, 7.0, 13.0, 5.0);
    float bv = bayer_vals[px.y * 4 + px.x] / 16.0 - 0.5;
    float step_size = 1.0 / max(dither_levels, 2.0);
    col = clamp(col + bv * step_size, 0.0, 1.0);
    col = floor(col / step_size + 0.5) * step_size;

    float n = hash12(FRAGCOORD.xy + time_seed * 97.0) - 0.5;
    col += n * grain_amount;
    COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
