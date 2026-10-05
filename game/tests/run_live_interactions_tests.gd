extends SceneTree

var m: Node3D
var passed := 0
var failed := 0
var folder: String

func _init() -> void:
	var isolated_runner: bool = str(get_script().resource_path).replace("\\", "/").contains("/.dryforge/evidence/checks/")
	if not OS.get_user_data_dir().contains("flesh-pit-restoration-") and not isolated_runner:
		quit(2)
		return
	Engine.max_fps = 60
	root.size = Vector2i(640, 360)
	folder = ProjectSettings.globalize_path("res://../.dryforge/evidence/live-interactions")
	DirAccess.make_dir_recursive_absolute(folder)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(count: int) -> void:
	for i in range(count): await physics_frame
	await process_frame

func key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)

func press(code: Key) -> void:
	key(code, true)
	await frames(3)
	key(code, false)
	await frames(3)

func aim(point: Vector3) -> void:
	var direction: Vector3 = (point - m.player.camera.global_position).normalized()
	m.player._yaw = atan2(-direction.x, -direction.z)
	m.player._pitch = asin(direction.y)
	m.player.rotation.y = m.player._yaw
	m.player.camera_pivot.rotation.x = m.player._pitch

func game_at(point: Vector3) -> void:
	if is_instance_valid(m):
		m.queue_free()
		await frames(2)
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = folder.path_join("test.bin")
	root.add_child(m)
	await frames(6)
	m.save_path = folder.path_join("test.bin")
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.player.global_position = point
	await frames(2)

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(name + ".png"))

