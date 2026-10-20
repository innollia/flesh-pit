extends SceneTree

## UI and effect polish (2026-10-19: "Esc screen and stomach UI are not
## pretty and not this game"): the Esc screen shuts the eyes and opens them
## over the running game; the stomach gauge and its mouth sit together
## bottom left; textured blobs really carry UVs; bits fly out of a tear and
## go away; the opening's vomit key goes once used; death wakes with lids.

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://ui-polish-test.bin"
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

func run() -> void:
	await frames(5)
	m.finish_opening()
	# --- Esc: eyes shut, then open over the running game
	var pm: FPPauseMenu = m.pause_menu
	m._esc_guard_frame = -10
	m.open_pause_menu()
	check(pm.is_open() and paused, "Esc shuts the eyes and holds the world")
	await frames(40)
	check(pm.shut > 0.99, "the lids close (%.2f)" % pm.shut)
	check(pm.column.modulate.a > 0.99, "the items show on the shut lids")
	check((pm.buttons[0] as Button).text == "눈 뜨기", "the first item opens the eyes")
	check(pm.root.get_viewport().gui_get_focus_owner() == pm.buttons[0], "and has focus")
	pm.resume()
	check(not pm.is_open() and not paused, "눈 뜨기 lets the world run at once")
	check(pm.visible and pm.root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the lids open over the game, passing input")
	check(pm.root.get_viewport().gui_get_focus_owner() == null, "no menu item keeps focus while the eyes open")
	await frames(40)
	check(not pm.visible and pm.shut <= 0.0, "fully open, the layer is gone")
	# --- stomach gauge and the mouth at its end
	var hud: FPStomachHUD = m.stomach_hud
	m.stomach.fill = m.stomach.config.capacity + m.stomach.config.overfill_capacity * 0.8
	await frames(30)
	check(m.vomit_button.shown and m.vomit_button.visible, "past the threshold the mouth shows")
	var gut_rect: Rect2 = hud.gut.get_global_rect()
	var mouth_rect: Rect2 = m.vomit_button.get_global_rect()
	check(absf(mouth_rect.position.x - gut_rect.end.x) < 12.0 * FPStomachHUD.ui_scale(hud.size.y), "the mouth sits at the gauge's end")
	check(absf(mouth_rect.get_center().y - gut_rect.get_center().y) < 8.0 * FPStomachHUD.ui_scale(hud.size.y), "level with the gauge")
	check(mouth_rect.position.y + mouth_rect.size.y <= hud.size.y + 0.5, "inside the screen")
	m.stomach.fill = 0.0
	await frames(5)
	# --- textured blobs carry UVs
	var mass: MeshInstance3D = m.stomach_view.get_node("Mass")
	var uvs: PackedVector2Array = mass.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var spread := Rect2(uvs[0], Vector2.ZERO)
	for uv in uvs:
		spread = spread.expand(uv)
	check(uvs.size() > 0 and spread.size.length() > 0.5, "the stomach mass has real UVs (spread %s)" % spread.size)
	var chunk: MeshInstance3D = m.hands_rig.find_child("TornChunk", true, false)
	check(chunk != null and (chunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() > 0, "the torn chunk in the hand has UVs")
	# --- bits out of a tear fly and go
	var at: Vector3 = m.player.camera.global_position + Vector3(0, -0.2, -0.6)
	m.gore.burst(at, Vector3(0, 0, 1), 3, 7)
	check(m.gore.live_count() == 10, "a tear throws bits and drops")
	await frames(3)
	check(m.gore.get_node("Bits").multimesh.visible_instance_count == 3, "drawn as MultiMesh instances")
	var t := 0.0
	while t < 3.0 and m.gore.live_count() > 0:
		await process_frame
		t += get_root().get_process_delta_time()
	check(m.gore.live_count() == 0, "and they are gone within a few seconds (%.1f s)" % t)
	# s4: bits torn above the player landed on its head and hung in the air
	var head: Vector3 = m.player.global_position + Vector3(0, 1.4, 0)
	m.gore.burst(head, Vector3.DOWN, 1, 0)
	var floor_y: float = m.gore.get("_live_bits")[0]["floor"]
	check(floor_y < m.player.global_position.y - 0.5, "bits from above the player fall past its body to the floor (floor %.2f, body %.2f)" % [floor_y, m.player.global_position.y])
	m.gore.set("_live_bits", [])
	# --- the opening's vomit key goes once used
	var hints = m.opening_view.hints
	hints.vomit_learned = false
	var ev := InputEventAction.new()
	ev.action = "fp_vomit"
	ev.pressed = true
	hints.vomit_hint = false
	hints._input(ev)
	check(not hints.vomit_learned, "V where the icon is not shown (it may only retch) does not retire it")
	hints.vomit_hint = true
	hints._input(ev)
	check(hints.vomit_learned, "pressing V once where it shows retires the opening's V icon")
	# --- eye mutations shut differently
	var lid_mat: ShaderMaterial = pm.lids.material
	pm.set_eyes(["T5", "M03"], 0.7)
	check(lid_mat.get_shader_parameter("fish") == 1.0 and lid_mat.get_shader_parameter("magnet") == 1.0 and lid_mat.get_shader_parameter("owl") == 0.0, "fish and magnet eyes shut their own way")
	check(is_equal_approx(lid_mat.get_shader_parameter("field_angle"), 0.7), "the magnetic eye's field points where it is told")
	pm.set_eyes([])
	check(lid_mat.get_shader_parameter("fish") == 0.0 and lid_mat.get_shader_parameter("echo") == 0.0, "plain eyes again")
	var fa: float = m.restroom_field_angle()
	m.player._yaw += PI * 0.5
	# the body turns in physics; wait by time, not frames (flaky under load)
	var head_t := 0.0
	while head_t < 0.5 and absf(wrapf(m.restroom_field_angle() - fa, -PI, PI)) <= 1.0:
		await process_frame
		head_t += get_root().get_process_delta_time()
	check(absf(wrapf(m.restroom_field_angle() - fa, -PI, PI)) > 1.0, "the field turns with the head (%.2f -> %.2f)" % [fa, m.restroom_field_angle()])
	# --- the key screen: a turntable of the player's body, one per action
	var kb: FPKeybindMenu = m.keybind_menu
	m.open_keybind_menu()
	await frames(5)
	var doll: Node = kb.doll
	check(doll.call("front_action") == kb._order[0], "the first action is in the light")
	var shown_caps := 0
	for a in kb.buttons:
		if (kb.buttons[a] as Button).visible:
			shown_caps += 1
	check(shown_caps == 1 and (kb.buttons[kb._order[0]] as Button).visible, "only its key cap shows")
	var waiting_bodies := 0
	for sl in doll.slots:
		if (sl.body as Node3D).visible and absf((sl.body as Node3D).position.x) > 0.8:
			waiting_bodies += 1
	check(waiting_bodies == 2, "the previous and next wait at the sides (%d)" % waiting_bodies)
	var right_ev := InputEventAction.new()
	right_ev.action = "ui_right"
	right_ev.pressed = true
	kb._input(right_ev)
	check(kb.current == 1 and doll.call("turning"), "→ turns the table to the next action")
	check(kb.action_label.text == String(m.keybind_defaults()[kb._order[1]]["설명"]) and (kb.buttons[kb._order[1]] as Button).visible, "its name and key cap show")
	var turn_t := 0.0
	while turn_t < 3.0 and (doll.call("turning") or doll.slots.all(func(sl): return sl.w < 0.6)):
		await process_frame
		turn_t += get_root().get_process_delta_time()
	check(not doll.call("turning") and doll.call("front_action") == kb._order[1], "the next body arrives in the light (%.2f s)" % turn_t)
	var front_w := 0.0
	for sl in doll.slots:
		front_w = maxf(front_w, sl.w)
	check(front_w > 0.5, "and starts its motion")
	kb.prev_arrow.pressed.emit()
	turn_t = 0.0
	while turn_t < 3.0 and doll.call("turning"):
		await process_frame
		turn_t += get_root().get_process_delta_time()
	check(kb.current == 0 and doll.call("front_action") == kb._order[0], "the left arrow turns back")
	kb.show_action(kb._order.size() - 1)
	check(doll.call("front_action") == kb._order.back(), "jumping goes the short way round")
	(kb.buttons["fp_carry"] as Button).pressed.emit()
	check(kb.waiting == "fp_carry" and doll.call("front_action") == "fp_carry", "clicking a cap turns its action into the light and waits for the key")
	kb.waiting = ""
	kb.close()
	# --- death wakes with the lids
	m.die("test")
	check(m.wake_lids.playing() and m.wake_lids.visible, "waking in the restroom starts with shut eyes")
	t = 0.0
	while t < 4.0 and m.wake_lids.playing():
		await process_frame
		t += get_root().get_process_delta_time()
	check(not m.wake_lids.playing() and not m.wake_lids.visible, "and the eyes are open within a few seconds (%.1f s)" % t)
	# --- the vent being holds its offer out in a hand you can see (2026-10-20)
	var art: Node3D = m.vent.art
	var arm: Node3D = art.get_node("BeingArm")
	m.player.global_position = Vector3(0.1, 0.9, 0.2)
	m.vent.open(30)
	await frames(10)
	check(not arm.visible, "no arm while nothing is offered")
	m.progression.teeth_in_hand = 30
	var ids: Array = m.place_teeth_at_vent()
	t = 0.0
	while t < 1.6:
		await process_frame
		t += get_root().get_process_delta_time()
	var item: Node3D = art.call("item_node", 0)
	var face_y: float = FPRestroom.VENT_CENTER.y
	check(not ids.is_empty() and arm.visible and item.is_visible_in_tree(), "the offer comes out in the being's hand")
	check(item.global_position.y < face_y - 0.25, "the hand holds it below the ceiling, in the light (%.2f m under)" % (face_y - item.global_position.y))
	var to_player: Vector3 = m.player.camera.global_position - FPRestroom.VENT_CENTER
	var toward: Vector3 = item.global_position - FPRestroom.VENT_CENTER
	check(Vector2(toward.x, toward.z).dot(Vector2(to_player.x, to_player.z)) > 0.0, "it reaches toward the player")
	var anchor: Node3D = m.vent.offer_nodes()[0]
	check(anchor.global_position.distance_to(item.global_position) < 0.01, "aiming picks the item where the hand holds it")
	check(FPInteractions.get_candidates(m).any(func(c): return c[0] == "vent" and (c[1] as Vector3).distance_to(m.vent.offer_center()) < 0.01), "the held-out hand is an aim point for taking")
	m.take_vent_offer(ids[0])
	t = 0.0
	while t < 1.2:
		await process_frame
		t += get_root().get_process_delta_time()
	check(not arm.visible, "after the take the arm goes back up into the dark")
	m.vent.close()
	# --- first expedition comes back (decision 0009, playtests s1/s4)
	m.lever_settled = false
	m.player.global_position = m.RESTROOM_CENTER + Vector3(1.0, -0.5, 4.5)
	m.stomach.add_flesh(60.0)
	var fill0: float = m.stomach.fill
	var gagged := [0]
	m.dry_heaved.connect(func(): gagged[0] += 1)
	m.request_vomit()
	check(m.stomach.fill == fill0 and gagged[0] == 1 and m.hand_motions.kind == "gag", "before the first lever settlement V out in the flesh only retches; the stomach keeps it")
	m.stomach.add_flesh(80.0)
	await frames(2)
	check(not m.opening_view.hints.vomit_hint and not m.vomit_button.shown, "out in the flesh the full stomach shows no vomit key")
	m.player.global_position = m.restroom.toilet.to_global(Vector3(0, 0.9, 0.5))
	await frames(2)
	check(m.opening_view.hints.vomit_hint and m.vomit_button.shown, "at the toilet it does")
	m.lever_settled = true
	m.player.global_position = m.RESTROOM_CENTER + Vector3(1.0, -0.5, 4.5)
	m.request_vomit()
	check(m.stomach.fill == 0.0, "after a lever settlement V outside empties the stomach as before")
	check(bool(m.serialize()["lever_settled"]), "the first settlement is saved")
	# --- the wrist compass points home
	var compass: Node3D = m.art_hookup.wrist_compass
	var active_rig: Node3D = m.art_hookup.get("_rig")
	check(compass.get_parent() == active_rig.get_node("HandLeft") and compass.is_visible_in_tree(), "the compass is on the left forearm of the hands in use")
	var settle_t := 0.0
	while settle_t < 1.2:
		await process_frame
		settle_t += get_root().get_process_delta_time()
	var needle: Node3D = compass.get_node("Needle")
	var tip: Vector3 = -needle.global_transform.basis.z
	var face_n: Vector3 = compass.global_transform.basis.y.normalized()
	var home: Vector3 = m.RESTROOM_CENTER - compass.global_position
	var flat_home := (home - face_n * home.dot(face_n)).normalized()
	check((tip - face_n * tip.dot(face_n)).normalized().dot(flat_home) > 0.97, "out in the flesh the needle points at the restroom (%.2f)" % (tip - face_n * tip.dot(face_n)).normalized().dot(flat_home))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.save_path))
	print("--- ui polish: %d passed, %d failed ---" % [passed, failed])
	m.queue_free()
	quit(1 if failed else 0)
