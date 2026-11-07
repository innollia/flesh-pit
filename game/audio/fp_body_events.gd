extends Node

## The flesh moving on its own: one-shot takes at long uneven gaps over the
## bed that plays, so the place lives without a cycle the ear can learn (owner,
## listening 2026-11-07: "different white noises"). The same way as the water in
## the restroom's pipes (audio/fp_pipe_water.gd), one voice at a time, on the
## Music bus with the beds, its level following the bed's own layer.
##
## The hookup calls step() each frame; this node reads the terrain and changes
## nothing, and its numbers are its own. Which takes play where comes from the
## manifest's "bed_events" (tools/build_biome_beds.py). A take the manifest calls
## spatial comes from a real wall near the player, found by walking out through
## the terrain's density; with no wall in reach it plays without a place.

const MANIFEST := "res://audio/manifest.json"
const INAUDIBLE_DB := -60.0
## Directions tried for a wall, and how far out along each (metres).
const SPOT_TRIES := 4
const SPOT_NEAR := 2.0
const SPOT_FAR := 9.0
const SPOT_STEP := 1.0
const SOLID := 0.5
## Attenuation of a take from the wall: full level up to here, then falling, so
## the near walls are a little louder and none is a jump.
const UNIT_SIZE := 7.0
const MAX_DISTANCE := 30.0
const PITCH := Vector2(0.95, 1.05)

var director: FDKAudioDirector
var terrain: Node
var listener: Node3D
var rng := RandomNumberGenerator.new()
## Every take so far, in order (tests read it).
var played: Array[String] = []
## terrain.density_at calls so far: the whole cost of placing takes.
var density_reads := 0
var last_spot: Variant = null

var _table: Dictionary = {}
var _bed := ""
var _wait := 0.0
var _left := 0.0
var _layer := ""
var _trim := 0.0
var _voice: Node

func _init() -> void:
	rng.randomize()

func _ready() -> void:
	load_table(FileAccess.get_file_as_string(MANIFEST))

func load_table(json_text: String) -> void:
	var data = JSON.parse_string(json_text)
	_table = data.get("bed_events", {}) if data is Dictionary else {}

func bed_table() -> Dictionary:
	return _table

## bed: the bed that plays now (director.current_bed).
func step(delta: float, bed: String) -> void:
	var has_events := _table.has(bed)
	if bed != _bed:
		_bed = bed
		# a new place speaks up soon after the player walks in
		if has_events:
			var first: Array = _table[bed]["first_gap"]
			_wait = rng.randf_range(float(first[0]), float(first[1]))
	if _voice != null:
		_left -= delta
		var db := director.bed_layer_db(_layer) + director.bed_gain_db if director != null else FDKAudioDirector.SILENT_DB
		_voice.set("volume_db", db + _trim)
		if _left <= 0.0 or db <= INAUDIBLE_DB:
			_stop_voice()
		return
	if not has_events:
		return
	_wait -= delta
	if _wait <= 0.0:
		var gap: Array = _table[bed]["gap"]
		_wait = rng.randf_range(float(gap[0]), float(gap[1]))
		_play_next(bed)

## Any take of the bed but the last one.
func _play_next(bed: String) -> void:
	var last: String = played.back() if not played.is_empty() else ""
	var from: Array = (_table[bed]["takes"] as Array).filter(func(t): return String(t["id"]) != last)
	if from.is_empty():
		from = _table[bed]["takes"]
	var take: Dictionary = from[rng.randi_range(0, from.size() - 1)]
	var range_db: Array = take["db"]
	play_take(String(take["id"]), bed, rng.randf_range(float(range_db[0]), float(range_db[1])))

## The first bed layer is the place's own (the second is the heart).
func _layer_of(bed: String) -> String:
	var layers: Array = director.bank.beds.get(bed, [])
	return String(layers[0]) if not layers.is_empty() else ""

func play_take(id: String, bed: String, trim_db: float = 0.0) -> void:
	if director == null or director.bank == null:
		return
	var stream := director.bank.pick(id)
	if stream == null:
		return
	_stop_voice()
	played.append(id)
	_layer = _layer_of(bed)
	_trim = trim_db
	var pitch := rng.randf_range(PITCH.x, PITCH.y)
	var at: Variant = wall_spot() if director.bank.is_spatial(id) else null
	last_spot = at
	var p: Node
	if at is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = UNIT_SIZE
		p3.max_distance = MAX_DISTANCE
		p = p3
	else:
		p = AudioStreamPlayer.new()
	# "Bed_" sends it to the Music bus with its bed (FPSettings.route_player)
	p.name = "Bed_body_event"
	p.set("stream", stream)
	p.set("bus", director.bus)
	p.set("pitch_scale", pitch)
	p.set("volume_db", director.bed_layer_db(_layer) + director.bed_gain_db + _trim)
	add_child(p)
	if at is Vector3:
		(p as Node3D).global_position = at
	p.call("play")
	_voice = p
	_left = stream.get_length() / pitch

## A solid spot in the flesh around the listener, or null. Bounded: at most
## SPOT_TRIES * 8 density reads, once per take.
func wall_spot() -> Variant:
	if terrain == null or listener == null or not listener.is_inside_tree() or not terrain.has_method("density_at"):
		return null
	var from := listener.global_position
	for i in range(SPOT_TRIES):
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 0.6), rng.randf_range(-1.0, 1.0)).normalized()
		var d := SPOT_NEAR
		while d <= SPOT_FAR:
			var at := from + dir * d
			density_reads += 1
			if float(terrain.call("density_at", at)) > SOLID:
				return at
			d += SPOT_STEP
	return null

func _stop_voice() -> void:
	if _voice != null:
		_voice.call("stop")
		# the name is how a new take finds the Music bus; free it now
		remove_child(_voice)
		_voice.queue_free()
	_voice = null
	_left = 0.0

func seconds_to_next() -> float:
	return _left + _wait

func seconds_left() -> float:
	return _left

## The take under way, or null.
func voice() -> Node:
	return _voice
