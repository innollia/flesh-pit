extends Node

## Music out in the flesh (user 2026-11-07: "살 팔때도 음악 들리기"), one song
## per shell, the candidate songs the user liked (tools/build_flesh_music.py):
##
##   shell 0, the core      mus_flesh_core     (lab_emotion)
##   shell 1, the mantle    mus_flesh_mantle   (lab_materials)
##   shell 2, the surface   mus_flesh_surface  (lab_cycle)
##
## The shell is what the player knows: the membrane between shells has to be
## dug through, the knife gate is the mantle's, the settlement pays by shell.
## Biomes are not used (several per shell, five beds for three songs), nor
## where you look, nor anything random. Same shell, same song.
##
## A change never cuts: when the shell under the player differs from the
## song's, the song plays on to its next phrase mark (audio/flesh_music.json
## "phrases", from the build) and only then crossfades into the new song from
## its start; walking back before the mark changes nothing.
##
## Long trips: a song plays once through, fades over its last bars and then
## there is silence for rest_seconds, only the body's bed and the ending
## song's faint tine (the hookup's song_melody fills the rests). Crossing
## into another shell during a rest starts that shell's song at once. A rest
## container is a rest: the song fades and the silence starts there.
##
## Not in the restroom, not at the ending (fp_music and the song layers have
## those), and not under Esc or the key settings (fp_music's mus_pause):
## there it fades and holds its place until the eyes open. Tab in the flesh
## keeps it.
##
## While a song is up the body's bed is lowered by bed_duck_db (the hookup
## sets FDKAudioDirector.bed_gain_db from level()), so the tearing, chewing,
## steps and the creak keep their margin over bed + song (tools/measure_beds.py
## --flesh-music).
##
## Only reads main's state; never changes progression. Music bus.

const DATA := "res://audio/flesh_music.json"
const BUS := &"Music"
const SILENT_DB := -80.0
## Places of fp_music that hold this music (Esc, key settings).
const HOLD_PLACES := ["pause", "keybind"]

var hookup: Node
var main: Node
var _data := {}
var _shells: Array = []

## The song now playing ("" = none), its own clock (s since its start), and
## how loud it is (0..1 before its gain).
var song := ""
var _shell := -1
var _pos := 0.0
var _level := 0.0
var _player: AudioStreamPlayer
## The old song while a crossfade runs.
var _old: AudioStreamPlayer
var _old_level := 0.0
var _old_gain := 0.0
## "play", "ending" (fading over its last bars), "switch" (waiting for the
## phrase mark), "rest", "off" (not in the flesh).
var phase := "off"
var _rest_left := 0.0
## The shell the rest belongs to: a rest ends early only when it changes.
var _rest_shell := -1
var _target_shell := -1
## Why the music is quiet now (tests and logs read it).
var reason := "off"
## Fade time of the song a rest cut short (a rest container), 0 at a song's end.
var _end_fade_extra := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if hookup == null:
		hookup = get_parent()
	if main == null and hookup != null:
		main = hookup.get("main")
	data()

## audio/flesh_music.json (tests read it too).
func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(DATA):
		var d = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if d is Dictionary:
			_data = d
			_shells = d.get("shells", [])
	return _data

func _num(key: String, fallback: float) -> float:
	return float(data().get(key, fallback))

## The song for a shell index.
func song_for_shell(s: int) -> String:
	data()
	if _shells.is_empty():
		return ""
	return String(_shells[clampi(s, 0, _shells.size() - 1)].get("song", ""))

## 0..1, how far the song is up now (the bed duck and the tine follow it).
func level() -> float:
	return maxf(_level, _old_level)

func _in_room() -> bool:
	return hookup != null and hookup.has_method("_player_in_room") and bool(hookup.call("_player_in_room"))

func _open(node_name: String) -> bool:
	var n = main.get(node_name)
	return n != null and n.has_method("is_open") and bool(n.is_open())

## Where the player is for the music: "flesh", "rest" (a rest container),
## "hold" (Esc or key settings over the flesh), "off" (room, ending, title).
func where() -> String:
	if main == null:
		return "off"
	var ending = main.get("ending")
	if ending != null and bool(ending.get("active")):
		return "off"
	if _open("title_screen"):
		return "off"
	if _in_room():
		return "off"
	if _open("pause_menu") or _open("keybind_menu"):
		return "hold"
	var player = main.get("player")
	var rests = main.get("rest_points")
	if player is Node3D and rests is Array and FPWorldFeatures.in_container((player as Node3D).global_position, rests):
		return "rest"
	return "flesh"

## The shell the player stands in (main.shell_at).
func shell_now() -> int:
	var player = main.get("player") if main != null else null
	if player is Node3D and main.has_method("shell_at"):
		return clampi(int(main.shell_at((player as Node3D).global_position)), 0, maxi(_shells.size() - 1, 0))
	return 0

func _process(delta: float) -> void:
	step(delta)

## Per-frame update (tests call it directly).
func step(delta: float) -> void:
	data()
	var w := where()
	match w:
		"off":
			if phase != "off":
				_stop_all(_num("leave_fade", 2.0))
			phase = "off"
			reason = "off"
		"hold":
			reason = "hold"
		"rest":
			if phase == "play" or phase == "ending" or phase == "switch":
				_begin_rest(_num("end_fade", 8.0) * 0.5)
			elif phase == "rest":
				_rest_left -= delta
			reason = "rest"
		"flesh":
			_flesh(delta)
	_fade(delta, w)

