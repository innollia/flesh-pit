extends SceneTree

## Background music (audio/fp_music.gd, tools/build_music.py). Each place
## starts its own track on the Music bus, and none of them plays in the flesh
## (the flesh's songs are audio/fp_flesh_music.gd, tests/run_flesh_music_tests.gd). The restroom and the bowl are one piece of
## music: parallel stems in one player, chosen by what the game says
## (audio/room_music.json), never swapped, never by where you look. The room's
## bed (hum, exhaust fan) goes on under it and leaves with the room. Real main
## scene, isolated save.
##   godot_console --headless --path game --script res://tests/run_music_tests.gd

const SAVE := "user://music-test.bin"
## fp_music FADE_OUT_FLESH (0.8 s) plus a frame: gone by then.
const OUT_S := 1.0
## The room's stems, the one player they share.
const ROOM := "mus_room"
## Esc in the room.
const PIANO := "mus_pause_alt"
var _passed := 0
var _failed := 0
var m: Node3D
var music: Node

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_music.json"
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

## The restroom bed (manifest "beds"): the owner's hum plus the exhaust fan
## (tools/build_restroom_amb.py); the water in the pipes is one-shots at long
## gaps over it (audio/fp_pipe_water.gd, run_audio_tests.gd).
const BED_LAYERS := ["amb_restroom", "amb_restroom_fan"]

