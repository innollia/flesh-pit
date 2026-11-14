extends SceneTree

## Rest buckets, carrying teeth home and the tooth pouch (decision 0016).
## Real Main, real terrain. A rest's bucket keeps the teeth of a stomach
## vomited there; they are the player's only once carried into the restroom.
## Out of the restroom the hand full of teeth does nothing else, unless the
## pouch at the waist has them. The seven rests stand at fixed places.
## Save and key files are this suite's own.

const RestArt := preload("res://main/art/fp_rest_container.gd")
const PouchScene := preload("res://main/art/fp_tooth_pouch.tscn")
const LEFT := FDKToolKit.Hand.LEFT
const RIGHT := FDKToolKit.Hand.RIGHT
const SAVE := "user://rest_pouch_test_save.bin"

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_rest_pouch.json"
	m.save_path = SAVE
	get_root().add_child(m)
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func look(yaw: float, pitch: float) -> void:
	m.player.rotation.y = yaw
	m.player.set("_yaw", yaw)
	m.player.camera_pivot.rotation.x = pitch
	m.player.set("_pitch", pitch)
	m.player.force_update_transform()

## Plays out whatever the hands and the eye are in the middle of (a vomit, a
## reach into the bucket): Main's own process is off in this suite.
func settle_motions() -> void:
	for i in range(80):
		m.hand_motions.tick(0.05)
	m.player.force_update_transform()

func box_dist(p: Vector3, c: Vector3, half: Vector3) -> float:
	var q := (p - c).abs() - half
	return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()

