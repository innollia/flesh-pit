extends SceneTree
var m: Node3D
var passed := 0
var failed := 0
var torn := 0
const CENTER := Vector3(8, 5, 8)
func _init() -> void:
	Engine.max_fps = 60
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL: ", label)
func frames(count: int) -> void:
	for i in range(count): await physics_frame
	await process_frame
func key(action: String, down: bool) -> void:
	if down: Input.action_press(action)
	else: Input.action_release(action)
func mouse(down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	Input.parse_input_event(ev)
func place() -> void:
	m.player.global_position = CENTER
	m.player.velocity = Vector3.ZERO
	m._crush_t = 0.0
	m.hazard.health = 100
func run() -> void:
	assert(OS.get_user_data_dir().contains("restoration"))
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://movement-boundary-test.bin"
	root.add_child(m)
	await create_timer(0.1).timeout
	m.finish_opening()
	m.chewer.cell_torn.connect(func(_p): torn += 1)
	m.terrain.fill_box_uniform(AABB(CENTER - Vector3.ONE * 3, Vector3.ONE * 6), 1.0, 0)
	m.terrain.remesh_all()
	place()
	await frames(30)
	check(m.player.global_position.distance_to(CENTER) < 0.005, "full solid capsule stays stationary without surface collider")
	check(m.hazard.health > 0, "short boxed interval preserves living player")
	for action in ["fdk_move_forward", "fdk_move_back", "fdk_move_left", "fdk_move_right", "fdk_jump"]:
		place()
		key(action, true)
		await frames(8)
		key(action, false)
		check(m.player.global_position.distance_to(CENTER) < 0.005, "boxed input cannot cross solid: " + action)
	place()
	key("fdk_crouch", true)
	mouse(true)
	await frames(8)
	check(m.player.global_position.distance_to(CENTER) < 0.005, "Ctrl eat cannot descend before actual removal")
	mouse(false)
	key("fdk_crouch", false)
	await frames(2)
	place()
	m.equip_tool("")
	m.carry_mode = false
	m.player._yaw = 0.0
	m.player._pitch = 0.0
	mouse(true)
	for i in range(110):
		await frames(1)
		if torn > 0: break
	mouse(false)
	print("TEAR_STATE physics=",m.player.is_physics_processing()," seated=",m._seated," settle=",m._settling," ended=",m.ended," deaths=",m.deaths," opening=",m.is_opening()," torn=", torn, " stomach=", m.stomach.fill, " pos=",m.player.global_position," hit=",m._look_hit()," chew=",m.chewer.is_chewing())
	check(torn > 0 and m.stomach.fill > 0, "real normal Main LMB completes first tear while boxed")
	check(m.hazard.health > 0 and m.deaths == 0, "first tear precedes crush death")
	# A real empty region has no fake collider: preserve old constant descent.
	m.terrain.fill_box_uniform(AABB(CENTER - Vector3.ONE * 3, Vector3.ONE * 6), 0.0, 0)
	m.terrain.remesh_all()
	place()
	await frames(12)
	var fall: float = CENTER.y - m.player.global_position.y
	print("FALL ", fall, " vel=",m.player.velocity," physics=",m.player.is_physics_processing())
	check(fall > 0.35 and fall < 0.65, "unsupported real empty space keeps 2.5m/s descent")
	place()
	key("fdk_crouch", true)
	mouse(true)
	await frames(12)
	mouse(false)
	key("fdk_crouch", false)
	check(CENTER.y - m.player.global_position.y > 0.35, "Ctrl eat descends through real empty feet space")
	# Ordinary physics can slide after the terrain boundary rejects one axis.
	m.terrain.fill_box_uniform(AABB(CENTER - Vector3.ONE * 3, Vector3.ONE * 6), 1.0, 0)
	m.terrain.carve_sphere(CENTER, 1.6)
	m.terrain.remesh_all()
	place()
	var forward := m._filter_terrain_motion(Vector3(0, 0, 0.04)) as Vector3
	check(forward.z > 0.039, "empty full capsule accepts ordinary movement")
	var far := m._filter_terrain_motion(Vector3(0, 0, 1.5)) as Vector3
	check(far.z > 0.0 and far.z < 1.5, "actual swept capsule rejects wall before centre reaches it")
	m.terrain.fill_box_uniform(AABB(CENTER - Vector3.ONE * 3, Vector3.ONE * 6), 0.0, 0)
	m.terrain.fill_box_uniform(AABB(CENTER - Vector3.ONE * 3, Vector3(6, 2, 6)), 1.0, 0)
	m.terrain.remesh_all()
	place()
	m.player.global_position.y = 5.5
	await frames(30)
	print("TERRAIN_FLOOR body=",m.player.global_position," feet=",m.player.get_feet_position()," floor=",m.player.is_on_floor())
	check(m.player.is_on_floor(), "actual terrain floor keeps ordinary grounded contact")
	# A low passage is actual floor and ceiling geometry, not a fake obstacle.
	m.terrain.fill_box_uniform(AABB(Vector3(5, 5.5, 5), Vector3(6, 2.5, 6)), 1.0, 0)
	m.terrain.remesh_all()
	key("fdk_crouch", true)
	await frames(2)
	var start: Vector3 = m.player.global_position
	key("fdk_move_forward", true)
	await frames(12)
	key("fdk_move_forward", false)
	check(m.player.is_on_floor() and m.player._bob_weight > 0.0, "real terrain walk retains grounded footstep camera bob")
	check(m.player.global_position.distance_to(start) > 0.15, "normal crouched capsule moves through real low passage")
	key("fdk_crouch", false)
	await frames(2)
	check(m.player._is_crouching, "actual low ceiling blocks standing expansion")
	var times: Array[int] = []
	var corners := 0
	for i in range(20):
		m._filter_terrain_motion(Vector3(0.02, -0.03, 0.02))
		times.append(m._body_clearance.last_motion_us)
		corners = maxi(corners, m._body_clearance.last_motion_corner_reads)
	times.sort()
	print("Movement filter median_us=", times[10], " max_us=", times[19], " corners=", corners)
	check(corners <= 1000, "per-frame terrain snapshot has bounded local corner count")
	check(times[10] < 20000, "headless local movement median remains under 20ms")
	# Current growth intrusion uses Main's normal relief writer alongside the
	# movement filter; a short verified escape must not become a deadlock.
	var old_field: Node = m.terrain
	var field := FDKTerrainField.new()
	field.config = FDKTerrainConfig.new()
	field.config.chunk_size = 8
	field.config.facet_jitter = 0.0
	var pocket_center := Vector3(8.25, 5.25, 8.25)
	var pocket := AABB(pocket_center-Vector3(0.4,1.05,0.9),Vector3(0.8,2.1,1.3))
	field.density_sampler = func(p: Vector3): return 0.0 if pocket.has_point(p) else 1.0
	field.tissue_sampler = func(_p): return 0
	root.add_child(field)
	field.generate_region(AABB(pocket_center-Vector3.ONE*3,Vector3.ONE*6))
	field.remesh_all()
	m.terrain = field
	m.chewer.terrain = field
	old_field.queue_free()
	await frames(2)
	m.player.global_position = pocket_center+Vector3.FORWARD*0.17
	m.player.velocity = Vector3.ZERO
	for x in range(15,19):
		for y in range(8,14): field._add_corner_global(Vector3i(x,y,15),1.0)
	var intrusion: Dictionary = m._body_clearance.assess(m.player,field,Vector3.BACK)
	print("SHORT_ESCAPE initial=",intrusion," crouch=",m.player._is_crouching)
	check(intrusion.overlap and not intrusion.trapped, "unpublished real intrusion retains short full capsule escape")
	var prior: Vector3 = m.player.global_position
	await frames(20)
	var relieved: Dictionary = m._body_clearance.assess(m.player,field)
	check(not relieved.overlap and not relieved.trapped, "normal Main relief and movement filter clear short intrusion together")
	check(m.player.global_position.z > prior.z and m.player.global_position.distance_to(prior)<0.25, "short escape remains bounded physical retreat")
	await diagonal_pending_case()
	print("Movement boundary: ", passed, " passed, ", failed, " failed")
	m.queue_free()
	await process_frame
	quit(1 if failed else 0)

func diagonal_pending_case() -> void:
	var old_field: Node = m.terrain
	var field := FDKTerrainField.new()
	field.config = FDKTerrainConfig.new()
	field.config.chunk_size = 8
	field.config.facet_jitter = 0.0
	field.density_sampler = func(_p): return 0.0
	field.tissue_sampler = func(_p): return 0
	root.add_child(field)
	field.generate_region(AABB(Vector3(6,2,6),Vector3(6,6,6)))
	field.remesh_all()
	m.terrain = field
	m.chewer.terrain = field
	old_field.queue_free()
	# Let the normal crouch-release use the new open ceiling first.
	m.player.global_position = Vector3(8,5,8)
	await frames(2)
	m.player.global_position = Vector3(8,5,8)
	m.player.velocity = Vector3.ZERO
	for y in range(7,14): field._add_corner_global(Vector3i(18,y,18),1.0)
	var desired := Vector3(2,0,2)
	check(not m.player.test_move(m.player.global_transform,desired), "pending diagonal corner has no published physics collider yet")
	var permitted: Vector3 = m._filter_terrain_motion(desired)
	var shape := m.player.collision_shape.shape as CapsuleShape3D
	check(not m.player._is_crouching and is_equal_approx(shape.height,m.player.config.stand_height), "diagonal fixture uses the actual configured standing capsule")
	var xf: Transform3D = m.player.collision_shape.global_transform
	var half_axis: float = shape.height*0.5-shape.radius
	var a: Vector3 = xf.origin-Vector3.UP*half_axis
	var b: Vector3 = xf.origin+Vector3.UP*half_axis
	var straight_clear: bool = m._body_clearance._sweep_clear(a,b,permitted,shape.radius-0.002)
	print("DIAGONAL requested=",desired," permitted=",permitted," actual_straight_clear=",straight_clear)
	check(not m._body_clearance._sweep_clear(a,b,desired,shape.radius-0.002), "actual current capsule diagonal intersects the pending corner")
	check(straight_clear, "returned motion validates the same straight capsule sweep used by normal physics")
	check(permitted.length()>0.1, "blocked diagonal retains a verified ordinary axis slide")
	# A fast configured player makes the disputed sweep observable in one
	# real physics tick. It still uses normal Main and move_and_slide; the
	# capsule is the unchanged configured standing body, not a point probe.
	var old_speed: float = m.player.config.walk_speed
	m.player.config.walk_speed = 170.0
	m.player._yaw = 0.0
	m.player.rotation.y = 0.0
	var prior: Vector3 = m.player.global_position
	key("fdk_move_back",true)
	key("fdk_move_right",true)
	await physics_frame
	await physics_frame
	key("fdk_move_back",false)
	key("fdk_move_right",false)
	m.player.config.walk_speed = old_speed
	var actual: Vector3 = m.player.global_position-prior
	# Both real tick motion and the returned callback motion have one safe
	# physical route; no centre-only / endpoint-only evidence substitutes it.
	print("DIAGONAL normal physics actual=",actual)
	check(actual.length()>0.1, "normal Main physics makes progress after diagonal rejection")
	check(m._body_clearance._sweep_clear(a,b,actual,shape.radius-0.002) and not m._body_clearance._touches_surface(a+actual,b+actual,shape.radius-0.002), "normal Main diagonal result keeps the whole capsule outside actual corner")
