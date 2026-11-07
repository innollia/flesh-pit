extends Node

## Background music (tools/build_music.py), one loop per place where the
## player stays. Out in the flesh nothing here plays: the flesh has its own
## songs, one per shell (audio/fp_flesh_music.gd, user 2026-11-07), and the
## ending song's faint melody is the hookup's song_melody layer. The ending has
## its own hum (song layers).
##
##   title     start screen (and its settings)          mus_title
##   keybind   key settings stage (from title or Esc)   mus_keybind
##   pause     Esc, eyes shut (and its settings)        mus_pause_alt or mus_pause
##   vent      in the restroom with the vent open       mus_vent
##   mirror    Tab's forearm screen, in the room        mus_mirror
##   room      the restroom and the bowl, once the      mus_room_* stems
##             eyes have adjusted (03 4: the glare)
##
## Esc: the song is chosen by where the eyes shut. In the room, the felt piano
## (a quiet room, the size of the room); in the flesh, the strings with no
## attack (a refuge from the noise). Never random, and held until Esc closes.
##
## The room is one piece of music, not one track per screen (user 2026-11-07:
## the music turning into another because you knelt at the bowl was wrong).
## Eight stems of the same key, tempo and length play in one synchronized
## stream on one player and only their levels move, slowly; the bowl is no
## place of its own and nothing is ever swapped. Which stems are up follows
## the game, by the situations in audio/room_music.json, read the way the
## being's lines read vent_rules.json: what the last trip did, how long you
## have stayed, the stomach, a death, a tumor, a big settlement. Where you look
## is not a fact here and never moves anything. The room's bed (hum, exhaust
## fan, pipe water) goes on under it as it was.
##
## Tab out in the flesh stays silent (08 3: nothing there). Not places: sitting
## on the toilet (still the room), the settings page (it keeps the music of the
## screen it was opened from, and its 배경음 slider has to be judged against
## that), the codex (no screen: crayon drawings on the room's wall).
##
## Only reads main's state and listens to its signals; never changes
## progression. Lives under the audio hookup and keeps running while the tree
## is paused (title, Esc). Every player is on the Music bus, so the "배경음"
## slider sets it.

const TRACKS := {
	"title": "mus_title", "keybind": "mus_keybind", "pause": "mus_pause",
	"vent": "mus_vent", "mirror": "mus_mirror",
}
## Esc with the eyes shut in the room (TRACKS.pause is the flesh's).
const PAUSE_IN_ROOM := "mus_pause_alt"
## The one player the room's stems share, under this id everywhere a track has one.
const ROOM := "mus_room"
const ROOM_DATA := "res://audio/room_music.json"
const BUS := &"Music"
## Seconds in the room, eyes adjusted and the opening over, before the
## restroom's music starts; it then comes in slowly under the room's hum.
const ROOM_SETTLE := 6.0
const FADE_IN := {"room": 8.0, "vent": 2.0, "mirror": 1.5}
## Crossfade between two places with music.
const FADE := 2.5
## Out in the flesh (stepping out the door, eyes opening there after Esc):
## the music is gone within this long.
const FADE_OUT_FLESH := 0.8
## A silent track's player is stopped and freed after this long.
const RELEASE := 4.0
const SILENT_DB := -80.0

var hookup: Node
var main: Node
## The place whose music is wanted now ("" = none).
var place: String = ""
var _players := {}
var _level := {}
var _silent := {}
var _room_t := 0.0
## The Esc song, chosen when the eyes shut and kept until they open.
var _pause_id := ""
## audio/room_music.json.
var _data := {}
## The stems in stream order, their levels now (0..1), the stream they are in.
var _stems: Array[String] = []
var _stem_level := {}
var _stream: AudioStreamSynchronized
## What the game has said, for the situations (room_music.json 사실).
var _out := false
var _cells_at_door := 0
var _tumors_at_door := 0
var _dug := 0
var _tumors := 0
var _away_t := 0.0
var _deepest := 0
var _stay_t := 0.0
var _died := false
var _flush_teeth := 0
var _flush_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if hookup == null:
		hookup = get_parent()
	if main == null and hookup != null:
		main = hookup.get("main")
	if main != null and main.has_signal("died"):
		main.connect("died", _on_died)
	if main != null and main.has_signal("flushed"):
		main.connect("flushed", _on_flushed)

func _on_died(_cause: String) -> void:
	_died = true

func _on_flushed(teeth: int, _hairs: int) -> void:
	_flush_teeth = teeth
	_flush_t = 0.0

func _open(node_name: String) -> bool:
	var n = main.get(node_name)
	return n != null and n.has_method("is_open") and bool(n.is_open())

