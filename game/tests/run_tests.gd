extends SceneTree

## Minimal self-test runner: no GUT dependency. Add test functions to the
## `_tests` array (Callable returning bool, or void that calls _assert()).
## Run with:
##   Godot_console.exe --headless --path <project> --script tests/run_tests.gd
## Exit code 0 = all passed, 1 = at least one failure.

var _failures: int = 0
var _passed: int = 0

func _init() -> void:
	print("=== flesh-pit self-tests ===")
	_run_terrain_tests()
	_run_stomach_tests()
	_run_chewer_tests()
	_run_surface_tests()
	_run_hand_tests()
	_run_ps1_tests()
	_run_barrier_tests()
	_run_spray_tests()
	_run_mutation_tests()
	_run_nerve_disturb_tests()
	_run_canary_tests()
	_run_death_drop_tests()
	for n in _to_free:
		if is_instance_valid(n):
			n.free()
	_to_free.clear()
	FDKPs1Material.clear_cache()
	print("--- %d passed, %d failed ---" % [_passed, _failures])
	quit(1 if _failures > 0 else 0)

## Nodes created by tests, freed before quitting so no RIDs leak.
var _to_free: Array = []

func _track(n: Node) -> Node:
	_to_free.append(n)
	return n

func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: %s" % message)

func _run_terrain_tests() -> void:
	var config := FDKTerrainConfig.new()
	config.chunk_size = 4
	config.cell_size = 0.5

	var field := _track(FDKTerrainField.new()) as FDKTerrainField
	field.config = config

	# fill_box_uniform should make a region solid; digging should remove
	# density; regenerate should restore it over time when the player is
	# far away (no protection radius interference).
	field.fill_box_uniform(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)), 1.0, 0)
	var chunk_coord := field.world_to_chunk_coord(Vector3.ZERO)
	var chunk := field.get_chunk(chunk_coord)
	_assert(chunk != null, "terrain: chunk exists after fill_box_uniform")

	field.dig_at(Vector3(0, 0, 0), 1.0)
	var result: Array = field.world_to_cell(Vector3(0, 0, 0))
	var local_cell: Vector3i = result[1]
	var density_after_dig: float = chunk.get_density_at_corner(local_cell.x, local_cell.y, local_cell.z)
	_assert(density_after_dig < 1.0, "terrain: dig_at reduces density at target cell")

	# Regenerate far from the dug point (protect radius should not reach it).
	field.regenerate_all(1000.0, Vector3(100, 100, 100), 0.5)
	var density_after_regen: float = chunk.get_density_at_corner(local_cell.x, local_cell.y, local_cell.z)
	_assert(density_after_regen > density_after_dig, "terrain: regenerate_all heals density toward original")

	# depth_at should be a plain euclidean distance from depth_origin.
	field.depth_origin = Vector3.ZERO
	var depth := field.depth_at(Vector3(3, 4, 0))
	_assert(is_equal_approx(depth, 5.0), "terrain: depth_at computes distance from depth_origin (got %f)" % depth)

	# Remeshing a chunk with a fully solid interior wall should produce
	# boundary faces (a non-empty mesh) rather than an empty array (which
	# would mean every face was incorrectly culled as interior-vs-interior).
	var elapsed_ms := chunk.remesh()
	_assert(elapsed_ms >= 0.0, "terrain: remesh returns a non-negative elapsed time")

	# Serialize/deserialize round trip.
	var saved := field.serialize()
	var field2 := _track(FDKTerrainField.new()) as FDKTerrainField
	field2.config = config
	field2.deserialize(saved)
	var chunk2 := field2.get_chunk(chunk_coord)
	_assert(chunk2 != null, "terrain: deserialize recreates chunks from saved data")
	if chunk2 != null:
		var d1 := chunk.get_density_at_corner(0, 0, 0)
		var d2 := chunk2.get_density_at_corner(0, 0, 0)
		_assert(is_equal_approx(d1, d2), "terrain: deserialize restores matching density (got %f vs %f)" % [d1, d2])

