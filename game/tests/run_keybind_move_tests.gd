extends SceneTree

## Key settings for walking, crouching and digging up/down inside the flesh
## (audit 1-11): the Esc key screen lists the four move keys, crouch and
## climb up; a key chosen there is saved to the key file (not the game save),
## survives a restart of the game, and the player walks, crouches and climbs
## with the new key and no longer with the old one. Isolated key file and save.
## Run: godot_console --headless --path game --script res://tests/run_keybind_move_tests.gd

const KEYS_PATH := "user://keybinds_test_move.json"
const SAVE_PATH := "user://keybinds_test_move.bin"
## action -> [default key, new key]
const REBIND := {
	"fdk_move_forward": [KEY_W, KEY_I], "fdk_move_back": [KEY_S, KEY_K],
	"fdk_move_left": [KEY_A, KEY_J], "fdk_move_right": [KEY_D, KEY_L],
	"fdk_crouch": [KEY_CTRL, KEY_O], "fdk_jump": [KEY_SPACE, KEY_U],
}

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	if FileAccess.file_exists(KEYS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(KEYS_PATH))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
	await process_frame

func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func key_ev(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.pressed = true
	return e

## A fresh game, as when the player starts it again.
func boot() -> void:
	if is_instance_valid(m):
		m.queue_free()
		await frames(2)
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = SAVE_PATH
	m.user_keybinds_path = KEYS_PATH
	root.add_child(m)
	await frames(6)
	m.finish_opening()
	m.player.mouse_look_enabled = false
	await frames(2)

## Stand at `at` looking along -X (forward = -X, right = -Z).
func stand(at: Vector3) -> void:
	m.player.global_position = at
	m.player.velocity = Vector3.ZERO
	m.player._yaw = PI * 0.5
	m.player._pitch = 0.0
	m.player.rotation.y = m.player._yaw
	await frames(3)

## Hold `code` for a few physics frames; how far the player went.
func walk(code: Key) -> Vector3:
	await stand(Vector3(1.2, 0.9, 0.0))
	var from: Vector3 = m.player.global_position
	key(code, true)
	await frames(14)
	key(code, false)
	await frames(2)
	var d: Vector3 = m.player.global_position - from
	d.y = 0.0
	return d

func run() -> void:
	await boot()
	# --- the key screen lists them and rebinds them through its own input
	var menu: FPKeybindMenu = m.keybind_menu
	m.open_keybind_menu()
	for action in REBIND:
		check(menu.buttons.has(action), "key screen lists %s" % action)
		check(menu._names.get(action, action) != action, "%s has a menu label" % action)
	for action in REBIND:
		if not menu.buttons.has(action):
			continue
		check(FPKeybindMenu.key_of(action) == OS.get_keycode_string(REBIND[action][0]), "%s starts on its default key" % action)
		(menu.buttons[action] as Button).pressed.emit()
		menu._input(key_ev(REBIND[action][1]))
		check(FPKeybindMenu.key_of(action) == OS.get_keycode_string(REBIND[action][1]), "%s takes the new key" % action)
	menu.close()
	var saved = JSON.parse_string(FileAccess.get_file_as_string(KEYS_PATH)) if FileAccess.file_exists(KEYS_PATH) else null
	for action in REBIND:
		var got := ""
		if saved is Dictionary and saved.get("키", {}).has(action):
			got = String(saved["키"][action].get("키보드", ""))
		check(got == OS.get_keycode_string(REBIND[action][1]), "%s saved in the key file (%s)" % [action, got])
	check(m.user_keybinds_path == KEYS_PATH, "the player's own key file is not touched")

	# --- restart: the input map starts empty again, the kit and the game
	# register their keys, the key file wins
	for action in REBIND:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	await boot()
	FDKInputActions.register_defaults() # another body's _ready must not bring the old keys back
	for action in REBIND:
		var keys: Array = []
		for e in InputMap.action_get_events(action):
			if e is InputEventKey:
				keys.append(e.physical_keycode)
		check(keys == [REBIND[action][1]], "after restart %s has only its new key (%s)" % [action, keys])

	# --- the player walks with the new keys and not the old
	var fwd := Vector3(-1, 0, 0)
	var right := Vector3(0, 0, -1)
	var d := await walk(KEY_I)
	check(d.dot(fwd) > 0.15, "new forward key walks forward (%.2f)" % d.dot(fwd))
	d = await walk(KEY_W)
	check(d.length() < 0.03, "old W no longer walks (%.2f)" % d.length())
	d = await walk(KEY_K)
	check(d.dot(-fwd) > 0.15, "new back key walks back (%.2f)" % d.dot(-fwd))
	d = await walk(KEY_S)
	check(d.length() < 0.03, "old S no longer walks (%.2f)" % d.length())
	d = await walk(KEY_J)
	check(d.dot(-right) > 0.15, "new left key steps left (%.2f)" % d.dot(-right))
	d = await walk(KEY_A)
	check(d.length() < 0.03, "old A no longer walks (%.2f)" % d.length())
	d = await walk(KEY_L)
	check(d.dot(right) > 0.15, "new right key steps right (%.2f)" % d.dot(right))
	d = await walk(KEY_D)
	check(d.length() < 0.03, "old D no longer walks (%.2f)" % d.length())

	# --- crouch
	await stand(Vector3(1.2, 0.9, 0.0))
	key(KEY_O, true)
	await frames(4)
	check(m.player._is_crouching, "new crouch key crouches")
	key(KEY_O, false)
	await frames(10)
	key(KEY_CTRL, true)
	await frames(4)
	check(not m.player._is_crouching, "old Ctrl no longer crouches")
	key(KEY_CTRL, false)
	await frames(10)

	# --- inside the flesh: climb up with the new key, dig down with the new
	# crouch key + left hand
	var inside := Vector3(0.0, 0.9, -FPRestroom.HALF.z - 2.0)
	check(m.can_climb_at(inside), "test spot is inside the flesh")
	m.player.global_position = inside
	await frames(2)
	key(KEY_U, true)
	await frames(2)
	m.player.global_position = inside
	await frames(1)
	check(m.player.climb_enabled and m.player._climb_input > 0.5, "new climb key digs up inside the flesh (%.1f)" % m.player._climb_input)
	key(KEY_U, false)
	key(KEY_SPACE, true)
	await frames(1)
	m.player.global_position = inside
	await frames(1)
	check(m.player.climb_enabled and m.player._climb_input == 0.0, "old Space no longer digs up (%.1f)" % m.player._climb_input)
	key(KEY_SPACE, false)
	Input.action_press("fdk_eat")
	key(KEY_O, true)
	await frames(1)
	m.player.global_position = inside
	await frames(1)
	check(m.player._climb_input < -0.5, "new crouch key + left hand digs down (%.1f)" % m.player._climb_input)
	key(KEY_O, false)
	key(KEY_CTRL, true)
	await frames(1)
	check(m.player._climb_input == 0.0, "old Ctrl + left hand no longer digs down (%.1f)" % m.player._climb_input)
	key(KEY_CTRL, false)
	Input.action_release("fdk_eat")
	await frames(2)

	# --- standing up from the vomit view goes through the actions too
	m.player.global_position = Vector3(0.0, 0.9, -0.5)
	await frames(3)
	m.stomach.add_flesh(8)
	m.start_settlement()
	await frames(3)
	check(m.is_settling(), "vomit view entered")
	key(KEY_W, true)
	await frames(3)
	key(KEY_W, false)
	await frames(2)
	check(m.is_settling(), "old W does not stand up from the vomit view")
	key(KEY_I, true)
	await frames(3)
	key(KEY_I, false)
	await frames(2)
	check(not m.is_settling(), "new forward key stands up from the vomit view")

	# --- back to the defaults
	m.reset_keybinds()
	check(not FileAccess.file_exists(KEYS_PATH), "reset removes the test key file")
	for action in REBIND:
		check(FPKeybindMenu.key_of(action) == OS.get_keycode_string(REBIND[action][0]), "%s back on its default key" % action)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	m.queue_free()
	print("--- %d passed, %d failed ---" % [passed, failed])
	quit(1 if failed > 0 else 0)
