extends SceneTree

## The edges of the chew assist (decision 0015) that run_chew_assist_tests.gd
## leaves out. Real Main, real input, real flesh; save and key files are this
## suite's own.
## - at the door stall, something that is not flesh between the eye and the
##   flesh under the aim line: the assist takes nothing (and takes a cell again
##   the moment the thing is gone)
## - the flesh under the line is membrane: bare hands slip off it at the
##   assisted contact and nothing is torn; a knife cuts it
## - a long open tunnel (its face farther than the arm + 1 m): eat alone and
##   eat + forward tear nothing, the body just walks
## - extra-cell mutations (M07 + M14) and the big saw, standing and crouching
##   out in the flesh: the face jumps away with every tear, and the bite still
##   never goes silent for more than 4 s and the body gets on 2 m

var m: Node3D
var passed := 0
var failed := 0
var tears: Array = [] ## [seconds, cell centre, aside, under the line, over the feet, assisted]
var _assisted_cell := Vector3.INF
var clock := 0.0
var contact_far := 0.0
var refused: Array = [] ## [tissue, distance from the eye]

func _init() -> void:
	Engine.max_fps = 60
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_chew_assist_edges.json"
	m.save_path = "user://capture-chew-assist-edges-tests.bin"
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

func physics(n: int) -> void:
	for i in range(n):
		await physics_frame

func press(action: String, held: bool) -> void:
	if held:
		Input.action_press(action)
	else:
		Input.action_release(action)

func face_out() -> void:
	m.player._yaw = PI
	m.player.rotation.y = PI
	m.player._pitch = 0.0
	m.player.camera_pivot.rotation.x = 0.0

func set_fill(v: float) -> void:
	m.stomach.fill = v
	m.stomach.fill_changed.emit(v, m.stomach_config.capacity, m.stomach_config.overfill_capacity)

## Hold the inputs for `seconds`, keeping the clock; stops early at `until`.
func hold(seconds: float, until: Callable = Callable()) -> void:
	var t := 0.0
	while t < seconds:
		await process_frame
		var d: float = m.get_process_delta_time()
		t += d
		clock += d
		if until.is_valid() and until.call():
			return

## The assist holds a cell this frame (its cell outlives the input by a frame).
func holding() -> bool:
	return m._assist_cell != Vector3.INF and Engine.get_process_frames() - m._assist_frame <= 1

## Longest silence between tears inside [from, to] seconds (ends included).
func longest_gap(from: float, to: float) -> float:
	var last := from
	var worst := 0.0
	for t in tears:
		if t[0] < from or t[0] > to:
			continue
		worst = maxf(worst, t[0] - last)
		last = t[0]
	return maxf(worst, to - last)

func note_tear(p: Vector3) -> void:
	var cell: Vector3 = m.cell_center(p)
	var ray: Array = m.player.get_look_ray()
	var d: Vector3 = ray[1]
	var n := (Vector3.DOWN - d * Vector3.DOWN.dot(d)).normalized()
	var side := d.cross(n).normalized()
	var rel: Vector3 = cell - (ray[0] as Vector3)
	var assisted := cell.is_equal_approx(_assisted_cell)
	_assisted_cell = Vector3.INF
	tears.append([clock, cell, absf(rel.dot(side)), rel.dot(n), cell.y - m.player.get_feet_position().y, assisted])

func dig_room(corner: Vector3, cells: Vector3i) -> void:
	var cs: float = m.terrain_config.cell_size
	for z in range(cells.z):
		for y in range(cells.y):
			for x in range(cells.x):
				m.terrain.dig_at(corner + (Vector3(x, y, z) + Vector3.ONE * 0.5) * cs, 1.0)
	m.terrain.remesh_all()