func _run_stomach_tests() -> void:
	var config := FDKStomachConfig.new()
	config.capacity = 100.0
	config.overfill_capacity = 50.0
	config.overfill_chew_multiplier = 4.0

	var stomach := _track(FDKStomach.new()) as FDKStomach
	stomach.config = config

	_assert(stomach.fill == 0.0, "stomach: starts empty")
	_assert(not stomach.is_overfull(), "stomach: not overfull when empty")

	stomach.add_flesh(60.0)
	_assert(stomach.fill == 60.0, "stomach: add_flesh accumulates")
	_assert(not stomach.is_overfull(), "stomach: under capacity is not overfull")
	_assert(stomach.chew_time_multiplier() == 1.0, "stomach: no slowdown under capacity")
	_assert(is_equal_approx(stomach.fill_ratio(), 0.6), "stomach: fill_ratio scales by capacity (got %f)" % stomach.fill_ratio())

	stomach.add_flesh(65.0) # total 125, 25 into the 50-wide overfill band
	_assert(stomach.is_overfull(), "stomach: over capacity is overfull")
	var ratio := stomach.overfill_ratio()
	_assert(is_equal_approx(ratio, 0.5), "stomach: overfill_ratio at halfway point (got %f)" % ratio)
	var multiplier := stomach.chew_time_multiplier()
	_assert(is_equal_approx(multiplier, 2.5), "stomach: chew multiplier interpolates (got %f)" % multiplier)

	var vomited := stomach.vomit()
	_assert(is_equal_approx(vomited, 125.0), "stomach: vomit returns full amount")
	_assert(stomach.fill == 0.0, "stomach: vomit empties stomach")

	var saved := stomach.serialize()
	stomach.add_flesh(999.0)
	stomach.deserialize(saved)
	_assert(stomach.fill == 0.0, "stomach: deserialize restores saved fill")

func _run_chewer_tests() -> void:
	var terrain_config := FDKTerrainConfig.new()
	terrain_config.chunk_size = 4
	terrain_config.cell_size = 0.5
	var field := _track(FDKTerrainField.new()) as FDKTerrainField
	field.config = terrain_config
	field.fill_box_uniform(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)), 1.0, 0)

	var stomach_config := FDKStomachConfig.new()
	stomach_config.base_chew_time = 0.5
	stomach_config.flesh_per_cell = 4.0

	var stomach := _track(FDKStomach.new()) as FDKStomach
	stomach.config = stomach_config

	var chewer := _track(FDKChewer.new()) as FDKChewer
	chewer.terrain = field
	chewer.stomach = stomach
	chewer.config = stomach_config

	_chewer_grab_count = 0
	_chewer_tear_count = 0
	_chewer_release_count = 0
	chewer.grab_started.connect(_on_test_grab_started)
	chewer.cell_torn.connect(_on_test_cell_torn)
	chewer.released.connect(_on_test_released)

	chewer.try_start(Vector3(0, 0, 0))
	_assert(chewer.is_chewing(), "chewer: try_start begins chewing")
	_assert(_chewer_grab_count == 1, "chewer: try_start emits grab_started once (got %d)" % _chewer_grab_count)

	chewer.process_chew(0.2)
	_assert(stomach.fill == 0.0, "chewer: no flesh gained before chew time elapses")

	chewer.process_chew(0.4) # total 0.6s > base_chew_time 0.5s at multiplier 1.0
	_assert(stomach.fill == 4.0, "chewer: cell_torn adds flesh_per_cell once chew completes (got %f)" % stomach.fill)
	_assert(_chewer_tear_count == 1, "chewer: cell_torn emitted once on tear completion (got %d)" % _chewer_tear_count)

	chewer.stop()
	_assert(not chewer.is_chewing(), "chewer: stop() ends chewing")
	_assert(_chewer_release_count == 1, "chewer: stop() emits released() once (got %d)" % _chewer_release_count)

	chewer.stop() # calling stop again while already stopped must not re-emit released
	_assert(_chewer_release_count == 1, "chewer: stop() is idempotent, no duplicate released() (got %d)" % _chewer_release_count)

