extends SceneTree

## --baseline runs the same required outcomes against the original Main
## six-point test. Ordinary runs require the new full capsule component.
var passed := 0
var failed := 0
var baseline := false
var m: Node3D
var actor: FDKFirstPersonController
var field: FDKTerrainField
var clearance: RefCounted
var center := Vector3(24.25, 8.25, 24.25)

func _init() -> void:
	Engine.max_fps = 60
	baseline = "--baseline" in OS.get_cmdline_user_args()
	print("=== T8 actual capsule / crush", " BASELINE RED" if baseline else "", " ===")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(n: int = 2) -> void:
	for i in range(n): await physics_frame
	await process_frame

func fixture(boxes: Array[AABB], restorable: bool = false) -> void:
	if is_instance_valid(field):
		field.queue_free()
		await frames()
	field = FDKTerrainField.new()
	field.config = FDKTerrainConfig.new()
	field.config.chunk_size = 8
	field.config.facet_jitter = 0.0
	field.density_sampler = func(p: Vector3):
		if restorable: return 1.0
		for box in boxes:
			if box.has_point(p): return 0.0
		return 1.0
	field.tissue_sampler = func(_p): return 0
	root.add_child(field)
	field.generate_region(AABB(center - Vector3.ONE * 3, Vector3.ONE * 6))
	if restorable:
		for x in range(42,56):
			for y in range(10,24):
				for z in range(42,56):
					for box in boxes:
						if box.has_point(Vector3(x,y,z) * field.config.cell_size):
							field._add_corner_global(Vector3i(x,y,z), -1.0)
							break
	field.remesh_all()
	actor.global_position = center
	actor.velocity = Vector3.ZERO
	m.terrain = field
	await frames(3)

func room() -> AABB:
	return AABB(center - Vector3(0.4, 1.05, 0.4), Vector3(0.8, 2.1, 0.8))

func trapped() -> bool:
	if baseline: return m.is_trapped()
	return bool(clearance.assess(actor, field).trapped)

func run() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://t8_crush_component_test.bin"
	root.add_child(m)
	await frames(6)
	m.finish_opening()
	m.process_mode = Node.PROCESS_MODE_DISABLED
	actor = load("res://addons/flesh_dig_kit/player/fdk_first_person_controller.tscn").instantiate()
	actor.mouse_look_enabled = false
	root.add_child(actor)
	actor.set_physics_process(false)
	m.player = actor
	if not baseline:
		clearance = load("res://main/scripts/fp_body_clearance.gd").new()
	# Only the back is roomy enough for the full capsule; all old probe
	# points remain solid. This is actual meshed/physics terrain, no mock.
	await fixture([AABB(center - Vector3(0.4, 1.05, 0.4), Vector3(0.8, 2.1, 1.3))])
	check(not actor.test_move(actor.global_transform, Vector3.BACK * 0.35), "real capsule can move into the back pocket")
	check(not trapped(), "back pocket prevents false crushing despite six solid distant points")
	if not baseline:
		actor.set_physics_process(true)
		Input.action_press("fdk_move_back")
		await frames(6)
		Input.action_release("fdk_move_back")
		actor.set_physics_process(false)
		check(actor.global_position.z > center.z + 0.1, "normal controller input actually retreats into the pocket")
	# Isolated 0.5m cell at the old back probe: it cannot fit a standing
	# capsule and a solid wall separates it from the player's chamber.
	await fixture([room(), AABB(Vector3(24.0, 8.0, 25.5), Vector3(0.51, 0.51, 0.51))])
	# The local chamber must actually pinch the current capsule. A normal
	# 0.7m body in this 1m chamber still has a short, legitimate local path.
	(actor.collision_shape.shape as CapsuleShape3D).radius = 0.46
	check(field.density_at(center + Vector3.BACK * 1.25) == 0.0, "old point probe sees the small isolated empty cell")
	check(trapped(), "one empty point behind a wall is not a full-body escape")
	(actor.collision_shape.shape as CapsuleShape3D).radius = 0.35
	if not baseline:
		await extra_checks()
	print("--- %d passed, %d failed ---" % [passed, failed])
	if is_instance_valid(field): field.queue_free()
	actor.queue_free()
	m.queue_free()
	await process_frame
	quit(1 if failed > 0 else 0)

