extends SceneTree
## Real historical v5 slots (pending hair flesh, a positive death drop) are
## not converted (decision 0012): each is refused, nothing of it arrives and
## the file is left as it is. The new game then round-trips on disk.
var m: Node3D
var passed := 0
var failed := 0
var folder: String
func _init() -> void:
	Engine.max_fps = 60
	if not OS.get_user_data_dir().contains("flesh-pit-restoration-"):
		quit(2)
		return
	folder = ProjectSettings.globalize_path("res://../.dryforge/evidence/T10/historical-progress")
	DirAccess.make_dir_recursive_absolute(folder)
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL: ",label)
func frames(count: int) -> void:
	for i in range(count): await physics_frame
	await process_frame
func load_fixture(name: String, size: int, sha: String) -> Dictionary:
	if is_instance_valid(m):
		m.queue_free()
		await frames(2)
	var path := folder.path_join(name + ".bin")
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/restoration_historical_" + name + "_v5.bin.gz").decompress(size,FileAccess.COMPRESSION_GZIP)
	var out := FileAccess.open(path,FileAccess.WRITE)
	out.store_buffer(bytes)
	out.close()
	check(bytes.size() == size and FileAccess.get_sha256(path) == sha, name + " actual archive save hash and length")
	var input := FileAccess.open(path,FileAccess.READ)
	var old: Dictionary = input.get_var()
	input.close()
	check(int(old.version) == 5 and not old.progression.has("migrated_v5_hairs"), name + " actual unmigrated historical schema")
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_restoration_historical_progress_t10.json"
	m.save_path = path
	root.add_child(m)
	await process_frame
	m.save_path = path
	# decision 0012: old slots are not converted. The file is refused and the
	# run stays a new game; the file itself is left as it is.
	check(m.save_file_version() == 5 and not m.has_current_save(), name + " historical slot is old: no continue offered")
	var fresh: Dictionary = m.serialize()
	check(not m.load_from_disk(), name + " historical slot is refused")
	var now: Dictionary = m.serialize()
	check(now.progression == fresh.progression and now.death_drop == fresh.death_drop and now.stomach == fresh.stomach, name + " refusal leaves the new game untouched")
	check(FileAccess.get_sha256(path) == sha, name + " refusal does not rewrite the file")
	return old
func roundtrips(label: String) -> void:
	var first: Dictionary = m.serialize()
	for i in range(2):
		check(m.save_to_disk() and m.load_from_disk(), label + " real disk roundtrip " + str(i))
		var next: Dictionary = m.serialize()
		check(next.progression == first.progression, label + " points/carry/items/mutations idempotent " + str(i))
		check(next.death_drop == first.death_drop, label + " actual death drop idempotent " + str(i))
		check(next.terrain == first.terrain, label + " actual terrain preserved " + str(i))
func run() -> void:
	var old: Dictionary = await load_fixture("pending",8611924,"4b6fee00e487d006f95981d71c766ab3700be7c4e1e3698353fa94c61a9b8fb1")
	check(old.progression.pending_hairs.common == 44 and old.progression.pending_hairs.mantle == 44,"actual historical weighted pending 44+44")
	check(m.progression.total_hairs() == 0 and m.progression.pending_hair_total() == 0 and float(m.progression.hair_carry.get("common", 0.0)) == 0.0 and float(m.progression.hair_carry.get("mantle", 0.0)) == 0.0,"none of the old pending flesh arrives: no hairs, no carry")
	await roundtrips("new game after refused pending slot")
	old = await load_fixture("drop",6725192,"3e798d23effd2ba59e1cf21a53b78af8602377b8edf7290521d4096a9b5a9226")
	check(bool(old.death_drop.active) and not m.death_drop.active,"the old slot's death drop is not in the new game")
	check(m.progression.tools.serialize() != old.progression.tools and m.progression.barriers == 0 and m.progression.sprays.cans.is_empty(),"the old slot's tools and consumables do not arrive")
	await roundtrips("new game after refused drop slot")
	m.queue_free()
	await frames(2)
	print("T10 historical progress: %d passed, %d failed" % [passed,failed])
	quit(1 if failed else 0)
