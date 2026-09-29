extends SceneTree

## Integration test for main.gd's serialize()/deserialize() round trip:
## dig some tunnel, fill the stomach partway, save, mutate further, then
## restore and confirm the restored state matches what was saved (not the
## further-mutated state). Run with:
##   Godot_console.exe --headless --path <project> --script tests/run_save_load.gd

var _failures: int = 0
var _passed: int = 0
var _main_node: Node3D
var _frame_count: int = 0
var _done: bool = false

func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: %s" % message)

func _init() -> void:
	print("=== flesh-pit save/load integration test ===")
	var packed: PackedScene = load("res://main/scenes/main.tscn")
	_main_node = packed.instantiate()
	get_root().add_child(_main_node)

func _process(_delta: float) -> bool:
	if _done:
		return false
	_frame_count += 1
	if _frame_count < 3: # let _ready() fully wire terrain/stomach/etc first
		return false

	_run_test()
	_done = true
	print("--- %d passed, %d failed ---" % [_passed, _failures])
	quit(1 if _failures > 0 else 0)
	return true

func _run_test() -> void:
	# Dig a short tunnel and fill the stomach partway, then save.
	for i in range(4):
		_main_node.terrain.dig_at(Vector3(0, 1, 3.0 + i * 0.5), 1.0)
	_main_node.stomach.add_flesh(42.0)
	var saved_data: Dictionary = _main_node.serialize()

	var saved_fill: float = _main_node.stomach.fill
	var probe_pos := Vector3(0, 1, 3.0)
	var result: Array = _main_node.terrain.world_to_cell(probe_pos)
	var chunk_coord: Vector3i = result[0]
	var local_cell: Vector3i = result[1]
	var saved_chunk: FDKChunk = _main_node.terrain.get_chunk(chunk_coord)
	var saved_density: float = saved_chunk.get_density_at_corner(local_cell.x, local_cell.y, local_cell.z)

	# Mutate further so restoring is a real test, not a no-op.
	_main_node.stomach.add_flesh(500.0)
	for i in range(4, 10):
		_main_node.terrain.dig_at(Vector3(0, 1, 3.0 + i * 0.5), 1.0)
	_assert(_main_node.stomach.fill != saved_fill, "sanity: further mutation actually changed stomach fill")

	# Restore and verify we're back to the saved snapshot, not the mutated one.
	_main_node.deserialize(saved_data)
	_assert(is_equal_approx(_main_node.stomach.fill, saved_fill),
		"save/load: stomach fill restored to saved value (got %f, expected %f)" % [_main_node.stomach.fill, saved_fill])

	var restored_chunk: FDKChunk = _main_node.terrain.get_chunk(chunk_coord)
	var restored_density: float = restored_chunk.get_density_at_corner(local_cell.x, local_cell.y, local_cell.z)
	_assert(is_equal_approx(restored_density, saved_density),
		"save/load: terrain density at dug cell restored (got %f, expected %f)" % [restored_density, saved_density])
