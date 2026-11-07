extends SceneTree

## The flesh's music as the engine really plays it (audio/fp_flesh_music.gd
## over the body's bed): the movie writer records the mix from the room out
## through the core, across into the mantle (the song waits for its phrase
## mark and crossfades) and the surface. Main is held still so the flesh does
## not push the body back. Isolated save. Prints "SEG <name> <frame>". It runs
## on the code before the flesh music too (then it records the bed alone).
##   godot_console --path game --resolution 480x270 --write-movie <dir>/flesh.avi --fixed-fps 30 --script res://tests/capture_flesh_music.gd

const SAVE := "user://capture-flesh-music.bin"
var m: Node3D
var _frame := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_flesh_music_capture.json"
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func secs(s: float) -> void:
	for i in range(int(s * 30.0)):
		await process_frame
		_frame += 1

func seg(name: String) -> void:
	print("SEG %s %d" % [name, _frame])

## A point at `depth` from the room's centre, clear of every rest container.
func spot(depth: float) -> Vector3:
	var c: Vector3 = m.RESTROOM_CENTER
	for k in range(64):
		var a := k * 0.39
		var p := c + Vector3(sin(a), 0.0, -cos(a)) * depth
		var clear := true
		for r in m.rest_points:
			if (r as Vector3).distance_to(p) < 4.0:
				clear = false
		if clear and p.z < c.z - 3.0:
			return p
	return c + Vector3(0, 0, -depth)

func _run() -> void:
	await secs(0.2)
	m.finish_opening()
	await secs(1.0)
	m.set_process(false)
	m.set_physics_process(false)
	m.player.set_physics_process(false)
	seg("room")
	await secs(4.0)
	seg("core")
	m.player.global_position = spot(6.5)
	await secs(40.0)
	seg("mantle")
	m.player.global_position = spot(13.0)
	await secs(40.0)
	seg("surface")
	m.player.global_position = spot(22.0)
	await secs(40.0)
	seg("end")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	m.queue_free()
	quit(0)
