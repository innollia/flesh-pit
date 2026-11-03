extends SceneTree

## The restroom as the game really mixes it (2026-11-04: its music on hold,
## the bed is the light's hum, the exhaust fan and the water in the pipes,
## tools/build_restroom_amb.py). The movie writer records the engine's own
## audio. Isolated save. Prints "SEG <name> <start frame>" for each part.
##   godot_console --path game --resolution 480x270 --write-movie <dir>/restroom.avi --fixed-fps 30 --script res://tests/capture_restroom_amb.gd

const SAVE := "user://capture-restroom-amb.bin"
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
	# a whole pipes loop (40 s) and more: where the music used to come in
	# (6 s after the glare) nothing but the room is heard
	seg("restroom")
	await frames(1500)
	# the cues the bed must not mask, played where the game plays them
	var hk: Node = m.get_node("AudioHookup")
	var d: FDKAudioDirector = hk.get("director")
	seg("cues")
	d.play("door_open", (m.restroom as Node3D).global_position + Vector3(0, 0, -1.4))
	await frames(75)
	d.play("toilet_flush", hk.call("_toilet_pos"))
	await frames(180)
	m.vent.is_open = true
	d.play("vent_open", (m.vent as Node3D).global_position if m.vent is Node3D else null)
	seg("vent_trade")
	await frames(300)
	m.vent.is_open = false
	seg("restroom_after_vent")
	await frames(300)
	# out in the flesh: held still; the fan and the pipes leave with the hum
	m.set_process(false)
	m.set_physics_process(false)
	m.player.set_physics_process(false)
	var c: Vector3 = m.RESTROOM_CENTER
	m.player.global_position = c + Vector3(0, 0, -6.0)
	seg("flesh")
	await frames(300)
	seg("end")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	m.queue_free()
	quit(0)
