extends SceneTree

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(m)
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func aim_slot(slot: int) -> void:
	var yaw: float = m.player.rotation.y
	var pitch := -1.3
	m.player.camera_pivot.rotation.x = pitch
	m.belt_swap.tick(0.0)
	var hip: float = m.belt_swap._hip_yaw
	var span := 1.0
	for round in range(6):
		var best := INF
		var cy := yaw
		var cp := pitch
		for a in range(-6, 7):
			for b in range(-6, 7):
				var y := cy + span * a / 6.0
				var p := clampf(cp + span * b / 6.0, -1.55, -1.0)
				m.player.rotation.y = y
				m.player.camera_pivot.rotation.x = p
				m.player.force_update_transform()
				m.belt_swap._hip_yaw = hip
				m.belt_swap.tick(0.0)
				var ray: Array = m.player.get_look_ray()
				var at: Vector3 = m.art_hookup.belt.call("slot_point", slot)
				var error: float = ray[1].angle_to(at - ray[0])
				if error < best:
					best = error
					yaw = y
					pitch = p
		span *= 0.3
	m.player.rotation.y = yaw
	m.player.camera_pivot.rotation.x = pitch
	m.player.force_update_transform()
	m.belt_swap._hip_yaw = hip
	m.belt_swap.tick(0.0)

func click_hand(hand: int) -> void:
	Input.action_press(FPHandActions.ACTIONS[hand])
	m.hand_actions.tick(0.01)

func release_hand(hand: int) -> void:
	Input.action_release(FPHandActions.ACTIONS[hand])
	m.hand_actions.tick(0.01)