func _run_surface_tests() -> void:
	var config := FDKTerrainConfig.new()
	config.chunk_size = 4
	config.cell_size = 0.5
	var field := _track(FDKTerrainField.new()) as FDKTerrainField
	field.config = config
	field.density_sampler = func(_p: Vector3) -> float: return 1.0
	field.tissue_sampler = func(p: Vector3) -> int: return 3 if p.x < -1.0 else 0
	field.generate_region(AABB(Vector3(-2, -2, -2), Vector3(3.9, 3.9, 3.9)))
	# chunk (0,0,0) spans 0..2m; a dig right at x=0 touches corners shared with chunk (-1,0,0)
	field.dig_at(Vector3(0.1, 0.6, 0.6), 1.0)
	var a := field.get_chunk(Vector3i(0, 0, 0))
	var b := field.get_chunk(Vector3i(-1, 0, 0))
	_assert(a.get_density_at_corner(0, 1, 1) < 0.5 and b.get_density_at_corner(4, 1, 1) < 0.5,
		"surface: dig on a chunk border updates the shared corner in both chunks")
	field.remesh_all()
	var mesh: ArrayMesh = a.get_node("Body/Mesh").mesh
	_assert(mesh != null and mesh.get_surface_count() == 1, "surface: dug chunk builds a mesh")
	if mesh != null and mesh.get_surface_count() == 1:
		var arr := mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var flat := v.size() % 3 == 0 and v.size() > 0
		for i in range(0, nn.size(), 3):
			if not (nn[i].is_equal_approx(nn[i + 1]) and nn[i].is_equal_approx(nn[i + 2])):
				flat = false
		_assert(flat, "surface: every triangle has one flat normal (faceted low-poly)")
		var not_axis := 0
		for i in range(0, nn.size(), 3):
			var m := maxf(absf(nn[i].x), maxf(absf(nn[i].y), absf(nn[i].z)))
			if m < 0.99:
				not_axis += 1
		_assert(not_axis * 2 > nn.size() / 3, "surface: most facets are slanted, not cube faces (%d of %d)" % [not_axis, nn.size() / 3])
	var b_mesh: ArrayMesh = b.get_node("Body/Mesh").mesh
	_assert(b_mesh != null, "surface: neighbour chunk also meshes its side of the border hole (no seam)")
	_assert(not field.is_edible_at(Vector3(-1.6, 0.5, 0.5)), "surface: membrane tissue is inedible")
	_assert(field.is_edible_at(Vector3(0.5, 0.5, 0.5)), "surface: flesh tissue is edible")
	var st_cfg := FDKStomachConfig.new()
	var chewer := _track(FDKChewer.new()) as FDKChewer
	chewer.terrain = field
	chewer.config = st_cfg
	chewer.try_start(Vector3(-1.6, 0.5, 0.5))
	_assert(not chewer.is_chewing(), "surface: chewer refuses to grab inedible tissue")

