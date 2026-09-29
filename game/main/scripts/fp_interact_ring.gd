extends Control

## Wordless interaction affordance (W03/W32, spec 03 §9 "상호작용이 뜬다"):
## a thin pale ring round the screen centre that fades in when fp_interact
## would do something. No text, no icon language to learn.

var shown: bool = false
var _a: float = 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	var target := 1.0 if shown else 0.0
	var na := move_toward(_a, target, delta * 5.0)
	if na != _a:
		_a = na
		queue_redraw()

func _draw() -> void:
	if _a <= 0.0:
		return
	var c := size * 0.5
	var r := lerpf(22.0, 14.0, _a)
	draw_arc(c, r, 0.0, TAU, 40, Color(0.96, 0.93, 0.88, 0.75 * _a), 2.0, true)
	draw_circle(c, 2.0, Color(0.96, 0.93, 0.88, 0.9 * _a))
