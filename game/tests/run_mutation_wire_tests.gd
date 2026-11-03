extends SceneTree

## Wiring of mutation signals that had no consumer (audit 2026-11-03):
## - 1-3 M22: the alien hand's own tear shows what a chewer tear shows (blood
##   on the hands, the hole's snap, strands, bits and blood spray), and the
##   eaten amount, removed density and the published hole stay one tear.
## - 1-9 M29: a crush death with dormancy sleeps curled up with the eyes shut
##   for 30 s, then the eyes open and the body uncurls; no game input acts
##   meanwhile, Esc still pauses.
## - M22 parity (findings 2026-11-03): an alien-hand tear changes the game
##   exactly as a chewer tear of the same cell does -- dug count, stomach and
##   hair, nerve touch and regrowth, extra cells, terrain -- in two identical
##   worlds tearing fat, flesh, nerve and rib cells.
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
	if _frame == 9:
		_run_dormancy_wake()
		_run_plain_crush_not_dormant()
		_m.queue_free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test-mutation-wire.bin"))
		_m = _new_world()
		return false
	# M22 parity: the same tears by the chewer in one world, by the alien
	# hand in an identical second world
	if _frame == 11 or _frame == 17:
		_m.finish_opening()
		return false
	if _frame == 15:
		_chewer_deltas = _run_parity_tears(false)
		_m.queue_free()
		_m = _new_world()
		return false
	if _frame < 21:
		return false
	_compare_parity(_chewer_deltas, _run_parity_tears(true))
	_m.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test-mutation-wire.bin"))
	print("--- %d passed, %d failed ---" % [_passed, _failures])
	quit(1 if _failures > 0 else 0)
	return true

var _chewer_deltas: Array = []
const PARITY_KINDS := [FDKTissueRules.COMPRESSIVE, FDKTissueRules.FAT, FDKTissueRules.COMPRESSIVE, FDKTissueRules.NERVE, FDKTissueRules.CARTILAGE, FDKTissueRules.FAT, FDKTissueRules.COMPRESSIVE, FDKTissueRules.NERVE, FDKTissueRules.CARTILAGE, FDKTissueRules.COMPRESSIVE]
const PARITY_NAMES := ["flesh at a nerve-regrowth spot", "fat", "flesh", "nerve", "rib", "fat 2", "flesh 2", "nerve 2", "rib 2", "flesh+M07"]
const PARITY_REGROW := 0 ## the tear aimed where main.tear_effects grows a nerve back

func _new_world() -> Node3D:
	var w: Node3D = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	w.save_path = "user://test-mutation-wire.bin"
	w.rest_seed = 1337
	get_root().add_child(w)
	return w

## The game state a tear can change, around the torn cell.
func _game_state(at: Vector3) -> Dictionary:
	var m = _m
	var prog: FPProgression = m.progression
	var cs: float = m.terrain_config.cell_size
	var cell := Vector3i(floori(at.x / cs), floori(at.y / cs), floori(at.z / cs))
	var dens := 0.0
	for z in range(-7, 9):
		for y in range(-7, 9):
			for x in range(-7, 9):
				dens += m.terrain.corner_density_global(cell + Vector3i(x, y, z))
	return {
		"dug": float(m.excavated_cells),
		"stomach": float(m.stomach.fill),
		"carried": float(m.carried_flesh),
		"deepest": float(prog.deepest_shell),
		"hair_common": float(prog.hair_carry.get(FPProgression.COMMON, 0.0)),
		"hair_pools": float(prog.hair_carry.size()),
		"points": float(prog.mutation_tree.points(FPProgression.COMMON)),
		"nerves": float(m.nerves.size()),
		"nerves_touched": float(m._nerve_cool.size()),
		"hazards": float(m._hazards.size()),
		"density": dens,
		"hole_corners": float(m.terrain._visible_tear_corners.size()),
	}

