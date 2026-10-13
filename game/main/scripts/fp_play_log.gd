class_name FPPlayLog
extends Node

## Timed reward-event log for docs/spec/09-reward-scale.md 10.2, read by
## tools/economy/reward_scale.py --log. Off unless the environment variable
## FP_PLAY_LOG names a CSV file; it never touches the save slot or settings.
## Only reads Main's state and listens to its signals.
##
## Columns: t, phase (A restroom or rest container / B digging out / C on
## the way back), shell, channel (S A D R B T), code (R-TEAR ...), du,
## dteeth, dhair_biome, dhair_common, dtumor, fill, x, y, z, sound,
## arm_visible, input_active. A PHASE row is written every second so the
## expedition boundaries are there even when nothing happens.

const COLS := "t,phase,shell,channel,code,du,dteeth,dhair_biome,dhair_common,dtumor,fill,x,y,z,sound,arm_visible,input_active"
const SAMPLE_EVERY := 1.0
## Walking this much back toward the restroom from the farthest point of
## the excursion (or a full stomach) starts the return (phase C).
const RETURN_BACKTRACK := 1.5
const MOVE_ACTIONS := ["fdk_move_forward", "fdk_move_back", "fdk_move_left", "fdk_move_right", "fdk_eat", "fp_pick", "fp_interact"]

var m: Node3D
var path := ""
var _f: FileAccess
var _t := 0.0
var _sample_t := 0.0
var _phase := "A"
var _far := 0.0
var _hairs := {}
var _deepest := 0

static func wanted() -> String:
	return OS.get_environment("FP_PLAY_LOG")

func setup(main: Node3D, file_path: String) -> bool:
	m = main
	path = file_path
	_f = FileAccess.open(path, FileAccess.WRITE)
	if _f == null:
		push_warning("FP_PLAY_LOG: cannot write " + path)
		return false
	_f.store_line(COLS)
	m.chewer.cell_torn.connect(func(_p): _row("S", "R-TEAR", {"du": m.chewer.last_units}, 1))
	m.flushed.connect(func(teeth, _h): _row("R", "R-SETL", {"dteeth": teeth}, 1))
	m.died.connect(func(_c): _row("T", "K-DEATH", {}, 1))
	m.ending_reached.connect(func(): _row("R", "R-END", {}, 1))
	m.canary_chirp.connect(func(_u): _row("T", "K-CANARY", {}, 1))
	m.stomach.vomited.connect(_on_vomited)
	if m.mirror != null and m.mirror.has_signal("mutated"):
		m.mirror.mutated.connect(func(_id): _row("B", "R-MUT", {}, 1))
	if m.mutation_apply != null:
		m.mutation_apply.tumor_eaten.connect(func(): _row("B", "R-TUM-EAT", {"dtumor": 1}, 1))
	_hairs = _hair_counts()
	_deepest = int(m.progression.deepest_shell)
	return true

func _exit_tree() -> void:
	if _f != null:
		_f.flush()
		_f.close()
		_f = null

func _process(delta: float) -> void:
	if _f == null or m == null:
		return
	_t += delta
	_update_phase()
	# hair grows on eating: one row per pool that gained strands
	var now := _hair_counts()
	for pool in now:
		var d: int = int(now[pool]) - int(_hairs.get(pool, 0))
		if d > 0:
			if pool == FPProgression.COMMON:
				_row("A", "R-HAIR-C", {"dhair_common": d}, 0)
			else:
				_row("A", "R-HAIR-B", {"dhair_biome": d}, 0)
	_hairs = now
	var deepest := int(m.progression.deepest_shell)
	if deepest > _deepest:
		_deepest = deepest
		_row("D", "R-SHELL", {}, 0)
	_sample_t -= delta
	if _sample_t <= 0.0:
		_sample_t = SAMPLE_EVERY
		_row("", "PHASE", {}, 0)
		_f.flush()

func _update_phase() -> void:
	var p: Vector3 = m.player.global_position
	var home: bool = m.restroom.contains(p) or FPWorldFeatures.in_container(p, m.rest_points)
	if home:
		_phase = "A"
		_far = 0.0
		return
	var d: float = p.distance_to(m.RESTROOM_CENTER)
	if _phase == "A":
		_phase = "B"
		_far = d
	if _phase == "B":
		_far = maxf(_far, d)
		if m.stomach.is_full() or (m.stomach.fill > 0.0 and _far - d >= RETURN_BACKTRACK):
			_phase = "C"

func _on_vomited(amount: float) -> void:
	if amount <= 0.0:
		return
	var p: Vector3 = m.player.global_position
	var at_home: bool = m._near_toilet() or m._near_rest_point() >= 0
	if not at_home:
		_row("T", "K-VOMIT-OUT", {"du": -amount}, 1)

func _hair_counts() -> Dictionary:
	var out := {}
	out[FPProgression.COMMON] = m.progression.hairs(FPProgression.COMMON)
	for b in FPProgression.BIOMES:
		out[b] = m.progression.hairs(b)
	return out

func _input_active() -> int:
	for a in MOVE_ACTIONS:
		if InputMap.has_action(a) and Input.is_action_pressed(a):
			return 1
	return 0

func _row(channel: String, code: String, d: Dictionary, sound: int) -> void:
	if _f == null:
		return
	var p: Vector3 = m.player.global_position
	var cols := [
		"%.3f" % _t, _phase, str(m.shell_at(p)), channel, code,
		"%.3f" % float(d.get("du", 0.0)), str(int(d.get("dteeth", 0))),
		str(int(d.get("dhair_biome", 0))), str(int(d.get("dhair_common", 0))), str(int(d.get("dtumor", 0))),
		"%.2f" % m.stomach.fill, "%.2f" % p.x, "%.2f" % p.y, "%.2f" % p.z,
		str(sound), "1" if bool(m.get("_mirror_open")) else "0", str(_input_active()),
	]
	_f.store_line(",".join(cols))
