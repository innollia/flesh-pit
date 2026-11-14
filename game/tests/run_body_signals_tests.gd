extends SceneTree

## Body signals: a bite never stops without the body saying why, and the
## stomach's end holds for every way flesh goes down.
## - the stomach gauge's vomit key shows only where vomiting settles
## - a full stomach refuses with its own signal (kit FDKChewer.refused_full,
##   game Main.stomach_refused, rationed), a lurch of the stomach mass and a
##   dip of the head; nothing is dug, nothing goes down
## - the M22 alien hand, the big saw's extra cells and the M07/M14 extra cells
##   tear nothing into a full stomach (eaten flesh = removed density)
## - flesh past the arm: the hands stretch at it with open fingers, and the
##   ring offers the key that digs up or down
## - a swallow kicks the stomach mass SWALLOW_DELAY after its tear
## - an overfull tear's jolt is longer; a crush presses the resting hands
## - the additions to the hands rig leave its poses alone at zero
## Real Main and real doorway flesh; save and key files are this suite's own.

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	Engine.max_fps = 60
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_body_signals.json"
	m.save_path = "user://capture-body-signals-tests.bin"
	root.add_child(m)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func aim(yaw: float, pitch: float) -> void:
	m.player.rotation.y = PI + yaw
	m.player.camera_pivot.rotation.x = pitch
	m.player.force_update_transform()

func full() -> float:
	return m.stomach_config.capacity + m.stomach_config.overfill_capacity

func pose_of(rig: FDKHandsRig, i: int) -> Dictionary:
	return rig._pose_for(rig._hands[i], 0.0)

func same_pose(a: Dictionary, b: Dictionary) -> bool:
	for k in a.keys():
		if a[k] is Vector3:
			if not (a[k] as Vector3).is_equal_approx(b[k]):
				return false
		elif not is_equal_approx(float(a[k]), float(b[k])):
			return false
	return true

