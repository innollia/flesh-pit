extends SceneTree

## Every item on the belt can be reached with real input (2026-11-07 "벨트에
## 있는 물건 목록을 아직 못 건드려"): the head bows with real mouse motion,
## the aimed item lights up, the left button takes it into the left hand and
## the right button into the right, and the held one goes back to its slot.
## In the restroom and out in the flesh.

var m: Node3D
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

func frames(c: int) -> void:
	for i in range(c):
		await physics_frame
		await process_frame

func mouse(button: int, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)

func tap_mouse(button: int) -> void:
	mouse(button, true)
	await frames(3)
	mouse(button, false)
	await frames(3)

## Real mouse motion only: move the view by (dyaw, dpitch) radians.
func move_view(dyaw: float, dpitch: float) -> void:
	var s: float = m.player.config.mouse_sensitivity
	var e := InputEventMouseMotion.new()
	e.relative = Vector2(-dyaw / s, -dpitch / s)
	Input.parse_input_event(e)
	await frames(2)

## Move the mouse like a player looking at the screen: push the crosshair
## toward where the item shows until it sits on it.
func look_at_item(point_of: Callable) -> void:
	var cam: Camera3D = m.player.camera
	for i in range(40):
		var p: Vector3 = point_of.call()
		var size := cam.get_viewport().get_visible_rect().size
		var f: float = size.y * 0.5 / tan(deg_to_rad(cam.fov) * 0.5)
		var off: Vector2
		if cam.is_position_behind(p):
			off = Vector2(0, size.y) # below and behind: bow further
		else:
			off = cam.unproject_position(p) - size * 0.5
		if off.length() < 2.0:
			return
		var s: float = m.player.config.mouse_sensitivity
		var e := InputEventMouseMotion.new()
		e.relative = Vector2(atan(off.x / f), atan(off.y / f)) * 0.7 / s
		Input.parse_input_event(e)
		await frames(2)

func fresh_game(at: Vector3) -> void:
	if is_instance_valid(m):
		m.queue_free()
		await frames(2)
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_belt_reach.json"
	m.save_path = "user://belt-reach-test.bin"
	root.add_child(m)
	await frames(6)
	m.save_path = "user://belt-reach-test.bin"
	m.finish_opening()
	m.player.mouse_look_enabled = true
	m.player.global_position = at
	m.player.velocity = Vector3.ZERO
	await frames(4)

func stock() -> void:
	var p: FPProgression = m.progression
	p.has_belt = true
	for id in ["knife", "blender", "big_saw", "spray_cheap", "spray_cheap", "spray_deep", "canary_feed", "barrier"]:
		p.grant_item(id)
	m.equip_tool("")
	await frames(3)

func slot_point(i: int) -> Vector3:
	return m.belt_swap._slot_point(m.art_hookup.belt, i)

const L := FDKToolKit.Hand.LEFT
const R := FDKToolKit.Hand.RIGHT

## The first key event bound to `action` (whatever the key settings say).
func bound_key(action: String) -> InputEventKey:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return e
	return null

func press_hand(hand: int, by_key: bool) -> void:
	if by_key:
		var k: InputEventKey = bound_key("fdk_eat" if hand == L else "fp_pick").duplicate()
		k.pressed = true
		Input.parse_input_event(k)
		await frames(3)
		k = k.duplicate()
		k.pressed = false
		Input.parse_input_event(k)
		await frames(3)
	else:
		await tap_mouse(MOUSE_BUTTON_LEFT if hand == L else MOUSE_BUTTON_RIGHT)
	for i in range(90):
		if not m.belt_swap.busy() and m.hand_motions.kind != "belt":
			return
		await frames(1)

func focused() -> int:
	if m.art_hookup.waist_compass.scale.x > 1.01:
		return FPBeltSwap.COMPASS_SLOT
	return int(m.art_hookup.belt.get("focused"))

## Look down at slot i: it is the aimed one, it lights, the ring shows the
## hand buttons that can use it.
func aim_slot(i: int, where: String) -> bool:
	await look_at_item(slot_point.bind(i))
	await frames(2)
	var id: String = FPBeltSwap.SLOTS[i]
	var ok: bool = m.belt_swap.aimed_hook() == i
	check(ok, "%s: looking down at the %s aims at it (got %d)" % [where, id, m.belt_swap.aimed_hook()])
	return ok

func hand_item(hand: int) -> String:
	return m.progression.hands.item(hand)