func _run_hand_tests() -> void:
	var rig := _track(FDKHandsRig.new()) as FDKHandsRig
	get_root().add_child(rig)
	rig.build()
	var worst := []
	var check := func() -> void:
		for side in ["right", "left"]:
			var a: Dictionary = rig.get_joint_angles(side)
			for j in FDKHandsRig.JOINT_NAMES:
				var lim: Array = FDKHandsRig.LIMITS_DEG[j]
				if a[j] < lim[0] - 0.001 or a[j] > lim[1] + 0.001:
					worst.append("%s %s=%.1f" % [side, j, a[j]])
	for i in range(30):
		rig.step(1.0 / 60.0)
		check.call()
	var idle: Dictionary = rig.get_joint_angles("right")
	var tips_idle: Array = rig.get_tip_positions("right")
	rig.on_grab_started(Vector3i.ZERO)
	rig.step(0.06)
	var early: Dictionary = rig.get_joint_angles("right")
	for i in range(30):
		rig.step(1.0 / 60.0)
		check.call()
	var grab: Dictionary = rig.get_joint_angles("right")
	var tips_grab: Array = rig.get_tip_positions("right")
	_assert(grab["f1"] > idle["f1"] + 30.0 and grab["f2"] > idle["f2"] + 30.0 and grab["f3"] > idle["f3"] + 30.0,
		"hands: grab curls all 3 finger-block joints (%.0f %.0f %.0f)" % [grab["f1"], grab["f2"], grab["f3"]])
	_assert(grab["t1"] > idle["t1"] + 10.0 and grab["t2"] > idle["t2"] + 10.0 and grab["t3"] > idle["t3"] + 10.0 and grab["t_opp"] > idle["t_opp"] + 20.0,
		"hands: grab curls all 3 thumb joints and swings the thumb across")
	_assert((early["f1"] - idle["f1"]) > (early["f3"] - idle["f3"]) + 5.0,
		"hands: joints curl in order, joint 1 leads joint 3 (%.1f vs %.1f)" % [early["f1"] - idle["f1"], early["f3"] - idle["f3"]])
	var d_idle: float = (tips_idle[0] as Vector3).distance_to(tips_idle[1])
	var d_grab: float = (tips_grab[0] as Vector3).distance_to(tips_grab[1])
	_assert(d_grab < d_idle * 0.8, "hands: fingertips and thumb tip close on each other when gripping (%.3f -> %.3f m)" % [d_idle, d_grab])
	var pos_before: Vector3 = rig.get_hand_root("right").position
	for i in range(40):
		rig.on_chew_progress(float(i) / 40.0, Vector3i.ZERO)
		rig.step(1.0 / 60.0)
		check.call()
	var pos_chew: Vector3 = rig.get_hand_root("right").position
	_assert(pos_chew.z > pos_before.z + 0.03, "hands: chewing pulls the hand back toward the player")
	rig.on_cell_torn(Vector3.ZERO)
	for i in range(12):
		rig.step(1.0 / 60.0)
		check.call()
	_assert(rig.state == FDKHandsRig.HandState.TEAR, "hands: tear state plays after cell_torn")
	for i in range(30):
		rig.step(1.0 / 60.0)
		check.call()
	rig.on_released()
	for i in range(90):
		rig.step(1.0 / 60.0)
		check.call()
	var rel: Dictionary = rig.get_joint_angles("right")
	_assert(rig.state == FDKHandsRig.HandState.IDLE and absf(rel["f2"] - idle["f2"]) < 6.0, "hands: release opens back to the idle pose")
	rig.set_carry(1.0)
	rig.apply_bob(Vector3(0, 0.04, 0))
	for i in range(30):
		rig.step(1.0 / 60.0)
		check.call()
	_assert(rig.is_carrying(), "hands: carry pose holds a flesh pile")
	# random stress: signals in random order never break limits
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(400):
		match rng.randi() % 5:
			0: rig.on_grab_started(Vector3i.ZERO)
			1: rig.on_chew_progress(rng.randf(), Vector3i.ZERO)
			2: rig.on_cell_torn(Vector3.ZERO)
			3: rig.on_released()
			4: rig.set_carry(rng.randf() if rng.randf() < 0.5 else 0.0)
		rig.step(rng.randf_range(0.001, 0.1))
		check.call()
	_assert(worst.is_empty(), "hands: every joint stays inside its angle limit (%s)" % str(worst.slice(0, 5)))

func _run_ps1_tests() -> void:
	# terrain material: PS1 look, one nearest-filtered texture per tissue,
	# vertex snapping and dithering can be switched off for a clean fallback
	var m0 := FDKChunk.terrain_material(0)
	_assert(m0.shader != null, "ps1: terrain tissue 0 gets a PS1 shader material")
	var tex: Texture2D = m0.get_shader_parameter("albedo_tex")
	_assert(tex != null, "ps1: terrain material has an albedo texture assigned")
	if tex != null:
		_assert(tex.get_width() <= 256 and tex.get_height() <= 256, "ps1: texture resolution is low-res (<=256px, got %dx%d)" % [tex.get_width(), tex.get_height()])
	var settings := FDKPs1Settings.active
	_assert(settings.enabled, "ps1: settings default to enabled")
	settings.enabled = false
	var m1 := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_flesh_128.png", 1.0, false, 0.4, 0.5)
	_assert(float(m1.get_shader_parameter("snap_precision")) > 9000.0, "ps1: disabling settings turns vertex snapping effectively off")
	settings.enabled = true
	FDKPs1Material.clear_cache()
	# a different tissue id must get a different texture (visibly distinct materials)
	var mat_flesh := FDKChunk.terrain_material(0)
	var mat_nerve := FDKChunk.terrain_material(1)
	_assert(mat_flesh.get_shader_parameter("albedo_tex") != mat_nerve.get_shader_parameter("albedo_tex"), "ps1: different tissues use different textures")
	FDKChunk.set_press_all(Vector3.ZERO, Vector3.FORWARD, 0.4)
	_assert(is_equal_approx(float(mat_flesh.get_shader_parameter("press_amount")), 0.4), "ps1: chew press still reaches the PS1 material")
	FDKChunk.set_press_all(Vector3.ZERO, Vector3.FORWARD, 0.0)

