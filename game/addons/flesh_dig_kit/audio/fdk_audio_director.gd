class_name FDKAudioDirector
extends Node

## Plays the kit's sounds by SUBSCRIBING to kit signals; it never drives game
## logic. Wire it with connect_chewer / connect_stomach / connect_player and
## call set_bed / set_surface / set_mutation_stage / set_shell from the game.
##
## - Every one-shot goes through FDKSoundBank.pick (no variation twice in a row).
## - Beds are sets of loop layers (manifest "beds"). All layers keep playing;
##   a bed change only crossfades their volumes, so the loops never restart.
## - The chew loop plays while chewing. Its speed follows the stomach: at
##   chew_time_multiplier() m it plays at pitch 1/m (clamped), so overfilled
##   chewing is slower and heavier, and a strain layer fades in with overfill.
## - Footsteps are detected from FDKFirstPersonController.footstep_bob troughs.
##
## Sound ids used (all optional; a missing id is silently skipped):
##   tear_flesh tear_nerve tear_fat tear_membrane tear_muscle tear_cartilage
##   tear_cloth tear_hair pull_stretch swallow stomach_gurgle
##   nerve_twitch vomit_toilet vomit_floor step_<surface>_s<1..3>
##   chew_loop_a chew_loop_b chew_strain regen_creak depth_marker
##   shell_transition canary_chirp canary_warn canary_wrong

const SILENT_DB := -80.0
## Tear sound per tissue id (FDKTissueRules). A tissue without an entry, or
## whose id the manifest lacks, tears as plain flesh.
const TISSUE_TEAR := {0: "tear_flesh", 1: "tear_nerve", 2: "tear_fat", 3: "tear_membrane",
	4: "tear_muscle", 6: "tear_cartilage", 7: "tear_cloth", 8: "tear_hair"}
const NERVE_TISSUE := 1

@export var manifest_path: String = ""
@export var bus: StringName = &"Master"
## Lowest chew-loop pitch when badly overfilled (1 = normal speed).
@export var chew_pitch_min: float = 0.55
## Delay between a tear and its swallow.
@export var swallow_delay: float = 0.3
## Seconds between regen creaks while life_enabled and nothing is close to
## closing (life_urgency 0).
@export var life_interval: Vector2 = Vector2(5.0, 12.0)
## The same gap when the regrowing spot is about to close (life_urgency 1).
@export var life_interval_urgent: Vector2 = Vector2(1.5, 3.0)
## Regen creaks sound only while this is on. The consumer sets it from where
## the listener is (in the flesh, whatever bed plays there).
@export var life_enabled: bool = false
## Beds the shell picks between (set_shell / body_bed_for_shell).
@export var body_beds: PackedStringArray = PackedStringArray(["body_a", "body_b"])
## A footstep sounds only when the listener really moved this far (m, level)
## since the bob's last trough: a body wedged in place bobs without walking.
## Without a listener every trough is a step.
@export var step_min_travel: float = 0.12
## The stretch layer (pull_stretch) under one bite: level and pitch at chew
## ratio 0 and 1 (the level follows ratio squared).
@export var pull_db: Vector2 = Vector2(-30.0, -6.0)
@export var pull_pitch: Vector2 = Vector2(0.85, 1.15)
## A tear of a thin, half-regrown cell is this much quieter (dB) and this much
## higher (pitch factor - 1) than a whole cell's; in between follows the units
## the chewer really removed.
@export var thin_tear_db: float = -8.0
@export var thin_tear_pitch: float = 0.08
## Shell index from which the deeper bed is used.
@export var deep_shell: int = 2
## Each footstep's pitch is 1 +- this (0.04 = about two thirds of a semitone).
@export var step_pitch_jitter: float = 0.04
## Each footstep's level is step_gain_db +- this, dB.
@export var step_gain_jitter_db: float = 1.5
## Each tear's pitch is 1 +- this: one handful after another is never the
## same rip.
@export var tear_pitch_jitter: float = 0.03

