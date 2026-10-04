extends SceneTree

const FDKSurfacePatch = preload("res://addons/flesh_dig_kit/terrain/fdk_surface_patch.gd")

var passed := 0
var failed := 0

func _init() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func make_field() -> FDKTerrainField:
	var f := FDKTerrainField.new()
	f.config = FDKTerrainConfig.new()
	f.config.chunk_size = 4
	f.density_sampler = func(_p: Vector3): return 1.0
	f.tissue_sampler = func(p: Vector3): return 0 if p.x < 0.0 else 2
	root.add_child(f)
	f.set_process(false)
	f.generate_region(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)))
	f.remesh_all()
	return f

func make_field_with_region(region: AABB) -> FDKTerrainField:
	var f := FDKTerrainField.new()
	f.config = FDKTerrainConfig.new()
	f.config.chunk_size = 4
	f.density_sampler = func(_p: Vector3): return 1.0
	f.tissue_sampler = func(p: Vector3): return 0 if p.x < 0.0 else 2
	root.add_child(f)
	f.set_process(false)
	f.generate_region(region)
	f.remesh_all()
	return f

func oriented_tri_key(t: Dictionary) -> String:
	var v0: Vector3 = t.v0.snapped(Vector3.ONE * 0.0001)
	var v1: Vector3 = t.v1.snapped(Vector3.ONE * 0.0001)
	var v2: Vector3 = t.v2.snapped(Vector3.ONE * 0.0001)
	var s0 := "%0.4f,%0.4f,%0.4f" % [v0.x, v0.y, v0.z]
	var s1 := "%0.4f,%0.4f,%0.4f" % [v1.x, v1.y, v1.z]
	var s2 := "%0.4f,%0.4f,%0.4f" % [v2.x, v2.y, v2.z]
	var best := s0 + ";" + s1 + ";" + s2
	var p1 := s1 + ";" + s2 + ";" + s0
	var p2 := s2 + ";" + s0 + ";" + s1
	if p1 < best:
		best = p1
	if p2 < best:
		best = p2
	return "%d:%s" % [t.tissue, best]

func count_open_oriented_edges(tris: Array) -> int:
	var edge_counts := {}
	for t in tris:
		var pts := [t.v0, t.v1, t.v2]
		for i in range(3):
			var pA: Vector3 = pts[i].snapped(Vector3.ONE * 0.0001)
			var pB: Vector3 = pts[(i + 1) % 3].snapped(Vector3.ONE * 0.0001)
			var ka := "%0.4f,%0.4f,%0.4f" % [pA.x, pA.y, pA.z]
			var kb := "%0.4f,%0.4f,%0.4f" % [pB.x, pB.y, pB.z]
			var k := ka + "->" + kb
			edge_counts[k] = edge_counts.get(k, 0) + 1
	var open := 0
	for edge_key in edge_counts.keys():
		var parts = edge_key.split("->")
		var reverse_key = parts[1] + "->" + parts[0]
		var forward_count: int = edge_counts[edge_key]
		var reverse_count: int = edge_counts.get(reverse_key, 0)
		if forward_count != reverse_count:
			open += absi(forward_count - reverse_count)
	return open

func extract_field_triangles(p_field: FDKTerrainField) -> Array:
	var tris: Array = []
	for chunk in p_field.get_chunks():
		var m: Mesh = chunk._mesh_instance.mesh
		if m == null:
			continue
		for s_idx in range(m.get_surface_count()):
			var mat = m.surface_get_material(s_idx)
			var tid := 0
			for i in range(FDKChunk.TISSUE_TEXTURES.size()):
				if mat == FDKChunk.terrain_material(i):
					tid = i
					break
			var arrays = m.surface_get_arrays(s_idx)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in range(0, verts.size(), 3):
				var w0: Vector3 = chunk.to_global(verts[i])
				var w1: Vector3 = chunk.to_global(verts[i + 1])
				var w2: Vector3 = chunk.to_global(verts[i + 2])
				tris.append({"v0": w0, "v1": w1, "v2": w2, "tissue": tid})
	return tris

