extends SceneTree
const INPUT_MODES := preload("res://main/scripts/fp_input_modes.gd")
var m: Node3D
var passed := 0
var failed := 0
func _init() -> void:
	if not OS.get_user_data_dir().contains("flesh-pit-restoration-T5"):
		quit(2)
		return
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://interaction-component-test.bin"
	root.add_child(m)
	run.call_deferred()
func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)
func clear_inputs() -> void:
	for action in ["fp_vomit", "fp_interact", "fp_pick", "fdk_move_forward", "fdk_eat"]:
		Input.action_release(action)
func run() -> void:
	await process_frame
	m.finish_opening()
	# Component checks deliberately isolate Main's old, not-yet-wired input loop.
	# Normal Main input/physics/render behavior is checked after final integration.
	m.set_process(false)
	m.player.set_physics_process(false)
	m.player.global_position = Vector3(-1.25, 0.9, 0.72)
	m.player.camera.look_at(m.lever_point(), Vector3.UP)
	await physics_frame
	check(FPInteractions.is_lever_aimed(m, m.player.camera), "actual nearby lever is reachable and aimed")
	var blocker := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * 0.15
	collider.shape = box
	blocker.add_child(collider)
	root.add_child(blocker)
	blocker.global_position = m.player.camera.global_position.lerp(m.lever_point(), 0.5)
	await physics_frame
	check(not FPInteractions.is_lever_aimed(m, m.player.camera), "real intervening collider blocks lever")
	blocker.queue_free()
	await physics_frame
	m.player.global_position += Vector3.RIGHT * 3.0
	m.player.camera.look_at(m.lever_point(), Vector3.UP)
	check(not FPInteractions.is_lever_aimed(m, m.player.camera), "presentation aim cannot extend physical lever reach")
	m.player.global_position = Vector3(-1.25, 0.9, 0.72)
	m.player.camera.look_at(m.lever_point(), Vector3.UP)
	m.player.camera.rotate_y(PI)
	check(not FPInteractions.is_lever_aimed(m, m.player.camera), "lever behind view is not aimed")
	m.player.camera.look_at(m.lever_point(), Vector3.UP)
	var before: Vector3 = FPInteractions.get_candidates(m)[5][1]
	m.restroom.set_door_open(true, true)
	var after: Vector3 = FPInteractions.get_candidates(m)[5][1]
	check(before.distance_to(after) > 0.2, "candidate follows actual door swing")
	check(m.tank_lid.get_parent() == m, "loose lid owner belongs to scene tree")
	Input.action_press("fp_vomit")
	m._settling = true
	m.toilet.bowl_flesh = 25.0
	FPInteractions.begin_settlement(m)
	var entry := Engine.get_process_frames()
	check(FPInteractions.handle_settling_input(m, entry, "fp_vomit") == "guard", "entry press cannot exit same frame")
	while Engine.get_process_frames() <= entry:
		await process_frame
	check(FPInteractions.handle_settling_input(m, entry, "fp_vomit") == "none", "held entry press does not exit next frame")
	Input.action_press("fdk_move_forward")
	check(FPInteractions.handle_settling_input(m, entry, "fp_vomit") == "exit", "new movement exits even while entry V remains held")
	check(not m._settling and is_equal_approx(m.toilet.bowl_flesh, 25.0), "exit preserves unflushed bowl")
	clear_inputs()
	await process_frame
	m._settling = true
	FPInteractions.begin_settlement(m)
	entry = Engine.get_process_frames()
	while Engine.get_process_frames() <= entry:
		await process_frame
	m.settle_camera.global_position = m.player.camera.global_position
	m.settle_camera.look_at(m.lever_point(), Vector3.UP)
	Input.action_press("fp_pick")
	check(FPInteractions.handle_settling_input(m, entry) == "flush", "fresh pick uses physically valid aimed lever")
	check(is_zero_approx(m.toilet.bowl_flesh) and not m._settling, "lever actually flushes bowl once")
	var teeth: int = m.progression.teeth
	check(FPInteractions.handle_settling_input(m, entry) == "none", "held pick does not repeat flush")
	check(m.progression.teeth == teeth, "held pick does not duplicate payout")
	clear_inputs()
	await process_frame
	m._settling = true
	FPInteractions.begin_settlement(m)
	entry = Engine.get_process_frames()
	while Engine.get_process_frames() <= entry:
		await process_frame
	Input.action_press("fp_vomit")
	check(FPInteractions.handle_settling_input(m, entry) == "exit", "fresh vomit press exits")
	clear_inputs()
	m.queue_free()
	await process_frame
	print("INTERACTIONS COMPONENT: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
