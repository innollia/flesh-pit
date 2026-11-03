extends SceneTree

## Wiring of mutation signals that had no consumer (audit 2026-11-03):
## - 1-3 M22: the alien hand's own tear shows what a chewer tear shows (blood
##   on the hands, the hole's snap, strands, bits and blood spray), and the
##   eaten amount, removed density and the published hole stay one tear.
## - 1-9 M29: a crush death with dormancy sleeps curled up with the eyes shut
##   for 30 s, then the eyes open and the body uncurls; no game input acts
##   meanwhile, Esc still pauses.
## Isolated save (never the player's slot).
## Run: godot_console --headless --path game --script res://tests/run_mutation_wire_tests.gd

var _failures := 0
var _passed := 0
var _m: Node3D
var _frame := 0

func _assert(c: bool, msg: String) -> void:
	if c:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: %s" % msg)

func _init() -> void:
	print("=== flesh-pit mutation wiring tests ===")
	_m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	_m.save_path = "user://test-mutation-wire.bin"
	_m.rest_seed = 1337
	get_root().add_child(_m)

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 2:
		_m.finish_opening()
	if _frame < 6:
		return false
	if _frame == 6:
		_run_alien_tear_gore()
		_run_dormancy()
		return false # the keys pressed asleep stay "just pressed" this frame
	if _frame < 9:
		return false
	_run_dormancy_wake()
	_run_plain_crush_not_dormant()
	_m.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test-mutation-wire.bin"))
	print("--- %d passed, %d failed ---" % [_passed, _failures])
	quit(1 if _failures > 0 else 0)
	return true

## What a tear shows, before -> after (deltas).
func _tear_marks() -> Dictionary:
	var tf = _m.tear_feel
	return {
		"blood": float(_m.hand_blood),
		"gore": int(_m.gore.live_count()),
		"wounds": (tf._wounds as Array).size(),
		"strands": (tf._strands as Array).size(),
		"snap": float(tf._snap_age),
		"jolt": float(tf._jolt_t),
	}

func _has_wound_at(p: Vector3) -> bool:
	for w in _m.tear_feel._wounds:
		if (w.pos as Vector3).distance_to(p) < 0.05:
			return true
	return false

func _place_facing_flesh() -> void:
	var m = _m
	m.terrain.carve_sphere(Vector3(0, 1.2, 4.2), 1.6)
	m.terrain.remesh_all()
	m.player.set_physics_process(false)
	m.player.velocity = Vector3.ZERO
	m.player.global_position = Vector3(0, 0.6, 4.0)
	m.player.rotation.y = PI
	m.player.camera_pivot.rotation.x = -0.15
	m.player.force_update_transform()
	m.progression.hands.clear()
	m.carry_mode = false

