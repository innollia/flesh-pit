extends SceneTree

## Teeth before the reward (user 2026-11-09): "손에 봉을 쥐고 환풍구 문을
## 열면 환풍구에 이빨을 넣기도 전에 화면이 보상 받을 때 화면이라 이빨을 못
## 넣어줌" -- 봉 is the being's word for teeth. With teeth in the hand,
## whatever the hands hold and whichever input opens the grate, the head
## stays out, the teeth go on the lip, and the head goes in only once the
## being holds something out. An offer held from last time waits up the duct
## until the teeth are in.
## And "이빨을 챙겨야 한다는 것에 대한 넛지가 부족함": the room shows where
## teeth come from and where they go -- the open grate's empty grasping hand
## (teeth in the tank, none in hand), the glinting lip (teeth in hand), the
## shut grate knocking (teeth in hand), the tank lid knocking before the
## first trade -- and none of it in any other state.
## Real input events through the normal game loop; isolated save and keys.

var m: Node3D
var passed := 0
var failed := 0
var stand := Vector3(0.3, 0.9, 0.3)
var knocks := 0

func _init() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://vent-teeth-test.bin"
	m.user_keybinds_path = "user://vent-teeth-test-keys.json"
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

## The first key or mouse button bound to `action`, as the player presses it.
func send(action: String, down: bool) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			var ev: InputEvent = e.duplicate()
			ev.pressed = down
			Input.parse_input_event(ev)
			return
	check(false, "%s has a key or button" % action)

func press(action: String) -> void:
	send(action, true)
	await frames(3)
	send(action, false)
	await frames(3)

func looking() -> bool:
	return m.hand_motions.vent_looking() or m.hand_motions.vent_eye_weight() > 0.0

func look_at_point(p: Vector3) -> void:
	var d: Vector3 = p - m.player.camera.global_position
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

## Standing in reach of the shut vent, looking at it, nothing held, the head out.
func reset() -> void:
	m._end_lean()
	m._tooth_op = ""
	await wait(0.7)
	while m.hand_motions.busy():
		await process_frame
	if m.vent.is_open:
		m.vent.pile = 0
		m.vent.close()
	m.vent._held.clear()
	m.vent.trade_paid = 0
	if "offer_after_pay" in m.vent:
		m.vent.offer_after_pay = false
	m.vent.trade_paid = 0
	m.vent._open_times.clear()
	m.vent.absent_left = 0.0
	m.vent.final_trade = false
	m.progression.teeth_in_hand = 0
	m.progression.hands.clear()
	m.player.global_position = stand
	await physics_frame
	await frames(3)
	for i in range(6):
		look_at_point(FPRestroom.VENT_CENTER + Vector3(0, -0.2, 0))
		await physics_frame
	await frames(2)

const SOURCES := {"fp_interact": FPInteractions.SOURCE_INTERACT, "fdk_eat": FPInteractions.SOURCE_LEFT, "fp_pick": FPInteractions.SOURCE_RIGHT}
## Every belt item, in the hand it is held in ("" = bare hands).
const ITEMS := ["", "knife", "spray_cheap", "spray_deep", "barrier", "canary_feed", "big_saw", "blender", "compass"]

