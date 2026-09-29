class_name FDKInputActions
extends Object

## Registers the kit's default input actions in code so the demo/game works
## without any manual Input Map setup, while still letting a game override
## bindings normally (via Project Settings > Input Map, or by calling
## register_defaults() before adding its own events to the same action).
##
## Actions:
##   fdk_move_forward / fdk_move_back / fdk_move_left / fdk_move_right
##   fdk_look_up / fdk_look_down / fdk_look_left / fdk_look_right  (keyboard-only look)
##   fdk_crouch
##   fdk_eat        (hold to chew/tear)
##   fdk_jump

const ACTIONS := {
	"fdk_move_forward": [KEY_W],
	"fdk_move_back": [KEY_S],
	"fdk_move_left": [KEY_A],
	"fdk_move_right": [KEY_D],
	"fdk_look_up": [KEY_UP],
	"fdk_look_down": [KEY_DOWN],
	"fdk_look_left": [KEY_LEFT],
	"fdk_look_right": [KEY_RIGHT],
	"fdk_crouch": [KEY_CTRL],
	"fdk_jump": [KEY_SPACE],
}

static func register_defaults() -> void:
	for action_name in ACTIONS.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		for keycode in ACTIONS[action_name]:
			var already_bound := false
			for event in InputMap.action_get_events(action_name):
				if event is InputEventKey and event.physical_keycode == keycode:
					already_bound = true
					break
			if not already_bound:
				var ev := InputEventKey.new()
				ev.physical_keycode = keycode
				InputMap.action_add_event(action_name, ev)

	if not InputMap.has_action("fdk_eat"):
		InputMap.add_action("fdk_eat")
	var has_mouse_left := false
	for event in InputMap.action_get_events("fdk_eat"):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			has_mouse_left = true
			break
	if not has_mouse_left:
		var mev := InputEventMouseButton.new()
		mev.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fdk_eat", mev)
	# Keyboard-only fallback for players without a mouse button held down easily.
	var has_e_key := false
	for event in InputMap.action_get_events("fdk_eat"):
		if event is InputEventKey and event.physical_keycode == KEY_E:
			has_e_key = true
			break
	if not has_e_key:
		var kev := InputEventKey.new()
		kev.physical_keycode = KEY_E
		InputMap.action_add_event("fdk_eat", kev)
