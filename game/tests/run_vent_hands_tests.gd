extends SceneTree

## The vent being's hands (user 2026-11-03):
## 1. the offer is held out close in front of the eye ("가까이서 보게"),
## 2. one hand per offered item, three or more, each an aim point of its own,
## 3. bright skin (brighter than the player's own),
## 4. the wrist stays near the forearm line all the way down,
## 5. no eyes in the duct, in any state.
## The trade itself (F takes the aimed item, the others go back up) holds.

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_vent_hands.json"
	m.save_path = "user://vent-hands-test.bin"
	root.add_child(m)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("ok: ", label)
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
		t += get_root().get_process_delta_time()

func look_at_point(p: Vector3) -> void:
	var eye: Vector3 = m.player.camera.global_position
	var d := p - eye
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

func offer(ids: Array) -> void:
	var typed: Array[String] = []
	for id in ids:
		typed.append(String(id))
	m.vent._set_offers(typed)

## No eye geometry anywhere under the vent, and nothing named like one shows.
func eyes_shown() -> int:
	var n := 0
	for c in m.vent.find_children("Eye*", "", true, false):
		if (c as Node3D).is_visible_in_tree():
			n += 1
	for c in m.vent.find_children("Pupil*", "", true, false):
		if (c as Node3D).is_visible_in_tree():
			n += 1
	return n

