extends SceneTree

## Tags over the vent's offered items (user 2026-11-09): each item held out
## gets a tag above it with its name and how many it gives, plus what it
## does; none while nothing is held out or after the pick. Tags sit above
## their own item, do not overlap one another and do not cover an item.
## Isolated save; the normal game loop runs.

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://vent-labels-test.bin"
	m.user_keybinds_path = "user://vent-labels-test-keys.json"
	root.add_child(m)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func wait(secs: float) -> void:
	var t := 0.0
	while t < secs:
		await process_frame
		t += root.get_process_delta_time()

func look_at_point(p: Vector3) -> void:
	var d: Vector3 = p - m.player.camera.global_position
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

func offer(ids: Array) -> void:
	var typed: Array[String] = []
	for id in ids:
		typed.append(String(id))
	m.vent._set_offers(typed)

func item_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	for i in range(m.vent.offers.size()):
		out.append(m.offer_labels._screen_box(cam, m.vent.art.call("item_node", i)))
	return out

func layout_ok(what: String) -> void:
	var tags: Array[Rect2] = m.offer_labels.tag_rects()
	var items := item_rects()
	check(tags.size() == m.vent.offers.size(), "%s: one tag per item (%d/%d)" % [what, tags.size(), m.vent.offers.size()])
	var view: Rect2 = root.get_viewport().get_visible_rect()
	for i in range(tags.size()):
		check(view.encloses(tags[i]), "%s: tag %d on screen" % [what, i])
		check(tags[i].size.y >= 14.0, "%s: tag %d readable height (%.0f px)" % [what, i, tags[i].size.y])
		for j in range(tags.size()):
			if j > i:
				check(not tags[i].intersects(tags[j]), "%s: tags %d and %d do not overlap" % [what, i, j])
		for j in range(items.size()):
			# a tag may graze the outline's corner, never its middle
			var core := items[j].grow_individual(-items[j].size.x * 0.2, -items[j].size.y * 0.2, -items[j].size.x * 0.2, -items[j].size.y * 0.2)
			check(not tags[i].intersects(core), "%s: tag %d clear of item %d" % [what, i, j])
		if i < items.size():
			check(tags[i].end.y <= items[i].position.y + items[i].size.y * 0.25, "%s: tag %d above its item" % [what, i])

func run() -> void:
	root.size = Vector2i(1280, 720)
	await frames(5)
	m.finish_opening()
	m.restroom.set_door_open(false, true)
	m.vent.instant_voice = true
	# data: every offerable id has a name, the count is what one pick gives
	var ids: Array = FPProgression.PRICE_UNITS.keys()
	ids.append("junk")
	for id in ids:
		check(FPOfferLabels.item_name(id) != id and FPOfferLabels.item_name(id) != "", "name for %s" % id)
		check(FPOfferLabels.item_use(id) != "" or FPOfferLabels.item_use_key(id) != "", "use line or its key for %s" % id)
		check(not FPOfferLabels.item_use(id).contains("item.") and FPOfferLabels.item_use(id) != FPOfferLabels.item_use_key(id), "%s: the placeholder key is never the line on its tag (%s)" % [id, FPOfferLabels.item_use(id)])
	check(FPOfferLabels.head_text(["knife", "barrier"], "knife").ends_with("×1"), "one pick gives one")
	m.player.global_position = Vector3(0.3, 0.9, 0.3)
	await physics_frame
	await frames(3)
	look_at_point(FPRestroom.VENT_CENTER + Vector3(0, -0.2, 0))
	await frames(3)
	check(m.offer_labels.tags_shown() == 0, "no tags with the vent shut")
	m.vent.open(30)
	await frames(30)
	check(m.offer_labels.tags_shown() == 0, "no tags with the vent open and nothing held out")
	offer(["knife", "spray_cheap", "barrier"])
	await frames(2)
	check(m.offer_labels.tags_shown() == 0, "no tags while the arms are still coming down")
	await wait(1.2)
	check(m.offer_labels.tags_shown() == 3, "a tag per item once held out (%d)" % m.offer_labels.tags_shown())
	var head: PackedStringArray = m.offer_labels.tag_texts(0)
	check(head.size() == 2 and head[0] == "칼 ×1", "first tag names the knife and its count (%s)" % [head])
	# the head goes in as the game does it after paying
	m._interact()
	await wait(1.2)
	check(m.hand_motions.vent_looking(), "head in under the vent")
	await frames(3)
	check(m.offer_labels.tags_shown() == 3, "tags stay with the head in")
	layout_ok("three, head in")
	for group in [["canary_feed", "spray_deep", "tumor_bag"], ["blender", "junk"], ["big_saw"]]:
		offer(group)
		await wait(1.2)
		layout_ok(", ".join(group))
	# an item whose line is not written shows its name alone, never a key
	FPOfferLabels._data = {"pouch": {"이름": "이빨 주머니", "하는일": "", "하는일_키": "item.pouch.desc"}, "knife": {"이름": "칼", "하는일": "질긴 막과 살을 뜯음", "하는일_키": "item.knife.desc"}}
	offer(["pouch", "knife"])
	await wait(1.2)
	check(m.offer_labels.tags_shown() == 2, "the pouch and the knife are tagged (%d)" % m.offer_labels.tags_shown())
	var bare: PackedStringArray = m.offer_labels.tag_texts(0)
	check(bare.size() == 1 and bare[0] == "이빨 주머니 ×1", "an unwritten line leaves the name alone on the tag (%s)" % [bare])
	check(m.offer_labels.tag_texts(1).size() == 2, "a written line is still the tag's second line")
	FPOfferLabels._data = {}
	offer(["pouch", "tumor_bag", "junk"])
	await wait(1.2)
	for i in range(3):
		for line in m.offer_labels.tag_texts(i):
			check(not line.contains("item."), "no key on tag %d (%s)" % [i, line])
	# taking one: the rest go back, no tags
	offer(["knife", "spray_cheap", "barrier"])
	await wait(1.2)
	check(m.vent.take("barrier", m.progression), "take the barrier")
	await frames(2)
	check(m.offer_labels.tags_shown() == 0, "no tags after the pick")
	print("--- vent labels: %d passed, %d failed ---" % [passed, failed])
	for f in ["user://vent-labels-test.bin", "user://vent-labels-test-keys.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	m.queue_free()
	await frames(2)
	quit(1 if failed > 0 else 0)
