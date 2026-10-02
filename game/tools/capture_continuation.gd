extends SceneTree

var m: Node3D
const OUT := "res://captures/continuation"

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(m)
	_run.call_deferred()

func shot(id: String) -> void:
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(OUT + "/" + id + ".png")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for i in range(5):
		await process_frame
	m.finish_opening()
	m.show_title()
	m.title_screen.has_save = true
	m.title_screen._refresh()
	await shot("title")
	for frame in range(75):
		await process_frame
	await shot("title_motion")
	m.title_screen.request_new_game()
	await shot("confirm")
	m.open_settings()
	await shot("settings")
	m.settings_menu.close()
	m.title_screen._show_confirm(false)
	m._leave_title()
	m._begin_opening()
	m._process_opening(30.0)
	await shot("seated_w")
	m.finish_opening()
	m.apply_atmosphere_now()
	m.set_process(false)
	m.player.set_physics_process(false)
	m.player.global_position = Vector3(-0.28, 0.95, FPRestroom.SINK_Z)
	m.player.rotation.y = PI * 0.5
	m.player.set("_yaw", PI * 0.5)
	m.player.set("_pitch", -0.1)
	m.player.camera_pivot.rotation.x = -0.1
	m.player.force_update_transform()
	m.hand_blood = 0.8
	FPHandBlood.set_amount(m.hand_blood_mat, 0.8)
	m.progression.grant_item("knife")
	m.equip_tool("knife")
	m.has_canary = true
	m.mirror_view.sync(true, true)
	m.mirror_view_right.sync(true, true)
	await shot("mirror_held")
	m.progression.grant_item("blender")
	m.equip_hand("blender", FDKToolKit.Hand.LEFT)
	m.mirror_view.sync(true, true)
	m.mirror_view_right.sync(true, true)
	await shot("mirror_both_hands")
	m.restroom.mirror_art.call("toggle_cabinet")
	for i in range(90):
		await process_frame
		m.mirror_view.sync(true, true)
		m.mirror_view_right.sync(true, true)
	await shot("mirror_cabinet_open")
	m.restroom.mirror_art.call("toggle_cabinet")
	for frame in range(90):
		await process_frame
	m.equip_tool("")
	m.tank_lid.pick()
	m.player.global_position = Vector3(0, 0.95, 0)
	m.player.rotation.y = 0
	m.player.camera_pivot.rotation.x = -0.7
	await shot("held_lid")
	m.tank_lid.drop()
	await shot("dropped_lid")
	m.tank_lid.replace_on_tank()
	m.opening_view.hints.visible = false
	m.player.global_position = Vector3(0.72, 0.95, 1.18)
	m.player.camera_pivot.rotation.x = 0
	m.player.camera.look_at(Vector3(-0.4, 1.18, -0.5), Vector3.UP)
	m.mirror_view.sync(true, false)
	await shot("bathroom")
	m.hands_rig.visible = false
	m.mirror_view.sync(true, false)
	m.mirror_view_right.sync(true, false)
	await shot("bathroom_clean")
	m.player.camera.look_at(FPRestroom.VENT_CENTER, Vector3.BACK)
	await shot("vent_closed")
	m.use_vent()
	for frame in range(55):
		await process_frame
	await shot("vent_open")
	m.hands_rig.visible = true
	m.player.camera.rotation = Vector3.ZERO
	m.player.rotation.y = PI
	m.player.set("_yaw", PI)
	m.player.camera_pivot.rotation.x = 0.0
	m.player.global_position = Vector3(0, 0.95, FPRestroom.HALF.z - 0.65)
	m.restroom.set_door_open(true, true)
	m.apply_atmosphere_now()
	m.vent.art.call("set_open", 0.0)
	await shot("door_flesh_before")
	Input.action_press("fdk_eat")
	for frame in range(240):
		m.hand_actions.tick(1.0 / 60.0)
		m.step_world(1.0 / 60.0)
		await physics_frame
	Input.action_release("fdk_eat")
	m.hand_actions.tick(0)
	m.terrain.set_press(Vector3.ZERO, Vector3.BACK, 0.0)
	m.stomach_hud.queue_redraw()
	await shot("door_flesh_dug")
	m.player.global_position = Vector3(0, 0.95, 0)
	m.hand_blood = 0
	FPHandBlood.set_amount(m.hand_blood_mat, 0)
	m.open_mirror()
	for pose in [["tab_down", -1.2], ["tab_level", 0.0], ["tab_up", 1.2]]:
		m.player.camera_pivot.rotation.x = pose[1]
		m.mirror._place()
		await shot(pose[0])
	m.mirror.close()
	m.open_keybind_menu()
	await shot("keybinds")
	quit()
