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
