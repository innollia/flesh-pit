extends SceneTree

## Music out in the flesh (audio/fp_flesh_music.gd, audio/flesh_music.json,
## tools/build_flesh_music.py). User 2026-11-07: "살 팔때도 음악 들리기". One
## song per shell (core lab_emotion, mantle lab_materials, surface
## lab_cycle), the same in the same shell, never by the eyes, nothing random;
## a shell change waits for the song's phrase mark and crossfades; a song
## plays once and a rest of silence follows (the ending tune's tine fills it);
## a rest container is a rest; Esc holds the song; the room and the ending
## have none. The body's bed steps back while a song is up. Real main scene,
## isolated save; the music is stepped by hand.
##   godot_console --headless --path game --script res://tests/run_flesh_music_tests.gd

const SAVE := "user://flesh-music-test.bin"
const SONGS := ["mus_flesh_core", "mus_flesh_mantle", "mus_flesh_surface"]
const DT := 0.1
var _passed := 0
var _failed := 0
var m: Node3D
var fm: Node
var hk: Node
var d: FDKAudioDirector

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_flesh_music.json"
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

## Steps the flesh music by `sec` (and the hookup's layers and bed duck with it).
func run_for(sec: float) -> void:
	var t := 0.0
	while t < sec - 0.0001:
		fm.call("step", DT)
		hk.call("_process_inner", DT)
		d.advance(DT)
		t += DT
	await process_frame

## A point at `depth` from the room's centre, clear of every rest container.
func spot(depth: float, turn: float = 0.0) -> Vector3:
	var c: Vector3 = m.RESTROOM_CENTER
	for k in range(64):
		var a := turn + k * 0.39
		var p := c + Vector3(sin(a), 0.0, -cos(a)) * depth
		var clear := true
		for r in m.rest_points:
			if (r as Vector3).distance_to(p) < 4.0:
				clear = false
		if clear and p.z < c.z - 3.0:
			return p
	return c + Vector3(0, 0, -depth)

func go(p: Vector3) -> void:
	m.player.global_position = p

func cur_db() -> float:
	var p: AudioStreamPlayer = fm.call("current_player")
	return p.volume_db if p != null else -80.0

