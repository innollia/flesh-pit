extends Control

## Wordless interaction affordance (W03/W32, spec 03 §9 "상호작용이 뜬다"):
## a thin pale ring round the screen centre that fades in when fp_interact
## would do something. A small button glyph sits at the ring's 4 o'clock,
## matching the device the player last touched (keyboard F key cap,
## gamepad X button, or a mouse with its side button lit).

var shown: bool = false
## "keyboard" | "pad" | "mouse" — follows the last input device used.
var device: String = "keyboard"
var _a: float = 0.0

const INK := Color(0.96, 0.93, 0.88)
const DARK := Color(0.08, 0.07, 0.07)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _input(event: InputEvent) -> void:
	var d := device
	if event is InputEventKey:
		d = "keyboard"
	elif event is InputEventJoypadButton:
		d = "pad"
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.4:
		d = "pad"
	elif event is InputEventMouseButton:
		d = "mouse"
	if d != device:
		device = d
		queue_redraw()

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
	draw_arc(c, r, 0.0, TAU, 40, Color(INK, 0.75 * _a), 2.0, true)
	draw_circle(c, 2.0, Color(INK, 0.9 * _a))
	# 4 o'clock: 30 degrees below the right horizontal (screen y points down).
	var p := c + Vector2(cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0))) * (r + 13.0)
	match device:
		"pad":
			_draw_pad(p)
		"mouse":
			_draw_mouse(p)
		_:
			_draw_key(p, _key_label())

func _draw_key(p: Vector2, label: String) -> void:
	var rect := Rect2(p - Vector2(9, 9), Vector2(18, 18))
	draw_rect(rect, Color(DARK, 0.55 * _a), true)
	draw_rect(rect, Color(INK, 0.85 * _a), false, 1.5)
	var font := ThemeDB.fallback_font
	var fs := 12
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, p + Vector2(-w * 0.5, fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(INK, 0.95 * _a))

func _draw_pad(p: Vector2) -> void:
	# Face-button diamond with the left (X) button filled.
	var off := 5.5
	var spots := [Vector2(0, -off), Vector2(off, 0), Vector2(0, off), Vector2(-off, 0)]
	for i in spots.size():
		var q: Vector2 = p + spots[i]
		if i == 3:
			draw_circle(q, 3.4, Color(INK, 0.95 * _a))
		else:
			draw_arc(q, 2.8, 0.0, TAU, 16, Color(INK, 0.6 * _a), 1.2, true)

func _draw_mouse(p: Vector2) -> void:
	# Mouse body seen from the side-top, side button (XBUTTON1) lit.
	var body := Rect2(p - Vector2(6, 9), Vector2(12, 18))
	draw_rect(body, Color(DARK, 0.55 * _a), true)
	draw_rect(body, Color(INK, 0.85 * _a), false, 1.5)
	draw_line(p + Vector2(0, -9), p + Vector2(0, -3), Color(INK, 0.6 * _a), 1.0)
	draw_line(p + Vector2(-6, -3), p + Vector2(6, -3), Color(INK, 0.6 * _a), 1.0)
	draw_rect(Rect2(p + Vector2(-8.5, -1), Vector2(3, 5)), Color(INK, 0.95 * _a), true)

func _key_label() -> String:
	if InputMap.has_action("fp_interact"):
		for e in InputMap.action_get_events("fp_interact"):
			if e is InputEventKey:
				var k := e as InputEventKey
				var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
				var s := OS.get_keycode_string(code)
				if s != "":
					return s
	return "F"
