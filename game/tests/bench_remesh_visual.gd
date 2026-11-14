extends SceneTree

## Cost of one chunk re-mesh on a dug, regrowing tunnel that crosses chunk
## borders and a tissue boundary (kit only: no Main, no save). Run the same
## script before and after a change to the mesh builder and compare the
## per-chunk means; the numbers are for this machine only.
##   godot_console --headless --path game --script res://tests/bench_remesh_visual.gd
## Prints density / mesh / arraymesh / total ms per surface chunk, and how many
## published triangles show another tissue than the cell an aimed tear takes.

const ROUNDS := 12
const FAR := Vector3(1000, 1000, 1000)

func _init() -> void:
	var field := FDKTerrainField.new()
	field.config = FDKTerrainConfig.new()
	field.density_sampler = func(_p: Vector3) -> float: return 1.0
	# tissue changes across x = 2 m and in a shell round the origin
	field.tissue_sampler = func(p: Vector3) -> int:
		if p.length() > 5.0:
			return FDKTissueRules.CONTRACTILE
		return FDKTissueRules.MEMBRANE if p.x > 2.0 and p.x < 2.5 else FDKTissueRules.COMPRESSIVE
	root.add_child(field)
	var cs := field.config.cell_size
	# a bent tunnel two cells wide through four chunks
	var p := Vector3(-3.0, 0.25, -3.0)
	for i in range(60):
		var step := Vector3(1, 0, 0) if i < 24 else (Vector3(0, 0, 1) if i < 44 else Vector3(0, 1, 0))
		p += step * cs
		for dy in range(2):
			for dz in range(2):
				field.dig_at(p + Vector3(0, dy, dz) * cs, 1.0)
	field.remesh_all()
	# regrowth under way everywhere (corners between 0 and iso)
	for i in range(40):
		field.regenerate_all(1.0, FAR, 0.0)
	field.remesh_all()
	var sums := {"density_ms": 0.0, "mesh_ms": 0.0, "arraymesh_ms": 0.0, "total_ms": 0.0}
	var count := 0
	var worst := 0.0
	for r in range(ROUNDS):
		for ch in field.get_chunks():
			var chunk: FDKChunk = ch
			if chunk._surface_faces.is_empty():
				continue
			chunk._dirty = true
			chunk.remesh(false)
			for k in sums.keys():
				sums[k] += float(chunk.last_stats[k])
			worst = maxf(worst, float(chunk.last_stats.total_ms) - float(chunk.last_stats.collider_ms))
			count += 1
	var line := "remesh chunks=%d" % (count / ROUNDS)
	for k in sums.keys():
		line += "  %s=%.3f" % [k, sums[k] / count]
	print(line + "  worst_no_collider=%.3f" % worst)
	# tissue shown by each published triangle against the aimed cell
	var wrong := 0
	var total := 0
	var by_axis := {}
	for ch in field.get_chunks():
		var chunk: FDKChunk = ch
		var mesh: Mesh = chunk._mesh_instance.mesh
		if mesh == null:
			continue
		for si in range(mesh.get_surface_count()):
			var shown := -1
			for t in range(FDKChunk.TISSUE_TEXTURES.size()):
				if mesh.surface_get_material(si) == FDKChunk.terrain_material(t):
					shown = t
			var v: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for i in range(0, v.size(), 3):
				var a: Vector3 = chunk.position + v[i]
				var b: Vector3 = chunk.position + v[i + 1]
				var c: Vector3 = chunk.position + v[i + 2]
				var outward: Vector3 = -(b - a).cross(c - a).normalized()
				var sample: Vector3 = (a + b + c) / 3.0 - outward * cs * 0.5
				total += 1
				if field.tissue_at(sample) != shown:
					wrong += 1
					var key := str(Vector3i(outward.round()))
					by_axis[key] = int(by_axis.get(key, 0)) + 1
	print("face tissue != aimed cell: %d of %d  by facing %s" % [wrong, total, str(by_axis)])
	quit(0)