func _run_alien_tear_gore() -> void:
	var m = _m
	var prog: FPProgression = m.progression
	var ma: FPMutationApply = m.mutation_apply
	_place_facing_flesh()
	prog.mutation_tree._purchased["M22"] = true
	# a chewer tear first: what the player sees when they tear a cell
	m.hand_blood = 0.0
	var chew_at: Vector3 = ma._alien_target()
	_assert(chew_at != Vector3.INF, "fixture: edible flesh in reach")
	m.terrain.dig_at(chew_at, 1.0)
	var a := _tear_marks()
	m.chewer.cell_torn.emit(chew_at)
	var b := _tear_marks()
	_assert(b.blood > a.blood and b.gore > a.gore and b.snap == 0.0 and b.jolt == 0.0 and _has_wound_at(chew_at), "reference: a chewer tear bloodies the hands, sprays gore, snaps the rim")
	# then the alien hand's own tear, a cell further in
	m.tear_feel.tick(1.0)
	m.terrain.remesh_all()
	var at: Vector3 = ma._alien_target()
	_assert(at != Vector3.INF and m.terrain.density_at(at) >= 0.5, "fixture: a second cell for the alien hand")
	var fill0: float = m.stomach.fill
	var sum0: float = m.terrain.cell_corner_sum(at)
	var c := _tear_marks()
	_assert(ma.alien_tear(), "M22 the alien hand tears")
	var d := _tear_marks()
	_assert(is_equal_approx(d.blood - c.blood, b.blood - a.blood), "M22 the alien tear bloodies the hands like a chewer tear (%.3f vs %.3f)" % [d.blood - c.blood, b.blood - a.blood])
	_assert(d.gore - c.gore == b.gore - a.gore, "M22 the alien tear sprays the same gore burst (%d vs %d)" % [d.gore - c.gore, b.gore - a.gore])
	_assert(d.snap == 0.0 and d.jolt == 0.0 and _has_wound_at(at), "M22 the alien tear snaps the rim, jolts the view and leaves the wound")
	_assert(d.strands >= c.strands and d.strands > 0, "M22 the alien tear snaps strands")
	# one and the same dig: eaten units = removed density, hole published
	var units: float = m.stomach_config.units_for_removed(sum0 - m.terrain.cell_corner_sum(at))
	_assert(units > 0.0 and is_equal_approx(m.stomach.fill - fill0, units), "M22 the stomach got exactly the density the cell lost (%.2f / %.2f)" % [m.stomach.fill - fill0, units])
	_assert(m.terrain.density_at(at) < 0.5, "M22 the cell is gone from the terrain")
	_assert(_tear_queued(at), "M22 the bloody hole is the published tear")
	prog.mutation_tree._purchased.erase("M22")
	m.player.set_physics_process(true)

func _tear_queued(p: Vector3) -> bool:
	var t: FDKTerrainField = _m.terrain
	var cs: float = _m.terrain_config.cell_size
	var cell := Vector3i(floori(p.x / cs), floori(p.y / cs), floori(p.z / cs))
	return t._visible_tear_corners.has(cell) and not t._visible_tear_readers.is_empty()

func _shut() -> float:
	return float(_m.wake_lids._mat.get_shader_parameter("close"))

## One real game frame of Main and the mutation node (and the lids).
func _tick(dt: float) -> void:
	_m._process(dt)
	_m.mutation_apply._process(dt)
	_m.wake_lids._process(dt)

func _run_dormancy() -> void:
	var m = _m
	var prog: FPProgression = m.progression
	var ma: FPMutationApply = m.mutation_apply
	var pl = m.player
	_place_facing_flesh()
	pl.set_physics_process(true)
	pl.set("_pitch", 0.2)
	prog.mutation_tree._purchased["M29"] = true
	m.die("crush")
	var stand_eye: float = -pl.config.stand_height * 0.5 + pl.config.eye_height
	_assert(ma.is_dormant(), "M29 a crush death goes dormant")
	_tick(0.1)
	# asleep: eyes shut, the heart slow, curled on the restroom floor
	_assert(m.wake_lids.visible and m.wake_lids.lids.visible and _shut() > 0.99, "M29 asleep: the eyes are shut (%.2f)" % _shut())
	_assert(ma.dormant_curl() > 0.99, "M29 asleep: the body is curled up")
	_assert(pl.camera_pivot.position.y < stand_eye - 0.7, "M29 asleep: the head is down on the floor (%.2f)" % pl.camera_pivot.position.y)
	_assert(pl.camera_pivot.rotation.x < -0.8 and absf(pl.camera_pivot.rotation.z) > 0.2, "M29 asleep: curled, head bent to the knees and to one side")
	_assert(bool(pl.get("_is_crouching")), "M29 asleep: the legs are drawn up (crouched body)")
	var rest_l := {"pos": Vector3(-0.16, -0.175, -0.31), "wrist_pitch": 48.0, "wrist_yaw": -14.0, "wrist_roll": 12.0, "f1": 12.0, "f2": 16.0, "f3": 12.0, "t1": -6.0, "t2": 6.0, "t3": 10.0, "t_opp": 0.0}
	var lp: Dictionary = m.hand_motions.shape_pose(m.hands_rig, -1.0, rest_l)
	_assert(float(lp["f1"]) > 60.0 and (lp["pos"] as Vector3).z > -0.28 and (lp["pos"] as Vector3).y < -0.25, "M29 asleep: the hands are fists drawn in to the chest")
	# no input acts while asleep (spec: it only wakes 30 s later)
	_assert(not pl.is_physics_processing() and not pl.is_processing_unhandled_input(), "M29 asleep: no walking, no looking around")
	var beat0: float = m.wake_lids._beat
	Input.action_press("fp_mutate")
	_tick(0.1)
	Input.action_release("fp_mutate")
	_assert(not m._mirror_open, "M29 asleep: Tab does not open the mutation screen")
	Input.action_press("fp_vomit")
	_tick(0.1)
	Input.action_release("fp_vomit")
	_assert(m.hand_motions.kind == "", "M29 asleep: V does not start a heave")
	_assert(m.wake_lids._beat - beat0 < 0.2 * 0.7, "M29 asleep: the heart beats slower than awake")
	# Esc still closes the eyes on the pause screen: the dormancy lids give way
	get_root().get_tree().paused = true
	m.wake_lids._process(0.016)
	_assert(not m.wake_lids.lids.visible, "M29 paused: the pause lids are not covered by the sleeping lids")
	get_root().get_tree().paused = false

