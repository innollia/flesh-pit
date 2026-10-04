extends SceneTree

## Run the ordinary game loop; inject input rather than calling UI/actions.
## Never use the player's save slot.
var m: Node3D
var failures := 0
var checks := 0
# B (00f17f2), with the user-requested whole-arm distance adjustment.
# Retain 5fe85ea's existing right-hand exit.
const REFERENCE_WATCH_BASIS := Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0))
const REFERENCE_WATCH_WRIST := Vector3(0.02, -0.21, -0.34)

func _init() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://watch_door_restore_test.bin"
	root.add_child(m)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)

func wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await process_frame
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func pose(pos: Vector3, yaw: float, pitch: float) -> void:
	m.player.global_position = pos
	m.player.velocity = Vector3.ZERO
	m.player._yaw = yaw
	m.player._pitch = pitch
	m.player.rotation.y = yaw
	m.player.camera_pivot.rotation.x = pitch

func face(point: Vector3, offset := 0.0) -> void:
	var d: Vector3 = point - m.player.camera.global_position
	m.player._yaw = atan2(-d.x, -d.z) + offset
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())
	m.player.rotation.y = m.player._yaw
	m.player.camera_pivot.rotation.x = m.player._pitch

func run() -> void:
	await wait(0.1)
	m.finish_opening()
	for pitch in [deg_to_rad(-89.0), -1.1, 0.0, 1.1, deg_to_rad(89.0)]:
		pose(Vector3(0, 0.95, 0.4), 0.0, pitch)
		await wait(0.05)
		await press("fp_mutate")
		check(m._mirror_open, "Tab opens at pitch " + str(pitch))
		var left: Node3D = m.mirror.hand_root
		for i in range(25):
			await process_frame
			check(not left.get_node("ArmHair/Forearm").visible and left.get_node("Forearm").visible, "watch keeps one forearm throughout raise")
		await wait(0.4)
		check(left.basis.is_equal_approx(REFERENCE_WATCH_BASIS), "original watch rotation")
		check(left.position.distance_to(REFERENCE_WATCH_WRIST) < 0.005, "B whole arm moves farther and lower")
		var thumb_pose: Dictionary = left.get_parent().get_joint_angles("left")
		check(thumb_pose.t2 > 29.9 and thumb_pose.t3 > 29.9 and thumb_pose.t_opp < 8.1, "watch thumb folds without spreading outward")
		var forearm: MeshInstance3D = left.get_node("Forearm")
		var shoulder := forearm.global_transform * Vector3(0.14, -0.1, 0.32)
		check(m.player.camera.unproject_position(shoulder).y > root.size.y, "upper arm heads below view toward shoulder")
		check(is_equal_approx(forearm.material_override.get_shader_parameter("watch_shoulder_drop"), 0.14), "upper arm bends while forearm stays horizontal")
		check(m.mirror.hand_root.get_node("Wrist").rotation.x > deg_to_rad(7.9) and m.mirror.hand_root.get_node("Wrist").rotation.x < deg_to_rad(8.1), "B original wrist pitch")
		var active_right: Node3D = left.get_parent().get_hand_root("right")
		check(active_right.position.distance_to(Vector3(0.2, -0.62, -0.25)) < 0.005, "existing right-hand exit position")
		check(m.mirror.body.scale.is_equal_approx(Vector3.ONE * 0.20), "requested larger doll scale")
		check(m.mirror.body.global_basis.y.normalized().dot(m.player.camera.global_basis.y) > 0.999, "doll follows camera")
		var head: Vector2 = m.player.camera.unproject_position(m.mirror.body.part_center("face"))
		check(root.get_visible_rect().has_point(head), "head stays within view")
		var head_mesh: MeshInstance3D = m.mirror.body.part_node("face").get_node("Head")
		for corner in range(8):
			var world_corner := head_mesh.global_transform * head_mesh.get_aabb().get_endpoint(corner)
			check(root.get_visible_rect().has_point(m.player.camera.unproject_position(world_corner)), "entire head stays within view")
		await press("fdk_eat")
		check(m.hand_motions.kind == "watch" and not m.hand_motions.cancelled, "UI click retains watch pose")
		await press("fp_mutate")
		check(not m._mirror_open, "Tab closes")
		await wait(0.5)
		check(left.basis.is_equal_approx(Basis.IDENTITY), "closing restores arm rotation")
		check(is_zero_approx(left.get_node("Forearm").material_override.get_shader_parameter("watch_shoulder_drop")), "upper arm returns to normal after closing")
		check(left.get_node("Forearm").visible and not left.get_node("ArmHair/Forearm").visible, "release does not replace forearm")
	var hair: MeshInstance3D = m.art_hookup.arm_hair.get_node("Forearm")
	var right: MeshInstance3D = m.hands_rig.get_node("HandRight/Forearm")
	check(right.mesh == hair.mesh and right.position == m.art_hookup.arm_hair.position, "normal arms use matching geometry")
	# Switch to a tumor rig, including a change while Tab is already open.
	m.progression.tumor_mutations.append("T2")
	await wait(0.05)
	await press("fp_mutate")
	await wait(0.4)
	var variant: FDKHandsRig = m.art_hookup.mut_hands.rig()
	check(m.mirror.hand_root == variant.get_hand_root("left"), "Tab follows visible mutation rig")
	check(m.mirror.hand_root.basis.is_equal_approx(REFERENCE_WATCH_BASIS), "mutation rig keeps original watch rotation")
	m.progression.tumor_mutations.clear()
	await wait(0.05)
	check(m.mirror.hand_root == m.hands_rig.get_hand_root("left"), "rig change during Tab retains forearm attachment")
	await press("fp_mutate")
	await wait(0.5)
	m.progression.mutation_tree._purchased["M14"] = true
	await wait(0.05)
	check(m.hands_rig.get_node("HandLeft/Forearm").scale.is_equal_approx(Vector3.ONE * 1.15), "left forearm muscle mutation remains visible")
	check(m.hands_rig.get_node("HandRight/Forearm").scale.is_equal_approx(Vector3.ONE * 1.15), "right forearm muscle mutation retained")
	m.progression.mutation_tree._purchased.erase("M14")
	await wait(0.05)
	var door_point := Vector3(0, 1, FPRestroom.HALF.z)
	pose(Vector3(0, 0.95, FPRestroom.HALF.z - 0.8), 0, 0)
	m.restroom.set_door_open(false, true)
	await wait(0.1)
	face(door_point, deg_to_rad(20))
	await wait(0.05)
	check(m.interact_target() == "door", "original 30 degree door cone")
	await press("fp_interact")
	check(m.restroom.is_door_open(), "F opens closed door")
	await wait(0.9)
	check(m.interact_target() == "door", "open door retains original target")
	await press("fp_interact")
	check(not m.restroom.is_door_open(), "F closes open door")
	await wait(0.9)
	m.restroom.set_door_open(true, true)
	# Reach the passage side through an actually excavated opening. Placing
	# the player in untouched solid flesh makes the flesh occlude the door.
	for x in range(-2, 3):
		for y in range(0, 7):
			for z in range(0, 4):
				m.terrain.dig_at(Vector3(x * 0.5, y * 0.5, FPRestroom.HALF.z + z * 0.5), 1.0)
	m.terrain.remesh_all()
	await physics_frame
	await physics_frame
	pose(Vector3(0, 0.95, FPRestroom.HALF.z + 0.5), 0, 0)
	await wait(0.1)
	check(m.terrain.density_at(m.player.global_position) < m.terrain.config.iso_level, "passage-side fixture has space for the player")
	check(m.terrain.density_at(m.player.camera.global_position) < m.terrain.config.iso_level, "passage-side fixture has space for the camera")
	face(door_point)
	await wait(0.05)
	check(m.interact_target() == "door", "open door can be reached from passage side")
	await press("fp_interact")
	check(not m.restroom.is_door_open(), "F closes door from passage side")
	pose(Vector3(0, 0.95, FPRestroom.HALF.z - 0.8), 0, 0)
	await wait(0.1)
	face(door_point, deg_to_rad(60))
	await wait(0.05)
	await press("fp_interact")
	check(not m.restroom.is_door_open(), "looking away cannot open door")
	pose(Vector3(0, 0.95, FPRestroom.HALF.z - 2.0), 0, 0)
	face(door_point)
	await wait(0.05)
	check(m.interact_target() != "door", "distant door rejected")
	pose(Vector3(0, 0.95, FPRestroom.HALF.z - 0.8), 0, 0)
	await wait(0.1)
	face(door_point)
	var obstruction := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 2.0, 0.1)
	shape.shape = box
	obstruction.add_child(shape)
	m.add_child(obstruction)
	obstruction.global_position = Vector3(0, 1, FPRestroom.HALF.z - 0.4)
	await wait(0.1)
	check(m.interact_target() != "door", "opaque obstruction blocks door")
	await press("fp_interact")
	check(not m.restroom.is_door_open(), "F cannot activate obstructed door")
	obstruction.queue_free()
	check(is_equal_approx(FPRestroom.HALF.x, 2.25), "accepted bathroom width retained")
	check(is_equal_approx(FPRestroom.DOOR_SPILL_ENERGY, 0.85), "accepted door light retained")
	print("WATCH/DOOR: ", checks - failures, " passed, ", failures, " failed")
	m.queue_free()
	await process_frame
	quit(1 if failures else 0)