func bed_on_music_bus(d: FDKAudioDirector, layer: String) -> bool:
	var p := d.get_node_or_null("Bed_" + layer) as AudioStreamPlayer
	return p != null and p.bus == &"Music" and p.playing and p.stream != null

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
	# the room's music comes in slowly once the eyes have settled, over the
	# light's hum and the exhaust fan, which stay as they were
	await run_for(3.0)
	_ok(music.call("audible").is_empty(), "not yet 3 s after the opening")
	await run_for(12.5)
	_ok(music.get("place") == "room" and on_music_bus(ROOM) and float(music.call("level", ROOM)) > 0.99,
		"the room's music is up 15 s after the opening (%s, %s)" % [music.get("place"), str(music.call("audible"))])
	await _stems_are_one_piece()
	var hk: Node = m.get_node("AudioHookup")
	var d: FDKAudioDirector = hk.get("director")
	_ok(d.current_bed == "restroom", "the restroom bed plays in the room (%s)" % d.current_bed)
	for layer in BED_LAYERS:
		_ok(bed_on_music_bus(d, layer) and d.bed_layer_db(layer) > -0.5, "%s plays at full level on the Music bus" % layer)
	# the vent trade takes over while the grate is open
	m.vent.is_open = true
	await run_for(3.0)
	_ok(music.get("place") == "vent" and on_music_bus("mus_vent") and float(music.call("level", "mus_vent")) > 0.99, "vent open plays mus_vent on the Music bus")
	m.vent.is_open = false
	await run_for(3.0)
	_ok(music.get("place") == "room" and float(music.call("level", "mus_vent")) < 0.01,
		"grate shut: the trade's music is gone and the room's is back (%s)" % music.get("place"))
	await run_for(8.0)
	await _modal_places_in_room()
	await _bowl_is_the_same_music()
	await _never_by_the_eyes()
	await _situations()
	# out in the flesh: held still so the flesh does not push the body back
	m.set_process(false)
	m.set_physics_process(false)
	m.player.set_physics_process(false)
	var c: Vector3 = m.RESTROOM_CENTER
	m.player.global_position = c + Vector3(0, 0, -6.0)
	await frames(2)
	await run_for(OUT_S)
	_ok(music.get("place") == "" and music.call("audible").is_empty(), "in the flesh none of fp_music's places plays (%s)" % str(music.call("audible")))
	# the fan leaves with the room's hum, on the same 2 s fade
	await frames(1)
	_ok(d.current_bed != "restroom", "outside, the bed is the body's (%s)" % d.current_bed)
	var lv := {}
	for layer in BED_LAYERS:
		lv[layer] = d.bed_layer_db(layer)
	d.advance(0.9)
	var mid := {}
	for layer in BED_LAYERS:
		mid[layer] = d.bed_layer_db(layer)
	_ok(mid["amb_restroom"] < -1.0 and mid["amb_restroom"] > -60.0, "the room's hum is mid-fade (%.1f dB)" % mid["amb_restroom"])
	for layer in ["amb_restroom_fan"]:
		_ok(absf(mid[layer] - mid["amb_restroom"]) < 0.01, "%s fades with the room's hum (%.1f dB vs %.1f dB)" % [layer, mid[layer], mid["amb_restroom"]])
	d.advance(1.5)
	for layer in BED_LAYERS:
		_ok(d.bed_layer_db(layer) <= -60.0 and d.is_bed_layer_running(layer), "%s silent in the flesh, kept running for the way back" % layer)
	await run_for(20.0)
	_ok(music.call("audible").is_empty(), "and fp_music stays silent while there (%s)" % str(music.call("audible")))
	# what is heard there is the body's bed, the shell's song
	# (fp_flesh_music) and the ending song's faint tine in its rests
	print("    in the flesh: bed %s, song_melody layer %.2f" % [hk.get("director").current_bed, float(hk.call("layer_level", "song_melody"))])
	m.player.global_position = c + Vector3(0, 0, -m.OUTER_RADIUS * 0.9)
	await frames(2)
	await run_for(5.0)
	_ok(music.call("audible").is_empty(), "not in the outer shell either")
	# Esc in the flesh: eyes shut, the lids' music; open them: silent again
	m.open_pause_menu()
	await frames(2)
	await run_for(3.0)
	_ok(music.get("place") == "pause" and on_music_bus("mus_pause") and float(music.call("level", "mus_pause")) > 0.99, "Esc in the flesh plays mus_pause (the strings) on the Music bus")
	_ok(music.call("player", PIANO) == null or float(music.call("level", PIANO)) <= 0.0, "and never the piano there")
	m.pause_menu.resume()
	m._on_pause_resumed()
	await frames(2)
	await run_for(OUT_S)
	_ok(music.call("audible").is_empty(), "eyes open in the flesh: the music is gone within %.1f s" % OUT_S)
	# Tab out in the flesh: the forearm screen opens, fp_music's mirror track stays in the room
	m.open_mirror()
	await frames(2)
	await run_for(3.0)
	_ok(m.mirror.visible and music.get("place") == "" and music.call("audible").is_empty(), "Tab in the flesh plays no fp_music track (%s)" % music.get("place"))
	m.mirror.close()
	m.player.set_physics_process(false)
	await frames(2)
	# settings keep the music of the screen that opened them
	m.open_pause_menu()
	await frames(2)
	await run_for(3.0)
	m.open_settings()
	await frames(2)
	await run_for(3.0)
	_ok(m.settings_menu.is_open() and music.get("place") == "pause" and float(music.call("level", "mus_pause")) > 0.99, "settings from Esc keep mus_pause (%s)" % music.get("place"))
	m.settings_menu.close()
	await frames(2)
	_ok(m.pause_menu.is_open(), "closing settings goes back to Esc")
	m.pause_menu.resume()
	m._on_pause_resumed()
	await frames(2)
	await run_for(OUT_S)
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
	m.open_settings()
	await frames(2)
	await run_for(3.0)
	_ok(m.settings_menu.is_open() and music.get("place") == "title" and float(music.call("level", "mus_title")) > 0.99, "settings from the start screen keep mus_title (%s)" % music.get("place"))
	m.settings_menu.close()
	await frames(2)
	await run_for(3.0)
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

## Same place, same Esc music: shut your eyes in the room and it is the felt
## piano, whatever happened before; it does not change until the eyes open.
func _esc_by_where_the_eyes_shut() -> void:
	var room_player: AudioStreamPlayer = music.call("player", ROOM)
	m.open_pause_menu()
	await frames(2)
	await run_for(3.0)
	_ok(music.get("place") == "pause" and on_music_bus(PIANO) and float(music.call("level", PIANO)) > 0.99, "Esc in the room plays mus_pause_alt, the felt piano")
	_ok(music.call("player", "mus_pause") == null, "and not the strings")
	# nothing can move the body while paused, but if it did the song stays
	var at: Vector3 = m.player.global_position
	m.player.global_position = m.RESTROOM_CENTER + Vector3(0, 0, -6.0)
	await run_for(1.0)
	_ok(float(music.call("level", PIANO)) > 0.99 and music.call("player", "mus_pause") == null, "the song does not change until Esc is closed")
	m.player.global_position = at
	await frames(1)
	m.open_settings()
	await frames(2)
	await run_for(2.0)
	_ok(float(music.call("level", PIANO)) > 0.99, "settings from Esc in the room keep the piano")
	await run_for(6.0)
	_ok(music.call("player", ROOM) == room_player and room_player != null, "the room's music keeps its place under a long Esc")
	m.settings_menu.close()
	await frames(2)
	m.pause_menu.resume()
	m._on_pause_resumed()
	await frames(2)
	await run_for(3.0)
	_ok(music.get("place") == "room" and float(music.call("level", PIANO)) < 0.01, "eyes open: the room's music again (%s)" % music.get("place"))
	await run_for(8.0)

