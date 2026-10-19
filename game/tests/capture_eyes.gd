extends SceneTree

## The Esc screen per eye mutation (none, M24 owl, T5 fish, M03 magnet,
## T1 echo), shut and half shut. Isolated save.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_eyes.gd

var m: Node3D
var out := ""

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = "user://capture-eyes.bin"
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(2)
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name)

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.player.global_position = Vector3(0.3, 0.9, 0.6)
	m.player._yaw = PI * 0.85
	m.player._pitch = -0.15
	await frames(60)
	for pair in [["none", []], ["owl", ["M24"]], ["fish", ["T5"]], ["magnet", ["M03"]], ["echo", ["T1"]]]:
		m.open_pause_menu()
		m.pause_menu.set_eyes(pair[1], m.restroom_field_angle())
		await frames(5)
		await shot("eye_%s_half" % pair[0])
		await frames(40)
		await shot("eye_%s" % pair[0])
		m.pause_menu.resume()
		await frames(30)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture-eyes.bin"))
	m.queue_free()
	quit(0)
