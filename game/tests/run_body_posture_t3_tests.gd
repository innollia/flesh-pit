extends SceneTree

## R06/R07/R08 geometry checks plus normal Main physics/process input checks.
## Historical leg profiles below are the approved standing model, before the
## knee/ankle split. Compare actual mesh vertices, not just pivot positions.
const K := preload("res://main/art/fp_art_kit.gd")
const LEG_PROFILE := [
	[-0.12, 0.087, 0.0, 0.084, 0.086, 0.09], [-0.2, 0.092, 0.012, 0.078, 0.082, 0.076],
	[-0.32, 0.089, 0.02, 0.062, 0.066, 0.058], [-0.42, 0.086, 0.025, 0.048, 0.05, 0.044],
	[-0.47, 0.085, 0.03, 0.042, 0.046, 0.038], [-0.53, 0.084, 0.005, 0.046, 0.04, 0.056],
	[-0.62, 0.083, -0.01, 0.05, 0.04, 0.066], [-0.72, 0.081, -0.004, 0.036, 0.034, 0.044],
	[-0.82, 0.079, 0.0, 0.026, 0.026, 0.028], [-0.88, 0.078, 0.0, 0.028, 0.027, 0.03]
]
var passed := 0
var failed := 0
var m: Node3D
var body: FPMirrorBody

func _init() -> void:
	print("=== T3 actual body posture ===")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
	await process_frame

