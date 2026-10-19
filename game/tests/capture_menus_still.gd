extends SceneTree

## Stills of the title, settings over pause, and the key screen. Isolated save.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_menus_still.gd

var m: Node3D
var out := ""

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = "user://capture-menus-still.bin"
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
	m.save_to_disk()
	m.show_title()
	await frames(40)
	await shot("title")
	m.open_settings()
	await frames(20)
	await shot("title_settings")
	m.settings_menu.close()
	m.title_screen.close()
	m._leave_title()
	m.finish_opening()
	await frames(30)
	m.open_pause_menu()
	await frames(30)
	m.open_settings()
	await frames(20)
	await shot("pause_settings")
	m.settings_menu.open_keys()
	await frames(20)
	await shot("pause_keys")
	m.handle_esc()
	m.handle_esc()
	m.handle_esc()
	await frames(10)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture-menus-still.bin"))
	m.queue_free()
	quit(0)