## Take slot i's item with `hand`, then put it back with the same button.
func take_and_return(i: int, hand: int, where: String, by_key := false) -> void:
	var id: String = FPBeltSwap.SLOTS[i]
	var label := "%s %s %s" % [where, "L" if hand == L else "R", id]
	if not await aim_slot(i, where):
		return
	check(focused() == i, "%s: the aimed item lights up (focus %d)" % [label, focused()])
	check(m.interact_target() == "belt" and m.interact_ring.shown, "%s: the ring shows over the belt" % label)
	check(bool(m.interact_ring.hand_left if hand == L else m.interact_ring.hand_right), "%s: the pressed hand's button is lit" % label)
	await press_hand(hand, by_key)
	check(m.progression.hands.holds(id) and (hand_item(hand) == id or id == "big_saw"), "%s: taken into that hand (L '%s' R '%s')" % [label, hand_item(L), hand_item(R)])
	if i < 3:
		check(m.art_hookup.belt.call("hung")[i] == "", "%s: its hook is left empty" % label)
	if i == FPBeltSwap.COMPASS_SLOT:
		check(not m.art_hookup.waist_compass.visible, "%s: gone from the waist" % label)
	# the same button on the same slot puts it back
	if not await aim_slot(i, where):
		return
	check(m.interact_target() == "belt", "%s: the slot of the held item is still a target" % label)
	await press_hand(hand, by_key)
	check(not m.progression.hands.holds(id), "%s: put back on the belt (L '%s' R '%s')" % [label, hand_item(L), hand_item(R)])
	if i < 3:
		check(m.art_hookup.belt.call("hung")[i] == id, "%s: back on its hook" % label)

func run() -> void:
	for place in [["restroom", Vector3(0, 0.95, 0)], ["flesh", Vector3(0, 0.6, 4.0)]]:
		var where: String = place[0]
		await fresh_game(place[1])
		if where == "flesh":
			m.terrain.carve_sphere(Vector3(0, 1.2, 4.2), 1.6)
			m.terrain.remesh_all()
			m.player.global_position = place[1]
			await frames(10)
		await stock()
		# looking ahead the hand buttons still dig: the belt changes nothing there
		await move_view(0.0, -m.player.camera_pivot.rotation.x - 0.1)
		check(m.belt_swap.aimed_hook() == -1 and FPInteractions.plan(m, "left") == "dig" and FPInteractions.plan(m, "right") == "dig", "%s: looking ahead both hands dig (%s)" % [where, FPInteractions.plan(m, "left")])
		# every item on the belt can be aimed with the mouse and lights up
		for i in range(FPBeltSwap.SLOTS.size()):
			if await aim_slot(i, where):
				check(focused() == i, "%s: the aimed %s lights up (focus %d)" % [where, FPBeltSwap.SLOTS[i], focused()])
				check(m.interact_target() == "belt", "%s: the ring is on the %s" % [where, FPBeltSwap.SLOTS[i]])
		# left click takes into the left hand, right click into the right
		await take_and_return(0, L, where)
		await take_and_return(0, R, where)
		await take_and_return(1, L, where)
		await take_and_return(2, R, where)
		await take_and_return(3, R, where)
		await take_and_return(4, L, where)
		await take_and_return(5, L, where)
		await take_and_return(6, R, where)
		await take_and_return(7, L, where)
		# the blender and the compass are left-hand things: the right button
		# does not light for them
		if await aim_slot(1, where):
			check(m.interact_ring.hand_left and not m.interact_ring.hand_right, "%s: on the blender only the left button lights" % where)
		if await aim_slot(7, where):
			check(m.interact_ring.hand_left and not m.interact_ring.hand_right, "%s: on the compass only the left button lights" % where)
		# a held item goes home when the hand takes another one
		if await aim_slot(4, where):
			await press_hand(L, false)
			check(hand_item(L) == "spray_deep", "%s: the deep can in the left hand" % where)
			if await aim_slot(0, where):
				await press_hand(L, false)
				check(hand_item(L) == "knife" and m.progression.sprays.count_of_tier(FDKSprayCan.Tier.DEEP) == 1 and m.art_hookup.belt.call("hung")[0] == "", "%s: the knife comes up and the can goes back (L '%s')" % [where, hand_item(L)])
		# the keys of the hand actions do the same (E / R as the key settings say)
		await take_and_return(6, L, where, true)
		await take_and_return(3, R, where, true)
		# both hands full, look up: digging with the knife is unchanged
		await move_view(0.0, -m.player.camera_pivot.rotation.x - 0.1)
		check(FPInteractions.plan(m, "left") == "dig", "%s: back up, the knife hand digs again" % where)
	m.queue_free()
	await frames(2)
	print("--- %d passed, %d failed ---" % [passed, failed])
	quit(1 if failed else 0)
