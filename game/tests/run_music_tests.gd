extends SceneTree

## Background music (audio/fp_music.gd, tools/build_music.py). Each place
## starts its own track on the Music bus, and nothing plays in the flesh
## (docs/spec/08-presentation.md 3). Real main scene, isolated save.
##   godot_console --headless --path game --script res://tests/run_music_tests.gd

const SAVE := "user://music-test.bin"
## fp_music FADE_OUT_FLESH (0.8 s) plus a frame: gone by then.
const OUT_S := 1.0
var _passed := 0
var _failed := 0
var m: Node3D
var music: Node

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  ok   ", msg)
	else:
		_failed += 1
		print("  FAIL ", msg)

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

## Advances the music by `sec` in small steps (as frames would).
func run_for(sec: float) -> void:
	var t := 0.0
	while t < sec:
		music.call("step", 0.1)
		t += 0.1
	await process_frame

func on_music_bus(id: String) -> bool:
	var p: AudioStreamPlayer = music.call("player", id)
	return p != null and p.bus == &"Music" and p.playing and AudioServer.get_bus_index(p.bus) >= 0

func _run() -> void:
	print("=== flesh-pit music tests ===")
	await frames(10)
	music = m.get_node_or_null("AudioHookup/Music")
	_ok(music != null, "the audio hookup adds the music node")
	if music == null:
		_finish()
		return
	var bank: FDKSoundBank = m.get_node("AudioHookup").get("director").bank
	var tracks: Dictionary = music.get("TRACKS")
	for place in tracks.keys():
		var id := String(tracks[place])
		_ok(bank.has(id) and bank.is_loop(id) and bank.stream(id, 0) != null, "%s (%s) is a loop in the manifest" % [id, place])
	# the opening (black screen, flush, canary) keeps the room quiet
	_ok(m.is_opening(), "main starts in the opening")
	await run_for(8.0)
	_ok(music.get("place") == "" and music.call("audible").is_empty(), "no music during the opening (%s)" % music.get("place"))
	m.finish_opening()
	await frames(2)
	# restroom: comes in only after the eyes have settled
	await run_for(3.0)
	_ok(music.call("audible").is_empty(), "not yet 3 s after the opening")
	await run_for(4.0)
	_ok(music.get("place") == "restroom", "restroom music wanted once settled (%s)" % music.get("place"))
	await run_for(8.5)
	_ok(on_music_bus("mus_restroom") and float(music.call("level", "mus_restroom")) > 0.99, "restroom plays mus_restroom on the Music bus")
	# the vent trade takes over while the grate is open
	m.vent.is_open = true
	await run_for(3.0)
	_ok(music.get("place") == "vent" and on_music_bus("mus_vent") and float(music.call("level", "mus_vent")) > 0.99, "vent open plays mus_vent on the Music bus")
	_ok(float(music.call("level", "mus_restroom")) < 0.01, "restroom music crossfaded out under the trade")
	m.vent.is_open = false
	await run_for(3.0)
	_ok(music.get("place") == "restroom" and float(music.call("level", "mus_restroom")) > 0.3, "grate shut: back to the restroom music")
	# out in the flesh: held still so the flesh does not push the body back
	m.set_process(false)
	m.set_physics_process(false)
	m.player.set_physics_process(false)
	var c: Vector3 = m.RESTROOM_CENTER
	m.player.global_position = c + Vector3(0, 0, -6.0)
	await frames(2)
	await run_for(OUT_S)
	_ok(music.get("place") == "" and music.call("audible").is_empty(), "in the flesh no music plays (%s)" % str(music.call("audible")))
	await run_for(20.0)
	_ok(music.call("audible").is_empty(), "and it stays silent while there (%s)" % str(music.call("audible")))
	# what is heard there is the body's bed and the song's own faint tine
	# (the spec's one exception), nothing from fp_music
	var hk: Node = m.get_node("AudioHookup")
	print("    in the flesh: bed %s, song_melody layer %.2f" % [hk.get("director").current_bed, float(hk.call("layer_level", "song_melody"))])
	m.player.global_position = c + Vector3(0, 0, -m.OUTER_RADIUS * 0.9)
	await frames(2)
	await run_for(5.0)
	_ok(music.call("audible").is_empty(), "not in the outer shell either")
	# Esc in the flesh: eyes shut, the lids' music; open them: silent again
	m.open_pause_menu()
	await frames(2)
	await run_for(3.0)
	_ok(music.get("place") == "pause" and on_music_bus("mus_pause") and float(music.call("level", "mus_pause")) > 0.99, "Esc plays mus_pause on the Music bus")
	m.pause_menu.resume()
	m._on_pause_resumed()
	await frames(2)
	await run_for(OUT_S)
	_ok(music.call("audible").is_empty(), "eyes open in the flesh: the music is gone within %.1f s" % OUT_S)
	# key settings stage
	m.open_keybind_menu()
	await frames(2)
	await run_for(3.0)
	_ok(music.get("place") == "keybind" and on_music_bus("mus_keybind") and float(music.call("level", "mus_keybind")) > 0.99, "key settings play mus_keybind on the Music bus")
	m.keybind_menu.close()
	await frames(2)
	# start screen
	m.player.global_position = c
	m.show_title()
	await frames(2)
	await run_for(3.0)
	_ok(music.get("place") == "title" and on_music_bus("mus_title") and float(music.call("level", "mus_title")) > 0.99, "start screen plays mus_title on the Music bus")
	_ok(music.call("audible") == ["mus_title"], "only one track left after the crossfade (%s)" % str(music.call("audible")))
	# the 배경음 slider is the Music bus
	var s: Dictionary = FPSettings.load_from().duplicate()
	s["music"] = 0.0
	FPSettings.apply_audio(s)
	_ok(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "배경음 0 mutes the Music bus the tracks play on")
	s["music"] = 0.5
	FPSettings.apply_audio(s)
	_ok(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.5)) < 0.01, "배경음 50 sets the Music bus to -6 dB")
	m.title_screen.close()
	paused = false
	# the ending has its own song: no background music under it
	m.ending.active = true
	await run_for(3.0)
	_ok(music.get("place") == "" and music.call("audible").is_empty(), "no background music under the ending's hum")
	m.ending.active = false
	_finish()

func _finish() -> void:
	print("--- %d passed, %d failed ---" % [_passed, _failed])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	if m != null:
		m.queue_free()
	quit(0 if _failed == 0 else 1)
