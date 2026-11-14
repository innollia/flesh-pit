extends SceneTree

## The vent being's hands (user 2026-11-03):
## 1. the offer is held out close in front of the eye ("가까이서 보게"),
## 2. one hand per offered item, three or more, each an aim point of its own,
## 3. bright skin (brighter than the player's own),
## 4. the wrist stays near the forearm line all the way down (a soft
##    extension at most), the elbow softly bent (user 2026-11-09),
## 5. no eyes in the duct, in any state.
## The trade itself (F takes the aimed item, the others go back up) holds.

var m: Node3D
var passed := 0
var failed := 0

## Where the checks stand, kept at the same offsets from the vent as before
## it moved to the room's centre line: a step away from under it (the spot
## was (0.1, 0.9, 0.2) for a vent at (-0.55, -0.78)), and across the room.
func near_stand() -> Vector3:
	return Vector3(FPRestroom.VENT_CENTER.x + 0.65, 0.9, FPRestroom.VENT_CENTER.z + 0.98)

func far_stand() -> Vector3:
	return Vector3(FPRestroom.VENT_CENTER.x + 1.9, 0.9, FPRestroom.VENT_CENTER.z + 1.4)

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

## An offered item's outline in its own frame (all its meshes).
func item_box(item: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in item.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var b: AABB = (item.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

## How an offered item sits on its palm: [gap in metres between the item's
## underside and the highest palm-skin vertex inside its footprint (minus:
## pressed in), palm vertices in that footprint, item middle over the palm].
func palm_contact(item: Node3D) -> Array:
	var hand: Node3D = item.get_parent()
	var palm: MeshInstance3D = hand.get_node("Hand")
	var box := item_box(item)
	var to_item := item.global_transform.affine_inverse() * palm.global_transform
	var top := -INF
	var n := 0
	for v in palm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var q: Vector3 = to_item * v
		if q.x > box.position.x and q.x < box.end.x and q.y > box.position.y and q.y < box.end.y:
			top = maxf(top, q.z)
			n += 1
	var s: float = item.global_basis.z.length()
	var mid: Vector3 = palm.global_transform.affine_inverse() * (item.global_transform * box.get_center())
	var pb: AABB = palm.get_aabb()
	var on := mid.x > pb.position.x and mid.x < pb.end.x and mid.y > pb.position.y and mid.y < pb.end.y
	return [(box.position.z - top) * s if n > 0 else 1.0, n, on]

## A finger's length from its knuckle to the end of its tip (nail
## included), in the hand's own frame.
func finger_len(hand: Node3D, i: int) -> float:
	var mid: Node3D = hand.get_node("Finger%d/Mid" % i)
	var tip: Node3D = mid.get_node("Tip")
	var bone: MeshInstance3D = tip.get_node("Bone")
	return absf(mid.position.y) + absf(tip.position.y) + absf(bone.get_aabb().position.y)

func luminance(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

func run() -> void:
	await frames(5)
	m.finish_opening()
	var art: Node3D = m.vent.art
	m.player.global_position = near_stand()
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
		# held, not floating (user 2026-11-09 "물건이 손에 잘 안 올라가있음"):
		# each item lies on its open palm, its underside on the real palm skin
		# under it (palm mesh vertices inside its footprint), its middle over
		# the palm
		var gap_worst := 0.0
		var over := true
		for i in range(ids.size()):
			var item: Node3D = art.call("item_node", i)
			var g := palm_contact(item)
			gap_worst = maxf(gap_worst, absf(g[0]))
			over = over and g[1] >= 6 and g[2]
		check(over, "every item lies over its own palm (%d items)" % ids.size())
		check(gap_worst < 0.004, "every item rests on the palm skin (worst gap %.4f m)" % gap_worst)
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
	m.player.global_position = far_stand()
	await wait(3.0)
	eye = m.player.camera.global_position
	var near_vent := 0.0
	for i in range(3):
		near_vent = maxf(near_vent, (art.call("item_node", i) as Node3D).global_position.distance_to(eye))
	check(near_vent < FPRestroom.VENT_CENTER.distance_to(eye) - 0.6, "from across the room the hands still reach well out toward the player (%.2f m, vent %.2f m)" % [near_vent, FPRestroom.VENT_CENTER.distance_to(eye)])
	m.player.global_position = near_stand()
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
	# --- 6. a beautiful hand (user 2026-11-08 "npc 손이 아직 덜 예뻐"): long
	# slender fingers on a narrow palm, ring as long as the index, one smooth
	# surface, the long fingers shown whole with the back of the hand to the eye
	var lens: Array = []
	for i in range(4):
		lens.append(finger_len(hand0, i))
	var knuckle: Vector3 = (hand0.get_node("Finger1") as Node3D).position
	var back_len := absf(knuckle.y)
	var breadth: float = palm_mesh.get_aabb().size.x
	check(lens[1] >= back_len * 1.25, "the middle finger is long: %.3f m from the knuckle, %.2f of the back of the hand" % [lens[1], lens[1] / back_len])
	check(breadth <= lens[1] * 0.78, "the palm is narrow: %.3f m across, %.2f of the middle finger" % [breadth, breadth / lens[1]])
	check(absf(lens[2] - lens[0]) <= lens[1] * 0.04 and lens[3] < lens[0] * 0.9, "ring and index are nearly equal, the little finger shorter (%.3f %.3f %.3f %.3f)" % lens)
	var smooth := true
	for n in hand0.find_children("*", "MeshInstance3D", true, false):
		var arr: Array = (n as MeshInstance3D).mesh.surface_get_arrays(0)
		# the being's skin only, not the item it holds
		if (n as MeshInstance3D).material_override != palm_mesh.material_override:
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		var nv: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var ni: int = (idx as PackedInt32Array).size() if idx is PackedInt32Array else 0
		smooth = smooth and ni > nv
	check(smooth, "hand and fingers are smooth shared-vertex surfaces, not loose facets")
	var nails := 0
	var tip_cols: PackedColorArray = (hand0.get_node("Finger1/Mid/Tip/Bone") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for c in tip_cols:
		if c.a < 0.9 and c.r - c.g > 0.25:
			nails += 1
	check(nails > 20, "the nails are lacquered in a rose colour (%d nail vertices)" % nails)
	var eye1: Vector3 = m.player.camera.global_position
	var palms := 0
	var open := 1.0
	var bends: Array = []
	var low_elbow := INF
	for i in range(3):
		var hand: Node3D = (art.call("item_node", i) as Node3D).get_parent()
		var pn: Vector3 = hand.global_basis.z.normalized()
		if pn.y > 0.25 and pn.dot((eye1 - hand.global_position).normalized()) > 0.25:
			palms += 1
		var root: Vector3 = (hand.get_node("Finger1") as Node3D).global_position
		var tip: Node3D = hand.get_node("Finger1/Mid/Tip")
		var end: Vector3 = tip.global_transform * Vector3(0, -(tip.get_node("Bone") as MeshInstance3D).get_aabb().size.y * 0.8, 0)
		open = minf(open, root.distance_to(end) / (finger_len(hand, 1) * hand.global_basis.y.length()))
		# the elbow: the upper arm down out of the opening, the forearm on to the wrist
		var rig_root: Node3D = hand.get_parent()
		var up_dir: Vector3 = (rig_root.get_node("UpperArm") as Node3D).global_basis.y.normalized()
		var fore_dir: Vector3 = -(rig_root.get_node("Forearm") as Node3D).global_basis.y.normalized()
		bends.append(rad_to_deg((-up_dir).angle_to(fore_dir)))
		# the bend shows: the elbow well out of the opening, not hidden at its lip
		var el_pos: Vector3 = (rig_root.get_node("Elbow") as Node3D).global_position
		low_elbow = minf(low_elbow, FPRestroom.VENT_CENTER.y - el_pos.y)
	check(palms == 3, "every hand turns its open palm up to the eye to offer (%d of 3)" % palms)
	check(open > 0.75, "the fingers stay long and open, not closed into a fist (knuckle to tip %.2f of the finger)" % open)
	var bent := true
	for bd in bends:
		bent = bent and bd > 18.0 and bd < 75.0
	check(bent, "every arm bends softly at the elbow, none a straight pole (%s°)" % str(bends))
	check(low_elbow > 0.15, "every elbow shows below the opening (highest %.2f m under it)" % low_elbow)
	check(bends.max() - bends.min() > 4.0, "each arm bends its own way (%s°)" % str(bends))
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
