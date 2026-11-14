extends SceneTree

## Vent: the absurd-overpay spill shows (audit 1-2) and the vent's held offer
## and last line survive a save (audit section 2), old saves still load.
## Run: Godot_console.exe --headless --path <project> --script tests/run_vent_save_tests.gd
## Saves go to <repo>/.dryforge/evidence/vent_save/ only (never the player's slot).

var passed := 0
var failed := 0
var folder: String
var m: Node3D

func _init() -> void:
	print("=== flesh-pit vent spill + save tests ===")
	folder = ProjectSettings.globalize_path("res://../.dryforge/evidence/vent_save")
	DirAccess.make_dir_recursive_absolute(folder)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
	await process_frame

func run() -> void:
	_held_roundtrip()
	_spill()
	await _old_file()
	if is_instance_valid(m):
		m.queue_free()
		await frames(2)
	print("--- %d passed, %d failed ---" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _vent() -> FPVent:
	var v := FPVent.new()
	v.instant_voice = true
	root.add_child(v)
	return v

## Spec 03 §7: left unpicked, the same offer comes back next time, a load
## in between or not.
func _held_roundtrip() -> void:
	var p := FPProgression.new()
	p.deepest_shell = 0
	var v := _vent()
	v.open(8)
	var o := v.place_teeth(8, p)
	check(not o.is_empty(), "an offer is held out (%s)" % [o])
	v.close()
	var d := v.serialize_progress()
	check(d.get("held", []) == o, "closing unpicked: the held offer is saved (%s)" % [d.get("held")])
	check(String(d.get("last_line", "")) == "leave.close" and v.last_line == "leave.close", "the last line is saved (%s)" % [d.get("last_line")])
	var w := _vent()
	w.restore_progress(d, true)
	check(w.held_offers() == o and w.last_line == "leave.close", "a loaded vent remembers the held offer and its last line")
	check(w.trade_paid == 0, "the paid teeth stay with the being, not paid again (%d)" % w.trade_paid)
	w.open(0)
	check(w.offers == o, "after a load the being holds out the same items again (%s vs %s)" % [w.offers, o])
	check(int(w.art.get("_count")) == o.size(), "one hand per re-offered item (%d)" % int(w.art.get("_count")))
	# saved while the offer is still held out: same thing on the next open
	var x := _vent()
	x.open(8)
	var o2 := x.place_teeth(8, p)
	var d2 := x.serialize_progress()
	check(d2.get("held", []) == o2, "an offer still held out when saving is kept (%s)" % [d2.get("held")])
	var y := _vent()
	y.restore_progress(d2, true)
	y.open(0)
	check(y.offers == o2, "it comes back on the first open after the load (%s)" % [y.offers])
	# taking the item clears it: nothing comes back
	y.take(o2[0], p)
	check(y.serialize_progress().get("held", ["x"]).is_empty(), "a taken offer is not saved as held")
	# older saves: no held, no last line
	var z := _vent()
	z.restore_progress({"met": true, "first_flush_heard": true, "paid_ever": true, "trade_paid": 3}, true)
	check(z.held_offers().is_empty() and z.last_line == "" and z.trade_paid == 3, "an old vent_progress (no held/last_line) loads")
	var old := _vent()
	old.restore_progress({}, false)
	check(old.held_offers().is_empty() and not old._met, "a save without vent_progress loads")
	# unknown ids in a damaged save are dropped, never offered
	var bad := _vent()
	bad.restore_progress({"met": true, "held": ["knife", "not_an_item", 5]}, true)
	check(bad.held_offers() == (["knife"] as Array[String]), "only real item ids come back (%s)" % [bad.held_offers()])
	for n in [v, w, x, y, z, old, bad]:
		n.queue_free()

## Audit 1-2: an absurd overpay spills early items out of the duct; they
## land on the floor under the vent, then go to the waist, and the
## inventory is exactly what the grant gave.
func _spill() -> void:
	var q := FPProgression.new()
	var v := _vent()
	v.position = FPRestroom.VENT_CENTER - Vector3(0, 0.03, 0)
	v.open(999)
	var heard := []
	v.spilled.connect(func(ids): heard.append(ids))
	var sp := q.vent_spill()
	var sprays0: int = q.sprays.count()
	v.place_teeth(q.vent_absurd_threshold(), q)
	check(heard.size() == 1 and heard[0] == sp, "spilled still fires with the granted ids (%s)" % [heard])
	check(q.barriers == 1 and q.owns("knife") and q.canary_feed == 1, "the spill is granted exactly as before")
	check(q.sprays.count() == sprays0 + 1, "one cheap spray from the spill")
	var art := v.art
	check(art.has_method("spill_count") and int(art.call("spill_count")) == sp.size(), "one falling item per spilled item (%s)" % [art.call("spill_count") if art.has_method("spill_count") else "none"])
	if not art.has_method("spill_count"):
		v.queue_free()
		return
	check(int(art.get("_count")) > 0, "the offer hands still come down with it")
	var nodes: Array = art.call("spill_nodes")
	var lowest := INF
	for i in range(int(2.2 * 60.0)):
		art.call("step_spill", 1.0 / 60.0)
	var landed := 0
	var under := 0
	for n in nodes:
		var g: Vector3 = (n as Node3D).global_position
		lowest = minf(lowest, g.y)
		if (n as Node3D).visible and absf(g.y - 0.03) < 0.02:
			landed += 1
		if Vector2(g.x - FPRestroom.VENT_CENTER.x, g.z - FPRestroom.VENT_CENTER.z).length() < 1.2:
			under += 1
	check(landed == nodes.size(), "every spilled item lies on the room floor (%d/%d, lowest y %.2f)" % [landed, nodes.size(), lowest])
	check(under == nodes.size(), "they land near the vent, inside the room")
	check(int(art.call("spill_count")) == sp.size(), "they lie there a moment before going")
	var k: Dictionary = art.get_script().get_script_constant_map()
	for i in range(int((float(k["SPILL_REST"]) + float(k["SPILL_STOW"]) + 0.2) * 60.0)):
		art.call("step_spill", 1.0 / 60.0)
	check(int(art.call("spill_count")) == 0, "then each goes to the waist and is gone from the floor")
	check(q.barriers == 1 and q.canary_feed == 1, "the inventory is unchanged by the show")
	v.queue_free()

## A copy of a real historical v5 save (no vent_progress at all) is refused
## (decision 0012: old slots are not converted) and the run stays a new game
## with nothing held; then a held offer and last line go through a real disk
## save and load of the current format.
func _old_file() -> void:
	var path := folder.path_join("old_pending.bin")
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/restoration_historical_pending_v5.bin.gz").decompress(8611924, FileAccess.COMPRESSION_GZIP)
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_buffer(bytes)
	out.close()
	check(FileAccess.get_sha256(path) == "4b6fee00e487d006f95981d71c766ab3700be7c4e1e3698353fa94c61a9b8fb1", "the copy is the archived historical save")
	await _load(path, false)
	check(m.vent.held_offers().is_empty() and m.vent.last_line == "", "old file: nothing held, nothing said")
	check(not m.serialize().is_empty() and m.serialize().vent_progress.get("held", ["x"]).is_empty(), "old file: saves an empty held offer")
	var prog: FPProgression = m.progression
	m.vent.instant_voice = true
	m.vent._met = true
	m.vent.open(10)
	var o: Array[String] = m.vent.place_teeth(8, prog)
	m.vent.close()
	check(not o.is_empty() and m.vent.held_offers() == o, "an offer is left unpicked (%s)" % [o])
	var line: String = m.vent.last_line
	check(m.save_to_disk(), "real disk save")
	await _load(path)
	check(m.vent.held_offers() == o and m.vent.last_line == line, "after a real load the vent still holds %s and remembers '%s' (%s, '%s')" % [o, line, m.vent.held_offers(), m.vent.last_line])
	m.vent.instant_voice = true
	m.vent.open(0)
	check(m.vent.offers == o, "the being holds out the same items after the load (%s)" % [m.vent.offers])

func _load(path: String, current: bool = true) -> void:
	if is_instance_valid(m):
		m.queue_free()
		await frames(2)
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_vent_save.json"
	m.save_path = path
	root.add_child(m)
	await process_frame
	m.save_path = path
	if current:
		check(m.load_from_disk(), "load " + path.get_file())
	else:
		check(m.save_file_version() == 5 and not m.has_current_save() and not m.load_from_disk(), "old slot refused: " + path.get_file())
	await frames(2)
