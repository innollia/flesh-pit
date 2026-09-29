extends SceneTree

## Measures single-chunk remesh time after one dig, to check against the
## <8ms budget in the handoff spec. Run with:
##   Godot_console.exe --headless --path <project> --script tests/measure_remesh.gd

func _init() -> void:
	var config := FDKTerrainConfig.new()
	config.chunk_size = 16
	config.cell_size = 0.5

	var field := FDKTerrainField.new()
	field.config = config
	field.fill_box_uniform(AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8)), 1.0, 0)

	var chunk_coord := field.world_to_chunk_coord(Vector3.ZERO)
	var chunk := field.get_chunk(chunk_coord)

	# Initial mesh build (cold), then measure a single post-dig remesh (the
	# steady-state cost the spec's 8ms budget is actually about).
	chunk.remesh()

	field.dig_at(Vector3(0, 0, 0), 1.0)
	var elapsed_ms := chunk.remesh()

	print("=== remesh benchmark ===")
	print("chunk_size=%d cell_size=%.2f" % [config.chunk_size, config.cell_size])
	print("single dig + remesh: %.3f ms" % elapsed_ms)

	# Average over several digs at different cells for a steadier reading.
	var total_ms := 0.0
	var trials := 20
	for i in range(trials):
		var pos := Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
		field.dig_at(pos, 1.0)
		total_ms += chunk.remesh()
	print("average over %d more digs: %.3f ms" % [trials, total_ms / trials])
	print("budget: 8.000 ms")
	field.free()
	FDKPs1Material.clear_cache()

	quit(0)
