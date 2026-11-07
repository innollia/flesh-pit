extends SceneTree

## The heart and the restroom water as the game really mixes them. The movie
## writer records the engine's own audio. Isolated save. The room part forces
## each water take once on a short timetable (the real gaps are 45-150 s) and
## shortens nothing else; prints "SEG <name> <start frame>" for each part.
##   godot_console --path game --resolution 480x270 --write-movie <dir>/hw.avi --fixed-fps 30 --script res://tests/capture_heart_water.gd

const SAVE := "user://capture-heart-water.bin"
var m: Node3D
var _frame := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_heart_water.json"
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame
		_frame += 1

func seg(name: String) -> void:
	print("SEG %s %d" % [name, _frame])

func hold_outside(at: Vector3) -> void:
	m.player.global_position = at

func _run() -> void:
	await frames(5)
	m.finish_opening()
	var hk: Node = m.get_node("AudioHookup")
	var d: FDKAudioDirector = hk.get("director")
	var water: Node = hk.get_node("PipeWater")
	seg("room_dry")
	await frames(300)
	for id in ["pipe_tick", "pipe_glug", "pipe_trickle", "pipe_run"]:
		seg("room_" + id)
		water.call("play_take", id)
		await frames(int(ceil(float(water.call("seconds_left")) * 30.0)) + 45)
	# a run under way when the player leaves: it goes with the bed
	seg("leaving_mid_take")
	water.call("play_take", "pipe_run")
	await frames(45)
	m.set_process(false)
	m.set_physics_process(false)
	m.player.set_physics_process(false)
	var c: Vector3 = m.RESTROOM_CENTER
	hold_outside(c + Vector3(0, 0, -6.0))
	await frames(150)
	seg("flesh_shallow")  # body_a or the biome's bed, amb_heart_a
	await frames(450)
	print("BED ", d.current_bed)
	hold_outside(c + Vector3(0, 0, -m.SHELL_THICKNESS * 3.5))
	seg("flesh_deep")  # body_b or the biome's bed, amb_heart_b (fade 3 s)
	await frames(600)
	print("BED ", d.current_bed, " shell ", d.shell)
	seg("end")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	m.queue_free()
	quit(0)
