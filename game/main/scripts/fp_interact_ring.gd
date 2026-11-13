extends Control

## Wordless interaction affordance (W03/W32, spec 03 §9 "상호작용이 뜬다"):
## a thin pale ring round the screen centre that fades in when fp_interact
## would do something. One small glyph sits at the ring's 4 o'clock, in the
## device the player looks with (spec 08 §1): a mouse with the buttons of the
## hands that can do it lit, the F key cap, or the gamepad X button.

var shown: bool = false
var action: String = "fp_interact":
	set(value):
		if action != value:
			action = value
			queue_redraw()
## The hands whose button acts on the target; the mouse glyph lights these.
var hand_left: bool = false:
	set(value):
		if hand_left != value:
			hand_left = value
			queue_redraw()
var hand_right: bool = false:
	set(value):
		if hand_right != value:
			hand_right = value
			queue_redraw()
## Off when another prompt already shows this input (the stomach's vomit key).
var glyph_on: bool = true:
	set(value):
		if glyph_on != value:
			glyph_on = value
			queue_redraw()
## "keyboard" | "pad" | "mouse": what the player looks with. Walking keys
## say nothing, so a mouse player's glyph does not flip with every step.
var device: String = "mouse"
var _a: float = 0.0

const INK := Color(0.96, 0.93, 0.88)
## Actions shown as their key cap even to a mouse player: no mouse button
## does them (the vomit key; crouch, shown over the canary hole and for
## digging down; the climb key for digging up).
const KEY_ACTIONS := ["fp_vomit", "fdk_crouch", "fdk_jump"]
const DARK := Color(0.08, 0.07, 0.07)

func _ready() -> void:
	# Anchors AND offsets: a bare set_anchors_preset keeps the zero-size
	# offsets, leaving the control at (viewport - start size), i.e. 0x0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _input(event: InputEvent) -> void:
	var d := device
	if event is InputEventKey and event.is_pressed() and _looks(event):
		d = "keyboard"
	elif event is InputEventJoypadButton:
		d = "pad"
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.4:
		d = "pad"
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		d = "mouse"
	if d != device:
		device = d
		queue_redraw()

func _looks(event: InputEvent) -> bool:
	for a in ["fdk_look_up", "fdk_look_down", "fdk_look_left", "fdk_look_right"]:
		if InputMap.has_action(a) and event.is_action(a):
			return true
	return false

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
	if not glyph_on:
		return
	var p := glyph_pos()
	draw_set_transform(p, 0.0, Vector2(k, k))
	p = Vector2.ZERO
	match device:
		"pad":
			if action == "fdk_crouch": _draw_stick_press(p)
			else: _draw_pad(p)
		"mouse":
			if action in KEY_ACTIONS: _draw_key(p, _key_label())
			else: FPMenuKit.draw_mouse(self, p, hand_left, hand_right, _a, 22.0)
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

## The same tooth-coloured key cap as the stomach and opening prompts. A
## wide cap (Ctrl) grows rightward so it never covers the ring.
func _draw_key(p: Vector2, label: String) -> void:
	var tw := FPMenuKit.FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var h := roundf(12 * 1.6)
	var w := maxf(roundf(tw + 12 * 0.9), h)
	FPMenuKit.draw_key(self, p + Vector2((w - h) * 0.5, 0), label, _a, 12)

## The pad's crouch is a left stick press: a stick ring with a dot pushed in.
func _draw_stick_press(p: Vector2) -> void:
	draw_arc(p, 7.0, 0.0, TAU, 20, Color(INK, 0.6 * _a), 1.4, true)
	draw_circle(p, 4.2, Color(INK, 0.95 * _a))
	draw_arc(p, 9.5, PI * 1.15, PI * 1.85, 8, Color(INK, 0.8 * _a), 1.2, true)

func _draw_pad(p: Vector2) -> void:
	# Face-button diamond with the left (X) button filled.
	var off := 5.5
	var spots := [Vector2(0, -off), Vector2(off, 0), Vector2(0, off), Vector2(-off, 0)]
	for i in spots.size():
		var q: Vector2 = p + spots[i]
		if i == (0 if action == "fp_vomit" else (2 if action == "fdk_jump" else 3)):
			draw_circle(q, 3.4, Color(INK, 0.95 * _a))
		else:
			draw_arc(q, 2.8, 0.0, TAU, 16, Color(INK, 0.6 * _a), 1.2, true)

func _key_label() -> String:
	if InputMap.has_action(action):
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				var k := e as InputEventKey
				var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
				var s := OS.get_keycode_string(code)
				if s != "":
					return s
	match action:
		"fp_vomit": return "V"
		"fdk_crouch": return "Ctrl"
		"fdk_jump": return "Space"
	return "F"