func luminance(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

func run() -> void:
	await frames(5)
	m.finish_opening()
	var art: Node3D = m.vent.art
	m.player.global_position = Vector3(0.1, 0.9, 0.2)
	await frames(3)
	# --- 5. no eyes: closed, open, frantic after a flush, calm after paying
	check(eyes_shown() == 0, "no eyes with the grate shut")
	m.vent.on_flush()
	m.vent.open(30)
	await frames(30)
	check(m.vent.mood() == "frantic" and eyes_shown() == 0, "no eyes in the open duct, frantic after a flush")
	check(art.find_children("Eye*", "", true, false).is_empty(), "the vent art builds no eyes at all")
	art.call("set_eyes", true)
	await frames(2)
	check(eyes_shown() == 0, "asking for the eyes still shows none")
	# --- 2. one hand per item, three and more
	for ids in [["knife", "spray_cheap", "barrier"], ["barrier", "spray_cheap", "knife", "canary_feed", "junk"], ["barrier", "spray_cheap", "knife", "spray_deep", "blender", "big_saw", "canary_feed", "tumor_bag"], ["spray_deep"]]:
		offer(ids)
		await wait(1.7)
		var hands: int = art.call("hand_count")
		check(hands == ids.size(), "%d items come out in %d hands" % [ids.size(), hands])
		var own := true
		var seen := {}
		for i in range(ids.size()):
			var item: Node3D = art.call("item_node", i)
			var hand: Node3D = item.get_parent()
			own = own and item.is_visible_in_tree() and hand.name == "Palm" and not seen.has(hand)
			seen[hand] = true
		check(own, "each of the %d items lies in a hand of its own" % ids.size())
		# held, not floating: the fingertips close on the item (index and
		# middle tips within a few centimetres of it, in front of the palm)
		var grip := 0.0
		for i in range(ids.size()):
			var item: Node3D = art.call("item_node", i)
			var hand: Node3D = item.get_parent()
			for f in ["Finger0/Mid/Tip", "Finger1/Mid/Tip"]:
				var tip: Node3D = hand.get_node(f)
				var tip_end: Vector3 = tip.global_transform * Vector3(0, -0.02, 0)
				grip = maxf(grip, tip_end.distance_to(item.global_position))
		# spread: seen from the eye no two items sit on top of each other
		var eye0: Vector3 = m.player.camera.global_position
		var closest := PI
		for i in range(ids.size()):
			for j in range(i + 1, ids.size()):
				var di: Vector3 = ((art.call("item_node", i) as Node3D).global_position - eye0).normalized()
				var dj: Vector3 = ((art.call("item_node", j) as Node3D).global_position - eye0).normalized()
				closest = minf(closest, di.angle_to(dj))
		if ids.size() > 1:
			check(closest > deg_to_rad(9.0), "the %d held items read apart from the eye (closest %.1f°)" % [ids.size(), rad_to_deg(closest)])
		check(grip < 0.045, "every hand's fingers close on its item (farthest tip %.3f m)" % grip)
		var cands: Array = FPInteractions.get_candidates(m)
		var aimable := true
		for n in m.vent.offer_nodes():
			var p: Vector3 = (n as Node3D).global_position
			aimable = aimable and cands.any(func(c): return c[0] == "vent" and (c[1] as Vector3).distance_to(p) < 0.01)
		check(aimable, "each of the %d held items is an aim point" % ids.size())
		check(eyes_shown() == 0, "no eyes while %d hands hold items out" % ids.size())
	# --- 1. close to the eye, below the ceiling
	offer(["knife", "spray_cheap", "barrier"])
	await wait(2.5)
	var eye: Vector3 = m.player.camera.global_position
	var far := 0.0
	for i in range(3):
		var item: Node3D = art.call("item_node", i)
		far = maxf(far, item.global_position.distance_to(eye))
		check(item.global_position.y < FPRestroom.VENT_CENTER.y - 0.3, "item %d is held below the ceiling" % i)
	check(far < 0.75, "standing near the vent, every item is held within reach of the eye (%.2f m)" % far)
	var before_far := far
	m.player.global_position = Vector3(1.4, 0.9, 0.9)
	await wait(3.0)
	eye = m.player.camera.global_position
	var near_vent := 0.0
	for i in range(3):
		near_vent = maxf(near_vent, (art.call("item_node", i) as Node3D).global_position.distance_to(eye))
	check(near_vent < FPRestroom.VENT_CENTER.distance_to(eye) - 0.6, "from across the room the hands still reach well out toward the player (%.2f m, vent %.2f m)" % [near_vent, FPRestroom.VENT_CENTER.distance_to(eye)])
	m.player.global_position = Vector3(0.1, 0.9, 0.2)
	await wait(3.0)
	# --- 3. bright skin
	var skin: Color = art.get("SKIN")
	var player_skin := Color(0.88, 0.72, 0.62)
	check(luminance(skin) > luminance(player_skin) + 0.1, "the being's skin is clearly brighter than the player's (%.2f vs %.2f)" % [luminance(skin), luminance(player_skin)])
	var hand0: Node3D = (art.call("item_node", 0) as Node3D).get_parent()
	var palm_mesh: MeshInstance3D = hand0.get_node("Hand")
	var cols: PackedColorArray = palm_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var lum := 0.0
	for c in cols:
		lum += luminance(c)
	lum /= maxf(1.0, float(cols.size()))
	check(lum > 0.84, "the hand mesh itself is painted bright (mean %.2f)" % lum)
	check(palm_mesh.material_override != null and palm_mesh.material_override != m.player.get("hands_material"), "the being's skin has its own material")
	# --- 4. the wrist on the way down: never bent past the limit, straight in the duct
	offer([])
	await wait(0.8)
	offer(["spray_cheap", "barrier", "knife"])
	var worst := 0.0
	var worst_drop := 0.0
	var limit: float = art.get("WRIST_MAX")
	var drop_phase: float = art.get("DROP_PHASE")
	for f in range(120):
		await process_frame
		var e: float = art.get("_extend")
		for i in range(3):
			var hand: Node3D = (art.call("item_node", i) as Node3D).get_parent()
			var fore: Node3D = hand.get_parent().get_node("Forearm")
			var arm_dir: Vector3 = -fore.global_basis.y.normalized()
			var fingers: Vector3 = -hand.global_basis.y.normalized()
			var bend := arm_dir.angle_to(fingers)
			worst = maxf(worst, bend)
			if e < drop_phase:
				worst_drop = maxf(worst_drop, bend)
	check(worst <= limit + 0.02, "the wrist never bends past %.0f° on the way down (worst %.1f°)" % [rad_to_deg(limit), rad_to_deg(worst)])
	check(worst_drop < 0.02, "coming straight down out of the duct the wrist is straight (worst %.1f°)" % rad_to_deg(worst_drop))
	# --- the trade: F on the aimed item takes that one, the rest go back up
	await wait(1.0)
	var target: Node3D = m.vent.offer_nodes()[2]
	var want: String = target.get_meta("offer_id")
	look_at_point(target.global_position)
	await frames(2)
	check(m.interact_target() == "vent", "looking at the outer hand's item aims at the vent offer")
	check(m.aimed_offer() == want, "the aimed item is the outer one (%s)" % want)
	var arms: Node3D = art.get_node("BeingArm")
	var before: int = m.progression.tools.owned.size() if "owned" in m.progression.tools else -1
	# the first F puts the head in under the hands (run_vent_look_tests.gd);
	# inside, the eye turns to the outer hand and F takes that one
	m.use_vent()
	check(m.vent.offers.size() == 3 and m.hand_motions.vent_looking(), "F puts the head in, nothing taken yet")
	await wait(1.0)
	var turn := 0.08
	for i in range(24):
		if m.aimed_offer() == want:
			break
		if i == 10:
			turn = -turn
			m.player._yaw += 0.9 * -turn
		m.player._yaw -= turn
		await frames(3)
	check(m.aimed_offer() == want, "inside, the eye reaches the outer hand (%s)" % m.aimed_offer())
	m.use_vent()
	check(m.vent.offers.is_empty(), "F takes the offer")
	await wait(1.2)
	check(not arms.visible, "after the take every arm is back up in the dark")
	check(eyes_shown() == 0, "and still no eyes")
	print("--- vent hands: %d passed, %d failed ---" % [passed, failed])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://vent-hands-test.bin"))
	m.queue_free()
	quit(1 if failed > 0 else 0)
