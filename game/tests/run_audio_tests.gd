extends SceneTree

## Audio self-tests (no GUT). Run:
##   Godot_console.exe --headless --path <game> --script tests/run_audio_tests.gd
## Exit 0 = all passed.

const MANIFEST := "res://audio/manifest.json"
var _passed := 0
var _failed := 0

func _initialize() -> void:
	print("=== flesh-pit audio tests ===")
	_test_manifest_files()
	_test_no_repeat()
	_test_bed_transition()
	_test_chew_speed()
	_test_signals_and_steps()
	# integration: the real main scene with the hookup added from outside,
	# exactly as the one line in audio/HOOKUP.md would add it
	_main = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_hook = (load("res://audio/fp_audio_hookup.gd") as GDScript).new()
	_main.add_child(_hook)

var _main: Node
var _hook: Node
var _frames := 0

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 90:
		return false
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
	_main.free()
	FDKPs1Material.clear_cache()
	print("--- %d passed, %d failed ---" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
	return true

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