## Ten tears into the same wall: flesh where a nerve grows back, fat, flesh,
## nerve and rib cartilage twice, then flesh with M07 (a second cell behind). A fresh nerve stands at
## each contact point and the dug count is past the regrowth threshold, so
## nerve touch and nerve regrowth can both happen. Returns each tear's deltas.
func _run_parity_tears(alien: bool) -> Array:
	var m = _m
	var ma: FPMutationApply = m.mutation_apply
	var prog: FPProgression = m.progression
	_place_facing_flesh()
	m.excavated_cells = 8
	var out: Array = []
	var kinds := PARITY_KINDS
	for i in range(kinds.size()):
		if i == kinds.size() - 1:
			prog.mutation_tree._purchased["M07"] = true
		# each tear into an untouched spot of the wall
		m.terrain.remesh_all()
		if i == PARITY_REGROW:
			_aim_at_regrowth_spot()
		else:
			_aim(0.25 * float((i - 1) % 5 - 2), -0.15 + (0.3 if i >= 6 else 0.0))
		var target: Vector3 = ma._alien_target()
		_assert(target != Vector3.INF, "parity fixture: a cell in reach (%s, tear %d)" % ["alien" if alien else "chewer", i])
		if target == Vector3.INF:
			return out
		var at: Vector3 = _cell_center(target)
		var rc: Array = m.terrain.world_to_cell(at)
		(m.terrain.get_or_create_chunk(rc[0]) as FDKChunk).set_tissue_at_cell(rc[1].x, rc[1].y, rc[1].z, kinds[i])
		# a nerve rooted in the flesh right beside the cell (its root stays in
		# flesh after the tear), in reach of the tear's nerve touch
		var dir: Vector3 = m.player.get_look_ray()[1]
		var side: Vector3 = dir.cross(Vector3.UP).normalized()
		var up: Vector3 = side.cross(dir).normalized()
		var cs: float = m.terrain_config.cell_size
		for off in [side, -side, -up, up]:
			var root: Vector3 = at + (off as Vector3) * cs * 1.3
			if m.terrain.density_at(root - dir * 0.15) >= 0.9 and m.terrain.density_at(root + dir * 0.15) >= 0.9:
				# as main._spawn_nerve sets one up, but in the tree at once
				var n := FDKNerveStalk.new()
				n.length = 0.5
				n.terrain = m.terrain
				n.place(root, -dir)
				if n.is_anchored():
					m.add_child(n)
					n.disturbed.connect(m._on_nerve_disturbed)
					m.nerves.append(n)
					break
				n.free()
		var s0 := _game_state(at)
		if alien:
			_assert(ma.alien_tear(), "parity: the alien hand tears tear %d" % i)
		else:
			var torn: Array = []
			var cb := func(p: Vector3) -> void: torn.append(p)
			m.chewer.cell_torn.connect(cb)
			m.chewer.try_start(at)
			m.chewer.process_chew(1000.0)
			m.chewer.stop()
			m.chewer.cell_torn.disconnect(cb)
			_assert(torn.size() == 1 and torn[0].distance_to(at) < 0.001, "parity: the chewer tears tear %d at the same cell" % i)
		var s1 := _game_state(at)
		var d := {}
		for k in s0.keys():
			d[k] = float(s1[k]) - float(s0[k])
		out.append(d)
	prog.mutation_tree._purchased.erase("M07")
	return out

func _cell_center(p: Vector3) -> Vector3:
	var cs: float = _m.terrain_config.cell_size
	return (Vector3(floorf(p.x / cs), floorf(p.y / cs), floorf(p.z / cs)) + Vector3(0.5, 0.5, 0.5)) * cs

func _aim(yaw: float, pitch: float) -> void:
	_m.player.rotation.y = PI + yaw
	_m.player.camera_pivot.rotation.x = pitch
	_m.player.force_update_transform()

## The first tear: a cell whose spot (hash) grows a nerve once past the dug
## threshold, with a small pocket carved into the flesh beside it, on the
## side main.tear_effects looks for a wall to root the new nerve in.
func _aim_at_regrowth_spot() -> void:
	var m = _m
	_aim(-0.5, -0.15)
	var t: Vector3 = m.mutation_apply._alien_target()
	if t == Vector3.INF:
		return
	var at: Vector3 = _cell_center(t)
	var dir := Vector3(1, 0, 0) if FDKLowPoly.hash3(int(at.z * 2.0), 1, 2) > 0.5 else Vector3(-1, 0, 0)
	m.terrain.carve_sphere(at + dir * 1.75, 0.75)
	m.terrain.remesh_all()

func _compare_parity(chew: Array, alien: Array) -> void:
	var nt := PARITY_KINDS.size()
	_assert(chew.size() == nt and alien.size() == nt, "parity: %d tears in each world (%d / %d)" % [nt, chew.size(), alien.size()])
	var names := PARITY_NAMES
	var touched := 0.0
	var grown := 0.0
	for i in range(mini(chew.size(), alien.size())):
		var c: Dictionary = chew[i]
		var a: Dictionary = alien[i]
		touched += float(c.nerves_touched)
		if i == PARITY_REGROW:
			grown = float(c.nerves)
		_assert(float(c.dug) == 1.0 and float(c.stomach) > 0.0, "parity reference: the chewer's %s tear digs one cell and feeds the stomach" % names[i])
		for k in c.keys():
			_assert(absf(float(c[k]) - float(a[k])) <= 1e-4 * maxf(1.0, absf(float(c[k]))), "M22 parity %s: %s changes the same (chewer %.4f, alien %.4f)" % [names[i], k, float(c[k]), float(a[k])])
	_assert(touched > 0.0, "parity fixture: at least one tear touched a nerve (%d)" % int(touched))
	_assert(grown > 0.0, "parity fixture: the regrowth-spot tear grew a nerve back (%d)" % int(grown))
	if chew.size() == nt:
		_assert(float(chew[nt - 1].stomach) > float(chew[2].stomach) * 1.5, "parity fixture: M07 took a second cell (%.2f vs %.2f)" % [float(chew[nt - 1].stomach), float(chew[2].stomach)])
	print("parity: nerves grown %d, touched %d" % [int(grown), int(touched)])

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
	_assert(d.snap == 0.0 and d.jolt == 0.0 and _has_wound_at(_cell_center(at)), "M22 the alien tear snaps the rim, jolts the view and leaves the wound")
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
