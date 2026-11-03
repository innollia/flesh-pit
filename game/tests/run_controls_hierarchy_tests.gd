extends SceneTree

## Interaction order and hand fixes, through real input events and the
## normal Main process (2026-11-03 play):
## - one place decides a press (FPInteractions.plan/press): lid, belt hook,
##   aimed target (F or the right hand, one per frame), held item, dig
## - the canary hole in front of the sink takes F and the right button
## - right click at the tank leaves no bent hand: the held-teeth cup gives
##   way while the hands work flesh and comes back when they rest
## - looking down, the hands come in to the flesh they tear instead of
##   staying swung aside off the bottom of the screen

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

func key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func mouse(button: int, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)

func tap_key(code: Key) -> void:
	key(code, true)
	await frames(3)
	key(code, false)
	await frames(3)

func tap_mouse(button: int) -> void:
	mouse(button, true)
	await frames(3)
	mouse(button, false)
	await frames(3)

func face(yaw: float, pitch: float) -> void:
	m.player._yaw = yaw
	m.player._pitch = pitch
	m.player.rotation.y = yaw
	m.player.camera_pivot.rotation.x = pitch

## The eye moves with the pitch (head bow): settle the aim over a few frames.
func aim(point: Vector3) -> void:
	for i in range(4):
		var d: Vector3 = (point - m.player.camera.global_position).normalized()
		face(atan2(-d.x, -d.z), asin(clampf(d.y, -1.0, 1.0)))
		await frames(2)

func fresh_game(at: Vector3) -> void:
	if is_instance_valid(m):
		m.queue_free()
		await frames(2)
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://controls-hierarchy-test.bin"
	root.add_child(m)
	await frames(6)
	m.save_path = "user://controls-hierarchy-test.bin"
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.player.global_position = at
	m.player.velocity = Vector3.ZERO
	await frames(4)