func extract_patch_triangles(p_patch) -> Array:
	var tris: Array = []
	var m: Mesh = p_patch.mesh
	if m == null:
		return tris
	for s_idx in range(m.get_surface_count()):
		var mat = m.surface_get_material(s_idx)
		var tid := 0
		for i in range(FDKChunk.TISSUE_TEXTURES.size()):
			if mat == FDKChunk.terrain_material(i):
				tid = i
				break
		var arrays = m.surface_get_arrays(s_idx)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in range(0, verts.size(), 3):
			var w0: Vector3 = p_patch.to_global(verts[i]) if p_patch.is_inside_tree() else verts[i]
			var w1: Vector3 = p_patch.to_global(verts[i + 1]) if p_patch.is_inside_tree() else verts[i + 1]
			var w2: Vector3 = p_patch.to_global(verts[i + 2]) if p_patch.is_inside_tree() else verts[i + 2]
			tris.append({"v0": w0, "v1": w1, "v2": w2, "tissue": tid})
	return tris

func tri_matches(t1: Dictionary, t2: Dictionary) -> bool:
	if t1.tissue != t2.tissue:
		return false
	var a1: Vector3 = t1.v0
	var b1: Vector3 = t1.v1
	var c1: Vector3 = t1.v2
	var a2: Vector3 = t2.v0
	var b2: Vector3 = t2.v1
	var c2: Vector3 = t2.v2
	if a1.is_equal_approx(a2) and b1.is_equal_approx(b2) and c1.is_equal_approx(c2):
		return true
	if a1.is_equal_approx(b2) and b1.is_equal_approx(c2) and c1.is_equal_approx(a2):
		return true
	if a1.is_equal_approx(c2) and b1.is_equal_approx(a2) and c1.is_equal_approx(b2):
		return true
	return false

func match_triangles(tris1: Array, tris2: Array) -> bool:
	if tris1.size() != tris2.size():
		return false
	var matched2 := []
	matched2.resize(tris2.size())
	matched2.fill(false)
	for t1 in tris1:
		var found := false
		for j in range(tris2.size()):
			if not matched2[j] and tri_matches(t1, tris2[j]):
				matched2[j] = true
				found = true
				break
		if not found:
			return false
	return true

func count_open_edges(tris: Array) -> int:
	var edge_counts := {}
	for t in tris:
		var pts := [t.v0, t.v1, t.v2]
		for i in range(3):
			var pA: Vector3 = pts[i]
			var pB: Vector3 = pts[(i + 1) % 3]
			var sA := pA.snapped(Vector3.ONE * 0.0001)
			var sB := pB.snapped(Vector3.ONE * 0.0001)
			var ka := "%0.4f,%0.4f,%0.4f" % [sA.x, sA.y, sA.z]
			var kb := "%0.4f,%0.4f,%0.4f" % [sB.x, sB.y, sB.z]
			var k := (ka + "|" + kb) if ka < kb else (kb + "|" + ka)
			edge_counts[k] = edge_counts.get(k, 0) + 1
	var open_edges := 0
	for count in edge_counts.values():
		if count != 2:
			open_edges += 1
	return open_edges

func check_six_axis_hits(center: Vector3, faces: PackedVector3Array) -> bool:
	var axes := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
	for dir in axes:
		var hit := false
		for i in range(0, faces.size(), 3):
			var pt = Geometry3D.ray_intersects_triangle(center, dir, faces[i], faces[i + 1], faces[i + 2])
			if pt != null:
				var dist: float = (pt - center).dot(dir)
				if dist > 0.0001:
					hit = true
					break
		if not hit:
			return false
	return true