func run() -> void:
	await frames(5)
	m.finish_opening()
	m.restroom.set_door_open(true, true)
	m.player.global_position = Vector3(0.0, 0.95, 0.2)
	aim(0.0, 0.0)
	await frames(30)
	var prog: FPProgression = m.progression
	var ma = m.mutation_apply
	var iso: float = m.terrain_config.iso_level
	# the doorway flesh straight ahead, and the spot that puts it in reach
	var ray: Array = m.player.get_look_ray()
	var q := PhysicsRayQueryParameters3D.create(ray[0], ray[0] + ray[1] * 12.0)
	q.exclude = [m.player.get_rid()]
	var wall: Dictionary = m.player.get_world_3d().direct_space_state.intersect_ray(q)
	check(not wall.is_empty() and wall.collider.has_meta("fdk_terrain_chunk"), "fixture: flesh straight ahead through the open door")
	if wall.is_empty():
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return
	var wall_z: float = wall.position.z
	var near := Vector3(0.0, 0.95, wall_z - 1.2)
	var far := Vector3(0.0, 0.95, wall_z - prog.reach() - 0.25)
	var doorway := Vector3(0.0, 0.6, 4.0) # out in the flesh, as run_mutation_tests stands for M22
	print("fixture wall_z=%.2f near_in_room=%s doorway_in_room=%s" % [wall_z, m.restroom.contains(near), m.restroom.contains(doorway)])

	# --- 1. the vomit key by the gauge: only where vomiting settles
	var hud: FPStomachHUD = m.stomach_hud
	m.stomach.fill = m.stomach_config.capacity * 1.2
	m.player.global_position = near
	await frames(3)
	check(not m._near_toilet() and m._near_rest_point() < 0, "fixture: by the door is no settle spot")
	check(not m.at_settle_spot and not hud.shows_vomit_key(), "overfull away from the toilet: no vomit key by the gauge")
	check(not m.vomit_button.shown and not m.opening_view.hints.vomit_hint, "and no mouth or onboarding vomit key either")
	m.player.global_position = m.restroom.toilet.to_global(Vector3(0, 0.9, 0.5))
	await frames(3)
	check(m.at_settle_spot and hud.shows_vomit_key(), "overfull at the toilet: the vomit key shows")
	m.stomach.fill = m.stomach_config.capacity * 0.5
	check(not hud.shows_vomit_key(), "under capacity the gauge shows no key even at the toilet")

	# --- 2. a full stomach refuses out loud, and takes nothing
	m.player.global_position = near
	aim(0.0, 0.0)
	await frames(3)
	var hit: Dictionary = m._look_hit()
	check(not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk"), "fixture: flesh in reach")
	var target: Vector3 = hit.position + m.player.get_look_ray()[1] * m.terrain_config.cell_size * 0.5
	var sum0: float = m.terrain.cell_corner_sum(target)
	m.stomach.fill = full()
	var kit_refusals := [0]
	var told: Array = []
	m.chewer.refused_full.connect(func(_p): kit_refusals[0] += 1)
	m.stomach_refused.connect(func(p: Vector3): told.append(p))
	var t := 0.0
	var first_press := 0.0
	var lurch := 0.0
	var dip := 0.0
	var gauge := 1.0
	while t < 0.5:
		await process_frame
		m._chew_step(1.0 / 60.0)
		if t == 0.0:
			lurch = m.stomach_view.heave_amount()
			dip = m.danger_show.heave_amount() if m.danger_show != null else 0.0
			gauge = hud.gulp_amount()
		first_press = maxf(first_press, m._full_press_t)
		t += root.get_process_delta_time()
	check(kit_refusals[0] >= 10, "the chewer reports every refused frame (%d)" % kit_refusals[0])
	check(told.size() == 1, "the game tells the refusal once, not every frame (%d)" % told.size())
	if not told.is_empty():
		check((told[0] as Vector3).distance_to(hit.position) < 0.3, "the refusal names the contact on the wall")
	check(not m.chewer.is_chewing(), "nothing is being chewed")
	check(is_equal_approx(m.stomach.fill, full()), "nothing went down")
	check(is_equal_approx(m.terrain.cell_corner_sum(target), sum0), "nothing was dug")
	check(lurch > 0.9 and first_press > 0.0, "the stomach mass lurches and the wall is gripped (%.2f, %.2f)" % [lurch, first_press])
	check(m.danger_show == null or dip > 0.9, "the head dips (%.2f)" % dip)
	check(gauge == 0.0, "the gauge's end does not bulge for a refusal: that bulge means a swallow (%.2f)" % gauge)
	check(m.hands_rig.state != FDKHandsRig.HandState.SLIP, "it is not the blade refusal's slip")
	while t < 1.3:
		await process_frame
		m._chew_step(1.0 / 60.0)
		t += root.get_process_delta_time()
	check(told.size() == 2, "held, it comes again after %.1f s (%d)" % [m.FULL_REFUSE_EVERY, told.size()])
	await frames(40)
	check(m.stomach_view.heave_amount() == 0.0, "the lurch passes")
	# carrying hands that hold all they can refuse the same way, on their own signal
	var carry_told := [0]
	m.carry_refused.connect(func(_p): carry_told[0] += 1)
	m.stomach.fill = 0.0
	m.carry_mode = true
	m.carried_flesh = prog.carry_capacity()
	for i in range(5):
		await process_frame
		m._chew_step(1.0 / 60.0)
	check(carry_told[0] == 1 and told.size() == 2, "full hands tell carry_refused, not the stomach's signal")
	check(is_equal_approx(m.terrain.cell_corner_sum(target), sum0) and is_equal_approx(m.carried_flesh, prog.carry_capacity()), "and take nothing")
	m.carry_mode = false
	m.carried_flesh = 0.0
	m.chewer.stop()

	# --- 3. the stomach's end holds for the extra ways flesh goes down
	prog.mutation_tree._purchased["M22"] = true
	m.player.global_position = doorway
	m.player.velocity = Vector3.ZERO
	check(not m.restroom.contains(doorway), "fixture: standing outside the restroom (M22 works there)")
	var at: Vector3 = ma._alien_target()
	check(at != Vector3.INF, "fixture: a cell for the alien hand")
	m.stomach.fill = full()
	var sum_alien: float = m.terrain.cell_corner_sum(m.cell_center(at))
	var tears0: int = ma.alien_tears
	check(not ma.alien_tear(), "M22 full: the alien hand tears nothing")
	var reached := 0.0
	for i in range(25):
		ma.step_timed(0.1)
		reached = maxf(reached, ma.alien_reach)
	check(ma.alien_tears == tears0 and reached == 0.0, "M22 full: standing still it neither reaches nor tears")
	check(is_equal_approx(m.terrain.cell_corner_sum(m.cell_center(at)), sum_alien) and is_equal_approx(m.stomach.fill, full()), "M22 full: density and stomach unchanged")
	m.stomach.fill = full() - 1.0
	for i in range(25):
		ma.step_timed(0.1)
	check(ma.alien_tears == tears0 + 1 and m.stomach.fill > full() - 1.0, "M22 with room left, the same wait tears and eats (%d)" % (ma.alien_tears - tears0))
	prog.mutation_tree._purchased.erase("M22")
	ma.step_timed(0.1)
	m.player.global_position = near
	m.player.velocity = Vector3.ZERO
	await frames(3)
	# M07: the extra cell behind a tear
	prog.mutation_tree._purchased["M07"] = true
	m.terrain.remesh_all()
	aim(0.3, 0.0)
	var first: Vector3 = ma._alien_target()
	var dir: Vector3 = m.player.get_look_ray()[1]
	var extra: Vector3 = first + dir * m.terrain_config.cell_size
	check(first != Vector3.INF and m.terrain.density_at(extra) >= 0.5, "fixture: two cells in a row")
	m.terrain.dig_at(first, 1.0)
	m.stomach.fill = full()
	var sum_extra: float = m.terrain.cell_corner_sum(extra)
	ma.on_torn(first)
	check(is_equal_approx(m.terrain.cell_corner_sum(extra), sum_extra) and is_equal_approx(m.stomach.fill, full()), "M07 full: the extra cell stays and nothing goes down")
	m.stomach.fill = 0.0
	ma.on_torn(first)
	check(m.terrain.density_at(extra) < 0.5 and m.stomach.fill > 0.0, "M07 with room: the extra cell is torn and eaten")
	prog.mutation_tree._purchased.erase("M07")
	# big saw: the stroke's extra cells
	prog.grant_item("big_saw")
	check(m.equip_tool("big_saw"), "fixture: the big saw is up")
	m.terrain.remesh_all()
	aim(-0.3, 0.0)
	var saw_at: Vector3 = ma._alien_target()
	check(saw_at != Vector3.INF, "fixture: a cell for the saw")
	saw_at = m.cell_center(saw_at)
	m.terrain.dig_at(saw_at, 1.0)
	m.stomach.fill = full()
	var dug0: float = _sum_around(saw_at)
	check(m.tissue_tools.on_cell_torn(saw_at) == 1, "big saw full: the stroke takes no extra cell")
	check(is_equal_approx(_sum_around(saw_at), dug0) and is_equal_approx(m.stomach.fill, full()), "big saw full: density and stomach unchanged")
	m.stomach.fill = 0.0
	var n: int = m.tissue_tools.on_cell_torn(saw_at)
	check(n > 1 and m.stomach.fill > 0.0 and m.stomach.fill <= float(n - 1) * m.stomach_config.flesh_per_cell + 0.001 and _sum_around(saw_at) < dug0, "big saw with room: %d cells come away and go down (%.1f)" % [n, m.stomach.fill])
	# carrying with the saw up (M28 / T2): its stroke goes straight down, so a
	# full stomach refuses the stroke itself, not only its extra cells
	m.terrain.remesh_all()
	aim(0.0, 0.0)
	await frames(5)
	hit = m._look_hit()
	check(not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk") and prog.equipped() == "big_saw", "fixture: flesh in reach of the saw")
	if not hit.is_empty():
		var saw_cell: Vector3 = m.cell_center(hit.position + m.player.get_look_ray()[1] * m.terrain_config.cell_size * 0.5)
		var saw_sum: float = m.terrain.cell_corner_sum(saw_cell)
		prog.mutation_tree._purchased["M28"] = true # both hands free for a tool while carrying
		m.carry_mode = true
		m.chewer.stomach = null # as Main.toggle_carry leaves it
		m.carried_flesh = 0.0
		m.stomach.fill = full()
		await frames(3)
		check(prog.equipped() == "big_saw" and m.saw_stroke_refused(), "fixture: the saw stays up while carrying")
		var told0: int = told.size()
		var carry0: int = carry_told[0]
		for i in range(150): # 2.5 s of holding, a stroke takes 0.9 s
			await process_frame
			m._chew_step(1.0 / 60.0)
		check(is_equal_approx(m.stomach.fill, full()) and m.terrain.cell_corner_sum(saw_cell) >= saw_sum - 0.001, "carrying + big saw, full: nothing is torn and nothing goes down (%.1f)" % m.stomach.fill)
		check(told.size() > told0 and carry_told[0] == carry0 and not m.chewer.is_chewing(), "and the stomach refuses it out loud (%d)" % (told.size() - told0))
		# with room the same hold starts the stroke (stopped short here: the
		# wall ahead is the next section's fixture)
		m.stomach.fill = 0.0
		var told1: int = told.size()
		for i in range(20):
			m._chew_step(1.0 / 60.0)
		check(m.chewer.is_chewing() and told.size() == told1 and not m.saw_stroke_refused(), "with room the same hold saws")
		m.chewer.stop()
		m.carry_mode = false
		m.chewer.stomach = m.stomach
		m.carried_units.clear()
		prog.mutation_tree._purchased.erase("M28")
	prog.hands.clear()
	prog.refresh_equipment()
	m.stomach.fill = 0.0
	await frames(30)

	# --- 4. flesh past the arm
	var rig: FDKHandsRig = m.hands_rig
	m.terrain.remesh_all()
	m.player.global_position = far
	aim(0.0, 0.0)
	await frames(20)
	check(m._look_hit().is_empty(), "fixture: nothing in reach from here")
	check(m._reach_short_point() != Vector3.INF, "the flesh just past the arm is found")
	var idle_r := pose_of(rig, 0)
	t = 0.0
	while t < 0.5:
		await process_frame
		m._chew_step(root.get_process_delta_time())
		t += root.get_process_delta_time()
	check(m.reach_short_at != Vector3.INF and rig.reach_short_amount() > 0.9, "holding eat, the hands stretch at it (%.2f)" % rig.reach_short_amount())
	check(rig.state == FDKHandsRig.HandState.IDLE and not m.chewer.is_chewing(), "no grab, no chew")
	var out_r := pose_of(rig, 0)
	check((out_r["pos"] as Vector3).z < (idle_r["pos"] as Vector3).z - 0.15, "the hand is out at arm's length (z %.2f -> %.2f)" % [(idle_r["pos"] as Vector3).z, (out_r["pos"] as Vector3).z])
	check(is_equal_approx(float(out_r["f2"]), float(idle_r["f2"])) and is_equal_approx(float(out_r["f3"]), float(idle_r["f3"])) and is_equal_approx(float(out_r["t_opp"]), float(idle_r["t_opp"])), "the fingers stay open: not a grab, not a clutch at the air")
	check(m.dig_key_hint() == "", "looking level, no dig key is offered")
	while t < 1.3:
		await process_frame
		m._chew_step(root.get_process_delta_time())
		t += root.get_process_delta_time()
	check(m._dig_hint_left > 0.0, "held a second, the dig key may show")
	aim(0.0, 0.5)
	m.player.climb_enabled = true
	check(m.dig_key_hint() == "fdk_jump", "looking up where the body can climb: the climb key")
	m.player.climb_enabled = false
	check(m.dig_key_hint() == "", "no climb key where Space does nothing")
	aim(0.0, -0.5)
	check(m.dig_key_hint() == "fdk_crouch", "looking down: the crouch key")
	m._dig_down_learned = true
	check(m.dig_key_hint() == "", "a key used once is not offered again")
	aim(0.0, 0.0)
	await frames(40)
	check(m.reach_short_at == Vector3.INF and rig.reach_short_amount() == 0.0, "released, the hands come back")
	check(same_pose(pose_of(rig, 0), _at_time(rig, idle_r)), "and rest exactly where they rested")
	m.player.global_position = near
	await frames(5)

	# --- 5. hands rig additions at zero leave the poses alone
	rig.set_crush(0.0)
	rig.set_strain(0.0)
	var rest0 := pose_of(rig, 0)
	rig.set_crush(1.0)
	var pressed := pose_of(rig, 0)
	var moved: Vector3 = (pressed["pos"] as Vector3) - (rest0["pos"] as Vector3)
	check(is_equal_approx(moved.x, -0.06) and is_equal_approx(moved.z, 0.04) and is_equal_approx(moved.y, 0.0), "crush presses the resting right hand in and toward the eye (%s)" % str(moved))
	var left_moved: Vector3 = (pose_of(rig, 1)["pos"] as Vector3)
	rig.set_crush(0.0)
	check(is_equal_approx((pose_of(rig, 1)["pos"] as Vector3).x - left_moved.x, -0.06), "and the left hand toward it")
	check(same_pose(pose_of(rig, 0), rest0), "crush 0: the idle pose is the idle pose")
	rig.on_grab_started()
	rig._state_time = 0.2
	rig._chew = 0.6
	var grab0 := pose_of(rig, 0)
	rig.set_crush(1.0)
	check(same_pose(pose_of(rig, 0), grab0), "a working hand ignores the crush offset (GRAB unchanged)")
	rig.set_crush(0.0)
	rig.set_strain(1.0)
	var grab_strained := pose_of(rig, 0)
	check(not (grab_strained["pos"] as Vector3).is_equal_approx(grab0["pos"]) and is_equal_approx(float(grab_strained["f1"]), float(grab0["f1"])), "strain only changes the pull's tremble")
	check((grab_strained["pos"] as Vector3).distance_to(grab0["pos"]) < 0.03, "by millimetres")
	rig.set_strain(0.0)
	check(same_pose(pose_of(rig, 0), grab0), "strain 0: GRAB is GRAB")
	rig.on_released()
	await frames(40)

	# --- 6. the swallow kicks the stomach mass on the swallow's beat
	m.stomach.fill = 0.0
	m.terrain.remesh_all()
	aim(0.6, 0.0)
	await frames(5)
	hit = m._look_hit()
	check(not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk"), "fixture: flesh to eat")
	var bite: Vector3 = hit.position + m.player.get_look_ray()[1] * m.terrain_config.cell_size * 0.5
	check(m.stomach_view.kick() == 0.0, "no kick before the bite")
	m.chewer.try_start(bite)
	m.chewer.process_chew(10.0)
	m.chewer.stop()
	check(m.stomach.fill > 0.0 and m.stomach_view.kick() == 0.0, "the tear itself does not kick")
	t = 0.0
	var kicked_at := -1.0
	var peak := 0.0
	while t < 1.2:
		await process_frame
		t += root.get_process_delta_time()
		if m.stomach_view.kick() > 0.0 and kicked_at < 0.0:
			kicked_at = t
		peak = maxf(peak, m.stomach_view.kick())
		gauge = maxf(gauge, hud.gulp_amount())
	check(gauge > 0.5, "the gauge's end bulges with the swallow (%.2f)" % gauge)
	check(kicked_at > 0.2 and kicked_at < 0.45, "the kick lands %.2f s after the tear (%.2f)" % [FPStomachView.SWALLOW_DELAY, kicked_at])
	check(peak > 0.5 and m.stomach_view.kick() == 0.0, "one kick, then it settles (peak %.2f)" % peak)
	m.carry_mode = true
	m.chewer.stomach = null
	m.terrain.remesh_all()
	aim(0.9, 0.0)
	await frames(5)
	hit = m._look_hit()
	if not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk"):
		m.chewer.try_start(hit.position + m.player.get_look_ray()[1] * m.terrain_config.cell_size * 0.5)
		m.chewer.process_chew(10.0)
		m.chewer.stop()
		await frames(30)
		check(m.carried_flesh > 0.0 and m.stomach_view.kick() == 0.0, "carried flesh is not swallowed: no kick")
	m.carry_mode = false
	m.chewer.stomach = m.stomach
	m.carried_flesh = 0.0
	m.carried_units.clear()

	# --- 7. an overfull tear lands heavier
	var feel = m.tear_feel
	feel.heavy = 0.0
	feel.on_tear(bite, m.player.camera.global_position)
	check(is_equal_approx(feel.jolt_length(), feel.JOLT_TIME), "a comfortable tear's jolt is the old %.1f s" % feel.JOLT_TIME)
	feel.tick(0.05)
	var light: float = feel.jolt_offset().length()
	var light_fov: float = feel.jolt_fov()
	feel.heavy = 1.0
	feel.on_tear(bite, m.player.camera.global_position)
	check(is_equal_approx(feel.jolt_length(), feel.JOLT_TIME_HEAVY), "a gorged tear's jolt lasts %.1f s" % feel.JOLT_TIME_HEAVY)
	feel.tick(0.05)
	check(feel.jolt_offset().length() > light and feel.jolt_fov() < light_fov, "bigger and less widening (%.4f > %.4f)" % [feel.jolt_offset().length(), light])
	feel.heavy = 0.0
	await frames(60)
	check(feel.jolt_offset() == Vector2.ZERO and is_equal_approx(feel.jolt_fov(), 1.0), "and it ends")

	# --- 8. crush throbs; squeezing through shudders
	if m.danger_show != null:
		var cam: Camera3D = m.player.camera
		var d = m.danger_show
		m._crush_t = prog.crush_time()
		d.tick(0.1)
		check(d.crush_beat() > 0.0 and is_equal_approx(rig.crush, 1.0), "a crush beats and presses the hands together")
		var beats: Array = []
		for i in range(12):
			d.tick(0.05)
			beats.append(d.crush_beat())
		check(beats.max() > 0.8 and beats.min() < 0.4, "the beat clenches and lets go (%.2f .. %.2f)" % [beats.min(), beats.max()])
		m._crush_t = 0.0
		d.tick(0.1)
		check(d.crush_beat() == 0.0 and rig.crush == 0.0, "free again: no beat, hands apart")
		check(is_equal_approx(cam.fov, d._base_fov), "and the view is back")

	print("%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

## The idle pose `was` moved to the rig's clock now: only breathing changes it.
func _at_time(rig: FDKHandsRig, was: Dictionary) -> Dictionary:
	var now := pose_of(rig, 0)
	var out := was.duplicate()
	out["wrist_pitch"] = now["wrist_pitch"]
	out["f1"] = now["f1"]
	return out

## Corner density of the 3x3x3 block of cells around p.
func _sum_around(p: Vector3) -> float:
	var cs: float = m.terrain_config.cell_size
	var total := 0.0
	for x in range(-2, 3):
		for y in range(-2, 3):
			for z in range(-2, 3):
				total += m.terrain.density_at(p + Vector3(x, y, z) * cs * 0.5)
	return total