func meshes(n: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if n is MeshInstance3D and n.material_override is ShaderMaterial and n.material_override.shader.code == FPMirrorBody.SHIMMER_SHADER:
		return result
	if n is MeshInstance3D and not String(n.name).begins_with("Mut_"):
		result.append(n)
	for child in n.get_children():
		result.append_array(meshes(child))
	return result

func vertices(n: Node3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	for mesh in meshes(n):
		for v in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			result.append(body.to_local(mesh.to_global(v)))
	return result

func vertex_keys(vs: PackedVector3Array) -> Dictionary:
	var result := {}
	for v in vs:
		result["%d/%d/%d" % [roundi(v.x * 100000), roundi(v.y * 100000), roundi(v.z * 100000)]] = true
	return result

func old_leg_vertices() -> PackedVector3Array:
	var st := K.begin()
	for sx in [-1, 1]:
		var rings: Array = []
		for r in LEG_PROFILE:
			rings.append(body._ring(r[0], sx * r[1], r[3], r[4], r[5], 8, r[2]))
		FDKLowPoly.loft(st, rings, [FPMirrorBody.SKIN], false, false)
		K.tube(st, Transform3D.IDENTITY, [Vector3(sx * 0.078, -0.89, -0.03), Vector3(sx * 0.08, -0.915, 0.03), Vector3(sx * 0.085, -0.93, 0.12)], [0.032, 0.036, 0.026], 6, [FPMirrorBody.SKIN_D, FPMirrorBody.SKIN], true, 0.65)
	var result: PackedVector3Array = K.finish(st).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in range(result.size()):
		result[i].y += 0.95
	return result

func aim_hits_torso(cam: Camera3D, torso: MeshInstance3D) -> bool:
	var a := torso.to_local(cam.global_position)
	var b := torso.to_local(cam.global_position - cam.global_basis.z * 1.5)
	var arrays := torso.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ids := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		ids = arrays[Mesh.ARRAY_INDEX]
	if ids.is_empty():
		for i in range(vs.size()):
			ids.append(i)
	for i in range(0, ids.size(), 3):
		if Geometry3D.segment_intersects_triangle(a, b, vs[ids[i]], vs[ids[i + 1]], vs[ids[i + 2]]) != null:
			return true
	return false

func check_geometry() -> void:
	body = FPMirrorBody.new()
	root.add_child(body)
	body.set_process(false)
	body.set_posture(0, 0, 0, 0)
	var actual := PackedVector3Array()
	for s in ["r", "l"]:
		actual.append_array(vertices(body.sub_node("thigh_" + s)))
	var actual_keys := vertex_keys(actual)
	var old_keys := vertex_keys(old_leg_vertices())
	check(actual_keys == old_keys, "standing leg/foot vertex positions preserve the historical profiles")
	var resting := {}
	for p in body._parts:
		resting[p] = body.part_node(p).transform
	var mesh_sizes := {}
	for mesh in meshes(body):
		mesh_sizes[mesh] = mesh.mesh.get_aabb().size
	var rest_ankles := {}
	for s in ["r", "l"]:
		rest_ankles[s] = body.sub_node("foot_" + s).global_position
	var previous_face: Vector3 = body.part_node("face").position
	for step in range(21):
		var c := float(step) / 20.0
		body.set_posture(c, 0, 0, 0)
		for s in ["r", "l"]:
			check(body.sub_node("foot_" + s).global_position.distance_to(rest_ankles[s]) < 0.00001, "ankle planted across squat fraction %d/%s" % [step, s])
			check(body.sub_node("foot_" + s).global_basis.is_equal_approx(Basis.IDENTITY), "foot stays flat at squat fraction %d/%s" % [step, s])
			var upper: Node3D = body.sub_node("upper_" + s)
			var lower: Node3D = body.part_node("right_hand" if s == "r" else "left_hand")
			check(lower.get_parent() == upper, "forearm stays connected to elbow %d/%s" % [step, s])
			check(lower.global_position.distance_to(upper.to_global(lower.get_meta("base_pos"))) < 0.00001, "elbow attachment shares the upper arm transform %d/%s" % [step, s])
		for n in body._rest_pose:
			var rest: Transform3D = body._rest_pose[n]
			check((n as Node3D).scale.is_equal_approx(rest.basis.get_scale()), "posture preserves full size of " + str(n.name))
		check(body.part_node("face").position.distance_to(previous_face) < 0.13, "head transition continuous at fraction %d" % step)
		previous_face = body.part_node("face").position
	for mesh in mesh_sizes:
		check(mesh.mesh.get_aabb().size.is_equal_approx(mesh_sizes[mesh]), "crouch leaves actual mesh dimensions intact: " + str(mesh.name))
	var low := INF
	var high := -INF
	for p in ["face", "neck", "belly", "chest", "arms", "legs"]:
		for v in vertices(body.part_node(p)):
			low = minf(low, v.y)
			high = maxf(high, v.y)
	check(low >= -0.005, "full crouched geometry does not penetrate the feet plane")
	check(high <= 0.905, "unscaled crouched head/body fits the actual 0.9m height")
	check(body.sub_node("thigh_r").rotation.x < -1.0 and body.sub_node("shin_r").rotation.x > 1.0, "squat is actual hip/knee articulation")
	for c in [0.0, 1.0]:
		for pitch in [-1.55, -0.8, 0.0, 0.8]:
			body.set_posture(c, 0, 0, pitch)
			var forward := body.part_node("face").basis.z.normalized()
			check(forward.y * pitch >= -0.00001, "+Z model gaze follows camera pitch sign %s/%s" % [c, pitch])
	for phase in [0.0, PI, TAU, PI * 3.0]:
		body.set_posture(0, phase, 1, 0)
		for s in ["r", "l"]:
			var lower: Node3D = body.part_node("right_hand" if s == "r" else "left_hand")
			check(lower.global_position.distance_to(lower.get_parent().to_global(lower.get_meta("base_pos"))) < 0.00001, "walking keeps elbow seam attached %s/%s" % [phase, s])
	check(absf(body.sub_node("thigh_r").rotation.x) > 0.1, "walking rotates actual thigh geometry")
	body.set_posture(0, 0, 0, 0)
	for p in resting:
		check(body.part_node(p).transform.is_equal_approx(resting[p]), "idle returns to original part transform: " + p)
	body.apply(["M18", "M20", "M01"])
	var mutated_arm: Basis = body.sub_node("upper_r").basis
	var mutated_hand: Basis = body.sub_node("hand_r").basis
	var mutated_belly: Transform3D = body.part_node("belly").transform
	body.set_posture(0, 0, 0, 0)
	check(body.sub_node("upper_r").basis.is_equal_approx(mutated_arm), "mutation upper-arm rotation survives idle posture")
	check(body.sub_node("hand_r").basis.is_equal_approx(mutated_hand), "mutation and original hand rotations survive posture")
	check(body.part_node("belly").transform.is_equal_approx(mutated_belly), "mutation belly size/offset survives posture")
	body.queue_free()

func run() -> void:
	check_geometry()
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://t3_body_posture_test.bin"
	root.add_child(m)
	await frames(6)
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.player.global_position = Vector3(0, 0.9, 0.3)
	await frames(6)
	var belt: Node3D = m.art_hookup.belt
	var standing_belt: Transform3D = belt.transform
	var standing_feet: Vector3 = m.player.get_feet_position()
	for crouch in [false, true, false]:
		if crouch:
			Input.action_press("fdk_crouch")
		else:
			Input.action_release("fdk_crouch")
		await frames(4)
		check(m.player._is_crouching == crouch, "normal physics input sets real crouch state")
		check(m.player.get_feet_position().distance_to(standing_feet) < 0.001, "actual crouch input preserves feet")
		var expected_eye := 0.8 if crouch else 1.6
		check(absf(m.player.camera_pivot.global_position.y - standing_feet.y - expected_eye) < 0.001, "actual crouch eye follows capsule height")
		for pitch in [0.0, -1.55]:
			m.player._pitch = pitch
			m.player.camera_pivot.rotation.x = pitch
			await frames(4)
			var offset: Vector3 = m.player.camera_pivot.basis * m.player.camera.position
			if pitch < -1.0:
				check(absf(offset.z + 0.17) < 0.002 and absf(offset.y + 0.08) < 0.002, "normal loop applies full-size 17cm/8cm head bow in player axes")
				check(not aim_hits_torso(m.player.camera, belt.get_node("Torso")), "actual belly mesh leaves the center aim clear when fully looking down")
			else:
				check(offset.length() < 0.001, "head rest returns without residual terrain correction")
			var rel: Transform3D = belt.transform
			for action in ["fdk_move_forward", "fdk_move_back", "fdk_move_left", "fdk_move_right"]:
				Input.action_press(action)
				await frames(6)
				Input.action_release(action)
				check(belt.transform.is_equal_approx(rel), "actual WASD preserves belt relative pose %s/%s/%s" % [crouch, pitch, action])
			await frames(20)
	check(belt.transform.is_equal_approx(standing_belt), "stand/crouch sequence restores approved belt pose")
	print("--- %d passed, %d failed ---" % [passed, failed])
	m.queue_free()
	await process_frame
	quit(1 if failed > 0 else 0)
