extends SceneTree

## What the newly wired sounds really sound like in the game mix
## (wire-sound 2026-11-03): each one is set off by the game's own signal or
## function on the running main scene, and the movie writer records the
## engine's audio. Isolated save. Prints "SEG <name> <start frame>".
##   godot_console --path game --resolution 960x540 --write-movie <dir>/wire.avi --fixed-fps 30 --script res://tests/capture_wire_sounds.gd

const SAVE := "user://capture-wire-sounds.bin"
var m: Node3D
var _frame := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_wire_sounds.json"
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
	await frames(60)
	var ma = m.mutation_apply
	var prog = m.progression
	seg("quiet")
	await frames(30)
	# a normal chewer tear (tear + the stomach swallow after it), to compare
	seg("normal_tear")
	m.chewer.cell_torn.emit(m.player.global_position + Vector3(0, 1.2, 0.8))
	await frames(45)
	# 1-3 M22: the left hand tears on its own
	seg("alien_tear")
	ma.alien_hand_tore.emit()
	await frames(45)
	# 1-4 M23: the hairs shiver before a squeeze
	seg("hair_shiver")
	ma.hair_shiver_started.emit()
	await frames(40)
	# 1-5 M15: the whole carried pile in one gulp
	m.carried_flesh = 1.0
	m.carried_units = {0: 1.0}
	seg("gulp")
	ma.gulp()
	await frames(55)
	# 1-10: the mirror refuses a part without enough hairs
	m.open_mirror()
	await frames(20)
	m.mirror.focus_part("face")
	seg("mirror_denied")
	m.mirror.buy_current()
	await frames(25)
	m.mirror.close()
	await frames(20)
	# 1-2: an absurd overpay at the open vent
	m.vent.open()
	await frames(75)
	seg("vent_spill")
	m.vent.place_teeth(prog.vent_absurd_threshold(), prog)
	await frames(75)
	m.vent.close()
	await frames(30)
	# 1-7: the lever with teeth only, then with a whole tumor
	m.toilet.vomit_into(20.0)
	seg("rattle_teeth")
	print("RATTLE teeth %.2f" % float(m.flush().get("rattle", 0.0)))
	await frames(120)
	m.toilet.bowl_tumors.append("core_knot")
	seg("rattle_tumor")
	print("RATTLE tumor %.2f" % float(m.flush().get("rattle", 0.0)))
	await frames(240)
	# 1-6: the ending song; the music slider at full, then at zero
	m.set_process(false)
	m.set_physics_process(false)
	m.player.set_physics_process(false)
	m.ending.start(2)
	await frames(60)
	seg("song_music_full")
	await frames(120)
	FPSettings.apply_audio({"master": 1.0, "sfx": 1.0, "music": 0.0})
	seg("song_music_zero")
	await frames(120)
	FPSettings.apply_audio({"master": 1.0, "sfx": 1.0, "music": 1.0})
	seg("end")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	m.queue_free()
	quit(0)
