extends SceneTree

## What the steady layers really sound like in the game mix (D03 M03 magnet
## hum, D05 ending song): the movie writer records the engine's own audio.
## Isolated save. Prints "SEG <name> <start frame>" for each segment; the
## two ending segments are 20 s and 24 s so the same 16 s song phase can be
## compared with and without the second voice.
##   godot_console --path game --resolution 960x540 --write-movie <dir>/song.avi --fixed-fps 30 --script res://tests/capture_song_layers.gd

const SAVE := "user://capture-song-layers.bin"
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

func face(target: Vector3) -> void:
	var p: Node3D = m.player
	p.look_at(Vector3(target.x, p.global_position.y, target.z), Vector3.UP)

func _run() -> void:
	await frames(5)
	m.finish_opening()
	await frames(25)
	var c: Vector3 = m.RESTROOM_CENTER
	seg("restroom")
	await frames(60)
	# out in the flesh: main is held still so the solid flesh does not crush
	# the body back to the restroom; the sound hookup runs as in play
	m.set_process(false)
	m.set_physics_process(false)
	m.player.set_physics_process(false)
	m.progression.mutation_tree._purchased["M03"] = true
	m.player.global_position = c + Vector3(0, 0, -6.0)
	face(c)
	seg("m03_facing_restroom")
	await frames(120)
	face(c + Vector3(0, 0, -20.0))
	seg("m03_facing_away")
	await frames(90)
	m.player.global_position = c + Vector3(0, 0, -m.OUTER_RADIUS * 0.95)
	seg("outer_shell")
	await frames(120)
	m.progression.mutation_tree._purchased.erase("M03")
	m.set_process(true)
	m.player.global_position = c + Vector3(0, 0, m.OUTER_RADIUS)
	m.step_world(0.016)
	seg("ending_one_voice")
	await frames(600)
	m.ending.active = false
	m.ending.start(2)
	seg("ending_two_voices")
	await frames(720)
	seg("end")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	m.queue_free()
	quit(0)