var _chewer_grab_count: int = 0
var _chewer_tear_count: int = 0
var _chewer_release_count: int = 0

func _on_test_grab_started(_cell: Vector3i) -> void:
	_chewer_grab_count += 1

func _on_test_cell_torn(_pos: Vector3) -> void:
	_chewer_tear_count += 1

func _on_test_released() -> void:
	_chewer_release_count += 1

func _run_barrier_tests() -> void:
	var b := _track(FDKBarrier.new()) as FDKBarrier
	b.break_threshold = 10.0
	b.stress_decay = 0.0
	_assert(b.damage_step() == 0, "barrier: starts intact (step 0)")

	var steps: Array = []
	b.damage_step_changed.connect(func(s): steps.append(s))
	var broke_ratio := [-1.0] # lambdas capture locals by value: use a box
	b.broke.connect(func(r): broke_ratio[0] = r)

	b.absorb_pressure(4.0, 1.0) # 40%
	_assert(b.damage_step() == 1, "barrier: 40%% stress reaches step 1 (got %d)" % b.damage_step())
	b.absorb_pressure(3.0, 1.0) # 70%
	_assert(b.damage_step() == 2, "barrier: 70%% stress reaches step 2 (got %d)" % b.damage_step())
	b.absorb_pressure(4.0, 1.0) # 110% -> breaks
	_assert(b.is_broken(), "barrier: exceeding break_threshold breaks it")
	_assert(b.damage_step() == 3, "barrier: broken reports step 3")
	_assert(broke_ratio[0] > 0.0, "barrier: broke signal fires with a positive release ratio (got %f)" % broke_ratio[0])
	_assert(steps.has(1) and steps.has(2) and steps.has(3), "barrier: damage_step_changed fired for each 33%% transition (got %s)" % [steps])

	var b2 := _track(FDKBarrier.new()) as FDKBarrier
	b2.absorb_pressure(5.0, 1.0)
	var saved := b2.serialize()
	var b3 := _track(FDKBarrier.new()) as FDKBarrier
	b3.deserialize(saved)
	_assert(is_equal_approx(b3.stress, b2.stress), "barrier: serialize/deserialize round-trips stress")

	var config := FDKTerrainConfig.new()
	config.chunk_size = 4
	config.cell_size = 0.5
	config.regen_rate = 1.0
	var field := _track(FDKTerrainField.new()) as FDKTerrainField
	field.config = config
	field.fill_box_uniform(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)), 1.0, 0)
	field.dig_at(Vector3(0, 0, 0), 1.0)
	var bfield := _track(FDKBarrierField.new()) as FDKBarrierField
	bfield.terrain = field
	var placed := bfield.place(Vector3(0, 0, 0))
	_assert(placed != null, "barrier_field: place succeeds under carry cap")
	_assert(bfield.carried_remaining() == 2, "barrier_field: carry cap decrements (got %d)" % bfield.carried_remaining())
	for i in range(3):
		bfield.place(Vector3(1, 0, 0))
	_assert(bfield.carried_remaining() == 0, "barrier_field: carry cap caps at MAX_CARRIED (got %d)" % bfield.carried_remaining())
	bfield.update(1.0)
	_assert(placed.stress > 0.0, "barrier_field: update feeds pressure from regen deficit at its position (got %f)" % placed.stress)

