extends SceneTree

## Terrain perf benchmark (before/after numbers for the perf pass).
## Digs a tunnel through a 3x3x3-chunk block, then simulates regrowth frames:
## regenerate_all + remesh of every dirty chunk. Prints average ms.
##   Godot_console.exe --headless --path <project> --script tests/measure_terrain_perf.gd

func _init() -> void:
	var config := FDKTerrainConfig.new()
	config.chunk_size = 16
	config.cell_size = 0.5
	var field := FDKTerrainField.new()
	field.config = config
	field.fill_box_uniform(AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24)), 1.0, 0)
	for i in range(80):
		field.dig_at(Vector3(-10.0 + i * 0.25, sin(i * 0.2) * 1.5, 0.0), 1.0)
		field.dig_at(Vector3(-10.0 + i * 0.25, sin(i * 0.2) * 1.5 + 0.5, 0.5), 1.0)
	field.remesh_all()
	var regen_ms := 0.0
	var remesh_ms := 0.0
	var remesh_n := 0
	var frames := 60
	var parts := {}
	for f in range(frames):
		var t0 := Time.get_ticks_usec()
		field.regenerate_all(1.0 / 60.0, Vector3(50, 50, 50), 1.0)
		regen_ms += (Time.get_ticks_usec() - t0) / 1000.0
		for c in field.get_chunks():
			if c.is_dirty():
				remesh_ms += c.remesh()
				remesh_n += 1
				if "last_stats" in c:
					for k in c.last_stats.keys():
						parts[k] = float(parts.get(k, 0.0)) + float(c.last_stats[k])
	print("=== terrain perf ===")
	print("regenerate_all avg: %.3f ms/frame over %d frames (%d chunks)" % [regen_ms / frames, frames, field.get_chunks().size()])
	print("remesh avg: %.3f ms/chunk over %d remeshes" % [remesh_ms / maxi(remesh_n, 1), remesh_n])
	for k in parts.keys():
		print("  %s avg: %.3f ms" % [k, parts[k] / maxi(remesh_n, 1)])
	field.free()
	FDKPs1Material.clear_cache()
	quit(0)