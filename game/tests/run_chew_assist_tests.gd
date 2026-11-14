extends SceneTree

## A fixed level aim with eat + forward held (decision 0015). The cells on the
## aim line go, the face leaves the arm's reach, and the body has to follow
## over the lip the tunnel leaves. Real Main, real input, real flesh; save and
## key files are this suite's own.
## - control at the door with the assist off: the bite goes silent (the bug)
## - eat alone at the stall tears nothing (the body is not pushing that way)
## - a full stomach at the stall: the assisted contact refuses like any bite
## - at the door, inside the room (no squeezing, no crawling up there): the
##   assist takes the flesh under the aim line that the eye sees, each cell
##   grabbed once, under the line, in the aim's column, never under the feet,
##   inside the arm's reach, eaten = removed. How far the body gets is recorded,
##   not judged: the lip at its feet is out of view and stays.
## - standing and crouching out in the flesh: the bite never stays silent more
##   than 4 s and the body gets on 2 m (the crouched body crawls up the lip
##   with crouch + eat held; it used to be held under it)
## A membrane or a thing that is not flesh under the line, extra-cell mutations
## and the big saw, a face farther than the arm + 1 m: run_chew_assist_edges_tests.gd.

var m: Node3D
var passed := 0
var failed := 0
var tears: Array = [] ## [seconds, cell centre, units, aside, above, below, over the feet, assisted]
var _assisted_cell := Vector3.INF
var clock := 0.0
var grabs := 0
var progress_dropped := 0
var _last_ratio := 0.0
var contact_far := 0.0

func _init() -> void:
	Engine.max_fps = 60
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_chew_assist.json"
	m.save_path = "user://capture-chew-assist-tests.bin"
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

## A tear as it happened: the cell against the aim line of that moment (the
## body climbs and drifts while it digs) and against the feet.
func note_tear(p: Vector3) -> void:
	var cell: Vector3 = m.cell_center(p)
	var ray: Array = m.player.get_look_ray()
	var d: Vector3 = ray[1]
	var n := (Vector3.DOWN - d * Vector3.DOWN.dot(d)).normalized()
	var side := d.cross(n).normalized()
	var rel: Vector3 = cell - (ray[0] as Vector3)
	var assisted := cell.is_equal_approx(_assisted_cell)
	_assisted_cell = Vector3.INF
	tears.append([clock, cell, m.chewer.last_units, absf(rel.dot(side)), -rel.dot(n), rel.dot(n), cell.y - m.player.get_feet_position().y, assisted])

## The assisted tears since `first`: the worst sideways offset from the aim
## line (x), the least depth under it (y; INF with none) and the least height
## of a cell's middle over the feet (z; INF with none).
func worst_offsets(first: int) -> Vector3:
	var out := Vector3(0.0, INF, INF)
	for i in range(first, tears.size()):
		if tears[i][7]:
			out.x = maxf(out.x, float(tears[i][3]))
			out.y = minf(out.y, float(tears[i][5]))
			out.z = minf(out.z, float(tears[i][6]))
	return out

## A room dug out of the flesh for the body to stand in: `cells` cells each
## way from `corner` (a grid point), really dug and published.
func dig_room(corner: Vector3, cells: Vector3i) -> void:
	var cs: float = m.terrain_config.cell_size
	for z in range(cells.z):
		for y in range(cells.y):
			for x in range(cells.x):
				m.terrain.dig_at(corner + (Vector3(x, y, z) + Vector3.ONE * 0.5) * cs, 1.0)
	m.terrain.remesh_all()

