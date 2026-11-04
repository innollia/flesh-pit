extends Node

## Water in the restroom's pipes: one-shot takes at long random gaps, only
## while the restroom bed is the bed that plays, so it is never a cycle the
## ear can learn (owner, listening 2026-11-04). The hookup calls step() each
## frame; this node reads no game state and changes none. A take under way
## follows the bed's fade when the player leaves and stops once it is gone.
## Takes come from tools/build_restroom_amb.py. Gaps are silence: they run
## from the end of one take to the start of the next.

const TAKES := ["pipe_trickle", "pipe_run", "pipe_glug", "pipe_tick"]
## Seconds from entering the room to the first take.
const FIRST_GAP := Vector2(25.0, 70.0)
const GAP := Vector2(45.0, 150.0)
const PITCH := Vector2(0.96, 1.04)
## The layer whose level the water follows.
const BED_LAYER := "amb_restroom"
const INAUDIBLE_DB := -60.0

var director: FDKAudioDirector
## Its own numbers; the game's random stream is never touched.
var rng := RandomNumberGenerator.new()
## Every take so far, in order (tests read it).
var played: Array[String] = []

var _armed := false
var _wait := 0.0
var _left := 0.0
var _voice: AudioStreamPlayer

func _init() -> void:
	rng.randomize()

## in_room: the restroom bed is the one playing now.
func step(delta: float, in_room: bool) -> void:
	if in_room and not _armed:
		_armed = true
		_wait = rng.randf_range(FIRST_GAP.x, FIRST_GAP.y)
	elif not in_room:
		_armed = false
	var bed_db := director.bed_layer_db(BED_LAYER) if director != null else FDKAudioDirector.SILENT_DB
	if _voice != null:
		_left -= delta
		_voice.volume_db = bed_db
		if _left <= 0.0 or (not in_room and bed_db <= INAUDIBLE_DB):
			_stop_voice()
		return
	if not _armed:
		return
	_wait -= delta
	if _wait <= 0.0:
		_wait = rng.randf_range(GAP.x, GAP.y)
		play_take(_next_take())

## Any take but the last one.
func _next_take() -> String:
	var last: String = played.back() if not played.is_empty() else ""
	var from: Array = TAKES.filter(func(id): return id != last)
	return String(from[rng.randi_range(0, from.size() - 1)])

func play_take(id: String) -> void:
	if director == null or director.bank == null:
		return
	var stream := director.bank.pick(id)
	if stream == null:
		return
	_stop_voice()
	played.append(id)
	var p := AudioStreamPlayer.new()
	# "Bed_" sends it to the Music bus with its bed (FPSettings.route_player)
	p.name = "Bed_pipe_water"
	p.stream = stream
	p.bus = director.bus
	p.pitch_scale = rng.randf_range(PITCH.x, PITCH.y)
	p.volume_db = director.bed_layer_db(BED_LAYER)
	add_child(p)
	p.play()
	_voice = p
	_left = stream.get_length() / p.pitch_scale

func _stop_voice() -> void:
	if _voice != null:
		_voice.stop()
		_voice.queue_free()
	_voice = null
	_left = 0.0

func is_armed() -> bool:
	return _armed

func seconds_to_next() -> float:
	return _left + _wait

## Left of the take under way (0 when none plays).
func seconds_left() -> float:
	return _left

## The take under way, or null.
func voice() -> AudioStreamPlayer:
	return _voice