var bank: FDKSoundBank
var terrain: Node = null
var stomach: FDKStomach = null
var listener: Node3D = null
## Optional: returns a world position where flesh is really regrowing near
## the listener, or null. When set, the life creak plays only from such a
## spot (a creak always means real regrowth); unset keeps the old random bed.
var creak_source: Callable
## 0..1, how close the regrowing spot is to closing (the consumer sets it,
## usually inside creak_source): creaks come more often and louder with it.
var life_urgency: float = 0.0
const LIFE_QUIET_DB := -6.0
var last_creak_db: float = 0.0
var surface: String = "flesh"
var mutation_stage: int = 0
var current_bed: String = ""
var shell: int = -1
var last_played: String = ""
var played_log: Array[String] = []
var steps_played: int = 0
## Footstep level a consumer sets, and the bus of the room the player is in
## (footsteps and tears play there, the mouth's own sounds stay on `bus`);
## room_bus empty plays everything on `bus`.
var step_gain_db: float = 0.0
## How heavy the walker's step is right now, set by a consumer: the pitch
## every footstep is scaled by and the dB added to its level (1.0 and 0.0 =
## the plain step).
var step_pitch_scale: float = 1.0
var step_weight_db: float = 0.0
var room_bus: StringName = &""
var last_step_pitch: float = 1.0
var last_step_db: float = 0.0
var last_tear_pitch: float = 1.0
var last_tear_db: float = 0.0

## Extra gain on every bed layer, dB (0 = as the bed is mixed). A consumer
## lowers the bed with it while its own music plays; bed_layer_db does not
## include it.
var bed_gain_db: float = 0.0:
	set(v):
		if is_equal_approx(v, bed_gain_db):
			return
		bed_gain_db = v
		for layer in _bed_players.keys():
			_apply_bed_volume(layer)
var _bed_players: Dictionary = {}
var _bed_level: Dictionary = {}
var _bed_target: Dictionary = {}
var _bed_silent: Dictionary = {}
var _fade: float = 1.0
var _chew: AudioStreamPlayer
var _strain: AudioStreamPlayer
var _pull: AudioStreamPlayer
var _chewer: FDKChewer = null
var _step_from: Vector3
var _step_from_set: bool = false
var _chewing: bool = false
var _chew_id: String = ""
var _swallow_timer: float = -1.0
var _fill_band: int = 0
var _prev_bob: float = 0.0
var _prev_dy: float = 0.0
var _life_timer: float = 8.0

func _ready() -> void:
	_ensure_core()
	_life_timer = bank.rng.randf_range(life_interval.x, life_interval.y)

func _process(delta: float) -> void:
	advance(delta)

## Creates the bank and the chew players on first use, so the director also
## works before _ready (driven directly from a test or a tool script).
func _ensure_core() -> void:
	if bank == null and manifest_path != "":
		bank = FDKSoundBank.from_file(manifest_path)
	if bank == null:
		bank = FDKSoundBank.new()
	if _chew == null:
		_chew = _make_player()
		_strain = _make_player()

# --- wiring ------------------------------------------------------------------

func connect_chewer(chewer: FDKChewer) -> void:
	_chewer = chewer
	chewer.grab_started.connect(_on_grab_started)
	chewer.chew_progress.connect(_on_chew_progress)
	chewer.cell_torn.connect(_on_chewer_torn)
	chewer.released.connect(_on_released)

func connect_stomach(s: FDKStomach) -> void:
	stomach = s
	s.fill_changed.connect(_on_fill_changed)

func connect_player(controller: Node) -> void:
	if controller.has_signal("footstep_bob"):
		controller.connect("footstep_bob", on_footstep_bob)
	if listener == null and controller is Node3D:
		listener = controller

# --- state from the game -----------------------------------------------------

func set_surface(surface_name: String) -> void:
	surface = surface_name

func set_mutation_stage(stage: int) -> void:
	var s := clampi(stage, 0, 2)
	if s == mutation_stage:
		return
	mutation_stage = s
	if _chewing:
		_start_chew_loop()

## Depth shell the player is in. Crossing deeper plays the depth marker and
## the body-shift sound; the body bed follows (shallow shells vs deep ones).
func set_shell(index: int) -> void:
	if index == shell:
		return
	var deeper := shell >= 0 and index > shell
	shell = index
	if deeper:
		play("depth_marker")
		play("shell_transition")
	if current_bed in body_beds:
		set_bed(body_bed_for_shell(), 3.0)

func body_bed_for_shell() -> String:
	return body_beds[1] if shell >= deep_shell and body_beds.size() > 1 else body_beds[0]

