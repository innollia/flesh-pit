extends SceneTree

## The head in under the vent (user 2026-11-07): F at the trade moves the eye
## in with an animation and locks walking, the being's hands stand big and
## whole in the middle of the view with 3, 5 and 8 items, nothing of the
## player's hands is in the way, and the trade, the spill, Esc, a restored
## save, going back in, the door, Tab and the eye guard all still hold.
## Isolated save; the normal game loop runs.

## The eye as the frame shows it, after main's tick and its eye guard.
class LateEye:
	extends Node
	var game: Node3D
	var eye := Vector3.ZERO
	func _process(_delta: float) -> void:
		eye = game.player.camera.global_position

const THREE := ["knife", "spray_cheap", "barrier"]
const FIVE := ["knife", "spray_cheap", "barrier", "canary_feed", "junk"]
const EIGHT := ["barrier", "spray_cheap", "knife", "spray_deep", "big_saw", "junk", "canary_feed", "blender"]

var m: Node3D
var passed := 0
var failed := 0
## The same spot relative to the vent as before the vent moved to the room's
## centre line (it was (0.3, 0.9, 0.3) for a vent at (-0.55, -0.78)).
var stand := Vector3(FPRestroom.VENT_CENTER.x + 0.85, 0.9, FPRestroom.VENT_CENTER.z + 1.08)

func _init() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://vent-look-test.bin"
	m.user_keybinds_path = "user://vent-look-test-keys.json"
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

func looking() -> bool:
	return m.hand_motions.has_method("vent_looking") and m.hand_motions.vent_looking()

func eye() -> Vector3:
	return m.player.camera.global_position

func press(action: String, hold := 2) -> void:
	Input.action_press(action)
	await frames(hold)
	Input.action_release(action)
	await frames(1)

func look_at_point(p: Vector3) -> void:
	var d := p - eye()
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

## Standing where the vent is in reach, looking at it, the vent shut, nothing
## in the hands, the head out.
func reset() -> void:
	if m.has_method("_end_lean"):
		m._end_lean()
	await wait(0.7)
	while m.hand_motions.busy():
		await process_frame
	if m.vent.is_open:
		m.vent.close()
	m.vent._held.clear()
	m.vent._open_times.clear()
	m.vent.absent_left = 0.0
	m.progression.teeth_in_hand = 0
	m.player.global_position = stand
	await physics_frame
	await frames(3)
	for i in range(6):
		look_at_point(FPRestroom.VENT_CENTER + Vector3(0, -0.2, 0))
		await physics_frame
	await frames(2)

func offer(ids: Array) -> void:
	var typed: Array[String] = []
	for id in ids:
		typed.append(String(id))
	m.vent._set_offers(typed)

func go_in() -> void:
	m.vent.open(30)
	await frames(30)
	offer(THREE)
	await wait(1.2)
	m._interact()
	await wait(1.0)

