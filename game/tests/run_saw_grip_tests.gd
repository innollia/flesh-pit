extends SceneTree

## The big saw is held by both hands (audit 1-8, findings 2026-11-03): it
## hangs on the right wrist, both finger loops close on its two handles, it
## shows only once both hands have it, and it bobs, strokes and digs with
## the hands. Isolated save path; the normal save is never touched.

const SAVE := "user://saw_grip_test.bin"
const DT := 1.0 / 60.0
## The curled finger loop in a wrist frame (FPArtHookup.SAW_GRIP).
const LOOP := Vector3(0.0, -0.03, -0.08)
const FPBigSawScript := preload("res://main/art/fp_big_saw.gd")
var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.user_keybinds_path = "user://keybinds_test_saw_grip.json"
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

## Highest screen point (smallest y) of a hand's palm, fingers and thumb.
func hand_top_px(side: String, cam: Camera3D) -> float:
	var hand := (m.art_hookup._rig as Node3D).get_node("HandLeft/Wrist" if side == "left" else "HandRight/Wrist")
	var top := INF
	var todo: Array = [hand]
	while not todo.is_empty():
		var n: Node = todo.pop_back()
		if n == m.art_hookup.saw:
			continue
		todo.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var box := mi.mesh.get_aabb()
		for c in range(8):
			top = minf(top, cam.unproject_position(mi.global_transform * box.get_endpoint(c)).y)
	return top

## The blade's side faces by band: luminance of every plate vertex (the
## spine edge, never the plain steel of the spine strip) and of every bevel
## vertex (the belly edge above the teeth).
func blade_bands() -> Array:
	var mesh := (m.art_hookup.saw.get_node("Blade") as MeshInstance3D).mesh
	var arr := mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var steel := Color(0.62, 0.62, 0.6)
	var plate: Array = []
	var bevel: Array = []
	for i in range(vs.size()):
		var v := vs[i]
		var c := cs[i]
		var l := (c.r + c.g + c.b) / 3.0
		if absf(v.x) > FPBigSawScript.L - 0.001: # the closed ends are plain steel
			continue
		if absf(v.y - 0.03) < 0.0002 and absf(absf(v.z) - 0.0015) < 0.0002:
			if absf(c.r - steel.r) + absf(c.g - steel.g) + absf(c.b - steel.b) > 0.02:
				plate.append(l)
		elif absf(absf(v.z) - 0.0008) < 0.0002 and v.y < -0.04:
			bevel.append(l)
	return [plate, bevel]

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
	# the handles are longer than the fists: wood shows over each hand, so
	# the hands read as holding something (2026-11-14 review: the handle
	# ended inside the fist and the hands seemed to float over the blade)
	var cam0: Camera3D = m.player.camera
	for side in ["left", "right"]:
		var sx := -1.0 if side == "left" else 1.0
		var top_px: float = cam0.unproject_position(ah.saw.global_transform * Vector3(sx * (FPBigSawScript.L + 0.028), FPBigSawScript.HANDLE_TOP, 0.0)).y
		var grip_px: float = cam0.unproject_position(ah.saw.global_transform * (ah.saw.call("grip_" + side) as Vector3)).y
		var fist_px := hand_top_px(side, cam0)
		var vh: float = cam0.get_viewport().get_visible_rect().size.y
		check(top_px < fist_px - 0.03 * vh and top_px < grip_px - 0.12 * vh, "the %s handle shows over the fist (handle top %.2f, fist top %.2f, grip %.2f of the view's height)" % [side, top_px / vh, fist_px / vh, grip_px / vh])
	check(FPBigSawScript.HANDLE_FOOT < -0.04 and FPBigSawScript.GRIP_Y - FPBigSawScript.HANDLE_FOOT > 0.12, "the handle runs on under the fist as well")
	# the blade reads along its length: a dull plate band and a bright bevel
	# band, the slices of one band nearly the same (one flat rust per slice
	# drew the blade as upright stripes)
	var bands := blade_bands()
	var plate: Array = bands[0]
	var bevel: Array = bands[1]
	check(plate.size() >= 24 and bevel.size() >= 24, "the blade has both bands along its whole length (%d, %d)" % [plate.size(), bevel.size()])
	if not plate.is_empty() and not bevel.is_empty():
		check(float(plate.max()) - float(plate.min()) < 0.06, "the plate's slices differ only a little (%.3f)" % (float(plate.max()) - float(plate.min())))
		check(float(bevel.min()) - float(plate.max()) > 0.15, "the bevel is clearly brighter than the plate (%.3f)" % (float(bevel.min()) - float(plate.max())))
	# the sheen texture's bands lie along the blade: u changes across the
	# blade only, never along it
	var barr := (ah.saw.get_node("Blade") as MeshInstance3D).mesh.surface_get_arrays(0)
	var bvs: PackedVector3Array = barr[Mesh.ARRAY_VERTEX]
	var buv: PackedVector2Array = barr[Mesh.ARRAY_TEX_UV]
	var u_follows_y := buv.size() == bvs.size() and bvs.size() > 0
	for i in range(mini(buv.size(), bvs.size())):
		if absf(buv[i].x - bvs[i].y * FPBigSawScript.BLADE_UV) > 0.0005:
			u_follows_y = false
	check(u_follows_y, "the blade's sheen bands run along its length")
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
