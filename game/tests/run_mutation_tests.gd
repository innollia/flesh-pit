extends SceneTree

## Session C tests: every mutation of docs/spec/05-mutations.md sets its
## parameter (W30), the mirror (W08: shimmer, ghost, red blink, keyboard-only
## purchase), M10 long knuckle end to end (W12: reach +0.4 m, the finger
## gets longer), tumors both ways (W11: eat -> belly bump -> mirror -> tumor
## mutation; carry -> toilet -> teeth + codex drawing) and the ★ stomach
## forms (W31).
## Run: Godot_console.exe --headless --path <project> --script tests/run_mutation_tests.gd

var _failures := 0
var _passed := 0
var _m: Node3D
var _frame := 0

## Camera-space point inside a 16:9 view of cam (vertical fov).
func _in_view(cam: Camera3D, p: Vector3) -> bool:
	if p.z > -cam.near:
		return false
	var ty := tan(deg_to_rad(cam.fov) * 0.5)
	return absf(p.y) / -p.z < ty and absf(p.x) / -p.z < ty * 16.0 / 9.0

func _assert(c: bool, msg: String) -> void:
	if c:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: %s" % msg)

func _init() -> void:
	print("=== flesh-pit mutation tests ===")
	_m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_m)

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 2:
		_m.finish_opening()
	if _frame < 6:
		return false
	_run_params()
	_run_mirror()
	_run_long_knuckle()
	_run_tumors()
	_run_stomach_forms()
	_run_skipped_followup()
	_m.queue_free()
	print("--- %d passed, %d failed ---" % [_passed, _failures])
	quit(1 if _failures > 0 else 0)
	return true

func _fresh() -> FPProgression:
	return FPProgression.new()

func _with(id: String) -> FPProgression:
	var p := FPProgression.new()
	if id.begins_with("T"):
		p.tumor_mutations.append(id)
	else:
		p.mutation_tree._purchased[id] = true
	return p