func run() -> void:
	root.size = Vector2i(1280, 720)
	await frames(5)
	m.finish_opening()
	m.restroom.set_door_open(false, true)
	m.vent.instant_voice = true
	await _going_in()
	await _composition()
	await _trade()
	await _spill()
	await _ways_out()
	await _save_restore()
	await _door_and_mirror()
	await _eye_guard()
	print("--- vent look: %d passed, %d failed ---" % [passed, failed])
	for f in ["user://vent-look-test.bin", "user://vent-look-test-keys.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	m.queue_free()
	await frames(2)
	quit(1 if failed > 0 else 0)

## The eye travels in over time, the body stays and cannot walk.
func _going_in() -> void:
	await reset()
	# teeth in the hand go on the lip first, the head out (user 2026-11-09)
	m.progression.teeth_in_hand = 12
	var from := eye()
	var body: Vector3 = m.player.global_position
	check(m.interact_target() == "vent", "looking at the shut vent aims at it")
	m._interact()
	check(m.vent.is_open, "F opens the vent")
	check(not looking(), "F with teeth in hand keeps the head out")
	await frames(2)
	m._interact()
	await frames(2)
	check(m.progression.teeth_in_hand == 11 and m.vent.pile == 1 and not looking(), "F places a tooth standing")
	m._tooth_op = ""
	m.progression.teeth_in_hand = 0
	m.vent.pile = 0
	offer(THREE)
	await wait(1.2)
	from = eye()
	m._interact()
	check(looking(), "F at the offer with an empty hand puts the head in")
	var path: Array[Vector3] = []
	var t := 0.0
	while t < 0.75:
		await process_frame
		t += root.get_process_delta_time()
		path.append(eye())
	var steps := 0
	for i in range(1, path.size()):
		if path[i].distance_to(path[i - 1]) > 0.002:
			steps += 1
	check(steps >= 6, "the eye travels over frames, no jump (%d moving frames)" % steps)
	var biggest := 0.0
	for i in range(1, path.size()):
		biggest = maxf(biggest, path[i].distance_to(path[i - 1]))
	check(biggest < 0.25, "no frame jumps the eye (largest step %.2f m)" % biggest)
	var v: Vector3 = FPRestroom.VENT_CENTER
	check(eye().distance_to(v) < from.distance_to(v) - 0.25, "the head ends up nearer the vent (%.2f m, was %.2f m)" % [eye().distance_to(v), from.distance_to(v)])
	check(eye().y > from.y, "and rises to it")
	check(m.player.camera.fov < FPSettings.base_fov(m.player.camera) - 5.0, "the lens narrows on the hands")
	Input.action_press("fdk_move_forward")
	await wait(0.4)
	Input.action_release("fdk_move_forward")
	await frames(2)
	check(looking(), "walking forward keeps the head in")
	check(m.player.global_position.distance_to(body) < 0.03, "walking is locked (body moved %.3f m)" % m.player.global_position.distance_to(body))
	check(m.interact_target() == "vent", "the aim stays on the vent")

func _on_screen_px(p: Vector3, size: Vector2) -> Vector2:
	var cam: Camera3D = m.player.camera
	return Vector2(-1, -1) if cam.is_position_behind(p) else cam.unproject_position(p)

## Every hand whole in frame, large enough, apart, in the middle; the
## player's own hands below the frame.
func _composition() -> void:
	await reset()
	await go_in()
	var size: Vector2 = m.player.camera.get_viewport().get_visible_rect().size
	for ids in [THREE, FIVE, EIGHT]:
		offer(ids)
		await wait(1.6)
		var art: Node3D = m.vent.art
		var n: int = ids.size()
		check(int(art.call("hand_count")) == n, "%d hands out" % n)
		var inside := 0
		var smallest := INF
		var worst_off := 0.0
		var sum := Vector2.ZERO
		var pts: Array[Vector2] = []
		for i in range(n):
			var item: Node3D = art.call("item_node", i)
			var hand: Node3D = item.get_parent()
			var wrist := _on_screen_px(hand.global_position, size)
			var tip := _on_screen_px((hand.get_node("Finger1/Mid/Tip") as Node3D).global_position, size)
			var it := _on_screen_px(item.global_position, size)
			var rect := Rect2(Vector2(0, 0), size)
			if rect.has_point(wrist) and rect.has_point(tip) and rect.has_point(it):
				inside += 1
			smallest = minf(smallest, wrist.distance_to(tip) / size.y)
			sum += (wrist + tip) * 0.5
			pts.append(tip)
		check(inside == n, "all %d hands and items are inside the frame (%d)" % [n, inside])
		var want := 0.14 if n <= 5 else 0.09
		check(smallest >= want, "%d hands stand large (smallest palm %.2f of the height)" % [n, smallest])
		var c := sum / float(n) - size * 0.5
		check(absf(c.x) < size.x * 0.1 and absf(c.y) < size.y * 0.25, "%d hands sit in the middle of the view (off by %s)" % [n, str(c)])
		var closest := INF
		for i in range(n):
			for j in range(i + 1, n):
				closest = minf(closest, pts[i].distance_to(pts[j]))
		check(closest > size.y * 0.06, "%d hands do not sit on top of each other (closest %.0f px)" % [n, closest])
		# the arms come down out of the opening into the frame
		var drop: Node3D = art.get_node("BeingArm")
		check(drop.visible, "the arms show")
		for rig in FPHandMotions.rigs_of(m):
			for side in ["left", "right"]:
				var root_h: Node3D = rig.call("get_hand_root", side)
				var px := _on_screen_px(root_h.global_position, size)
				check(not Rect2(Vector2.ZERO, size).has_point(px) or px.y > size.y * 0.97, "the player's %s hand is out of the frame (%s)" % [side, str(px)])
	check(m.interact_target() == "vent", "still aimed at the vent with 8 hands")

## F in the look takes what the eye is on; the spray in the middle by
## default, the outer one after turning the eye; the head comes back out.
func _trade() -> void:
	await reset()
	m.vent.open(30)
	await frames(30)
	offer(THREE)
	await wait(1.2)
	var body: Vector3 = m.player.global_position
	var offered: Array = m.vent.offers.duplicate()
	m._interact()
	check(looking(), "the first F at an offer puts the head in")
	check(m.vent.offers == offered, "and takes nothing yet")
	await wait(1.0)
	check(m.aimed_offer() == offered[1], "the head comes in on the middle item (%s)" % m.aimed_offer())
	m.player._yaw -= 0.5
	await wait(0.1)
	check(m.aimed_offer() != offered[1], "turning the eye moves to an outer hand (%s)" % m.aimed_offer())
	var want: String = m.aimed_offer()
	m.player._yaw -= 2.0
	await wait(0.1)
	check(absf(m.hand_motions.vent_pan.x) <= m.VENT_PAN_MAX.x + 0.001, "the turn stops at its limit (%.2f)" % m.hand_motions.vent_pan.x)
	var at := eye()
	m._interact()
	await frames(1)
	check(m.vent.offers.is_empty(), "F takes the item")
	check(m.hand_motions.kind in ["take", "take2"], "the hand takes it (%s)" % m.hand_motions.kind)
	check(eye().distance_to(at) < 0.05, "the head is still in when the hand goes out")
	await wait(0.2)
	check(eye().distance_to(at) < 0.1, "and until the fingers close")
	await wait(1.6)
	check(not looking() and m.hand_motions.vent_eye_weight() <= 0.0, "with the item taken the head has come back out")
	check(not m.player.move_locked, "and the body walks again")
	check(m.player.global_position.distance_to(body) < 0.05, "from where it stood")
	check(absf(m.player.camera.fov - FPSettings.base_fov(m.player.camera)) < 0.01, "the lens is back")
	check(want != "", "taken: %s" % want)
	# the right hand still trades without going in
	await reset()
	m.vent.open(30)
	await frames(30)
	offer(THREE)
	await wait(1.2)
	m.activate_target("vent", FPInteractions.SOURCE_RIGHT)
	check(m.vent.offers.is_empty() and not looking(), "the right hand takes straight, as at the tank")

## The absurd overpay spills with the head in, and the look survives it.
func _spill() -> void:
	await reset()
	m.progression.teeth_in_hand = m.progression.vent_absurd_threshold() + 5
	m._interact()
	await wait(0.8)
	check(not looking(), "an absurd handful goes on standing")
	var n: int = m.progression.teeth_in_hand
	m.place_teeth_at_vent()
	check(n > 0 and m.progression.teeth_in_hand == 0, "the handful goes on the lip")
	await frames(2)
	check(m.vent.art.call("spill_count") > 0, "the overpay spills (%d)" % m.vent.art.call("spill_count"))
	await wait(0.3)
	check(looking(), "teeth given: the head goes in under the offer during the spill")
	await wait(1.0)
	check(looking(), "and it stays in through the spill")

func _ways_out() -> void:
	for a in ["fdk_move_back", "fdk_jump", "ui_cancel"]:
		await reset()
		await go_in()
		check(looking(), "in again for %s" % a)
		var paused_before: bool = paused
		await press(a)
		await wait(0.8)
		check(not looking(), "%s brings the head out" % a)
		check(m.hand_motions.vent_eye_weight() <= 0.0, "%s: the eye is all the way back" % a)
		check(not m.player.move_locked, "%s: the body walks" % a)
		check(paused == paused_before, "%s: the game is not paused" % a)
		# Esc again from outside is the pause menu
		if a == "ui_cancel":
			await frames(4)
			check(m.esc_target() == "pause", "Esc with the head out is the pause menu again (%s)" % m.esc_target())
	# frantic walking
	await reset()
	await go_in()
	for i in range(m.LEAN_FRANTIC):
		await press("fdk_move_left" if i % 2 == 0 else "fdk_move_right", 1)
	await wait(0.8)
	check(not looking(), "frantic movement brings the head out")
	# nothing left to trade: out by itself
	await reset()
	await go_in()
	check(looking(), "in at an offer")
	m.vent._clear_offers()
	await wait(m.VENT_LOOK_IDLE + 1.0)
	check(not looking(), "with nothing left to trade the head comes back out")
	# in, out, straight back in
	await reset()
	await go_in()
	var pose := eye()
	await press("fdk_move_back")
	await wait(0.1)
	check(m.interact_target() == "vent", "F on the way out still means the vent")
	m._interact()
	await wait(1.0)
	check(looking() and eye().distance_to(pose) < 0.02, "going back in lands on the same pose")

func _save_restore() -> void:
	await reset()
	await go_in()
	check(m.save_to_disk(), "a save made with the head in")
	var body: Vector3 = m.player.global_position
	var offered: Array = m.vent.offers.duplicate()
	var f := FileAccess.open(m.save_path, FileAccess.READ)
	var data: Dictionary = f.get_var()
	f.close()
	var saved: Array = data.get("player_position", [])
	check(Vector3(saved[0], saved[1], saved[2]).distance_to(body) < 0.01, "stores the body where it stands, not the eye")
	check(m.load_from_disk(), "loads")
	check(not looking(), "the head is not in after the load")
	await frames(3)
	check(not m.player.move_locked, "the body walks after the load")
	check(m.hand_motions.vent_eye_weight() <= 0.0, "the eye is at rest")
	check(absf(m.player.camera.fov - FPSettings.base_fov(m.player.camera)) < 0.01, "the lens is back after the load")
	check(eye().distance_to(m.player.camera_pivot.global_position) < 0.2, "the eye is on the body (%.2f m)" % eye().distance_to(m.player.camera_pivot.global_position))
	var rig: Node3D = m.hands_rig
	check(rig.position.y > -0.05, "the hands are back in place (%.2f)" % rig.position.y)
	check(not m.vent.art.call("looking"), "the hands left the close-up")
	check(m.vent.offers == offered or m.vent.held_offers() == offered, "the offer survives")
	m.player.global_position = stand
	await frames(3)
	look_at_point(FPRestroom.VENT_CENTER + Vector3(0, -0.2, 0))
	await frames(2)
	for i in range(6):
		look_at_point(FPRestroom.VENT_CENTER + Vector3(0, -0.2, 0))
		await physics_frame
	await frames(2)
	m._interact()
	await frames(30)
	if not looking():
		m._interact() # a vent the load left shut opens on the first press
	await wait(1.0)
	check(looking(), "the look works again after the load")

func _door_and_mirror() -> void:
	# the door: not reachable from inside, works again outside
	await reset()
	await go_in()
	var door: bool = m.restroom.is_door_open()
	m._interact()
	check(m.restroom.is_door_open() == door, "F inside never reaches the door")
	await reset()
	await frames(2)
	m.player.global_position = Vector3(0.0, 0.9, 0.8)
	await frames(3)
	look_at_point(m.door_handle_point())
	await frames(2)
	check(m.interact_target() == "door", "after the look the door is aimed as before (%s)" % m.interact_target())
	m._interact()
	await frames(2)
	check(m.restroom.is_door_open() != door, "and opens")
	m.restroom.set_door_open(door, true)
	# Tab: the forearm hologram takes over and hands everything back
	await reset()
	await go_in()
	m.open_mirror()
	await frames(2)
	check(m._mirror_open and m.hand_motions.kind == "watch", "Tab opens from inside")
	check(not looking(), "and ends the look")
	await wait(0.8)
	check(m.hand_motions.vent_eye_weight() <= 0.0, "the eye has come back under the hologram")
	m.mirror.close()
	await wait(0.8)
	check(not m._mirror_open and not m.player.move_locked, "closing it leaves the body free")
	check(not m.hand_motions.busy(), "and the arm down")
	# the cabinet mirror
	await reset()
	await go_in()
	var cab: bool = m.restroom.mirror_art.cabinet_open
	m.restroom.mirror_art.call("toggle_cabinet")
	await frames(2)
	check(looking(), "the cabinet opening does not break the look")
	m.restroom.mirror_art.call("toggle_cabinet")
	check(m.restroom.mirror_art.cabinet_open == cab, "and shuts again")

## Flesh between the body and the head: the guard shortens the eye as for
## any other pose, in the same real frame.
func _eye_guard() -> void:
	await reset()
	await go_in()
	var free := eye()
	var body: Vector3 = m.player.global_position
	var mid := body.lerp(free, 0.55)
	var box := AABB(mid - Vector3(0.45, 0.45, 0.45), Vector3(0.9, 0.9, 0.9))
	m.terrain.fill_box_uniform(box, 1.0, 0)
	m.terrain.remesh_all()
	await wait(0.4)
	await physics_frame
	await frames(3)
	# the flesh may shoulder the capsule aside: the guard works from where it is
	var want: Vector3 = m.terrain.constrain_eye(free, m.player.global_position, m.player.camera.near)
	check(want.distance_to(free) > 0.1, "the test flesh stands between body and eye (%.2f m)" % want.distance_to(free))
	# read after main's own tick: the next frame's start takes the correction off
	var seen := LateEye.new()
	seen.game = m
	root.add_child(seen)
	await frames(3)
	check(seen.eye.distance_to(want) < 0.03, "the eye stops at the real surface (%.2f m off)" % seen.eye.distance_to(want))
	m.terrain.carve_sphere(mid, 0.8)
	m.terrain.remesh_all()
	await frames(4)
	check(seen.eye.distance_to(free) < 0.03, "with the flesh gone the eye returns to the pose")
	seen.queue_free()
