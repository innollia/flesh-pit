extends SceneTree

## Decision 0012 (flesh unit 2, compressive regrowth x1.0) judged in code on
## the kit's real terrain, chewer and stomach. No Main, no save file.
## - a whole cell is 2.0 units: 50 cells fill the stomach, the 81st is refused
## - a cell that has not grown back pays only the density really removed
## - the lever: 100 units -> 8 teeth, 160 -> 13
## - an empty compressive corner in the core is solid again after 166.7 /
##   111.1 / 83.3 / 66.7 s with 0-1 / 2 / 3 / 4 solid neighbours; the mantle's
##   contractile (123.5 s) and the surface's nerve (122.5 s) are as they were
## - a 34-step tunnel one cell wide and two high, dug at 2.7 s a bite: the
##   entrance has closed on turning back, it is torn open again without the
##   stomach refusing, and the body arrives with 110-150 units. At 0.9 s a
##   bite nothing has closed. This compares the paper model with the terrain:
##   the measured values are printed for the record.
const STEP := 0.1
const FAR := Vector3(1000, 1000, 1000)
const CENTER := Vector3(0, 1, 0)
const AIM_TIME := 0.3 ## turning to the next cell (the calculator's aim time)
const STEPS := 34
const X0 := 4 ## first tunnel cell (x); the tunnel runs toward +x
const Y0 := 6 ## floor cell row; the tunnel is rows Y0 and Y0 + 1
const Z0 := 8
const BODY_PROTECT := 0.9 ## main.gd BODY_PROTECT_RADIUS
var _passed := 0
var _failed := 0

func _init() -> void:
	_run_units()
	_run_teeth()
	_run_close_times()
	_run_tunnel()
	print("--- economy r2: %d passed, %d failed ---" % [_passed, _failed])
	quit(1 if _failed else 0)