## Eat + forward on the level aim for up to `seconds` (or `far` metres on).
func dig_on(label: String, seconds: float, far: float) -> Dictionary:
	var start: Vector3 = m.player.global_position
	var aim: Vector3 = m.player.get_look_ray()[1]
	var t0 := clock
	var first := tears.size()
	var assist0: int = m.assist_tears
	var cap: float = m.stomach_config.capacity
	var full_at := -1.0
	contact_far = 0.0
	press("fdk_eat", true)
	press("fdk_move_forward", true)
	var t := 0.0
	var log_t := 0.0
	var reached := 0.0 ## the farthest the body got with the inputs held
	while t < seconds:
		await process_frame
		var d: float = m.get_process_delta_time()
		t += d
		clock += d
		log_t += d
		if full_at < 0.0 and m.stomach.fill >= cap:
			full_at = clock
		if log_t >= 5.0:
			log_t = 0.0
			print("INFO: %s t=%.0f pos=%s adv=%.2f tears=%d assist=%d fill=%.1f stuck=%.2f sq=%.2f short=%s" % [label, t, m.player.global_position, (m.player.global_position - start).dot(aim), tears.size() - first, m.assist_tears - assist0, m.stomach.fill, m.player.stuck_time, m.player.squeeze(), m._reach_short_point() != Vector3.INF])
		reached = maxf(reached, (m.player.global_position - start).dot(aim))
		if reached >= far:
			break
	press("fdk_eat", false)
	press("fdk_move_forward", false)
	await frames(3)
	# The run stops itself at `far`: the body settling back a hair once the
	# inputs are let go is not a stall, so the judged advance is the farthest.
	var adv: float = maxf(reached, (m.player.global_position - start).dot(aim))
	var off := Vector3(0.0, INF, INF)
	for i in range(first, tears.size()):
		if tears[i][5]:
			off.x = maxf(off.x, float(tears[i][2]))
			off.y = minf(off.y, float(tears[i][3]))
			off.z = minf(off.z, float(tears[i][4]))
	var out := {
		"adv": adv, "tears": tears.size() - first, "assist": m.assist_tears - assist0,
		"gap": longest_gap(t0, full_at if full_at >= 0.0 else clock), "off": off,
		"contact": contact_far, "rise": m.player.global_position.y - start.y, "seconds": t,
		"fill": m.stomach.fill, "filled": full_at >= 0.0,
	}
	print("INFO: %s adv=%.2f m in %.0f s, tears=%d (assist %d), gap=%.1f s, assisted(aside, under the line, over the feet)=%s, fill=%.1f, rise=%.2f" % [label, adv, t, out.tears, out.assist, out.gap, off, m.stomach.fill, out.rise])
	return out

## The stall must not come back: never silent, the body gets on, and what the
## assist took is the body's own way.
func judge(label: String, r: Dictionary) -> void:
	var cs: float = m.terrain_config.cell_size
	check(float(r.gap) <= 4.0, "%s: no silence longer than 4 s before the stomach filled (%.1f s)" % [label, r.gap])
	check(float(r.adv) >= 2.0, "%s: the body got on down the aim (%.2f m, stomach %.0f)" % [label, r.adv, r.fill])
	var off: Vector3 = r.off
	check(off.x <= cs * 0.5 + 0.03, "%s: every assisted cell is in the aim's own column (%.2f m aside)" % [label, off.x])
	check(off.y >= cs * 0.5 - 0.03, "%s: every assisted cell lay under the aim's own row (the nearest %.2f m under the line)" % [label, off.y])
	check(off.z >= 0.05, "%s: no assisted cell lay under the feet (lowest middle %.2f m over them)" % [label, off.z])
	check(float(r.contact) <= m.progression.reach() + 0.001, "%s: every assisted contact was inside the arm's reach (%.2f m)" % [label, r.contact])

## A body in a room dug at `corner`, facing out along +Z, walked up against
## the room's wall.
func stand_in_room(corner: Vector3, crouched: bool) -> void:
	press("fdk_crouch", false)
	set_fill(0.0)
	dig_room(corner, Vector3i(4, 4, 4))
	m.player.global_position = corner + Vector3(1.25, 0.8, 1.0)
	m.player.velocity = Vector3.ZERO
	face_out()
	if crouched:
		press("fdk_crouch", true)
	await physics(40)
	press("fdk_move_forward", true)
	await physics(90)
	press("fdk_move_forward", false)
	check(not m.restroom.contains(m.player.global_position) and m.player.squeeze_enabled, "fixture: out in the flesh, where the body may squeeze")
	check(m.player._is_crouching == crouched and absf(m.player._pitch) < 0.01, "fixture: %s, the aim level" % ("crouching" if crouched else "standing"))

