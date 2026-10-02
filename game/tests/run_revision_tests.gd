extends SceneTree

var m: Node3D
var passed := 0
var failed := 0
var torn: Array[Vector3] = []

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

func _run() -> void:
	for frame in range(6):
		await physics_frame
	m.finish_opening()
	m.set_process(false)
	m.player.set_physics_process(false)
	check(m.nerves.is_empty(), "no nerve stalks before excavation")
	check(m._world_tissue(Vector3(0, 1, FPRestroom.HALF.z + 0.1)) == FDKTissueRules.COMPRESSIVE, "door starts with flesh, no exposed nerve tissue")
	check(m.title_screen.wall.terrain is FDKTerrainField, "title uses actual game terrain field")
	check(m.title_screen.wall.surface.mesh is ArrayMesh, "title uses meshed low-poly tissue, not a plane")
	check(m.title_screen.confirm_yes.text == "BONG", "inline new-game confirmation says BONG")
	check(m.vent.art.get_node("BlackOpening").visible, "closed vent has black backing without added flesh")
	check(m.settings_menu.root.find_children("*", "PanelContainer", true, false).is_empty(), "settings has no floating panel")
	var wall_mat: ShaderMaterial = m.restroom.get_node("Tiles").mesh.surface_get_material(0)
	check(wall_mat.get_shader_parameter("tile_dimensions").is_equal_approx(Vector2(0.3, 0.3)), "wall tiles are square")
	check(is_equal_approx(m.restroom.toilet.rotation.y, PI * 0.5), "toilet tank rests on left wall")
	check(m.restroom.get_node("Bathtub").mesh.get_aabb().size.x > FPRestroom.HALF.x * 1.9, "bathtub spans the back wall")
	check(m.restroom.get_node("Shower").scale.x > 0, "shower remains in back-left corner")
	check(m.restroom.mirror_art.door_surface_right != null, "cabinet has two mirrored doors")
	check(m.mirror_view_right.body == m.mirror_view.body, "mirror doors share one relaxed player body")
	check(m.mirror_view._vp.size.x * 3 == m.mirror_view._vp.size.y * 2, "reflection viewport matches each door's aspect ratio")
	check(m.mirror_view.body.part_node("face").find_children("Eyes", "MeshInstance3D", true, false).is_empty(), "face features use image texture without eye geometry")
	check(m.mirror_view.body.part_node("face").get_node("Head").material_override.get_shader_parameter("face_tex") != null, "generated face texture is applied")
	m.player.global_position = Vector3(-0.28, 0.95, FPRestroom.SINK_Z)
	m.player.rotation.y = PI * 0.5
	m.player.camera_pivot.rotation.x = 0.0
	m.player.force_update_transform()
	m.progression.grant_item("knife")
	m.equip_hand("knife", FDKToolKit.Hand.RIGHT)
	m.hand_blood = 0.7
	m.mirror_view.sync(true, false)
	m.mirror_view_right.sync(true, false)
	check(m.mirror_view._held.has("knife") and m.mirror_view._held["knife"].visible, "held tool updates when only the second mirror door is in view")
	check(not m.mirror_view._mouth_flesh.visible, "idle standing reflection has no floating mouth flesh")
	m.equip_tool("")
	m.show_title()
	check(m.mirror_view._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED and m.mirror_view_right._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "title disables both room reflection viewports")
	m._leave_title()
	m.set_process(false)
	m.player.set_physics_process(false)
	m.player.global_position = Vector3(0, 0.95, FPRestroom.HALF.z - 0.65)
	m.player.rotation.y = PI
	m.player.set("_yaw", PI)
	m.player.camera_pivot.rotation.x = 0
	m.player.set("_pitch", 0.0)
	m.restroom.set_door_open(true, true)
	for frame in range(4):
		await physics_frame
	var first_hit: Dictionary = m._look_hit()
	check(not first_hit.is_empty() and first_hit.collider.has_meta("fdk_terrain_chunk"), "aim ray hits the door flesh")
	var start_distance: float = m.player.camera.global_position.distance_to(first_hit.position)
	m.chewer.cell_torn.connect(func(p): torn.append(p))
	var fill_before: float = m.stomach.fill
	# Drive the same held-hand route as gameplay while physics and meshing update.
	Input.action_press("fdk_eat")
	for frame in range(240):
		m.hand_actions.tick(1.0 / 60.0)
		await physics_frame
	Input.action_release("fdk_eat")
	m.hand_actions.tick(0)
	check(torn.size() >= 2, "holding use repeatedly excavates actual cells")
	check(m.stomach.fill > fill_before, "excavation fills the stomach")
	var unique := {}
	for p in torn:
		unique[p] = true
	check(unique.size() == torn.size(), "empty cells cannot be eaten repeatedly")
	check(is_equal_approx(m.stomach.fill - fill_before, torn.size() * m.stomach_config.flesh_per_cell), "food is awarded exactly once per removed cell")
	var after_hit: Dictionary = m._look_hit()
	check(after_hit.is_empty() or m.player.camera.global_position.distance_to(after_hit.position) > start_distance + 0.35, "visible/collision surface recedes into a real hole")
	check(m.nerves.is_empty(), "small initial excavation reveals no premature nerves")
	m.stomach_hud._process(0)
	check(m.stomach_hud.visible, "stomach HUD is visible in gameplay")
	var cleared: Vector3 = torn[0]
	var before: float = m.stomach.fill
	m.chewer.try_start(cleared)
	m.chewer.process_chew(3)
	check(is_equal_approx(before, m.stomach.fill), "chewing an empty cell yields no food")
	# An older wide-room save keeps its progress and exterior tunnel after fitting.
	m.progression.teeth = 17
	m.terrain.dig_at(Vector3(0, 1, 6), 1.0)
	var saved: Dictionary = m.serialize()
	saved["version"] = 3
	saved["player_position"] = [-1.6, 0.95, 0.0]
	m.deserialize(saved)
	check(m.progression.teeth == 17, "legacy room migration preserves earned progress")
	check(m.player.global_position.is_equal_approx(Vector3(-1.6, 0.95, 0)), "legacy save keeps a valid position in the restored room")
	check(m.terrain.density_at(Vector3(0, 1, 6)) < 0.5, "legacy migration preserves excavated exterior tunnels")
	check(m.terrain.density_at(Vector3(1.75, 1, 0)) < 0.5, "legacy migration preserves the restored wide bathroom interior")
	print("--- revision: %d passed, %d failed ---" % [passed, failed])
	m.queue_free()
	quit(1 if failed else 0)
