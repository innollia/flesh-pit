extends SceneTree

## Gorged walk (decision 0012): past a full stomach the walk grows heavy.
## - FPProgression.gorge_speed_factor: 1.0 up to capacity, 0.75 at the cap
## - real Main, a clear lane across the restroom floor: the controller's
##   move_speed_scale and the distance really walked follow it (the walk
##   stays heavy in the white room until the stomach is emptied)
## - never on top of another slowdown: with the crush clock running the speed
##   is the squeeze factor alone (0.5, M19 1.3, M20 1.0), and against the
##   posture slowdown only the smaller of the two counts
## - climbing keeps its speed; vomiting frees the legs the next frame
## - the footstep is lower and heavier, as many steps per metre as before
## - the head bob is deeper; the camera's fov is left alone
## Save and key files are this suite's own.

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	Engine.max_fps = 60
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_gorge_walk.json"
	m.save_path = "user://capture-gorge-walk-tests.bin"
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

func set_fill(v: float) -> void:
	m.stomach.fill = v
	m.stomach.fill_changed.emit(v, m.stomach_config.capacity, m.stomach_config.overfill_capacity)

func face_hall() -> void:
	m.player._yaw = -PI * 0.5
	m.player.rotation.y = -PI * 0.5
	m.player._pitch = 0.0
	m.player.camera_pivot.rotation.x = 0.0
	m.player.velocity = Vector3.ZERO

## A lane across the restroom, door side of the toilet: 3.6 m of clear floor
## from here toward +x.
const HALL_START := Vector3(-1.7, 0.95, 0.6)

func to_hall_start() -> void:
	m.player.global_position = HALL_START
	face_hall()

## Metres really covered along the hall in `seconds` of holding forward.
func walk(seconds: float, crouched: bool) -> float:
	to_hall_start()
	if crouched:
		Input.action_press("fdk_crouch")
	await physics(30)
	await frames(2)
	var from: Vector3 = m.player.global_position
	Input.action_press("fdk_move_forward")
	await physics(int(round(seconds * 60.0)))
	var to: Vector3 = m.player.global_position
	Input.action_release("fdk_move_forward")
	Input.action_release("fdk_crouch")
	await physics(2)
	return Vector2(to.x - from.x, to.z - from.z).length()