func run() -> void:
	await physics(5)
	m.save_path = "user://capture-chew-assist-edges-tests.bin"
	m.finish_opening()
	m.restroom.set_door_open(true, true)
	m.player.mouse_look_enabled = false
	var cs: float = m.terrain_config.cell_size
	var iso: float = m.terrain_config.iso_level
	var prog = m.progression
	m.chew_assisted.connect(func(c): _assisted_cell = c)
	m.chewer.cell_torn.connect(note_tear)
	m.chew_assisted.connect(func(_c):
		if not m._assist_hit.is_empty():
			contact_far = maxf(contact_far, m.player.get_look_ray()[0].distance_to(m._assist_hit.position)))
	m.grab_refused.connect(func(tissue, at): refused.append([tissue, m.player.get_look_ray()[0].distance_to(at)]))

	# --- 1. the door stall: the aim-line cells eaten with the assist off
	m.player.global_position = Vector3(0.0, 0.95, 0.9)
	face_out()
	press("fdk_move_forward", true)
	await physics(90)
	await frames(2)
	m.chew_assist_enabled = false
	press("fdk_eat", true)
	await hold(16.0, func(): return tears.size() >= 2 and clock - float(tears[-1][0]) > 2.5)
	press("fdk_eat", false)
	press("fdk_move_forward", false)
	await frames(3)
	var eye: Vector3 = m.player.get_look_ray()[0]
	var aim: Vector3 = m.player.get_look_ray()[1]
	check(tears.size() >= 2 and m._look_hit().is_empty() and m._reach_short_point() != Vector3.INF, "fixture: the door stall (%d tears, the face just past the arm)" % tears.size())
	check(m.assist_tears == 0, "fixture: nothing assisted yet")
	m.chew_assist_enabled = true

	# something that is not flesh under the line, between the eye and the slab
	var plate := StaticBody3D.new()
	plate.collision_layer = 1 << 9
	plate.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 0.02, 4.0)
	shape.shape = box
	plate.add_child(shape)
	root.add_child(plate)
	plate.global_position = eye + Vector3.DOWN * 0.07 + aim * 1.9
	check((m.player.collision_mask & plate.collision_layer) == 0, "fixture: the plate does not push the body")
	await physics(3)
	var held := [false]
	var before := tears.size()
	press("fdk_eat", true)
	press("fdk_move_forward", true)
	await hold(3.0, func():
		held[0] = held[0] or holding()
		return false)
	check(m.player.stuck_time > 0.4 and m._reach_short_point() != Vector3.INF, "occluded: the body is stuck and the face is still seen past the arm")
	check(not held[0] and m.assist_tears == 0 and tears.size() == before, "occluded: the assist took nothing through the thing in the way (held %s, %d tears)" % [held[0], tears.size() - before])
	check(m.reach_short_t > 0.0, "occluded: the hands show out of reach instead (%.2f)" % m.reach_short_t)
	plate.queue_free()
	await physics(3)
	await hold(3.0, func():
		held[0] = held[0] or holding()
		return held[0])
	press("fdk_eat", false)
	press("fdk_move_forward", false)
	await frames(3)
	check(held[0], "occluded, control: with the thing gone the same input takes a cell under the line")

	# the flesh under the line is membrane
	var feet: Vector3 = m.player.get_feet_position()
	var painted := {}
	for z in range(int(floor(eye.z / cs)), int(floor((eye.z + 4.0) / cs)) + 1):
		for y in range(int(floor((feet.y - 0.5) / cs)), int(floor(eye.y / cs)) + 1):
			for x in range(-2, 2):
				var c := (Vector3(x, y, z) + Vector3.ONE * 0.5) * cs
				if c.y > eye.y - cs * 0.5 + 0.03 or m.terrain.density_at(c) < iso:
					continue
				var rc: Array = m.terrain.world_to_cell(c)
				(m.terrain.get_or_create_chunk(rc[0]) as FDKChunk).set_tissue_at_cell(rc[1].x, rc[1].y, rc[1].z, FDKTissueRules.MEMBRANE)
				painted[Vector3i(x, y, z)] = true
	m.terrain.remesh_all()
	await physics(4)
	check(painted.size() >= 4, "fixture: the flesh under the line is membrane (%d cells)" % painted.size())
	check(prog.equipped() == "", "fixture: bare hands")
	refused.clear()
	held[0] = false
	before = tears.size()
	press("fdk_eat", true)
	press("fdk_move_forward", true)
	await hold(3.0, func():
		held[0] = held[0] or holding()
		return false)
	press("fdk_eat", false)
	press("fdk_move_forward", false)
	await frames(3)
	var slipped := 0
	var slip_far := 0.0
	for r in refused:
		if int(r[0]) == FDKTissueRules.MEMBRANE:
			slipped += 1
			slip_far = maxf(slip_far, float(r[1]))
	check(held[0] and slipped >= 1, "membrane, bare hands: the hands went under the line and slipped off it (held %s, %d slips)" % [held[0], slipped])
	check(slip_far <= prog.reach() + 0.001, "membrane, bare hands: the slip is at a contact inside the arm's reach (%.2f m)" % slip_far)
	check(tears.size() == before and m.assist_tears == 0, "membrane, bare hands: nothing was torn")
	prog.grant_item("knife")
	check(m.equip_tool("knife"), "fixture: the knife is up")
	var fill0: float = m.stomach.fill
	press("fp_pick", true) # the knife is in the right hand
	press("fdk_move_forward", true)
	await hold(6.0, func(): return m.assist_tears >= 1)
	press("fp_pick", false)
	press("fdk_move_forward", false)
	await frames(3)
	check(m.assist_tears >= 1 and tears.size() > before, "membrane, knife: the assisted cell is cut (%d)" % m.assist_tears)
	if tears.size() > before:
		var cut: Vector3 = tears[-1][1]
		check(painted.has(Vector3i((cut / cs).floor())) and bool(tears[-1][5]), "membrane, knife: what was cut is the membrane under the line")
		check(m.stomach.fill > fill0 and is_equal_approx(m.stomach.fill - fill0, m.chewer.last_units), "membrane, knife: the stomach rose by what the cut removed (%.2f)" % (m.stomach.fill - fill0))
	check(m.equip_tool(""), "fixture: bare hands again")

	# --- 2. a long open tunnel: nothing to take, the body walks
	set_fill(0.0)
	var corner := Vector3(11.0, 0.0, -1.0)
	dig_room(corner, Vector3i(4, 4, 4))
	for i in range(16):
		for y in range(2):
			m.terrain.dig_at(corner + Vector3(1.25, (float(y) + 0.5) * cs, 2.0 + (float(i) + 0.5) * cs), 1.0)
	m.terrain.remesh_all()
	m.player.global_position = corner + Vector3(1.25, 0.8, 1.0)
	m.player.velocity = Vector3.ZERO
	face_out()
	press("fdk_crouch", true)
	await physics(40)
	print("INFO: tunnel start pos=%s crouch=%s in room=%s" % [m.player.global_position, m.player._is_crouching, m.restroom.contains(m.player.global_position)])
	var a0: int = m.assist_tears
	before = tears.size()
	held[0] = false
	var from: Vector3 = m.player.global_position
	check(m._look_hit().is_empty() and m._reach_short_point() == Vector3.INF, "tunnel fixture: the face is farther than the arm + 1 m")
	press("fdk_eat", true)
	await hold(3.0, func():
		held[0] = held[0] or holding()
		return false)
	check(tears.size() == before and not held[0], "tunnel, eat alone: nothing torn, nothing taken")
	press("fdk_move_forward", true)
	await hold(2.0, func():
		held[0] = held[0] or holding()
		return false)
	press("fdk_eat", false)
	press("fdk_move_forward", false)
	press("fdk_crouch", false)
	await frames(3)
	var walked: float = (m.player.global_position - from).dot(Vector3(0, 0, 1))
	print("INFO: tunnel walked=%.2f tears=%d assist=%d fill=%.1f" % [walked, tears.size() - before, m.assist_tears - a0, m.stomach.fill])
	check(tears.size() == before and m.assist_tears == a0 and not held[0] and is_zero_approx(m.stomach.fill), "tunnel, eat + forward: nothing torn, nothing taken, nothing eaten")
	check(walked > 1.0, "tunnel, eat + forward: the body walks down it (%.2f m)" % walked)

	# --- 3. extra-cell mutations: every tear takes two more cells down the aim
	prog.mutation_tree._purchased["M07"] = true
	prog.mutation_tree._purchased["M14"] = true
	m.mutation_apply._apply_speeds()
	check(prog.tear_cells() == 3, "fixture: M07 + M14, three cells a tear")
	await stand_in_room(Vector3(3.0, 0.0, -1.0), false)
	judge("M07 + M14, standing", await dig_on("M07 + M14, standing", 30.0, 2.0))
	await stand_in_room(Vector3(-5.0, 0.0, -1.0), true)
	judge("M07 + M14, crouching", await dig_on("M07 + M14, crouching", 30.0, 2.0))
	press("fdk_crouch", false)
	prog.mutation_tree._purchased.erase("M07")
	prog.mutation_tree._purchased.erase("M14")
	m.mutation_apply._apply_speeds()

	# --- 4. the big saw: every stroke takes five more cells round its own
	prog.grant_item("big_saw")
	await stand_in_room(Vector3(7.0, 0.0, -1.0), false)
	check(m.equip_tool("big_saw"), "fixture: the big saw is up")
	judge("big saw, standing", await dig_on("big saw, standing", 30.0, 2.0))
	await stand_in_room(Vector3(-9.0, 0.0, -1.0), true)
	check(prog.equipped() == "big_saw", "fixture: the big saw is still up")
	judge("big saw, crouching", await dig_on("big saw, crouching", 30.0, 2.0))
	press("fdk_crouch", false)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
