extends RefCounted

## W32: every screen playable with the mouse alone, the keyboard alone, or a
## gamepad. Keyboard bindings live in main.gd / FDKInputActions (WASD, arrows
## look, E eat, R pick, F interact, Q carry, V vomit ...). This adds the rest:
##
## Gamepad: left stick move, right stick look, RT eat/tear, LT pick,
##   A jump, B carry, X interact, Y vomit, LB crouch, RB next tool,
##   d-pad tools/consumables (main.gd), Start = ui_cancel. Menus use Godot's
##   ui_* actions, which already include the d-pad and A/B.
## Mouse only: move look, LMB eat, RMB pick, MIDDLE hold = walk forward,
##   side button 1 = interact, side button 2 = carry, wheel = next tool,
##   on-screen vomit button. Mirror: click part to buy, wheel candidate,
##   RMB close (fp_mirror.gd).

const AXES := [
	["fdk_move_forward", JOY_AXIS_LEFT_Y, -1.0], ["fdk_move_back", JOY_AXIS_LEFT_Y, 1.0],
	["fdk_move_left", JOY_AXIS_LEFT_X, -1.0], ["fdk_move_right", JOY_AXIS_LEFT_X, 1.0],
	["fdk_look_up", JOY_AXIS_RIGHT_Y, -1.0], ["fdk_look_down", JOY_AXIS_RIGHT_Y, 1.0],
	["fdk_look_left", JOY_AXIS_RIGHT_X, -1.0], ["fdk_look_right", JOY_AXIS_RIGHT_X, 1.0],
	["fdk_eat", JOY_AXIS_TRIGGER_RIGHT, 1.0], ["fp_pick", JOY_AXIS_TRIGGER_LEFT, 1.0],
]
const BUTTONS := [
	["fdk_jump", JOY_BUTTON_A], ["fdk_crouch", JOY_BUTTON_LEFT_SHOULDER],
	["ui_cancel", JOY_BUTTON_START], ["ui_cancel", JOY_BUTTON_B], ["ui_accept", JOY_BUTTON_A],
	["ui_left", JOY_BUTTON_DPAD_LEFT], ["ui_right", JOY_BUTTON_DPAD_RIGHT],
	["ui_up", JOY_BUTTON_DPAD_UP], ["ui_down", JOY_BUTTON_DPAD_DOWN],
]
const MOUSE := [
	["fdk_move_forward", MOUSE_BUTTON_MIDDLE], ["fp_interact", MOUSE_BUTTON_XBUTTON1],
	["fp_carry", MOUSE_BUTTON_XBUTTON2], ["fp_tool_next", MOUSE_BUTTON_WHEEL_DOWN],
]

static func register() -> void:
	for a in AXES:
		_ensure(a[0])
		var e := InputEventJoypadMotion.new()
		e.axis = a[1]
		e.axis_value = a[2]
		_add(a[0], e)
	for b in BUTTONS:
		_ensure(b[0])
		var e := InputEventJoypadButton.new()
		e.button_index = b[1]
		_add(b[0], e)
	for m in MOUSE:
		_ensure(m[0])
		var e := InputEventMouseButton.new()
		e.button_index = m[1]
		_add(m[0], e)

## Which input devices can fire `action` ("mouse", "keyboard", "pad").
static func devices_of(action: String) -> Array[String]:
	var out: Array[String] = []
	if not InputMap.has_action(action):
		return out
	for e in InputMap.action_get_events(action):
		var d := ""
		if e is InputEventMouseButton:
			d = "mouse"
		elif e is InputEventKey:
			d = "keyboard"
		elif e is InputEventJoypadButton or e is InputEventJoypadMotion:
			d = "pad"
		if d != "" and not out.has(d):
			out.append(d)
	return out

static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

static func _add(action: String, ev: InputEvent) -> void:
	for e in InputMap.action_get_events(action):
		if e.is_match(ev, true) and e.get_class() == ev.get_class():
			if not (e is InputEventJoypadMotion) or (e as InputEventJoypadMotion).axis_value == (ev as InputEventJoypadMotion).axis_value:
				return
	InputMap.action_add_event(action, ev)