func _run() -> void:
	print("=== flesh-pit flesh music tests ===")
	await frames(10)
	hk = m.get_node("AudioHookup")
	d = hk.get("director")
	fm = m.get_node_or_null("AudioHookup/FleshMusic")
	_ok(fm != null, "the audio hookup adds the flesh music node")
	if fm == null:
		_finish()
		return
	fm.set_process(false)
	hk.set_process(false)
	d.set_process(false)
	var data: Dictionary = fm.call("data")
	var shells: Array = data.get("shells", [])
	_ok(shells.size() == 3, "one song per shell, three shells (%d)" % shells.size())
	for i in range(mini(shells.size(), 3)):
		var sh: Dictionary = shells[i]
		var id := String(sh.get("song", ""))
		_ok(id == SONGS[i], "shell %d plays %s (%s)" % [i, SONGS[i], id])
		_ok(d.bank.has(id) and d.bank.is_loop(id) and d.bank.stream(id, 0) != null, "%s is a loop in the manifest" % id)
		var ph: Array = sh.get("phrases", [])
		_ok(ph.size() >= 4 and float(ph[0]) == 0.0 and float(ph[-1]) < float(sh.get("loop_seconds", 0.0)), "%s has its phrase marks from the build (%d)" % [id, ph.size()])
	_ok(String(shells[0].get("source", "")) == "lab_emotion" and String(shells[1].get("source", "")) == "lab_materials" and String(shells[2].get("source", "")) == "lab_cycle",
		"the songs are the candidates the user liked: emotion, materials, cycle outward")
	var prog_before := [m.excavated_cells, m.stomach.fill]

	# the room: none of this plays
	m.finish_opening()
	await frames(2)
	m.set_process(false)
	m.set_physics_process(false)
	m.player.set_physics_process(false)
	await run_for(5.0)
	_ok(fm.call("audible").is_empty() and fm.get("phase") == "off", "in the restroom the flesh music is off (%s)" % fm.get("phase"))

	# out into the core: its song comes in, on the Music bus
	var core := spot(6.5)
	go(core)
	await run_for(0.2)
	_ok(fm.get("song") == SONGS[0], "out the door into the core: %s starts (%s)" % [SONGS[0], fm.get("song")])
	await run_for(3.0)
	var p: AudioStreamPlayer = fm.call("current_player")
	_ok(p != null and p.bus == &"Music" and p.playing, "it plays on the Music bus (the music slider sets it)")
	_ok(absf(cur_db() - float(shells[0].get("gain_db", 0.0))) < 0.5, "up to its level after the fade-in (%.1f dB)" % cur_db())
	_ok(absf(d.bed_gain_db - float(data.get("bed_duck_db", 0.0))) < 0.2 and d.bed_gain_db < -1.0, "the body's bed steps back under it (%.1f dB)" % d.bed_gain_db)
	_ok(float(hk.call("layer_level", "song_melody")) < 0.01, "the ending tine gives way while a song plays (%.3f)" % float(hk.call("layer_level", "song_melody")))
	# never by the eyes
	var before_song := String(fm.get("song"))
	for k in range(8):
		m.player.rotate_y(0.8)
		await run_for(0.5)
	_ok(fm.get("song") == before_song and fm.get("phase") == "play", "turning around changes nothing (%s)" % fm.get("song"))

	# into the mantle: the core's song plays on to its phrase mark, then crossfades
	var pos0: float = fm.get("_pos")
	var mark: float = fm.call("_next_mark", 0, pos0)
	go(spot(13.0))
	await run_for(0.2)
	_ok(fm.get("song") == SONGS[0] and fm.get("phase") == "switch", "just past the membrane the song is not cut (%s, %s)" % [fm.get("song"), fm.get("phase")])
	await run_for(maxf(mark - pos0 - 0.4, 0.0))
	_ok(fm.get("song") == SONGS[0], "it waits for the phrase mark at %.1f s" % mark)
	await run_for(0.4)
	_ok(fm.get("song") == SONGS[1], "at the mark the mantle's song takes over (%s)" % fm.get("song"))
	_ok(fm.call("audible").has(SONGS[0]), "the core's song is still fading under it (crossfade, not a cut): %s" % str(fm.call("audible")))
	await run_for(float(data.get("crossfade", 3.0)) + 0.3)
	_ok(fm.call("audible") == [SONGS[1]], "after the crossfade only the mantle's song (%s)" % str(fm.call("audible")))
	# a step back over the membrane and back again before a mark changes nothing
	var at: float = fm.get("_pos")
	var m2: float = fm.call("_next_mark", 1, at)
	if m2 - at < 1.5:
		await run_for(m2 - at + 0.2)
	go(spot(6.5))
	await run_for(0.5)
	go(spot(13.0))
	await run_for(0.5)
	_ok(fm.get("song") == SONGS[1] and fm.get("phase") == "play", "a step back and forth before the mark keeps the song (%s %s)" % [fm.get("song"), fm.get("phase")])

	# the song plays once through, then a rest of silence
	var loop_s := float(shells[1].get("loop_seconds", 100.0))
	await run_for(loop_s - float(fm.get("_pos")) - 3.0)
	_ok(fm.get("phase") == "ending" and cur_db() < float(shells[1].get("gain_db", 0.0)) - 3.0, "over its last bars the song fades (%.1f dB)" % cur_db())
	await run_for(3.5)
	_ok(fm.get("phase") == "rest" and fm.get("song") == "", "at its end a rest begins (%s)" % fm.get("phase"))
	await run_for(1.0)
	_ok(fm.call("audible").is_empty(), "the rest is silent (%s)" % str(fm.call("audible")))
	_ok(absf(d.bed_gain_db) < 0.05, "the bed is back to its own level in the rest (%.2f dB)" % d.bed_gain_db)
	_ok(float(hk.call("layer_level", "song_melody")) > 0.0, "the ending tine fills the rest (%.3f)" % float(hk.call("layer_level", "song_melody")))
	var rest_s := float(data.get("rest_seconds", 75.0))
	await run_for(rest_s - 3.0)
	_ok(fm.call("audible").is_empty(), "still silent %.0f s into the rest" % (rest_s - 2.0))
	await run_for(2.5)
	_ok(fm.get("song") == SONGS[1] and float(fm.get("_pos")) < 1.0, "after the rest the same shell's song starts again from its top (%s)" % fm.get("song"))
	# the same state plays the same song: no draw anywhere
	_ok(fm.call("song_for_shell", 1) == fm.call("song_for_shell", 1) and fm.call("song_for_shell", 7) == SONGS[2], "the song follows the shell and nothing else")

	# a rest container is a rest
	if m.rest_points.size() > 0:
		var rp: Vector3 = m.rest_points[0]
		go(rp)
		await run_for(0.2)
		_ok(fm.call("where") == "rest" and fm.get("phase") == "rest", "inside a rest container the song stops (%s)" % fm.get("phase"))
		await run_for(5.0)
		_ok(fm.call("audible").is_empty(), "and is gone within 5 s")
		var rshell: int = m.shell_at(rp)
		go(spot(FPWorldFeatures.REST_DEPTH[rshell] + 0.5, 2.0))
		await run_for(2.0)
		_ok(fm.call("audible").is_empty() and fm.get("phase") == "rest", "stepping out of it the rest goes on in the same shell (%s, %s, shell %d -> %d)" % [fm.get("phase"), fm.call("where"), rshell, fm.call("shell_now")])
		# crossing into another shell during a rest starts that shell's song at once
		var other := 0 if rshell != 0 else 1
		go(spot(6.5 if other == 0 else 13.0))
		await run_for(0.2)
		_ok(fm.get("song") == SONGS[other] and fm.get("phase") == "play", "a new shell during a rest starts its song at once (%s)" % fm.get("song"))
	else:
		_ok(false, "the world has rest containers")

	# Esc in the flesh: the strings take over, the song holds its place
	go(spot(22.0))
	await run_for(30.0)
	_ok(fm.get("song") == SONGS[2], "in the surface its song plays (%s)" % fm.get("song"))
	var held: float = fm.get("_pos")
	m.open_pause_menu()
	await frames(2)
	await run_for(3.0)
	var pp: AudioStreamPlayer = fm.call("current_player")
	_ok(fm.call("audible").is_empty() and pp != null and pp.stream_paused, "under Esc the song fades and holds (%s)" % str(fm.call("audible")))
	_ok(absf(float(fm.get("_pos")) - held) < 0.01, "its place is kept while the eyes are shut")
	m.pause_menu.resume()
	m._on_pause_resumed()
	await frames(2)
	await run_for(3.5)
	_ok(fm.get("song") == SONGS[2] and not pp.stream_paused and absf(cur_db() - float(shells[2].get("gain_db", 0.0))) < 0.5, "eyes open: the same song comes back where it was (%.1f dB)" % cur_db())
	# Tab out in the flesh keeps it
	m.open_mirror()
	await frames(2)
	await run_for(1.0)
	_ok(fm.get("song") == SONGS[2] and not fm.call("audible").is_empty(), "Tab in the flesh keeps the song")
	m.mirror.close()

	# back in the room: gone, and fp_music's room is untouched by it
	go(m.RESTROOM_CENTER)
	await run_for(float(data.get("leave_fade", 2.0)) + 0.3)
	_ok(fm.call("audible").is_empty() and fm.get("phase") == "off", "back in the restroom the flesh music is gone (%s)" % str(fm.call("audible")))
	_ok(absf(d.bed_gain_db) < 0.05, "and the room's bed is at its own level (%.2f dB)" % d.bed_gain_db)
	_ok(m.excavated_cells == prog_before[0] and is_equal_approx(m.stomach.fill, prog_before[1]), "the music changed no progression")
	_finish()

func _finish() -> void:
	print("--- %d passed, %d failed ---" % [_passed, _failed])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	if m != null:
		m.queue_free()
	quit(0 if _failed == 0 else 1)
