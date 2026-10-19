extends SceneTree

## Picking teeth at the open tank (2026-10-19 play): F leans the head in
## over the tank mouth and picks one tooth at a time (held F repeats, right
## click puts one back); the held teeth sit on the cupped right palm, one
## real tooth per tooth, in the lean and walking around; moving, the lid or
## looking away ends the lean and the teeth stay in the hand.

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	root.add_child(m)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func look_at_point(p: Vector3) -> void:
	var eye: Vector3 = m.player.camera.global_position
	var d := (p - eye).normalized()
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = asin(clampf(d.y, -1, 1))

const LEAN_KEYS := ["fdk_move_left", "fdk_move_right", "fdk_move_left", "fdk_move_right", "fdk_move_forward"]

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func run() -> void:
	await frames(5)
	m.finish_opening()
	m.vent.instant_voice = true
	m.progression.teeth = 20
	m.tank_lid.pick()
	m.tank_lid.drop()
	check(not m.tank_lid.on_tank and not m.tank_lid.held, "the lid is off the tank")
	var tank: Vector3 = m.restroom.tank_art.to_global(Vector3(0, 0.3, 0))
	var mouth: Vector3 = m.restroom.tank_art.to_global(Vector3(0, 0.34, 0))
	m.player.global_position = Vector3(-1.39, 0.9, 0.8)
	for i in range(20):
		look_at_point(tank)
		await physics_frame
	var far: float = m.player.camera.global_position.distance_to(mouth)
	check(m.interact_target() == "tank_teeth", "standing in front of the open tank aims at the teeth")
	m._interact()
	check(m.hand_motions.tank_leaning() and m.progression.teeth_in_hand == 1, "F leans in and takes one tooth")
	# the lean takes TANK_LEAN_IN seconds of game time, however fast frames run
	var waited := 0
	while m.hand_motions.weight() < 0.999 and waited < 600:
		await process_frame
		waited += 1
	await frames(2)
	var near: float = m.player.camera.global_position.distance_to(mouth)
	check(near < 0.6 and near < far - 0.4, "the head bends over the tank mouth (%.2f m, was %.2f m)" % [near, far])
	check(m.interact_target() == "tank_teeth", "and still aims at the teeth")
	var ht: MultiMeshInstance3D = m.art_hookup.held_teeth
	check(ht.visible and ht.multimesh.visible_instance_count == 1, "one tooth on the palm")
	for k in range(5):
		m.scoop_teeth()
		check(m.hand_motions._dip_t < 0.05, "the hand dips in for tooth %d" % (k + 2))
		await frames(6)
	check(m.progression.teeth_in_hand == 6 and m.progression.teeth == 14, "one tooth at a time (6 in hand, 14 left)")
	check(ht.multimesh.visible_instance_count == 6, "six real teeth on the palm, never a number")
	m.put_tooth_back()
	await frames(2)
	check(m.progression.teeth_in_hand == 5 and m.progression.teeth == 15 and ht.multimesh.visible_instance_count == 5, "right click puts one back")
	# the palm with the teeth faces the eye
	await frames(20)
	var wrist: Node3D = ht.get_parent()
	var to_eye: Vector3 = (m.player.camera.global_position - wrist.global_position).normalized()
	check((wrist.global_basis * Vector3.DOWN).normalized().dot(to_eye) > 0.4, "the palm (and the teeth on it) faces the eye")
	# left/right walk the head round the tank; the body stays put
	var body_at: Vector3 = m.player.global_position
	var eye_at: Vector3 = m.player.camera.global_position
	Input.action_press("fdk_move_left")
	var held := 0.0
	while held < 0.5:
		await process_frame
		held += get_root().get_process_delta_time()
	Input.action_release("fdk_move_left")
	await frames(3)
	check(m.hand_motions.tank_leaning(), "walking sideways keeps the lean")
	check(m.hand_motions.lean_orbit < -0.3, "the head walks round the tank (%.2f rad)" % m.hand_motions.lean_orbit)
	check(m.player.global_position.distance_to(body_at) < 0.05, "the body stays put while leaning")
	check(m.player.camera.global_position.distance_to(eye_at) > 0.05 and m.player.camera.global_position.distance_to(mouth) < 0.6, "the eye moves round, still bent over the tank mouth")
	# moving back ends the lean; the teeth stay in the hand, still shown
	Input.action_press("fdk_move_back")
	await frames(2)
	m.hand_motions.check_cancel()
	await frames(20)
	Input.action_release("fdk_move_back")
	await frames(20)
	check(not m.hand_motions.tank_leaning(), "moving ends the lean")
	check(m.progression.teeth_in_hand == 5 and ht.visible, "the teeth stay in the hand")
	var right: Node3D = m.hands_rig.get_hand_root("right")
	check(right.basis.get_euler().length() > 1.0, "the right hand is turned palm-up while it holds teeth")
	# the lid going back on ends a lean
	m.player.global_position = Vector3(-1.39, 0.9, 0.8)
	for i in range(20):
		look_at_point(tank)
		await physics_frame
	m._interact()
	check(m.hand_motions.tank_leaning(), "leaning in again")
	# frantic movement gets you out
	for k in range(LEAN_KEYS.size()):
		Input.action_press(LEAN_KEYS[k])
		await frames(2)
		Input.action_release(LEAN_KEYS[k])
		await frames(2)
	await frames(2)
	check(not m.hand_motions.tank_leaning(), "frantic movement ends the lean")
	for i in range(20):
		look_at_point(tank)
		await physics_frame
	m._interact()
	m.tank_lid.on_tank = true
	await frames(3)
	check(not m.hand_motions.tank_leaning(), "the lid back on ends the lean")
	m.tank_lid.on_tank = false
	# empty hand: the hand turns back
	while m.progression.teeth_in_hand > 0:
		m.put_tooth_back()
	var turned := 0
	while not right.basis.is_equal_approx(Basis.IDENTITY) and turned < 600:
		await process_frame
		turned += 1
	check(not ht.visible and right.basis.is_equal_approx(Basis.IDENTITY), "an empty hand is the rig's own hand again")
	# F at the toilet settles like V, standing by it without aiming at it
	m.stomach.add_flesh(20.0)
	m.player.global_position = Vector3(-1.39, 0.9, 0.8)
	m.player._pitch = 0.6
	await frames(3)
	check(m.interact_target() == "" and m._near_toilet(), "standing by the toilet, aiming at nothing")
	m._interact()
	check(m.is_settling(), "F settles at the toilet as V does")
	m.leave_settlement()
	print("--- tank lean: %d passed, %d failed ---" % [passed, failed])
	m.queue_free()
	quit(1 if failed else 0)
