extends SceneTree
## The real historical v5 slot is refused (decision 0012: old slots are not
## converted); a slot of the current format round-trips exactly.
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
	m.user_keybinds_path = "user://keybinds_test_restoration_old_v5_t10.json"
	m.save_path = path
	root.add_child(m)
	await process_frame
	m.save_path = path
	# decision 0012: a slot written before SAVE_VERSION is not converted. The
	# real historical v5 file is refused and the run stays a new game.
	check(int(original.version) == 5 and m.save_file_version() == 5 and not m.has_current_save(), "actual historical v5 slot is old: no continue offered")
	var fresh: Dictionary = m.serialize()
	check(not m.load_from_disk(), "actual historical v5 slot is refused")
	var first: Dictionary = m.serialize()
	check(first.progression == fresh.progression and first.stomach == fresh.stomach and first.terrain == fresh.terrain and first.death_drop == fresh.death_drop, "a refused old slot changes nothing in the new game")
	check(m.progression.total_hairs() == 0 and m.progression.teeth == 0 and first.progression.mutations == fresh.progression.mutations and first.progression.tools == fresh.progression.tools, "none of the old slot's hairs, teeth, mutations or tools arrive")
	check(FileAccess.get_sha256(path) == SHA, "refusing the old slot does not rewrite it")
	# a slot of the current format round-trips exactly
	m.progression.teeth = 9
	m.progression.on_flesh_eaten(0, 60.0)
	m.stomach.add_flesh(60.0)
	m.terrain.dig_at(Vector3(0.25, 1.25, 4.25), 1.0)
	first = m.serialize()
	check(int(first.version) == m.SAVE_VERSION and m.SAVE_VERSION == 7, "new slots are written as version 7")
	for index in range(2):
		check(m.save_to_disk() and m.has_current_save() and m.load_from_disk(), "real save/load roundtrip %d" % index)
		var after: Dictionary = m.serialize()
		check(after.progression == first.progression, "roundtrip %d progression idempotent" % index)
		check(after.death_drop == first.death_drop, "roundtrip %d drop idempotent" % index)
		check(after.stomach == first.stomach, "roundtrip %d stomach idempotent" % index)
		for entry in first.terrain.chunks:
			var c: Array = entry.chunk_coord
			var chunk: FDKChunk = m.terrain.get_chunk(Vector3i(c[0],c[1],c[2]))
			var actual: Dictionary = chunk.serialize()
			check(actual.density == entry.density and actual.tissue == entry.tissue and actual.sealed == entry.sealed and actual.boost == entry.boost, "roundtrip %d actual density/tissue/sealed/boost %s" % [index,c])
	m.queue_free()
	await process_frame
	print("T10 actual old v5: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
