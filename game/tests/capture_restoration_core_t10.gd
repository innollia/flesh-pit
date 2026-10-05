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

func run() -> void:
	await new_game(Vector3(5.0, 1.4, -2.5))
	# One initial physical fixture: ordinary core flesh, an open narrow walkable
	# tunnel, and a real flesh floor. No subsequent density or stomach resets.
	m.terrain.fill_box_uniform(AABB(Vector3(3, 0, -4), Vector3(5, 5, 8)), 1.0, 0)
	m.terrain.fill_box_uniform(AABB(Vector3(4.5, 0.5, -3.5), Vector3(1.0, 3.5, 7)), 0.0, 0)
	m.terrain.remesh_all()
	await frames(4)
	var tears: Array[Vector3] = []
	m.chewer.cell_torn.connect(func(p): tears.append(p))
	var baseline_teeth: int = m.progression.teeth
	var baseline_hair: int = m.progression.total_hairs()
	var vomits := 0
	for step in range(13):
		for height in [1.0, 1.5, 2.0, 2.5]:
			for depth in range(3):
				if tears.size() >= 75: break
				var target := Vector3(5.75 + depth * 0.5, height, m.player.global_position.z)
				aim(target)
				await frames(2)
				var before := tears.size()
				mouse(MOUSE_BUTTON_LEFT, true)
				for i in range(100):
					await process_frame
					if tears.size() > before: break
				mouse(MOUSE_BUTTON_LEFT, false)
				await frames(2)
				if tears.size() > before:
					print("COREPROGRESS cells=",tears.size()," fill=",m.stomach.fill," hairs=",m.progression.total_hairs()," body=",m.player.global_position)
					var p: Vector3 = tears.back()
					check(m.shell_at(p) == 0 and m.terrain.density_at(p) < 0.5, "actual core tear %d density removed" % tears.size())
					if tears.size() % 25 == 0:
						check(is_equal_approx(m.stomach.fill, 100.0), "actual %d cells fills stomach 100" % tears.size())
						check(m.progression.total_hairs() > baseline_hair and m.progression.teeth == baseline_teeth, "hair visible before any flush at %d cells" % tears.size())
						if DisplayServer.get_name() != "headless": await shot("core-fill-%d" % tears.size())
						if tears.size() < 75:
							key(KEY_V, true)
							await frames(3)
							key(KEY_V, false)
							await frames(150)
							check(is_zero_approx(m.stomach.fill) and not m.is_settling(), "natural cave V empties stomach without flush")
							vomits += 1
			if tears.size() >= 75: break
		if tears.size() >= 75: break
		# Actual normal movement along the opened corridor to new wall cells.
		aim(m.player.camera.global_position + Vector3.RIGHT)
		var z: float = m.player.global_position.z
		key(KEY_D, true)
		for i in range(50):
			await physics_frame
			if m.player.global_position.z > z + 0.5: break
		key(KEY_D, false)
		await frames(2)
	print("CORE75 count=",tears.size()," pos=",m.player.global_position," hair=",m.progression.total_hairs()," vomits=",vomits," deaths=",m.deaths)
	check(tears.size() == 75 and vomits == 2, "75 actual LMB cells over three normal fills")
	check(m.progression.hairs(FPProgression.biome_for_shell(0)) == 6, "actual core 300 grows six biome hairs")
	check(m.progression.hairs(FPProgression.COMMON) == 2, "actual core 300 grows two common hairs")
	check(m.progression.total_hairs() - baseline_hair == 8 and m.progression.teeth == baseline_teeth, "six plus two hairs before flush")
	check(m.deaths == 0 and m.is_processing() and m.player.is_physics_processing(), "normal physical gameplay remains alive")
	var output := FileAccess.open(folder.path_join("core75-results.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed": passed, "failed": failed, "checks": records, "tears": tears.size(), "vomits": vomits}, "\t"))
	output.close()
	m.queue_free()
	await frames(2)
	print("T10 core75: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