## Crossfade to a bed (manifest "beds" name). fade 0 = instant.
func set_bed(bed_name: String, fade: float = 1.5) -> void:
	_ensure_core()
	current_bed = bed_name
	_fade = maxf(fade, 0.0)
	var wanted: Array = bank.beds.get(bed_name, [])
	# only the wanted bed's layers start; the others keep fading out
	for layer in wanted:
		_ensure_bed_layer(String(layer))
	for layer in _bed_players.keys():
		_bed_target[layer] = 1.0 if wanted.has(layer) else 0.0
		if _fade == 0.0:
			_bed_level[layer] = _bed_target[layer]
			_apply_bed_volume(layer)

func bed_layer_db(layer: String) -> float:
	if not _bed_level.has(layer):
		return SILENT_DB
	return _lin_to_db(float(_bed_level[layer]))

func is_bed_layer_running(layer: String) -> bool:
	return _bed_players.has(layer)

# --- playback ----------------------------------------------------------------

## One-shot. With a world position and a spatial sound it plays in 3D.
func play(id: String, world_pos: Variant = null, volume_db: float = 0.0) -> void:
	_play(id, world_pos, volume_db, 1.0, bus)

## One footstep: the surface/stage id, each step a little off in pitch and
## level (step_pitch_jitter, step_gain_jitter_db) so a walk is not one sample
## fired again and again, at step_gain_db (+ step_weight_db, pitch x
## step_pitch_scale), on room_bus when set.
func play_step() -> void:
	_ensure_core()
	var r := bank.rng
	last_step_pitch = step_pitch_scale * (1.0 + r.randf_range(-step_pitch_jitter, step_pitch_jitter))
	last_step_db = step_gain_db + step_weight_db + r.randf_range(-step_gain_jitter_db, step_gain_jitter_db)
	_play(footstep_id(), null, last_step_db, last_step_pitch, room_bus if room_bus != &"" else bus)

func _play(id: String, world_pos: Variant, volume_db: float, pitch: float, bus_name: StringName) -> void:
	_ensure_core()
	if not bank.has(id):
		return
	# a loop-kind sound fired as an event (the squeeze strain is the chew
	# strain layer) plays once: a looping one-shot never finishes or frees
	var stream := bank.pick_once(id)
	if stream == null:
		return
	last_played = id
	played_log.append(id)
	if played_log.size() > 128:
		played_log.pop_front()
	if not is_inside_tree():
		return
	if world_pos is Vector3 and bank.is_spatial(id):
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.volume_db = volume_db
		p3.pitch_scale = pitch
		p3.bus = bus_name
		p3.unit_size = 3.0
		p3.max_distance = 40.0
		add_child(p3)
		p3.global_position = world_pos
		p3.play()
		p3.finished.connect(p3.queue_free)
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = stream
		p2.volume_db = volume_db
		p2.pitch_scale = pitch
		p2.bus = bus_name
		add_child(p2)
		p2.play()
		p2.finished.connect(p2.queue_free)

func play_vomit(into_toilet: bool) -> void:
	play("vomit_toilet" if into_toilet else "vomit_floor")

## state: "normal", "warn" or "wrong".
func play_canary(state: String, world_pos: Variant = null) -> void:
	var ids := {"normal": "canary_chirp", "warn": "canary_warn", "wrong": "canary_wrong"}
	play(String(ids.get(state, "canary_chirp")), world_pos)

func footstep_id() -> String:
	return "step_%s_s%d" % [surface, mutation_stage + 1]

func chew_pitch_scale() -> float:
	var m := stomach.chew_time_multiplier() if stomach != null else 1.0
	return clampf(1.0 / maxf(m, 0.001), chew_pitch_min, 1.0)

func strain_level() -> float:
	return stomach.overfill_ratio() if stomach != null else 0.0

func is_chew_active() -> bool:
	return _chewing

func chew_loop_id() -> String:
	return _chew_id

func chew_player_pitch() -> float:
	return _chew.pitch_scale if _chew != null else 1.0

