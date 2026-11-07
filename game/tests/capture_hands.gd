extends SceneTree

## The first-person hands in the real game (isolated save): resting, mid
## grab on the flesh past the door, carrying a pile, and a close look.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_hands.gd

var m: Node3D
var out := ""
const SAVE := "user://capture-hands.bin"

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_hands.json"
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(1)
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name)

func look_at_point(target: Vector3) -> void:
	var eye: Vector3 = m.player.camera.global_position
	var d := target - eye
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.restroom.set_door_open(true, true)
	var door := Vector3(0.0, 0.95, FPRestroom.HALF.z - 0.5)
	m.player.global_position = door
	await frames(3)
	look_at_point(Vector3(0.0, 0.9, FPRestroom.HALF.z + 1.5))
	await frames(40)
	await shot("hands_idle")
	var rig: Node3D = m.hands_rig
	rig.on_grab_started()
	for i in range(12):
		rig.on_chew_progress(float(i) / 12.0)
		await frames(1)
	await shot("hands_grab")
	rig.on_released()
	await frames(40)
	rig.set_carry(1.0)
	await frames(40)
	await shot("hands_carry")
	rig.set_carry(0.0)
	await frames(30)
	# hands raised and spread, seen close
	look_at_point(Vector3(0.0, 0.4, FPRestroom.HALF.z + 1.5))
	rig.on_released()
	await frames(8)
	await shot("hands_open")
	quit(0)