func _flesh(delta: float) -> void:
	var s := shell_now()
	match phase:
		"off":
			_start(s)
		"rest":
			reason = "rest"
			_rest_left -= delta
			if s != _rest_shell or _rest_left <= 0.0:
				_start(s)
		"play", "switch":
			reason = "play"
			if s != _shell:
				phase = "switch"
				_target_shell = s
			else:
				phase = "play"
			var loop_s := _loop_seconds(_shell)
			var end_at := loop_s - _num("end_fade", 8.0)
			var mark := _next_mark(_shell, _pos)
			var was := _pos
			_pos += delta
			if phase == "switch" and was < mark and _pos >= mark:
				_crossfade(_target_shell)
			elif phase == "play" and _pos >= end_at:
				phase = "ending"
		"ending":
			reason = "play"
			_pos += delta
			if s != _shell:
				# crossing a membrane while it winds down: the new shell at once
				_crossfade(s)
			elif _pos >= _loop_seconds(_shell):
				_begin_rest(0.0)

## The next phrase mark of the shell's song at or after t (loop end last).
func _next_mark(s: int, t: float) -> float:
	var marks: Array = _shells[s].get("phrases", []) if s >= 0 and s < _shells.size() else []
	for m in marks:
		if float(m) > t:
			return float(m)
	return _loop_seconds(s)

func _loop_seconds(s: int) -> float:
	if s < 0 or s >= _shells.size():
		return 100.0
	return float(_shells[s].get("loop_seconds", 100.0))

func _gain(s: int) -> float:
	return float(_shells[s].get("gain_db", 0.0)) if s >= 0 and s < _shells.size() else 0.0

func _start(s: int) -> void:
	var id := song_for_shell(s)
	if id == "":
		return
	if _player != null:
		_player.stop()
		_player.queue_free()
	_player = _make(id)
	song = id
	_shell = s
	_pos = 0.0
	_level = 0.0
	phase = "play"
	reason = "play"

## The old song fades over the crossfade; the new one starts from its top.
func _crossfade(s: int) -> void:
	_drop_old()
	if _player != null:
		_old = _player
		_old_level = _level
		_old_gain = _gain(_shell)
		_player = null
	_start(s)

func _begin_rest(fade_more: float) -> void:
	phase = "rest"
	reason = "rest"
	_rest_shell = shell_now()
	_rest_left = _num("rest_seconds", 75.0)
	if _player != null:
		_drop_old()
		_old = _player
		_old_level = _level
		_old_gain = _gain(_shell)
		_player = null
	_level = 0.0
	song = ""
	_end_fade_extra = fade_more

func _stop_all(_fade_s: float) -> void:
	if _player != null:
		_drop_old()
		_old = _player
		_old_level = _level
		_old_gain = _gain(_shell)
		_player = null
	_level = 0.0
	song = ""
	_shell = -1
	_end_fade_extra = 0.0

func _drop_old() -> void:
	if _old != null:
		_old.stop()
		_old.queue_free()
	_old = null
	_old_level = 0.0

func _make(id: String) -> AudioStreamPlayer:
	var director = hookup.get("director") if hookup != null else null
	var bank = director.get("bank") if director != null else null
	var p := AudioStreamPlayer.new()
	p.name = "FleshMusic_" + id
	p.bus = BUS
	p.volume_db = SILENT_DB
	if bank != null and bank.has(id):
		p.stream = bank.stream(id, 0)
	add_child(p)
	if p.stream != null:
		p.play()
	return p

func _fade(delta: float, w: String) -> void:
	# the new song
	if _player != null:
		var want := 1.0
		var rate := 1.0 / maxf(_num("fade_in", 3.0), 0.01)
		if w == "hold":
			want = 0.0
			rate = 1.0 / maxf(_num("pause_fade", 2.5), 0.01)
		elif phase == "ending":
			# down over the last bars, silent at the loop's end
			var left := _loop_seconds(_shell) - _pos
			want = clampf(left / maxf(_num("end_fade", 8.0), 0.01), 0.0, 1.0)
			rate = 1.0e6
			want = minf(want, _level)
		_level = move_toward(_level, want, rate * delta)
		_player.stream_paused = w == "hold" and _level <= 0.0001
		_player.volume_db = SILENT_DB if _level <= 0.0001 else maxf(linear_to_db(_level) + _gain(_shell), SILENT_DB)
	# the one fading out
	if _old != null:
		var out_s := _num("crossfade", 3.0)
		if phase == "rest":
			out_s = maxf(_end_fade_extra, 0.5)
		elif phase == "off":
			out_s = _num("leave_fade", 2.0)
		_old_level = move_toward(_old_level, 0.0, delta / maxf(out_s, 0.01))
		_old.volume_db = SILENT_DB if _old_level <= 0.0001 else maxf(linear_to_db(_old_level) + _old_gain, SILENT_DB)
		if _old_level <= 0.0:
			_drop_old()

## The song players that are audible now (tests read it).
func audible() -> Array[String]:
	var out: Array[String] = []
	for p in [_player, _old]:
		if p != null and p.playing and not p.stream_paused and p.volume_db > SILENT_DB + 1.0:
			out.append(String(p.name).trim_prefix("FleshMusic_"))
	return out

## The player of the current song (tests read it), or null.
func current_player() -> AudioStreamPlayer:
	return _player
