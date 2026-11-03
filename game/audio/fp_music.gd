extends Node

## Background music (tools/build_music.py), one loop per place where the
## player stays and the spec allows music. docs/spec/08-presentation.md 3:
## while digging there is no music, only the low drone (the ending song's
## faint melody is the hookup's song_melody layer, not this), so out in the
## flesh nothing here plays. The ending has its own hum (song layers).
##
##   title     start screen (and its settings)          mus_title
##   keybind   key settings stage (from title or Esc)   mus_keybind
##   pause     Esc, eyes shut (and its settings)        mus_pause
##   vent      in the restroom with the vent open       mus_vent
##   restroom  in the restroom once the eyes have       mus_restroom
##             adjusted (03 4: the glare on return)
##
## Only reads main's state; never changes progression. Lives under the
## audio hookup and keeps running while the tree is paused (title, Esc).
## Every player is on the Music bus, so the "배경음" slider sets it.

const TRACKS := {
	"title": "mus_title", "keybind": "mus_keybind", "pause": "mus_pause",
	"vent": "mus_vent", "restroom": "mus_restroom",
}
const BUS := &"Music"
## Seconds in the room, eyes adjusted and the opening over, before the
## restroom's music starts; it then comes in slowly under the room's hum.
const ROOM_SETTLE := 6.0
const FADE_IN := {"restroom": 8.0, "vent": 2.0}
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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if hookup == null:
		hookup = get_parent()
	if main == null and hookup != null:
		main = hookup.get("main")

func _open(node_name: String) -> bool:
	var n = main.get(node_name)
	return n != null and n.has_method("is_open") and bool(n.is_open())

func _in_room() -> bool:
	return hookup != null and hookup.has_method("_player_in_room") and bool(hookup.call("_player_in_room"))

## Where the music should be now. delta advances the room's settle clock.
func want_place(delta: float = 0.0) -> String:
	if main == null:
		return ""
	var ending = main.get("ending")
	if ending != null and bool(ending.get("active")):
		_room_t = 0.0
		return ""
	if _open("keybind_menu"):
		return "keybind"
	if _open("title_screen"):
		return "title"
	if _open("pause_menu"):
		return "pause"
	if not _in_room():
		_room_t = 0.0
		return ""
	var vent = main.get("vent")
	if vent != null and bool(vent.get("is_open")):
		return "vent"
	var opening: bool = main.has_method("is_opening") and bool(main.is_opening())
	var glare = main.get("glare_controller")
	var dazzled: bool = glare != null and glare.has_method("get_flash") and float(glare.get_flash()) > 0.05
	if opening or dazzled:
		_room_t = 0.0
	elif not get_tree().paused:
		_room_t += delta
	return "restroom" if _room_t >= ROOM_SETTLE else ""

func _process(delta: float) -> void:
	step(delta)

## Per-frame update (tests call it directly).
func step(delta: float) -> void:
	place = want_place(delta)
	if place != "":
		_ensure(TRACKS[place])
	var flesh := place == "" and not _in_room()
	for id in _players.keys():
		var want := 1.0 if place != "" and TRACKS[place] == id else 0.0
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
			if _silent[id] >= RELEASE:
				_release(id)
		else:
			_silent.erase(id)

func _ensure(id: String) -> void:
	if _players.has(id):
		return
	var director = hookup.get("director") if hookup != null else null
	var bank = director.get("bank") if director != null else null
	if bank == null or not bank.has(id):
		return
	var p := AudioStreamPlayer.new()
	p.name = "Music_" + id
	p.bus = BUS
	p.stream = bank.stream(id, 0)
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
