extends SceneTree

## Audio self-tests (no GUT). Run:
##   Godot_console.exe --headless --path <game> --script tests/run_audio_tests.gd
## Exit 0 = all passed.

const MANIFEST := "res://audio/manifest.json"
var _passed := 0
var _failed := 0

## run_godot_checks.cjs puts the isolated save path in here.
func _init() -> void:
	pass

func _initialize() -> void:
	print("=== flesh-pit audio tests ===")
	_test_manifest_files()
	_test_no_repeat()
	_test_bed_transition()
	_test_chew_speed()
	_test_signals_and_steps()
	_test_heart_and_hum_loops()
	_test_restroom_water_assets()
	_test_pipe_water_gaps()
	# integration: the real main scene; main.gd adds the hookup itself (the
	# one line in audio/HOOKUP.md), so use that node, never a second one
	_main = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	_main.user_keybinds_path = "user://keybinds_test_audio.json"
	root.add_child(_main)
	# (_hook is looked up once main's _ready has run, in _process)

var _main: Node
var _hook: Node
var _frames := 0

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 90:
		return false
	if _frames > 90:
		return _layer_steps(_delta)
	_hook = _main.get_node_or_null("AudioHookup")
	_ok(_hook != null, "main.gd adds the audio hookup itself")
	if _hook == null:
		print("--- %d passed, %d failed ---" % [_passed, _failed])
		quit(1)
		return true
	var d: FDKAudioDirector = _hook.get("director")
	_ok(d != null, "hookup creates the director inside main")
	if d != null:
		_ok(d.bank.sounds.size() >= 30, "hookup loads the game manifest")
		_ok(d.current_bed == "restroom", "game starts on the restroom bed (%s)" % d.current_bed)
		_ok(d.bed_layer_db("amb_restroom") > -0.5, "restroom bed audible at start")
		_ok(d.surface == "tile", "start surface is tile")
		_test_step_room(d)
		var chewer = _main.get("chewer")
		if chewer is FDKChewer:
			(chewer as FDKChewer).cell_torn.emit(Vector3(0, 1, 3))
			_ok(d.last_played.begins_with("tear_"), "main's chewer drives tear sounds (%s)" % d.last_played)
		# stage-5 event sounds: every one is in the manifest and plays by name
		var events: Dictionary = _hook.get("EVENT_SOUNDS")
		var all_ok := true
		for ev in events.keys():
			_hook.call("play_event", ev)
			if not d.bank.has(String(events[ev])) or d.last_played != String(events[ev]):
				all_ok = false
				print("  missing event sound: ", ev)
		_ok(all_ok and events.size() == 26, "all 26 event sounds (stage 5, the T1 tongue click, the canary, squeezing past flesh, a refused grip, a dry heave, the tank rattle, M23 hairs, the M15 gulp, the vent spill, the mirror refusal) load and play (%d)" % events.size())
		_main.emit_signal("died", "test")
		_ok(d.last_played == "player_death", "main.died plays the death sound (%s)" % d.last_played)
		var mirror = _main.get("mirror")
		if mirror != null and mirror.has_signal("mutated"):
			mirror.emit_signal("mutated", "test")
			_ok(d.last_played == "mirror_mutate", "mirror.mutated plays the mutation sound (%s)" % d.last_played)
		# the seven events that got signals in main now reach their sounds
		var dirs := _main.find_children("*", "FDKAudioDirector", true, false).size()
		_ok(dirs == 1, "exactly one audio director under main (%d)" % dirs)
		var sigs := [["spray_used", [Vector3(0, 1, 3)], "spray_hiss"], ["blender_drunk", [], "blender_drink"],
			["scissors_snipped", [], "scissors_snip"], ["saw_stroked", [], "saw_stroke"],
			["settle_ticked", [4], "settle_tick"], ["ui_clicked", [], "ui_click"]]
		for s in sigs:
			_main.callv("emit_signal", [s[0]] + s[1])
			_ok(d.last_played == s[2], "main.%s plays %s (%s)" % [s[0], s[2], d.last_played])
		_main.mutation_apply.tumor_eaten.emit()
		_ok(d.last_played == "tumor_eat", "mutation_apply.tumor_eaten plays tumor_eat (%s)" % d.last_played)
		_main.mutation_apply.echo_click.emit()
		_ok(d.last_played == "echo_click", "mutation_apply.echo_click plays the T1 tongue click (%s)" % d.last_played)
		_main.canary_cry.emit(true)
		_ok(d.last_played == "canary_wrong", "a frightened canary cries (%s)" % d.last_played)
		_main.terrain.contraction_warning.emit(Vector3(0, 1, 4))
		_ok(d.last_played == "regen_creak", "a wall about to squeeze creaks first (%s)" % d.last_played)
		_main.toilet.tank_rattle_started.emit(0.5, false)
		_ok(d.last_played == "coin_drop", "teeth rattle down into the tank (%s)" % d.last_played)
		_main.toilet.tank_rattle_finished.emit()
		# wire-sound 2026-11-03: signals that had no listener now sound
		var ma = _main.mutation_apply
		var pe: Array = _hook.get("played_events")
		ma.alien_hand_tore.emit()
		_ok(d.last_played.begins_with("tear_") and pe.back() == "alien_tear", "1-3 M22 the alien hand's own tear sounds like a tear (%s)" % d.last_played)
		ma.hair_shiver_started.emit()
		_ok(d.last_played == "hair_rustle", "1-4 M23 the stiff arm hairs rustle before a squeeze (%s)" % d.last_played)
		# M15: the real gulp of a carried pile (the stomach swallow is another sound)
		_main.carried_flesh = 1.0
		_main.carried_units = {0: 1.0}
		ma.gulp()
		_ok(pe.has("gulp") and d.played_log.has("gulp_whole") and d.bank.has("gulp_whole") and not (d.bank.sounds["gulp_whole"]["files"] as Array).has(d.bank.sounds["swallow"]["files"][0]), "1-5 M15 a whole pile goes down with its own gulp (%s)" % d.last_played)
		# an absurd overpay at the real vent: early items tumble out
		var prog = _main.progression
		_main.vent.open()
		var spilled_ids: Array = []
		_main.vent.spilled.connect(func(ids): spilled_ids.append_array(ids))
		_main.vent.place_teeth(prog.vent_absurd_threshold(), prog)
		_ok(not spilled_ids.is_empty() and pe.back() == "vent_spill" and d.last_played == "vent_spill", "1-2 an absurd overpay spills items with a clatter (%s, %s)" % [str(spilled_ids), d.last_played])
		_main.vent.close()
		# the mirror refuses a part the hairs cannot pay for
		_main.open_mirror()
		_main.mirror.focus_part("face")
		var bought: String = _main.mirror.buy_current()
		_ok(bought == "" and d.last_played == "ui_deny" and pe.back() == "mirror_denied", "1-10 the mirror's refusal has its own short sound (%s)" % d.last_played)
		_main.mirror.close()
		_ok(_hook.call("_regrowing_spot") == null, "no creak without flesh really growing back nearby")
		_main.flush()
		_ok(_hook.get("played_events").has("settle_tick"), "the lever's flush ticks the settle sound")
		_main.vomit_button.pressed.emit()
		_ok(d.last_played == "ui_click" or _hook.get("played_events").back() == "ui_click", "the vomit button clicks")
	return _layer_steps(_delta)