## Per-frame update; _process calls it, tests call it directly.
func advance(delta: float) -> void:
	_ensure_core()
	for layer in _bed_players.keys():
		var cur: float = _bed_level[layer]
		var tgt: float = _bed_target[layer]
		if cur != tgt:
			var step := 1.0 if _fade <= 0.0 else delta / _fade
			_bed_level[layer] = move_toward(cur, tgt, step)
			_apply_bed_volume(layer)
		if _bed_level[layer] <= 0.0 and tgt <= 0.0:
			_bed_silent[layer] = float(_bed_silent.get(layer, 0.0)) + delta
			if _bed_silent[layer] >= BED_RELEASE:
				_release_bed_layer(layer)
		else:
			_bed_silent.erase(layer)
	if _swallow_timer >= 0.0:
		_swallow_timer -= delta
		if _swallow_timer < 0.0:
			play("swallow")
	if _chewing:
		_chew.pitch_scale = chew_pitch_scale()
		_strain.volume_db = _lin_to_db(strain_level())
	if life_enabled:
		# a wait drawn while nothing was closing never outlasts the urgent one
		_life_timer = minf(_life_timer, life_gap().y) - delta
		if _life_timer <= 0.0:
			var pos: Variant = null
			if creak_source.is_valid():
				pos = creak_source.call() # may set life_urgency for this spot
				if pos != null:
					last_creak_db = lerpf(LIFE_QUIET_DB, 0.0, clampf(life_urgency, 0.0, 1.0))
					play("regen_creak", pos, last_creak_db)
			else:
				if listener != null and listener.is_inside_tree():
					var dir := Vector3(bank.rng.randf_range(-1, 1), bank.rng.randf_range(-0.5, 0.5), bank.rng.randf_range(-1, 1)).normalized()
					pos = listener.global_position + dir * bank.rng.randf_range(2.5, 6.0)
				last_creak_db = lerpf(LIFE_QUIET_DB, 0.0, clampf(life_urgency, 0.0, 1.0))
				play("regen_creak", pos, last_creak_db)
			var gap := life_gap()
			_life_timer = bank.rng.randf_range(gap.x, gap.y)

## Shortest and longest wait before the next regen creak at this life_urgency.
func life_gap() -> Vector2:
	return life_interval.lerp(life_interval_urgent, clampf(life_urgency, 0.0, 1.0))

## Seconds until the next regen creak may sound (tests read it).
func life_wait() -> float:
	return _life_timer

# --- signal handlers -----------------------------------------------------------

func _on_grab_started(_cell: Vector3i) -> void:
	if not _chewing:
		_chewing = true
		_start_chew_loop()

func _on_released() -> void:
	_chewing = false
	_chew_id = ""
	if _chew != null:
		_chew.stop()
		_strain.stop()
	_hush_pull()

## One bite's pull: the stretch layer rises and tightens with the chew ratio
## the chewer reports, and is cut the moment the flesh tears or is let go.
func _on_chew_progress(ratio: float, _cell: Vector3i = Vector3i.ZERO) -> void:
	_ensure_core()
	if not bank.has("pull_stretch"):
		return
	if _pull == null:
		_pull = _make_player()
		_pull.name = "PullStretch"
		_pull.stream = bank.stream("pull_stretch", 0)
		_pull.volume_db = SILENT_DB
	_pull.bus = room_bus if room_bus != &"" else bus
	var r := clampf(ratio, 0.0, 1.0)
	_pull.volume_db = lerpf(pull_db.x, pull_db.y, r * r)
	_pull.pitch_scale = lerpf(pull_pitch.x, pull_pitch.y, r)
	if _pull.is_inside_tree() and not _pull.playing:
		_pull.play()

## Nothing is being pulled: the layer stops (no loop is left running between
## bites) and starts again from its top with the next chew_progress.
func _hush_pull() -> void:
	if _pull != null:
		_pull.volume_db = SILENT_DB
		_pull.stop()

## Level of the stretch layer now, dB (SILENT_DB when nothing is being pulled).
func pull_level_db() -> float:
	return _pull.volume_db if _pull != null else SILENT_DB

func pull_pitch_now() -> float:
	return _pull.pitch_scale if _pull != null else 1.0

## The chewer's own tear: as loud and low as the flesh that really came away
## (FDKChewer.last_units against a whole cell).
func _on_chewer_torn(world_pos: Vector3) -> void:
	var whole := 1.0
	if _chewer != null and is_instance_valid(_chewer) and _chewer.config != null and _chewer.config.flesh_per_cell > 0.0:
		whole = clampf(_chewer.last_units / _chewer.config.flesh_per_cell, 0.0, 1.0)
	_on_cell_torn(world_pos, whole)

