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
##   tear_flesh tear_nerve tear_fat tear_membrane swallow stomach_gurgle
##   nerve_twitch vomit_toilet vomit_floor step_<surface>_s<1..3>
##   chew_loop_a chew_loop_b chew_strain regen_creak depth_marker
##   shell_transition canary_chirp canary_warn canary_wrong

const SILENT_DB := -80.0
const TISSUE_TEAR := {0: "tear_flesh", 1: "tear_nerve", 2: "tear_fat", 3: "tear_membrane"}
const NERVE_TISSUE := 1

@export var manifest_path: String = ""
@export var bus: StringName = &"Master"
## Lowest chew-loop pitch when badly overfilled (1 = normal speed).
@export var chew_pitch_min: float = 0.55
## Delay between a tear and its swallow.
@export var swallow_delay: float = 0.3
## Seconds between random "body alive" one-shots (regen creaks) while a body bed plays.
@export var life_interval: Vector2 = Vector2(5.0, 12.0)
## Beds that count as "inside the body" (life one-shots only play there).
@export var body_beds: PackedStringArray = PackedStringArray(["body_a", "body_b"])
## Shell index from which the deeper bed is used.
@export var deep_shell: int = 2

var bank: FDKSoundBank
var terrain: Node = null
var stomach: FDKStomach = null
var listener: Node3D = null
var surface: String = "flesh"
var mutation_stage: int = 0
var current_bed: String = ""
var shell: int = -1
var last_played: String = ""
var played_log: Array[String] = []
var steps_played: int = 0

var _bed_players: Dictionary = {}
var _bed_level: Dictionary = {}
var _bed_target: Dictionary = {}
var _fade: float = 1.0
var _chew: AudioStreamPlayer
var _strain: AudioStreamPlayer
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
	chewer.grab_started.connect(_on_grab_started)
	chewer.cell_torn.connect(_on_cell_torn)
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
	for b in bank.beds.keys():
		for layer in bank.beds[b]:
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
	_ensure_core()
	if not bank.has(id):
		return
	var stream := bank.pick(id)
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
		p3.bus = bus
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
		p2.bus = bus
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
	if _swallow_timer >= 0.0:
		_swallow_timer -= delta
		if _swallow_timer < 0.0:
			play("swallow")
	if _chewing:
		_chew.pitch_scale = chew_pitch_scale()
		_strain.volume_db = _lin_to_db(strain_level())
	if current_bed in body_beds:
		_life_timer -= delta
		if _life_timer <= 0.0:
			_life_timer = bank.rng.randf_range(life_interval.x, life_interval.y)
			var pos: Variant = null
			if listener != null and listener.is_inside_tree():
				var dir := Vector3(bank.rng.randf_range(-1, 1), bank.rng.randf_range(-0.5, 0.5), bank.rng.randf_range(-1, 1)).normalized()
				pos = listener.global_position + dir * bank.rng.randf_range(2.5, 6.0)
			play("regen_creak", pos)

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

func _on_cell_torn(world_pos: Vector3) -> void:
	var tissue := 0
	if terrain != null and terrain.has_method("tissue_at"):
		tissue = int(terrain.call("tissue_at", world_pos))
	play(String(TISSUE_TEAR.get(tissue, "tear_flesh")), world_pos)
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
	if _prev_dy < 0.0 and dy >= 0.0 and y < 0.0:
		steps_played += 1
		play(footstep_id())
	_prev_bob = y
	if dy != 0.0:
		_prev_dy = dy

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

func _apply_bed_volume(layer: String) -> void:
	(_bed_players[layer] as AudioStreamPlayer).volume_db = _lin_to_db(float(_bed_level[layer]))

func _lin_to_db(v: float) -> float:
	return SILENT_DB if v <= 0.0001 else maxf(linear_to_db(v), SILENT_DB)
