extends SceneTree

var m: Node3D
var passed := 0
var failed := 0
var folder: String
var records: Array = []

func _init() -> void:
	if not OS.get_user_data_dir().contains("flesh-pit-restoration-"):
		quit(2)
		return
	root.size = Vector2i(640, 360)
	folder = ProjectSettings.globalize_path("res://../.dryforge/evidence/T10/normal-play")
	DirAccess.make_dir_recursive_absolute(folder)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL: ", label)
	records.append({"label": label, "passed": ok})

func frames(count: int) -> void:
	for i in range(count): await physics_frame
	await process_frame

func aim(point: Vector3) -> void:
	var d: Vector3 = (point - m.player.camera.global_position).normalized()
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = asin(d.y)
	m.player.rotation.y = m.player._yaw
	m.player.camera_pivot.rotation.x = m.player._pitch

func key(code: Key, held: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = held
	Input.parse_input_event(e)

func mouse(button: MouseButton, held: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = held
	Input.parse_input_event(e)

func event_input(kind: String, value: int, held: bool) -> void:
	if kind == "key": key(value as Key, held)
	elif kind == "mouse": mouse(value as MouseButton, held)
	elif kind == "pad":
		var e := InputEventJoypadMotion.new()
		e.device = 0
		e.axis = JOY_AXIS_LEFT_Y
		e.axis_value = -1.0 if held else 0.0
		Input.parse_input_event(e)

func new_game(position := Vector3(-1.25, 0.9, 0.72)) -> void:
	if is_instance_valid(m):
		m.queue_free()
		await frames(2)
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = folder.path_join("isolated.bin")
	root.add_child(m)
	await frames(6)
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.player.global_position = position
	aim(m.toilet_point())
	await frames(3)

func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_size() == Vector2i(640, 360), label + " real GUI 640x360")
	check(image.save_png(folder.path_join(label + ".png")) == OK, label + " saved")

func exit_case(kind: String, value: int, label: String, lever := false) -> void:
	await new_game()
	if value == KEY_P:
		var binding := InputEventKey.new()
		binding.physical_keycode = KEY_P
		InputMap.action_add_event("fp_vomit", binding)
	m.stomach.add_flesh(25.0)
	key(KEY_V, true)
	await frames(5)
	check(m.is_settling(), label + " entry V stays held without exit")
	key(KEY_V, false)
	await frames(3)
	if lever:
		await frames(150)
		aim(m.lever_point())
		await frames(2)
		# Initial aiming of the existing presentation camera only; normal Main input owns execution.
		m.settle_camera.look_at(m.lever_point(), Vector3.UP)
		await frames(2)
		print(label, " physical_eye=", m.player.camera.global_position, " lever=", m.lever_point(), " distance=", m.player.camera.global_position.distance_to(m.lever_point()), " ray=", FPInteractions.check_aim(m, m.lever_point(), "lever"), " kind=", m.hand_motions.kind)
		check(FPInteractions.is_lever_aimed(m, m.settle_camera), label + " actual lever visible and reachable")
	else:
		m.settle_camera.look_at(m.toilet_point(), Vector3.UP)
	var bowl: float = m.toilet.bowl_flesh
	var teeth: int = m.progression.teeth
	event_input(kind, value, true)
	await frames(4)
	check(not m.is_settling() and m.player.is_physics_processing(), label + " fresh input exits")
	check(is_zero_approx(m.toilet.bowl_flesh) if lever else is_equal_approx(m.toilet.bowl_flesh, bowl), label + " flush priority / preserve bowl")
	check(m.progression.teeth > teeth if lever else m.progression.teeth == teeth, label + " only aimed lever awards teeth")
	event_input(kind, value, false)
	await frames(2)

func run() -> void:
	await new_game()
	check(m.is_processing() and m.player.is_physics_processing(), "normal process and physics enabled")
	check(not m.has_canary, "initial canary absent")
	await shot("initial-room")
	for code in [KEY_V, KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_F, KEY_ESCAPE]:
		await exit_case("key", code, "raw key " + OS.get_keycode_string(code))
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		await exit_case("mouse", button, "raw mouse " + str(button))
	await exit_case("pad", 0, "pad left stick")
	# Bind a fresh alternate key without changing persisted settings.
	var remapped := InputEventKey.new()
	remapped.physical_keycode = KEY_P
	InputMap.action_add_event("fp_vomit", remapped)
	await exit_case("key", KEY_P, "remapped vomit P")
	InputMap.action_erase_event("fp_vomit", remapped)
	for code in [KEY_F, KEY_R]: await exit_case("key", code, "aimed lever " + OS.get_keycode_string(code), true)
	await exit_case("mouse", MOUSE_BUTTON_RIGHT, "aimed lever RMB", true)
	await shot("after-natural-exit")
	var output := FileAccess.open(folder.path_join("results.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed": passed, "failed": failed, "checks": records}, "\t"))
	output.close()
	m.queue_free()
	await frames(2)
	print("T10 normal play: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
