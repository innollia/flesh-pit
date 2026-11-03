extends SceneTree

## Each belt item held in the right hand in the real game (isolated save),
## looking ahead past the open door: form, size and material in the hand.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_held_items.gd

var m: Node3D
var out := ""
const SAVE := "user://capture-held-items.bin"

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
	m.restroom.set_door_open(true, true)
	m.player.global_position = Vector3(0.0, 0.95, 0.2)
	m.player._yaw = PI
	m.player._pitch = -0.1
	var p = m.progression
	p.has_belt = true
	for id in ["spray_cheap", "spray_deep", "canary_feed", "barrier", "knife", "blender"]:
		p.grant_item(id)
	await frames(10)
	for id in ["spray_cheap", "spray_deep", "canary_feed", "barrier", "knife", "blender"]:
		m.belt_swap.swap_now(id)
		await frames(30)
		await shot("held_" + id)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
