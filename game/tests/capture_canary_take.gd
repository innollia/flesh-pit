extends SceneTree

## Canary take from the first-person camera (user 2026-11-08): the crouch key
## cap over the hole while standing (and after rebinding), then the left hand
## deep in, the swarm on it, the one shake, the stir and the single bird
## pulled out. Real Main, real input events, isolated save and key file.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --write-movie <dir>/canary.avi --script res://tests/capture_canary_take.gd

var m: Node3D
var out := ""
const SAVE := "user://capture-canary-take.bin"
const KEYS := "user://keybinds_capture_canary_take.json"

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(KEYS))
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func shot(name: String) -> void:
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	var stage: String = m.canary_pull.stage() if m.canary_pull != null else "-"
	var perched: int = m.canary_pull.perched_count() if m.canary_pull != null else 0
	if m.canary_pull != null:
		var bd: Node3D = m.canary_pull.bird
		var wr: Node3D = m.canary_pull.active_rig().get_node("HandLeft/Wrist")
		print("  bird vis=", bd.is_visible_in_tree(), " scr=", m.player.camera.unproject_position(bd.global_position), " wrist scr=", m.player.camera.unproject_position(wr.global_position), " d=", bd.global_position.distance_to(m.player.camera.global_position), " bird=", bd.global_position, " wrist=", wr.global_position, " feet=", m.player.get_feet_position().y)
	print("CAP ", name, " stage=", stage, " perched=", perched, " ring=", m.interact_ring.shown, " action=", m.interact_ring.action, " has=", m.has_canary, " wrist_scale=", (m.canary_pull.active_rig().get_node("HandLeft/Wrist") as Node3D).global_basis.get_scale() if m.canary_pull != null else Vector3.ZERO)

func key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func mouse(button: int, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)

func aim(point: Vector3) -> void:
	for i in range(4):
		var d: Vector3 = (point - m.player.camera.global_position).normalized()
		m.player._yaw = atan2(-d.x, -d.z)
		m.player._pitch = asin(clampf(d.y, -1.0, 1.0))
		m.player.rotation.y = m.player._yaw
		m.player.camera_pivot.rotation.x = m.player._pitch
		await frames(2)

func _run() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = KEYS
	m.save_path = SAVE
	root.add_child(m)
	await frames(6)
	m.save_path = SAVE
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.player.global_position = Vector3(-1.3, 0.9, -0.51)
	m.player.velocity = Vector3.ZERO
	await frames(10)
	# standing over the hole: the crouch key cap
	await aim(m.canary_hole_point())
	await frames(20)
	await shot("01-standing-crouch-hint")
	m.rebind_key("fdk_crouch", "C")
	await frames(10)
	await shot("02-standing-hint-rebound-C")
	m.rebind_key("fdk_crouch", "Ctrl")
	await frames(4)
	# crouched: the hole is the target, only the left button lit
	key(KEY_CTRL, true)
	await frames(20)
	await aim(m.canary_hole_point())
	await frames(15)
	await shot("03-crouched-left-button")
	mouse(MOUSE_BUTTON_LEFT, true)
	await frames(3)
	mouse(MOUSE_BUTTON_LEFT, false)
	var marks := [0.17, 0.24, 0.31, 0.36, 0.42, 0.47, 0.49, 0.51, 0.53, 0.57, 0.62, 0.67, 0.73, 0.78, 0.81, 0.86]
	var i := 0
	while m.is_pulling_canary() and i < marks.size():
		if m.canary_pull.progress() >= marks[i]:
			await shot("%02d-u%03d" % [10 + i, int(marks[i] * 100)])
			i += 1
		await frames(1)
	while m.is_pulling_canary():
		await frames(1)
	await frames(10)
	await shot("40-after-has-canary")
	key(KEY_CTRL, false)
	await frames(5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(KEYS))
	quit()
