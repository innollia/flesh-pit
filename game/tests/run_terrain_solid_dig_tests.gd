extends SceneTree

# Dedicated tests for real Main input tearing/repeating from full solid mass.
# Exercises real PackedScene, player physics, game loop, and real Input.parse_input_event(LMB).

var m: Node3D
var passed := 0
var failed := 0
var torn: Array[Vector3] = []
var center := Vector3(8, 5, 8)
var grabs := 0
var progress := 0
var releases := 0
var fixed_down_support: StaticBody3D

func _init() -> void:
	Engine.max_fps = 60
	m = load("res://main/scenes/main.tscn").instantiate()
	m.rest_seed = 1337
	root.add_child(m)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func mouse(held: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = held
	Input.parse_input_event(event)

func aim(direction: Vector3) -> void:
	var dir := direction.normalized()
	m.player._yaw = atan2(-dir.x, -dir.z)
	m.player._pitch = asin(clampf(dir.y, -1, 1))
	m.player.rotation.y = m.player._yaw
	m.player.camera_pivot.rotation.x = m.player._pitch

func ray(origin: Vector3, direction: Vector3, distance: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * distance)
	q.exclude = [m.player.get_rid()]
	return m.get_world_3d().direct_space_state.intersect_ray(q)

func mesh_triangle_count() -> int:
	var result := 0
	for chunk in m.terrain.get_chunks():
		var mesh: Mesh = chunk._mesh_instance.mesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			result += mesh.surface_get_array_len(surface) / 3
	return result

func fixture_solid(direction: Vector3) -> void:
	mouse(false)
	m._crush_t = 0.0
	await create_timer(0.2).timeout
	m.terrain.remesh_budget_per_frame = 1
	m.terrain.fill_box_uniform(AABB(center - Vector3.ONE * 3, Vector3.ONE * 6), 1.0, 0)
	m.terrain.remesh_all()
	m.player.global_position = center - Vector3.UP * m.player.eye_pivot_y(false)
	m.player.velocity = Vector3.ZERO
	m.stomach.fill = 0
	m.carried_flesh = 0
	m.excavated_cells = 0
	m._crush_t = 0.0
	m.hazard.health = 100
	m.carry_mode = false
	m.equip_tool("")
	aim(direction)
	await physics_frame
	await physics_frame
	await process_frame
	torn.clear()

func run() -> void:
	await create_timer(0.1).timeout
	m.finish_opening()

	InputMap.action_erase_events("fdk_eat")
	var binding := InputEventMouseButton.new()
	binding.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fdk_eat", binding)

	m.chewer.cell_torn.connect(func(p): torn.append(p))
	m.chewer.grab_started.connect(func(_p): grabs += 1)
	m.chewer.chew_progress.connect(func(_r, _p): progress += 1)
	m.chewer.released.connect(func(): releases += 1)

	# --- 1. 6 axes + diagonal single tear test in full solid mass ---
	var directions: Array[Vector3] = [
		Vector3.FORWARD,
		Vector3.BACK,
		Vector3.LEFT,
		Vector3.RIGHT,
		Vector3.UP,
		Vector3.DOWN,
		Vector3(1, 0.9, 0.8).normalized()
	]

	for dir in directions:
		var label := "solid_axis " + str(dir)
		await fixture_solid(dir)
		var eye: Vector3 = m.player.camera.global_position
		var reach: float = m.progression.reach()

		# Verify full solid mass initial state
		check(ray(eye, dir, reach).is_empty(), label + " ordinary physics 0 faces along ray")
		check(m._published_terrain_contact(eye, dir, reach).is_empty(), label + " ordinary mesh 0 faces within reach")
		var pre_hit: Dictionary = m._look_hit()
		check(not pre_hit.is_empty() and pre_hit.get("fdk_solid_volume", false) == true, label + " solid volume look_hit")

		# Check 8 corners around camera cell >= iso
		var cell_info: Array = m.terrain.world_to_cell(eye)
		var chunk_coord: Vector3i = cell_info[0]
		var local_cell: Vector3i = cell_info[1]
		var global_cell: Vector3i = chunk_coord * m.terrain_config.chunk_size + local_cell
		var all_eight_solid := true
		for dz in range(2):
			for dy in range(2):
				for dx in range(2):
					if m.terrain.corner_density_global(global_cell + Vector3i(dx, dy, dz)) < m.terrain_config.iso_level:
						all_eight_solid = false
		check(all_eight_solid, label + " actual 8 corners >= iso")

		# Start real LMB grab
		mouse(true)
		for frame in range(15):
			await process_frame
			if m.chewer.is_chewing():
				break

		# Check before first tear: food 0, torn 0, chew active, no death
		check(torn.is_empty(), label + " no tear before chew time")
		check(m.stomach.fill == 0 and m.carried_flesh == 0, label + " food 0 before first tear")
		check(m.chewer.is_chewing(), label + " chew actively chewing")
		check(m.hazard.health > 0 and m.deaths == 0, label + " player alive without death during grab")

		# Wait for first actual tear
		for frame in range(75):
			if not torn.is_empty():
				break
			await process_frame

		check(torn.size() == 1, label + " first actual tear occurred")
		check(m.hazard.health > 0 and m.deaths == 0, label + " player alive after first tear")

		if torn.size() >= 1:
			var target_pos: Vector3 = torn[0]
			check(m.terrain.density_at(target_pos) < m.terrain_config.iso_level, label + " density decreased at torn target")
			var has_surface: bool = (m.terrain._surface_patch != null and not m.terrain._surface_patch.faces.is_empty()) or mesh_triangle_count() > 0
			check(has_surface, label + " actual mesh or pending faces created")
			check(m.excavated_cells == 1, label + " excavated_cells == 1")
			check(is_equal_approx(m.stomach.fill, m.stomach_config.flesh_per_cell), label + " stomach fill matches flesh_per_cell")

		# Release real LMB and verify stop
		mouse(false)
		await process_frame
		await process_frame
		check(not m.chewer.is_chewing(), label + " release actual stop")

	# --- 2. Budget 1 pending gap inspection & 6-direction hole investigation ---
	var budget_label := "budget1_gap_hole"
	await fixture_solid(Vector3.FORWARD)
	m.terrain.remesh_budget_per_frame = 1
	mouse(true)
	for frame in range(75):
		if not torn.is_empty():
			break
		await process_frame
	mouse(false)
	check(torn.size() == 1, budget_label + " tear completed")

	if torn.size() >= 1:
		var hole_p: Vector3 = torn[0]
		# Do NOT call remesh_all()! Budget 1 is active.
		# Maintain budget 1 across several frames and check pending patch gap exists
		var patch_existed := false
		for f in range(4):
			await process_frame
			await physics_frame
			if m.terrain._surface_patch != null and not m.terrain._surface_patch.faces.is_empty():
				patch_existed = true
		check(patch_existed, budget_label + " pending surface patch existed during budget 1 frames")

		# Allow publication to finish naturally through frame processing
		var wait_frames := 0
		while not m.terrain._mesh_batch.is_empty() and wait_frames < 60:
			await process_frame
			await physics_frame
			wait_frames += 1

		# Investigate collision + hole in 6 directions from hole center
		var axes := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
		for a in axes:
			var col := ray(hole_p, a, 0.7)
			check(not col.is_empty() and col.collider.has_meta("fdk_terrain_chunk"), budget_label + " hole collision in direction " + str(a))
			if not col.is_empty():
				var dist := hole_p.distance_to(col.position)
				check(dist >= 0.1 and dist <= 0.65, budget_label + " hole wall distance in range for " + str(a))

	# --- 3. Carry mode test in full solid mass ---
	var carry_label := "solid_carry"
	await fixture_solid(Vector3.RIGHT)
	m.progression.grant_item("blender")
	m.toggle_carry()
	m.equip_hand("", FDKToolKit.Hand.LEFT)
	check(m.carry_mode, carry_label + " carry mode active")
	mouse(true)
	for frame in range(75):
		if not torn.is_empty():
			break
		await process_frame
	mouse(false)
	await process_frame
	await process_frame
	check(torn.size() == 1, carry_label + " carry tear completed")
	check(m.stomach.fill == 0, carry_label + " stomach fill 0 in carry mode")
	check(is_equal_approx(m.carried_flesh, m.stomach_config.flesh_per_cell), carry_label + " carried flesh matches flesh_per_cell")
	check(not m.chewer.is_chewing(), carry_label + " chewer stopped after release")
	m.toggle_carry()

	# --- 4. Consecutive held LMB 2-tear test (FORWARD, reachable) ---
	var repeat_label := "consecutive_held_lmb"
	await fixture_solid(Vector3.FORWARD)
	mouse(true)
	for frame in range(140):
		if torn.size() >= 2:
			break
		await process_frame
	mouse(false)
	await process_frame
	await process_frame

	check(torn.size() >= 2, repeat_label + " held LMB produces at least 2 consecutive tears")
	check(m.excavated_cells == torn.size(), repeat_label + " excavated cells matches tear count")
	check(is_equal_approx(m.stomach.fill, torn.size() * m.stomach_config.flesh_per_cell), repeat_label + " stomach fill matches 2 tears")
	for p in torn:
		check(m.terrain.density_at(p) < m.terrain_config.iso_level, repeat_label + " torn cell is empty " + str(p))
	check(not m.chewer.is_chewing(), repeat_label + " chewer stopped on release")
	check(m.hazard.health > 0 and m.deaths == 0, repeat_label + " player survived consecutive tears")

	# --- 5. Downward reach boundary case (radius 1.2 -> second surface > 2.5m -> 1 tear stop) ---
	var down_reach_label := "down_reach_boundary"
	mouse(false)
	m._crush_t = 0.0
	await create_timer(0.2).timeout
	m.terrain.fill_box_uniform(AABB(center - Vector3.ONE * 3, Vector3.ONE * 6), 1.0, 0)
	m.terrain.carve_sphere(center, 1.2)
	m.terrain.carve_sphere(center - Vector3.UP * 0.7, 1.2)
	m.terrain.remesh_all()
	m.player.global_position = center - Vector3.UP * m.player.eye_pivot_y(false)
	m.player.velocity = Vector3.ZERO
	m.stomach.fill = 0
	m.carried_flesh = 0
	m.excavated_cells = 0
	m._crush_t = 0.0
	m.hazard.health = 100
	m.carry_mode = false
	aim(Vector3.DOWN)
	await physics_frame
	await physics_frame
	await process_frame
	torn.clear()
	await support_fixed_down_reach()
	var supported_before: Vector3 = m.player.global_position

	mouse(true)
	await create_timer(2.05).timeout
	mouse(false)
	await process_frame
	await process_frame

	check(m.player.global_position.distance_to(supported_before) < 0.02, "reach fixture normal physics preserves actual distance")
	check(torn.size() == 1, down_reach_label + " wide downward floor stops after only reachable tear")
	check(m.excavated_cells == 1, down_reach_label + " excavated_cells == 1")
	check(is_equal_approx(m.stomach.fill, m.stomach_config.flesh_per_cell), down_reach_label + " no food for out-of-reach surface")
	var look_r: Array = m.player.get_look_ray()
	var beyond: Dictionary = m._published_terrain_contact(look_r[0], look_r[1], m.progression.reach() + m.terrain_config.cell_size)
	check(not beyond.is_empty() and look_r[0].distance_to(beyond.position) > m.progression.reach(), down_reach_label + " next downward surface is beyond reach")
	check(m._look_hit().is_empty() and not m.chewer.is_chewing(), down_reach_label + " chewer cleanly stopped at reach boundary")

	# --- 6. Downward reachable consecutive case (radius 1.0 -> 2 reachable cells -> 2 tears) ---
	var down_repeat_label := "down_reachable_consecutive"
	mouse(false)
	if is_instance_valid(fixed_down_support): fixed_down_support.queue_free()
	m._crush_t = 0.0
	await create_timer(0.2).timeout
	m.terrain.fill_box_uniform(AABB(center - Vector3.ONE * 3, Vector3.ONE * 6), 1.0, 0)
	m.terrain.carve_sphere(center, 1.0)
	m.terrain.carve_sphere(center - Vector3.UP * 0.7, 1.0)
	m.terrain.remesh_all()
	m.player.global_position = center - Vector3.UP * m.player.eye_pivot_y(false)
	m.player.velocity = Vector3.ZERO
	m.stomach.fill = 0
	m.carried_flesh = 0
	m.excavated_cells = 0
	m._crush_t = 0.0
	m.hazard.health = 100
	m.carry_mode = false
	aim(Vector3.DOWN)
	await physics_frame
	await physics_frame
	await process_frame
	torn.clear()

	mouse(true)
	for frame in range(140):
		if torn.size() >= 2:
			break
		await process_frame
	mouse(false)
	await process_frame
	await process_frame

	check(torn.size() >= 2, down_repeat_label + " reachable downward fixture produces 2 consecutive tears")
	check(m.excavated_cells == torn.size(), down_repeat_label + " excavated cells matches tear count")
	check(is_equal_approx(m.stomach.fill, torn.size() * m.stomach_config.flesh_per_cell), down_repeat_label + " stomach fill matches 2 tears")
	check(not m.chewer.is_chewing(), down_repeat_label + " chewer stopped after release")

	# Summary
	print("%d passed, %d failed" % [passed, failed])
	m.queue_free()
	await process_frame
	quit(1 if failed else 0)

func support_fixed_down_reach() -> void:
	# Initial physical fixture for the unchanged 2.5m reach boundary. The
	# approved idle head bow changes eye height; use an absolute initial
	# pose so prior unsupported physics frames cannot shorten the boundary.
	# A real support beside the feet keeps physics active and leaves the
	# down aim ray unobstructed. Separate radius1.0 cases remain unsupported.
	m.player.global_position = center - Vector3.UP * m.player.eye_pivot_y(false) + Vector3.UP * 0.3
	fixed_down_support = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 0.1, 0.2)
	shape.shape = box
	fixed_down_support.add_child(shape)
	m.add_child(fixed_down_support)
	fixed_down_support.global_position = m.player.get_feet_position() + Vector3(0.25, -0.05, 0)
	await physics_frame
	await physics_frame
	await process_frame
	var rr: Array = m.player.get_look_ray()
	var hit: Dictionary = ray(rr[0], rr[1], m.progression.reach() + 1.0)
	check(m.player.is_on_floor(), "reach fixture actual support grounds normal physics")
	check(not hit.is_empty() and hit.collider != fixed_down_support, "reach fixture support does not occlude actual flesh ray")
