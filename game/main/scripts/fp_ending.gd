class_name FPEnding
extends CanvasLayer

## Ending signal (design-core 10): breaking through the outermost shell.
## Placeholder presentation only -- a white fade, then a credits card. The
## real street scene, humming song and camera pull-back are later work;
## `voice_layers` tells the audio layer how many song voices to play.

signal finished

var active: bool = false
var voice_layers: int = 1
var _t: float = 0.0
var _fade: ColorRect
var _credits: Label

func _ready() -> void:
	layer = 20
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(1, 1, 1, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_credits = Label.new()
	_credits.set_anchors_preset(Control.PRESET_CENTER)
	_credits.text = "flesh-pit"
	_credits.modulate = Color(0.2, 0.2, 0.2, 0)
	add_child(_credits)
	visible = false

func start(p_voice_layers: int) -> void:
	if active:
		return
	active = true
	voice_layers = p_voice_layers
	_t = 0.0
	visible = true

func tick(delta: float) -> void:
	if not active:
		return
	_t += delta
	_fade.color.a = clampf(_t / 2.0, 0.0, 1.0)
	_credits.modulate.a = clampf((_t - 3.0) / 1.5, 0.0, 1.0)
	if _t >= 8.0 and _t - delta < 8.0:
		finished.emit()
