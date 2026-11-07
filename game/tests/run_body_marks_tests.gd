extends SceneTree

## Whole-body hair (grown with the arm hair), whole-body blood and the body
## shadow (a full shadow-only body wearing the belt). Ordinary Main frames;
## the mirror is refreshed by looking at it, not by calling refresh().

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_body_marks.json"
	m.save_path = "user://body_marks_test.bin"
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
		await physics_frame
	await process_frame

func aim(point: Vector3) -> void:
	var d: Vector3 = (point - m.player.camera.global_position).normalized()
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = asin(d.y)
	m.player.rotation.y = m.player._yaw
	m.player.camera_pivot.rotation.x = m.player._pitch

func set_hair(total: int) -> void:
	var tree = m.progression.mutation_tree
	var want := {"common": total / 2, "core": total / 6, "mantle": total / 6, "surface": total - total / 2 - 2 * (total / 6)}
	for pool in want:
		tree.add_points(pool, int(want[pool]) - tree.points(pool))

func run() -> void:
	await frames(6)
	m.finish_opening()
	m.player.mouse_look_enabled = false
	var surface: Node3D = m.restroom.mirror_art.call("reflection_surface")
	var glass: Vector3 = surface.to_global(Vector3(0, 1.78, 0.016))
	var n: Vector3 = surface.global_transform.basis.z.normalized()
	var stand := glass + n * 1.15
	stand.y = 0.95
	m.player.global_position = stand
	await frames(3)
	aim(glass + Vector3(0, -0.32, 0))
	await frames(4)
	var body: FPMirrorBody = m.mirror_view.body

	# --- 1. body hair grows with the arm hair ---------------------------------
	set_hair(0)
	await frames(4)
	check(body.hair_points == 0 and body.body_hair_strands() == 0, "no arm hair: no body hair strands")
	var counts := []
	for total in [12, 40, 90]:
		set_hair(total)
		await frames(4)
		var arm: int = m.art_hookup.arm_hair.call("hair_total")
		check(arm == total, "arm hair shows %d" % total)
		check(body.hair_points == arm, "mirror body hair follows the arm hair (%d)" % total)
		check(is_equal_approx(float(body._marks.get_shader_parameter("hair")), FPBodyMarks.hair_density(arm)), "painted body hair density follows the arm hair")
		var right: Node3D = m.art_hookup.arm_hair_right
		check(right != null and int(right.call("hair_total")) == arm, "right forearm grows the same arm hair")
		check(is_equal_approx(float(m.art_hookup.belt._marks.get_shader_parameter("hair")), FPBodyMarks.hair_density(arm)), "first-person belly hair density follows the arm hair")
		var legs: Node3D = m.art_hookup.legs
		check(is_equal_approx(float(legs._marks.get_shader_parameter("hair")), FPBodyMarks.hair_density(arm)), "first-person legs hair density follows the arm hair")
		counts.append(body.body_hair_strands())
	check(counts[0] > 0 and counts[1] > counts[0] and counts[2] > counts[1], "more arm hair, more body hair strands %s" % str(counts))
	var hair_parts := {}
	for mi in body.find_children("BodyHair", "MeshInstance3D", true, false):
		hair_parts[String(mi.get_parent().name)] = true
	for part in ["Forearm", "UpperArm", "Thigh", "Shin", "Chest", "Belly"]:
		check(hair_parts.has(part), "body hair strands on " + part)
	var belly_hair: MeshInstance3D = m.art_hookup.belt.get_node_or_null("Torso/BodyHair")
	var leg_hair: Array = m.art_hookup.legs.find_children("BodyHair", "MeshInstance3D", true, false)
	check(leg_hair.size() == 4, "first-person thighs and shins carry hair strands")
	check(belly_hair != null and belly_hair.visible and belly_hair.mesh.get_surface_count() > 0, "first-person belly carries hair strands")
	set_hair(300)
	await frames(4)
	check(body.hair_points == FPBodyHair.BODY_FULL and body.body_hair_strands() >= counts[2], "past BODY_FULL arm hairs the body stays at its fullest")
	# spending hair thins the body again
	set_hair(12)
	await frames(4)
	check(body.hair_points == 12 and body.body_hair_strands() == counts[0], "spent arm hair thins the body hair")
	# the Tab doll is the same body
	m.open_mirror()
	await frames(10)
	check(m.mirror.body.hair_points == 12, "Tab doll grows the same body hair")
	m.mirror.close()
	await frames(4)

	# --- 2. blood over the whole body --------------------------------------------
	var painted := 0
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		if FPMirrorBody.MARKS.has(String(mi.name)) and not body._belt.is_ancestor_of(mi) and mi.material_overlay != null:
			painted += 1
	check(painted >= 17, "every skin part of the mirror body carries the blood/hair overlay (%d)" % painted)
	var palm: MeshInstance3D = body.sub_node("hand_r").get_node("Palm")
	check(palm.material_overlay != body._marks and palm.material_overlay != null, "mirror hands keep the hand blood overlay")
	var rig_palm: Array = m.hands_rig.get_node("HandRight").find_children("Palm", "MeshInstance3D", true, false)
	check(not rig_palm.is_empty() and rig_palm[0].material_overlay == m.hand_blood_mat, "first-person hands keep FPHandBlood")
	m.hand_blood = 0.6
	await frames(3)
	check(is_equal_approx(body.blood_amount(), 0.6), "mirror body blood follows the hand blood")
	check(is_equal_approx(float(m.art_hookup.belt._marks.get_shader_parameter("blood")), 0.6), "first-person belly/briefs blood follows the hand blood")
	check(is_equal_approx(float(m.art_hookup.legs._marks.get_shader_parameter("blood")), 0.6), "first-person legs blood follows the hand blood")
	var torso: MeshInstance3D = m.art_hookup.belt.get_node("Torso")
	check(torso.material_overlay == m.art_hookup.belt._marks, "first-person belly carries the body overlay")
	m.hand_blood = 0.0
	await frames(3)
	check(body.blood_amount() == 0.0, "washed hands clear the body blood")

	# --- 3. the shadow is a whole body wearing the belt ---------------------------
	var sb: FPShadowBody = m.shadow_body
	check(sb != null and sb.body != null and sb.body.get_parent() == m.player, "shadow body stands under the player")
	var casters: Array = sb.casters()
	var all_only := true
	for c in casters:
		if (c as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			all_only = false
	check(casters.size() > 20 and all_only, "every shadow-body mesh is shadow-only (never drawn)")
	var room_light: Light3D = m.restroom.get_node("RoomLight")
	check(room_light.shadow_enabled and (room_light.light_cull_mask & FPShadowBody.LAYERS) != 0, "restroom ceiling light shadows the body")
	# every other shadowed lamp in the scene shadows it too
	for l in m.find_children("*", "Light3D", true, false):
		if (l as Light3D).shadow_enabled and l.is_visible_in_tree():
			check(((l as Light3D).light_cull_mask & FPShadowBody.LAYERS) != 0, "shadowed lamp %s reaches the shadow body" % l.name)
	check(sb.body._belt != null and sb.body._belt.visible, "shadow body wears its belt")
	var feet: Vector3 = m.player.call("get_feet_position")
	check(absf(sb.body.global_position.y - feet.y) < 0.02, "shadow body stands on the real feet")
	var belt_y: float = sb.body._belt.global_position.y - feet.y
	check(belt_y > 0.85 and belt_y < 1.1, "shadow belt sits at the body's waist (%.2f m)" % belt_y)
	var fp_belt: Node3D = m.art_hookup.belt
	m.progression.has_bag = true
	m.progression.has_belt = true
	m.progression.grant_item("knife")
	if m.progression.hands.holds("knife"):
		m.progression.hands.clear() if m.progression.hands.has_method("clear") else null
	await frames(3)
	var fp_cast := 0
	for g in fp_belt.find_children("*", "GeometryInstance3D", true, false):
		if (g as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			fp_cast += 1
	check(fp_cast == 0, "first-person belt adds no floating ring shadow (%d casters)" % fp_cast)
	var tool: Node3D = fp_belt.get_node_or_null("Hook0/Tool")
	var tool_ok := tool != null
	if tool != null:
		for g in tool.find_children("*", "GeometryInstance3D", true, false):
			tool_ok = tool_ok and (g as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	check(tool_ok, "a tool hung later on the first-person belt casts no extra shadow")
	var shadow_tool: Node3D = sb.body._belt.get_node_or_null("Hook0/Tool")
	var shadow_tool_ok := shadow_tool != null
	if shadow_tool != null:
		for g in shadow_tool.find_children("*", "GeometryInstance3D", true, false):
			shadow_tool_ok = shadow_tool_ok and (g as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	check(shadow_tool_ok, "the hung knife hangs on the shadow belt as a shadow-only caster")
	var bag: Node3D = sb.body._belt.get_node_or_null("TumorBag")
	check(bag != null and bag.visible, "shadow belt carries the tumor bag when owned")
	var stand_pelvis: float = sb.body.part_node("legs").position.y
	m.player.set("_is_crouching", true)
	await frames(3)
	check(sb.body.part_node("legs").position.y < stand_pelvis - 0.1, "shadow body crouches with the player")
	m.player.set("_is_crouching", false)
	await frames(2)
	# no camera draws it: the eye and the mirror see only its shadow
	check(sb.body.visible, "shadow body is active in the room")

	print("BODY MARKS: %d passed, %d failed" % [passed, failed])
	m.queue_free()
	await process_frame
	quit(1 if failed > 0 else 0)
