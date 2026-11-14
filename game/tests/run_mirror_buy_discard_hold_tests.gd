extends SceneTree

## Two rules of where and how (real Main, own save and key files):
## - the Tab screen opens anywhere and buys only standing in the restroom
##   looking into the mirror from close by (decision 0014). Anywhere else the
##   list, the part glow and the ghost are there, and a buy press changes
##   nothing: no hairs gone, no red refusal, the ghost flickers once.
## - V away from the bowl and the rest points throws the stomach away only
##   after the key has been held DISCARD_HOLD seconds (decision 0009, amended):
##   a tap, a short hold and a re-press give nothing away. At the bowl and at a
##   rest point V still settles at once.

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	Engine.max_fps = 60
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_mirror_hold.json"
	m.save_path = "user://capture-mirror-hold-tests.bin"
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

func look(yaw: float, pitch: float = 0.0) -> void:
	m.player._yaw = yaw
	m.player.rotation.y = yaw
	m.player._pitch = pitch
	m.player.camera_pivot.rotation.x = pitch

## In front of the mirror (it hangs on the -X wall), `away` metres from its
## glass, turned `off` degrees from straight at it.
func stand_at_mirror(away: float = 1.0, off: float = 0.0) -> void:
	var p: Vector3 = m.mirror_point()
	m.player.global_position = Vector3(p.x + away, 0.95, p.z)
	look(PI * 0.5 + deg_to_rad(off))

func set_fill(v: float) -> void:
	m.stomach.fill = v
	m.stomach.fill_changed.emit(v, m.stomach_config.capacity, m.stomach_config.overfill_capacity)

## The hold, stepped by hand in exact slices (no frame runs between them).
func hold_for(seconds: float, held: bool = true) -> void:
	var left := seconds
	while left > 0.0001:
		var d := minf(0.01, left)
		m.discard_hold_step(d, held)
		left -= d