func _in_room() -> bool:
	return hookup != null and hookup.has_method("_player_in_room") and bool(hookup.call("_player_in_room"))

## Where the music should be now. delta advances the room's settle clock.
func want_place(delta: float = 0.0) -> String:
	if main == null:
		return ""
	if not _open("pause_menu") and not _open("keybind_menu"):
		_pause_id = ""
	var ending = main.get("ending")
	if ending != null and bool(ending.get("active")):
		_room_t = 0.0
		return ""
	if _open("keybind_menu"):
		return "keybind"
	if _open("title_screen"):
		return "title"
	if _open("pause_menu"):
		if _pause_id == "":
			_pause_id = PAUSE_IN_ROOM if _in_room() else String(TRACKS["pause"])
		return "pause"
	if not _in_room():
		_room_t = 0.0
		return ""
	# the bowl is the room: the screens with music of their own stop short of it
	if not (main.has_method("is_settling") and bool(main.is_settling())):
		if _open("mirror"):
			return "mirror"
		var vent = main.get("vent")
		if vent != null and bool(vent.get("is_open")):
			return "vent"
	var opening: bool = main.has_method("is_opening") and bool(main.is_opening())
	var glare = main.get("glare_controller")
	var dazzled: bool = glare != null and glare.has_method("get_flash") and float(glare.get_flash()) > 0.05
	var lids = main.get("wake_lids")
	var waking: bool = lids != null and bool(lids.playing())
	if opening or dazzled or waking:
		_room_t = 0.0
	elif not get_tree().paused:
		_room_t += delta
	return "room" if _room_t >= ROOM_SETTLE else ""

func _process(delta: float) -> void:
	step(delta)

## Per-frame update (tests call it directly).
func step(delta: float) -> void:
	_watch(delta)
	place = want_place(delta)
	var track := _track(place)
	if track != "":
		_ensure(track)
	var flesh := place == "" and not _in_room()
	_step_stems(delta)
	for id in _players.keys():
		var want := 1.0 if track == id else 0.0
		var cur: float = _level[id]
		var rate: float
		if want > cur:
			rate = 1.0 / float(FADE_IN.get(place, FADE))
		else:
			rate = 1.0 / (FADE_OUT_FLESH if flesh else FADE)
		cur = move_toward(cur, want, rate * delta)
		_level[id] = cur
		var p: AudioStreamPlayer = _players[id]
		p.volume_db = SILENT_DB if cur <= 0.0001 else maxf(linear_to_db(cur), SILENT_DB)
		if cur <= 0.0 and want <= 0.0:
			_silent[id] = float(_silent.get(id, 0.0)) + delta
			# the room's music keeps its place under a screen in the room
			var held: bool = id == ROOM and ["pause", "vent", "mirror"].has(place) and _in_room()
			if _silent[id] >= RELEASE and not held:
				_release(id)
		else:
			_silent.erase(id)

func _track(where: String) -> String:
	match where:
		"":
			return ""
		"room":
			return ROOM
		"pause":
			return _pause_id
	return String(TRACKS[where])

func _ensure(id: String) -> void:
	if _players.has(id):
		return
	var director = hookup.get("director") if hookup != null else null
	var bank = director.get("bank") if director != null else null
	if bank == null or (id != ROOM and not bank.has(id)):
		return
	var stream: AudioStream = _room_stream(bank) if id == ROOM else bank.stream(id, 0)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.name = "Music_" + id
	p.bus = BUS
	p.stream = stream
	p.volume_db = SILENT_DB
	add_child(p)
	p.play()
	_players[id] = p
	_level[id] = 0.0

func _release(id: String) -> void:
	var p: AudioStreamPlayer = _players[id]
	p.stop()
	p.queue_free()
	_players.erase(id)
	_level.erase(id)
	_silent.erase(id)
	if id == ROOM:
		_stream = null
		_stem_level.clear()

## --- the room's stems ---

## room_music.json (tests read it too).
func room_data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(ROOM_DATA):
		var d = JSON.parse_string(FileAccess.get_file_as_string(ROOM_DATA))
		if d is Dictionary:
			_data = d
	return _data

## All stems in one stream: they cannot slide against each other, and only
## their levels are ever touched. Nil when a stem is missing.
func _room_stream(bank) -> AudioStream:
	var layers: Dictionary = room_data().get("층", {})
	_stems.clear()
	var stream := AudioStreamSynchronized.new()
	stream.stream_count = layers.size()
	var at := 0
	for stem in layers.keys():
		var id := String(layers[stem]["곡"])
		if not bank.has(id):
			return null
		stream.set_sync_stream(at, bank.stream(id, 0))
		stream.set_sync_stream_volume(at, SILENT_DB)
		_stems.append(String(stem))
		at += 1
	_stream = stream
	_stem_level.clear()
	return stream

