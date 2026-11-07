extends SceneTree

## Footsteps as the engine mixes them over the bed, for listening and for
## measuring the step against the bed (round7-sfx). The movie writer records
## the engine's own audio. Isolated save. A step every 0.55 s: 12 s in the
## flesh over body_a, 12 s over rib_vault, 10 s in the restroom on tile.
## FP_STEPS_OLD=1 plays them the way they were played before round7-sfx
## (director.play, dry, every step the same pitch and level), so the same
## script records the old way with the old files checked out.
##   godot_console --path game --resolution 480x270 --write-movie <dir>/steps.avi --fixed-fps 30 --script res://tests/capture_steps.gd

const SAVE := "user://capture-steps.bin"
const GAP := 0.55
var m: Node3D
var _frame := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = SAVE
	m.user_keybinds_path = "user://keybinds_test_steps.json"
	root.add_child(m)
	_run.call_deferred()

func _walk(d: FDKAudioDirector, seconds: float, old: bool) -> void:
	var next := 0.5
	var t := 0.0
	while t < seconds:
		if t >= next:
			next += GAP
			if old:
				d.play(d.footstep_id())
			else:
				d.play_step()
		await process_frame
		_frame += 1
		t += 1.0 / 30.0

func _run() -> void:
	var old := OS.get_environment("FP_STEPS_OLD") == "1"
	# FP_STEPS_NOBED=1 mutes the Music bus (beds): the steps and their room alone
	if OS.get_environment("FP_STEPS_NOBED") == "1":
		AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Music"), true)
	for i in range(5):
		await process_frame
		_frame += 1
	m.finish_opening()
	var hk: Node = m.get_node("AudioHookup")
	var d: FDKAudioDirector = hk.get("director")
	hk.set_process(false)
	hk.get_node("BodyEvents").set_process(false)
	m.set_process(false)
	m.set_physics_process(false)
	m.player.set_physics_process(false)
	m.player.global_position = m.RESTROOM_CENTER + Vector3(0, 0, -6.0)
	for bed in ["body_a", "rib_vault"]:
		print("SEG %s %d" % [bed, _frame])
		d.set_surface("flesh")
		if not old:
			hk.call("_set_room", "flesh")
		d.set_bed(bed, 0.3)
		await _walk(d, 12.0, old)
	print("SEG restroom %d" % _frame)
	d.set_surface("tile")
	if not old:
		hk.call("_set_room", "tile")
	d.set_bed("restroom", 0.3)
	await _walk(d, 10.0, old)
	print("SEG end %d" % _frame)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit()