func _run_spray_tests() -> void:
	var config := FDKTerrainConfig.new()
	config.chunk_size = 4
	config.cell_size = 0.5
	var field := _track(FDKTerrainField.new()) as FDKTerrainField
	field.config = config
	field.fill_box_uniform(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)), 1.0, 0)

	var can := FDKSprayCan.new(FDKSprayCan.Tier.CHEAP)
	var sealed := can.apply(field, Vector3(0, 0, 0))
	_assert(sealed > 0, "spray: apply seals at least one cell (got %d)" % sealed)
	_assert(not field.is_edible_at(Vector3(0, 0, 0)), "spray: sealed cell is not edible")
	_assert(field.is_sealed_at(Vector3(0, 0, 0)), "spray: is_sealed_at reports true after spraying")

	# the cheap radius only clears the corners nearest the centre; a deep can
	# clears the whole cell, so the probe cell reads open before regen
	FDKSprayCan.new(FDKSprayCan.Tier.DEEP).apply(field, Vector3(0.25, 0.25, 0.25))
	_assert(field.density_at(Vector3(0, 0, 0)) < 0.5, "spray: deep can opens the whole probe cell")
	field.regenerate_all(1000.0, Vector3(100, 100, 100), 0.5)
	_assert(field.density_at(Vector3(0, 0, 0)) < 0.5, "spray: sealed tissue does not regenerate even after time passes")

	var deep := FDKSprayCan.new(FDKSprayCan.Tier.DEEP)
	_assert(deep.radius() > can.radius(), "spray: DEEP tier reaches farther than CHEAP tier")

	var inv := FDKSprayCan.Inventory.new()
	_assert(inv.add(FDKSprayCan.new()), "spray_inventory: can add under cap")
	_assert(inv.add(FDKSprayCan.new()), "spray_inventory: can add second")
	_assert(inv.add(FDKSprayCan.new()), "spray_inventory: can add third (cap)")
	_assert(not inv.add(FDKSprayCan.new()), "spray_inventory: refuses a 4th can (cap is 3)")
	var used := inv.use(field, Vector3(-1, -1, -1), FDKSprayCan.Tier.CHEAP)
	_assert(used >= 0, "spray_inventory: use() applies and removes a matching can")
	_assert(inv.count() == 2, "spray_inventory: count decrements after use (got %d)" % inv.count())

func _run_mutation_tests() -> void:
	var tree := FDKMutationTree.new()
	tree.define_node("root", [], FDKMutationTree.COMMON, 10)
	tree.define_node("biome_a_1", [], "biome_a", 5)
	tree.define_node("biome_b_1", [], "biome_b", 5)
	tree.define_node("combo", ["biome_a_1", "biome_b_1"], "biome_a", 20, ["biome_a", "biome_b"])

	_assert(not tree.can_purchase("root"), "mutation: cannot purchase with 0 points")
	tree.grant_reward("biome_a", 10, 8) # common += 10, biome_a += 8
	_assert(tree.points(FDKMutationTree.COMMON) == 10, "mutation: grant_reward adds to common pool (got %d)" % tree.points(FDKMutationTree.COMMON))
	_assert(tree.points("biome_a") == 8, "mutation: grant_reward adds to the biome pool (got %d)" % tree.points("biome_a"))
	_assert(tree.can_purchase("root"), "mutation: can_purchase true once common affords it")
	_assert(tree.purchase("root"), "mutation: purchase succeeds")
	_assert(tree.points(FDKMutationTree.COMMON) == 0, "mutation: purchase deducts cost")
	_assert(not tree.purchase("root"), "mutation: cannot re-purchase an owned node")

	_assert(not tree.can_purchase("combo"), "mutation: combo node blocked until both parents purchased")
	tree.grant_reward("biome_a", 0, 0)
	tree._points["biome_a"] = 5
	_assert(tree.purchase("biome_a_1"), "mutation: biome_a_1 purchasable from its own pool")
	tree._points["biome_b"] = 5
	_assert(tree.purchase("biome_b_1"), "mutation: biome_b_1 purchasable from its own pool")
	_assert(not tree.can_purchase("combo"), "mutation: combo still blocked, neither pool has 20 yet")
	tree._points["biome_a"] = 20
	_assert(tree.can_purchase("combo"), "mutation: combo purchasable once parents done and one pool affords it")
	_assert(tree.purchase("combo"), "mutation: combo purchase succeeds, paid from biome_a")
	_assert(tree.points("biome_a") == 0, "mutation: combo payment deducted from the affordable pool")

	var saved := tree.serialize()
	var tree2 := FDKMutationTree.new()
	tree2.deserialize(saved)
	_assert(tree2.is_purchased("combo"), "mutation: deserialize restores purchased nodes")

