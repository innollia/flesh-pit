extends SceneTree

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://spray_attachment_test.bin"
	root.add_child(m)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func run() -> void:
	await create_timer(0.1).timeout
	m.finish_opening()
	m.player.global_position = Vector3(0, 0.95, 0.4)
	m.player._yaw = 0.0
	m.player.rotation.y = 0.0
	m.player._pitch = -1.2
	m.player.camera_pivot.rotation.x = -1.2
	var belt: Node3D = m.art_hookup.belt
	check(belt.get_parent() == m.player, "belt attached to player")
	for counts in [Vector2i(2, 1), Vector2i(0, 0), Vector2i(1, 2), Vector2i(2, 1)]:
		belt.set_spray_count(counts.x, counts.y)
		for i in range(3):
			var clip: MeshInstance3D = belt.get_node("Can%d/Clip" % i)
			check(clip.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "first-person clip casts no detached shadow")
			var can := belt.get_node_or_null("Can%d/Spray/CanMesh" % i) as MeshInstance3D
			if can != null:
				check(can.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "rebuilt spray casts no detached shadow")
	for action in ["fdk_move_forward", "fdk_move_back", "fdk_move_left", "fdk_move_right"]:
		var start: Vector3 = m.player.global_position
		var offset: Vector3 = belt.get_node("Can0").global_position - start
		check(InputMap.has_action(action), "movement action exists")
		Input.action_press(action)
		await create_timer(0.15).timeout
		Input.action_release(action)
		check(m.player.global_position.distance_to(start) > 0.01, "WASD actually moves player")
		check((belt.get_node("Can0").global_position - m.player.global_position).distance_to(offset) < 0.001, "holster moves at player's speed")
	var reflection_belt: Node3D = m.mirror_view.body._belt
	check(reflection_belt.spray_cast_shadows, "mirror belt keeps existing default policy")
	for i in range(3):
		var clip: MeshInstance3D = reflection_belt.get_node("Can%d/Clip" % i)
		check(clip.layers == FPMirrorReflection.MIRROR_BODY_LAYER and clip.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "existing mirror-only render policy retained")
	print("SPRAY ATTACHMENT: %d passed, %d failed" % [passed, failed])
	m.queue_free()
	await process_frame
	quit(1 if failed > 0 else 0)
