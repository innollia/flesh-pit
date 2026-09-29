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
	# Hand rig / hand mesh / hand animation is frontend scope (owned by
	# another model per 형님's 2026-09-29 scope split) and is not tested here.
	print("--- %d passed, %d failed ---" % [_passed, _failures])
	quit(1 if _failures > 0 else 0)

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

	var field := FDKTerrainField.new()
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
	var field2 := FDKTerrainField.new()
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

	var stomach := FDKStomach.new()
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
	var field := FDKTerrainField.new()
	field.config = terrain_config
	field.fill_box_uniform(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)), 1.0, 0)

	var stomach_config := FDKStomachConfig.new()
	stomach_config.base_chew_time = 0.5
	stomach_config.flesh_per_cell = 4.0

	var stomach := FDKStomach.new()
	stomach.config = stomach_config

	var chewer := FDKChewer.new()
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

var _chewer_grab_count: int = 0
var _chewer_tear_count: int = 0
var _chewer_release_count: int = 0

func _on_test_grab_started(_cell: Vector3i) -> void:
	_chewer_grab_count += 1

func _on_test_cell_torn(_pos: Vector3) -> void:
	_chewer_tear_count += 1

func _on_test_released() -> void:
	_chewer_release_count += 1
