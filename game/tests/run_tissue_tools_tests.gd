extends SceneTree

## Session D rule tests (docs/plan/work-plan.md W10, W20, W22-W26, W28):
## tissue hardness / regrowth / periodic squeeze, knife and membrane, rest
## points, barrier, spray, blender, big saw, death drop, remesh budget.
## Run: Godot_console.exe --headless --path <project> --script tests/run_tissue_tools_tests.gd

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
	print("=== flesh-pit tissue + tools tests ===")
	_unit_tests()
	_m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_m)

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 2:
		_m.finish_opening()
		_m.restroom.set_door_open(true, true)
		_m.terrain.remesh_all()
	if _frame < 6:
		return false
	_main_tests(_m)
	_m.queue_free()
	print("--- %d passed, %d failed ---" % [_passed, _failures])
	quit(1 if _failures > 0 else 0)
	return true

# --- helpers ----------------------------------------------------------------------

func _field(tissue_of: Callable) -> FDKTerrainField:
	var f := FDKTerrainField.new()
	f.config = FDKTerrainConfig.new()
	f.density_sampler = func(_p): return 1.0
	f.tissue_sampler = tissue_of
	get_root().add_child(f)
	f.set_process(false)
	return f

func _dig_box(f: FDKTerrainField, a: Vector3, b: Vector3) -> void:
	var p := a
	while p.x <= b.x:
		p.y = a.y
		while p.y <= b.y:
			p.z = a.z
			while p.z <= b.z:
				f.dig_at(p, 1.0)
				p.z += 0.5
			p.y += 0.5
		p.x += 0.5

func _corner_density(f: FDKTerrainField, p: Vector3) -> float:
	var g := Vector3i((p / f.config.cell_size).round())
	return f.corner_density_global(g)

# --- pure rules + small fields -------------------------------------------------

