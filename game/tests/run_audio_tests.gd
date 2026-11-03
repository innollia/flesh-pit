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
	# integration: the real main scene; main.gd adds the hookup itself (the
	# one line in audio/HOOKUP.md), so use that node, never a second one
	_main = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
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
		_ok(all_ok and events.size() == 21, "all 21 event sounds (stage 5, the T1 tongue click, the canary, squeezing past flesh, a refused grip, a dry heave) load and play (%d)" % events.size())
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
		if _layer_t < LAYER_WAIT:
			return false
	var lv := func(id: String) -> float: return float(_hook.call("layer_level", id))
	var c: Vector3 = _main.RESTROOM_CENTER
	var prog = _main.progression
	match _layer_step:
		0:
			for id in ["magnet_hum", "song_melody", "song_hum", "song_voice2"]:
				var pl = _hook.get_node_or_null("Layer_" + id)
				_ok(pl is AudioStreamPlayer and (pl as AudioStreamPlayer).playing, "steady layer %s is loaded and running" % id)
			_ok(lv.call("magnet_hum") == 0.0 and lv.call("song_melody") == 0.0 and lv.call("song_hum") == 0.0, "in the restroom without M03 every steady layer is silent")
			_main.set_process(false)
			_main.set_physics_process(false)
			_main.player.set_physics_process(false)
			prog.mutation_tree._purchased["M03"] = true
			_main.player.global_position = c + Vector3(0, 0, -6.0)
			_face(c)
		1:
			var want: float = _main.mutation_apply.magnet_hum_level()
			_ok(want > 0.5 and absf(lv.call("magnet_hum") - want) < 0.01, "D03 M03 facing the restroom hums in the ears (%.2f, game %.2f)" % [lv.call("magnet_hum"), want])
			_ok((_hook.get_node("Layer_magnet_hum") as AudioStreamPlayer).volume_db > -6.0, "D03 the hum player is audible (%.1f dB)" % (_hook.get_node("Layer_magnet_hum") as AudioStreamPlayer).volume_db)
			var m1: float = lv.call("song_melody")
			_ok(m1 > 0.0 and absf(m1 - _main.melody_level() * _hook.MELODY_IN_FLESH) < 0.01, "D05 just outside the restroom the melody is faint (%.3f)" % m1)
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
			return _finish()
	_layer_step += 1
	_layer_t = 0.0
	return false

var _layer_near := 0.0

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
