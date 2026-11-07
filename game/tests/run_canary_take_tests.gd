extends SceneTree

## Canary take (user 2026-11-08), through real input events and Main's own
## process:
## - standing over the hole, the aim ring shows the crouch key cap, read
##   from the crouch keybind (Ctrl, then whatever it is rebound to)
## - crouched, the hole is the left hand's: the ring lights the left button
##   only, right click does not start it, left click does
## - the LEFT hand goes deep into the hole, a crowd of canaries perches on
##   it, one shake throws them all off back into the hole, the hand stirs
##   inside and pulls out exactly one bird; the right palm braces the floor
## - possession only after the tuck, one canary, and a move press before
##   the tuck cancels it with no canary and nothing left behind

var m: Node3D
var passed := 0
var failed := 0
const SAVE := "user://canary-take-test.bin"
const KEYS := "user://keybinds_test_canary_take.json"

func _init() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(KEYS))
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

func aim(point: Vector3) -> void:
	for i in range(4):
		var d: Vector3 = (point - m.player.camera.global_position).normalized()
		m.player._yaw = atan2(-d.x, -d.z)
		m.player._pitch = asin(clampf(d.y, -1.0, 1.0))
		m.player.rotation.y = m.player._yaw
		m.player.camera_pivot.rotation.x = m.player._pitch
		await frames(2)

func fresh_game() -> void:
	if is_instance_valid(m):
		m.queue_free()
		await frames(2)
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = KEYS
	m.save_path = SAVE
	root.add_child(m)
	await frames(6)
	m.save_path = SAVE
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.player.global_position = Vector3(-1.3, 0.9, -0.51)
	m.player.velocity = Vector3.ZERO
	await frames(4)

func crouch_at_hole() -> void:
	key(KEY_CTRL, true)
	await frames(15)
	await aim(m.canary_hole_point())
	await frames(3)