func run() -> void:
	# Scenario 1: target cell 0 (Vector3i.ZERO)
	var field := make_field()
	var helper := FDKSurfacePatch.new(field)

	# Fully solid before dig: faces 0, mesh null
	helper.build(Vector3i.ZERO)
	check(helper.faces.size() == 0, "fullysolid beforedig faces 0")
	check(helper.mesh == null, "fullysolid beforedig mesh null")

	# Single dig at cell(.1, .3, .05) targeting cell 0
	field.dig_at(Vector3(0.1, 0.3, 0.05), 0.65)
	var ser_before := field.serialize()
	var chunks_before := field.get_chunks().size()

	helper.build(Vector3i.ZERO)
	check(field.serialize() == ser_before, "field.serialize preserved")
	check(field.get_chunks().size() == chunks_before, "get_chunks preserved")
	check(helper.read_corner_count <= 64, "geometry does not read beyond 3^3 cells corners")
	check(helper.faces.size() > 0, "dug patch has faces")

	field.remesh_all()
	var f_tris := extract_field_triangles(field)
	var p_tris := extract_patch_triangles(helper)
	check(p_tris.size() > 0, "patch produced triangles")
	check(p_tris.size() == f_tris.size(), "triangle count matches field.remesh_all (%d == %d)" % [p_tris.size(), f_tris.size()])
	check(match_triangles(p_tris, f_tris), "patch triangles match field world triangles (vertices/winding/tissue)")
	check(count_open_edges(p_tris) == 0, "open edges count is 0")
	check(check_six_axis_hits(Vector3(0.5, 0.5, 0.5), helper.faces), "six axis hits confirmed for target cell 0")

	helper.free()
	field.queue_free()
	await process_frame

	# Scenario 2: negative boundary target cell (-1, -1, -1)
	var field2 := make_field()
	var helper2 := FDKSurfacePatch.new(field2)

	helper2.build(Vector3i(-1, -1, -1))
	check(helper2.faces.size() == 0, "neg boundary before dig faces 0")

	field2.dig_at(Vector3(-0.5, -0.5, -0.5), 0.65)
	var ser2_before := field2.serialize()
	var chunks2_before := field2.get_chunks().size()

	helper2.build(Vector3i(-1, -1, -1))
	check(field2.serialize() == ser2_before, "field2.serialize preserved")
	check(field2.get_chunks().size() == chunks2_before, "field2.get_chunks preserved")
	check(helper2.read_corner_count <= 64, "helper2 reads at most 64 corners")
	check(helper2.faces.size() > 0, "helper2 has faces")

	field2.remesh_all()
	var f2_tris := extract_field_triangles(field2)
	var p2_tris := extract_patch_triangles(helper2)
	check(p2_tris.size() > 0, "helper2 produced triangles")
	check(p2_tris.size() == f2_tris.size(), "triangle count matches field2.remesh_all (%d == %d)" % [p2_tris.size(), f2_tris.size()])
	check(match_triangles(p2_tris, f2_tris), "helper2 triangles match field2 (vertices/winding/tissue)")
	check(count_open_edges(p2_tris) == 0, "helper2 open edges count is 0")
	check(check_six_axis_hits(Vector3(-0.5, -0.5, -0.5), helper2.faces), "six axis hits confirmed for target cell -1,-1,-1")

	helper2.free()
	field2.queue_free()
	await process_frame

	# Scenario 3: adjacent dig at cell 0 and cell (0, 0, 1) with build_region (36 cells, 80 corners)
	var field3 := make_field()
	var helper3 := FDKSurfacePatch.new(field3)

	field3.dig_at(Vector3(0.1, 0.3, 0.05), 0.65)
	field3.dig_at(Vector3(0.1, 0.3, 0.55), 0.65)
	var ser3_before := field3.serialize()
	var chunks3_before := field3.get_chunks().size()

	var ok3 := helper3.build_region(Vector3i(-1, -1, -1), Vector3i(1, 1, 2))
	check(ok3, "build_region(-1,-1,-1 to 1,1,2) succeeded")
	check(field3.serialize() == ser3_before, "field3.serialize preserved")
	check(field3.get_chunks().size() == chunks3_before, "field3.get_chunks preserved")
	check(helper3.read_corner_count == 80, "helper3 read exactly 80 corners (4x4x5)")
	check(helper3.faces.size() > 0, "helper3 has faces")

	field3.remesh_all()
	var f3_tris := extract_field_triangles(field3)
	var p3_tris := extract_patch_triangles(helper3)
	check(p3_tris.size() > 0, "helper3 produced triangles")
	check(p3_tris.size() == f3_tris.size(), "triangle count matches field3.remesh_all (%d == %d)" % [p3_tris.size(), f3_tris.size()])
	check(match_triangles(p3_tris, f3_tris), "helper3 triangles match field3 (vertices/winding/tissue)")
	check(count_open_edges(p3_tris) == 0, "helper3 open edges count is 0")
	check(check_six_axis_hits(Vector3(0.1, 0.3, 0.3), helper3.faces), "six axis hits confirmed for adjacent dug hole")

	helper3.free()
	field3.queue_free()
	await process_frame

	# Scenario 4: negative chunk boundary crossing 2 adjacent cells
	var field4 := make_field()
	var helper4 := FDKSurfacePatch.new(field4)

	field4.dig_at(Vector3(-0.5, -0.5, -0.5), 0.65)
	field4.dig_at(Vector3(-0.5, -0.5, 0.1), 0.65)
	var ser4_before := field4.serialize()
	var chunks4_before := field4.get_chunks().size()

	var ok4 := helper4.build_region(Vector3i(-2, -2, -2), Vector3i(0, 0, 1))
	check(ok4, "build_region across neg boundary succeeded")
	check(field4.serialize() == ser4_before, "field4.serialize preserved")
	check(field4.get_chunks().size() == chunks4_before, "field4.get_chunks preserved")
	check(helper4.read_corner_count == 80, "helper4 read exactly 80 corners across chunk boundary")
	check(helper4.faces.size() > 0, "helper4 has faces")

	field4.remesh_all()
	var f4_tris := extract_field_triangles(field4)
	var p4_tris := extract_patch_triangles(helper4)
	check(p4_tris.size() > 0, "helper4 produced triangles")
	check(p4_tris.size() == f4_tris.size(), "triangle count matches field4.remesh_all (%d == %d)" % [p4_tris.size(), f4_tris.size()])
	check(match_triangles(p4_tris, f4_tris), "helper4 triangles match field4 across chunk boundary")
	check(count_open_edges(p4_tris) == 0, "helper4 open edges count is 0")
	check(check_six_axis_hits(Vector3(-0.25, -0.25, 0.0), helper4.faces), "six axis hits confirmed across neg boundary")

	helper4.free()
	field4.queue_free()
	await process_frame

	# Scenario 5: region bounds limit: max span 7 / 512 corners, rejects span > 7 or min > max
	var field5 := make_field()
	var helper5 := FDKSurfacePatch.new(field5)

	var ok_max := helper5.build_region(Vector3i.ZERO, Vector3i(6, 6, 6))
	check(ok_max, "span 7 is allowed")
	check(helper5.read_corner_count == 512, "span 7 reads exactly 512 corners (8x8x8)")

	var fail_span := helper5.build_region(Vector3i.ZERO, Vector3i(7, 0, 0))
	check(not fail_span, "span > 7 rejected")
	check(helper5.faces.size() == 0, "rejected span > 7 has 0 faces")
	check(helper5.mesh == null, "rejected span > 7 has null mesh")

	var fail_order := helper5.build_region(Vector3i(1, 0, 0), Vector3i(0, 0, 0))
	check(not fail_order, "min > max rejected")
	check(helper5.faces.size() == 0, "rejected min > max has 0 faces")
	check(helper5.mesh == null, "rejected min > max has null mesh")

	helper5.free()
	field5.queue_free()
	await process_frame

	# Scenario 6: build_tile edge ownership with span > 7 closed cavity
	var field6 := make_field_with_region(AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8)))
	var cs6: float = field6.config.cell_size

	# Dig an elongated closed cavity spanning 9 cells along X (from cx=-4 to cx=4, span 9 > 7)
	# crossing both negative and positive coordinates
	for cx in range(-4, 5):
		for cy in range(-1, 2):
			for cz in range(-1, 2):
				var w := (Vector3(cx, cy, cz) + Vector3(0.5, 0.5, 0.5)) * cs6
				field6.dig_at(w, 0.65)

	var ser6_before := field6.serialize()
	var chunks6_before := field6.get_chunks().size()

	# Build tiles covering the excavated cavity (origins at multiples of 4 corners)
	var all_tile_tris: Array = []
	var tile_corner_counts_ok := true
	var active_tiles := 0
	var active_neg_tiles := 0
	var active_pos_tiles := 0
	var has_individual_open_tile := false
	var patches: Array = []

	for tx in range(-3, 3):
		for ty in range(-2, 2):
			for tz in range(-2, 2):
				var origin := Vector3i(tx * 4, ty * 4, tz * 4)
				var patch := FDKSurfacePatch.new(field6)
				patches.append(patch)
				var ok := patch.build_tile(origin)
				check(ok, "build_tile(%d,%d,%d) succeeded" % [origin.x, origin.y, origin.z])
				if patch.read_corner_count > 216:
					tile_corner_counts_ok = false
				if patch.faces.size() > 0:
					active_tiles += 1
					if origin.x < 0 or origin.y < 0 or origin.z < 0:
						active_neg_tiles += 1
					if origin.x >= 0 and origin.y >= 0 and origin.z >= 0:
						active_pos_tiles += 1
					var tile_tris := extract_patch_triangles(patch)
					var open_e := count_open_edges(tile_tris)
					if open_e > 0:
						has_individual_open_tile = true
					all_tile_tris.append_array(tile_tris)

	check(field6.serialize() == ser6_before, "field6.serialize preserved after building tiles")
	check(field6.get_chunks().size() == chunks6_before, "field6 chunk count preserved after building tiles")
	check(tile_corner_counts_ok, "all tiles read at most 216 corners")
	check(active_tiles >= 4, "cavity spans across multiple active tiles (%d >= 4)" % active_tiles)
	check(active_neg_tiles > 0 and active_pos_tiles > 0, "tiles span across negative and positive tile boundaries (neg: %d, pos: %d)" % [active_neg_tiles, active_pos_tiles])
	check(has_individual_open_tile, "individual tiles crossing boundary have open edges (not closed individually)")

	field6.remesh_all()
	var f6_tris := extract_field_triangles(field6)
	check(all_tile_tris.size() > 0, "tile union produced triangles")
	check(all_tile_tris.size() == f6_tris.size(), "triangle count matches field6.remesh_all (%d == %d)" % [all_tile_tris.size(), f6_tris.size()])

	# Verify no duplicate triangles in tile union
	var tile_key_counts := {}
	var duplicate_count := 0
	for t in all_tile_tris:
		var k := oriented_tri_key(t)
		var cur: int = tile_key_counts.get(k, 0)
		if cur > 0:
			duplicate_count += 1
		tile_key_counts[k] = cur + 1
	check(duplicate_count == 0, "duplicate triangle count is 0 in tile union")

	# Verify oriented triangle keys match field6.remesh_all exactly (not just counts)
	var field_key_counts := {}
	for t in f6_tris:
		var k := oriented_tri_key(t)
		field_key_counts[k] = field_key_counts.get(k, 0) + 1
	var keys_match := true
	if tile_key_counts.size() != field_key_counts.size():
		keys_match = false
	else:
		for k in tile_key_counts.keys():
			if tile_key_counts[k] != field_key_counts.get(k, 0):
				keys_match = false
				break
	check(keys_match, "tile union oriented triangle keys match field6.remesh_all exactly")

	# Verify merged surface is closed: open unoriented edges == 0, open oriented edges == 0
	check(count_open_edges(all_tile_tris) == 0, "tile union open edges count is 0 (mesh is closed)")
	check(count_open_oriented_edges(all_tile_tris) == 0, "tile union open oriented edges count is 0")

	for p in patches:
		p.free()
	field6.queue_free()
	await process_frame

	# A ray query on a pure preview must not stream terrain or return a null body.
	var query_field := FDKTerrainField.new()
	query_field.config.chunk_size = 4
	var query_center := Vector3(10.25, 0.25, 0.25)
	query_field.density_sampler = func(p: Vector3): return 0.0 if p.distance_to(query_center) < 0.6 else 1.0
	root.add_child(query_field)
	query_field.set_process(false)
	var query_patch := FDKSurfacePatch.new(query_field)
	query_patch.build(Vector3i(20, 0, 0))
	check(not query_patch.faces.is_empty(), "unstreamed preview has actual sampled surface geometry")
	var query_saved := query_field.serialize()
	var query_hit := query_patch.contact_ray(query_center, query_center + Vector3.RIGHT * 2.0)
	check(query_hit.is_empty(), "unstreamed preview does not fabricate a null collider contact")
	check(query_field.get_chunks().is_empty(), "preview ray query does not generate terrain chunks")
	check(query_field.serialize() == query_saved, "preview ray query preserves serialized state")
	query_patch.free()
	query_field.queue_free()
	await process_frame
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