## The stems are one piece: same length, same rate, in one synchronized stream
## on one player, every one of them a manifest loop.
func _stems_are_one_piece() -> void:
	var bank: FDKSoundBank = m.get_node("AudioHookup").get("director").bank
	var data: Dictionary = music.call("room_data")
	_ok(data != null and not data.is_empty(), "room_music.json loads")
	var stems: Array = (data.get("층", {}) as Dictionary).keys()
	_ok(stems.size() >= 8, "at least eight stems (%d)" % stems.size())
	var length := -1.0
	var rate := -1
	var same := true
	for stem in stems:
		var id := String(data["층"][stem]["곡"])
		var wav := bank.stream(id, 0) as AudioStreamWAV
		_ok(bank.has(id) and bank.is_loop(id) and wav != null, "%s (%s) is a loop in the manifest" % [id, stem])
		if wav == null:
			continue
		if length < 0.0:
			length = wav.get_length()
			rate = wav.mix_rate
		same = same and absf(wav.get_length() - length) < 0.00001 and wav.mix_rate == rate
	_ok(same, "every stem has the same length and rate (%.3f s at %d)" % [length, rate])
	var beats := length * 54.0 / 60.0
	_ok(absf(beats - roundf(beats)) < 0.001, "the loop is whole beats at 54 bpm (%.2f beats)" % beats)
	var p: AudioStreamPlayer = music.call("player", ROOM)
	_ok(p != null and p.stream is AudioStreamSynchronized and (p.stream as AudioStreamSynchronized).stream_count == stems.size(), "one player, one synchronized stream")
	var players := music.get_children().filter(func(c): return c is AudioStreamPlayer)
	_ok(players.size() == 1, "the stems are not separate players (%d)" % players.size())
	# the situations' conditions read facts that exist, and quiet is quiet
	var facts: Dictionary = music.call("facts")
	var bad: Array = []
	for sit in data.get("상황", []):
		for key in (sit.get("조건", {}) as Dictionary).keys():
			if not facts.has(key):
				bad.append(key)
		for stem in (sit.get("층", {}) as Dictionary).keys():
			if not stems.has(stem):
				bad.append(stem)
	_ok(bad.is_empty(), "every condition and stem named in the situations exists %s" % str(bad))
	_ok(music.call("active_situations") == ["평소"], "fresh in the room only the quiet is active (%s)" % str(music.call("active_situations")))

func _modal_places_in_room() -> void:
	var bank: FDKSoundBank = m.get_node("AudioHookup").get("director").bank
	_ok(bank.has(PIANO) and bank.is_loop(PIANO), "mus_pause_alt is a loop in the manifest")
	_ok(not bank.has("mus_settle") and not bank.has("mus_restroom"), "the two old tracks are folded into the stems")
	var teeth_before: int = m.progression.teeth_in_hand
	var muts_before: Array[String] = m.progression.all_mutations()
	await _esc_by_where_the_eyes_shut()
	m.open_mirror()
	await frames(2)
	await run_for(2.0)
	_ok(music.get("place") == "mirror" and on_music_bus("mus_mirror") and float(music.call("level", "mus_mirror")) > 0.99, "Tab in the room plays mus_mirror on the Music bus (%s)" % music.get("place"))
	m.mirror.close()
	await frames(2)
	await run_for(3.0)
	_ok(music.get("place") == "room" and float(music.call("level", "mus_mirror")) < 0.01, "forearm down: the room's music again")
	await run_for(8.0)
	# sitting on the toilet is still the room
	_ok(m.sit_down(), "sat down")
	await run_for(3.0)
	_ok(music.get("place") == "room" and music.call("audible") == [ROOM], "sitting on the toilet is the room's music (%s)" % str(music.call("audible")))
	m.stand_up()
	_ok(m.progression.teeth_in_hand == teeth_before and m.progression.all_mutations() == muts_before, "the music changed nothing in progression")

