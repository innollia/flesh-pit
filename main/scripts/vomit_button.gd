class_name FPVomitButton
extends Control

## A round, wordless on-screen button that appears once the player has
## overfilled past a threshold (design-core 1). Drawn in code: a sick-green
## disc with a mouth and a drip. Click it (or press fdk_vomit) to vomit.

signal pressed

var shown: bool = false
var _t: float = 0.0
var _alpha: float = 0.0

func _ready() -> void:
    custom_minimum_size = Vector2(96, 96)
    mouse_filter = Control.MOUSE_FILTER_STOP
    set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    offset_left = -150
    offset_top = -170
    offset_right = -54
    offset_bottom = -74

func _process(delta: float) -> void:
    _t += delta
    _alpha = move_toward(_alpha, 1.0 if shown else 0.0, delta * 4.0)
    visible = _alpha > 0.01
    queue_redraw()

func _gui_input(event: InputEvent) -> void:
    if shown and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        pressed.emit()
        accept_event()

func _draw() -> void:
    var c := size * 0.5
    var r := minf(size.x, size.y) * 0.45 * (1.0 + sin(_t * 6.0) * 0.04)
    var a := _alpha
    draw_circle(c + Vector2(0, 4), r, Color(0, 0, 0, 0.35 * a))
    draw_circle(c, r, Color(0.46, 0.62, 0.22, 0.95 * a))
    draw_circle(c, r * 0.86, Color(0.58, 0.74, 0.28, 0.95 * a))
    # open mouth
    var mouth := PackedVector2Array()
    for i in range(16):
        var ang := TAU * i / 16.0
        mouth.append(c + Vector2(cos(ang) * r * 0.42, sin(ang) * r * 0.3 + r * 0.05))
    draw_colored_polygon(mouth, Color(0.25, 0.05, 0.06, a))
    # drip out of the mouth
    var drip := r * (0.25 + 0.2 * fposmod(_t * 0.8, 1.0))
    draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.12, r * 0.25), c + Vector2(r * 0.12, r * 0.25), c + Vector2(0, r * 0.3 + drip)]), Color(0.72, 0.82, 0.3, a))
    draw_circle(c + Vector2(0, r * 0.3 + drip), r * 0.09, Color(0.72, 0.82, 0.3, a))
    # two squeezed eyes
    draw_line(c + Vector2(-r * 0.45, -r * 0.38), c + Vector2(-r * 0.18, -r * 0.28), Color(0.2, 0.25, 0.1, a), 4.0)
    draw_line(c + Vector2(r * 0.45, -r * 0.38), c + Vector2(r * 0.18, -r * 0.28), Color(0.2, 0.25, 0.1, a), 4.0)
