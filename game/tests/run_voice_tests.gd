extends SceneTree

## Recorded vent voice (audio/fp_vent_voice.gd): a line with a file plays and
## the subtitle stays as long as the clip, a line without one is subtitle
## only, the next line cuts the one playing. Clips are plain tones written to
## a temp folder for this run, never into res://audio/voice.
##   FP_CHECK_SUITES=run_voice_tests.gd node --test game/tests/run_godot_checks.cjs

var _passed := 0
var _failed := 0
var _main: Node
var _voice: Node
var _vent: Node
var _subs: FPSubtitles
var _dir := ""
var _cuts: Array[String] = []

## run_godot_checks.cjs puts the isolated save path in here.
func _init() -> void:
	pass

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: " + msg)

func _initialize() -> void:
	print("=== vent voice tests ===")
	_dir = OS.get_temp_dir().path_join("fp_voice_%d" % OS.get_process_id()).replace("\\", "/")
	DirAccess.make_dir_recursive_absolute(_dir)
	_write_tone("first.heard", 1.2)
	_write_tone("first.tsk", 6.0)
	_write_tone("first.hello", 0.5)
	_write_tone("tank.leave", 0.2)
	_write_bytes("flush.a1.wav", "not a wav".to_utf8_buffer())
	_write_tone("flush.a2", 0.0)
	_write_extensible("flush.a3", 0.75)
	_main = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	_main.user_keybinds_path = _dir.path_join("keybinds.json")
	root.add_child(_main)
	_run.call_deferred()

func _frames(n: int) -> void:
	for _i in n:
		await process_frame