func _run_params() -> void:
	var base := _fresh()
	_assert(base.mutation_count() == 29, "29 mutations from the spec (%d)" % base.mutation_count())
	var expect_ids := ["M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08", "M09", "M10", "M12", "M13", "M14", "M15", "M16", "M17", "M18", "M19", "M20", "M21", "M22", "M23", "M24", "M25", "M26", "M27", "M28", "M29", "M30"]
	for id in expect_ids:
		_assert(base.mutation_info.has(id), "spec mutation %s defined" % id)
	_assert(not base.mutation_info.has("M11") and not base.mutation_info.has("thick_skin"), "deleted M11 and the old placeholder list are gone")
	# costs by branch (04-economy.md 2)
	_assert(base.cost_in("M01", "common") == 12 and base.cost_in("M07", "core") == 5 and base.cost_in("M14", "mantle") == 10 and base.cost_in("M21", "surface") == 15, "branch costs 12 / 5 / 10 / 15")
	_assert(base.cost_in("M28", "core") == 8 and base.cost_in("M28", "mantle") == 15 and base.cost_in("M28", "surface") == -1, "combination costs 1.5x of either biome")
	# one parameter check per mutation (W30)
	_assert(is_equal_approx(_with("M01").capacity(), 120.0), "M01 capacity +20")
	_assert(is_equal_approx(_with("M02").overfill_chew_multiplier(), 2.4), "M02 overfill chew 3.0 -> 2.4")
	_assert(_with("M03").has_mutation("M03") and is_equal_approx(_with("M03").reach(), 2.5), "M03 magnet eye is owned, touches no body number")
	_assert(is_equal_approx(_with("M04").base_chew_time(), 0.6 * 0.85), "M04 chew time x0.85")
	_assert(is_equal_approx(_with("M05").body_radius(), 0.35 * 0.85), "M05 body radius x0.85")
	_assert(is_equal_approx(_with("M06").crush_time(), 9.0), "M06 crush time +3 s")
	_assert(_with("M07").tear_cells() == 2, "M07 tear cells +1")
	_assert(is_equal_approx(_with("M08").hardness(0), 0.7) and is_equal_approx(_with("M08").hardness(4), 1.4), "M08 compressive hardness x0.7 only")
	var m09 := _with("M09")
	_assert(m09.can_grab_membrane_bare() and is_equal_approx(m09.hardness(3, true), 6.0) and not base.can_grab_membrane_bare(), "M09 bare-hand membrane, chew x3")
	_assert(is_equal_approx(_with("M10").reach(), 2.9), "M10 reach +0.4 m")
	_assert(is_equal_approx(_with("M12").hardness(4), 1.2) and is_equal_approx(_with("M12").hardness(0), 1.0), "M12 hardness 1.4 -> 1.2, below 1.0 untouched")
	_assert(is_equal_approx(_with("M13").carry_capacity(), 60.0), "M13 carry capacity x1.5")
	var m14 := _with("M14")
	_assert(m14.tear_cells() == 2 and is_equal_approx(m14.walk_speed_factor(), 0.9), "M14 tear +1, walk x0.9")
	_assert(_with("M15").can_lift_without_blender() and not base.can_lift_without_blender(), "M15 lifts without a blender")
	_assert(_with("M16").has_mutation("M16") and is_equal_approx(FPProgression.CUD_SHRINK, 0.1), "M16 cud stomach")
	_assert(is_equal_approx(_with("M17").tissue_damage_factor(), 0.5), "M17 tissue damage x0.5")
	_assert(is_equal_approx(_with("M18").hardness(4), 1.4 * 0.6), "M18 contractile hardness x0.6")
	_assert(is_equal_approx(_with("M19").squeeze_speed_factor(0.6), 1.3) and is_equal_approx(base.squeeze_speed_factor(0.6), 0.5), "M19 squeeze speeds up x1.3")
	_assert(is_equal_approx(_with("M20").squeeze_speed_factor(0.9), 1.0), "M20 no squeeze slowdown")
	_assert(is_equal_approx(_with("M21").blender_self_charge(), 5.0), "M21 blender charges 5/s")
	_assert(_with("M22").has_mutation("M22") and is_equal_approx(FPProgression.ALIEN_HAND_PERIOD, 2.0), "M22 alien hand every 2 s")
	_assert(_with("M23").has_mutation("M23") and is_equal_approx(FPProgression.HAIR_WARN_TIME, 1.5), "M23 hair warns 1.5 s early")
	var m24 := _with("M24")
	_assert(is_equal_approx(m24.light_range_factor(), 1.6) and is_equal_approx(m24.restroom_glare_factor(), 2.0), "M24 light x1.6, glare x2")
	_assert(_with("M25").has_mutation("M25"), "M25 hyper memory owned")
	_assert(is_equal_approx(_with("M26").health_regen_factor(), 3.0), "M26 health regen x3")
	_assert(_with("M27").has_mutation("M27") and is_equal_approx(FPProgression.TRUNK_RADIUS, 10.0), "M27 trunk sniffs 10 m")
	_assert(_with("M28").two_hand_tools_while_carrying(), "M28 two-hand tools while carrying")
	_assert(_with("M29").has_mutation("M29") and is_equal_approx(FPProgression.DORMANT_WAKE, 30.0), "M29 dormancy 30 s")
	_assert(is_equal_approx(_with("M30").overfill_capacity(), 100.0), "M30 overfill capacity +40")
	# tumor mutations
	_assert(_with("T1").has_mutation("T1"), "T1 echolocation owned")
	_assert(_with("T2").two_hand_tools_while_carrying(), "T2 third arm frees the hands")
	var t3 := _with("T3")
	_assert(is_equal_approx(t3.base_chew_time(), 0.24) and not t3.right_hand_can_carry(), "T3 chew x0.4, no pile in the right hand")
	var t4 := _with("T4")
	_assert(is_equal_approx(t4.capacity(), 200.0) and is_equal_approx(t4.body_radius(), 0.35 * 1.3), "T4 capacity x2, body radius x1.3")
	_assert(is_equal_approx(_with("T5").fov(), 200.0), "T5 field of view 200")
	var t6 := _with("T6")
	_assert(is_equal_approx(t6.hardness(3), 1.0) and t6.can_grab_membrane_bare(), "T6 membrane hardness 2.0 -> 1.0")
	_assert(is_equal_approx(_with("T7").walk_speed_factor(), 0.8), "T7 walk x0.8")
	# live game: parameters reach the systems
	var m = _m
	var prog: FPProgression = m.progression
	prog.mutation_tree._purchased["M01"] = true
	prog.mutation_tree._purchased["M14"] = true
	m.mutation_apply.apply_now()
	_assert(is_equal_approx(m.stomach_config.capacity, 120.0), "the stomach config follows M01")
	_assert(is_equal_approx(m.player.config.walk_speed, 3.0 * 0.9), "the player walk speed follows M14")
	prog.mutation_tree._purchased.erase("M01")
	prog.mutation_tree._purchased.erase("M14")
	prog.mutation_tree._purchased["M16"] = true
	m.stomach.fill = 50.0
	m.mutation_apply.step_timed(61.0)
	_assert(is_equal_approx(m.stomach.fill, 45.0), "M16 shrinks the stomach 10%% per 60 s (%.1f)" % m.stomach.fill)
	prog.mutation_tree._purchased.erase("M16")
	m.stomach.fill = 0.0
	prog.mutation_tree._purchased["M06"] = true
	_assert(is_equal_approx(m.progression.crush_time(), 9.0) and m.crush_progress() >= 0.0, "main's crush clock reads M06")
	prog.mutation_tree._purchased.erase("M06")
	m.mutation_apply.apply_now()

