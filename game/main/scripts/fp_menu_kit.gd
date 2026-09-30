class_name FPMenuKit
extends RefCounted

## Shared look for the title screen, pause and settings: dark plate, pale
## clinical text, one bright focus frame (mouse hover moves focus, so only
## one item is ever lit). Layouts are made for 1280x720 and scaled to the
## window height, so 1920x1080 shows the same layout larger.

const BASE_H := 720.0
const INK := Color(0.93, 0.9, 0.86)
const DIM_INK := Color(0.66, 0.6, 0.57)
const PLATE := Color(0.1, 0.07, 0.07, 0.96)
const EDGE := Color(0.5, 0.24, 0.22)

## Grain + ordered dither over the dim backdrop (PS1 treatment for UI).
const GRAIN_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.03, 0.0, 0.01, 0.7);
uniform float blur = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
float bayer(vec2 p) {
    int x = int(mod(p.x, 4.0));
    int y = int(mod(p.y, 4.0));
    int i = x + y * 4;
    float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
    return m[i] / 16.0 - 0.5;
}
void fragment() {
    vec3 base = vec3(0.0);
    if (blur > 0.0) {
        vec2 px = SCREEN_PIXEL_SIZE * blur;
        float w = 0.0;
        for (int x = -2; x <= 2; x++) {
            for (int y = -2; y <= 2; y++) {
                base += texture(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px).rgb;
                w += 1.0;
            }
        }
        base /= w;
    }
    vec3 c = mix(base, tint.rgb, tint.a);
    float n = fract(sin(dot(floor(FRAGCOORD.xy / 2.0), vec2(12.9898, 78.233)) + TIME * 3.0) * 43758.5453);
    c += (n - 0.5) * 0.035 + bayer(floor(FRAGCOORD.xy / 2.0)) * 0.02;
    COLOR = vec4(c, blur > 0.0 ? 1.0 : tint.a);
}
"""

static func make_root(layer: CanvasLayer) -> Control:
    var root := Control.new()
    root.name = "Root"
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    layer.add_child(root)
    return root

## Scales the layer so a 720-high layout fills any window height.
static func fit(layer: CanvasLayer, root: Control) -> void:
    if root == null or not layer.is_inside_tree():
        return
    var vp := layer.get_viewport().get_visible_rect().size
    var k := maxf(vp.y / BASE_H, 0.5)
    layer.scale = Vector2(k, k)
    root.position = Vector2.ZERO
    root.size = vp / k

static func backdrop(root: Control, alpha: float = 0.7, blur: float = 0.0) -> ColorRect:
    var dim := ColorRect.new()
    dim.name = "Backdrop"
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var mat := ShaderMaterial.new()
    var sh := Shader.new()
    sh.code = GRAIN_SHADER
    mat.shader = sh
    mat.set_shader_parameter("tint", Color(0.03, 0.0, 0.01, alpha))
    mat.set_shader_parameter("blur", blur)
    dim.material = mat
    root.add_child(dim)
    return dim

## A centred plate; returns the column to fill.
static func plate(root: Control, min_w: float = 0.0) -> VBoxContainer:
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(center)
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(min_w, 0)
    var sb := StyleBoxFlat.new()
    sb.bg_color = PLATE
    sb.border_color = EDGE
    sb.set_border_width_all(2)
    sb.set_corner_radius_all(4)
    sb.content_margin_left = 30
    sb.content_margin_right = 30
    sb.content_margin_top = 20
    sb.content_margin_bottom = 20
    panel.add_theme_stylebox_override("panel", sb)
    center.add_child(panel)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 10)
    panel.add_child(col)
    return col

static func label(text: String, size: int = 18, color: Color = INK) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    return l

static func _focus_box() -> StyleBoxFlat:
    var f := StyleBoxFlat.new()
    f.bg_color = Color(0.58, 0.2, 0.19)
    f.border_color = Color(1.0, 0.9, 0.78)
    f.set_border_width_all(2)
    f.set_corner_radius_all(3)
    return f

static func button(text: String, w: float = 280.0, h: float = 40.0) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size = Vector2(w, h)
    b.focus_mode = Control.FOCUS_ALL
    b.add_theme_font_size_override("font_size", 19)
    b.add_theme_color_override("font_color", INK)
    b.add_theme_color_override("font_focus_color", Color(1, 1, 1))
    b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
    b.add_theme_color_override("font_disabled_color", Color(0.4, 0.36, 0.35))
    var n := StyleBoxFlat.new()
    n.bg_color = Color(0.2, 0.11, 0.11)
    n.set_corner_radius_all(3)
    var f := _focus_box()
    b.add_theme_stylebox_override("normal", n)
    b.add_theme_stylebox_override("hover", f)
    b.add_theme_stylebox_override("focus", f)
    b.add_theme_stylebox_override("pressed", f)
    b.add_theme_stylebox_override("disabled", n)
    b.mouse_entered.connect(func():
        if not b.disabled:
            b.grab_focus())
    return b

static func slider(min_v: float, max_v: float, step: float, w: float = 260.0) -> HSlider:
    var s := HSlider.new()
    s.min_value = min_v
    s.max_value = max_v
    s.step = step
    s.custom_minimum_size = Vector2(w, 30)
    s.focus_mode = Control.FOCUS_ALL
    s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var track := StyleBoxFlat.new()
    track.bg_color = Color(0.22, 0.13, 0.13)
    track.content_margin_top = 4
    track.content_margin_bottom = 4
    var fill := StyleBoxFlat.new()
    fill.bg_color = Color(0.7, 0.62, 0.58)
    fill.content_margin_top = 4
    fill.content_margin_bottom = 4
    var focus := StyleBoxFlat.new()
    focus.draw_center = false
    focus.border_color = Color(1.0, 0.9, 0.78)
    focus.set_border_width_all(2)
    focus.expand_margin_left = 6
    focus.expand_margin_right = 6
    focus.expand_margin_top = 4
    focus.expand_margin_bottom = 4
    s.add_theme_stylebox_override("slider", track)
    s.add_theme_stylebox_override("grabber_area", fill)
    s.add_theme_stylebox_override("grabber_area_highlight", fill)
    s.add_theme_stylebox_override("focus", focus)
    s.mouse_entered.connect(func(): s.grab_focus())
    return s

## Wire vertical focus through a list of controls (wraps round).
static func chain_focus(items: Array) -> void:
    var n := items.size()
    for i in range(n):
        var c: Control = items[i]
        var up: Control = items[(i - 1 + n) % n]
        var down: Control = items[(i + 1) % n]
        c.focus_neighbor_top = c.get_path_to(up)
        c.focus_neighbor_bottom = c.get_path_to(down)
        c.focus_previous = c.get_path_to(up)
        c.focus_next = c.get_path_to(down)