func run() -> void:
	await frames(5)
	m.finish_opening()
	m.player.mouse_look_enabled = false
	var prog: FPProgression = m.progression
	var ma = m.mutation_apply
	var c: Resource = m.player.config
	var cap: float = m.stomach_config.capacity
	var over: float = m.stomach_config.overfill_capacity

	# G1 the rule itself
	check(is_equal_approx(FPProgression.GORGE_WALK_MIN, 0.75), "G1 the gorged walk bottoms out at 0.75")
	check(is_equal_approx(prog.gorge_speed_factor(0.0), 1.0) and is_equal_approx(prog.gorge_speed_factor(0.5), 0.875) and is_equal_approx(prog.gorge_speed_factor(1.0), 0.75), "G1 factor 1.0 / 0.875 / 0.75 at overfill 0 / 0.5 / 1")
	check(is_equal_approx(prog.gorge_speed_factor(-1.0), 1.0) and is_equal_approx(prog.gorge_speed_factor(3.0), 0.75), "G1 the factor is clamped outside 0..1")

	to_hall_start()
	await physics(20)
	await frames(3)
	check(m.crush_progress() <= 0.0 and m.player.squeeze() < 0.01 and m.player.is_on_floor(), "fixture: standing free on the restroom floor (squeeze %.2f)" % m.player.squeeze())
	var base_walk: float = float(c.walk_speed)
	var base_crouch: float = float(c.crouch_speed)
	var base_climb: float = float(c.climb_speed)
	var base_climb_up: float = float(c.climb_up_speed)
	var base_bob: float = float(c.bob_amplitude)
	var base_sway: float = float(c.bob_sway)
	var fov0: float = m.player.camera.fov
	check(is_equal_approx(base_bob, 0.045) and is_equal_approx(base_sway, 0.022), "fixture: the kit's plain bob (0.045, 0.022)")

	# G2 the scale on the controller and the ground really covered
	for spec in [[cap, 1.0], [cap + over * 0.5, 0.875], [cap + over, 0.75]]:
		set_fill(float(spec[0]))
		await frames(3)
		check(is_equal_approx(m.player.move_speed_scale, float(spec[1])), "G2 fill %.0f walks at x%.3f (got %.3f)" % [spec[0], spec[1], m.player.move_speed_scale])
		var want: float = base_crouch * float(spec[1]) * 2.0
		var got: float = await walk(2.0, true)
		check(absf(got - want) <= want * 0.05, "G2 fill %.0f: crouched 2 s covers %.2f m (got %.2f)" % [spec[0], want, got])
	set_fill(cap * 0.5)
	await frames(3)
	check(is_equal_approx(m.player.move_speed_scale, 1.0), "G2 below capacity the walk is untouched")

	# G6 climbing keeps its speed, G8 the bob deepens, the fov is left alone
	set_fill(cap + over)
	to_hall_start()
	await frames(3)
	check(is_equal_approx(float(c.climb_speed), base_climb) and is_equal_approx(float(c.climb_up_speed), base_climb_up), "G6 climbing is as fast gorged as empty")
	check(is_equal_approx(float(c.walk_speed), base_walk) and is_equal_approx(float(c.crouch_speed), base_crouch), "the kit's own walk and crouch speeds are not rewritten")
	check(is_equal_approx(float(c.bob_amplitude), base_bob * 1.5) and is_equal_approx(float(c.bob_sway), base_sway * 1.5), "G8 gorged bob is x1.5 (%.4f, %.4f)" % [c.bob_amplitude, c.bob_sway])
	check(is_equal_approx(m.player.camera.fov, fov0), "G8 the gorged walk adds nothing to the fov")
	c.head_bob_enabled = false
	await physics(30)
	var pivot0: Vector3 = m.player.camera_pivot.position
	Input.action_press("fdk_move_forward")
	var moved_cam := false
	for i in range(40):
		await physics_frame
		if not m.player.camera_pivot.position.is_equal_approx(pivot0):
			moved_cam = true
	Input.action_release("fdk_move_forward")
	check(not moved_cam, "G8 with the head bob off the camera does not move")
	c.head_bob_enabled = true
	await physics(5)

	# G3 the crush clock: the squeeze factor alone, as with an empty stomach
	to_hall_start()
	m._crush_t = 1.0
	ma.step_timed(0.0)
	check(is_equal_approx(m.player.move_speed_scale, 0.5), "G3 gorged and boxed in: x0.5, not 0.5 x 0.75 (got %.3f)" % m.player.move_speed_scale)
	prog.mutation_tree._purchased["M19"] = true
	ma.apply_now()
	m._crush_t = 1.0
	ma.step_timed(0.0)
	check(is_equal_approx(m.player.move_speed_scale, 1.3), "G3 M19 gorged and boxed in: x1.3 (got %.3f)" % m.player.move_speed_scale)
	prog.mutation_tree._purchased.erase("M19")
	prog.mutation_tree._purchased["M20"] = true
	ma.apply_now()
	m._crush_t = 1.0
	ma.step_timed(0.0)
	check(is_equal_approx(m.player.move_speed_scale, 1.0), "G3 M20 gorged and boxed in: x1.0 (got %.3f)" % m.player.move_speed_scale)
	prog.mutation_tree._purchased.erase("M20")
	ma.apply_now()
	m._crush_t = 0.0

	# G4 the posture slowdown: only the smaller of the two counts
	var smin: float = float(c.squeeze_speed_min)
	check(is_equal_approx(smin, 0.35), "fixture: the tightest squeeze walks at x0.35")
	for sq in [1.0, 0.3, 0.0]:
		m.player.duck = sq
		m.player.twist = 0.0
		ma.step_timed(0.0)
		var posture: float = lerpf(1.0, smin, sq)
		var real: float = m.player.move_speed_scale * posture
		check(is_equal_approx(real, minf(posture, 0.75)), "G4 gorged at squeeze %.1f: x%.3f = the smaller of posture %.3f and gorge 0.75" % [sq, real, posture])
	m.player.duck = 0.0
	ma.step_timed(0.0)

	# G7 the footstep: lower, heavier, as many per metre
	var director: FDKAudioDirector = m.get_node("AudioHookup").director
	set_fill(0.0)
	await frames(3)
	check(is_equal_approx(director.step_pitch_scale, 1.0) and is_equal_approx(director.step_weight_db, 0.0), "G7 an empty stomach leaves the step plain")
	var n0: int = director.steps_played
	var d0: float = await walk(1.0, false)
	var per_m_empty: float = float(director.steps_played - n0) / maxf(d0, 0.01)
	set_fill(cap)
	await frames(3)
	check(is_equal_approx(director.step_pitch_scale, 1.0) and is_equal_approx(director.step_weight_db, 0.0), "G7 a full stomach (not gorged) leaves the step plain")
	set_fill(cap + over)
	await frames(3)
	check(is_equal_approx(director.step_pitch_scale, 0.85) and is_equal_approx(director.step_weight_db, 3.0), "G7 gorged: pitch x0.85, +3 dB (%.3f, %.1f)" % [director.step_pitch_scale, director.step_weight_db])
	var n1: int = director.steps_played
	var lo := 9.0
	var hi := 0.0
	var dlo := 99.0
	var dhi := -99.0
	to_hall_start()
	await physics(20)
	var from: Vector3 = m.player.global_position
	Input.action_press("fdk_move_forward")
	var seen: int = director.steps_played
	for i in range(78):
		await physics_frame
		if director.steps_played != seen:
			seen = director.steps_played
			lo = minf(lo, director.last_step_pitch)
			hi = maxf(hi, director.last_step_pitch)
			dlo = minf(dlo, director.last_step_db)
			dhi = maxf(dhi, director.last_step_db)
	Input.action_release("fdk_move_forward")
	var d1: float = Vector2(m.player.global_position.x - from.x, m.player.global_position.z - from.z).length()
	var steps1: int = director.steps_played - n1
	check(steps1 >= 2, "G7 fixture: the gorged walk made footsteps (%d over %.2f m)" % [steps1, d1])
	var j: float = director.step_pitch_jitter
	var g: float = director.step_gain_jitter_db
	check(lo >= 0.85 * (1.0 - j) - 0.001 and hi <= 0.85 * (1.0 + j) + 0.001, "G7 gorged footsteps sit at 0.85 x (1 +- %.2f) (%.3f..%.3f)" % [j, lo, hi])
	check(dlo >= director.step_gain_db + 3.0 - g - 0.001 and dhi <= director.step_gain_db + 3.0 + g + 0.001, "G7 gorged footsteps are 3 dB up, +- %.1f (%.2f..%.2f around %.1f)" % [g, dlo, dhi, director.step_gain_db + 3.0])
	check(absf(float(steps1) - per_m_empty * d1) <= 1.0, "G7 as many steps per metre as with an empty stomach (%d over %.2f m against %.2f per m)" % [steps1, d1, per_m_empty])
	check(absf(d1 - base_walk * 0.75 * 78.0 / 60.0) <= base_walk * 0.75 * 78.0 / 60.0 * 0.05, "G7 the gorged standing walk covers %.2f m in 78 ticks (got %.2f)" % [base_walk * 0.75 * 78.0 / 60.0, d1])

	# G5 vomiting frees the legs the next frame
	check(is_equal_approx(m.player.move_speed_scale, 0.75), "G5 fixture: still gorged")
	m.stomach.vomit()
	await frames(2)
	check(is_equal_approx(m.player.move_speed_scale, 1.0) and is_equal_approx(float(c.bob_amplitude), base_bob) and is_equal_approx(director.step_pitch_scale, 1.0), "G5 after vomiting the walk, bob and step are plain again")

	print("%d passed, %d failed" % [passed, failed])
	m.queue_free()
	await process_frame
	quit(1 if failed else 0)