func _run() -> void:
	for i in range(5):
		await process_frame
	m.finish_opening()
	m.set_process(false)
	m.player.set_physics_process(false)
	var p: FPProgression = m.progression
	for id in ["knife", "blender", "big_saw", "spray_cheap", "spray_deep", "canary_feed", "barrier"]:
		p.grant_item(id)
	p.has_belt = true
	for id in ["fp_spray", "fp_blend", "fp_feed_canary", "fp_tool_1", "fp_tool_2", "fp_tool_3", "fp_tool_4"]:
		check(not InputMap.has_action(id), "removed binding " + id)
	check(FPKeybindMenu.binding_of("fdk_eat").contains("LMB") and FPKeybindMenu.binding_of("fp_pick").contains("RMB"), "both hand buttons appear in settings")
	check(FPKeybindMenu.key_of("fp_tool_prev") == "Z" and FPKeybindMenu.key_of("fp_tool_next") == "X", "Z/X previous and next")
	m._register_keybinds()
	var devices: Array = (load("res://main/scripts/fp_input_modes.gd") as GDScript).call("devices_of", "fdk_eat")
	check(devices.has("pad") and devices.has("mouse") and devices.has("keyboard"), "rebuilding key bindings preserves trigger and mouse hand controls")
	check(m.equip_hand("knife", 1) and m.equip_hand("blender", 0), "independent tools in both hands")
	check(p.hands.left == "blender" and p.hands.right == "knife", "equipping second hand preserves first")
	check(not m.equip_hand("blender", 1), "blender stays in left hand")
	var saved := p.serialize()
	var restored := FPProgression.new()
	restored.deserialize(saved)
	check(restored.hands.left == "blender" and restored.hands.right == "knife", "both held tools survive save/load")
	m.art_hookup._process(0.0)
	check(m.art_hookup.knife.visible and m.art_hookup.blender.visible, "both held props visible")
	m.mirror_view._sync_live_details()
	check(m.mirror_view._held["knife"].visible and m.mirror_view._held["blender"].visible, "mirror shows both held tools")
	m.mirror_view._sync_live_details()
	check(m.mirror_view.body._sub["hand_r"].global_position.y < m.mirror_view.body.global_position.y + 1.0, "reflection keeps relaxed standing hands below waist")
	check(m.mirror_view._held["knife"].get_parent() == m.mirror_view.body._sub["hand_r"], "reflected knife attaches to relaxed hand")
	check(not m.can_climb_at(Vector3(0, 0.95, 0)), "Space cannot lift player from restroom floor")
	m.terrain.dig_at(Vector3(0, 1, 6), 1.0)
	check(m.terrain.density_at(Vector3(0, 1, 6)) < 0.5 and m.can_climb_at(Vector3(0, 1, 6)), "climbing works in excavated tunnel with adjacent flesh")
	check(not m.can_climb_at(Vector3(0, 1, m.OUTER_RADIUS + 5)), "no Space movement in unsupported open air")
	m.equip_tool("")
	m.player.global_position = Vector3(0, 0.95, 0)
	m.player.rotation.y = 0
	m.player.camera_pivot.rotation.x = -1.25
	m.belt_swap.tick(0.0)
	aim_slot(0)
	check(m.belt_swap.aimed_hook() == 0, "look ray identifies knife home")
	m._interact()
	check(not m.belt_swap.busy(), "F does not exchange belt items")
	click_hand(0)
	check(m.belt_swap.busy(), "LMB starts left-hand belt exchange")
	m.belt_swap.tick(FPBeltSwap.SWAP_TIME)
	check(p.hands.left == "knife" and p.hands.right == "", "belt knife goes into selected left hand")
	check(m.hand_actions.blocked[0], "exchange press cannot immediately use new item")
	release_hand(0)
	check(not m.hand_actions.blocked[0], "release permits next use")
	m.equip_tool("")
	aim_slot(1)
	click_hand(1)
	m.belt_swap.tick(FPBeltSwap.SWAP_TIME)
	check(p.hands.right == "" and not p.hands.holds("blender"), "right-hand belt click cannot take blender")
	release_hand(1)
	for slot in range(3, 7):
		m.equip_tool("")
		m.art_hookup._process(0.0)
		aim_slot(slot)
		check(m.belt_swap.aimed_hook() == slot, "consumable has reachable fixed home %d" % slot)
		click_hand(1)
		m.belt_swap.tick(FPBeltSwap.SWAP_TIME)
		check(p.hands.right == FPBeltSwap.SLOTS[slot], "RMB takes consumable %d" % slot)
		release_hand(1)
	m.equip_tool("canary_feed")
	m.player.camera_pivot.rotation.x = 0
	m.has_canary = true
	var feed := p.canary_feed
	click_hand(1)
	check(p.canary_feed == feed - 1, "held feed uses right-hand button")
	check(not p.hands.holds("canary_feed"), "consumed final item clears hand")
	release_hand(1)
	m.equip_hand("blender", 0)
	m.blender_charge = 1.0
	m.carried_flesh = 10.0
	click_hand(0)
	check(m.tissue_tools.blend_state == FPTissueTools.Blend.SPIN, "held blender starts with left-hand button")
	release_hand(0)
	var art: Node3D = m.restroom.mirror_art
	check(m.restroom.get_node_or_null("WallDrawer") == null and art.get_node_or_null("StorageCabinet") != null, "storage cabinet is above sink")
	art.call("toggle_cabinet")
	art.call("_process", 1.0)
	check(art.cabinet_open and absf(art.door_pivot.rotation.y) > 1.0, "mirrored storage door opens")
	check(m.mirror_view.art == art.door_surface, "reflection follows moving door surface")
	check(m.restroom.get_node("RoomLight").shadow_enabled, "room lighting retains fixture shadows")
	m.player.rotation.y = 0.3
	m.player.camera_pivot.rotation.x = -1.2
	m.hand_motions.play_vomit(false, 0.5)
	m.hand_motions.t = 0.9
	m.hand_motions._apply_cams(0.375)
	var bowed: Transform3D = m.player.camera.global_transform
	m.hand_motions._finish()
	m.player.camera_pivot.rotation.x = 1.2
	m.hand_motions.play_vomit(false, 0.5)
	m.hand_motions.t = 0.9
	m.hand_motions._apply_cams(0.375)
	check(m.player.camera.global_transform.is_equal_approx(bowed), "vomit world camera is identical after looking up or down")
	m.player.rotation.y += 0.4
	m.player.camera_pivot.rotation.x = -0.7
	m.hand_motions._apply_cams(0.375)
	check(m.player.camera.global_transform.is_equal_approx(bowed), "vomit camera keeps captured direction during head movement")
	m.hand_motions._spill(false, 1)
	var spill: Node3D = m.get_node("Spill")
	var local: Vector3 = m.player.camera.global_transform.affine_inverse() * spill.global_position
	check(local.y < -0.08, "vomit flesh starts below camera rather than above")
	m.hand_motions._finish()
	m.save_path = "user://hand_controls_test.bin"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.save_path))
	m.hand_motions.kind = ""
	m.tick_autosave(29.0)
	check(not m.has_save_file(), "periodic autosave waits for interval")
	m.tick_autosave(1.0)
	check(m.has_save_file(), "periodic autosave writes single slot")
	check(m.save_to_disk(), "atomic save can replace existing Windows slot")
	check(not FileAccess.file_exists(m.save_path + ".tmp"), "completed save leaves no temporary slot")
	m.ended = true
	m.progression.teeth = 23
	m.save_to_disk()
	m.show_title()
	check(m.continue_game() and not m.ended and m.player.global_position.is_equal_approx(m.START_POS) and m.progression.teeth == 23, "completed save continues in restroom with progress rather than freezing")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.save_path))
	print("--- hand controls: %d passed, %d failed ---" % [passed, failed])
	m.queue_free()
	quit(1 if failed else 0)
