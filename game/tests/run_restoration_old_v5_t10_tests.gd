extends SceneTree
var m: Node3D
var passed := 0
var failed := 0
var folder: String
var path: String
const SHA := "71946d862fd19b6e17c9ddd12880c8838b7664da00c07c3e057e052bd6385f02"
func _init() -> void:
	if not OS.get_user_data_dir().contains("flesh-pit-restoration-"):
		quit(2)
		return
	folder = ProjectSettings.globalize_path("res://../.dryforge/evidence/T10/old-v5")
	DirAccess.make_dir_recursive_absolute(folder)
	path = folder.path_join("isolated-historical.bin")
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL: ", label)
func run() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/terrain_old_v5.bin.gz").decompress(6722764, FileAccess.COMPRESSION_GZIP)
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_buffer(bytes)
	out.close()
	check(bytes.size() == 6722764 and FileAccess.get_sha256(path) == SHA, "exact historical v5 byte length and hash")
	var input := FileAccess.open(path, FileAccess.READ)
	var original: Dictionary = input.get_var()
	input.close()
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = path
	root.add_child(m)
	await process_frame
	m.save_path = path
	check(m.load_from_disk(), "actual historical disk load")
	var first: Dictionary = m.serialize()
	check(first.progression.migrated_v5_hairs, "actual historical old marker migrated")
	check(m.progression.total_hairs() == 0, "actual historical zero pending does not recreate discarded hair")
	check(first.progression.tools == original.progression.tools and first.progression.hands == original.progression.hands, "historical tools and hand items preserved")
	check(first.progression.mutations == original.progression.mutations, "historical purchased mutations and points preserved")
	check(first.death_drop.items == original.death_drop.items, "historical death-drop contents preserved")
	for index in range(2):
		check(m.save_to_disk() and m.load_from_disk(), "real save/load roundtrip %d" % index)
		var after: Dictionary = m.serialize()
		check(after.progression == first.progression, "roundtrip %d progression idempotent" % index)
		check(after.death_drop == first.death_drop, "roundtrip %d drop idempotent" % index)
		check(after.stomach == first.stomach, "roundtrip %d stomach idempotent" % index)
		for entry in first.terrain.chunks:
			var c: Array = entry.chunk_coord
			var chunk: FDKChunk = m.terrain.get_chunk(Vector3i(c[0],c[1],c[2]))
			var actual: Dictionary = chunk.serialize()
			check(actual.density == entry.density and actual.tissue == entry.tissue and actual.sealed == entry.sealed and actual.boost == entry.boost, "roundtrip %d historical actual density/tissue/sealed/boost %s" % [index,c])
	m.queue_free()
	await process_frame
	print("T10 actual old v5: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
