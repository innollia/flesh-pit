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

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var field := FDKTerrainField.new()
	field.config = FDKTerrainConfig.new()
	field.config.chunk_size = 4
	field.config.cell_size = 1.0
	field.density_sampler = func(_p: Vector3): return 1.0
	world.add_child(field)
	field.set_process(false)

	# --- Test 1: Initial epoch state and dig_at increment ---
	check(field.get_dig_epoch() == 0, "field initial dig_epoch is 0")
	check(field.get_mesh_snapshot_epoch() == 0, "field initial snapshot_epoch is 0")

	field.generate_region(AABB(Vector3.ZERO, Vector3(8, 4, 4)))
	field.remesh_all()

	var chunk0: FDKChunk = field.get_chunk(Vector3i(0, 0, 0))
	var chunk1: FDKChunk = field.get_chunk(Vector3i(1, 0, 0))
	check(chunk0 != null, "chunk (0,0,0) exists")
	check(chunk1 != null, "chunk (1,0,0) exists")
	check(chunk0.get_surface_edit_epoch() == 0, "chunk0 initial surface_edit_epoch is 0")
	check(chunk0.get_staged_edit_epoch() == 0, "chunk0 initial staged_edit_epoch is 0")
	check(chunk1.get_surface_edit_epoch() == 0, "chunk1 initial surface_edit_epoch is 0")

	field.dig_at(Vector3(1.5, 1.5, 1.5), 0.4)
	check(field.get_dig_epoch() == 1, "dig_at increments dig_epoch to 1")
	check(chunk0.is_dirty(), "chunk0 is dirty after dig_at")

	# --- Test 2: Freeze snapshot, adjacent next dig, old batch keeps old epoch ---
	# 2a. Begin mesh batch freezes mesh_snapshot_epoch to current dig epoch (1)
	field._begin_mesh_batch()
	check(field.get_mesh_snapshot_epoch() == 1, "batch freeze sets mesh_snapshot_epoch to 1")
	check(not chunk0.is_dirty(), "chunk0 dirty cleared upon batch freeze")

	# 2b. Adjacent next dig during batch increments dig epoch to 2, marks chunk0 dirty again
	field.dig_at(Vector3(1.8, 1.5, 1.5), 0.3)
	check(field.get_dig_epoch() == 2, "next dig increments dig_epoch to 2")
	check(chunk0.is_dirty(), "next dig during old batch leaves chunk0 dirty")

	# 2c. Old batch remesh (reading frozen snapshot epoch 1)
	field._reading_mesh_snapshot = true
	chunk0.remesh(false, true)
	field._reading_mesh_snapshot = false

	check(chunk0.get_staged_edit_epoch() == 1, "staged edit epoch is frozen old epoch 1, not new epoch 2")
	check(chunk0.get_surface_edit_epoch() == 0, "surface edit epoch not updated before publish")

	# 2d. Publish staged mesh delivers frozen old epoch to surface
	chunk0.publish_staged_mesh()
	check(chunk0.get_surface_edit_epoch() == 1, "published surface edit epoch is old epoch 1, not new epoch 2")
	check(chunk0.get_staged_edit_epoch() == 0, "staged edit epoch cleared after publish")
	check(chunk0.is_dirty(), "chunk0 remains dirty from next dig after old batch publish")

	# 2e. Finish old batch and begin next batch
	field._mesh_batch.clear()
	field._mesh_snapshot.clear()
	field._mesh_missing_snapshot.clear()

	field._begin_mesh_batch()
	check(field.get_mesh_snapshot_epoch() == 2, "next batch freezes mesh_snapshot_epoch to new epoch 2")

	field._reading_mesh_snapshot = true
	chunk0.remesh(false, true)
	field._reading_mesh_snapshot = false

	check(chunk0.get_staged_edit_epoch() == 2, "next batch staged epoch is 2")
	chunk0.publish_staged_mesh()
	check(chunk0.get_surface_edit_epoch() == 2, "next batch publish reaches new epoch 2")

	field._mesh_batch.clear()
	field._mesh_snapshot.clear()
	field._mesh_missing_snapshot.clear()

	# --- Test 3: remesh_all updates dirty chunk to current epoch, clean chunk untouched ---
	# chunk0 surface epoch is 2, clean. chunk1 surface epoch is 0, clean.
	check(not chunk0.is_dirty(), "chunk0 is clean")
	check(not chunk1.is_dirty(), "chunk1 is clean")
	check(chunk1.get_surface_edit_epoch() == 0, "chunk1 surface epoch is 0")

	# Dig strictly inside chunk0
	field.dig_at(Vector3(1.0, 1.0, 1.0), 0.2)
	check(field.get_dig_epoch() == 3, "dig_epoch incremented to 3")
	check(chunk0.is_dirty(), "chunk0 is dirty from dig")
	check(not chunk1.is_dirty(), "chunk1 remains clean")

	# remesh_all should remesh dirty chunk0 to current epoch 3, but leave clean chunk1 untouched
	field.remesh_all()
	check(chunk0.get_surface_edit_epoch() == 3, "remesh_all updated dirty chunk0 to current epoch 3")
	check(chunk1.get_surface_edit_epoch() == 0, "remesh_all did NOT falsely update clean chunk1 epoch")

	# --- Test 4: Standalone chunk safety (field == null) ---
	var standalone := FDKChunk.new()
	standalone.setup(Vector3i.ZERO, field.config)
	world.add_child(standalone)
	check(standalone.field == null, "standalone chunk has null field")
	standalone.fill_uniform(0.6, 0)
	check(standalone.get_surface_edit_epoch() == 0, "standalone chunk initial surface epoch is 0")

	# Staged remesh on standalone chunk
	standalone.remesh(false, true)
	check(standalone.get_staged_edit_epoch() == 0, "standalone chunk staged epoch is safe 0")
	standalone.publish_staged_mesh()
	check(standalone.get_surface_edit_epoch() == 0, "standalone chunk surface epoch remains safe 0")

	# Direct remesh on standalone chunk
	standalone.remesh(true, false)
	check(standalone.get_surface_edit_epoch() == 0, "standalone direct remesh surface epoch remains safe 0")

	world.remove_child(standalone)
	standalone.queue_free()

	# --- Test 5: Deserialize clears pending without resetting epochs ---
	var epoch_before_save := field.get_dig_epoch()
	var chunk0_epoch_before := chunk0.get_surface_edit_epoch()
	check(epoch_before_save == 3, "epoch before save is 3")
	check(chunk0_epoch_before == 3, "chunk0 epoch before save is 3")

	var save_data := field.serialize()
	field.deserialize(save_data)

	check(field.get_dig_epoch() == 3, "deserialize did not reset field dig_epoch")
	check(chunk0.get_surface_edit_epoch() == 3, "deserialize did not reset chunk surface_edit_epoch")

	# --- Test 6: Serialization format and mesh density/geometry unchanged ---
	check(save_data.has("chunks"), "save data has chunks key")
	check(save_data.has("version"), "save data has version key")
	check(not save_data.has("_dig_epoch"), "save data does not contain _dig_epoch key")
	check(not save_data.has("dig_epoch"), "save data does not contain dig_epoch key")

	var chunk_data: Dictionary = (save_data["chunks"] as Array)[0]
	check(chunk_data.has("chunk_coord"), "chunk data has chunk_coord")
	check(chunk_data.has("density"), "chunk data has density")
	check(chunk_data.has("tissue"), "chunk data has tissue")
	check(chunk_data.has("sealed"), "chunk data has sealed")
	check(chunk_data.has("boost"), "chunk data has boost")
	check(not chunk_data.has("surface_edit_epoch"), "chunk data does not serialize surface_edit_epoch")
	check(not chunk_data.has("_surface_edit_epoch"), "chunk data does not serialize _surface_edit_epoch")
	check(not chunk_data.has("staged_edit_epoch"), "chunk data does not serialize staged_edit_epoch")
	check(not chunk_data.has("_staged_edit_epoch"), "chunk data does not serialize _staged_edit_epoch")

	# Mesh triangles and densities geometry verification
	var faces_count := chunk0._surface_faces.size()
	check(faces_count > 0, "chunk0 has published surface faces")
	check(faces_count % 3 == 0, "chunk0 surface faces form valid triangles")
	check(chunk0._surface_density.size() > 0, "chunk0 has published surface density")

	world.queue_free()
	await process_frame

	print("%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