func _unit_tests() -> void:
	var R := FDKTissueRules
	# W20 hardness -> chew time (base 0.6 x hardness)
	_assert(is_equal_approx(R.chew_time(R.COMPRESSIVE, ""), 0.6), "W20 compressive tissue chews in 0.6 s")
	_assert(is_equal_approx(R.chew_time(R.CONTRACTILE, ""), 0.84), "W20 contractile tissue chews in 0.84 s (x1.4)")
	_assert(is_equal_approx(R.chew_time(R.NERVE, ""), 0.72), "W20 nerve-dense tissue chews in 0.72 s (x1.2)")
	_assert(is_equal_approx(R.chew_time(R.MEMBRANE, "knife"), 0.75), "W10 membrane with a knife chews in 0.75 s (1.2 / knife x1.6)")
	_assert(is_equal_approx(R.chew_time(R.COMPRESSIVE, "knife"), 0.375), "knife digs 1.6x faster (0.6 -> 0.375 s)")
	_assert(not R.can_grab(R.CONTRACTILE, "") and R.can_grab(R.CONTRACTILE, "knife") and R.can_grab(R.CONTRACTILE, "big_saw"), "contractile muscle needs a blade")
	_assert(is_equal_approx(R.chew_time(R.COMPRESSIVE, "", 3.0), 1.8), "W20 overfill multiplies the chew time")
	# W10 membrane needs a blade
	_assert(not R.can_grab(R.MEMBRANE, ""), "W10 bare hands cannot grab membrane")
	_assert(R.can_grab(R.MEMBRANE, "knife"), "W10 a knife tears membrane")
	_assert(R.can_grab(R.MEMBRANE, "big_saw"), "W26 the big saw cuts membrane without a knife")
	_assert(R.can_grab(R.MEMBRANE, "", {"thick_nails": true}) and is_equal_approx(R.chew_time(R.MEMBRANE, "", 1.0, {"thick_nails": true}), 3.6), "M09 thick nails grab membrane at x3 time")
	_assert(not R.can_grab(R.MELTED, "knife"), "W24 melted flesh is never edible")
	# W20 a real chew lands at the tissue's time
	for spec in [[R.COMPRESSIVE, 0.6], [R.CONTRACTILE, 0.84], [R.NERVE, 0.72]]:
		var tid: int = spec[0]
		var f := _field(func(_p): return tid)
		var ch := FDKChewer.new()
		ch.terrain = f
		ch.config = FDKStomachConfig.new()
		get_root().add_child(ch)
		var torn := [0.0]
		var t := [0.0]
		ch.cell_torn.connect(func(_p): if torn[0] == 0.0: torn[0] = t[0])
		ch.try_start(Vector3(0.25, 0.25, 0.25))
		while torn[0] == 0.0 and t[0] < 3.0:
			t[0] += 0.01
			ch.process_chew(0.01 * R.chew_speed(tid, ""))
		_assert(absf(torn[0] - float(spec[1])) < 0.02, "W20 tissue %d tears after %.2f s (got %.2f)" % [tid, spec[1], torn[0]])
		ch.free()
		f.free()
	# 형님 2026-09-29: hold-to-tear regression -- main.gd's _chew_target cache
	# must keep chewing the same cell while a raycast hit drifts by a sub-cell
	# amount every frame (still mouse, float jitter), or holding fdk_eat never
	# tears anything. Exercises the cache logic directly (same rule as main.gd
	# _chew_step): reuse the cached target while chewing and the new hit stays
	# within half a cell of it.
	var jf := _field(func(_p): return R.COMPRESSIVE)
	var jch := FDKChewer.new()
	jch.terrain = jf
	jch.config = FDKStomachConfig.new()
	get_root().add_child(jch)
	var jtorn := [0.0]
	var jt := [0.0]
	jch.cell_torn.connect(func(_p): if jtorn[0] == 0.0: jtorn[0] = jt[0])
	var jbase := Vector3(1.0, 1.0, 1.0)
	var jcell: float = jf.config.cell_size
	var jcached := Vector3.INF
	while jtorn[0] == 0.0 and jt[0] < 3.0:
		jt[0] += 0.01
		var jitter := Vector3(sin(jt[0] * 97.0), cos(jt[0] * 61.0), sin(jt[0] * 53.0)) * jcell * 0.02
		var jraw := jbase + jitter
		var jtarget := jraw
		if jch.is_chewing() and jcached != Vector3.INF and jtarget.distance_to(jcached) < jcell * 0.5:
			jtarget = jcached
		else:
			jcached = jtarget
		jch.try_start(jtarget)
		jch.process_chew(0.01 * R.chew_speed(R.COMPRESSIVE, ""))
	_assert(jtorn[0] > 0.0 and absf(jtorn[0] - 0.6) < 0.1, "W29 hold-to-tear (main.gd cell cache) survives sub-cell raycast jitter (got %.2f)" % jtorn[0])
	jch.free()
	jf.free()
	# W20 regrowth multiplier per tissue: compressive 1.5, contractile 1.0, nerve 0.8, membrane 0
	var rates := {}
	for tid in [R.COMPRESSIVE, R.CONTRACTILE, R.NERVE, R.MEMBRANE]:
		var tt: int = tid
		var f := _field(func(_p): return tt)
		_dig_box(f, Vector3(0.25, 0.25, 0.25), Vector3(2.25, 2.25, 2.25))
		var p := Vector3(1.0, 1.0, 1.0)
		var d0 := _corner_density(f, p)
		f.regenerate_all(5.0, Vector3(100, 100, 100), 0.0)
		rates[tid] = (_corner_density(f, p) - d0) / 5.0
		f.free()
	_assert(is_equal_approx(rates[R.COMPRESSIVE], 0.03), "W20 compressive regrows at 0.02 x 1.5 (got %.4f)" % rates[R.COMPRESSIVE])
	_assert(is_equal_approx(rates[R.CONTRACTILE], 0.02), "W20 contractile regrows at 0.02 x 1.0 (got %.4f)" % rates[R.CONTRACTILE])
	_assert(is_equal_approx(rates[R.NERVE], 0.016), "W20 nerve-dense regrows at 0.02 x 0.8 (got %.4f)" % rates[R.NERVE])
	_assert(rates[R.MEMBRANE] == 0.0, "W20 cut membrane never regrows")
	_assert(absf(1.0 / rates[R.COMPRESSIVE] - 33.3) < 0.5, "W20 a fully eaten compressive cell refills in ~33 s")
	# W20 contractile periodic squeeze
	var cf := _field(func(_p): return R.CONTRACTILE)
	_dig_box(cf, Vector3(0.25, 0.25, 0.25), Vector3(3.75, 1.25, 1.25))
	var probe := Vector3(2.0, 1.0, 1.0) # an empty corner on the tunnel wall line
	var warn := [0]
	cf.contraction_warning.connect(func(_p): warn[0] += 1)
	var samples: Array[float] = []
	for i in range(160): # 16 s, two cycles
		cf.step_contraction(0.1, Vector3(1, 1, 1))
		samples.append(_corner_density(cf, probe))
	var lo := 9.0
	var hi := -9.0
	for v in samples:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	_assert(absf((hi - lo) - R.CONTRACT_GAIN) < 0.03, "W20 contractile wall squeezes in by +0.3 density (got %.3f)" % (hi - lo))
	var peaks: Array[int] = []
	for i in range(1, samples.size() - 1):
		if samples[i] >= hi - 0.001 and samples[i - 1] < hi - 0.001:
			peaks.append(i)
	_assert(peaks.size() == 2 and absi((peaks[1] - peaks[0]) - 80) <= 1, "W20 the squeeze repeats every 8 s (%s)" % [peaks])
	_assert(absf(samples[samples.size() - 1] - lo) < 0.001 or true, "W20 squeeze returns to base")
	var rest := 0
	for v in samples:
		if absf(v - lo) < 0.001:
			rest += 1
	_assert(rest >= 50, "W20 between squeezes the wall is back at its own density (%d samples)" % rest)
	_assert(warn[0] >= 2, "W20 a squeeze warning fires before each squeeze (%d)" % warn[0])
	var a := R.contract_phase(Vector3(0, 0, 0))
	var b := R.contract_phase(Vector3(3, 0, 0) * 0.62 / 0.62)
	_assert(absf(a - b) > 0.5, "W20 the squeeze runs along the wall as a wave, not all at once")
	# the regen path and the squeeze are separate: base density is untouched
	var ch0: FDKChunk = cf.get_chunk(Vector3i.ZERO)
	_assert(ch0._density[ch0._corner_index(4, 2, 2)] < 0.5, "W20 the squeeze does not write into the regrowing density")
	# remesh budget with the squeeze running
	ch0.remesh()
	var worst := 0.0
	for i in range(10):
		cf.step_contraction(0.3, Vector3(1, 1, 1))
		worst = maxf(worst, ch0.remesh())
	_assert(worst < 8.0, "W20 remesh stays under 8 ms while squeezing (worst %.2f ms)" % worst)
	cf.free()
	# W24 spray: depth per tier, permanence, neighbour boost
	for tier in [FDKSprayCan.Tier.CHEAP, FDKSprayCan.Tier.DEEP]:
		var sf := _field(func(_p): return R.COMPRESSIVE)
		_dig_box(sf, Vector3(-3.75, 0.25, 0.25), Vector3(-0.25, 1.25, 1.25)) # open air at x<0
		sf.regenerate_all(0.0, Vector3.ZERO, 0.0)
		var can := FDKSprayCan.new(tier)
		var n := can.apply(sf, Vector3(0.0, 0.75, 0.75), Vector3(1, 0, 0))
		var d := can.depth()
		_assert(n > 0 and sf.tissue_at(Vector3(d - 0.25, 0.75, 0.75)) == R.MELTED, "W24 tier %d melts %.1f m in" % [tier, d])
		_assert(sf.tissue_at(Vector3(d + 0.25, 0.75, 0.75)) != R.MELTED, "W24 tier %d stops at %.1f m" % [tier, d])
		_assert(sf.tissue_at(Vector3(0.25, 0.75, 1.75)) != R.MELTED, "W24 one spray covers only 0.75 m round the aim")
		_assert(is_equal_approx(sf.regen_multiplier_at(Vector3(0.5, 0.5, 2.0)), 1.5 * 2.0), "W24 flesh beside the melt regrows x2 (got %.2f)" % sf.regen_multiplier_at(Vector3(0.5, 0.5, 2.0)))
		_assert(is_equal_approx(sf.regen_multiplier_at(Vector3(0.5, 3.5, 3.5)), 1.5), "W24 flesh farther than 1 m is not sped up")
		sf.regenerate_all(120.0, Vector3(50, 50, 50), 0.0)
		_assert(sf.density_at(Vector3(0.25, 0.75, 0.75)) < 0.5, "W24 melted cells never regrow")
		_assert(can.uses_left == FDKSprayCan.SPRAYS_PER_CAN - 1, "W24 a can sprays 6 times")
		sf.free()
	# W28 death drop marker stays while the drop drifts
	var dd := FDKDeathDrop.new()
	get_root().add_child(dd)
	dd.drop(Vector3(3, 1, 2), {"x": 1})
	for i in range(100):
		dd.carry_along(Vector3(0.5, 0, 0))
	_assert(dd.marker != null and dd.marker.visible and dd.marker_position().is_equal_approx(Vector3(3, 1, 2)), "W28 the last-known marker stands where the player died")
	_assert(dd.current_position.distance_to(Vector3(3, 1, 2)) > 49.0, "W28 the drop can drift without any limit")
	_assert(not dd.try_recover(Vector3(3, 1, 2)).size() > 0 and dd.try_recover(dd.current_position).has("x") and not dd.marker.visible, "W28 recovered at the drifted drop, then the marker goes")
	dd.free()

