extends SceneTree

## Isolated save, ordinary game/rig updates and actual Tab input.
var m: Node3D
var frame := 0

func _init() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://watch_restore_probe.bin"
	root.add_child(m)

func key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_TAB
	event.pressed = pressed
	Input.parse_input_event(event)

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 3:
		m.finish_opening()
		m.player.global_position = Vector3(0, 0.95, 0.4)
		m.player._yaw = 0.0
		m.player._pitch = 0.0
		m.player.rotation.y = 0.0
		m.player.camera_pivot.rotation.x = 0.0
	if frame == 10: key(true)
	if frame == 11: key(false)
	if frame in [9, 12, 14, 18, 25, 35]:
		var hand: Node3D = m.hands_rig.get_hand_root("left")
		print("WATCH_FRAME ", frame, " open=", m._mirror_open, " t=", m.hand_motions.t, " pos=", hand.position, " basis=", hand.basis)
	if frame == 36: key(true)
	if frame == 37: key(false)
	return false
