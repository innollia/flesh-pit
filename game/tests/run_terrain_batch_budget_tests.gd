extends SceneTree

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

func count_open_edges_from_faces(faces: PackedVector3Array) -> int:
	var edge_counts := {}
	for i in range(0, faces.size(), 3):
		var pts := [faces[i], faces[i + 1], faces[i + 2]]
		for j in range(3):
			var pA: Vector3 = pts[j]
			var pB: Vector3 = pts[(j + 1) % 3]
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

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	# --- Test 1: Negative Chunks & Shared Padding Reader Selection ---
	var field := FDKTerrainField.new()
	field.config = FDKTerrainConfig.new()
	field.config.chunk_size = 4
	field.config.cell_size = 1.0
	field.density_sampler = func(_p: Vector3): return 1.0
	world.add_child(field)
	field.set_process(false)

	# Generate region spanning negative and positive coordinates: [-8, 8] on X, [-4, 4] on Y, Z
	field.generate_region(AABB(Vector3(-8, -4, -4), Vector3(16, 8, 8)))
	field.remesh_all()

	var c_neg: FDKChunk = field.get_chunk(Vector3i(-1, 0, 0))
	var c_pos: FDKChunk = field.get_chunk(Vector3i(0, 0, 0))
	var c_far_neg: FDKChunk = field.get_chunk(Vector3i(-2, 0, 0))
	var c_far_pos: FDKChunk = field.get_chunk(Vector3i(1, 0, 0))
	check(c_neg != null and c_pos != null, "test1: boundary chunks exist")
	check(c_far_neg != null and c_far_pos != null, "test1: far chunks exist")

	# Dig on the boundary between (-1, 0, 0) and (0, 0, 0)
	field.dig_at(Vector3(0.0, 2.0, 2.0), 0.6)
	check(c_neg.is_dirty() or c_pos.is_dirty(), "test1: boundary edit marked chunks dirty")

	field._begin_mesh_batch()
	var batch_coords := []
	for c in field._mesh_batch:
		batch_coords.append(c.chunk_coord)
	check(batch_coords.has(Vector3i(-1, 0, 0)), "test1: negative chunk included in batch targets")
	check(batch_coords.has(Vector3i(0, 0, 0)), "test1: positive chunk included in batch targets")
	check(not batch_coords.has(Vector3i(-2, 0, 0)), "test1: far negative chunk not included in targets")
	check(not batch_coords.has(Vector3i(1, 0, 0)), "test1: far positive chunk not included in targets")

	# Clean up batch state
	field._mesh_batch.clear()
	field._mesh_snapshot.clear()
	field._mesh_missing_snapshot.clear()
	field.remesh_all()

	# --- Test 2: Interior-Only Edit Isolation ---
	# Edit strictly inside chunk (0, 0, 0) at local cell (1, 1, 1) with corners in {1, 2}
	field.dig_at(Vector3(1.0, 1.0, 1.0), 0.2)
	check(c_pos.is_dirty(), "test2: chunk (0,0,0) is dirty after interior edit")
	check(not c_neg.is_dirty(), "test2: neighbor chunk (-1,0,0) not dirty from interior edit")

	field._begin_mesh_batch()
	check(field._mesh_batch.size() == 1, "test2: interior edit batch contains only the edited chunk")
	check(field._mesh_batch[0].chunk_coord == Vector3i(0, 0, 0), "test2: target is exactly chunk (0,0,0)")

	field._mesh_batch.clear()
	field._mesh_snapshot.clear()
	field._mesh_missing_snapshot.clear()
	field.remesh_all()

	# --- Test 3: Urgent Chunks Priority Ordering ---
	c_pos.set_density_at_corner(2, 2, 2, 0.5)
	c_neg.set_density_at_corner(2, 2, 2, 0.5)
	field._urgent_chunks[Vector3i(-1, 0, 0)] = true
	field._begin_mesh_batch()
	check(field._mesh_batch.size() >= 2, "test3: batch has both dirty chunks")
	check(field._mesh_batch[0].chunk_coord == Vector3i(-1, 0, 0), "test3: urgent chunk (-1,0,0) is prioritized first in batch")
	check(not field._urgent_chunks.has(Vector3i(-1, 0, 0)), "test3: urgent chunk erased after batch begin")

	field._mesh_batch.clear()
	field._mesh_snapshot.clear()
	field._mesh_missing_snapshot.clear()
	field.remesh_all()

	# --- Test 4: Frozen Batch & Atomic Connected Publication Under Continuous Regen/Dig ---
	# Dig crossing boundary between chunk (0,0,0) and (1,0,0) at y=1, z=1 (so y,z remain strictly interior)
	field.dig_at(Vector3(4.0, 1.0, 1.0), 1.2)
	var dig_epoch_1 := field.get_dig_epoch()
	field._begin_mesh_batch()
	check(field.get_mesh_snapshot_epoch() == dig_epoch_1, "test4: snapshot epoch matches initial dig")
	check(field._mesh_groups.size() == 1, "test4: connected chunks grouped into single component")
	check(field._mesh_batch.size() == 2, "test4: batch has exactly the 2 connected boundary chunks")

	var grp_id: int = field._mesh_group_for[Vector3i(0, 0, 0)]
	check(field._mesh_group_for.get(Vector3i(1, 0, 0)) == grp_id, "test4: both boundary chunks share the same group id")
	check(field._mesh_group_remaining[grp_id] == 2, "test4: initial group remaining count is 2")

	# Next dig arriving while batch is in-flight
	field.dig_at(Vector3(4.2, 2.0, 2.0), 0.3)
	check(field.get_dig_epoch() == dig_epoch_1 + 1, "test4: next dig increments dig epoch")
	check(c_pos.is_dirty(), "test4: chunk becomes dirty again for next batch")

	# Remesh first chunk only
	var first_chunk: FDKChunk = field._mesh_batch[0]
	var second_chunk: FDKChunk = field._mesh_batch[1]
	field._reading_mesh_snapshot = true
	first_chunk.remesh(false, true)
	field._reading_mesh_snapshot = false

	field._mesh_group_remaining[grp_id] -= 1
	check(field._mesh_group_remaining[grp_id] == 1, "test4: group remaining is 1 after first chunk remesh")
	check(first_chunk.get_surface_edit_epoch() == 0, "test4: surface not published until whole group completes")

	# Remesh second chunk
	field._reading_mesh_snapshot = true
	second_chunk.remesh(false, true)
	field._reading_mesh_snapshot = false
	field._mesh_group_remaining[grp_id] -= 1
	check(field._mesh_group_remaining[grp_id] == 0, "test4: group remaining is 0 after all chunks remesh")

	# Atomic publish
	for ready in field._mesh_groups[grp_id]:
		ready.publish_staged_mesh()
	check(first_chunk.get_surface_edit_epoch() == dig_epoch_1, "test4: first chunk published with frozen epoch")
	check(second_chunk.get_surface_edit_epoch() == dig_epoch_1, "test4: second chunk published with frozen epoch")

	field._mesh_batch.clear()
	field._mesh_snapshot.clear()
	field._mesh_missing_snapshot.clear()
	field.remesh_all()

	# --- Test 5: Chunk Size s = 1 Edge Case ---
	var field1 := FDKTerrainField.new()
	field1.config = FDKTerrainConfig.new()
	field1.config.chunk_size = 1
	field1.config.cell_size = 1.0
	field1.density_sampler = func(_p: Vector3): return 1.0
	world.add_child(field1)
	field1.set_process(false)
	field1.generate_region(AABB(Vector3.ZERO, Vector3(2, 2, 2)))
	field1.remesh_all()

	field1.dig_at(Vector3(0.5, 0.5, 0.5), 0.4)
	field1._begin_mesh_batch()
	check(field1._mesh_batch.size() > 0, "test5: s=1 chunk mesh batch created successfully")
	field1._mesh_batch.clear()
	field1._mesh_snapshot.clear()
	field1._mesh_missing_snapshot.clear()
	field1.queue_free()

	# --- Test 6: Surface Topology, Collision Consistency, and Zero Open Edges ---
	var field2 := FDKTerrainField.new()
	field2.config = FDKTerrainConfig.new()
	field2.config.chunk_size = 4
	field2.config.cell_size = 1.0
	field2.density_sampler = func(_p: Vector3): return 1.0
	world.add_child(field2)
	field2.set_process(true)

	field2.generate_region(AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8)))
	field2.remesh_all()

	# Multiple digs across chunk boundaries and contraction
	field2.dig_at(Vector3(0.0, 0.0, 0.0), 1.5)
	field2.dig_at(Vector3(-1.0, 0.5, 0.0), 1.2)
	field2.dig_at(Vector3(1.0, -0.5, 0.5), 1.0)
	field2.contract_sphere(Vector3.ZERO, 1.8, 0.3)
	# Expensive preparation may use the budget, but the frozen batch must
	# make progress next tick even when continuing regeneration adds dirt.
	field2.remesh_ms_per_frame = 0.000001
	field2._process(0.1)
	check(not field2._mesh_batch.is_empty(), "budget: preparation preserves a pending batch")
	check(field2._mesh_batch_cursor == 0, "budget: no mesh build is added after preparation exceeds budget")
	var prepared_epoch := field2.get_mesh_snapshot_epoch()
	field2.regenerate_all(0.1, Vector3.ONE * 1000, 0.1)
	field2._process(0.1)
	check(field2._mesh_batch_cursor > 0, "budget: prepared batch progresses on the next tick")
	check(field2.get_mesh_snapshot_epoch() == prepared_epoch, "budget: regeneration cannot restart work in flight")

	# Process frames until all batches and collisions settle
	for step in range(30):
		field2._process(0.1)

	var all_surface_faces := PackedVector3Array()
	var all_collision_faces := PackedVector3Array()
	for ch in field2.get_chunks():
		var chunk_trans: Transform3D = ch.transform
		for pt in ch._surface_faces:
			all_surface_faces.append(chunk_trans * pt)
		if ch._collision != null and ch._collision.shape is ConcavePolygonShape3D:
			var cfaces = (ch._collision.shape as ConcavePolygonShape3D).get_faces()
			for pt in cfaces:
				all_collision_faces.append(chunk_trans * pt)

	check(all_surface_faces.size() > 0, "test6: surface generated mesh faces")
	check(all_surface_faces.size() % 3 == 0, "test6: surface faces form valid triangles")
	var open_edges := count_open_edges_from_faces(all_surface_faces)
	check(open_edges == 0, "test6: surface has exactly 0 open edges (closed manifold)")
	check(all_collision_faces.size() > 0, "test6: collision generated faces")
	check(all_collision_faces.size() % 3 == 0, "test6: collision faces form valid triangles")

	field2.queue_free()
	field.queue_free()
	world.queue_free()
	await process_frame

	print("%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