## Steady layers (D03 M03 magnet hum, D05 ending song): the game state is set
## once per step and the hookup's own _process follows it for LAYER_WAIT s.
## Main's own process is held still so the player standing in solid flesh is
## not crushed back to the restroom between steps.
const LAYER_WAIT := 1.0
var _layer_step := 0
var _layer_t := -1.0

func _finish() -> bool:
	_main.free()
	FDKPs1Material.clear_cache()
	print("--- %d passed, %d failed ---" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
	return true

func _face(target: Vector3) -> void:
	var pl: Node3D = _main.player
	var flat := Vector3(target.x, pl.global_position.y, target.z)
	pl.look_at(flat, Vector3.UP)

func _layer_steps(delta: float) -> bool:
	if _hook == null or _hook.get("director") == null:
		return _finish()
	if _layer_t >= 0.0:
		_layer_t += delta
		if _layer_t < _step_wait:
			return false
		_step_wait = LAYER_WAIT
	var lv := func(id: String) -> float: return float(_hook.call("layer_level", id))
	var c: Vector3 = _main.RESTROOM_CENTER
	var prog = _main.progression
	match _layer_step:
		0:
			for id in ["magnet_hum", "song_melody", "song_hum", "song_voice2"]:
				var pl = _hook.get_node_or_null("Layer_" + id)
				_ok(pl is AudioStreamPlayer and (pl as AudioStreamPlayer).playing, "steady layer %s is loaded and running" % id)
				_ok(pl is AudioStreamPlayer and (pl as AudioStreamPlayer).bus == &"Music", "1-6 steady layer %s follows the music slider (bus %s)" % [id, (pl as AudioStreamPlayer).bus if pl is AudioStreamPlayer else &"-"])
			_ok(lv.call("magnet_hum") == 0.0 and lv.call("song_melody") == 0.0 and lv.call("song_hum") == 0.0, "in the restroom without M03 every steady layer is silent")
			_main.set_process(false)
			_main.set_physics_process(false)
			_main.player.set_physics_process(false)
			prog.mutation_tree._purchased["M03"] = true
			# the tine sounds in the flesh music's rests (audio/fp_flesh_music.gd):
			# hold that music in a rest here so the tine's own level is judged
			var fm: Node = _hook.get_node_or_null("FleshMusic")
			if fm != null:
				fm.set_process(false)
			_main.player.global_position = c + Vector3(0, 0, -6.0)
			_face(c)
		1:
			var want: float = _main.mutation_apply.magnet_hum_level()
			_ok(want > 0.5 and absf(lv.call("magnet_hum") - want) < 0.01, "D03 M03 facing the restroom hums in the ears (%.2f, game %.2f)" % [lv.call("magnet_hum"), want])
			_ok((_hook.get_node("Layer_magnet_hum") as AudioStreamPlayer).volume_db > -6.0, "D03 the hum player is audible (%.1f dB)" % (_hook.get_node("Layer_magnet_hum") as AudioStreamPlayer).volume_db)
			var m1: float = lv.call("song_melody")
			_ok(m1 > 0.0 and absf(m1 - _main.melody_level() * _hook.MELODY_IN_FLESH * (1.0 - float(_hook.call("flesh_music_level")))) < 0.01, "D05 just outside the restroom, in a rest of the flesh's songs, the melody is faint (%.3f)" % m1)
			_face(c + Vector3(0, 0, -20.0))
		2:
			_ok(lv.call("magnet_hum") == 0.0, "D03 facing away from the restroom the hum stops (%.2f)" % lv.call("magnet_hum"))
			_layer_near = float(lv.call("song_melody"))
			_main.player.global_position = c + Vector3(0, 0, -_main.OUTER_RADIUS * 0.95)
			_face(c)
		3:
			var far: float = lv.call("song_melody")
			_ok(far > _layer_near and far <= _hook.MELODY_IN_FLESH + 0.001, "D05 the melody grows toward the outer shell and stays faint (%.3f -> %.3f)" % [_layer_near, far])
			_ok(lv.call("magnet_hum") > 0.0, "D03 the hum works from the outer shell too")
			prog.mutation_tree._purchased.erase("M03")
		4:
			_ok(lv.call("magnet_hum") == 0.0, "D03 without M03 facing the restroom is silent")
			_ok(lv.call("song_hum") == 0.0 and lv.call("song_voice2") == 0.0, "D05 no humming before the ending")
			# the real breakthrough: main starts the ending with 1 + codex voices
			_main.player.global_position = c + Vector3(0, 0, _main.OUTER_RADIUS)
			_main.step_world(0.016)
			_ok(_main.ending.active and _main.ending.voice_layers == 1, "the breakthrough starts the ending with one voice (codex not complete)")
		5:
			_ok(lv.call("song_hum") > 0.99 and lv.call("song_melody") == 0.0, "D05 at the ending the hum takes the tune over from the tine")
			_ok(lv.call("song_voice2") == 0.0, "D05 an incomplete codex adds no second voice")
			_ok((_hook.get("director") as FDKAudioDirector).current_bed == "ending", "D05 on the street the body bed is let go")
			var pos := []
			for id in ["song_melody", "song_hum", "song_voice2"]:
				pos.append((_hook.get_node("Layer_" + id) as AudioStreamPlayer).get_playback_position())
			_ok(absf(pos[0] - pos[1]) < 0.1 and absf(pos[0] - pos[2]) < 0.1, "D05 the song layers play in step %s" % str(pos))
			# a complete codex: main passes two voices (1 + codex_complete)
			_main.ending.active = false
			_main.ending.start(2)
		6:
			_ok(lv.call("song_voice2") > 0.99 and lv.call("song_hum") > 0.99, "D05 a complete codex adds the second voice")
			var dd: FDKAudioDirector = _hook.get("director")
			var loud := -80.0
			for layer in ["amb_body_a", "amb_heart_a", "amb_body_b", "amb_heart_b"]:
				if dd.is_bed_layer_running(layer):
					loud = maxf(loud, dd.bed_layer_db(layer))
			_ok(loud < -12.0, "D05 the body drone fades out under the ending hum (%.1f dB)" % loud)
			_main.ending.active = false
			# 1-7: a whole tumor in the bowl, the real lever: the clatter
			# lasts as long as the tank shakes and stops with it
			_main.toilet.bowl_tumors.append("core_knot")
			_rattle_from = _rattle_count()
			_rattle = float(_main.flush().get("rattle", 0.0))
			_ok(_rattle > FPToiletSettlement.RATTLE_TUMOR_EXTRA, "a thrown tumor makes the rattle much longer (%.2f s)" % _rattle)
			_step_wait = _rattle - 0.4
		7:
			var n := _rattle_count() - _rattle_from
			_ok(_main.toilet.is_rattling() and _hook.has_method("is_rattling") and _hook.call("is_rattling"), "1-7 the clatter still sounds near the end of the long rattle")
			_ok(n >= int(_rattle / RATTLE_GAP_MAX) - 1, "1-7 teeth keep clattering for the whole tumor rattle (%d clinks in %.1f s)" % [n, _rattle - 0.4])
			_rattle_from = _rattle_count()
			_step_wait = 0.8
		8:
			_ok(not _main.toilet.is_rattling() and _hook.has_method("is_rattling") and not bool(_hook.call("is_rattling")), "1-7 the clatter ends with tank_rattle_finished")
			_rattle_from = _rattle_count()
			_step_wait = 0.8
		9:
			_ok(_rattle_count() == _rattle_from, "1-7 no clink after the tank is still")
			_water_in_room_start()
			_step_wait = 2.3
		10:
			_water_leaving_start()
			_step_wait = 1.0
		11:
			_water_leaving_mid()
			_step_wait = 2.5
		12:
			_water_left()
			return _finish()
	_layer_step += 1
	_layer_t = 0.0
	return false

var _layer_near := 0.0
var _rattle := 0.0
var _rattle_from := 0
var _step_wait := LAYER_WAIT
const RATTLE_GAP_MAX := 0.45

func _rattle_count() -> int:
	return (_hook.get("played_events") as Array).count("tank_rattle")

## Restroom water in the real main: armed only in the room, played by the
## hookup's own node, and an event under way fades with the bed.
func _pipe_water() -> Node:
	return _hook.get_node_or_null("PipeWater")

func _water_in_room_start() -> void:
	var w := _pipe_water()
	_ok(w != null, "the hookup plays the restroom water")
	if w == null:
		return
	# the player was moved out by the layer steps; back in the room the bed
	# returns, the water timer rearms and never fires straight away
	var d: FDKAudioDirector = _hook.get("director")
	_main.ending.active = false
	_main.player.global_position = _main.RESTROOM_CENTER
	_hook.call("_process_inner", 0.016)
	_ok(d.current_bed == "restroom", "back in the room for the water check (%s)" % d.current_bed)
	_ok(bool(w.call("is_armed")) and float(w.call("seconds_to_next")) >= 20.0, "entering the room arms the water, not right away (%.1f s)" % float(w.call("seconds_to_next")))

func _water_leaving_start() -> void:
	var w := _pipe_water()
	if w == null:
		return
	var d: FDKAudioDirector = _hook.get("director")
	_ok(d.bed_layer_db("amb_restroom") > -1.0, "the room's bed is back up (%.1f dB)" % d.bed_layer_db("amb_restroom"))
	w.call("play_take", "pipe_run")
	_water_voice = w.call("voice")
	_ok(_water_voice is AudioStreamPlayer and _water_voice.is_inside_tree(), "a water take plays on its own voice")
	_ok(_water_voice != null and String(_water_voice.name).begins_with("Bed_"), "the water follows the same volume slider as its bed")
	_main.player.global_position = _main.RESTROOM_CENTER + Vector3(0, 0, -6.0)

func _water_leaving_mid() -> void:
	var w := _pipe_water()
	if w == null:
		return
	var d: FDKAudioDirector = _hook.get("director")
	var bed := d.bed_layer_db("amb_restroom")
	_ok(d.current_bed != "restroom" and bed < -1.0 and bed > -60.0, "the bed is mid-fade (%s %.1f dB)" % [d.current_bed, bed])
	_ok(absf((_water_voice as AudioStreamPlayer).volume_db - bed) < 1.5, "the water fades with the bed (%.1f dB vs %.1f dB)" % [(_water_voice as AudioStreamPlayer).volume_db, bed])
	_ok(not bool(w.call("is_armed")), "out in the flesh the water is not armed")

func _water_left() -> void:
	var w := _pipe_water()
	if w == null:
		return
	_ok(w.call("voice") == null, "the water take stopped with the bed gone")
	var heard: int = (w.get("played") as Array).size()
	for k in range(600):
		w.call("step", 1.0, false)
	_ok((w.get("played") as Array).size() == heard, "no water in the flesh in ten minutes")

var _water_voice: Object

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + msg)

