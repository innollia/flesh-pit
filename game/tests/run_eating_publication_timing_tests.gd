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

func field_at_boundary() -> FDKTerrainField:
	var field := FDKTerrainField.new()
	field.config = FDKTerrainConfig.new()
	field.config.chunk_size = 4
	field.config.facet_jitter = 0.0
	field.density_sampler = func(p: Vector3): return clampf(p.z * 2.0 + 0.5, 0.0, 1.0)
	field.tissue_sampler = func(_p): return 0
	root.add_child(field)
	field.set_process(false)
	field.generate_region(AABB(Vector3(-2,-2,-2), Vector3(4,4,4)))
	field.remesh_all()
	field.remesh_budget_per_frame = 1
	return field

func run() -> void:
	var field := field_at_boundary()
	# An older ordinary update is already frozen; its unrelated corner
	# must not move early just because the player tears a nearby cell.
	var old_chunk: FDKChunk = field._chunks[Vector3i.ZERO]
	var unrelated := Vector3i(3,3,3)
	old_chunk.set_density_at_corner(3,3,3,0.8)
	field._begin_mesh_batch()
	var snapshot_epoch := field.get_mesh_snapshot_epoch()
	var original_cursor := field._mesh_batch_cursor
	check(not field._mesh_batch.is_empty(), "older ordinary batch exists")
	field.dig_at(Vector3(0.25,0.25,0.25),1.0)
	check(field._surface_patch == null, "external surface had no buried-volume patch")
	var edit_epoch := field.get_dig_epoch()
	field.queue_visible_tear(Vector3(0.25,0.25,0.25))
	var readers: Array = field._visible_tear_readers.values()
	check(readers.size() >= 2, "shared negative-boundary readers participate")
	field._process(1.0/60.0)
	for chunk in readers:
		check(chunk.get_surface_edit_epoch() == edit_epoch, "tear readers published latest edit together")
	check(field.get_mesh_snapshot_epoch() == snapshot_epoch, "ordinary frozen snapshot was retained")
	check(field._mesh_batch_cursor > original_cursor, "ordinary work still advances")
	check(field._visible_tear_readers.is_empty() and field._visible_tear_corners.is_empty(), "temporary tear data retired")
	check(is_equal_approx(old_chunk.get_published_corner_density(unrelated.x,unrelated.y,unrelated.z),1.0), "unrelated pending corner stays at its published value")
	check(is_equal_approx(field.corner_density_global(unrelated),0.8), "actual unrelated density was not changed by preview")
	var expected := field_at_boundary()
	expected.dig_at(Vector3(0.25,0.25,0.25),1.0)
	expected.remesh_all()
	for chunk in readers:
		var reference: FDKChunk = expected._chunks[chunk.chunk_coord]
		check(chunk._surface_faces == reference._surface_faces, "tear geometry equals coherent full publication, including shared boundaries")
		check(chunk._coll_density == chunk._surface_density, "tear collision and rendered geometry use the same snapshot")
	expected.queue_free()
	for z in range(2):
		for y in range(2):
			for x in range(2):
				var g := Vector3i(x,y,z)
				check(is_equal_approx(old_chunk.get_published_corner_density(x,y,z),field.corner_density_global(g)), "visible removed corner equals actual removal")
	# An older connected batch must never fill the new hole back in.
	for i in range(40):
		field._process(1.0/60.0)
		for chunk in readers:
			check(chunk.get_surface_edit_epoch() >= edit_epoch, "older work cannot resurrect removed flesh")
	check(is_equal_approx(old_chunk.get_published_corner_density(3,3,3),0.8), "normal publication eventually catches up unrelated update")
	check(field._mesh_batch.is_empty(), "ordinary batch completed instead of starving")
	field.queue_visible_tear(Vector3(0.25,0.25,0.25))
	field.remesh_all()
	check(field._visible_tear_readers.is_empty() and field._visible_tear_corners.is_empty(), "full restoration retires queued preview")
	field.queue_visible_tear(Vector3(0.25,0.25,0.25))
	field.deserialize(field.serialize())
	check(field._visible_tear_readers.is_empty() and field._visible_tear_corners.is_empty(), "load retires pre-load queued preview")
	field.queue_free()
	await process_frame
	print("%d passed, %d failed" % [passed,failed])
	quit(0 if failed == 0 else 1)