func _finish() -> void:
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)
	print("--- %d passed, %d failed ---" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _run() -> void:
	await _frames(90)
	_voice = _main.get_node_or_null("AudioHookup/Voice")
	_ok(_voice != null, "the audio hookup adds the voice layer")
	if _voice == null:
		_finish()
		return
	_vent = _main.get("vent")
	_subs = _main.get("subtitles")
	_voice.set("voice_dir", _dir)
	_vent.set("instant_voice", true)
	_voice.connect("voice_cut", func(id: String): _cuts.append(id))
	_test_no_file()
	_test_file_plays()
	_test_voice_sets_subtitle_time()
	_test_bad_files()
	_test_extensible_wav()
	await _test_next_line_cuts()
	await _test_silent_line_cuts()
	await _test_natural_end()
	_test_silent_lines_still_queue()
	await _test_voiced_line_jumps_queue()
	_test_settings()
	_finish()

## Puts subtitles and voice back to nothing between checks.
func _reset() -> void:
	_voice.call("stop")
	_subs._queue.clear()
	_subs._left = 0.0
	_subs.current_text = ""
	_subs.band.visible = false
	_cuts.clear()

func _say(id: String) -> void:
	_vent.call("_say", id)

func _player() -> AudioStreamPlayer:
	return _voice.get("player")

func _test_no_file() -> void:
	_reset()
	_say("first.nobody")
	_ok(String(_voice.get("current_id")) == "" and not _player().playing, "no file: nothing plays")
	var t := FPSubtitles.line_text("first.nobody")
	_ok(_subs.current_text == t, "no file: the subtitle still shows")
	var want := maxf(FPSubtitles.MIN_TIME, t.length() * FPSubtitles.PER_CHAR)
	_ok(is_equal_approx(_subs._left, want), "no file: subtitle time is the reading estimate")

func _test_file_plays() -> void:
	_reset()
	_say("first.heard")
	_ok(String(_voice.get("current_id")) == "first.heard", "file: the voice takes the line")
	_ok(_player().playing, "file: the player runs")
	_ok(_player().stream != null and absf(_player().stream.get_length() - 1.2) < 0.01, "file: the clip for this id is loaded")
	_ok(String(_player().bus) == "Voice", "voice goes through its own bus")
	_ok(AudioServer.get_bus_index("Voice") >= 0, "the voice bus exists")

func _test_voice_sets_subtitle_time() -> void:
	# much shorter than the reading estimate
	_reset()
	_say("first.heard")
	var est := FPSubtitles.line_text("first.heard").length() * FPSubtitles.PER_CHAR
	_ok(est > 2.5, "first.heard estimate is long enough to tell apart")
	_ok(absf(_subs._left - (1.2 + FPSubtitles.VOICE_TAIL)) < 0.01, "short clip: the subtitle follows the clip (%.2f)" % _subs._left)
	# much longer than the reading estimate
	_reset()
	_say("first.tsk")
	_ok(absf(_subs._left - (6.0 + FPSubtitles.VOICE_TAIL)) < 0.01, "long clip: the subtitle stays for the clip (%.2f)" % _subs._left)
	# a clip of a grunt still leaves time to read it
	_reset()
	_say("tank.leave")
	_ok(is_equal_approx(_subs._left, FPSubtitles.VOICE_MIN_TIME), "tiny clip: subtitle stays the minimum")

func _test_bad_files() -> void:
	_reset()
	_say("flush.a1")
	_ok(String(_voice.get("current_id")) == "" and not _player().playing, "broken file: subtitle only")
	_ok(_subs.current_text == FPSubtitles.line_text("flush.a1"), "broken file: the subtitle shows")
	_reset()
	_say("flush.a2")
	_ok(String(_voice.get("current_id")) == "", "empty clip: subtitle only")

func _test_extensible_wav() -> void:
	_reset()
	_say("flush.a3")
	_ok(String(_voice.get("current_id")) == "flush.a3", "24-bit extensible WAV plays")
	_ok(_player().stream != null and absf(_player().stream.get_length() - 0.75) < 0.01, "24-bit clip has its length")

func _test_next_line_cuts() -> void:
	_reset()
	_say("first.tsk")
	await _frames(3)
	_say("first.hello")
	_ok(_cuts == ["first.tsk"], "the next line cuts the one playing once (%s)" % [_cuts])
	_ok(String(_voice.get("current_id")) == "first.hello" and _player().playing, "the new line plays")
	_ok(absf(_player().stream.get_length() - 0.5) < 0.01, "the new line's clip is in the player")
	_ok(_subs.current_text == FPSubtitles.line_text("first.hello"), "the subtitle moves with the voice at once")
	_ok(_subs.queued() == 0, "the voiced line does not also wait in the queue")

func _test_silent_line_cuts() -> void:
	_reset()
	_say("first.tsk")
	await _frames(3)
	_say("first.nobody")
	_ok(_cuts == ["first.tsk"], "a line without a file also cuts the voice")
	_ok(String(_voice.get("current_id")) == "" and not _player().playing, "nothing plays after that cut")
	await _frames(2)
	_ok(_subs.current_text == FPSubtitles.line_text("first.nobody"), "the cut subtitle gives way to the silent line")
	_ok(_subs.queued() == 0, "the silent line left the queue")

func _test_natural_end() -> void:
	_reset()
	_say("tank.leave")
	var waited := 0
	while String(_voice.get("current_id")) != "" and waited < 180:
		await create_timer(0.05).timeout
		waited += 1
	_ok(String(_voice.get("current_id")) == "", "a clip that ends leaves the voice free")
	_ok(_cuts.is_empty(), "a clip that ends is not a cut")

func _test_silent_lines_still_queue() -> void:
	_reset()
	_say("first.nobody")
	_say("distract.sink")
	_ok(_subs.current_text == FPSubtitles.line_text("first.nobody"), "silent lines: the first stays up")
	_ok(_subs.queued() == 1, "silent lines: the second waits its turn as before")

func _test_voiced_line_jumps_queue() -> void:
	_reset()
	_say("first.nobody")
	_say("distract.sink")
	_say("first.hello")
	_ok(_subs.current_text == FPSubtitles.line_text("first.hello"), "a voiced line shows while it is being said")
	_ok(_subs.queued() == 1, "other waiting lines stay queued")
	await _frames(1)
	_reset()

func _test_settings() -> void:
	var d := FPSettings.defaults()
	_ok(is_equal_approx(float(d.get("voice", -1.0)), 1.0), "voice volume has a default")
	var old := FPSettings.sanitize({"master": 0.5})
	_ok(is_equal_approx(float(old.get("voice", -1.0)), 1.0), "a settings file from before keeps working")
	_ok(float(FPSettings.sanitize({"voice": 9})["voice"]) == 1.0, "voice volume is clamped")
	var s := FPSettings.defaults()
	s["voice"] = 0.5
	FPSettings.apply_audio(s)
	var i := AudioServer.get_bus_index("Voice")
	_ok(absf(AudioServer.get_bus_volume_db(i) - linear_to_db(0.5)) < 0.01, "voice volume on the bus")
	s["voice"] = 0.0
	FPSettings.apply_audio(s)
	_ok(AudioServer.is_bus_mute(i), "voice volume zero mutes")
	FPSettings.apply_audio(FPSettings.defaults())
	_ok(not AudioServer.is_bus_mute(i), "voice volume comes back")
	# old callers pass only the three they knew
	FPSettings.apply_audio({"master": 1.0, "sfx": 1.0, "music": 1.0})
	_ok(not AudioServer.is_bus_mute(i), "apply_audio without a voice value keeps working")
	FPSettings.apply_audio(FPSettings.defaults())
	var sm = _main.get("settings_menu")
	_ok(sm != null and sm.sliders.has("voice"), "the settings menu has a voice slider")
	if sm != null and sm.sliders.has("voice"):
		_ok(sm.call("_text_for", "voice") == "100%", "the voice slider reads as a percent")

func _write_tone(id: String, seconds: float) -> void:
	var rate := 48000
	var n := int(seconds * rate)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in n:
		pcm.encode_s16(i * 2, int(sin(TAU * 220.0 * i / rate) * 6000.0))
	_write_bytes(id + ".wav", _wav_header(n * 2, rate) + pcm)

## What editors write for 24-bit: format tag 0xFFFE, the real format in a GUID.
func _write_extensible(id: String, seconds: float) -> void:
	var rate := 48000
	var n := int(seconds * rate)
	var pcm := PackedByteArray()
	pcm.resize(n * 3)
	for i in n:
		var v := int(sin(TAU * 220.0 * i / rate) * 1500000.0)
		pcm.encode_u16(i * 3, v & 0xFFFF)
		pcm.encode_u8(i * 3 + 2, (v >> 16) & 0xFF)
	var h := PackedByteArray()
	h.resize(68)
	h.encode_u32(0, 0x46464952)
	h.encode_u32(4, 60 + pcm.size())
	h.encode_u32(8, 0x45564157)
	h.encode_u32(12, 0x20746d66)
	h.encode_u32(16, 40)
	h.encode_u16(20, 0xFFFE)
	h.encode_u16(22, 1)
	h.encode_u32(24, rate)
	h.encode_u32(28, rate * 3)
	h.encode_u16(32, 3)
	h.encode_u16(34, 24)
	h.encode_u16(36, 22)
	h.encode_u16(38, 24)
	h.encode_u32(40, 4)
	h.encode_u16(44, 1) # GUID starts with the real format: PCM
	h.encode_u32(60, 0x61746164)
	h.encode_u32(64, pcm.size())
	_write_bytes(id + ".wav", h + pcm)

func _wav_header(data_size: int, rate: int) -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(44)
	h.encode_u32(0, 0x46464952) # RIFF
	h.encode_u32(4, 36 + data_size)
	h.encode_u32(8, 0x45564157) # WAVE
	h.encode_u32(12, 0x20746d66) # fmt
	h.encode_u32(16, 16)
	h.encode_u16(20, 1) # PCM
	h.encode_u16(22, 1) # mono
	h.encode_u32(24, rate)
	h.encode_u32(28, rate * 2)
	h.encode_u16(32, 2)
	h.encode_u16(34, 16)
	h.encode_u32(36, 0x61746164) # data
	h.encode_u32(40, data_size)
	return h

func _write_bytes(file_name: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(_dir.path_join(file_name), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