## The largest change in any stem over one 0.1 s step while `sec` passes.
func track_stems(sec: float) -> float:
	var biggest := 0.0
	var t := 0.0
	var was: Dictionary = music.call("room_levels")
	while t < sec:
		music.call("step", 0.1)
		t += 0.1
		var now: Dictionary = music.call("room_levels")
		for k in now.keys():
			biggest = maxf(biggest, absf(float(now[k]) - float(was.get(k, 0.0))))
		was = now
	await process_frame
	return biggest

## Kneeling at the bowl and standing up again: the same player keeps running,
## nothing else comes in, the master does not move, and only the stems drift.
func _bowl_is_the_same_music() -> void:
	m.player.global_position = m.RESTROOM_CENTER
	var p: AudioStreamPlayer = music.call("player", ROOM)
	var before_id := p.get_instance_id() if p != null else 0
	var before: Dictionary = music.call("room_levels")
	m.start_settlement()
	await frames(2)
	_ok(m.is_settling(), "at the bowl")
	var biggest: float = await track_stems(0.8)
	var q: AudioStreamPlayer = music.call("player", ROOM)
	_ok(music.get("place") == "room" and music.call("audible") == [ROOM], "over the bowl the room's music goes on, nothing else plays (%s %s)" % [music.get("place"), str(music.call("audible"))])
	_ok(q != null and q.get_instance_id() == before_id and q.playing, "the same player, never restarted")
	_ok(float(music.call("level", ROOM)) > 0.99, "the master does not dip")
	_ok(biggest <= 0.0126, "the first 0.8 s moves any stem at most 1/8 per second (%.4f per 0.1 s)" % biggest)
	biggest = await track_stems(9.0)
	var over: Dictionary = music.call("room_levels")
	_ok(biggest <= 0.0126 and float(over.get("reckon", 0.0)) > float(before.get("reckon", 0.0)) + 0.2, "the reckoning stem rises slowly (%.2f)" % float(over.get("reckon", 0.0)))
	m.leave_settlement()
	await frames(2)
	biggest = await track_stems(14.0)
	var after: Dictionary = music.call("room_levels")
	_ok(biggest <= 0.0126 and float(after.get("reckon", 0.0)) <= float(before.get("reckon", 0.0)) + 0.001, "standing up it sinks back as slowly (%.2f)" % float(after.get("reckon", 0.0)))
	var r: AudioStreamPlayer = music.call("player", ROOM)
	_ok(r != null and r.get_instance_id() == before_id, "and it is still the same player")

## Where you look changes nothing: a whole turn, at the bowl, the mirror, the door.
func _never_by_the_eyes() -> void:
	var before: Dictionary = music.call("room_levels")
	var same := not before.is_empty()
	for i in range(36):
		m.player.rotation.y = TAU * float(i) / 36.0
		music.call("step", 0.1)
		same = same and music.call("room_levels") == before and music.get("place") == "room"
	await process_frame
	m.player.rotation.y = 0.0
	_ok(same, "a whole turn in the room changes no stem")

## Out through the door and back with main held still, so the flesh does not
## push the body around; `out` is what happens while away.
func _trip(out: Callable) -> void:
	var c: Vector3 = m.RESTROOM_CENTER
	m.player.global_position = c + Vector3(0, 0, -6.0)
	await frames(1)
	await run_for(0.3)
	await out.call()
	await run_for(0.3)
	m.player.global_position = c
	await frames(1)
	await run_for(16.0)

func _hears(stem: String, situation: String) -> void:
	var t: Dictionary = music.call("room_targets")
	var active: Array = music.call("active_situations")
	_ok(active.has(situation), "%s is active (%s)" % [situation, str(active)])
	_ok(float(t.get(stem, 0.0)) > 0.2 and float((music.call("room_levels") as Dictionary).get(stem, 0.0)) > 0.2, "%s brings up %s (%.2f)" % [situation, stem, float(t.get(stem, 0.0))])