func run() -> void:
	root.size = Vector2i(1280, 720)
	await frames(5)
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.restroom.set_door_open(false, true)
	m.vent.instant_voice = true
	if m.has_signal("tank_teeth_knocked"):
		m.connect("tank_teeth_knocked", func(): knocks += 1)
	for id in ITEMS:
		if id != "" and id != "compass":
			m.progression.grant_item(id)
	await _held_items()
	await _held_offer_waits()
	await _reward_after_paying()
	_nudge_table()
	await _open_grate_nudges()
	await _shut_grate_knocks()
	await _tank_knocks()
	print("--- vent teeth: %d passed, %d failed ---" % [passed, failed])
	for f in ["user://vent-teeth-test.bin", "user://vent-teeth-test-keys.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	m.queue_free()
	await frames(2)
	quit(1 if failed > 0 else 0)

## Each item in its hand, each input that acts on the vent: it opens with
## the head out, and the same input puts a tooth on the lip.
func _held_items() -> void:
	for id in ITEMS:
		for action in SOURCES:
			await reset()
			var hand: int = m.progression.tools.hand_of(id) if id != "" else FDKToolKit.Hand.RIGHT
			if id != "":
				m.progression.equip_hand(id, hand, false)
				if m.progression.hands.item(hand) != id:
					check(false, "%s goes in a hand" % id)
					continue
			var plan: String = FPInteractions.plan(m, SOURCES[action])
			if plan != "target:vent":
				# the left hand on the blender stays on it (FPInteractions.right_hand_only)
				check(id == "blender" and action == "fdk_eat", "%s with %s: the press is the vent's (%s)" % [action, id, plan])
				continue
			m.progression.teeth_in_hand = 5
			var tag := "%s holding %s" % [action, id if id != "" else "teeth only"]
			await press(action)
			check(m.vent.is_open, tag + ": the grate opens")
			await wait(0.5)
			check(not looking(), tag + ": no reward view before the teeth (eye %.2f)" % m.hand_motions.vent_eye_weight())
			check(not m.player.move_locked, tag + ": the body is not locked in a look")
			await press(action)
			check(m.vent.pile == 1 and m.progression.teeth_in_hand == 4, tag + ": the same input puts a tooth on the lip (pile %d, hand %d)" % [m.vent.pile, m.progression.teeth_in_hand])
			check(not looking(), tag + ": still standing while paying")

## An offer left last time does not come out over the teeth in the hand.
func _held_offer_waits() -> void:
	await reset()
	m.vent._held = ["knife", "spray_cheap"] as Array[String]
	m.progression.teeth_in_hand = 3
	await press("fp_interact")
	await wait(0.5)
	check(m.vent.offers.is_empty() and m.vent.held_offers().size() == 2, "teeth in hand: the held offer stays up (%s)" % [m.vent.offers])
	check(int(m.vent.art.call("hand_count")) == 0 or m.vent.art.call("begging"), "no item hands out")
	check(not looking(), "and no reward view")
	await press("fp_interact")
	check(m.vent.pile == 1 and m.vent.held_offers().is_empty(), "the first tooth: it looks again at the whole")
	await wait(1.3)
	check(not m.vent.offers.is_empty(), "then pushes out a new offer (%s)" % [m.vent.offers])
	check(not m.hand_motions.vent_looking(), "teeth still in hand: the head stays out for more")
	# with an empty hand the held offer comes out at once, the head goes in
	await reset()
	m.vent._held = ["knife"] as Array[String]
	await press("fp_interact")
	await wait(0.8)
	check(m.vent.offers.size() == 1 and m.vent.offers[0] == "knife" and m.hand_motions.vent_looking(), "empty hand: the held offer comes out and the head goes in")
	# teeth in hand, grate open, the teeth go back to the tank: the next press brings the offer
	await reset()
	m.vent._held = ["knife"] as Array[String]
	m.progression.teeth_in_hand = 2
	await press("fp_interact")
	await wait(0.4)
	m.progression.teeth += m.progression.teeth_in_hand
	m.progression.teeth_in_hand = 0
	await press("fp_interact")
	await wait(0.8)
	check(m.vent.offers.size() == 1 and m.vent.offers[0] == "knife" and m.hand_motions.vent_looking(), "hand emptied: the next press brings the held offer out and the head in")

## Paid standing; the being looks and holds items out; then the head goes in to take one.
func _reward_after_paying() -> void:
	await reset()
	m.progression.teeth_in_hand = 2
	await press("fp_interact")
	await press("fp_interact")
	await wait(0.3)
	await press("fp_interact")
	check(m.progression.teeth_in_hand == 0 and m.vent.pile + m.vent.trade_paid == 2, "both teeth on the lip (hand %d pile %d paid %d open %s)" % [m.progression.teeth_in_hand, m.vent.pile, m.vent.trade_paid, m.vent.is_open])
	await wait(1.3)
	check(not m.vent.offers.is_empty(), "the being holds something out")
	await wait(0.8)
	check(m.hand_motions.vent_looking(), "teeth given, items held out: the head goes in by itself")
	await press("fp_interact")
	check(m.vent.offers.is_empty(), "F inside takes the item")

func _nudge_table() -> void:
	var nf := Callable(FPVent, "nudge_for")
	check(nf.call(true, false, false, 0, false, 8, 0) == "beg", "open, teeth in the tank, empty hand: the empty hand grasps")
	check(nf.call(true, false, false, 0, false, 8, 3) == "lip", "open, teeth in hand: the lip glints")
	check(nf.call(true, false, false, 0, false, 0, 3) == "lip", "open, teeth only in hand: the lip glints")
	check(nf.call(true, false, false, 0, false, 0, 0) == "", "open, no teeth anywhere: nothing")
	check(nf.call(false, false, false, 0, false, 8, 3) == "", "shut: nothing on the grate")
	check(nf.call(true, true, false, 0, false, 8, 3) == "", "the being gone: nothing")
	check(nf.call(true, false, true, 0, false, 8, 3) == "", "an offer out: nothing")
	check(nf.call(true, false, false, 2, false, 8, 3) == "", "teeth on the lip: nothing")
	check(nf.call(true, false, false, 0, true, 8, 0) == "", "an offer held back (empty hand brings it): no begging")

func _open_grate_nudges() -> void:
	var art: Node3D = m.vent.art
	await reset()
	m.progression.teeth = 8
	await press("fp_interact")
	await wait(1.4)
	check(m.vent.nudge == "beg" and art.call("begging") and int(art.call("hand_count")) == 1, "teeth in the tank, empty hand: one empty hand out (%s)" % m.vent.nudge)
	check(not art.call("glint_shown"), "and no glint")
	check(m.vent.offers.is_empty() and m.vent.offer_nodes().is_empty(), "the begging hand is not an offer to take")
	m.progression.teeth -= 3
	m.progression.teeth_in_hand = 3
	await wait(0.6)
	check(m.vent.nudge == "lip" and art.call("glint_shown") and not art.call("begging"), "teeth in hand: the hand goes, the lip glints")
	await press("fp_interact")
	await frames(2)
	check(m.vent.nudge == "" and not art.call("glint_shown"), "a tooth on the lip: the glint stops")
	await wait(1.3)
	check(m.vent.nudge == "" and not art.call("begging") and int(art.call("hand_count")) == m.vent.offers.size(), "an offer out: only its hands (%d)" % int(art.call("hand_count")))
	await reset()
	m.progression.teeth = 0
	await press("fp_interact")
	await wait(1.4)
	check(m.vent.nudge == "" and int(art.call("hand_count")) == 0, "no teeth anywhere: no hand comes")
	m.vent.close()
	await wait(0.5)
	check(m.vent.nudge == "" and not art.call("glint_shown"), "shut: nothing")
	m.progression.teeth = 8

func _shut_grate_knocks() -> void:
	var art: Node3D = m.vent.art
	await reset()
	m.progression.teeth_in_hand = 0
	var seen := false
	var t := 0.0
	while t < 4.0:
		await process_frame
		t += root.get_process_delta_time()
		seen = seen or art.call("jostling")
	check(not seen, "shut grate, empty hand: no knock")
	m.progression.teeth_in_hand = 4
	t = 0.0
	while t < 3.5 and not seen:
		await process_frame
		t += root.get_process_delta_time()
		seen = art.call("jostling")
	check(seen, "shut grate, teeth in hand: it knocks (%.1f s)" % t)
	m.player.global_position = Vector3(0, 0.9, FPRestroom.HALF.z + 3.0)
	await wait(0.6)
	seen = false
	t = 0.0
	while t < 4.0:
		await process_frame
		t += root.get_process_delta_time()
		seen = seen or art.call("jostling")
	check(not seen, "out of the room: no knock")
	m.progression.teeth_in_hand = 0

func _tank_knocks() -> void:
	var tank: Node3D = m.restroom.tank_art
	await reset()
	m.progression.teeth = 8
	m.vent._paid_ever = false
	knocks = 0
	var seen := false
	var t := 0.0
	while t < 3.0 and knocks == 0:
		await process_frame
		t += root.get_process_delta_time()
		seen = seen or tank.call("jostling")
	check(knocks == 1 and seen, "teeth in the shut tank before the first trade: the lid knocks (%.1f s)" % t)
	for case in ["hand", "lid", "paid", "empty", "away"]:
		await reset()
		m.progression.teeth = 8
		m.vent._paid_ever = false
		match case:
			"hand": m.progression.teeth_in_hand = 2
			"lid": m.tank_lid.pick()
			"paid": m.vent._paid_ever = true
			"empty": m.progression.teeth = 0
			"away": m.player.global_position = Vector3(0, 0.9, FPRestroom.HALF.z + 3.0)
		knocks = 0
		await wait(6.0)
		check(knocks == 0, "no lid knock when %s" % case)
		if case == "lid":
			m.tank_lid.replace_on_tank()
	m.vent._paid_ever = true