## Keeps what the game has said since the door: the counters are main's and
## only read here. The title starts the story over (Continue reloads it all).
func _watch(delta: float) -> void:
	if main == null:
		return
	if _open("title_screen"):
		_out = false
		_dug = 0
		_tumors = 0
		_deepest = 0
		_away_t = 0.0
		_stay_t = 0.0
		_died = false
		_flush_teeth = 0
		return
	var cells := int(main.get("excavated_cells"))
	var prog = main.get("progression")
	var eaten: int = int(prog.get("tumors_eaten")) if prog != null else 0
	if _in_room():
		_out = false
	else:
		if not _out:
			_out = true
			_cells_at_door = cells
			_tumors_at_door = eaten
			_deepest = 0
			_away_t = 0.0
			_stay_t = 0.0
			_died = false
			_flush_teeth = 0
		_dug = maxi(0, cells - _cells_at_door)
		_tumors = maxi(0, eaten - _tumors_at_door)
		if not get_tree().paused:
			_away_t += delta
		var body = main.get("player")
		if body != null and main.has_method("shell_at"):
			_deepest = maxi(_deepest, int(main.shell_at((body as Node3D).global_position)))
	if _in_room() and not get_tree().paused:
		_stay_t += delta
		_flush_t += delta

## The facts the situations read (room_music.json 사실).
func facts() -> Dictionary:
	var stomach = main.get("stomach") if main != null else null
	return {
		"이번_굴착": _dug, "이번_시간": _away_t, "이번_깊이": _deepest, "이번_종양": _tumors,
		"방_체류": _stay_t,
		"위장": float(stomach.fill_ratio()) if stomach != null else 0.0,
		"죽고_돌아옴": 1 if _died else 0,
		"변기앞": 1 if main != null and main.has_method("is_settling") and bool(main.is_settling()) else 0,
		"정산_이빨": _flush_teeth, "정산_경과": _flush_t,
	}

static func _holds(condition: Dictionary, now: Dictionary) -> bool:
	for key in condition.keys():
		var value := float(now.get(key, 0.0))
		var rule: Dictionary = condition[key]
		if rule.has("이상") and value < float(rule["이상"]):
			return false
		if rule.has("이하") and value > float(rule["이하"]):
			return false
	return true

## The ids of the situations that hold now.
func active_situations() -> Array:
	var now := facts()
	var out: Array = []
	for sit in room_data().get("상황", []):
		if _holds(sit.get("조건", {}), now):
			out.append(String(sit["id"]))
	return out

## stem -> the level the situations want, the loudest of those that hold.
func room_targets() -> Dictionary:
	var now := facts()
	var out := {}
	for stem in room_data().get("층", {}).keys():
		out[String(stem)] = 0.0
	for sit in room_data().get("상황", []):
		if not _holds(sit.get("조건", {}), now):
			continue
		var layers: Dictionary = sit.get("층", {})
		for stem in layers.keys():
			out[stem] = maxf(float(out.get(stem, 0.0)), float(layers[stem]))
	return out

## stem -> its level now (empty when the room's player is not running).
func room_levels() -> Dictionary:
	return _stem_level.duplicate()

## Stems drift to where the situations want them. While the whole room is
## silent they just stand there, so the first note you hear is already right.
func _step_stems(delta: float) -> void:
	if _stream == null:
		return
	var times: Dictionary = room_data().get("시간", {})
	var up := 1.0 / float(times.get("층_오름_초", 8.0))
	var down := 1.0 / float(times.get("층_내림_초", 12.0))
	var targets := room_targets()
	var snap := float(_level.get(ROOM, 0.0)) <= 0.0
	for at in range(_stems.size()):
		var stem := _stems[at]
		var want := float(targets.get(stem, 0.0))
		var cur := float(_stem_level.get(stem, want))
		cur = want if snap else move_toward(cur, want, (up if want > cur else down) * delta)
		_stem_level[stem] = cur
		_stream.set_sync_stream_volume(at, SILENT_DB if cur <= 0.0001 else maxf(linear_to_db(cur), SILENT_DB))

## 0..1 level of a track (tests), -1 when it has no player.
func level(id: String) -> float:
	return float(_level.get(id, -1.0))

## The track ids that are audible now (level above zero).
func audible() -> Array[String]:
	var out: Array[String] = []
	for id in _level.keys():
		if float(_level[id]) > 0.0 and (_players[id] as AudioStreamPlayer).playing:
			out.append(String(id))
	return out

func player(id: String) -> AudioStreamPlayer:
	return _players.get(id)
