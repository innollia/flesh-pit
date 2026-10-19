extends Control

## Wordless interaction affordance (W03/W32, spec 03 §9 "상호작용이 뜬다"):
## a thin pale ring round the screen centre that fades in when fp_interact
## would do something. A small button glyph sits at the ring's 4 o'clock,
## matching the device the player last touched (keyboard F key cap,
## gamepad X button, or a mouse with its side button lit).

var shown: bool = false
var action: String = "fp_interact":
	set(value):
		if action != value:
			action = value
			queue_redraw()
## "keyboard" | "pad" | "mouse" — follows the last input device used.
var device: String = "keyboard"
var _a: float = 0.0

const INK := Color(0.96, 0.93, 0.88)
const DARK := Color(0.08, 0.07, 0.07)

func _ready() -> void:
	# Anchors AND offsets: a bare set_anchors_preset keeps the zero-size
	# offsets, leaving the control at (viewport - start size), i.e. 0x0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	var c := ring_center()
	var k := ui_scale()
	var r := lerpf(26.0, 17.0, _a) * k
	# Dark halo under a pale ring: readable on bright walls and dark flesh.
	draw_arc(c, r, 0.0, TAU, 48, Color(DARK, 0.7 * _a), 6.0 * k, true)
	draw_arc(c, r, 0.0, TAU, 48, Color(INK, 0.95 * _a), 3.0 * k, true)
	draw_circle(c, 3.5 * k, Color(DARK, 0.7 * _a))
	draw_circle(c, 2.2 * k, Color(INK, 0.95 * _a))
	var p := glyph_pos()
	draw_set_transform(p, 0.0, Vector2(k, k))
	p = Vector2.ZERO
	match device:
		"pad":
			_draw_pad(p)
		"mouse":
			if action == "fp_vomit": _draw_key(p, _key_label())
			else: _draw_mouse(p)
		_:
			_draw_key(p, _key_label())
	draw_set_transform(Vector2.ZERO)

## Screen centre (the crosshair), from the viewport so it never depends on
## this control's own layout.
func ring_center() -> Vector2:
	return get_viewport_rect().size * 0.5

## 1.0 at 720p, grows with the window height.
func ui_scale() -> float:
	return maxf(1.0, get_viewport_rect().size.y / 720.0)

## Glyph centre at the ring's 4 o'clock: 30 degrees below the right
## horizontal (screen y points down), just outside the settled ring.
func glyph_pos() -> Vector2:
	var k := ui_scale()
	return ring_center() + Vector2(cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0))) * (17.0 + 16.0) * k

## The same tooth-coloured key cap as the stomach and opening prompts.
func _draw_key(p: Vector2, label: String) -> void:
	FPMenuKit.draw_key(self, p, label, _a, 12)

func _draw_pad(p: Vector2) -> void:
	# Face-button diamond with the left (X) button filled.
	var off := 5.5
	var spots := [Vector2(0, -off), Vector2(off, 0), Vector2(0, off), Vector2(-off, 0)]
	for i in spots.size():
		var q: Vector2 = p + spots[i]
		if i == (0 if action == "fp_vomit" else 3):
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
	if InputMap.has_action(action):
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				var k := e as InputEventKey
				var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
				var s := OS.get_keycode_string(code)
				if s != "":
					return s
	return "V" if action == "fp_vomit" else "F"