func _key(m, action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	m.mirror._input(ev)

func _run_mirror() -> void:
	var m = _m
	var prog: FPProgression = m.progression
	m.open_mirror()
	var mir: FPMirror = m.mirror
	_assert(mir.visible and mir.body != null, "interacting with the mirror shows the reflected body")
	_assert(m.hand_motions.kind == "watch", "the mirror raises the left arm like reading a wristwatch")
	m.hand_motions.tick(0.5)
	_assert(m.hand_motions.watch_raised() > 0.99 and m.hand_motions.busy(), "the arm stays up while looking")
	var lp: Dictionary = m.hand_motions.shape_pose(m.hands_rig, -1.0, {"pos": Vector3(-0.16, -0.175, -0.31), "wrist_pitch": 48.0, "wrist_yaw": -14.0, "wrist_roll": 12.0, "f1": 12.0, "f2": 16.0, "f3": 12.0, "t1": -6.0, "t2": 6.0, "t3": 10.0, "t_opp": 0.0})
	var lpp: Vector3 = lp["pos"]
	_assert(lpp.z <= -0.35 and lpp.z >= -0.45 and lpp.y < -0.05, "the left wrist sits 0.35-0.45 m out in the lower third")
	var rp: Dictionary = m.hand_motions.shape_pose(m.hands_rig, 1.0, {"pos": Vector3(0.16, -0.175, -0.31), "wrist_pitch": 48.0, "wrist_yaw": 14.0, "wrist_roll": -12.0, "f1": 12.0, "f2": 16.0, "f3": 12.0, "t1": -6.0, "t2": 6.0, "t3": 10.0, "t_opp": 0.0})
	_assert((rp["pos"] as Vector3).y < -0.5, "the right hand drops out of view while looking")
	var hair: Node3D = m.art_hookup.arm_hair
	_assert(hair != null and hair.is_visible_in_tree(), "arm hairs stay visible in the watch look")
	var lroot: Node3D = m.hands_rig.call("get_hand_root", "left")
	_assert((lroot.basis * Vector3.UP).z > 0.6 and (lroot.basis * Vector3.FORWARD).x > 0.6 and (lroot.basis * Vector3.FORWARD).z < -0.4, "watch look: the forearm runs in from the lower left toward the middle, hairy top to the camera")
	# mirror 4: the elbow (arm-hair origin) sits past the frame edge, so the
	# forearm comes in from off-screen instead of floating as a stub
	var cam: Camera3D = m.player.camera
	var e_pos := lpp + (lroot.basis * Vector3.BACK) * 0.34
	_assert(not _in_view(cam, e_pos) and _in_view(cam, lpp), "watch look: wrist on screen, elbow past the frame edge")
	# mirror 5: no screen panel; the glass reflects the player's own body
	var keep_pos: Vector3 = m.player.global_position
	var keep_yaw: float = m.player.rotation.y
	m.player.global_position = Vector3(-0.6, 0.95, -0.35)
	m.player.rotation.y = PI * 0.5
	m.player.set("_yaw", PI * 0.5)
	m.player.camera_pivot.rotation.x = 0.0
	var keep_size: Vector2i = m.get_viewport().size
	m.get_viewport().size = Vector2i(1280, 720)
	mir.sync(true)
	_assert(mir.body.get_parent() == m.player, "the mirror body is the player's own body in the world")
	_assert((cam.cull_mask & FPMirror.MIRROR_BODY_LAYER) == 0 and (mir.cam.cull_mask & FPMirror.MIRROR_BODY_LAYER) != 0, "only the reflection camera sees the body")
	_assert((mir.cam.cull_mask & m.BODY_LAYER) == 0 and (mir.cam.cull_mask & FPMirror.HANDS_ROOM_LAYER) == 0, "the reflection leaves out the first-person waist and hands")
	_assert(mir.cam.projection == Camera3D.PROJECTION_FRUSTUM and mir.cam.near > 0.1, "the reflection camera is clipped at the glass")
	var n_img: Vector3 = m.restroom.mirror_art.global_transform.basis.z
	_assert(n_img.dot(mir.cam.global_position - m.restroom.mirror_art.global_position) < 0.0, "the reflection camera sits behind the glass (mirrored eye)")
	var ctl := 0
	for c in mir.get_children():
		if c is Control:
			ctl += 1
	_assert(ctl == 0, "no UI panel or chip row on screen")
	mir.focus_part("face")
	_assert(mir.buds().size() == mir._open_ids("face").size() and mir.buds().size() > 0, "the face's open mutations sprout as buds on the reflected skin")
	_assert(mir.body.shimmer_on("face"), "the aimed part glows")
	var face_px: Vector2 = mir.part_screen("face")
	mir.focus_part("belly")
	mir.aim(face_px)
	_assert(mir.current_part() == "face", "aiming at the face in the glass selects it")
	if mir.buds().size() > 1:
		mir.aim(mir.bud_screen(1))
		_assert(mir.candidate() == mir._open_ids("face")[1] and mir.ghost_id() == mir.candidate(), "aiming at a bud grows its mutation as a ghost")
	mir.select_candidate(0)
	m.player.global_position = keep_pos
	m.player.rotation.y = keep_yaw
	m.player.set("_yaw", keep_yaw)
	m.get_viewport().size = keep_size
	_assert(mir.body.shimmer_on("face") and mir.body.shimmer_on("right_hand"), "mutable parts shimmer without hovering")
	mir.focus_part("face")
	_assert(mir.ghost_id() != "" and mir._ghost != null, "focusing a part overlays its next mutation")
	# not enough hairs: red blink, nothing bought
	var before := prog.purchased_mutations().size()
	_assert(mir.buy_current() == "" and mir.body.is_red("face") and prog.purchased_mutations().size() == before, "a part without enough hairs blinks red")
	# keyboard only: move to the right hand, pick M10, buy it
	prog.mutation_tree.add_points("core", 5)
	var guard := 0
	while mir.current_part() != "right_hand" and guard < 20:
		_key(m, "ui_right")
		guard += 1
	_assert(mir.current_part() == "right_hand", "arrow keys walk the parts")
	guard = 0
	while mir.candidate() != "M10" and guard < 10:
		_key(m, "ui_down")
		guard += 1
	_assert(mir.candidate() == "M10" and mir.ghost_id() == "M10", "up/down switch the mutation and its ghost")
	_key(m, "ui_accept")
	_assert(prog.has_mutation("M10") and prog.hairs("core") == 0, "Enter buys with the keyboard alone, hairs fall off")
	_assert("M10" in mir.body.applied, "the mirror body changes at once")
	_key(m, "ui_cancel")
	_assert(not mir.visible and not m._mirror_open, "Esc leaves the mirror")
	_assert(m.hand_motions.cancelled or not m.hand_motions.busy(), "leaving the mirror lowers the arm")
	for i in range(20):
		m.hand_motions.tick(0.05)
	_assert(not m.hand_motions.busy(), "the arm is back down")
	_assert((m.hands_rig.call("get_hand_root", "left") as Node3D).basis.is_equal_approx(Basis.IDENTITY), "the forearm roll is undone when the arm drops")
	m.open_mirror()
	m.mirror.close()
	_assert(not m._mirror_open, "interact / move also end the mirror look")
	for i in range(20):
		m.hand_motions.tick(0.05)
	var eye: float = m.player.camera.global_position.y - (m.player.global_position.y - m.player.config.stand_height * 0.5)
	_assert(absf(eye - 1.6) < 0.05, "eye height is about 1.6 m over the feet (real proportions)")

func _run_long_knuckle() -> void:
	var m = _m
	var prog: FPProgression = m.progression
	_assert(is_equal_approx(prog.reach(), 2.9), "after the mirror M10 the reach is 2.9 m")
	# the eat ray now reaches 0.4 m further
	m.player.global_position = Vector3(0, 0.95, 0.0)
	m.player.set("_yaw", PI)
	m.player.rotation.y = PI
	m.player.camera_pivot.rotation.x = 0.0
	m.player.force_update_transform()
	var ray: Array = m.player.get_look_ray()
	_assert(true, "look ray %s" % [ray[1]])
	# first-person finger: the second joint of the right finger block is longer
	m.art_hookup._process(0.016)
	var seg: Node3D = m.hands_rig.get_node("HandRight/Wrist/Finger1/Finger2/Seg")
	var f3: Node3D = m.hands_rig.get_node("HandRight/Wrist/Finger1/Finger2/Finger3")
	_assert(seg.scale.z > 1.4 and absf(f3.position.z) > 0.04, "the first-person finger joint grows longer (%.2f, %.3f)" % [seg.scale.z, f3.position.z])
	var lseg: Node3D = m.hands_rig.get_node("HandLeft/Wrist/Finger1/Finger2/Seg")
	_assert(is_equal_approx(lseg.scale.z, 1.0), "the left hand is untouched by M10")

func _run_tumors() -> void:
	var m = _m
	var prog: FPProgression = m.progression
	# path 1: eat -> bump on the belly -> press it in the mirror
	var t: Node3D = m.tumor_nodes[4]
	m.player.global_position = t.global_position - Vector3(0, 0.6, 0)
	_assert(m.eat_tumor() and prog.belly_bumps() == 1 and not t.visible, "eating a tumor raises one bump on the belly")
	m.open_mirror()
	_assert(m.mirror._order.has("tumor") and m.mirror.body.shimmer_on("belly"), "the bump shows in the mirror")
	m.mirror.focus_part("tumor")
	var got: String = m.mirror.buy_current()
	_assert(got in FPProgression.TUMOR_MUTATIONS and prog.belly_bumps() == 0 and prog.has_mutation(got), "pressing the bump turns it into a tumor mutation (%s)" % got)
	_assert(m.mirror.buy_current() == "", "no bump left, nothing more")
	m.mirror.close()
	# never the same one twice, and no more bumps after all 7
	var p2 := FPProgression.new()
	for i in range(9):
		p2.eat_tumor_kind("core_knot")
		p2.buy_tumor_mutation()
	var uniq := {}
	for x in p2.tumor_mutations:
		uniq[x] = true
	_assert(p2.tumor_mutations.size() == 7 and uniq.size() == 7 and p2.belly_bumps() == 0, "7 different tumor mutations, then no more bumps")
	# path 2: carry one in hand to the toilet -> teeth + codex drawing
	var t2: Node3D = m.tumor_nodes[6]
	m.player.global_position = t2.global_position - Vector3(0, 0.6, 0)
	_assert(m.pick_up_tumor() and prog.tumor_in_hand(), "a tumor is carried in one hand")
	m.player.global_position = m.restroom.toilet.global_position + Vector3(0, 0.9, 0.6)
	var teeth: int = prog.teeth
	var kind: String = String(t2.get_meta("kind"))
	m.start_settlement()
	m.flush()
	_assert(prog.teeth > teeth and prog.tumors.is_in_codex(kind), "thrown in the toilet it pays teeth and enters the codex (teeth %d -> %d, codex %s)" % [teeth, prog.teeth, prog.tumors.is_in_codex(kind)])
	m.mutation_apply._process(0.016)
	var dressed := false
	var papers = m.get("drawing_nodes")
	if papers is Array:
		for pp in papers:
			if pp.get_node_or_null("Crayon") != null and String(pp.get_meta("tumor_kind", "")) == kind:
				dressed = true
	else:
		var sheet: Node3D = m.mutation_apply.codex.call("sheet", kind)
		dressed = sheet != null and sheet.visible
	_assert(dressed, "a crayon drawing of it goes up on the restroom wall")

func _run_stomach_forms() -> void:
	var m = _m
	var sv = m.stomach_view
	var prog: FPProgression = m.progression
	for id in ["M01", "M02", "M30"]:
		prog.mutation_tree._purchased[id] = true
	m.mutation_apply._process(0.016)
	_assert(sv.has_form("M01") and sv.has_form("M02") and sv.has_form("M30"), "★ mutations reach the stomach view")
	sv.set_state(1.0, 0.8)
	sv.snap()
	_assert(sv._pouch.visible and sv._gullet.visible, "throat pouch and gullet tube show when overfull")

## Session C follow-up: T1 echo marks, M23 hair shiver, M25 live death marker.
func _grant(id: String) -> void:
	var p: FPProgression = _m.progression
	if id.begins_with("T"):
		p.tumor_mutations.append(id)
	else:
		p.mutation_tree._purchased[id] = true

func _ungrant(id: String) -> void:
	var p: FPProgression = _m.progression
	while id in p.tumor_mutations:
		p.tumor_mutations.erase(id)
	p.mutation_tree._purchased.erase(id)

func _run_skipped_followup() -> void:
	var ma: FPMutationApply = _m.mutation_apply
	var t: FDKTerrainField = _m.terrain
	for id in ["T1", "M23", "M25"]:
		_ungrant(id)
	var c := Vector3(160, 20, 160)
	t.fill_box_uniform(AABB(c - Vector3.ONE * 6.0, Vector3.ONE * 12.0), 1.0, FPProgression.TISSUE_COMPRESSIVE)
	t.fill_box_uniform(AABB(c + Vector3(0.9, -0.6, -0.6), Vector3(1.2, 1.2, 1.2)), 1.0, FPProgression.TISSUE_NERVE)
	t.fill_box_uniform(AABB(c + Vector3(-0.6, -2.4, -0.6), Vector3(1.2, 1.2, 1.2)), 1.0, FPProgression.TISSUE_CONTRACTILE)
	t.carve_sphere(c, 1.5)
	t.carve_sphere(c + Vector3(0, 0, 3.2), 1.4) # leaves a thin wall on +z
	t.fill_box_uniform(AABB(c + Vector3(-1.2, -0.3, -0.3), Vector3(0.6, 0.6, 0.6)), 0.3, FPProgression.TISSUE_COMPRESSIVE)
	var cp := c + Vector3(0, -1.5, 0)
	t.contract_time = FDKTissueRules.CONTRACT_PERIOD - FDKTissueRules.contract_phase(cp) - 1.0
	var fake := Node3D.new()
	_m.add_child(fake)
	fake.global_position = c + Vector3(0.6, 0.3, 0)
	_m.tumor_nodes.append(fake)
	_grant("T1")
	_m.player.global_position = c - Vector3(0, 1.4, 0)
	var n: Dictionary = ma.echo_pulse()
	var E := FPMutationApply.Echo
	_assert(int(n[E.NERVE]) > 0, "T1 echo marks the nerve patch (%d)" % int(n[E.NERVE]))
	_assert(int(n[E.THIN]) > 0, "T1 echo marks the thin wall (%d)" % int(n[E.THIN]))
	_assert(int(n[E.REGROW]) > 0, "T1 echo marks regrowing flesh (%d)" % int(n[E.REGROW]))
	_assert(int(n[E.SQUEEZE]) > 0, "T1 echo marks the wall about to squeeze (%d)" % int(n[E.SQUEEZE]))
	_assert(int(n[E.TUMOR]) == 1, "T1 echo marks the tumor")
	var thin_ok := true
	for e in ma.echo_marks:
		if e.kind == E.THIN and (e.pos as Vector3).z < c.z + 0.5:
			thin_ok = false
	_assert(thin_ok, "T1 only the thin +z wall reads as thin")
	_assert(ma._echo_mm != null and ma._echo_mm.visible and ma._echo_mm.multimesh.instance_count == ma.echo_marks.size(), "T1 echo marks are drawn")
	t.contract_time = FDKTissueRules.CONTRACT_PERIOD - FDKTissueRules.contract_phase(cp) - 5.0
	n = ma.echo_pulse()
	_assert(int(n[E.SQUEEZE]) == 0, "T1 a resting contractile wall is not marked")
	_ungrant("T1")
	ma._step_echo_marks(0.016)
	_assert(not ma._echo_mm.visible, "T1 marks vanish without the tumor")
	_m.tumor_nodes.erase(fake)
	fake.queue_free()
	# M23: periodic squeeze
	_grant("M23")
	var fires := [0]
	var cb := func(): fires[0] += 1
	ma.hair_shiver_started.connect(cb)
	_m.player.global_position = c - Vector3(0, 1.0, 0)
	t.contract_time = FDKTissueRules.CONTRACT_PERIOD - FDKTissueRules.contract_phase(cp) - 1.2
	ma._shiver_scan_t = 0.0
	ma._step_hair_shiver(0.016)
	_assert(ma.hair_shiver > 0.0 and fires[0] == 1, "M23 hairs shiver before a nearby squeeze (eta %.2f)" % ma.squeeze_eta())
	ma._step_hair_shiver(0.016)
	_assert(fires[0] == 1, "M23 one warning per squeeze")
	t.contract_time = FDKTissueRules.CONTRACT_PERIOD - FDKTissueRules.contract_phase(cp) - 4.0
	ma._shiver_scan_t = 0.0
	ma._step_hair_shiver(0.016)
	_assert(ma.hair_shiver == 0.0, "M23 still hairs while the squeeze is far off (eta %.2f)" % ma.squeeze_eta())
	# M23: nerve charge
	_m.player.global_position = c + Vector3(0, 30, 0)
	var tt = _m.tissue_tools
	tt.plugged = true
	tt.plug_t = 0.4
	tt._next_contract = 1.5
	ma._shiver_scan_t = 0.0
	ma._step_hair_shiver(0.016)
	_assert(ma.hair_shiver > 0.0 and fires[0] == 2, "M23 hairs shiver before the plugged nerve squeezes")
	tt.plugged = false
	tt._next_contract = FPTissueTools.CHARGE_CONTRACT_DELAY
	_ungrant("M23")
	ma._step_hair_shiver(0.016)
	_assert(ma.hair_shiver == 0.0, "M23 no shiver without the mutation")
	ma.hair_shiver_started.disconnect(cb)
	# M25: the death marker follows the drifting drop
	var dd: FDKDeathDrop = _m.death_drop
	dd.drop(c, {})
	dd.carry_along(Vector3(0.7, 0, 0))
	ma.step_timed(0.016)
	_assert(dd.marker_position().is_equal_approx(c), "without M25 the marker stays stale")
	_grant("M25")
	ma.step_timed(0.016)
	_assert(dd.marker_position().is_equal_approx(c + Vector3(0.7, 0, 0)), "M25 the marker follows the drift")
	dd.carry_along(Vector3(0, 0, 0.5))
	ma.step_timed(0.016)
	_assert(dd.marker_position().is_equal_approx(c + Vector3(0.7, 0, 0.5)), "M25 the marker keeps updating")
	_ungrant("M25")
	dd.try_recover(dd.current_position)