## The AABB of everything drawn under `n`, in `space`'s frame.
func box_of(n: Node3D, space: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var list: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		list.append(n)
	for mi in list:
		var v := mi as MeshInstance3D
		if v.mesh == null or not v.is_visible_in_tree():
			continue
		var b: AABB = (space.global_transform.affine_inverse() * v.global_transform) * v.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

func _run() -> void:
	for i in range(5):
		await process_frame
	if m.save_path == "user://save.bin":
		m.save_path = SAVE
	m.finish_opening()
	m.set_process(false)
	m.player.set_physics_process(false)
	_layout()
	await _tunnel()
	await _bucket()
	_lead_lock()
	await _pouch()
	await _waist()
	print("--- rest and pouch: %d passed, %d failed ---" % [passed, failed])
	quit(1 if failed > 0 else 0)

# --- the fixed layout ---------------------------------------------------------

func _layout() -> void:
	var c: Vector3 = m.RESTROOM_CENTER
	var rp: Array[Vector3] = m.rest_points
	var rh: Array[Vector3] = m.rest_halves
	check(rp.size() == 7 and rh.size() == 7 and FPWorldFeatures.rest_count() == 7 and m.rest_cans.size() == 7 and m.rest_buckets.size() == 7 and m.rest_teeth.size() == 7, "seven rests, each with a can and a bucket")
	var per := [0, 0, 0]
	var shell_ok := true
	for i in range(rp.size()):
		per[FPWorldFeatures.rest_shell(i)] += 1
		if FPWorldFeatures.shell_of_depth(rp[i].distance_to(c)) != FPWorldFeatures.rest_shell(i):
			shell_ok = false
	check(per == FPWorldFeatures.REST_PER_SHELL and per[0] == 0 and shell_ok, "no rest in the core; the table and REST_PER_SHELL agree (%s)" % str(per))
	var thick: float = FPWorldFeatures.SHELL_THICKNESS
	var corners_ok := true
	var tumor_gap := INF
	for i in range(rp.size()):
		var s := FPWorldFeatures.rest_shell(i)
		for k in range(8):
			var corner := rp[i] + Vector3(rh[i].x * (1.0 if k & 1 else -1.0), rh[i].y * (1.0 if k & 2 else -1.0), rh[i].z * (1.0 if k & 4 else -1.0))
			var d := corner.distance_to(c)
			if d <= s * thick or d >= (s + 1) * thick - FPWorldFeatures.BOUNDARY_BAND:
				corners_ok = false
				print("  rest %d corner at depth %.2f" % [i, d])
		for t in m.tumor_nodes:
			tumor_gap = minf(tumor_gap, box_dist((t as Node3D).global_position, rp[i], rh[i]))
	check(corners_ok, "every box corner lies in its own shell, clear of the membrane band")
	check(tumor_gap >= 3.0, "no tumor within 3 m of a rest box (nearest %.2f m)" % tumor_gap)
	var on := 0
	for s in m.biomes.structures:
		if bool(s["enabled"]):
			on += 1
	check(m.biomes.structures.size() == 16 and on == 16, "all 16 structures stand beside the fixed rests (%d)" % on)
	# the two stem rests: the door hole on the restroom's door axis, its face
	# just behind the membrane of the shell before it
	var door_mid := Vector3((RestArt.DOOR_X0 + RestArt.DOOR_X1) * 0.5, 1.0, RestArt.Wd)
	var want_depth := {0: 9.9, 3: 18.9}
	for i: int in want_depth:
		var at: Vector3 = rp[i] + FPWorldFeatures.rest_local(i, door_mid)
		var art: Node3D = m.rest_cans[i].get_parent().get_node("ContainerArt")
		check((art.global_transform * door_mid).distance_to(at) < 0.001, "rest %d: the drawn door is where the layout says" % i)
		check(absf(at.x - c.x) <= 0.1 and absf((at.z - c.z) - float(want_depth[i])) <= 0.05, "stem rest %d: door hole on the door axis, %.2f m out (x %.2f)" % [i, at.z - c.z, at.x])
		check(absf(at.z - (rp[i].z - rh[i].z)) < 0.001, "stem rest %d: the door is on the wall that faces the restroom" % i)
	for i in range(rp.size()):
		check(is_equal_approx(m._world_density(rp[i]), 0.0) and m.in_rest(rp[i]) and FPWorldFeatures.rest_at(rp[i], rp, rh) == i, "rest %d is hollow and knows itself" % i)
		check(m.in_rest(m.rest_stand_point(i)) and m.in_rest(m.rest_cans[i].global_position), "rest %d: bucket spot and can are inside its box" % i)
		m.player.global_position = m.rest_stand_point(i)
		m._crush_t = 3.0
		m._step_hazards(0.1)
		check(m._crush_t == 0.0, "rest %d: the crush never builds inside" % i)
		var want := "spray_cheap" if i == 0 or i == 3 else "spray_deep"
		check(String(m.rest_cans[i].get_meta("loot")) == want and FPWorldFeatures.rest_loot(i) == want, "rest %d holds a %s" % [i, want])
	m._crush_t = 0.0

## Straight out of the door, a one-cell tunnel 9.9 m long ends inside the
## mantle stem rest.
func _tunnel() -> void:
	var c: Vector3 = m.RESTROOM_CENTER
	var iso: float = m.terrain_config.iso_level
	check(m.terrain.density_at(Vector3(0.0, c.y, 9.5)) >= iso, "before digging there is flesh in front of the stem rest's door")
	var z: float = FPRestroom.HALF.z
	while z <= 9.9:
		m.terrain.dig_at(Vector3(0.0, c.y, z), 0.5)
		z += 0.25
	for i in range(4):
		await physics_frame
	var open := true
	z = FPRestroom.HALF.z + 0.3
	while z <= 11.0:
		if m.terrain.density_at(Vector3(0.0, c.y, z)) >= iso:
			open = false
			print("  flesh left at z ", z)
		z += 0.25
	check(open, "the tunnel runs on into the container with no flesh in the door hole")
	var body: float = m.player.body_radius()
	check(m.in_rest(Vector3(0.0, 0.95, 9.9 + body + 0.05)) and FPWorldFeatures.rest_at(Vector3(0.0, 0.95, 9.9 + body + 0.05), m.rest_points, m.rest_halves) == 0, "a body one step past the door face stands inside the mantle stem rest")
	var door_x0: float = (m.rest_points[0] + FPWorldFeatures.rest_local(0, Vector3(RestArt.DOOR_X0, 0, RestArt.Wd))).x
	var door_x1: float = (m.rest_points[0] + FPWorldFeatures.rest_local(0, Vector3(RestArt.DOOR_X1, 0, RestArt.Wd))).x
	check(minf(absf(door_x0), absf(door_x1)) >= 0.35, "the door hole is wider than the body on both sides of the axis (%.2f, %.2f)" % [door_x0, door_x1])

# --- the bucket and the hand ----------------------------------------------------

func _bucket() -> void:
	var prog: FPProgression = m.progression
	var flushes := [0]
	var vomits := []
	var heaves := [0]
	var refused := [0]
	m.flushed.connect(func(_t, _h): flushes[0] += 1)
	m.rest_vomited.connect(func(r, n): vomits.append([r, n]))
	m.dry_heaved.connect(func(): heaves[0] += 1)
	m.belt_refused.connect(func(): refused[0] += 1)
	prog.teeth = 5
	prog.teeth_in_hand = 0
	var lever0: bool = m.lever_settled
	m.player.global_position = m.rest_stand_point(0)
	look(0.0, 0.5)
	check(m._near_rest_point() == 0 and m.settle_spot_here(), "at the stem rest's empty bucket V has somewhere to go")
	m.stomach.add_flesh(100.0)
	prog.on_flesh_eaten(1, 100)
	m.request_vomit()
	check(prog.teeth == 5 and m.rest_teeth[0] == 8 and m.stomach.fill == 0.0, "100 u vomited at a rest: 8 teeth in its bucket, the tank untouched (%d, %d)" % [prog.teeth, m.rest_teeth[0]])
	check(flushes[0] == 0 and vomits == [[0, 8]] and m.lever_settled == lever0 and not m.is_settling(), "no flush, no settlement: one rest_vomited(0, 8)")
	check(prog.total_hairs() >= 0 and prog.pending_hair_total() == 0, "the stomach's pending share is gone with it")
	m._update_rest_teeth()
	check(m.rest_piles[0].count == 8 and m.rest_piles[0].shown() == 8, "the bucket shows eight teeth")
	check((m.serialize()["rest_teeth"] as Array)[0] == 8, "they are in the save")
	# a bucket that holds teeth takes no second stomach
	m.stomach.add_flesh(40.0)
	m.request_vomit()
	check(is_equal_approx(m.stomach.fill, 40.0) and m.rest_teeth[0] == 8 and heaves[0] == 1 and vomits.size() == 1, "V over a bucket with teeth in it: a dry heave, the stomach stays")
	check(not m.settle_spot_here() and m.rest_piles[0].shaking(), "the vomit key has nowhere to go there, and the pile shivers")
	check(FPInteractions.get_candidates(m).any(func(cd): return cd[0] == "rest_teeth"), "the bucket's teeth are something to reach for")
	# hands that cannot take a tooth
	m.carried_flesh = 5.0
	check(m.take_rest_tooth() == 0 and m.rest_teeth[0] == 8 and refused[0] == 1, "hands under a flesh pile come back empty")
	m.carried_flesh = 0.0
	# the knife in the right hand makes way for the first tooth
	prog.grant_item("knife")
	prog.grant_item("blender")
	prog.has_belt = true
	check(m.equip_hand("knife", RIGHT) and prog.hands.right == "knife" and prog.hands.left == "", "fixture: the knife in the right hand")
	check(not m.palm_blocked(), "no teeth carried: the palm is free")
	check(m.take_rest_tooth() == 1 and prog.teeth_in_hand == 1 and m.rest_teeth[0] == 7, "one tooth out of the bucket")
	check(m.palm_blocked() and prog.palm_teeth_blocks, "out of the restroom, no pouch: the palm is taken")
	check(prog.hands.right == "" and prog.hands.left == "knife", "the knife went to the empty left hand")
	check(not m.equip_hand("knife", RIGHT) and prog.hands.right == "" and prog.hands.left == "knife", "the hand full of teeth takes no tool")
	m.toggle_carry()
	check(not m.carry_mode, "and does not carry flesh")
	for i in range(7):
		m.take_rest_tooth()
	check(m.rest_teeth[0] == 0 and prog.teeth_in_hand == 8 and m.take_rest_tooth() == 0, "eight picks empty the bucket into the hand")
	for i in range(3):
		m.put_rest_tooth()
	check(m.rest_teeth[0] == 3 and prog.teeth_in_hand == 5, "three put back: 3 in the bucket, 5 in the hand")
	check(m.rest_teeth[0] + prog.teeth_in_hand == 8 and prog.teeth == 5, "no tooth made or lost on the way")
	for i in range(3):
		m.take_rest_tooth()
	check(m.settle_spot_here(), "the emptied bucket takes a stomach again")
	m.stomach.vomit()
	m.stomach.add_flesh(6.0)
	m.request_vomit()
	check(m.rest_teeth[0] == 0 and m.stomach.fill == 0.0 and vomits.size() == 2 and vomits[1] == [0, 0] and m.settle_spot_here(), "6 u is no tooth: the bucket stays empty and V works again")
	# what the buttons do with the palm full
	settle_motions()
	look(0.0, 0.5)
	check(FPInteractions.plan(m, FPInteractions.SOURCE_RIGHT) == "hold_teeth" and FPInteractions.plan(m, FPInteractions.SOURCE_LEFT) == "dig", "right closes over the teeth, left digs (%s, %s)" % [FPInteractions.plan(m, FPInteractions.SOURCE_RIGHT), FPInteractions.plan(m, FPInteractions.SOURCE_LEFT)])
	check(FPInteractions.blocks_hand("hold_teeth"), "a held right button never turns into digging")
	# out in the flesh: the right hand clutches, the left alone tears
	prog.hands.set_item("", LEFT)
	prog.tools.equipped = ""
	var out := Vector3(0.0, 0.95, FPRestroom.HALF.z + 3.0)
	m.player.global_position = out
	settle_motions()
	look(-PI * 0.5, 0.0) # the tunnel's wall, an arm's length away
	for i in range(6):
		await physics_frame
	var hit: Dictionary = m._look_hit()
	check(not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk") and m.player.camera.global_position.distance_to(hit.position) < 1.5, "fixture: in the tunnel, its flesh wall in reach")
	check(not m.restroom.contains(out) and m.palm_blocked() and m.player.camera.global_position.distance_to(out) < 0.8, "fixture: out of the restroom with teeth on the palm")
	var torn: Array = []
	m.chewer.cell_torn.connect(func(p): torn.append(p))
	var fill0: float = m.stomach.fill
	await process_frame
	Input.action_press("fp_pick")
	m.hand_actions.tick(1.0 / 60.0)
	check(m.hand_motions._clutch_t >= 0.0 and m.hand_actions.blocked[RIGHT], "the right button starts the clutch and blocks the hand")
	m.hand_motions.tick(m.hand_motions.CLUTCH_TIME * 0.5)
	var cup: Dictionary = m.hand_motions._cup_teeth(m.hands_rig, {})
	check(m.hand_motions.clutch() > 0.9 and absf(float(cup["f1"]) - (26.0 + m.hand_motions.CLUTCH_CURL * m.hand_motions.clutch())) < 0.01, "half way the fingers are 20 degrees further closed over the teeth")
	for f in range(90):
		m.hand_actions.tick(1.0 / 60.0)
		await physics_frame
	check(torn.is_empty() and is_equal_approx(m.stomach.fill, fill0) and not m.chewer.is_chewing(), "held 1.5 s the right hand tears nothing")
	m.hand_motions.tick(m.hand_motions.CLUTCH_TIME)
	check(m.hand_motions.clutch() == 0.0, "the clutch opens again by itself")
	Input.action_release("fp_pick")
	m.hand_actions.tick(0.0)
	Input.action_press("fdk_eat")
	for f in range(420):
		m.hand_actions.tick(1.0 / 60.0)
		await physics_frame
		if torn.size() >= 2:
			break
	Input.action_release("fdk_eat")
	m.hand_actions.tick(0.0)
	check(torn.size() >= 1, "the left hand alone tears flesh (%d cells)" % torn.size())
	check(is_equal_approx(m.stomach.fill - fill0, torn.size() * m.stomach_config.flesh_per_cell), "the stomach rose by exactly what was torn out (%.2f for %d cells)" % [m.stomach.fill - fill0, torn.size()])
	var holes := true
	for p in torn:
		if m.terrain.density_at(p) >= m.terrain_config.iso_level:
			holes = false
	check(holes, "every torn cell is a hole in the flesh")
	check(m.hands_rig.lead_lock == FPHandActions.RIG_LEFT and m.hands_rig._lead == FPHandActions.RIG_LEFT, "the left hand led every bite (lead %d)" % m.hands_rig._lead)
	var cupped: Dictionary = m.hand_motions._cup_teeth(m.hands_rig, {"pos": Vector3.ZERO})
	check(cupped.has("f1") and (cupped["pos"] as Vector3) == m.hand_motions.HOLD_TEETH_POS, "the right hand stayed cupped under the teeth while the left worked")
	# in the restroom the hand is a hand again
	m.player.global_position = m.START_POS
	m.hand_actions.tick(0.0)
	m._step_palm_teeth()
	check(not m.palm_blocked() and not prog.palm_teeth_blocks and m.hands_rig.lead_lock == -1, "inside the restroom nothing is blocked")
	check(FPInteractions.plan(m, FPInteractions.SOURCE_RIGHT) == FPInteractions._plan(m, FPInteractions.SOURCE_RIGHT), "and the right button does what it always did")
	check(m.equip_hand("knife", RIGHT) and prog.hands.right == "knife", "the right hand takes the knife there")
	# stepping out with the knife in that hand: it goes to the left
	m.player.global_position = out
	m._step_palm_teeth()
	check(m.palm_blocked() and prog.hands.right == "" and prog.hands.left == "knife", "stepping out of the door the knife changes hands")
	# death: every carried tooth lies with the body, the tank keeps its own
	m.stomach.vomit()
	prog.teeth_in_hand = 8
	var tank: int = prog.teeth
	m.die("crush")
	var body: FDKDeathDrop = m.death_drop
	check(int(body.items.get("teeth_in_hand", 0)) == 8 and prog.teeth_in_hand == 0 and prog.teeth == tank, "dying with 8 teeth in the hand leaves all 8 on the body")
	check(m.restroom.contains(m.player.global_position) and not m.palm_blocked(), "and wakes in the restroom with an empty hand")
	m.player.global_position = body.current_position
	m._step_death_drop(0.016)
	check(prog.teeth_in_hand == 8 and prog.teeth == tank, "reaching the body gives the 8 back to the hand")
	m._step_palm_teeth()
	check(m.palm_blocked(), "and the palm is taken again")
	# they are the player's once put in the tank
	m.player.global_position = m.START_POS
	var back := 0
	for i in range(8):
		back += m.put_tooth_back()
	check(back == 8 and prog.teeth == tank + 8 and prog.teeth_in_hand == 0, "eight teeth put in the tank: the tank is 8 richer")

## FDKHandsRig.lead_lock: the kit's own flag, no teeth involved.
func _lead_lock() -> void:
	var rig := FDKHandsRig.new()
	get_root().add_child(rig)
	rig.set_process(false)
	rig.build()
	rig.lead_lock = 1
	rig.step(0.01)
	var stays := rig._lead == 1
	for n in range(3):
		rig.on_grab_started()
		rig.on_cell_torn()
		rig.step(FDKHandsRig.TEAR_TIME + 0.01)
		if rig._lead != 1:
			stays = false
	check(stays, "a locked lead hand leads tear after tear")
	rig.lead_lock = -1
	rig.on_cell_torn()
	rig.step(FDKHandsRig.TEAR_TIME + 0.01)
	var first := rig._lead
	rig.on_cell_torn()
	rig.step(FDKHandsRig.TEAR_TIME + 0.01)
	check(first == 0 and rig._lead == 1, "unlocked, the hands take turns again")
	rig.queue_free()

# --- the pouch ------------------------------------------------------------------

func _pouch() -> void:
	var prog: FPProgression = m.progression
	check(prog.price_for("pouch") == 16, "the pouch costs 16 teeth (%d)" % prog.price_for("pouch"))
	var fresh := FPProgression.new()
	check(fresh.vent_offer(8)[0] == "knife", "in the core 8 teeth still bring the knife first")
	fresh.grant_item("knife")
	fresh.deepest_shell = 0
	check(not fresh.vent_offer(16).has("pouch"), "the pouch is not offered before the mantle")
	fresh.deepest_shell = 1
	check(fresh.vent_offer(16)[0] == "pouch", "in the mantle 16 teeth bring the pouch first (%s)" % str(fresh.vent_offer(16)))
	fresh.grant_item("pouch")
	check(fresh.has_pouch and not fresh.vent_offer(16).has("pouch") and not fresh.vent_offer(64).has("pouch"), "once owned it is not offered again")
	var kept: Dictionary = fresh.serialize()
	var loaded := FPProgression.new()
	loaded.deserialize(kept)
	check(loaded.has_pouch and not FPProgression.new().has_pouch, "the pouch is saved with the run")
	var art: Node3D = FPItemArt.make("pouch")
	check(art != null and FPVent.ART_KIND.get("pouch", "") == "pouch", "the vent being has a pouch to hold out")
	if art != null:
		art.free()
	# out of the restroom the pouch has the teeth and both hands work
	var out := Vector3(0.0, 0.95, FPRestroom.HALF.z + 3.0)
	prog.grant_item("pouch")
	prog.teeth_in_hand = 8
	m.player.global_position = out
	look(-PI * 0.5, 0.0)
	m._step_palm_teeth()
	m.hand_actions.tick(0.0)
	for i in range(3):
		await process_frame
	check(prog.has_pouch and m.teeth_in_pouch() and not m.palm_blocked() and not prog.palm_teeth_blocks and m.hands_rig.lead_lock == -1, "with the pouch the palm is free out in the flesh")
	check(FPInteractions.plan(m, FPInteractions.SOURCE_RIGHT) == "dig", "the right hand digs (%s)" % FPInteractions.plan(m, FPInteractions.SOURCE_RIGHT))
	check(m.equip_hand("knife", RIGHT), "and takes a tool")
	var pouch: Node3D = m.art_hookup.pouch
	check(pouch.visible and int(pouch.call("fill_stage")) == 1 and not m.art_hookup.held_teeth.visible, "eight teeth sag the pouch; none lie on the palm")
	check(not m.hand_motions._teeth_on_palm(), "the hand is not cupped")
	# a rest bucket fills the pouch as it filled the hand
	m.player.global_position = m.rest_stand_point(1)
	settle_motions()
	look(0.0, 0.0)
	m.rest_teeth[1] = 2
	check(m.take_rest_tooth() == 1 and m.put_rest_tooth() == 1 and m.take_rest_tooth() == 1 and prog.teeth_in_hand == 9 and m.rest_teeth[1] == 1, "teeth go between the bucket and the pouch one at a time")
	m.rest_teeth[1] = 0
	prog.teeth_in_hand = 8
	# in the restroom they are on the palm, where the tank and the vent look
	settle_motions()
	m.player.global_position = m.START_POS
	prog.hands.set_item("", RIGHT)
	for i in range(3):
		await process_frame
	check(not m.teeth_in_pouch() and m.hand_motions._teeth_on_palm(), "inside the restroom the teeth are on the palm")
	check(m.art_hookup.held_teeth.visible and m.art_hookup.held_teeth.multimesh.visible_instance_count == 8 and int(pouch.call("fill_stage")) == 0 and pouch.visible, "the palm shows eight teeth and the pouch hangs empty")
	# the pouch keeps nothing safe
	m.player.global_position = out
	var tank: int = prog.teeth
	m.die("crush")
	check(int(m.death_drop.items.get("teeth_in_hand", 0)) == 8 and prog.teeth_in_hand == 0 and prog.teeth == tank and prog.has_pouch, "dying with the pouch: all 8 lie with the body, the pouch stays on")
	m.player.global_position = m.death_drop.current_position
	m._step_death_drop(0.016)
	check(prog.teeth_in_hand == 8, "and they come back from the body")
	# the four looks
	var p: Node3D = PouchScene.instantiate()
	get_root().add_child(p)
	var stages: Array = []
	for n in [0, 1, 8, 9, 24, 25, 200]:
		p.call("set_fill", n)
		stages.append(int(p.call("fill_stage")))
	check(stages == [0, 1, 1, 2, 2, 3, 3], "empty, sagging from 1, round from 9, stuffed from 25 (%s)" % str(stages))
	var shown := 0
	for ch in p.find_children("Stage*", "Node3D", true, false):
		if (ch as Node3D).visible:
			shown += 1
	check(shown == 1, "one look at a time")
	p.queue_free()

## The pouch hangs clear of everything else on the waist.
func _waist() -> void:
	var prog: FPProgression = m.progression
	for id in ["knife", "blender", "big_saw", "spray_cheap", "spray_deep", "spray_deep", "canary_feed", "barrier", "tumor_bag"]:
		prog.grant_item(id)
	prog.hands.clear()
	prog.tools.equipped = ""
	prog.teeth_in_hand = 30
	m.has_canary = true
	m.player.global_position = Vector3(0.0, 0.95, FPRestroom.HALF.z + 3.0)
	for i in range(6):
		await process_frame
	var belt: Node3D = m.art_hookup.belt
	var pouch: Node3D = m.art_hookup.pouch
	check(int(pouch.call("fill_stage")) == 3 and pouch.visible, "fixture: the pouch at its fullest")
	# hanging still (it swings when teeth go in and with the walk)
	pouch.set("_swing", 0.0)
	pouch.call("set_walk", 0.0)
	await process_frame
	check((pouch.get_node("Hang") as Node3D).rotation.is_zero_approx(), "standing still the pouch hangs straight down")
	var mine := box_of(pouch, belt)
	var others := 0
	var clear := true
	# whichever tool hangs on whichever hook
	for hung in [["knife", "blender", "big_saw"], ["knife", "big_saw", "blender"], ["blender", "knife", "big_saw"], ["blender", "big_saw", "knife"], ["big_saw", "knife", "blender"], ["big_saw", "blender", "knife"], ["", "", ""]]:
		belt.call("set_hung", hung)
		others = 0
		for ch in belt.get_children():
			if not (ch is Node3D) or ch == pouch or ch.name in ["Trousers", "Torso", "Belt"]:
				continue
			var b := box_of(ch, belt)
			if b.size == Vector3.ZERO:
				continue
			others += 1
			if mine.intersects(b):
				clear = false
				print("  the pouch touches ", ch.name, " ", b, " with ", hung, " (pouch ", mine, ")")
	check(others >= 12 and clear, "the fullest pouch touches no hook, tool, can, pack, bird, compass or bag (%d things round the waist)" % others)
	check(mine.end.y <= -0.03 and mine.position.x < 0.0 and mine.end.z < 0.0, "it hangs under the band on the front left")