func _run_dormancy_wake() -> void:
	var m = _m
	var prog: FPProgression = m.progression
	var ma: FPMutationApply = m.mutation_apply
	var pl = m.player
	var stand_eye: float = -pl.config.stand_height * 0.5 + pl.config.eye_height
	var rest_l := {"pos": Vector3(-0.16, -0.175, -0.31), "wrist_pitch": 48.0, "wrist_yaw": -14.0, "wrist_roll": 12.0, "f1": 12.0, "f2": 16.0, "f3": 12.0, "t1": -6.0, "t2": 6.0, "t3": 10.0, "t_opp": 0.0}
	var lp: Dictionary
	# just before 30 s: still asleep
	while ma._dormant_t < FPProgression.DORMANT_WAKE - 0.3:
		_tick(0.25)
	var t: float = ma._dormant_t
	_assert(ma.is_dormant() and _shut() > 0.99 and ma.dormant_curl() > 0.99, "M29 at %.1f s still asleep" % t)
	# wakes at 30 s: the eyes open first, the body still curled
	var opened := false
	var curled_when_open := false
	var rose := false
	for i in range(80):
		_tick(0.05)
		if not opened and _shut() < 0.2 and m.wake_lids.playing():
			opened = true
			curled_when_open = ma.dormant_curl() > 0.9
		if opened and ma.dormant_curl() < 0.5 and ma.dormant_curl() > 0.0:
			rose = true
	_assert(opened and curled_when_open, "M29 wake: the eyes open on the curled-up body")
	_assert(rose, "M29 wake: the body uncurls after the eyes open")
	_assert(not ma.is_dormant() and is_equal_approx(ma.dormant_curl(), 0.0), "M29 awake again")
	_assert(pl.is_physics_processing() and pl.is_processing_unhandled_input(), "M29 awake: walking and looking come back")
	_assert(absf(pl.camera_pivot.position.y - stand_eye) < 0.02 and is_equal_approx(pl.camera_pivot.rotation.x, 0.2) and is_equal_approx(pl.camera_pivot.rotation.z, 0.0), "M29 awake: standing, the view where it was (%.2f)" % pl.camera_pivot.position.y)
	lp = m.hand_motions.shape_pose(m.hands_rig, -1.0, rest_l)
	_assert(lp == rest_l, "M29 awake: the hands are back in their own pose")
	_assert(m.restroom.contains(pl.global_position), "M29 wakes in the restroom")
	prog.mutation_tree._purchased.erase("M29")

func _run_plain_crush_not_dormant() -> void:
	var m = _m
	var ma: FPMutationApply = m.mutation_apply
	_place_facing_flesh()
	m.player.set_physics_process(true)
	m.die("crush")
	_assert(not ma.is_dormant() and m.player.is_physics_processing(), "without M29 a crush death wakes at once (no dormancy)")
	_assert(is_equal_approx(ma.dormant_curl(), 0.0), "without M29 the body is not curled")
