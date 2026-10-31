extends SceneTree

## The Esc screen's lids on the other screen changes (isolated save): the
## start screen opening out of shut eyes, and the opening / loading a run
## (eyes shut over the flush, then opening seated).
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_lid_transitions.gd

var m: Node3D
var out := ""
const SAVE := "user://capture-lids.bin"

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
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

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.show_title()
	await shot("title_0_shut")
	await frames(24)
	await shot("title_1_opening")
	await frames(40)
	await shot("title_2_open")
	m.new_game()
	await frames(30)
	await shot("load_0_shut")
	await frames(85)
	await shot("load_1_opening")
	await frames(40)
	await shot("load_2_open")
	quit(0)