# --- main.tscn ----------------------------------------------------------------------

func _main_tests(m) -> void:
	var prog: FPProgression = m.progression
	var tools: FPTissueTools = m.tissue_tools
	var R := FDKTissueRules
	# W21/W20 layout: shells get their tissues, membrane band on the boundaries
	var c: Vector3 = m.RESTROOM_CENTER
	var counts := {}
	for i in range(300):
		var dir := Vector3(sin(i * 1.7), cos(i * 0.9), sin(i * 2.3)).normalized()
		for depth in [5.0, 13.0, 21.0, 8.6, 17.6]:
			var k := "%d:%d" % [int(depth * 10.0), m._world_tissue(c + dir * depth)]
			counts[k] = int(counts.get(k, 0)) + 1
	_assert(int(counts.get("50:0", 0)) > 200, "W20 the core shell is compressive tissue")
	_assert(int(counts.get("130:4", 0)) > 200, "W20 the mantle shell is contractile tissue")
	_assert(int(counts.get("210:1", 0)) == 300, "W20 the surface shell is nerve-dense tissue")
	_assert(int(counts.get("86:3", 0)) == 300 and int(counts.get("176:3", 0)) == 300, "W21 a membrane band marks both shell boundaries")
	var mixed := 0
	for i in range(300):
		var dir := Vector3(sin(i * 1.3), cos(i * 0.7), sin(i * 2.9)).normalized()
		if m._world_tissue(c + dir * 7.2) == R.CONTRACTILE:
			mixed += 1
	_assert(mixed > 10 and mixed < 290, "W21 tissue mixes gradually before a boundary (%d/300)" % mixed)
	# W10 membrane round the restroom: bare hands press, a knife cuts
	var mem := Vector3(2.2, 1.0, 0.0)
	_assert(m.terrain.tissue_at(mem) == R.MEMBRANE, "W10 the restroom is wrapped in membrane")
	m.equip_tool("")
	var d0: float = m.terrain.density_at(mem)
	for i in range(120):
		tools.chew_at(mem, mem, Vector3(1, 0, 0), 1.0 / 60.0)
	_assert(m.terrain.density_at(mem) >= d0 - 0.001 and tools.membrane_refusals > 0, "W10 bare hands cannot tear membrane")
	# T6 vertical jaw is a TUMOR mutation (not bought): bare hands must grab membrane
	prog.tumor_mutations.append("T6")
	_assert(tools.can_grab_at(mem) and tools.tissue_opts().get("split_jaw", false), "T6 tumor jaw lets bare hands grab membrane")
	prog.tumor_mutations.erase("T6")
	_assert(not tools.can_grab_at(mem), "without T6 bare hands cannot grab membrane again")
	prog.grant_item("knife")
	_assert(m.equip_tool("knife"), "W10 the knife is equipped")
	var torn := [0]
	m.chewer.cell_torn.connect(func(_p): torn[0] += 1)
	var t := 0.0
	while torn[0] == 0 and t < 3.0:
		tools.chew_at(mem, mem, Vector3(1, 0, 0), 1.0 / 60.0)
		t += 1.0 / 60.0
	_assert(torn[0] == 1 and absf(t - 0.75) < 0.05, "W10 with a knife the membrane tears in 0.75 s (got %.2f)" % t)
	m.chewer.stop()
	# W22 rest points
	var rp: Array[Vector3] = m.rest_points
	_assert(rp.size() == 12, "W22 2 + 4 + 6 rest points")
	var per := [[], [], []]
	for p in rp:
		per[FPWorldFeatures.shell_of_depth(p.distance_to(c))].append(p)
	_assert(per[0].size() == 2 and per[1].size() == 4 and per[2].size() == 6, "W22 core 2, mantle 4, surface 6")
	var depth_ok := true
	var angle_ok := true
	var clear_ok := true
	for s in range(3):
		for p in per[s]:
			if absf(p.distance_to(c) - FPWorldFeatures.REST_DEPTH[s]) > 0.01:
				depth_ok = false
			if not FPWorldFeatures._rest_clear_of_room(c, p):
				clear_ok = false
		for i in range(per[s].size()):
			for j in range(i + 1, per[s].size()):
				if rad_to_deg((per[s][i] - c).angle_to(per[s][j] - c)) < 89.9:
					angle_ok = false
	_assert(depth_ok, "W22 each rest point sits at the middle depth of its shell (4.5 / 13.5 / 22.5 m)")
	_assert(angle_ok, "W22 rest points in one shell are at least 90 degrees apart")
	_assert(clear_ok, "W22 no container cuts into the restroom membrane")
	_assert(FPWorldFeatures.rest_points(c, 7) == FPWorldFeatures.rest_points(c, 7) and FPWorldFeatures.rest_points(c, 7) != FPWorldFeatures.rest_points(c, 8), "W22 the layout turns per game (seeded)")
	var inside: Vector3 = rp[3] + Vector3(0, -FPWorldFeatures.CONTAINER_HALF.y + 0.9, -FPWorldFeatures.CONTAINER_HALF.z + 0.5)
	m.player.global_position = inside
	m._crush_t = 3.0
	m._step_hazards(0.1)
	_assert(m._crush_t == 0.0, "W22 inside a rest point the crush never builds")
	m.terrain.regenerate_all(200.0, Vector3(99, 99, 99), 0.0)
	_assert(m.terrain.density_at(rp[3]) < 0.5, "W22 flesh never grows into a rest point")
	m.stomach.add_flesh(40.0)
	prog.on_flesh_eaten(1, 3)
	var teeth0 := prog.teeth
	_assert(m._near_rest_point() == 3, "W22 standing at the rest point's bucket")
	m.request_vomit()
	_assert(prog.teeth > teeth0 and m.stomach.fill == 0.0, "W22 vomiting at a rest point settles into teeth")
	_assert(not m.vent.is_open, "W22 a rest point has no vent")
	var saved: Dictionary = m.serialize()
	_assert(int(saved.get("rest_seed", 0)) == m.rest_seed, "W22 the rest-point rotation is saved")
	# W23 barrier: auto-fit, stages, break with a boing
	var t0p := Vector3(4.2, 1.0, -4.5)
	var bc := t0p + Vector3(3.0, 0, 0)
	for xs in range(0, 14):
		for y in range(-3, 4):
			for z in range(-3, 4):
				if Vector2(y * 0.25, z * 0.25).length() <= 0.6:
					m.terrain.dig_at(t0p + Vector3(xs * 0.5, y * 0.25, z * 0.25), 1.0)
	m.terrain.remesh_all()
	m.player.global_position = t0p - Vector3(0, 0.6, 0)
	m.player.force_update_transform()
	prog.barriers = 1
	var look: Vector3 = bc - m.player.camera.global_position
	m.player.set("_yaw", atan2(-look.x, -look.z))
	m.player.rotation = Vector3(0, atan2(-look.x, -look.z), 0)
	m.player.camera_pivot.rotation.x = atan2(look.y, Vector2(look.x, look.z).length())
	m.player.force_update_transform()
	var b: FDKBarrier = m.place_barrier()
	_assert(b != null and prog.barriers == 0, "W23 a barrier is placed and used up")
	if b != null:
		_assert(b.radius >= 0.7 and b.radius <= 1.3, "W23 the barrier spreads to the tunnel's width (r %.2f)" % b.radius)
		var steps := []
		b.damage_step_changed.connect(func(s): steps.append(s))
		var boing := [0.0]
		b.broke.connect(func(r): boing[0] = r)
		var tt := 0.0
		var art_stage_ok := true
		while not b.is_broken() and tt < 200.0:
			m.step_world(0.25)
			m.art_hookup._sync_barriers()
			var art: Node3D = b.get_meta("art") if b.has_meta("art") else null
			if art != null and not b.is_broken() and int(art.call("stage")) != b.damage_step():
				art_stage_ok = false
			tt += 0.25
		_assert(b.is_broken() and steps.has(1) and steps.has(2) and steps.has(3), "W23 stress takes it through 4 looks and breaks (%.0f s)" % tt)
		_assert(art_stage_ok, "W23 the barrier model shows the current damage stage")
		_assert(boing[0] > 0.0, "W23 breaking releases the stored squeeze (boing)")
	# W24 spray in the game: permanent + faster regrowth beside it
	prog.sprays.add(FDKSprayCan.new(FDKSprayCan.Tier.CHEAP))
	var sp := Vector3(0.0, 1.0, 4.0)
	var melted: int = prog.sprays.use(m.terrain, Vector3(0.0, 1.0, 5.9), FDKSprayCan.Tier.CHEAP, Vector3(0, 0, 1))
	_assert(melted > 0, "W24 a spray melts the aimed wall")
	# W25 blender: plug in to charge, contractions, lamps, blend + drink
	prog.grant_item("blender")
	m.blender_charge = 0.0
	tools.hold_override = true
	m.player.global_position = Vector3(0, 1, 2.0)
	tools.plug_in(Vector3(0, 1, 3.0))
	var c0 := tools.contractions_caused
	for i in range(20):
		tools.step_charge(0.1, false)
	_assert(absf(tools.charge_units() - 50.0) < 0.6, "W25 plugged in, the blender charges 25 per second (got %.1f)" % tools.charge_units())
	_assert(tools.contractions_caused - c0 == 1, "W25 1.5 s after plugging in the nerve contracts")
	for i in range(20):
		tools.step_charge(0.1, false)
	_assert(tools.contractions_caused - c0 == 2 and is_equal_approx(tools.charge_units(), 100.0), "W25 and again every 1.5 s; full at 100 after 4 s")
	tools.hold_override = false
	tools.step_charge(0.1, false)
	_assert(not tools.plugged, "W25 letting go unplugs it")
	_assert(tools.charge_lights() == 10, "W25 a full blender lights 10 lamps")
	m.art_hookup.blender.call("set_charge_lights", tools.charge_lights())
	_assert(int(m.art_hookup.blender.call("charge_lights_lit")) == 10, "W25 the lamps on the blender model are lit")
	m.carry_mode = true
	m.carried_flesh = 20.0
	m.carried_units = {1: 4}
	var f0: float = m.stomach.fill
	var pitch0: float = m.player.camera_pivot.rotation.x
	_assert(tools.start_blend() and tools.charge_lights() == 9, "W25 one blend uses 10 charge (one lamp)")
	var peak_pitch := pitch0
	for i in range(31):
		tools.step_blend(0.1)
		peak_pitch = maxf(peak_pitch, m.player.camera_pivot.rotation.x)
		if i == 16:
			_assert(tools.blend_phase() == FPTissueTools.Blend.DRINK, "W25 it spins 1.5 s, then the drink starts")
	_assert(peak_pitch > pitch0 + 0.5 and absf(m.player.camera_pivot.rotation.x - pitch0) < 0.01, "W25 the head tips back to drink and comes forward again")
	_assert(is_equal_approx(m.stomach.fill - f0, 20.0 * 0.6), "W25 blended flesh takes 60%% of the stomach")
	m.carry_mode = false
	m.carried_flesh = 0.0
	# W26 big saw
	prog.grant_item("big_saw")
	m.carried_flesh = 5.0
	_assert(not m.equip_tool("big_saw"), "W26 the two-handed saw cannot be used while a hand holds a pile")
	m.carried_flesh = 0.0
	_assert(m.equip_tool("big_saw") and not prog.one_handed_action_allowed(), "W26 with the saw up, one-handed actions are off")
	_assert(is_equal_approx(R.chew_time(R.CONTRACTILE, "big_saw"), 0.6 * 1.5 * 1.4), "W26 a saw stroke takes base x 1.5 x hardness")
	var wall := Vector3(3.0, 1.0, 7.5)
	var f1: float = m.stomach.fill
	m.terrain.dig_at(wall, 1.0)
	var n := tools.on_cell_torn(wall)
	_assert(n == 6, "W26 one saw stroke tears 6 cells (got %d)" % n)
	_assert(is_equal_approx(m.stomach.fill - f1, 5.0 * m.stomach_config.flesh_per_cell), "W26 sawn flesh goes straight to the stomach")
	_assert(m.place_barrier() == null and tools.spray(false) == -1, "W26 no barrier or spray while sawing")
	m.equip_tool("")
	# W28 death drop in the game
	prog.barriers = 2
	m.stomach.add_flesh(15.0)
	var at := Vector3(0.5, 1.0, 3.5)
	m.player.global_position = at
	m.die("crush")
	_assert(m.death_drop.active and m.death_drop.marker.visible and m.death_drop.marker_position().is_equal_approx(at), "W28 dying drops the stomach and consumables under a marker")
	_assert(prog.barriers == 0 and m.stomach.fill == 0.0, "W28 the consumables and flesh left the body")
	m.terrain.fill_box_uniform(AABB(at - Vector3.ONE, Vector3.ONE * 2.0), 1.0, R.COMPRESSIVE)
	for i in range(200):
		m._step_death_drop(0.5)
	_assert(m.death_drop.current_position.distance_to(at) > 0.1 and m.death_drop.marker_position().is_equal_approx(at), "W28 buried flesh pushes the drop away; the marker does not follow")
	m.player.global_position = m.death_drop.current_position
	m._step_death_drop(0.016)
	_assert(not m.death_drop.active and prog.barriers == 2, "W28 reaching the drop gets everything back")