func run() -> void:
	for i in range(5):
		await physics_frame
	m.save_path = "user://capture-mirror-hold-tests.bin"
	m.finish_opening()
	m.player.mouse_look_enabled = false
	await frames(2)
	var prog: FPProgression = m.progression
	var mir: FPMirror = m.mirror
	var cost: int = prog.cost_in("M10", "core")
	prog.mutation_tree.add_points("core", cost)
	check(prog.any_buyable_mutation() and prog.can_buy_mutation("M10"), "fixture: the hairs can pay for M10")
	var not_here := [0]
	var denied := [0]
	var mutated := [0]
	mir.not_here.connect(func(_p): not_here[0] += 1)
	mir.denied.connect(func(_p): denied[0] += 1)
	mir.mutated.connect(func(_id): mutated[0] += 1)

	# --- where the mirror counts
	stand_at_mirror()
	check(m.at_mirror(), "standing 1 m in front of the mirror, looking into it: at the mirror")
	stand_at_mirror(1.0, 30.0)
	check(m.at_mirror(), "30 degrees off the mirror still counts")
	stand_at_mirror(1.0, 40.0)
	check(not m.at_mirror(), "40 degrees off does not")
	stand_at_mirror(1.9)
	check(not m.at_mirror(), "1.9 m away does not (the eye is farther than 1.6 m)")
	stand_at_mirror(1.0, 180.0)
	check(not m.at_mirror(), "back to the mirror does not")
	stand_at_mirror()
	m.restroom.mirror_art.set("cabinet_open", true)
	check(not m.at_mirror(), "the cabinet door swung open: no mirror to look into")
	m.restroom.mirror_art.set("cabinet_open", false)
	check(m.at_mirror(), "the door shut again: the mirror counts")

	# --- the first time something can be bought: the Tab cap shows on the mirror
	stand_at_mirror(1.9)
	await frames(3)
	check(m._first_mirror_spot().is_finite() and m.opening_view.hints.mirror_at.is_finite(), "in the room, the mirror in view, hairs enough, nothing bought yet: the Tab cap pulses on the mirror")
	stand_at_mirror(1.9, 180.0)
	await frames(3)
	check(not m.opening_view.hints.mirror_at.is_finite(), "the mirror out of view: no cap")
	stand_at_mirror()
	await frames(3)
	check(m.interact_target() == "mirror" and String(m.interact_ring.get("action")) == "fp_mutate", "at the mirror the aim ring's glyph is the Tab key (%s, %s)" % [m.interact_target(), m.interact_ring.get("action")])
	check(not m.opening_view.hints.mirror_at.is_finite(), "the ring shows the key there, the pulsing cap does not double it")

	# --- away from the mirror the screen opens and shows, and buys nothing
	var away := {
		"in the room, back to the mirror": func(): stand_at_mirror(1.0, 180.0),
		"out in the flesh": func():
			m.player.global_position = Vector3(0.0, 0.6, 6.0)
			look(PI),
		"at a rest point": func():
			m.player.global_position = m.rest_points[0] + Vector3(0, -FPWorldFeatures.CONTAINER_HALF.y + 0.9, 0.0)
			look(0.0),
	}
	for label: String in away:
		(away[label] as Callable).call()
		m.open_mirror()
		check(mir.visible and not mir.can_buy_here, "%s: Tab opens the screen, and it does not buy here" % label)
		mir.focus_part("right_hand")
		var guard := 0
		while mir.candidate() != "M10" and guard < 10:
			mir.select_candidate(int(mir._cand.get("right_hand", 0)) + 1)
			guard += 1
		check(mir.candidate() == "M10" and mir.ghost_id() == "M10" and mir.panel.visible and not mir.rows().is_empty(), "%s: the list and the ghost of what could be bought are shown" % label)
		check(mir.body.shimmer_on("right_hand"), "%s: the part still glows" % label)
		await frames(2)
		var hair: Node3D = mir.arm_hair()
		check(hair != null and int(hair.call("blink_count")) == 0, "%s: no hair blinks as a price" % label)
		var before: Array = [not_here[0], denied[0], mutated[0]]
		check(mir.buy_current() == "" and prog.hairs("core") == cost and not prog.has_mutation("M10"), "%s: a buy press takes no hair and gives no mutation" % label)
		check(not_here[0] == before[0] + 1 and denied[0] == before[1] and mutated[0] == before[2], "%s: it is told as 'not here', not as a refusal" % label)
		check(mir.ghost_flickering() and not mir.body.is_red("right_hand"), "%s: the ghost flickers, nothing blinks red" % label)
		for i in range(30):
			mir._step_flicker(0.01)
		check(not mir.ghost_flickering() and mir.ghost_id() == "M10", "%s: the flicker is over in 0.15 s and the ghost is back" % label)
		mir.close()
		await frames(2)

	# --- a bump away from the mirror: no beat, no press
	var t: Node3D = m.tumor_nodes[4]
	m.player.global_position = t.global_position - Vector3(0, 0.6, 0.7)
	m.player.camera.look_at(t.global_position, Vector3.UP)
	check(m.eat_tumor() and prog.belly_bumps() == 1, "fixture: a tumor eaten, one bump on the belly")
	m.player.camera.rotation = Vector3.ZERO
	m.open_mirror()
	mir.focus_part("tumor")
	check(mir.body.tumor_bumps().size() == 1 and not mir.body.tumor_shimmer_on(), "away from the mirror the bump is on the doll and does not beat")
	check(mir.buy_current() == "" and prog.belly_bumps() == 1 and prog.tumor_mutations.is_empty(), "away from the mirror a press on the bump changes nothing")
	mir.close()
	await frames(2)

	# --- at the mirror it buys
	stand_at_mirror()
	m.open_mirror()
	check(mir.can_buy_here, "at the mirror: the screen buys")
	check(mir.body.tumor_bumps().size() == 1, "the screen opened a second time still has its bump (%d)" % mir.body.tumor_bumps().size())
	check(mir.body.tumor_shimmer_on(), "at the mirror the bump beats")
	mir.focus_part("right_hand")
	var g := 0
	while mir.candidate() != "M10" and g < 10:
		mir.select_candidate(int(mir._cand.get("right_hand", 0)) + 1)
		g += 1
	await frames(2)
	var hair2: Node3D = mir.arm_hair()
	check(hair2 != null and String(hair2.call("blink_kind")) == "core" and int(hair2.call("blink_count")) == cost, "at the mirror the hairs the row costs blink")
	var was: int = not_here[0]
	check(mir.buy_current() == "M10" and prog.has_mutation("M10") and prog.hairs("core") == 0, "at the mirror the buy press buys: hairs gone, mutation owned")
	check(not_here[0] == was and mutated[0] == 1, "told as a mutation, not as 'not here'")
	mir.focus_part("tumor")
	var got: String = mir.buy_current()
	check(got in FPProgression.TUMOR_MUTATIONS and prog.belly_bumps() == 0, "at the mirror the bump turns into its mutation (%s)" % got)
	mir.close()
	await frames(3)
	check(not m._first_mirror_spot().is_finite(), "a mutation owned: the first-time cap is over for good")

	# --- V out of the bowl's and the rest points' reach: held, not tapped
	m.lever_settled = true
	m.player.global_position = Vector3(1.5, 0.95, 1.0)
	look(PI)
	var heaves := [0]
	m.dry_heaved.connect(func(): heaves[0] += 1)
	check(not m._near_toilet() and m._near_rest_point() < 0, "fixture: away from the bowl and every rest point")
	check(is_equal_approx(m.DISCARD_HOLD, 0.8), "the hold is 0.8 s")
	var teeth0: int = prog.teeth
	set_fill(100.0)
	m.mutation_apply.cud_credit = 3.0
	m.request_vomit()
	check(is_equal_approx(m.stomach.fill, 100.0) and m.discard_holding() and m.hand_motions.kind == "vomit_floor", "the press only starts the bow: the stomach is whole")
	hold_for(0.79)
	check(is_equal_approx(m.stomach.fill, 100.0) and m.discard_holding(), "held 0.79 s: still whole")
	hold_for(0.02)
	check(m.stomach.fill == 0.0 and m.mutation_apply.cud_credit == 0.0 and prog.teeth == teeth0 and not m.discard_holding(), "past 0.8 s the stomach and the cud go, for no teeth")
	check(m.hand_motions.kind == "vomit_floor" and not m.hand_motions.cancelled, "the bow goes on into the heave")
	check(heaves[0] == 0, "no dry heave was told")
	for i in range(60):
		m.hand_motions.tick(0.05)
	# a short hold, let go, pressed again short
	set_fill(100.0)
	m.request_vomit()
	hold_for(0.5)
	m.discard_hold_step(0.01, false)
	check(not m.discard_holding() and (m.hand_motions.cancelled or not m.hand_motions.busy()), "let go at 0.5 s: the hold is over and the body straightens")
	hold_for(0.5)
	check(is_equal_approx(m.stomach.fill, 100.0), "holding again without a new press does nothing")
	for i in range(20):
		m.hand_motions.tick(0.05)
	m.request_vomit()
	hold_for(0.5)
	m.request_vomit() # let go and pressed again inside one frame
	hold_for(0.5)
	check(is_equal_approx(m.stomach.fill, 100.0) and m.discard_holding(), "0.5 s, a new press, 0.5 s: the count started again, still whole")
	m.discard_hold_step(0.01, false)
	for i in range(20):
		m.hand_motions.tick(0.05)
	# taps
	for i in range(20):
		m.request_vomit()
		hold_for(0.05)
		m.discard_hold_step(0.0, false)
		for k in range(10):
			m.hand_motions.tick(0.05)
	check(is_equal_approx(m.stomach.fill, 100.0) and not m.discard_holding(), "twenty 0.05 s taps: nothing thrown away")
	# the real key, through the frames
	Input.action_press("fp_vomit")
	var t_held := 0.0
	var at_07 := -1.0
	var gone_at := -1.0
	while t_held < 1.6 and gone_at < 0.0:
		await process_frame
		t_held += m.get_process_delta_time()
		if t_held <= 0.7:
			at_07 = m.stomach.fill
		if m.stomach.fill == 0.0:
			gone_at = t_held
	Input.action_release("fp_vomit")
	check(is_equal_approx(at_07, 100.0) and gone_at >= 0.75 and gone_at <= 1.0, "the V key held through real frames: whole at 0.7 s, gone at about 0.8 s (%.2f s)" % gone_at)
	await frames(3)
	for i in range(60):
		m.hand_motions.tick(0.05)

	# --- before the first settlement
	m.lever_settled = false
	set_fill(40.0)
	m.request_vomit()
	hold_for(2.0)
	check(heaves[0] == 1 and is_equal_approx(m.stomach.fill, 40.0) and not m.discard_holding(), "before the first settlement V is one dry heave however long it is held")
	for i in range(40):
		m.hand_motions.tick(0.05)
	set_fill(m.stomach_config.capacity + m.stomach_config.overfill_capacity)
	check(m.stomach.is_full(), "fixture: the stomach at its end before the first settlement")
	var full: float = m.stomach.fill
	m.request_vomit()
	hold_for(0.79)
	check(is_equal_approx(m.stomach.fill, full) and heaves[0] == 1, "a stomach at its end (decision 0013): the same hold, whole at 0.79 s")
	hold_for(0.02)
	check(m.stomach.fill == 0.0, "and gone past 0.8 s")
	for i in range(60):
		m.hand_motions.tick(0.05)

	# --- at a rest point and at the bowl V settles at once
	m.lever_settled = true
	m.player.global_position = m.rest_stand_point(0)
	check(m._near_rest_point() == 0, "fixture: at the first rest point's bucket")
	set_fill(60.0)
	m.request_vomit()
	check(m.stomach.fill == 0.0 and not m.discard_holding() and m.rest_teeth[0] == FPProgression.teeth_for(60.0), "at a rest point the press empties the stomach into the bucket at once, no hold")
	for i in range(60):
		m.hand_motions.tick(0.05)
	m.player.global_position = m.restroom.toilet.to_global(Vector3(0, 0.9, 0.9))
	check(m._near_toilet(), "fixture: at the bowl")
	set_fill(60.0)
	m.request_vomit()
	check(m.stomach.fill == 0.0 and m._settling and not m.discard_holding(), "at the bowl the press settles at once, no hold")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
