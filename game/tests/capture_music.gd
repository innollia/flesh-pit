extends SceneTree

## The background music as the game really mixes it (audio/fp_music.gd):
## the movie writer records the engine's own audio, beds and all. Isolated
## save. Prints "SEG <name> <start frame>" for each place.
##   godot_console --path game --resolution 480x270 --write-movie <dir>/music.avi --fixed-fps 30 --script res://tests/capture_music.gd

const SAVE := "user://capture-music.bin"
var m: Node3D
var _frame := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame
		_frame += 1

func seg(name: String) -> void:
	print("SEG %s %d" % [name, _frame])

func _run() -> void:
	await frames(5)
	m.finish_opening()
	# the restroom: no music, only its bed
	seg("restroom")
	await frames(450)
	seg("vent_trade")
	m.vent.is_open = true
	await frames(600)
	m.vent.is_open = false
	await frames(120)
	# the two modal screens in the room
	m.open_mirror()
	seg("mirror")
	await frames(600)
	m.mirror.close()
	await frames(120)
	m.start_settlement()
	seg("settle")
	await frames(450)
	m.leave_settlement()
	await frames(120)
	m.open_keybind_menu()
	seg("keybind")
	await frames(540)
	m.keybind_menu.close()
	m.open_pause_menu()
	seg("pause")
	await frames(540)
	m.pause_menu.resume()
	m._on_pause_resumed()
	# out in the flesh: held still; only the body's drone (and the song's
	# faint tine further out) may be heard
	m.set_process(false)
	m.set_physics_process(false)
	m.player.set_physics_process(false)
	var c: Vector3 = m.RESTROOM_CENTER
	m.player.global_position = c + Vector3(0, 0, -6.0)
	seg("flesh")
	await frames(450)
	m.player.global_position = c
	m.show_title()
	seg("title")
	await frames(720)
	seg("end")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	m.queue_free()
	quit(0)
