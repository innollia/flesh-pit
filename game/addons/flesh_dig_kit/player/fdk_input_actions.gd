class_name FDKInputActions
extends Object

## Registers the kit's default input actions in code so the demo/game works
## without any manual Input Map setup, while still letting a game override
## bindings normally (via Project Settings > Input Map, or by calling
## register_defaults() before adding its own events to the same action).
## A default key is only added to an action that has no keyboard key yet, so
## calling this again (another controller's _ready) never brings back a key
## the game rebound away.
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
		if _has_key(action_name):
			continue
		for keycode in ACTIONS[action_name]:
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
	if not _has_key("fdk_eat"):
		var kev := InputEventKey.new()
		kev.physical_keycode = KEY_E
		InputMap.action_add_event("fdk_eat", kev)

static func _has_key(action_name: String) -> bool:
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			return true
	return false
