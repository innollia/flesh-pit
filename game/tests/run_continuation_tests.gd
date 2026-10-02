extends SceneTree

## Regression checks for the unfinished 2026-09-30 handoff.
var m: Node3D
var passed := 0
var failed := 0
var frame := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(m)

func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", message)

func _process(_delta: float) -> bool:
	frame += 1
	if frame != 5:
		return false
	_run()
	return false

func _run() -> void:
	m.set_process(false)
	m.player.set_physics_process(false)
	m._begin_opening()
	m._process_opening(30.0)
	check(m.is_opening() and m.player.global_position.is_equal_approx(m.SEAT_POS), "opening waits seated even after 30 seconds")
	check(m.opening_view.waiting_to_rise, "forward input icon blinks at the seat")
	Input.action_press("fdk_move_forward")
	m._process_opening(0.1)
	Input.action_release("fdk_move_forward")
	check(m._opening_rising, "forward input starts standing")
	m._process_opening(2.0)
	check(not m.is_opening() and m.opening_done, "stand animation finishes")
	check(m.opening_view.hints.remaining.size() == 6, "movement and mouse icons remain after standing")
	var ev := InputEventAction.new()
	ev.action = "fdk_move_left"
	ev.pressed = true
	m.opening_view.hints._input(ev)
	check(not m.opening_view.hints.remaining.has("fdk_move_left") and m.opening_view.hints.remaining.has("fdk_move_right"), "only the used icon disappears")
	check(m.hands_rig.get_node("HandLeft/Forearm").visible and m.hands_rig.get_node("HandRight/Forearm").visible, "both native forearms remain visible")
	check(not m.art_hookup.arm_hair.get_node("Forearm").visible, "hair scene cannot replace only one forearm")
	check(not m.has_canary and not m.art_hookup.belt.get_node("Canary").visible, "fresh run has no canary")
	var belt: Node3D = m.art_hookup.belt
	belt.set_spray_count(1, 0)
	var can := belt.get_node("Can0/Spray").get_child(0)
	for i in range(20):
		belt.set_spray_count(1, 0)
	check(belt.get_node("Can0/Spray").get_child_count() == 1 and belt.get_node("Can0/Spray").get_child(0) == can, "unchanged spray count reuses geometry for every frame")
	m.art_hookup.belt.set_canary(true)
	check(not m.art_hookup.belt.get_node("Canary/Body").visible and m.art_hookup.belt.get_node("Canary/Waistband").visible, "bird body is covered by bulging briefs")
	m.art_hookup.belt.set_canary(false)
	check(m.mirror_view.body._sub["eyes"].position.y < 0.03, "eyes sit below forehead")
	var lid: FPTankLid = m.tank_lid
	check(lid.pick(), "loose lid can be picked up")
	check(lid.held and lid.lid.is_ancestor_of(lid.lid.get_child(0)) and m.hands_rig.is_ancestor_of(lid.lid), "actual lid geometry belongs to the hand")
	check(m.restroom._lid_target != 0.0 and not lid.on_tank, "tank is accessible after taking lid")
	m.progression.grant_item("knife")
	check(not m.equip_tool("knife"), "cannot equip over a carried ceramic lid")
	var held_data := lid.serialize()
	lid.replace_on_tank()
	lid.deserialize(held_data)
	check(lid.held, "held lid survives save/load")
	m.mirror_view._sync_live_details()
	check(m.mirror_view._held["lid"].visible, "mirror reflects the carried tank lid")
	m.player.global_position = Vector3(0, 0.95, 0)
	m.player.rotation.y = 0
	m.player.camera_pivot.rotation.x = -0.8
	m.player.force_update_transform()
	check(lid.drop(), "interaction drops lid to a real floor")
	check(not lid.held and not lid.on_tank and lid.lid.global_position.y > 0, "dropped lid remains visible on floor")
	var dropped := lid.serialize()
	lid.replace_on_tank()
	lid.deserialize(dropped)
	check(not lid.held and not lid.on_tank, "dropped lid position survives save/load")
	lid.replace_on_tank()
	check(lid.on_tank and lid.lid.rotation.is_zero_approx(), "lid rests flat without a hinge")
	m.mirror_view.sync(false, false)
	check(m.mirror_view._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "mirror stops rendering outside room")
	m.hand_blood = 0.7
	m.equip_tool("knife")
	m.mirror_view._sync_live_details()
	check(is_equal_approx(float(m.mirror_view._blood.get_shader_parameter("amount")), 0.7), "mirror blood follows gameplay")
	check(m.mirror_view._held["knife"].visible, "mirror shows held knife")
	m.wash_hands()
	m.equip_tool("")
	m.mirror_view._sync_live_details()
	check(float(m.mirror_view._blood.get_shader_parameter("amount")) == 0.0 and not m.mirror_view._held["knife"].visible, "mirror follows washing and unequipping")
	m.hands_rig.state = FDKHandsRig.HandState.TEAR
	m.carried_flesh = 20.0
	m.mirror_view._sync_live_details()
	check(m.mirror_view._mouth_flesh.visible and m.mirror_view._carry_flesh.visible, "mirror shows eating and carried flesh")
	m.show_title()
	var wall: FPTitleWall = m.title_screen.wall
	wall._process(0.0)
	var original := Vector2(170, 370)
	var p := Vector2(original.x / wall.menu_root.size.x - 0.5, 0.5 - original.y / wall.menu_root.size.y) * wall.extent
	var q := p + wall.displacement(p)
	var projected := Vector2(q.x / wall.extent.x + 0.5, 0.5 - q.y / wall.extent.y) * wall.menu_root.size
	check(wall.screen_to_menu(projected).distance_to(original) < 0.01, "mouse coordinates follow the deforming title surface")
	m.title_screen.has_save = true
	m.title_screen.request_new_game()
	check(m.title_screen.settings_button.is_visible_in_tree() and m.title_screen.continue_button.is_visible_in_tree(), "confirmation replaces only new-game row")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	wall._input(cancel)
	check(not m.title_screen.is_confirming(), "Esc restores new-game row on curved menu")
	await process_frame
	await process_frame
	var button: Button = m.title_screen.settings_button
	original = button.global_position + button.size * 0.5
	p = Vector2(original.x / wall.menu_root.size.x - 0.5, 0.5 - original.y / wall.menu_root.size.y) * wall.extent
	q = p + wall.displacement(p)
	projected = Vector2(q.x / wall.extent.x + 0.5, 0.5 - q.y / wall.extent.y) * wall.menu_root.size
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = wall.get_global_transform_with_canvas() * projected
	click.pressed = true
	wall._input(click)
	click.pressed = false
	wall._input(click)
	check(m.settings_menu.is_open(), "mouse click reaches the curved title button")
	paused = false
	print("--- continuation: %d passed, %d failed ---" % [passed, failed])
	m.queue_free()
	quit(1 if failed else 0)
