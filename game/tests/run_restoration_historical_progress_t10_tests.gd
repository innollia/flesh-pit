extends SceneTree
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
	m.save_path = path
	root.add_child(m)
	await process_frame
	m.save_path = path
	check(m.load_from_disk(),name + " actual disk load")
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
	check(m.progression.hair_carry.common == 44.0 and m.progression.hair_carry.mantle == 44.0,"legacy pending is already weighted, retained 44 without fourfold units")
	check(m.progression.total_hairs() == 0 and m.progression.pending_hair_total() == 0,"subthreshold historical pending migrates to carry once")
	check(m.progression.serialize().migrated_v5_hairs,"historical pending marker persisted")
	await roundtrips("pending")
	old = await load_fixture("drop",6725192,"3e798d23effd2ba59e1cf21a53b78af8602377b8edf7290521d4096a9b5a9226")
	check(m.death_drop.active and m.death_drop.items.pending_hairs.common == 13,"actual historical positive death drop remains recoverable")
	check(m.progression.tools.serialize() == old.progression.tools,"actual historical owned tools preserved")
	await roundtrips("drop before recovery")
	# Initial approach fixture after exact historical terrain roundtrips. The
	# drop/items remain historical; actual normal movement recovers it.
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.terrain.fill_box_uniform(AABB(Vector3(-0.25,0.1,2.0),Vector3(1.5,2.5,2.5)),0.0,0)
	m.terrain.remesh_all()
	m.player.global_position = Vector3(0.5,0.9,2.1)
	m.player._yaw = PI
	m.player.rotation.y = PI
	m.player._pitch = 0.0
	m.player.camera_pivot.rotation.x = 0.0
	await frames(2)
	var fill_before: float = m.stomach.fill
	var barriers_before: int = m.progression.barriers
	Input.action_press("fdk_move_forward")
	for i in range(30):
		await physics_frame
		if not m.death_drop.active: break
	Input.action_release("fdk_move_forward")
	await frames(2)
	check(not m.death_drop.active,"actual approach movement recovers historical drop")
	check(is_equal_approx(m.stomach.fill - fill_before,47.0),"actual historical stomach payload recovered once")
	check(m.progression.hair_carry.common == 20.0 and m.progression.hair_carry.core == 6.0 and m.progression.hair_carry.mantle == 14.0,"historical drop 13/5/8 is weighted once with old carry 7/1/6")
	check(m.progression.barriers == barriers_before + 2,"historical consumable barriers recovered")
	check(m.progression.sprays.cans.size() == 1 and m.progression.sprays.cans[0].uses_left == 5,"historical cheap spray remaining uses recovered")
	var recovered: Dictionary = m.progression.serialize()
	await frames(12)
	check(m.progression.serialize() == recovered and is_equal_approx(m.stomach.fill - fill_before,47.0),"standing at consumed drop does not duplicate rewards")
	await roundtrips("drop after recovery")
	m.queue_free()
	await frames(2)
	print("T10 historical progress: %d passed, %d failed" % [passed,failed])
	quit(1 if failed else 0)
