extends SceneTree

## The big saw is held by both hands (audit 1-8, findings 2026-11-03): it
## hangs on the right wrist, both finger loops close on its two handles, it
## shows only once both hands have it, and it bobs, strokes and digs with
## the hands. Isolated save path; the normal save is never touched.

const SAVE := "user://saw_grip_test.bin"
const DT := 1.0 / 60.0
## The curled finger loop in a wrist frame (FPArtHookup.SAW_GRIP).
const LOOP := Vector3(0.0, -0.03, -0.08)
var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = SAVE
	get_root().add_child(m)
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

## Distance (m) between a hand's finger loop and the saw handle it should hold.
func gap(side: String) -> float:
	var ah = m.art_hookup
	var w := (ah._rig as Node3D).get_node("HandLeft/Wrist" if side == "left" else "HandRight/Wrist") as Node3D
	var loop: Vector3 = w.global_transform * LOOP
	var handle: Vector3 = ah.saw.global_transform * (ah.saw.call("grip_left" if side == "left" else "grip_right") as Vector3)
	return loop.distance_to(handle)

func shown(rig: Node3D) -> bool:
	return rig.has_method("both_grip_shown") and bool(rig.call("both_grip_shown"))

func steps(n: int) -> void:
	for i in range(n):
		m.art_hookup._rig.step(DT)
		m.art_hookup._process(DT)

func _run() -> void:
	for i in range(5):
		await process_frame
	m.finish_opening()
	m.set_process(false)
	m.player.set_physics_process(false)
	var p: FPProgression = m.progression
	for id in ["knife", "blender", "big_saw"]:
		p.grant_item(id)
	p.has_belt = true
	var ah: FPArtHookup = m.art_hookup
	var rig: FDKHandsRig = ah._rig
	var rw := rig.get_node("HandRight/Wrist") as Node3D
	var lw := rig.get_node("HandLeft/Wrist") as Node3D
	steps(30)
	check(m.equip_tool("big_saw") and p.hands.holds("big_saw"), "the saw is equipped")
	ah._process(0.0)
	check(ah.saw.get_parent() == rw, "held saw hangs on the right wrist, not in camera space")
	check(not ah.saw.visible, "the saw does not show before the hands have it")
	# take: both hands drop out of view and come up holding it
	var seen_apart := false
	var rel0 := Transform3D()
	var rel_ok := true
	for i in range(40):
		steps(1)
		if ah.saw.visible and not shown(rig):
			seen_apart = true
		if ah.saw.visible:
			var rel: Transform3D = rw.global_transform.affine_inverse() * ah.saw.global_transform
			if rel0 == Transform3D():
				rel0 = rel
			elif not rel.is_equal_approx(rel0):
				rel_ok = false
	check(not seen_apart, "the saw shows only while both hands hold it")
	check(ah.saw.visible and shown(rig), "the saw is up in both hands")
	check(gap("right") < 0.005 and gap("left") < 0.01, "both hands close on the saw handles (left %.3f m, right %.3f m)" % [gap("left"), gap("right")])
	# both fists curled round the handles
	var lj: Dictionary = rig.get_joint_angles("left")
	var rj: Dictionary = rig.get_joint_angles("right")
	check(float(lj["f2"]) > 60.0 and float(rj["f2"]) > 60.0, "both hands' fingers are closed on the handles")
	# natural arms: the handles stand upright in the view and each forearm
	# comes in from its own lower side
	var cam: Camera3D = m.player.camera
	var up_cam: Vector3 = cam.global_basis.inverse() * (ah.saw.global_basis * Vector3.UP).normalized()
	check(up_cam.y > 0.9, "the saw handles stand upright in the view (%.2f)" % up_cam.y)
	var lr: Vector3 = rig.get_hand_root("left").position
	var rr: Vector3 = rig.get_hand_root("right").position
	check(lr.x < -0.2 and rr.x > 0.2 and lr.y < -0.15 and rr.y < -0.15 and absf(lr.x + rr.x) < 0.01, "forearms come up from the lower left and lower right (%s, %s)" % [lr, rr])
	var lsp: Vector2 = cam.unproject_position(lw.global_transform * LOOP)
	var rsp: Vector2 = cam.unproject_position(rw.global_transform * LOOP)
	var vp: Vector2 = cam.get_viewport().get_visible_rect().size
	check(lsp.x > 0.0 and rsp.x < vp.x and lsp.y < vp.y and rsp.y < vp.y and lsp.x < vp.x * 0.5 and rsp.x > vp.x * 0.5, "both gripping hands are on screen, one each side (%s, %s)" % [lsp, rsp])
	# walking bob: both hands bob, the saw goes with them and stays in both
	var at_rest: Vector3 = rig.get_hand_root("right").position
	rig.apply_bob(Vector3(0.01, 0.03, 0.0))
	steps(30)
	var moved: float = rig.get_hand_root("right").position.distance_to(at_rest)
	var rel_bob: Transform3D = rw.global_transform.affine_inverse() * ah.saw.global_transform
	check(moved > 0.02 and rel_ok and rel_bob.is_equal_approx(rel0) and gap("left") < 0.01, "walking bob moves both hands and the saw together (hand %.3f m, left gap %.3f m)" % [moved, gap("left")])
	rig.apply_bob(Vector3.ZERO)
	steps(30)
	# using it: a stroke slides the saw and both hands along the blade
	var saw_at: Vector3 = rig.to_local(ah.saw.global_position)
	ah.saw.call("set_stroke", 1.0)
	steps(30)
	var slid: float = rig.to_local(ah.saw.global_position).x - saw_at.x
	check(slid > 0.05 and gap("left") < 0.01, "a stroke slides the saw with both hands on it (%.3f m, left gap %.3f m)" % [slid, gap("left")])
	ah.saw.call("set_stroke", 0.0)
	# working flesh: the grab pushes the saw in and it stays in both hands
	rig.on_grab_started()
	rig.on_chew_progress(0.8)
	steps(20)
	var pushed: float = saw_at.z - rig.to_local(ah.saw.global_position).z
	check(pushed > 0.03 and gap("left") < 0.01, "a saw grab presses it in, still in both hands (%.3f m, left gap %.3f m)" % [pushed, gap("left")])
	rig.on_cell_torn()
	check(rig.torn_chunk() == null, "no torn chunk shows in a fist on the saw")
	rig.on_released()
	steps(40)
	# put away: it goes down with the hands and is gone before they return
	m.equip_tool("")
	var left_hands := false
	for i in range(40):
		steps(1)
		if ah.saw.visible and not shown(rig):
			left_hands = true
	check(not left_hands and not ah.saw.visible and not shown(rig), "putting the saw away takes it down with both hands")
	# straight from the blender: the blender goes down, the saw comes up, never both
	m.equip_tool("blender")
	steps(40)
	check(ah.blender.visible, "blender up in the left hand")
	m.equip_tool("big_saw")
	var both := false
	for i in range(40):
		steps(1)
		if ah.blender.visible and ah.saw.visible:
			both = true
	check(not both and ah.saw.visible and not ah.blender.visible and gap("left") < 0.01, "blender to saw: the blender goes down and the saw comes up in both hands")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("--- saw grip: %d passed, %d failed ---" % [passed, failed])
	m.queue_free()
	quit(1 if failed else 0)