func extra_checks() -> void:
	await fixture([AABB(center - Vector3(0.4,1.05,0.9), Vector3(0.8,2.1,1.3))])
	actor.global_position = center + Vector3.FORWARD * 0.17
	await frames(2)
	for x in range(47,51):
		for y in range(14,20): field._add_corner_global(Vector3i(x,y,47), 1.0)
	var shallow: Dictionary = clearance.assess(actor, field, Vector3.BACK)
	print("T8 changing surface intrusion assess_us=", clearance.last_assess_us, " corner_reads=", clearance.last_corner_reads, " direction_queries=", clearance.last_direction_queries)
	check(shallow.overlap, "shallow pocket starts with actual capsule surface intrusion")
	check(actor.test_move(actor.global_transform, Vector3.BACK * 0.35), "long endpoint collides with the far wall of the shallow pocket")
	check(not actor.test_move(actor.global_transform, Vector3.BACK * 0.12), "short retreat passes normal full capsule motion")
	check(not shallow.trapped, "short full capsule retreat prevents false crush")
	if not shallow.trapped:
		var before := actor.global_position
		for i in range(16):
			await physics_frame
			var fresh: Dictionary = clearance.assess(actor, field, Vector3.BACK)
			if not fresh.overlap: break
			clearance.relieve(actor, fresh, 1.0 / 60.0)
		var after: Dictionary = clearance.assess(actor, field)
		check(not after.overlap, "normal move_and_collide relief removes the shallow intrusion")
		check(not actor.test_move(actor.global_transform, Vector3.BACK * 0.1), "short physical motion remains possible after intrusion relief")
		check(not after.trapped, "relieved capsule does not immediately resume false crush")
		check(actor.global_position.z > before.z and actor.global_position.distance_to(before) < 0.14, "relief is bounded physical retreat rather than relocation")
	for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.DOWN]:
		var low := center - Vector3(0.4, 1.05, 0.4)
		var size := Vector3(0.8, 2.1, 0.8)
		if direction == Vector3.LEFT:
			low.x -= 0.5
			size.x += 0.5
		elif direction == Vector3.RIGHT: size.x += 0.5
		else:
			low.y -= 0.5
			size.y += 0.5
		await fixture([AABB(low, size)])
		check(not actor.test_move(actor.global_transform, direction * 0.35), "actual capsule path " + str(direction))
		check(not trapped(), "full body escape " + str(direction))
	# Same pose and same dig epoch: contraction/current corner writes must
	# invalidate surface reuse before a new physics mesh is published.
	await fixture([AABB(center - Vector3(0.4, 1.05, 0.4), Vector3(0.8, 2.1, 1.3))])
	(actor.collision_shape.shape as CapsuleShape3D).radius = 0.46
	check(not trapped(), "fresh open pocket")
	var rebuilds: int = clearance.surface_rebuilds
	check(not trapped() and clearance.surface_rebuilds == rebuilds, "unchanged surface reused, verdict still queried")
	var epoch: int = field.get_dig_epoch()
	for x in range(47, 51):
		for y in range(14, 20):
			for z in range(50, 53): field._add_corner_global(Vector3i(x,y,z), 1.0)
	check(field.get_dig_epoch() == epoch, "growth does not require a dig epoch")
	check(trapped() and clearance.surface_rebuilds > rebuilds, "unpublished growth closes the current capsule path immediately")
	print("T8 changing surface boxed assess_us=", clearance.last_assess_us, " corner_reads=", clearance.last_corner_reads, " direction_queries=", clearance.last_direction_queries)
	field.remesh_all()
	await frames(3)
	check(trapped(), "published closure agrees with current surface")
	var boxed_costs: Array[int] = []
	for i in range(4):
		clearance.assess(actor, field)
		boxed_costs.append(clearance.last_assess_us)
	print("T8 cached boxed assess_us=", boxed_costs, " corner_reads=", clearance.last_corner_reads, " direction_queries=", clearance.last_direction_queries)
	for x in range(47, 51):
		for y in range(14, 20):
			for z in range(50, 53):
				var p := Vector3(x,y,z) * field.config.cell_size
				if AABB(center - Vector3(0.4,1.05,0.4), Vector3(0.8,2.1,1.3)).has_point(p): field._add_corner_global(Vector3i(x,y,z), -1.0)
	check(trapped(), "unpublished reopening cannot ignore the still published solid collision")
	field.remesh_all()
	await frames(3)
	check(not trapped(), "published reopening restores the capsule escape")
	(actor.collision_shape.shape as CapsuleShape3D).radius = 0.35
	check(clearance.last_direction_queries <= 20, "direction query bound")
	var costs: Array[int] = []
	for i in range(12):
		clearance.assess(actor, field)
		costs.append(clearance.last_assess_us)
	costs.sort()
	print("T8 cached open assess median_us=", costs[6], " max_us=", costs[11], " corner_reads=", clearance.last_corner_reads, " direction_queries=", clearance.last_direction_queries)
	var pocket := AABB(center - Vector3(0.4,1.05,0.4), Vector3(0.8,2.1,1.3))
	await fixture([pocket], true)
	check(not trapped(), "restorable dug pocket starts open")
	var regen_epoch: int = field.get_dig_epoch()
	field.regenerate_all(1000.0, center + Vector3.ONE * 100, 0.0)
	check(trapped() and field.get_dig_epoch() == regen_epoch, "actual regeneration invalidates escape without a dig epoch")
	await fixture([pocket], true)
	check(not trapped(), "second restorable pocket starts open")
	var contract_epoch: int = field.get_dig_epoch()
	field.contract_sphere(center, 3.0, 1.0)
	check(trapped() and field.get_dig_epoch() == contract_epoch, "actual contraction invalidates escape without a dig epoch")
	# A genuinely low side passage fits the current crouched capsule only.
	await fixture([room(), AABB(center + Vector3(0.0,-1.05,-0.4), Vector3(1.3,1.1,0.8))])
	check(actor.test_move(actor.global_transform, Vector3.RIGHT * 0.35), "standing capsule cannot enter the low side passage")
	Input.action_press("fdk_crouch")
	actor.set_physics_process(true)
	await frames(2)
	actor.set_physics_process(false)
	check(is_equal_approx((actor.collision_shape.shape as CapsuleShape3D).height, actor.config.crouch_height), "real controller installed crouched capsule")
	check(not trapped(), "actual crouched capsule offset fits low side passage")
	Input.action_press("fdk_move_right")
	actor.set_physics_process(true)
	await frames(6)
	actor.set_physics_process(false)
	Input.action_release("fdk_move_right")
	check(actor.global_position.x > center.x + 0.1, "normal crouched movement enters the low passage")
	Input.action_release("fdk_crouch")
	var danger = load("res://main/scripts/fp_danger_show.gd").new()
	danger.setup(m)
	var cam := actor.camera
	var pose := cam.global_transform
	cam.h_offset = 0.02
	cam.v_offset = -0.03
	m._crush_t = m.progression.crush_time()
	danger.tick(0.1)
	check(is_equal_approx(cam.fov, 75.0 * 0.78), "crush narrows live base FOV by 22 percent")
	check(is_equal_approx(cam.h_offset, 0.02 + sin(3.1) * 0.006), "31Hz shake adds to existing horizontal offset")
	check(is_equal_approx(cam.v_offset, -0.03 + sin(3.6) * 0.005), "23Hz shake adds to existing vertical offset")
	var applied := Vector2(cam.h_offset, cam.v_offset)
	danger.apply_camera()
	check(applied.is_equal_approx(Vector2(cam.h_offset, cam.v_offset)), "predraw reapplication is idempotent")
	check(cam.global_transform.is_equal_approx(pose), "danger preserves head and captured vomit camera transform")
	m.progression.tumor_mutations.append("T5")
	m.mutation_apply.apply_now()
	danger.apply_camera()
	var live: float = minf(170.0, 75.0 * m.progression.fov() / FPProgression.BASE_FOV)
	check(is_equal_approx(cam.fov, live * 0.78), "late mutation FOV write recomposes against live T5 base")
	m._crush_t = 0.0
	danger.apply_camera()
	check(is_equal_approx(cam.fov, live), "escape releases squeeze to live mutation FOV")
	check(Vector2(cam.h_offset, cam.v_offset).is_equal_approx(Vector2(0.02,-0.03)), "escape removes owned shake only")
	danger.restore_camera()
	cam.fov = 66.0
	danger.apply_camera()
	check(is_equal_approx(cam.fov, 66.0), "zero crush preserves a hand pose's 66 degree FOV")
	m._crush_t = m.progression.crush_time()
	danger.apply_camera()
	check(is_equal_approx(cam.fov, 66.0 * 0.78), "crush composes against hand pose FOV rather than forcing 75")
	m._crush_t = 0.0
	danger.apply_camera()
	check(is_equal_approx(cam.fov, 66.0), "escape restores hand pose FOV")
	var settle_pose: Transform3D = m.settle_camera.transform
	var settle_fov: float = m.settle_camera.fov
	danger.tick(0.1)
	check(m.settle_camera.transform.is_equal_approx(settle_pose) and is_equal_approx(m.settle_camera.fov, settle_fov), "settlement camera remains under its existing hand pose writer")