func _assert(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: " + message)

func _field(chunks_x: int, chunk_size: int, tissue: int = FDKTissueRules.COMPRESSIVE) -> FDKTerrainField:
	var field := FDKTerrainField.new()
	field.config = FDKTerrainConfig.new()
	field.config.chunk_size = chunk_size
	for x in range(chunks_x):
		field.get_or_create_chunk(Vector3i(x, 0, 0)).fill_uniform(1.0, tissue)
	return field

func _mouth(field: FDKTerrainField) -> Array:
	var stomach := FDKStomach.new()
	var chewer := FDKChewer.new()
	chewer.terrain = field
	chewer.stomach = stomach
	chewer.config = stomach.config
	return [chewer, stomach]

func _bite(chewer: FDKChewer, at: Vector3) -> void:
	chewer.try_start(at)
	chewer.process_chew(100.0)
	chewer.stop()

# --- the flesh unit ---------------------------------------------------------------

func _run_units() -> void:
	var field := _field(1, 16)
	var mouth := _mouth(field)
	var chewer: FDKChewer = mouth[0]
	var stomach: FDKStomach = mouth[1]
	var cell: float = field.config.cell_size
	var refused: Array = []
	chewer.refused_full.connect(func(p: Vector3) -> void: refused.append(p))
	_assert(is_equal_approx(stomach.config.flesh_per_cell, 2.0), "a cell is 2 flesh units")
	_assert(is_equal_approx(float(FDKTissueRules.SAW_TEAR_CELLS) * stomach.config.flesh_per_cell, 12.0), "one stroke of the big saw is at most 12 units")
	# whole cells that share no corner: every tear removes all 8 corners
	var cells: Array[Vector3] = []
	for z in range(7):
		for y in range(7):
			for x in range(7):
				cells.append((Vector3(1 + 2 * x, 1 + 2 * y, 1 + 2 * z) + Vector3.ONE * 0.5) * cell)
	_bite(chewer, cells[0])
	_assert(is_equal_approx(stomach.fill, 2.0) and is_equal_approx(chewer.last_units, 2.0), "a whole cell puts 2.0 in the stomach (%.2f)" % stomach.fill)
	_assert(field.density_at(cells[0]) < field.config.iso_level, "and the cell is really gone")
	for i in range(1, 50):
		_bite(chewer, cells[i])
	_assert(is_equal_approx(stomach.fill, stomach.config.capacity) and is_equal_approx(stomach.fill, 100.0), "50 cells fill the stomach to 100 (%.1f)" % stomach.fill)
	_assert(not stomach.is_full() and refused.is_empty(), "a full stomach still eats into the overfill")
	for i in range(50, 80):
		_bite(chewer, cells[i])
	_assert(is_equal_approx(stomach.fill, 160.0) and stomach.is_full() and refused.is_empty(), "80 cells reach the end of the overfill at 160 (%.1f)" % stomach.fill)
	_bite(chewer, cells[80])
	_assert(refused.size() == 1 and is_equal_approx(stomach.fill, 160.0) and field.density_at(cells[80]) >= field.config.iso_level, "the 81st cell is refused: nothing eaten, nothing removed")
	# a cell that has only partly grown back pays what was really removed
	stomach.vomit()
	var g := Vector3i(8, 8, 10) # the 81 cells above end at z 3: this one shares no corner with them
	for dz in range(2):
		for dy in range(2):
			field._add_corner_global(g + Vector3i(1, dy, dz), -1.0)
			field._add_corner_global(g + Vector3i(0, dy, dz), -0.1)
	var before: float = field.cell_corner_sum((Vector3(g) + Vector3.ONE * 0.5) * cell)
	_bite(chewer, (Vector3(g) + Vector3(0.1, 0.5, 0.5)) * cell)
	_assert(is_equal_approx(before, 3.6) and is_equal_approx(stomach.fill, 2.0 * 3.6 / 4.0), "a cell with 3.6 of density left pays 1.8, not 2 (%.2f)" % stomach.fill)
	chewer.free()
	stomach.free()
	field.free()

func _run_teeth() -> void:
	for pair in [[100.0, 8], [160.0, 13]]:
		var prog := FPProgression.new()
		prog.settle(pair[0])
		_assert(prog.teeth == pair[1], "the lever pays %d teeth for %d units (%d)" % [pair[1], int(pair[0]), prog.teeth])

# --- how long an empty corner takes to be solid again --------------------------------

func _close_time(solid_neighbours: int) -> Dictionary:
	var field := _field(1, 6)
	var chunk := field.get_chunk(Vector3i.ZERO)
	var s := Vector3i(3, 3, 3)
	var around: Array[Vector3i] = [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.BACK, Vector3i.FORWARD]
	var held: Array[Vector3i] = []
	for i in range(6 - solid_neighbours):
		held.append(s + around[i])
	field._add_corner_global(s, -1.0)
	for h in held:
		field._add_corner_global(h, -1.0)
	var counted: int = chunk._solid_neighbours(s.x, s.y, s.z, field.config.chunk_size + 1)
	var ticks := 0
	while chunk.get_density_at_corner(s.x, s.y, s.z) < field.config.iso_level and ticks < 5000:
		field.regenerate_all(STEP, FAR, BODY_PROTECT)
		for h in held: # the corners round it are kept open (eaten again and again)
			field._add_corner_global(h, -1.0)
		ticks += 1
	var want: float = field.config.iso_level / (field.config.regen_rate * FDKTissueRules.regen_multiplier(FDKTissueRules.COMPRESSIVE) * FDKChunk.crowd_growth_factor(solid_neighbours))
	field.free()
	return {"seconds": ticks * STEP, "want": want, "counted": counted}

func _shell_time(tissue: int, cc: Vector3i) -> float:
	var field := _field(0, 6)
	field.regen_rate_scale = func(p: Vector3) -> float:
		return FPWorldFeatures.regen_scale(p, CENTER, FPWorldFeatures.SHELL_THICKNESS)
	var chunk := field.get_or_create_chunk(cc)
	chunk.fill_uniform(1.0, tissue)
	for z in range(1, 4):
		for y in range(1, 4):
			for x in range(1, 4):
				chunk.dig_cell(Vector3i(x, y, z), 1.0)
	var ticks := 0
	while chunk.get_density_at_corner(2, 2, 2) < field.config.iso_level and ticks < 5000:
		field.regenerate_all(STEP, FAR, BODY_PROTECT)
		ticks += 1
	field.free()
	return ticks * STEP

func _run_close_times() -> void:
	_assert(is_equal_approx(FDKTissueRules.regen_multiplier(FDKTissueRules.COMPRESSIVE), 1.0), "compressive flesh regrows at x1.0")
	var literal := [166.7, 166.7, 111.1, 83.3, 66.7]
	for n in range(5):
		var r := _close_time(n)
		print("close time, %d solid neighbours: %.1f s (formula %.1f)" % [n, r.seconds, r.want])
		_assert(r.counted == n, "fixture: the corner has %d solid neighbours (%d)" % [n, r.counted])
		_assert(absf(r.seconds - r.want) <= STEP + 0.001 and absf(r.seconds - literal[n]) <= STEP + 0.05, "core, %d solid neighbours: solid again after %.1f s (%.1f)" % [n, literal[n], r.seconds])
	var mantle := _shell_time(FDKTissueRules.CONTRACTILE, Vector3i(5, 0, 0))
	var surface := _shell_time(FDKTissueRules.NERVE, Vector3i(7, 0, 0))
	print("close time, mantle contractile %.1f s, surface nerve %.1f s" % [mantle, surface])
	_assert(absf(mantle - 123.5) <= STEP + 0.05, "mantle contractile closes after 123.5 s as before (%.1f)" % mantle)
	_assert(absf(surface - 122.5) <= STEP + 0.05, "surface nerve closes after 122.5 s as before (%.1f)" % surface)

# --- dig out, turn back, tear the closed tunnel open again ---------------------------

func _step_pos(field: FDKTerrainField, i: int) -> Vector3:
	var cell: float = field.config.cell_size
	return Vector3((X0 + i + 0.5) * cell, Y0 * cell + 0.45, (Z0 + 0.5) * cell)

## Open height of tunnel step `i` on its centre line (metres).
func _open_height(field: FDKTerrainField, i: int) -> float:
	var cell: float = field.config.cell_size
	var x: float = (X0 + i + 0.5) * cell
	var z: float = (Z0 + 0.5) * cell
	var open := 0
	for k in range(100):
		if field.density_at(Vector3(x, Y0 * cell + (k + 0.5) * 0.01 * 2.0 * cell, z)) < field.config.iso_level:
			open += 1
	return open * 0.01 * 2.0 * cell

func _trip(pace: float) -> Dictionary:
	var field := _field(3, 16)
	var mouth := _mouth(field)
	var chewer: FDKChewer = mouth[0]
	var stomach: FDKStomach = mouth[1]
	var body_cfg := FDKPlayerConfig.new()
	var cell: float = field.config.cell_size
	var refused: Array = []
	chewer.refused_full.connect(func(p: Vector3) -> void: refused.append(p))
	var clock := [0.0, 0.0] # seconds run, seconds owed to the next regrowth step
	var run := func(seconds: float, body: Vector3) -> void:
		clock[0] += seconds
		clock[1] += seconds
		while clock[1] >= STEP:
			field.regenerate_all(STEP, body, BODY_PROTECT)
			clock[1] -= STEP
	var bite_time := func() -> float:
		return stomach.config.base_chew_time * stomach.chew_time_multiplier() + AIM_TIME + (pace - stomach.config.base_chew_time - AIM_TIME)
	# --- out
	for i in range(STEPS):
		var body := _step_pos(field, maxi(i - 1, 0))
		for row in range(2):
			run.call(bite_time.call(), body)
			_bite(chewer, Vector3((X0 + i + 0.5) * cell, (Y0 + row + 0.5) * cell, (Z0 + 0.5) * cell))
	var dug_seconds: float = clock[0]
	var turn_fill: float = stomach.fill
	# the entrance on turning back: its top and bottom corner rows, and the middle
	var outer := 1.0
	var middle := 1.0
	for dz in range(2):
		outer = minf(outer, minf(field.corner_density_global(Vector3i(X0 + 1, Y0, Z0 + dz)), field.corner_density_global(Vector3i(X0 + 1, Y0 + 2, Z0 + dz))))
		middle = minf(middle, field.corner_density_global(Vector3i(X0 + 1, Y0 + 1, Z0 + dz)))
	var closed_at_turn := 0
	for i in range(STEPS):
		if _open_height(field, i) < body_cfg.squeeze_min_height:
			closed_at_turn += 1
	# --- back
	var closed := 0
	var squeezed := 0
	var retorn := 0.0
	var stuck := false
	for i in range(STEPS - 1, -1, -1):
		var body := _step_pos(field, mini(i + 1, STEPS - 1))
		var h := _open_height(field, i)
		var pinch := 1.0
		if h < body_cfg.squeeze_min_height:
			closed += 1
			var x: float = (X0 + i + 0.5) * cell
			for aim_y in [Y0 * cell + 0.05, (Y0 + 2) * cell - 0.05]:
				var aim := Vector3(x, aim_y, (Z0 + 0.5) * cell)
				if field.density_at(aim) < field.config.iso_level:
					continue
				run.call(bite_time.call(), body)
				var had: float = stomach.fill
				_bite(chewer, aim)
				retorn += stomach.fill - had
			if not refused.is_empty() or _open_height(field, i) < body_cfg.squeeze_min_height:
				stuck = true
				break
		elif h < body_cfg.crouch_height:
			squeezed += 1
			pinch = lerpf(body_cfg.squeeze_speed_min, 1.0, (h - body_cfg.squeeze_min_height) / (body_cfg.crouch_height - body_cfg.squeeze_min_height))
		var gorge: float = lerpf(1.0, FPProgression.GORGE_WALK_MIN, stomach.overfill_ratio())
		run.call(cell / (body_cfg.crouch_speed * minf(pinch, gorge)), body)
	var result := {"dug_seconds": dug_seconds, "turn_fill": turn_fill, "outer": outer, "middle": middle,
		"closed_at_turn": closed_at_turn, "closed": closed, "squeezed": squeezed, "retorn": retorn, "stuck": stuck,
		"refused": refused.size(), "fill": stomach.fill, "seconds": clock[0]}
	chewer.free()
	stomach.free()
	field.free()
	return result

func _run_tunnel() -> void:
	var slow := _trip(2.7)
	print("tunnel 34 steps at 2.7 s a bite: dug %.0f s to %.0f u; entrance rows top/bottom %.2f, middle %.2f; closed on turning %d; back in %.0f s, closed steps met %d, squeezed %d, torn again %.1f u, arrived with %.1f u, refused %d, stuck %s" % [
		slow.dug_seconds, slow.turn_fill, slow.outer, slow.middle, slow.closed_at_turn, slow.seconds - slow.dug_seconds, slow.closed, slow.squeezed, slow.retorn, slow.fill, slow.refused, slow.stuck])
	# the first step has no open face behind it (2 + 2), every later one pays 2 + 1
	_assert(is_equal_approx(slow.turn_fill, 4.0 + (STEPS - 1) * 3.0), "34 steps of a two-row tunnel are 103 units (4, then 3 a step): %.1f" % slow.turn_fill)
	_assert(absf(slow.dug_seconds - STEPS * 2 * 2.7) <= 1.5, "fixture: the tunnel took %.0f s to dig (%.1f)" % [STEPS * 2 * 2.7, slow.dug_seconds])
	_assert(slow.outer >= 0.5, "2.7 s a bite: the entrance's top and bottom corner rows are solid on turning back (%.2f)" % slow.outer)
	_assert(slow.closed > 0, "2.7 s a bite: closed steps are met on the way back (%d)" % slow.closed)
	_assert(not slow.stuck and slow.refused == 0, "2.7 s a bite: the closed tunnel is torn open again without the stomach refusing")
	_assert(slow.fill >= 110.0 and slow.fill <= 150.0, "2.7 s a bite: the body arrives with 110-150 units (%.1f)" % slow.fill)
	var fast := _trip(0.9)
	print("tunnel 34 steps at 0.9 s a bite: dug %.0f s to %.0f u; entrance rows top/bottom %.2f, middle %.2f; closed on turning %d; back in %.0f s, closed steps met %d, squeezed %d, arrived with %.1f u" % [
		fast.dug_seconds, fast.turn_fill, fast.outer, fast.middle, fast.closed_at_turn, fast.seconds - fast.dug_seconds, fast.closed, fast.squeezed, fast.fill])
	_assert(fast.closed_at_turn == 0 and fast.closed == 0 and not fast.stuck, "0.9 s a bite: no step has closed at 100 units, nor on the way back (%d / %d)" % [fast.closed_at_turn, fast.closed])
	_assert(is_equal_approx(fast.fill, fast.turn_fill), "0.9 s a bite: nothing is torn twice (%.1f)" % fast.fill)