func run() -> void:
	await fresh_game()
	# --- standing: the crouch key cap over the hole ---------------------------
	await aim(m.canary_hole_point())
	await frames(4)
	var ring: Control = m.interact_ring
	check(m.interact_target() != "canary", "standing, the hole is out of reach")
	check(ring.shown and ring.action == "fdk_crouch", "standing over the hole the ring shows the crouch key (%s %s)" % [ring.shown, ring.action])
	check(ring.call("_key_label") == "Ctrl", "the cap reads the bound crouch key Ctrl (%s)" % ring.call("_key_label"))
	check(not ring.hand_left and not ring.hand_right, "no mouse button is lit for crouching")
	ring.device = "mouse"
	check(ring.action in ring.KEY_ACTIONS, "a mouse player still sees the key cap")
	check(m.rebind_key("fdk_crouch", "C"), "crouch rebinds to C")
	await frames(3)
	check(ring.call("_key_label") == "C", "the cap follows the rebinding (%s)" % ring.call("_key_label"))
	await tap_key(KEY_C)
	check(ring.action == "fdk_crouch", "tapping the rebound key keeps the hint until the body is down")
	key(KEY_C, true)
	await frames(15)
	await aim(m.canary_hole_point())
	await frames(3)
	check(m.player._is_crouching and m.interact_target() == "canary", "the rebound key crouches and the hole becomes the target")
	check(ring.action != "fdk_crouch", "crouched, the crouch hint gives way to the hole")
	key(KEY_C, false)
	await frames(8)
	m.rebind_key("fdk_crouch", "Ctrl")
	await frames(3)
	check(ring.call("_key_label") == "Ctrl", "rebinding back shows Ctrl")
	# looking away: no hint
	await aim(m.player.global_position + Vector3(0, 0.6, 1.5))
	await frames(3)
	check(ring.action != "fdk_crouch" or not ring.shown, "looking away from the hole, no crouch hint")

	# --- crouched: the left hand's ---------------------------------------------
	await crouch_at_hole()
	check(m.interact_target() == "canary", "crouched, the hole is the target")
	check(ring.hand_left and not ring.hand_right, "the ring lights only the left button")
	check(FPInteractions.plan(m, "left") == "target:canary", "left click plans the canary")
	check(FPInteractions.plan(m, "right") != "target:canary", "right click leaves the canary to the left hand")
	await tap_mouse(MOUSE_BUTTON_RIGHT)
	check(not m.is_pulling_canary(), "right click does not start the take")
	await frames(10)
	await aim(m.canary_hole_point())
	await frames(3)
	mouse(MOUSE_BUTTON_LEFT, true)
	await frames(2)
	mouse(MOUSE_BUTTON_LEFT, false)
	check(m.is_pulling_canary(), "left click starts the take")
	check(not ring.shown, "the ring stays out of the take")
	var pull: FPCanaryPull = m.canary_pull
	var stages: Array[String] = []
	var max_perched := 0
	var deep_inside := false
	var right_braced := true
	var flew := false
	var perched_after_shake := 0
	var held_before_shake := false
	var taken_at := -1.0
	var hole: Vector3 = m.canary_hole_point()
	var wall_x: float = -FPRestroom.HALF.x
	while m.is_pulling_canary():
		var u: float = pull.progress()
		var s: String = pull.stage()
		if stages.is_empty() or stages[-1] != s:
			stages.append(s)
		max_perched = maxi(max_perched, pull.perched_count())
		var left: Node3D = pull.active_rig().get_node("HandLeft/Wrist")
		var right: Node3D = pull.active_rig().get_node("HandRight/Wrist")
		if u > 0.2 and u < 0.28 and left.global_position.x < wall_x - 0.08 and absf(left.global_position.z - hole.z) < 0.08:
			deep_inside = true
		if u > 0.2 and u < 0.8 and right.global_position.distance_to(hole) < 0.3:
			right_braced = false
		if u > FPCanaryPull.SHAKE_RELEASE + 0.005 and u < FPCanaryPull.SHAKE_RELEASE + 0.05:
			if pull.flying_count() > 0: flew = true
			perched_after_shake = maxi(perched_after_shake, pull.perched_count())
		if u < FPCanaryPull.P_GRAB.x and pull.bird.visible:
			held_before_shake = true
		if m.has_canary and taken_at < 0.0:
			taken_at = u
		await frames(1)
	print("stages ", stages, " max_perched ", max_perched, " taken_at ", taken_at)
	check(stages == ["reach", "swarm", "shake", "stir", "pull", "tuck", "stand"], "phases come in order (%s)" % [stages])
	check(deep_inside, "the left hand goes deep into the hole, past the wall face")
	check(right_braced, "the right hand stays braced away from the hole")
	check(max_perched >= 12, "a crowd of canaries perches on the left hand (%d)" % max_perched)
	check(flew and perched_after_shake == 0, "one shake throws every bird off the hand")
	check(not held_before_shake, "no bird is held before the stir and grab")
	check(taken_at >= FPCanaryPull.TUCK_AT - 0.01, "possession only after the tuck (%.2f)" % taken_at)
	check(m.has_canary, "the take ends with the canary")
	var leftover := 0
	for c in m.get_children():
		if str(c.name).begins_with("SwarmCanary") or str(c.name) == "CaughtCanary":
			leftover += 1 if not c.is_queued_for_deletion() else 0
	check(leftover == 0, "no bird nodes stay behind (%d)" % leftover)
	check(m.player.is_physics_processing(), "movement comes back")
	await frames(10)
	await aim(m.canary_hole_point())
	await frames(3)
	check(m.interact_target() != "canary" and not m.begin_canary_pull(), "only one canary: the hole is done")
	key(KEY_CTRL, false)
	await frames(5)

	# --- cancel before the tuck ----------------------------------------------
	await fresh_game()
	await crouch_at_hole()
	var collider: Transform3D = m.player.collision_shape.transform
	mouse(MOUSE_BUTTON_LEFT, true)
	await frames(2)
	mouse(MOUSE_BUTTON_LEFT, false)
	check(m.is_pulling_canary(), "left click starts a second take")
	while m.is_pulling_canary() and m.canary_pull.progress() < 0.4:
		await frames(1)
	await tap_key(KEY_W)
	check(m.canary_pull == null or m.canary_pull.cancelled, "a move press cancels the take")
	var waited := 0
	while m.is_pulling_canary() and waited < 120:
		await frames(1)
		waited += 1
	check(not m.is_pulling_canary() and waited < 60, "the cancel eases out quickly (%d frames)" % waited)
	check(not m.has_canary, "a cancelled take gives no canary")
	check(m.player.collision_shape.transform.is_equal_approx(collider), "the cancel restores the crouched collider")
	leftover = 0
	for c in m.get_children():
		if str(c.name).begins_with("SwarmCanary") and not c.is_queued_for_deletion():
			leftover += 1
	check(leftover == 0, "the cancelled crowd is cleared")
	key(KEY_CTRL, false)
	await frames(3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(KEYS))
	print("Canary take: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