## A tear at world_pos. whole 0..1: how much of a whole cell came away (a
## caller without that number, like a tear outside the chewer, leaves it 1).
func _on_cell_torn(world_pos: Vector3, whole: float = 1.0) -> void:
	_hush_pull()
	var tissue := 0
	if terrain != null and terrain.has_method("tissue_at"):
		tissue = int(terrain.call("tissue_at", world_pos))
	_ensure_core()
	last_tear_pitch = (1.0 + bank.rng.randf_range(-tear_pitch_jitter, tear_pitch_jitter)) * (1.0 + thin_tear_pitch * (1.0 - whole))
	last_tear_db = lerpf(thin_tear_db, 0.0, whole)
	var tear_id := String(TISSUE_TEAR.get(tissue, "tear_flesh"))
	if not bank.has(tear_id):
		tear_id = "tear_flesh"
	_play(tear_id, world_pos, last_tear_db, last_tear_pitch, room_bus if room_bus != &"" else bus)
	if tissue == NERVE_TISSUE:
		play("nerve_twitch", world_pos)
	_swallow_timer = swallow_delay

func _on_fill_changed(fill: float, capacity: float, _overfill_capacity: float) -> void:
	var band := int(floor(fill / maxf(capacity, 0.001) * 4.0))
	if band > _fill_band:
		play("stomach_gurgle")
	_fill_band = band

## Call every physics frame with the bob offset (connect_player does this).
## A step is the trough of the bob sine.
func on_footstep_bob(offset: Vector3) -> void:
	var y := offset.y
	var dy := y - _prev_bob
	if _prev_dy < 0.0 and dy >= 0.0 and y < 0.0 and _really_stepped():
		steps_played += 1
		play_step()
	_prev_bob = y
	if dy != 0.0:
		_prev_dy = dy

## True when the listener moved step_min_travel on the level since the last
## bob trough (always true without a listener, and for the first trough).
func _really_stepped() -> bool:
	if listener == null or not listener.is_inside_tree():
		return true
	var at := listener.global_position
	var moved := Vector2(at.x - _step_from.x, at.z - _step_from.z).length()
	var first := not _step_from_set
	_step_from = at
	_step_from_set = true
	return first or moved >= step_min_travel

# --- internals -----------------------------------------------------------------

func _start_chew_loop() -> void:
	_ensure_core()
	var id := "chew_loop_b" if mutation_stage >= 1 and bank.has("chew_loop_b") else "chew_loop_a"
	_chew_id = id
	if not bank.has(id):
		return
	_chew.stream = bank.stream(id, 0)
	_chew.pitch_scale = chew_pitch_scale()
	if _chew.is_inside_tree():
		_chew.play()
	if bank.has("chew_strain"):
		_strain.stream = bank.stream("chew_strain", 0)
		_strain.volume_db = _lin_to_db(strain_level())
		if _strain.is_inside_tree():
			_strain.play()

func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

func _ensure_bed_layer(layer: String) -> void:
	if _bed_players.has(layer) or not bank.has(layer):
		return
	var p := _make_player()
	p.name = "Bed_" + layer
	p.stream = bank.stream(layer, 0)
	_bed_players[layer] = p
	_bed_level[layer] = 0.0
	_bed_target[layer] = 0.0
	_apply_bed_volume(layer)
	if p.is_inside_tree():
		p.play()

## A layer silent this long stops and lets go of its stream; a quick walk
## back still finds it running.
const BED_RELEASE := 30.0

func _release_bed_layer(layer: String) -> void:
	var p := _bed_players[layer] as AudioStreamPlayer
	p.stop()
	p.queue_free()
	_bed_players.erase(layer)
	_bed_level.erase(layer)
	_bed_target.erase(layer)
	_bed_silent.erase(layer)
	bank.forget(layer)

func _apply_bed_volume(layer: String) -> void:
	var db := _lin_to_db(float(_bed_level[layer]))
	(_bed_players[layer] as AudioStreamPlayer).volume_db = db if db <= SILENT_DB else maxf(db + bed_gain_db, SILENT_DB)

func _lin_to_db(v: float) -> float:
	return SILENT_DB if v <= 0.0001 else maxf(linear_to_db(v), SILENT_DB)
