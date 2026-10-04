extends SceneTree

var m: Node3D
var passed := 0
var failed := 0
var torn: Array[Vector3] = []
var destination: String
var isolated_save_path: String

func _init() -> void:
	root.size = Vector2i(640, 360)
	destination = ProjectSettings.globalize_path("res://../.dryforge/evidence/antigravity-19-passage")
	DirAccess.make_dir_recursive_absolute(destination)
	var passage_evidence := ProjectSettings.globalize_path("res://../.dryforge/evidence/main-passage")
	DirAccess.make_dir_recursive_absolute(passage_evidence)
	isolated_save_path = passage_evidence.path_join("isolated.bin")

	m = load("res://main/scenes/main.tscn").instantiate()
	m.rest_seed = 1337
	m.save_path = isolated_save_path
	root.add_child(m)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func send_key(keycode: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.keycode = keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)

func send_mouse(button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)

func aim(yaw: float, pitch: float) -> void:
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

func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image.get_size() == Vector2i(640, 360), label + " resolution 640x360")
	image.save_png(destination.path_join(label + ".png"))
	var exposed := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.r > 0.8 and color.b > 0.8 and color.g < 0.2:
				exposed += 1
	print(label, " background_pixels=", exposed, " tears=", torn.size(), " pos=", m.player.global_position)
	check(exposed == 0, label + " background_pixels == 0")

func run() -> void:
	await process_frame
	root.size = Vector2i(640, 360)
	m.save_path = isolated_save_path
	m.finish_opening()

	m.environment.background_color = Color(1, 0, 1, 1)
	m.apply_atmosphere_now()

	m.chewer.cell_torn.connect(func(p: Vector3):
		torn.append(p)
		print("CELL_TORN at ", p, " count=", torn.size())
	)

	# Fixture pose: inside restroom facing closed stall door
	var door_point := Vector3(0, 1, FPRestroom.HALF.z)
	m.player.global_position = Vector3(0, 0.95, FPRestroom.HALF.z - 0.8)
	m.player.velocity = Vector3.ZERO
	face(door_point)
	for _f in range(5):
		await process_frame

	check(m.interact_target() == "door", "aiming at closed door targets door")

	# Real F input to open door
	send_key(KEY_F, true)
	await process_frame
	await process_frame
	send_key(KEY_F, false)
	await process_frame
	await process_frame

	check(m.restroom.is_door_open(), "F key opens door")

	# Wait for door swing animation to settle
	for _f in range(60):
		await process_frame

	# Phase 1: 뜯기 전 (before dig)
	await shot("phase1_before_dig")
	check(m.stomach.fill == 0 and torn.is_empty(), "clean digestive state before dig")
	var initial_fill: float = m.stomach.fill
	var initial_excavated: int = m.excavated_cells

	# Phase 2: Start Left Mouse Click and capture 진행 중 (in progress)
	send_mouse(MOUSE_BUTTON_LEFT, true)

	var in_progress_captured := false
	var captured_tears := 0

	for frame in range(250):
		await process_frame
		if frame % 12 == 0:
			await shot("held_frame_%03d" % frame)
		if not in_progress_captured and m.chewer.is_chewing():
			in_progress_captured = true
			await shot("phase2_chew_in_progress")

		if torn.size() > captured_tears:
			captured_tears = torn.size()
			await shot("tear_" + str(captured_tears))

		if torn.size() >= 2:
			break

	send_mouse(MOUSE_BUTTON_LEFT, false)
	await process_frame

	# Phase 3: 직후 (right after dig)
	await shot("phase3_right_after_dig")

	check(torn.size() >= 2, "held left click produced at least 2 repeated tears")
	check(m.excavated_cells == initial_excavated + torn.size(), "excavated cells matched tear count")
	check(is_equal_approx(m.stomach.fill, initial_fill + torn.size() * m.stomach_config.flesh_per_cell), "stomach fill matched torn cells")
	for p in torn:
		check(m.terrain.density_at(p) < m.terrain_config.iso_level, "density decreased below iso at " + str(p))
	check(not m.chewer.is_chewing(), "chewing stopped after mouse release")

	# Phase 4: 재생 중 (during regeneration)
	for _f in range(30):
		await process_frame
		if _f % 5 == 0:
			await shot("healing_frame_%02d" % _f)
	await shot("phase4_during_regeneration")

	# Movement: Real W input to advance toward excavated passage
	var z_start: float = m.player.global_position.z
	send_key(KEY_W, true)

	var penetrated := false
	for frame in range(60):
		await physics_frame
		if frame % 5 == 0:
			await shot("walking_frame_%02d" % frame)
		if m.terrain.density_at(m.player.global_position) >= m.terrain_config.iso_level:
			penetrated = true
			break
		if m.terrain.density_at(m.player.camera.global_position) >= m.terrain_config.iso_level:
			penetrated = true
			break

	send_key(KEY_W, false)
	await physics_frame
	await physics_frame

	check(not penetrated, "no collision penetration into solid flesh while walking forward")
	check(m.player.global_position.z > z_start + 0.05, "player advanced forward along excavated direction")
	check(m.player.global_position.y > 0.0, "player grounded without falling through floor")

	# Directional look observation: ceiling, diagonal, walls
	var current_yaw: float = m.player._yaw

	# Ceiling
	aim(current_yaw, deg_to_rad(80.0))
	await shot("look_ceiling")

	# Diagonal up-left
	aim(current_yaw - deg_to_rad(40.0), deg_to_rad(45.0))
	await shot("look_diagonal_up_left")

	# Diagonal up-right
	aim(current_yaw + deg_to_rad(40.0), deg_to_rad(45.0))
	await shot("look_diagonal_up_right")

	# Wall left
	aim(current_yaw - deg_to_rad(75.0), deg_to_rad(5.0))
	await shot("look_wall_left")

	# Wall right
	aim(current_yaw + deg_to_rad(75.0), deg_to_rad(5.0))
	await shot("look_wall_right")

	# Floor
	aim(current_yaw, deg_to_rad(-60.0))
	await shot("look_floor")
	check(m.deaths == 0 and m.hazard.health > 0, "no death or reset hides the passage failure")

	print("%d passed, %d failed" % [passed, failed])
	m.queue_free()
	await process_frame
	quit(1 if failed else 0)