## Eat + forward on the level aim for up to `seconds` (or `far` metres on).
## Returns what happened; the eye line is the one the run started on.
func dig_on(label: String, seconds: float, far: float) -> Dictionary:
	var start: Vector3 = m.player.global_position
	var eye0: Vector3 = m.player.get_look_ray()[0]
	var aim: Vector3 = m.player.get_look_ray()[1]
	var t0 := clock
	var first := tears.size()
	var fill0: float = m.stomach.fill
	var grabs0 := grabs
	var drops0 := progress_dropped
	var assist0: int = m.assist_tears
	var cap: float = m.stomach_config.capacity
	var full_at := -1.0
	contact_far = 0.0
	press("fdk_eat", true)
	press("fdk_move_forward", true)
	var t := 0.0
	var log_t := 0.0
	var reached := 0.0 ## the farthest the body got with the inputs held
	var eye_drift := 0.0
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
			var lh: Dictionary = m._look_hit()
			var what := "nothing in reach"
			if not lh.is_empty():
				what = "tissue %d" % m.terrain.tissue_at(m._terrain_target(lh, m.player.get_look_ray()[1])) if lh.collider.has_meta("fdk_terrain_chunk") else String(lh.collider.name)
			print("INFO: %s t=%.0f pos=%s adv=%.2f tears=%d assist=%d fill=%.1f stuck=%.2f sq=%.2f aim=%s short=%s refusals=%d" % [label, t, m.player.global_position, (m.player.global_position - start).dot(aim), tears.size() - first, m.assist_tears - assist0, m.stomach.fill, m.player.stuck_time, m.player.squeeze(), what, m._reach_short_point() != Vector3.INF, m.tissue_tools.membrane_refusals])
		reached = maxf(reached, (m.player.global_position - start).dot(aim))
		if reached >= far:
			break
	press("fdk_eat", false)
	press("fdk_move_forward", false)
	await frames(3)
	var eaten := 0.0
	for i in range(first, tears.size()):
		eaten += float(tears[i][2])
	# The run stops itself at `far`: the body settling back a hair once the
	# inputs are let go is not a stall, so the judged advance is the farthest.
	var adv: float = maxf(reached, (m.player.global_position - start).dot(aim))
	var out := {
		"adv": adv, "tears": tears.size() - first, "assist": m.assist_tears - assist0,
		"gap": longest_gap(t0, full_at if full_at >= 0.0 else clock),
		"off": worst_offsets(first), "eaten": eaten, "gain": m.stomach.fill - fill0,
		"grabs": grabs - grabs0, "drops": progress_dropped - drops0, "contact": contact_far,
		"rise": m.player.global_position.y - start.y, "eye": eye0, "seconds": t,
	}
	print("INFO: %s adv=%.2f m in %.0f s, tears=%d (assist %d), gap=%.1f s, assisted(aside, under the line, over the feet)=%s, eaten=%.1f u (%.1f u/m, %.1f bites/m), rise=%.2f" % [label, adv, t, out.tears, out.assist, out.gap, out.off, eaten, eaten / maxf(adv, 0.01), float(out.tears) / maxf(adv, 0.01), out.rise])
	return out

## The judged run: the body gets on, never silent, only its own way is torn.
func judge(label: String, r: Dictionary) -> void:
	check(float(r.gap) <= 4.0, "%s: no silence longer than 4 s before the stomach filled (%.1f s)" % [label, r.gap])
	check(float(r.adv) >= 2.0, "%s: the body got on down the aim (%.2f m)" % [label, r.adv])
	invariants(label, r)

## What holds for every run, judged or recorded.
func invariants(label: String, r: Dictionary) -> void:
	var cs: float = m.terrain_config.cell_size
	var off: Vector3 = r.off
	check(off.x <= cs * 0.5 + 0.03, "%s: every assisted cell is in the aim's own column (%.2f m aside)" % [label, off.x])
	check(off.y >= cs * 0.5 - 0.03, "%s: every assisted cell lay under the aim's own row (the nearest %.2f m under the line)" % [label, off.y])
	check(off.z >= 0.05, "%s: no assisted cell lay under the feet (lowest middle %.2f m over them)" % [label, off.z])
	check(absf(float(r.gain) - float(r.eaten)) < 0.001, "%s: the stomach rose by exactly what the tears removed (%.2f / %.2f)" % [label, r.gain, r.eaten])
	check(float(r.contact) <= m.progression.reach() + 0.001, "%s: every assisted contact was inside the arm's reach (%.2f m)" % [label, r.contact])
	if bool(r.get("still", false)):
		check(int(r.grabs) <= int(r.tears) + 1 and int(r.drops) == 0, "%s: a grabbed cell is torn, not dropped for another, and its progress never fell back (%d grabs, %d tears, %d drops)" % [label, r.grabs, r.tears, r.drops])

