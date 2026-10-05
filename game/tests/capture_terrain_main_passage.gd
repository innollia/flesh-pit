extends SceneTree

var m: Node3D
var passed := 0
var failed := 0
var torn: Array[Vector3] = []
var destination: String
var isolated_save_path: String
var surface_probe: FPBodyClearance
var capsule_overlap_seen := false

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
	surface_probe = FPBodyClearance.new()
	await passage_surface_controls()
	var z_start: float = m.player.global_position.z
	send_key(KEY_W, true)
	var penetrated := false
	for frame in range(60):
		await physics_frame
		if frame % 5 == 0:
			await shot("walking_frame_%02d" % frame)
		var lo: Vector3 = m.player.global_position.min(m.player.camera.global_position) - Vector3.ONE * 1.5
		var hi: Vector3 = m.player.global_position.max(m.player.camera.global_position) + Vector3.ONE * 1.5
		surface_probe._prepare_surface(m.terrain, lo, hi)
		var body_inside: bool = surface_probe._point_in_solid(m.player.global_position)
		var camera_inside: bool = surface_probe._point_in_solid(m.player.camera.global_position)
		var capsule: Dictionary = FPBodyClearance.new().assess(m.player, m.terrain)
		capsule_overlap_seen = capsule_overlap_seen or bool(capsule.overlap)
		if frame % 5 == 0 or m.terrain.density_at(m.player.camera.global_position) >= m.terrain_config.iso_level:
			print("PASSAGE_CURRENT frame=",frame," body=",m.player.global_position," camera=",m.player.camera.global_position," body_inside=",body_inside," camera_inside=",camera_inside," capsule_overlap=",capsule.overlap," conservative_camera_cell=",m.terrain.density_at(m.player.camera.global_position)," independent_trilinear=",continuous_density(m.player.camera.global_position))
		if body_inside or camera_inside:
			penetrated = true
			break

	send_key(KEY_W, false)
	await physics_frame
	await physics_frame

	check(not penetrated, "no collision penetration into solid flesh while walking forward")
	check(not capsule_overlap_seen, "actual whole capsule stays outside current terrain surface while walking")
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

func continuous_density(p: Vector3) -> float:
	# Independent diagnostic only. Surface-net triangles remain authoritative
	# in mixed cells; max-of-eight is a conservative cell query, not a point.
	var scaled: Vector3 = p / m.terrain_config.cell_size
	var base := Vector3i(scaled.floor())
	var weight: Vector3 = scaled - Vector3(base)
	var result := 0.0
	for z in range(2):
		for y in range(2):
			for x in range(2):
				var w: float = (weight.x if x else 1.0-weight.x) * (weight.y if y else 1.0-weight.y) * (weight.z if z else 1.0-weight.z)
				result += m.terrain.corner_density_global(base+Vector3i(x,y,z)) * w
	return result

func passage_surface_controls() -> void:
	var empty := Vector3(0,1.2,0)
	surface_probe._prepare_surface(m.terrain,empty-Vector3.ONE,empty+Vector3.ONE)
	check(not surface_probe._point_in_solid(empty) and continuous_density(empty) < m.terrain_config.iso_level,"actual room empty-point negative control")
	var solid := Vector3.ZERO
	var found := false
	for x in range(3,12):
		for y in range(0,6):
			for z in range(3,12):
				var point: Vector3 = (Vector3(x,y,z)+Vector3.ONE*0.5)*m.terrain_config.cell_size
				var base := Vector3i(x,y,z)
				var low := INF
				for dz in range(2):
					for dy in range(2):
						for dx in range(2): low=minf(low,m.terrain.corner_density_global(base+Vector3i(dx,dy,dz)))
				if low >= m.terrain_config.iso_level:
					solid=point
					found=true
					break
			if found: break
		if found: break
	check(found,"actual fully solid eight-corner positive fixture exists")
	if found:
		surface_probe._prepare_surface(m.terrain,solid-Vector3.ONE,solid+Vector3.ONE)
		check(surface_probe._point_in_solid(solid) and continuous_density(solid) >= m.terrain_config.iso_level,"actual full-solid inside positive control is detected")
	var eye: Vector3 = m.player.camera.global_position
	surface_probe._prepare_surface(m.terrain,eye-Vector3.ONE*2.0,eye+Vector3.ONE*2.0)
	var faces: PackedVector3Array = surface_probe._faces
	check(faces.size() >= 3,"actual current mixed-cell surface triangles exist")
	if faces.size() >= 3:
		var a := faces[0]
		var b := faces[1]
		var c := faces[2]
		var at := (a+b+c)/3.0
		var outward := -(b-a).cross(c-a).normalized()
		var inside := at-outward*0.02
		var outside := at+outward*0.02
		check(Geometry3D.segment_intersects_triangle(inside,outside,a,b,c)!=null,"known actual triangle crosses oriented inside/outside control segment")
		check(surface_probe._point_in_solid(inside) and not surface_probe._point_in_solid(outside),"actual oriented mixed-face inside/outside controls agree")