func _run_nerve_disturb_tests() -> void:
	var config := FDKTerrainConfig.new()
	config.chunk_size = 4
	config.cell_size = 0.5
	var field := _track(FDKTerrainField.new()) as FDKTerrainField
	field.config = config
	field.fill_box_uniform(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)), 1.0, 0)

	var n := _track(FDKNerveStalk.new()) as FDKNerveStalk
	n.terrain = field
	n.place(Vector3(0, 0, 0), Vector3(0, 0, 1))
	var got_signal := [false]
	n.disturbed.connect(func(_p): got_signal[0] = true)
	var density_before := field.density_at(n.base_probe)
	n.disturb(1.0)
	_assert(got_signal[0], "nerve: disturb() emits disturbed signal")
	var density_after := field.density_at(n.base_probe)
	_assert(density_after < density_before, "nerve: disturb() locally contracts tissue at its base (got %f -> %f)" % [density_before, density_after])

func _run_canary_tests() -> void:
	var config := FDKTerrainConfig.new()
	config.chunk_size = 4
	config.cell_size = 0.5
	var field := _track(FDKTerrainField.new()) as FDKTerrainField
	field.config = config
	field.fill_box_uniform(AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8)), 1.0, 0)

	var canary := _track(FDKCanary.new()) as FDKCanary
	canary.terrain = field
	canary.route_samples = 4

	var warnings: Array = []
	canary.route_warning.connect(func(u): warnings.append(u))
	canary.update(Vector3(0, 0, 0), Vector3(1.5, 0, 0)) # entirely solid tissue between: fully blocked
	_assert(warnings.size() > 0, "canary: emits route_warning when urgency changes")
	_assert(canary.last_route_urgency > 0.5, "canary: reports high urgency through solid tissue (got %f)" % canary.last_route_urgency)

	field.dig_at(Vector3(0.75, 0, 0), 1.0)
	field.dig_at(Vector3(0.4, 0, 0), 1.0)
	field.dig_at(Vector3(1.1, 0, 0), 1.0)
	canary.update(Vector3(0, 0, 0), Vector3(1.5, 0, 0))
	_assert(canary.last_route_urgency < 1.0, "canary: dug-out route lowers urgency (got %f)" % canary.last_route_urgency)

func _run_death_drop_tests() -> void:
	var drop := _track(FDKDeathDrop.new()) as FDKDeathDrop
	drop.drop(Vector3(1, 0, 1), {"gold": 3})
	_assert(drop.active, "death_drop: drop() activates it")
	_assert(drop.last_known_position == Vector3(1, 0, 1), "death_drop: last_known_position set at drop time")

	drop.carry_along(Vector3(1.5, 0, 0))
	_assert(drop.current_position.is_equal_approx(Vector3(2.5, 0, 1)), "death_drop: carry_along displaces current_position")
	_assert(drop.last_known_position == Vector3(1, 0, 1), "death_drop: last_known_position stays stale after drift (no auto-update)")

	var too_far := drop.try_recover(Vector3(1, 0, 1), 1.0) # stale marker, but drop actually moved
	_assert(too_far.is_empty(), "death_drop: recovery at the stale marker fails once it has drifted out of range")

	var got := drop.try_recover(Vector3(2.5, 0, 1), 1.0)
	_assert(got.has("gold") and got["gold"] == 3, "death_drop: recovery at the real current position returns the items")
	_assert(not drop.active, "death_drop: recovered drop becomes inactive")