func _director() -> FDKAudioDirector:
	var d := FDKAudioDirector.new()
	d.bank = FDKSoundBank.from_file(MANIFEST)
	root.add_child(d)
	return d

func _test_manifest_files() -> void:
	var bank := FDKSoundBank.from_file(MANIFEST)
	_ok(bank.sounds.size() >= 30, "manifest has the full sound list (%d)" % bank.sounds.size())
	var missing := 0
	for id in bank.sounds.keys():
		for i in range(bank.variation_count(id)):
			var s := bank.stream(id, i)
			if s == null:
				missing += 1
				printerr("  cannot load %s #%d" % [id, i])
			elif bank.is_loop(id) and s is AudioStreamWAV:
				_ok((s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loops" % id)
		if not bank.is_loop(id):
			_ok(bank.variation_count(id) == 4, "%s has 4 variations" % id)
	_ok(missing == 0, "every manifest file loads as an AudioStream")
	for bed in ["restroom", "body_a", "body_b"]:
		_ok(bank.beds.has(bed), "bed %s defined" % bed)

func _test_no_repeat() -> void:
	var bank := FDKSoundBank.from_file(MANIFEST)
	bank.rng.seed = 12345
	for id in bank.sounds.keys():
		var n := bank.variation_count(id)
		if n < 2:
			continue
		var prev := -1
		var repeats := 0
		var seen := {}
		for k in range(400):
			var i := bank.pick_index(id)
			if i == prev:
				repeats += 1
			seen[i] = true
			prev = i
		_ok(repeats == 0, "%s never repeats a variation back to back (%d repeats)" % [id, repeats])
		_ok(seen.size() == n, "%s uses all %d variations" % [id, n])

func _test_bed_transition() -> void:
	var d := _director()
	d.set_bed("restroom", 0.0)
	d.advance(0.05)
	_ok(d.bed_layer_db("amb_restroom") > -0.5, "restroom bed at full level")
	_ok(d.bed_layer_db("amb_body_a") <= -60.0, "body bed silent in restroom")
	d.set_bed("body_a", 1.0)
	d.advance(0.5)
	var mid_room := d.bed_layer_db("amb_restroom")
	var mid_body := d.bed_layer_db("amb_body_a")
	_ok(mid_room < -0.5 and mid_room > -60.0 and mid_body > -60.0 and mid_body < -0.5, "halfway through a crossfade both beds sound (%.1f / %.1f dB)" % [mid_room, mid_body])
	d.advance(0.6)
	_ok(d.bed_layer_db("amb_body_a") > -0.5 and d.bed_layer_db("amb_heart_a") > -0.5, "body_a drone + heart at full level")
	_ok(d.bed_layer_db("amb_restroom") <= -60.0, "restroom faded out")
	_ok(d.is_bed_layer_running("amb_restroom"), "faded layer is kept running, not restarted")
	_ok(not d.is_bed_layer_running("amb_body_b"), "a bed nobody asked for does not run")
	d.advance(d.BED_RELEASE + 0.1)
	_ok(not d.is_bed_layer_running("amb_restroom"), "a layer silent for %.0f s stops" % d.BED_RELEASE)
	_ok(d.is_bed_layer_running("amb_body_a"), "the playing bed keeps running")
	d.shell = 0
	d.set_shell(2)
	_ok(d.played_log.has("depth_marker") and d.played_log.has("shell_transition"), "going deeper plays depth marker + transition")
	d.advance(3.1)
	_ok(d.current_bed == "body_b" and d.bed_layer_db("amb_body_b") > -0.5 and d.bed_layer_db("amb_body_a") <= -60.0, "deep shell switches to body_b")
	d.free()

func _test_chew_speed() -> void:
	var d := _director()
	var cfg := FDKStomachConfig.new()
	var st := FDKStomach.new()
	st.config = cfg
	root.add_child(st)
	d.connect_stomach(st)
	d._on_grab_started(Vector3i.ZERO)
	d.advance(0.016)
	_ok(d.is_chew_active() and d.chew_loop_id() == "chew_loop_a", "grab starts the chew loop")
	_ok(is_equal_approx(d.chew_player_pitch(), 1.0), "empty stomach chews at normal speed")
	var prev := d.chew_player_pitch()
	var monotonic := true
	for k in range(60):
		st.add_flesh(cfg.capacity * 0.05)
		d.advance(0.016)
		var expect := clampf(1.0 / st.chew_time_multiplier(), d.chew_pitch_min, 1.0)
		if absf(d.chew_player_pitch() - expect) > 0.0001:
			monotonic = false
		if d.chew_player_pitch() > prev + 0.0001:
			monotonic = false
		prev = d.chew_player_pitch()
	_ok(monotonic, "chew speed follows 1/chew_time_multiplier and only slows while overfilling")
	_ok(st.overfill_ratio() > 0.0 and d.chew_player_pitch() < 1.0, "overfilled chewing is slower (pitch %.2f, mult %.2f, overfill %.2f, player %s)" % [d.chew_player_pitch(), st.chew_time_multiplier(), st.overfill_ratio(), str(d._chew)])
	_ok(d.strain_level() > 0.0, "strain layer rises with overfill")
	d.set_mutation_stage(1)
	_ok(d.chew_loop_id() == "chew_loop_b", "mutation changes the chewing sound")
	d._on_released()
	_ok(not d.is_chew_active(), "release stops the chew loop")
	d.free()
	st.free()

func _test_signals_and_steps() -> void:
	var d := _director()
	var chewer := FDKChewer.new()
	root.add_child(chewer)
	d.connect_chewer(chewer)
	chewer.cell_torn.emit(Vector3.ZERO)
	_ok(d.last_played == "tear_flesh", "cell_torn plays a tear (no terrain -> flesh)")
	d.advance(0.35)
	_ok(d.last_played == "swallow", "a swallow follows the tear")
	chewer.grab_started.emit(Vector3i.ZERO)
	_ok(d.is_chew_active(), "grab_started signal starts chewing")
	chewer.released.emit()
	_ok(not d.is_chew_active(), "released signal stops chewing")
	# two bob cycles -> two steps
	d.set_surface("tile")
	d.set_mutation_stage(2)
	for k in range(200):
		d.on_footstep_bob(Vector3(0, sin(k * TAU / 100.0) * 0.05, 0))
	_ok(d.steps_played == 2, "one footstep per bob trough (%d)" % d.steps_played)
	_ok(d.last_played == "step_tile_s3", "footstep uses surface + mutation stage")
	d.free()
	chewer.free()
	_test_step_variation()
	_test_step_files()

## round7-sfx: the steps sound in the room the feet are in. The Room bus
## carries a reverb, sends to SFX (the slider still sets it), and the flesh
## room is more damped than the tiled one, with the flesh steps lower.
func _test_step_room(d: FDKAudioDirector) -> void:
	var i := AudioServer.get_bus_index(&"Room")
	_ok(i >= 0 and AudioServer.get_bus_send(i) == &"SFX", "a Room bus sends to SFX (%d)" % i)
	var rv: AudioEffectReverb = AudioServer.get_bus_effect(i, 0) as AudioEffectReverb if i >= 0 and AudioServer.get_bus_effect_count(i) > 0 else null
	_ok(rv != null, "the Room bus has a reverb")
	_ok(d.room_bus == &"Room", "footsteps play on the Room bus (%s)" % d.room_bus)
	_ok(_hook.call("room") == "tile" and is_equal_approx(d.step_gain_db, 0.0), "the restroom is the tiled room, steps at full level")
	if rv == null:
		return
	var tile_damp := rv.damping
	_hook.call("_set_room", "flesh")
	_ok(rv.damping > tile_damp and rv.room_size < 0.3 and d.step_gain_db < -1.0, "in the flesh the room is damped and small, steps lower (damp %.2f > %.2f, %.1f dB)" % [rv.damping, tile_damp, d.step_gain_db])
	_hook.call("_set_room", "tile")
	_ok(is_equal_approx(rv.damping, tile_damp), "back in the restroom the tiled room returns")

## round7-sfx: a walk is not one sample fired again and again. Each step is a
## little off in pitch and level, never far enough to sound like another foot.
func _test_step_variation() -> void:
	var d := _director()
	d.step_gain_db = -3.0
	var lo := 9.0
	var hi := 0.0
	var dlo := 99.0
	var dhi := -99.0
	for k in range(60):
		d.play_step()
		lo = minf(lo, d.last_step_pitch)
		hi = maxf(hi, d.last_step_pitch)
		dlo = minf(dlo, d.last_step_db)
		dhi = maxf(dhi, d.last_step_db)
	var j := d.step_pitch_jitter
	_ok(lo >= 1.0 - j - 0.0001 and hi <= 1.0 + j + 0.0001 and j <= 0.06, "footstep pitch stays within +-%.2f (%.3f..%.3f)" % [j, lo, hi])
	_ok(hi - lo > j, "footstep pitch really varies over 60 steps (%.3f..%.3f)" % [lo, hi])
	var g := d.step_gain_jitter_db
	_ok(dlo >= -3.0 - g - 0.001 and dhi <= -3.0 + g + 0.001 and dhi - dlo > g, "footstep level varies around step_gain_db by at most +-%.1f dB (%.2f..%.2f)" % [g, dlo, dhi])
	var pitched := 0
	for c in d.get_children():
		if c is AudioStreamPlayer and not is_equal_approx((c as AudioStreamPlayer).pitch_scale, 1.0):
			pitched += 1
	_ok(pitched > 0 or not d.is_inside_tree(), "the step player gets its pitch (%d)" % pitched)
	var tlo := 9.0
	var thi := 0.0
	for k in range(60):
		d._on_cell_torn(Vector3.ZERO)
		tlo = minf(tlo, d.last_tear_pitch)
		thi = maxf(thi, d.last_tear_pitch)
	var tj := d.tear_pitch_jitter
	_ok(d.last_played.begins_with("tear_") and tlo >= 1.0 - tj - 0.0001 and thi <= 1.0 + tj + 0.0001 and thi - tlo > tj and tj <= 0.05, "each tear is a little off in pitch, within +-%.2f (%.3f..%.3f)" % [tj, tlo, thi])
	d.free()

## round7-sfx: the footsteps are rebuilt without the PS1 crunch and without a
## pure-tone thud, so no step rings at one pitch. Pitch clarity is the highest
## normalised autocorrelation at 70 Hz..1 kHz in the 50 ms after the peak; the
## old step_tile_s2 and step_flesh_s2 had 0.6 and 0.5. Four variations each,
## level within a few dB of each other.
func _test_step_files() -> void:
	var worst := 0.0
	var worst_id := ""
	var spread_ok := true
	for surface in ["flesh", "tile"]:
		for s in range(1, 4):
			var id := "step_%s_s%d" % [surface, s]
			var lv: Array[float] = []
			for v in range(1, 5):
				var path := "res://audio/sfx/%s_v%d.wav" % [id, v]
				var x := _wav_left(path)
				_ok(x.size() > 4800, "%s_v%d is there" % [id, v])
				lv.append(_db(_power(x)))
				if v == 1:
					var c := _pitch_clarity(x)
					if c > worst:
						worst = c
						worst_id = id
			if lv.max() - lv.min() > 4.0:
				spread_ok = false
	_ok(worst < 0.4, "no footstep rings at one pitch (worst %s %.2f < 0.40)" % [worst_id, worst])
	_ok(spread_ok, "each footstep's four variations are within 4 dB")

func _pitch_clarity(x: PackedFloat32Array) -> float:
	var peak := 0
	for i in range(x.size()):
		if absf(x[i]) > absf(x[peak]):
			peak = i
	var n := 2400
	var seg := x.slice(peak, mini(peak + n, x.size()))
	var e0 := 0.0
	for i in range(seg.size()):
		e0 += seg[i] * seg[i]
	if e0 <= 0.0:
		return 0.0
	var best := 0.0
	var lag := 48
	while lag < 686:
		var acc := 0.0
		for i in range(seg.size() - lag):
			acc += seg[i] * seg[i + lag]
		best = maxf(best, acc / e0)
		lag += 2
	return best

## Reader for the builders' plain 16-bit wavs: left channel, -1..1.
func _wav_left(path: String) -> PackedFloat32Array:
	var b := FileAccess.get_file_as_bytes(path)
	var at := 12
	while at + 8 < b.size():
		var size := b.decode_u32(at + 4)
		if b.slice(at, at + 4).get_string_from_ascii() == "data":
			var ch := b.decode_u16(22)
			var out := PackedFloat32Array()
			out.resize(size / (2 * ch))
			for i in range(out.size()):
				out[i] = b.decode_s16(at + 8 + i * 2 * ch) / 32768.0
			return out
		at += 8 + size + (size & 1)
	return PackedFloat32Array()

## Butterworth high-pass, two poles.
func _highpass(x: PackedFloat32Array, hz: float) -> PackedFloat32Array:
	var w := TAU * hz / 48000.0
	var a := sin(w) / sqrt(2.0)
	var c := cos(w)
	var a0 := 1.0 + a
	var b0 := (1.0 + c) * 0.5 / a0
	var b1 := -(1.0 + c) / a0
	var a1 := -2.0 * c / a0
	var a2 := (1.0 - a) / a0
	var y := PackedFloat32Array()
	y.resize(x.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in range(x.size()):
		var v := b0 * x[i] + b1 * x1 + b0 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x[i]
		y2 = y1
		y1 = v
		y[i] = v
	return y

func _power(x: PackedFloat32Array, from: int = 0, to: int = -1) -> float:
	var end := x.size() if to < 0 else to
	var sum := 0.0
	for i in range(from, end):
		sum += x[i] * x[i]
	return sum / maxf(float(end - from), 1.0)

func _db(p: float) -> float:
	return 10.0 * log(maxf(p, 1e-14)) / log(10.0)

## Short-time levels (dB), one per window.
func _levels(x: PackedFloat32Array, window: int) -> Array[float]:
	var out: Array[float] = []
	var at := 0
	while at + window <= x.size():
		out.append(_db(_power(x, at, at + window)))
		at += window
	return out

## Lubs per loop: the level rises through (peak - 12 dB), the dub falls
## inside the hold-off.
func _beats(x: PackedFloat32Array) -> int:
	var lv := _levels(x, 960)
	var top: float = lv.max()
	var n := 0
	var hold := 0
	for i in range(lv.size()):
		hold -= 1
		if lv[i] > top - 12.0 and hold <= 0:
			n += 1
			hold = 50
	return n

func _test_heart_and_hum_loops() -> void:
	# owner, listening: amb_heart_b could not be heard at all. The beat must
	# live where speakers reach, not under 60 Hz.
	var want := {"amb_heart_a": 6, "amb_heart_b": 5}
	for id in want.keys():
		var x := _wav_left("res://audio/loops/%s.wav" % id)
		var hi := _highpass(x, 70.0)
		var share := _power(hi) / maxf(_power(x), 1e-14)
		_ok(share > 0.6, "%s lives above 70 Hz (%.0f%% of its energy)" % [id, share * 100.0])
		_ok(_db(_power(hi)) > -36.0, "%s is up in the audible band (%.1f dB above 70 Hz)" % [id, _db(_power(hi))])
		var low: float = _levels(_highpass(x, 170.0), 2400).max()
		_ok(low > -34.0, "%s reaches a laptop speaker (beat %.1f dB above 170 Hz)" % [id, low])
		_ok(_beats(x) == want[id], "%s keeps its own pace (%d beats per 8 s)" % [id, _beats(x)])
	# the room's hum must not surge: the old 8 s trickle swing read as water
	var room := _wav_left("res://audio/loops/amb_restroom.wav")
	var hiss := _levels(_highpass(_highpass(room, 3500.0), 3500.0), 24000)
	_ok(hiss.max() - hiss.min() < 2.0, "amb_restroom's top no longer swells on the loop (%.1f dB swing)" % (hiss.max() - hiss.min()))
	var all := _levels(room, 24000)
	_ok(all.max() - all.min() < 1.0, "amb_restroom's body stays level (%.1f dB swing)" % (all.max() - all.min()))

const PIPE_TAKES := ["pipe_trickle", "pipe_run", "pipe_glug", "pipe_tick"]

func _test_restroom_water_assets() -> void:
	var bank := FDKSoundBank.from_file(MANIFEST)
	_ok(not (bank.beds["restroom"] as Array).has("amb_restroom_pipes"), "the restroom bed no longer holds the water loop")
	_ok((bank.beds["restroom"] as Array).has("amb_restroom") and (bank.beds["restroom"] as Array).has("amb_restroom_fan"), "the hum and the fan stay in the bed")
	for id in PIPE_TAKES:
		_ok(bank.has(id) and not bank.is_loop(id), "%s is a one-shot water take" % id)
		for bed in bank.beds.keys():
			_ok(not (bank.beds[bed] as Array).has(id), "%s is not in bed %s" % [id, bed])

## Hours of simulated room time: the gaps are long, random and uneven, the
## first one is never right at entry, and leaving stops the water.
func _test_pipe_water_gaps() -> void:
	if not ResourceLoader.exists("res://audio/fp_pipe_water.gd"):
		_ok(false, "audio/fp_pipe_water.gd plays the restroom water")
		return
	var d := _director()
	d.set_bed("restroom", 0.0)
	var w: Node = load("res://audio/fp_pipe_water.gd").new()
	w.set("director", d)
	root.add_child(w)
	var firsts: Array[float] = []
	var gaps: Array[float] = []
	var seen := {}
	var t := 0.0
	var repeats := 0
	var dt := 0.25
	seed(1)  # the game's own random state must not matter here
	var game_draw := randi()
	seed(1)
	var played: Array = w.get("played")
	for visit in range(40):
		var entered := t
		var last_end := -1.0
		var stay := 900.0 if visit % 2 == 0 else 12.0
		while t < entered + stay:
			t += dt
			var heard := played.size()
			w.call("step", dt, true)
			if played.size() == heard:
				continue
			seen[played.back()] = true
			if played.size() >= 2 and played[played.size() - 1] == played[played.size() - 2]:
				repeats += 1
			if last_end < 0.0:
				firsts.append(t - entered)
			else:
				gaps.append(t - last_end)
			last_end = t + float(w.call("seconds_left"))
		var before := played.size()
		for k in range(240):
			t += dt
			w.call("step", dt, false)
		_ok(played.size() == before, "visit %d: no water while out of the room" % visit)
	_ok(randi() == game_draw, "the water never draws from the game's random numbers")
	_ok(gaps.size() >= 20, "enough events to judge the gaps (%d)" % gaps.size())
	var low := 1e9
	var high := 0.0
	for g in gaps:
		low = minf(low, g)
		high = maxf(high, g)
	_ok(low >= 44.5 and high <= 150.5, "gaps stay in 45-150 s (%.1f..%.1f)" % [low, high])
	_ok(high - low > 50.0, "the gaps are uneven, not one cycle (%.1f..%.1f)" % [low, high])
	var first_low := 1e9
	for f in firsts:
		first_low = minf(first_low, f)
	_ok(not firsts.is_empty() and first_low >= 20.0, "the first water is never right at entry (%.1f s, %d entries)" % [first_low, firsts.size()])
	_ok(seen.size() == PIPE_TAKES.size(), "all the takes come up (%s)" % str(seen.keys()))
	_ok(repeats == 0, "never the same take twice in a row (%d)" % repeats)
	w.free()
	d.free()