func run() -> void:
	# --- canary hole from in front of the sink, crouched ---------------------
	for button in ["F", "RMB"]:
		await fresh_game(Vector3(-1.3, 0.9, -0.51))
		key(KEY_CTRL, true)
		await frames(15)
		await aim(m.canary_hole_point())
		check(m.interact_target() == "canary", "crouched in front of the sink the visible hole is the target (%s)" % button)
		check(FPInteractions.plan(m, "right") == "target:canary", "the right hand plans the canary")
		if button == "F":
			await tap_key(KEY_F)
		else:
			await tap_mouse(MOUSE_BUTTON_RIGHT)
		check(m.is_pulling_canary(), "%s begins the canary pull" % button)
		while m.is_pulling_canary():
			await frames(5)
		check(m.has_canary, "%s ends with the canary tucked in" % button)
		key(KEY_CTRL, false)
		await frames(3)
	# standing it stays hidden and out of reach (spec 03 9)
	await fresh_game(Vector3(-1.3, 0.9, -0.51))
	await aim(m.canary_hole_point())
	check(m.interact_target() != "canary", "standing, the hole is not a target")
	# the sink still stops the body and still washes
	await fresh_game(Vector3(-1.3, 0.9, -0.3))
	key(KEY_A, true)
	face(PI * 0.5, 0.0)
	await frames(60)
	key(KEY_A, false)
	face(PI * 0.5, 0.0)
	key(KEY_W, true)
	await frames(60)
	key(KEY_W, false)
	await frames(3)
	check(m.player.global_position.x > -2.25 + FPRestroom.SINK_BOWL_OUT - 0.05, "walking into the basin stops at its bowl (x %.2f)" % m.player.global_position.x)
	m.player.global_position = Vector3(-1.4, 0.9, -0.3)
	await frames(4)
	await aim(m.sink_point())
	check(m.interact_target() == "sink", "the basin is still the sink target (%s at %s)" % [m.interact_target(), m.player.global_position])

	# --- tank: right click takes a tooth, the hand is never left bent --------
	await fresh_game(Vector3(-1.25, 0.9, 0.72))
	m.progression.teeth = 12
	m.tank_lid.pick()
	m.tank_lid.drop()
	await aim(m.restroom.tank_art.to_global(Vector3(0, 0.3, 0)))
	check(m.interact_target() == "tank_teeth", "aiming at the open tank")
	await tap_mouse(MOUSE_BUTTON_RIGHT)
	check(m.progression.teeth_in_hand == 1, "one right click takes one tooth")
	check(m.hand_motions.kind == "scoop", "the right hand scoops")
	var rr: Node3D = m.hands_rig.get_hand_root("right")
	var reach_min := 0.0
	while m.hand_motions.kind == "scoop":
		reach_min = minf(reach_min, rr.position.z)
		await frames(1)
	check(reach_min < -0.45, "the scoop reaches out toward the tank, not down to the belly (z %.2f)" % reach_min)
	await frames(40)
	var roll: float = rr.basis.get_euler().z
	check(absf(roll) > 1.0 and absf(roll) <= FPHandMotions.HOLD_TEETH_ROLL + 0.01, "held teeth: palm turned up as far as a forearm turns (%.2f rad)" % roll)
	var wrist: Dictionary = m.hands_rig.get_joint_angles("right")
	check(absf(float(wrist.wrist_pitch)) < 20.0, "held teeth: the wrist is straight, not bent back (%.0f)" % wrist.wrist_pitch)
	# dig with the right hand while it holds teeth: the hand goes to work
	m.restroom.set_door_open(true, true)
	m.player.global_position = Vector3(0.0, 0.9, 1.25)
	face(PI, -0.3)
	await frames(10)
	mouse(MOUSE_BUTTON_RIGHT, true)
	var torn := [0]
	var cupped_at_tear := [0]
	var on_tear := func(_p: Vector3):
		torn[0] += 1
		if absf(rr.basis.get_euler().z) > 0.3:
			cupped_at_tear[0] += 1
	m.chewer.cell_torn.connect(on_tear)
	for i in range(80):
		await frames(1)
		face(PI, -0.3)
	mouse(MOUSE_BUTTON_RIGHT, false)
	check(torn[0] > 0, "the right hand tears flesh while holding teeth (%d)" % torn[0])
	check(cupped_at_tear[0] == 0, "no tear happens with the hand still cupped")
	await frames(60)
	check(m.hands_rig.state == FDKHandsRig.HandState.IDLE and absf(rr.basis.get_euler().z) > 1.0, "after digging the hand comes back to holding the teeth")
	check(m.progression.teeth_in_hand == 1, "the teeth stay in the hand")
	m.chewer.cell_torn.disconnect(on_tear)

	# --- looking down: the tearing hand is in view at the flesh --------------
	# one session going steeper, as a player digs the floor down past the door
	# (no belt: an aimed belt hook would rightly take the press instead)
	await fresh_game(Vector3(0.0, 0.9, 1.25))
	m.restroom.set_door_open(true, true)
	for pitch_deg in [-35.0, -50.0, -65.0, -80.0]:
		m.player.global_position = Vector3(0.0, 0.9, 1.25)
		m.player.velocity = Vector3.ZERO
		face(PI, deg_to_rad(pitch_deg))
		await frames(20)
		if pitch_deg < -50.0:
			check(m.hands_rig.aside > 0.4, "resting hands swing aside looking down %.0f" % pitch_deg)
		var at_tear := []
		var on_down := func(p: Vector3):
			var lead: Node3D = m.hands_rig.get_hand_root("right" if m.hands_rig._lead == 0 else "left")
			var cam: Camera3D = m.player.camera
			var size: Vector2 = cam.get_viewport().get_visible_rect().size
			var sp: Vector2 = cam.unproject_position(lead.global_position)
			at_tear.append(sp.y / size.y)
		m.chewer.cell_torn.connect(on_down)
		var grabs := [0, 0.0]
		var on_grab := func(_c): grabs[0] += 1
		var on_prog := func(r, _c): grabs[1] = maxf(grabs[1], r)
		m.chewer.grab_started.connect(on_grab)
		m.chewer.chew_progress.connect(on_prog)
		mouse(MOUSE_BUTTON_LEFT, true)
		for i in range(420):
			await frames(1)
			face(PI, deg_to_rad(pitch_deg))
		mouse(MOUSE_BUTTON_LEFT, false)
		await frames(3)
		var hit_dbg: Dictionary = m._look_hit()
		check(not at_tear.is_empty(), "looking down %.0f tears flesh (hit %s at %s, fill %.2f, state %d, tissue %d, grabs %s)" % [pitch_deg, str(hit_dbg.get("collider", "none")), str(hit_dbg.get("position", "-")), m.stomach.fill_ratio(), m.hands_rig.state, m._world_tissue(hit_dbg.get("position", Vector3.ZERO)), str(grabs)])
		var worst := 0.0
		for y in at_tear:
			worst = maxf(worst, y)
		check(worst < 0.85, "every tear at %.0f has the leading hand on screen near the aim (lowest %.2f of the height)" % [pitch_deg, worst])
		await frames(40)
		check((pitch_deg >= -50.0 or m.hands_rig.aside > 0.4) and not m.hands_rig.has_reach_point(), "released, the hands rest (aside when bowed) and drop the grab point")
		m.chewer.cell_torn.disconnect(on_down)
		m.chewer.grab_started.disconnect(on_grab)
		m.chewer.chew_progress.disconnect(on_prog)

	# --- the hierarchy -------------------------------------------------------
	await fresh_game(Vector3(0, 0.9, 0.8))
	var width: float = 2.0 * FPRestroom.DOOR_HALF_W - 0.01
	var door_mid: Vector3 = m.restroom.door_pivot.to_global(Vector3(width * 0.5, FPRestroom.DOOR_H * 0.5, 0))
	await aim(door_mid)
	check(m.interact_target() == "door", "aiming at the door")
	check(FPInteractions.plan(m, "left") == "dig", "the left hand never acts on a target")
	await tap_mouse(MOUSE_BUTTON_LEFT)
	await frames(30)
	check(not m.restroom.is_door_open(), "left click does not open the door")
	await tap_mouse(MOUSE_BUTTON_RIGHT)
	await frames(45)
	check(m.restroom.is_door_open(), "right click opens the aimed door like F")
	await aim(door_mid)
	# F and right click in the same frame: one press, one action
	key(KEY_F, true)
	mouse(MOUSE_BUTTON_RIGHT, true)
	await frames(3)
	key(KEY_F, false)
	mouse(MOUSE_BUTTON_RIGHT, false)
	await frames(45)
	check(not m.restroom.is_door_open(), "F and right click together toggle the door once")
	check(not m.hand_actions.blocked[1], "release frees the hand")
	# a right press on a target keeps that hand from digging while held
	await aim(door_mid)
	mouse(MOUSE_BUTTON_RIGHT, true)
	await frames(3)
	check(m.hand_actions.blocked[1] and not m.chewer.is_chewing(), "holding the press on a target does not start digging")
	mouse(MOUSE_BUTTON_RIGHT, false)
	await frames(45)
	# a click pressed and released before the next frame still counts once
	var open_before: bool = m.restroom.is_door_open()
	await aim(door_mid)
	mouse(MOUSE_BUTTON_RIGHT, true)
	mouse(MOUSE_BUTTON_RIGHT, false)
	await frames(45)
	check(m.restroom.is_door_open() != open_before, "a click shorter than a frame still acts once")
	# a held item: target first, item otherwise
	m.progression.grant_item("spray_cheap")
	m.equip_hand("spray_cheap", FDKToolKit.Hand.RIGHT)
	await aim(door_mid)
	check(FPInteractions.plan(m, "right") == "target:door", "an aimed target comes before the held item")
	face(0.0, -0.2)
	await frames(4)
	if m.interact_target() == "":
		check(FPInteractions.plan(m, "right") == "item:spray_cheap", "with nothing aimed the held item is used")
	# the held lid: the right hand that holds it puts it down
	await fresh_game(Vector3(-1.25, 0.9, 0.72))
	await aim(m.tank_lid.lid.global_position)
	await tap_mouse(MOUSE_BUTTON_RIGHT)
	check(m.tank_lid.held, "right click lifts the aimed lid")
	face(m.player._yaw + 1.2, -0.4)
	await frames(4)
	check(FPInteractions.plan(m, "left") == "none", "the left hand does nothing while the right holds the lid")
	await tap_mouse(MOUSE_BUTTON_RIGHT)
	check(not m.tank_lid.held and not m.tank_lid.on_tank, "right click puts the held lid down")
	# the belt: hand buttons only
	await fresh_game(Vector3(0, 0.95, 0))
	m.progression.has_belt = true
	m.progression.grant_item("knife")
	m.equip_tool("")
	var found := false
	for yi in range(-12, 13):
		for pi in range(0, 14):
			face(yi * 0.08, -1.0 - pi * 0.04)
			m.belt_swap.tick(0.0)
			if m.belt_swap.aimed_hook() == 0:
				found = true
				break
		if found:
			break
	check(found, "a belt hook can be aimed")
	if found:
		check(FPInteractions.plan(m, "interact") != "belt", "F does not swap belt items")
		check(FPInteractions.plan(m, "right") == "belt", "the hand button swaps with the aimed hook")
	m.queue_free()
	await frames(2)
	print("CONTROLS HIERARCHY: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
