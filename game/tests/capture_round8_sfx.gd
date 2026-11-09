extends SceneTree

## The three sounds the owner called out on 2026-11-09, as the engine mixes
## them over the real beds, for listening (round8-sfx). Movie writer audio,
## isolated save.
##   SEG door     the restroom door opens (1 s) and shuts (3.5 s) through the
##                restroom's own is_door_open, which the hookup turns into
##                door_open / door_close
##   SEG flush    the lever: tank rattle for 2 s and the flush, through the
##                toilet's signals as toilet_settlement emits them
##   SEG tear     in the flesh (body_a bed, flesh room): three knife tears
##                (the chewer's cell_torn and main.scissors_snipped in the same
##                frame, as fp_art_hookup does with the knife), one bare-hand
##                tear, then a fat tear and a nerve tear
## FP_R8_OLD=1 records with the old files checked out: the tank rattle is then
## played as coin_drop at the hookup's gaps (the old EVENT_SOUNDS mapping).
##   godot_console --path game --resolution 480x270 --write-movie <dir>/r8.avi --fixed-fps 30 --script res://tests/capture_round8_sfx.gd

const SAVE := "user://capture-round8.bin"
var m: Node3D
var _frame := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = SAVE
	m.user_keybinds_path = "user://keybinds_test_round8.json"
	root.add_child(m)
	_run.call_deferred()

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await process_frame
		_frame += 1
		t += 1.0 / 30.0

func _run() -> void:
	var old := OS.get_environment("FP_R8_OLD") == "1"
	await _wait(0.2)
	m.finish_opening()
	var hk: Node = m.get_node("AudioHookup")
	var d: FDKAudioDirector = hk.get("director")
	hk.get_node("BodyEvents").set_process(false)
	m.set_process(false)
	m.set_physics_process(false)
	m.player.set_physics_process(false)
	await _wait(2.0)
	print("SEG door %d" % _frame)
	await _wait(1.0)
	m.restroom.set_door_open(true)
	await _wait(2.5)
	m.restroom.set_door_open(false)
	await _wait(2.5)
	print("SEG flush %d" % _frame)
	if old:
		m.toilet.lever_pulled.emit(10, 0)
		var t := 0.0
		var rng := RandomNumberGenerator.new()
		rng.seed = 8
		while t < 2.0:
			d.play("coin_drop", null)
			var g := rng.randf_range(0.22, 0.45)
			await _wait(g)
			t += g
	else:
		m.toilet.tank_rattle_started.emit(2.0, false)
		m.toilet.lever_pulled.emit(10, 0)
		await _wait(2.0)
		m.toilet.tank_rattle_finished.emit()
	await _wait(3.0)
	print("SEG tear %d" % _frame)
	hk.set_process(false)
	d.set_surface("flesh")
	hk.call("_set_room", "flesh")
	d.set_bed("body_a", 0.3)
	await _wait(1.0)
	var at: Vector3 = m.player.global_position + Vector3(0, 1.4, -1.0)
	for i in range(3):
		d._on_cell_torn(at)
		m.scissors_snipped.emit()
		await _wait(1.5)
	d._on_cell_torn(at)
	await _wait(1.5)
	# a fat and a nerve tear by name (the tissue under `at` is muscle)
	d._play("tear_fat", at, 0.0, 1.0, d.room_bus)
	await _wait(1.5)
	d._play("tear_nerve", at, 0.0, 1.0, d.room_bus)
	d.play("nerve_twitch", at)
	await _wait(2.0)
	print("SEG end %d" % _frame)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit()