func run() -> void:
	await game_at(Vector3(-1.25, 0.9, 0.72))
	aim(m.toilet_point())
	await frames(30)
	check(m.interact_target() == "toilet", "actual bowl aim")
	check(m.interact_ring.action == "fp_vomit" and m.interact_ring._key_label() == "V", "bowl shows actual V input")
	await shot("toilet-V-prompt")
	m.stomach.add_flesh(8)
	key(KEY_V, true)
	await frames(5)
	check(m.is_settling(), "held entry V does not immediately exit")
	key(KEY_V, false)
	await frames(3)
	await press(KEY_W)
	check(not m.is_settling() and m.player.is_physics_processing(), "raw W leaves vomit view")
	check(m.toilet.has_contents(), "standing does not flush contents")
	for code in [KEY_A, KEY_S, KEY_D, KEY_SPACE]:
		m.player.global_position = Vector3(-1.25, 0.9, 0.72)
		aim(m.toilet_point())
		await frames(3)
		await press(KEY_V)
		check(m.is_settling(), "V enters for alternate exit")
		await press(code)
		check(not m.is_settling(), "raw alternate exit %s" % OS.get_keycode_string(code))
	await game_at(Vector3(-1.25, 0.9, 0.72))
	aim(m.toilet_point())
	await frames(3)
	await press(KEY_F)
	check(m.is_seated(), "empty bowl F seats")
	await press(KEY_W)
	check(not m.is_seated(), "raw W also leaves ordinary seated state")
	await game_at(Vector3(-1.25, 0.9, 0.72))
	m.toilet.bowl_flesh = 25.0
	aim(m.lever_point())
	await frames(3)
	await press(KEY_F)
	await press(KEY_F)
	check(m.vent.spoken.count(FPVent.FIRST_CHAIN[0]) == 1, "repeated raw flush does not repeat first introduction")
	aim(m.tank_lid.lid.global_position)
	await frames(3)
	await press(KEY_F)
	check(m.tank_lid.held, "raw F picks lid")
	aim(m.player.camera.global_position + Vector3.RIGHT)
	await frames(3)
	await press(KEY_F)
	check(not m.tank_lid.on_tank and not m.tank_lid.held, "raw F puts lid on floor")
	aim(m.restroom.tank_art.to_global(Vector3(0, 0.3, 0)))
	await frames(3)
	await press(KEY_R)
	check(m.progression.teeth_in_hand > 0, "raw right-hand R scoops tank currency")
	await frames(35)
	aim(FPRestroom.VENT_CENTER)
	await frames(3)
	await press(KEY_F)
	check(m.vent.is_open, "raw F opens NPC")
	await press(KEY_R)
	check(m.progression.teeth_in_hand == 0 and not m.vent.offers.is_empty(), "raw R gives held currency instead of putting empty hand in NPC")
	await shot("NPC-paid-with-right-hand")
	await frames(50)
	await press(KEY_R)
	check(m.vent.offers.is_empty(), "raw R accepts one NPC item after payment")
	check(m.save_to_disk() and m.load_from_disk(), "NPC milestones survive actual isolated disk save/load")
	var saved: Dictionary = m.serialize()
	check(saved.vent_progress.met and saved.vent_progress.paid_ever and saved.vent_progress.first_flush_heard, "save includes one-time conversation milestones")
	m.vent.restore_progress(saved.vent_progress, false)
	m.vent.is_open = false
	var first_count: int = m.vent.spoken.count(FPVent.FIRST_CHAIN[0])
	m.vent.on_flush()
	check(m.vent.spoken.count(FPVent.FIRST_CHAIN[0]) == first_count, "restored introduction is not replayed")
	await game_at(Vector3(0, 0.9, 0.8))
	var width: float = 2.0 * FPRestroom.DOOR_HALF_W - 0.01
	aim(m.restroom.door_pivot.to_global(Vector3(width * 0.5, FPRestroom.DOOR_H * 0.5, 0)))
	await frames(3)
	await press(KEY_F)
	await frames(45)
	check(m.restroom.is_door_open(), "raw F opens actual door")
	aim(m.restroom.door_pivot.to_global(Vector3(width * 0.5, FPRestroom.DOOR_H * 0.5, 0)))
	await frames(3)
	check(m.interact_target() == "door", "swung open door remains an aimed interaction")
	await press(KEY_F)
	await frames(45)
	check(not m.restroom.is_door_open(), "raw F closes door again")
	await game_at(Vector3(-1.8, 0.9, -1.0))
	key(KEY_CTRL, true)
	await frames(3)
	aim(m.canary_hole_point())
	await frames(3)
	var feet: float = m.player.get_feet_position().y
	var collider_before: Transform3D = m.player.collision_shape.transform
	var arms_before: Array = [m.hands_rig.get_node("HandRight/Forearm").mesh, m.hands_rig.get_node("HandLeft/Forearm").mesh]
	await press(KEY_F)
	check(m.is_pulling_canary(), "raw F begins canary retrieval")
	var phases := [0.40, 0.56, 0.66, 0.79, 0.82, 0.88]
	for u in phases:
		while m.is_pulling_canary() and m.canary_pull.progress() < u:
			await frames(1)
		check(m.is_pulling_canary(), "retrieval still active at %s" % u)
		check(absf(m.player.get_feet_position().y - feet) < 0.01, "real rotated capsule stays on floor")
		check(m.player.camera.global_position.y > feet + 0.08, "eye stays above floor")
		if u == 0.40:
			check(not m.has_canary and m.canary_pull.prone() > 0.95, "prone search before possession")
			var hand: Node3D = m.hands_rig.get_node("HandRight")
			check(hand.global_position.distance_to(m.canary_hole_point()) < 0.13, "right hand physically reaches opening")
			var left: Node3D = m.hands_rig.get_node("HandLeft")
			check(left.global_position.distance_to(m.canary_hole_point()) > 0.3, "left hand braces instead of swimming")
			check(m.mirror_view.body._sub["hand_r"].global_position.distance_to(m.canary_hole_point()) < 0.17, "connected reflected right arm reaches same hole")
		if u == 0.56:
			check(not m.has_canary and m.canary_pull.bird.visible, "caught single bird is held before tucking")
		if u == 0.88:
			check(m.has_canary and not m.canary_pull.bird.visible, "possession transfers only after tucking")
		await shot("canary-phase-%s" % u)
		if u == 0.40:
			var observer := Camera3D.new()
			m.add_child(observer)
			observer.global_position = Vector3(-0.45, 1.2, -0.2)
			observer.look_at(m.player.global_position + Vector3(0,-0.6,0), Vector3.UP)
			observer.cull_mask = (m.player.camera.cull_mask | FPMirrorReflection.MIRROR_BODY_LAYER) & ~(1 << 11) & ~FPMirrorReflection.HANDS_ROOM_LAYER
			observer.make_current()
			await frames(2)
			await shot("canary-prone-body")
			m.player.camera.make_current()
			observer.queue_free()
	while m.is_pulling_canary(): await frames(1)
	check(m.player.collision_shape.transform.is_equal_approx(collider_before), "retrieval restores actual crouched collider")
	check(m.player.is_physics_processing(), "retrieval restores movement")
	check(m.hands_rig.get_node("HandRight/Forearm").mesh == arms_before[0] and m.hands_rig.get_node("HandLeft/Forearm").mesh == arms_before[1], "retrieval restores exact approved original arm meshes")
	var belt: Node3D = m.art_hookup.belt
	check(belt.get_node_or_null("Canary/BriefBulge") == null and belt.get_node_or_null("Canary/Waistband") == null, "no invented pocket or added elastic block")
	check(belt.get_node("Trousers").mesh == belt._brief_meshes[1], "existing briefs fabric expands for bird")
	key(KEY_CTRL, false)
	await frames(3)
	await press(KEY_TAB)
	await frames(40)
	check(m._mirror_open and m.hand_motions.kind == "watch", "raw Tab still raises approved B after retrieval")
	check(m.hands_rig.get_node("HandRight").position.y < -0.5, "B still sends right arm out of view after retrieval")
	await press(KEY_TAB)
	print("Live interactions: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
