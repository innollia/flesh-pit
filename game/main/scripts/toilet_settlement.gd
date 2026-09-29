class_name FPToiletSettlement
extends CanvasLayer

## The toilet settlement overlay (design-core 1/8): shown while the camera
## looks down into the toilet. Left-bottom: mutation points and money, each
## as a dark-gray existing total plus a green newly gained amount that
## counts up ("5000 +2293"). Right side: the shop (placeholder slots only;
## items and prices are not designed yet). Picking a slot emits
## buy_requested; the coin-throw and tank delivery are played by main.

signal buy_requested(slot: int)
signal closed

const SHOP_SLOTS := 6
const COUNT_TIME := 1.6

var mutation_old: int = 0
var mutation_gain: int = 0
var money_old: int = 0
var money_gain: int = 0
var _t: float = 0.0
var _root: Control
var _rows: Array = [] # [[old_label, gain_label], ...]
var _slots: Array[Button] = []

func _ready() -> void:
    layer = 5
    _build()
    visible = false

func _build() -> void:
    _root = Control.new()
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_root)
    # counters
    var box := VBoxContainer.new()
    box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    box.offset_left = 48
    box.offset_top = -170
    box.offset_bottom = -40
    box.add_theme_constant_override("separation", 10)
    _root.add_child(box)
    for kind in [0, 1]:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 14)
        box.add_child(row)
        var icon := _Icon.new()
        icon.kind = kind
        icon.custom_minimum_size = Vector2(44, 44)
        row.add_child(icon)
        var old := Label.new()
        old.add_theme_font_size_override("font_size", 40)
        old.add_theme_color_override("font_color", Color(0.22, 0.23, 0.25))
        row.add_child(old)
        var gain := Label.new()
        gain.add_theme_font_size_override("font_size", 40)
        gain.add_theme_color_override("font_color", Color(0.1, 0.62, 0.22))
        row.add_child(gain)
        _rows.append([old, gain])
    # shop panel on the right
    var panel := PanelContainer.new()
    panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
    panel.offset_left = -330
    panel.offset_right = -36
    panel.offset_top = 60
    panel.offset_bottom = -60
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.93, 0.94, 0.95, 0.92)
    sb.border_color = Color(0.7, 0.72, 0.75)
    sb.set_border_width_all(3)
    sb.set_corner_radius_all(10)
    panel.add_theme_stylebox_override("panel", sb)
    _root.add_child(panel)
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 14)
    grid.add_theme_constant_override("v_separation", 14)
    var margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 18)
    panel.add_child(margin)
    margin.add_child(grid)
    for i in range(SHOP_SLOTS):
        var b := Button.new()
        b.custom_minimum_size = Vector2(120, 120)
        b.text = "?\n---"
        b.add_theme_font_size_override("font_size", 26)
        b.add_theme_color_override("font_color", Color(0.4, 0.42, 0.45))
        var bs := StyleBoxFlat.new()
        bs.bg_color = Color(0.82, 0.84, 0.86)
        bs.set_corner_radius_all(8)
        b.add_theme_stylebox_override("normal", bs)
        var bh := bs.duplicate()
        bh.bg_color = Color(0.75, 0.86, 0.76)
        b.add_theme_stylebox_override("hover", bh)
        b.pressed.connect(func(): buy_requested.emit(i))
        grid.add_child(b)
        _slots.append(b)

func open(p_mut_old: int, p_mut_gain: int, p_money_old: int, p_money_gain: int) -> void:
    mutation_old = p_mut_old
    mutation_gain = p_mut_gain
    money_old = p_money_old
    money_gain = p_money_gain
    _t = 0.0
    visible = true
    _refresh()

func close() -> void:
    visible = false
    closed.emit()

func finish_counting() -> void:
    _t = COUNT_TIME
    _refresh()

func is_counting() -> bool:
    return _t < COUNT_TIME

func _process(delta: float) -> void:
    if not visible:
        return
    _t += delta
    _refresh()

func _refresh() -> void:
    var k := clampf(_t / COUNT_TIME, 0.0, 1.0)
    k = 1.0 - pow(1.0 - k, 3.0)
    _rows[0][0].text = str(mutation_old)
    _rows[0][1].text = "+%d" % int(round(mutation_gain * k))
    _rows[1][0].text = str(money_old)
    _rows[1][1].text = "+%d" % int(round(money_gain * k))

class _Icon extends Control:
    var kind: int = 0
    func _draw() -> void:
        var c := size * 0.5
        var r := minf(size.x, size.y) * 0.45
        if kind == 0:
            # mutation: a twisted red cell with a yellow nucleus
            draw_circle(c, r, Color(0.72, 0.12, 0.2))
            draw_circle(c + Vector2(r * 0.2, -r * 0.15), r * 0.4, Color(0.95, 0.8, 0.2))
        else:
            # money: a coin
            draw_circle(c, r, Color(0.78, 0.6, 0.12))
            draw_circle(c, r * 0.72, Color(0.95, 0.8, 0.25))
            draw_rect(Rect2(c - Vector2(r * 0.12, r * 0.4), Vector2(r * 0.24, r * 0.8)), Color(0.78, 0.6, 0.12))
