extends SceneTree

## Left click on aimed targets (2026-11-04 decision): the left hand reaches
## for the door handle and pulls the flush lever. Real input events through
## Main; isolated save.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_left_click_targets.gd

var m: Node3D
var out := ""
const SAVE := "user://capture-left-click.bin"

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await physics_frame
		await process_frame

func shot(name: String) -> void:
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name, " kind=", m.hand_motions.kind, " side=", m.hand_motions.hand_side, " u=%.2f" % m.hand_motions.progress())

func mouse(button: int, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)

func face(yaw: float, pitch: float) -> void:
	m.player._yaw = yaw
	m.player._pitch = pitch
	m.player.rotation.y = yaw
	m.player.camera_pivot.rotation.x = pitch

func aim(point: Vector3) -> void:
	for i in range(4):
		var d: Vector3 = (point - m.player.camera.global_position).normalized()
		face(atan2(-d.x, -d.z), asin(clampf(d.y, -1.0, 1.0)))
		await frames(2)

func game_at(at: Vector3) -> void:
	if is_instance_valid(m):
		m.queue_free()
		await frames(2)
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_left_click_targets.json"
	m.save_path = SAVE
	root.add_child(m)
	await frames(6)
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.player.global_position = at
	m.player.velocity = Vector3.ZERO
	await frames(10)

## Press left click; shoot at the grip and at the pull of the motion.
func left_click_shots(prefix: String) -> void:
	await shot(prefix + "_0_aim")
	mouse(MOUSE_BUTTON_LEFT, true)
	for i in range(12):
		await frames(1)
		if m.hand_motions.kind == "press":
			break
	while m.hand_motions.kind == "press" and m.hand_motions.progress() < 0.36:
		await process_frame
	await shot(prefix + "_1_reach")
	while m.hand_motions.kind == "press" and m.hand_motions.progress() < 0.52:
		await process_frame
	await shot(prefix + "_2_pull")
	mouse(MOUSE_BUTTON_LEFT, false)
	await frames(40)
	await shot(prefix + "_3_after")

func _run() -> void:
	await game_at(Vector3(0, 0.9, 0.75))
	await aim(m.door_handle_point())
	await left_click_shots("door")
	print("door open: ", m.restroom.is_door_open())
	await game_at(Vector3(-1.25, 0.9, 0.72))
	m.toilet.bowl_flesh = 5.0
	await aim(m.lever_point())
	print("lever target: ", m.interact_target())
	await left_click_shots("lever")
	m.queue_free()
	await frames(2)
	quit(0)