func run() -> void:
	await physics(5)
	m.save_path = "user://capture-chew-assist-tests.bin"
	m.finish_opening()
	m.restroom.set_door_open(true, true)
	m.player.mouse_look_enabled = false
	var cs: float = m.terrain_config.cell_size
	m.chew_assisted.connect(func(c): _assisted_cell = c)
	m.chewer.cell_torn.connect(note_tear)
	m.chewer.grab_started.connect(func(_c): grabs += 1)
	m.chewer.chew_progress.connect(func(r, _c):
		if r + 0.0001 < _last_ratio:
			progress_dropped += 1
		_last_ratio = r)
	m.chewer.cell_torn.connect(func(_p): _last_ratio = 0.0)
	m.chewer.released.connect(func(): _last_ratio = 0.0)
	m.chew_assisted.connect(func(_c):
		if not m._assist_hit.is_empty():
			contact_far = maxf(contact_far, m.player.get_look_ray()[0].distance_to(m._assist_hit.position)))

	# --- 1. at the open door, body against the flesh, aim level and fixed
	m.player.global_position = Vector3(0.0, 0.95, 0.9)
	face_out()
	press("fdk_move_forward", true)
	await physics(90)
	await frames(2)
	var start: Vector3 = m.player.global_position
	var aim: Vector3 = m.player.get_look_ray()[1]
	check(absf(aim.y) < 0.01 and aim.z > 0.99, "fixture: the aim is level, out of the door")
	check(m.player.stuck_time > 0.4, "fixture: the body is walking into the doorway flesh (stuck %.2f s)" % m.player.stuck_time)
	check(m.restroom.contains(start), "fixture: the door's threshold is still the room (no squeezing there)")
	# control: the assist off, the same input stalls
	m.chew_assist_enabled = false
	press("fdk_eat", true)
	await hold(14.0)
	var ctl_tears := tears.size()
	var ctl_gap := longest_gap(0.0, clock)
	var ctl_adv: float = (m.player.global_position - start).dot(aim)
	print("INFO: control tears=%d longest_gap=%.1f advance=%.2f fill=%.1f" % [ctl_tears, ctl_gap, ctl_adv, m.stomach.fill])
	check(ctl_tears >= 2, "control: the cells on the aim line were torn (%d)" % ctl_tears)
	check(ctl_gap > 4.0 and ctl_adv < 0.6, "control: without the assist the bite goes silent (%.1f s) and the body stays (%.2f m)" % [ctl_gap, ctl_adv])
	check(m.assist_tears == 0, "control: the assist tore nothing while off")
	check(m.reach_short_at != Vector3.INF, "control: the hands stretch at the face out of reach (the old signal)")
	# eat alone at the stall: the body is not pushing, nothing under the line
	press("fdk_move_forward", false)
	await physics(4)
	m.chew_assist_enabled = true
	var before_alone := tears.size()
	await hold(5.0)
	check(tears.size() == before_alone and m.assist_tears == 0, "eat alone at the stall: nothing torn (%d)" % (tears.size() - before_alone))
	check(m.reach_short_t >= 1.0, "eat alone at the stall: the hands keep showing out of reach (%.2f)" % m.reach_short_t)
	press("fdk_eat", false)
	await frames(3)
	# a full stomach: the contact under the line refuses like any bite
	var refusals := [0]
	var held := [false]
	m.stomach_refused.connect(func(_at): refusals[0] += 1)
	var fill_was: float = m.stomach.fill
	set_fill(m.stomach_config.capacity + m.stomach_config.overfill_capacity)
	check(m.stomach.is_full(), "fixture: the stomach is at its end")
	press("fdk_eat", true)
	press("fdk_move_forward", true)
	before_alone = tears.size()
	await hold(3.0, func():
		held[0] = held[0] or m._assist_cell != Vector3.INF
		return false)
	press("fdk_eat", false)
	press("fdk_move_forward", false)
	check(held[0] and refusals[0] >= 1, "full stomach: the hands went to the flesh under the line and the stomach refused it (held %s, %d refusals)" % [held[0], refusals[0]])
	check(tears.size() == before_alone and m.assist_tears == 0, "full stomach: nothing was torn")
	set_fill(fill_was)
	await physics(4)
	# the threshold itself: the room's body neither squeezes nor crawls up
	var door: Dictionary = await dig_on("door, standing in the room", 15.0, 3.0)
	door["still"] = true
	check(int(door.assist) >= 3, "door: the assist took the flesh under the line (%d cells)" % door.assist)
	invariants("door", door)

	# --- 2. out in the flesh, standing: a room dug to stand in, the same input
	set_fill(0.0)
	dig_room(Vector3(3.0, 0.0, -1.0), Vector3i(4, 4, 4))
	m.player.global_position = Vector3(4.25, 0.8, 0.0)
	face_out()
	await physics(40)
	press("fdk_move_forward", true)
	await physics(90)
	press("fdk_move_forward", false)
	check(not m.restroom.contains(m.player.global_position) and m.player.squeeze_enabled, "fixture: standing out in the flesh, where the body may squeeze")
	check(not m.player._is_crouching, "fixture: standing")
	var stand: Dictionary = await dig_on("flesh, standing", 45.0, 2.0)
	judge("flesh, standing", stand)

	# --- 3. out in the flesh, crouching
	set_fill(0.0)
	dig_room(Vector3(-5.0, 0.0, -1.0), Vector3i(4, 4, 4))
	m.player.global_position = Vector3(-3.75, 0.8, 0.0)
	face_out()
	press("fdk_crouch", true)
	await physics(40)
	press("fdk_move_forward", true)
	await physics(90)
	press("fdk_move_forward", false)
	check(m.player._is_crouching and m.player.squeeze_enabled, "fixture: crouching out in the flesh")
	check(absf(m.player._pitch) < 0.01, "fixture: the aim is level (crouch + eat is held the whole run)")
	var crouch: Dictionary = await dig_on("flesh, crouching", 45.0, 2.0)
	judge("flesh, crouching", crouch)
	press("fdk_crouch", false)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