func _situations() -> void:
	m.set_process(false)
	m.set_physics_process(false)
	m.player.set_physics_process(false)
	var quiet: Dictionary = music.call("room_targets")
	# a short trip, nothing dug: the quiet comes back
	await _trip(func(): pass)
	_ok(music.call("active_situations") == ["평소"], "a walk to the door and back changes nothing (%s)" % str(music.call("active_situations")))
	_ok(music.call("room_targets") == quiet, "same stems as before")
	# back from a big dig
	await _trip(func():
		m.excavated_cells += 60
		await run_for(0.2))
	_hears("dread", "많이_파고_옴")
	_ok(float((music.call("facts") as Dictionary).get("이번_굴착", 0.0)) >= 60.0, "the dig is counted")
	await run_for(260.0)
	_ok(not music.call("active_situations").has("많이_파고_옴"), "the fear wears off after minutes in the room (%s)" % str(music.call("active_situations")))
	# a long stay: the same clock, now past the long-stay line
	await run_for(30.0)
	_hears("linger", "오래_안_나감")
	# a small dig is not a big dig
	await _trip(func():
		m.excavated_cells += 5
		await run_for(0.2))
	_ok(not music.call("active_situations").has("많이_파고_옴"), "a few cells are not a big dig")
	_ok(not music.call("active_situations").has("오래_안_나감"), "and going out ended the long stay")
	# the stomach
	m.stomach.fill = m.stomach_config.capacity
	await run_for(10.0)
	_hears("gut", "위장이_참")
	m.stomach.fill = 0.0
	await run_for(14.0)
	_ok(not music.call("active_situations").has("위장이_참"), "emptied, the stem goes")
	# a tumor eaten out there
	await _trip(func():
		m.progression.eat_tumor_kind("T1")
		await run_for(0.2))
	_hears("wrong", "종양을_먹음")
	# a big settlement
	m.toilet.vomit_into(240.0)
	var got: Dictionary = m.pull_lever()
	await run_for(10.0)
	_hears("gold", "이빨을_많이_정산")
	_ok(int(got["teeth"]) >= 12, "the bowl paid %d teeth" % int(got["teeth"]))
	await run_for(100.0)
	_ok(not music.call("active_situations").has("이빨을_많이_정산"), "that wears off too")
	# dying: main.die moves the body back; the lids must finish first
	m.excavated_cells += 60
	m.player.global_position = m.RESTROOM_CENTER + Vector3(0, 0, -6.0)
	await frames(1)
	await run_for(3.0)
	m.die("test")
	await frames(1)
	_ok(m.wake_lids.playing(), "waking behind the lids")
	music.call("step", 0.1)
	_ok(music.get("place") == "", "nothing starts behind the lids (%s)" % music.get("place"))
	m.wake_lids.set("_t", -1.0)
	await run_for(16.0)
	_hears("cold", "죽고_돌아옴")
	_ok(not music.call("active_situations").has("많이_파고_옴"), "death takes the place of the fear")
	# the glare on the way back holds the start until the eyes have adjusted
	m.player.global_position = m.RESTROOM_CENTER + Vector3(0, 0, -6.0)
	await frames(1)
	await run_for(6.0)
	_ok(music.call("audible").is_empty(), "out again, nothing plays")
	m.player.global_position = m.RESTROOM_CENTER
	m.glare_controller.flash = 1.0
	await frames(1)
	for i in range(25):
		music.call("step", 0.1)
		m.glare_controller.flash = maxf(0.0, m.glare_controller.flash - 0.04)
	await process_frame
	_ok(music.call("audible").is_empty(), "under the glare no music")
	m.glare_controller.flash = 0.0
	await run_for(5.5)
	_ok(music.call("audible").is_empty(), "nor for the 6 s after it clears")
	await run_for(1.0)
	_ok(float(music.call("level", ROOM)) > 0.0 and float(music.call("level", ROOM)) < 0.2, "then it rises slowly (%.2f)" % float(music.call("level", ROOM)))
	m.set_process(true)
	m.set_physics_process(true)
	m.player.set_physics_process(true)
	await frames(1)

func _finish() -> void:
	print("--- %d passed, %d failed ---" % [_passed, _failed])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	if m != null:
		m.queue_free()
	quit(0 if _failed == 0 else 1)
