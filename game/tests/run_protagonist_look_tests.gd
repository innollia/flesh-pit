extends SceneTree

## The protagonist's look (first-person hand rig, skin texture, mirror/Tab
## body): the first hands and skin (user decision 2026-11-14) and the
## figure's build. Builds the
## models alone; no game scene and no save file. Run headless:
##   godot_console --headless --path game --script res://tests/run_protagonist_look_tests.gd

var _passed := 0
var _failed := 0

func _init() -> void:
	run.call_deferred()

func ok(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("  PASS ", msg)
	else:
		_failed += 1
		print("  FAIL ", msg)

func run() -> void:
	print("=== protagonist look tests ===")
	skin_texture()
	skin_shader()
	hand_rig()
	mirror_body()
	print("protagonist look tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func skin_texture() -> void:
	# User decision 2026-11-14: the protagonist's skin is the one from before
	# the grain texture (tex_skin_body_128) was tried, the kit's first skin.
	var path := "res://addons/flesh_dig_kit/textures/tex_skin_128.png"
	var mat := FDKSkinMaterial.make()
	var tex := mat.get_shader_parameter("skin_tex") as Texture2D
	ok(tex != null and tex.resource_path == path, "skin: the body material wears the first skin texture (tex_skin_128)")
	var src := FileAccess.get_file_as_string("res://addons/flesh_dig_kit/common/fdk_skin_material.gd")
	ok(not "tex_skin_body" in src, "skin: the grain texture is not referenced by the skin material")

func skin_shader() -> void:
	var code := FDKSkinMaterial.SHADER
	var gloss_lines := 0
	var dry_safe := true
	for line in code.split("
"):
		if "spec" in line and "ALBEDO" in line:
			gloss_lines += 1
			if not "* wet *" in line:
				dry_safe = false
	ok(gloss_lines == 1 and dry_safe, "skin: the highlight is added only times wet (a dry hand is untouched)")
	ok("24.0" in code and "vec3(0.16) * wet * spec" in code and not "floor(spec" in code, "skin: the wet highlight is the first soft one (power 24, 0.16, no steps)")
	ok("vec4(0.88, 0.72, 0.62, 1.0)" in code and "mix(vec3(1.0), tex, 0.5)" in code, "skin: body colour and texture mix are the approved ones")

func _min_z_near(mesh: Mesh, x: float, reach: float) -> float:
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var best := INF
	for v in verts:
		if absf(v.x - x) < reach:
			best = minf(best, v.z)
	return best

## Mesh colours are stored in 8 bits.
func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.006 and absf(a.g - b.g) < 0.006 and absf(a.b - b.b) < 0.006

func hand_rig() -> void:
	var rig := FDKHandsRig.new()
	root.add_child(rig)
	rig.build()
	# joints: places the fingertip tests, held tools and mutations rely on
	var want := {
		"Wrist/Finger1": Vector3(0, 0.001, -0.088),
		"Wrist/Finger1/Finger2": Vector3(0, 0, -0.044),
		"Wrist/Finger1/Finger2/Finger3": Vector3(0, 0, -0.031),
		"Wrist/Thumb1": Vector3(0.036, -0.008, -0.016),
		"Wrist/Thumb1/Thumb2": Vector3(0, 0, -0.04),
		"Wrist/Thumb1/Thumb2/Thumb3": Vector3(0, 0, -0.03),
	}
	var moved: Array = []
	var missing: Array = []
	for hand in ["HandRight", "HandLeft"]:
		var ts := -1.0 if hand == "HandRight" else 1.0
		for p in want:
			var node := rig.get_node_or_null(hand + "/" + p) as Node3D
			if node == null:
				missing.append(hand + "/" + p)
				continue
			var at: Vector3 = want[p]
			if p == "Wrist/Thumb1":
				at.x *= ts
			if not node.position.is_equal_approx(at):
				moved.append("%s/%s %s" % [hand, p, node.position])
			if node.get_node_or_null("Seg") == null:
				missing.append(hand + "/" + p + "/Seg")
		for p in ["Forearm", "Wrist/Palm", "Wrist/TornChunk"]:
			if rig.get_node_or_null(hand + "/" + p) == null:
				missing.append(hand + "/" + p)
	ok(missing.is_empty(), "hands: every joint, Seg, Forearm, Palm and TornChunk keeps its name %s" % [missing])
	ok(moved.is_empty(), "hands: the 12 joints sit where they did before the reshaping %s" % [moved])
	var fore: AABB = (rig.get_node("HandRight/Forearm") as MeshInstance3D).mesh.get_aabb()
	ok(absf(fore.position.z - 0.008) < 0.0005 and absf(fore.end.z - 0.34) < 0.0005,
		"hands: forearm still spans z 0.008..0.34 (%.3f..%.3f)" % [fore.position.z, fore.end.z])
	# User decision 2026-11-14: the first hand. A fused finger block of four
	# rounded ridges (20-point section), a smooth fingertip curve with the
	# tip band in the nail colour, a tapering thumb; no nail plates, no
	# shaded grooves, no wrist bone.
	var fverts: PackedVector3Array = (rig.get_node("HandRight/Forearm") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var zs := {}
	for v in fverts:
		zs[snappedf(v.z, 0.001)] = true
	ok(zs.size() == 4 and zs.has(0.34) and zs.has(0.18) and zs.has(0.06) and zs.has(0.008), "hands: the forearm is the first four-ring taper %s" % [zs.keys()])
	ok(FDKHandsRig.FINGER_PROFILE.size() == 20, "hands: the finger block section is the first 20-point one (%d)" % FDKHandsRig.FINGER_PROFILE.size())
	var tip: Mesh = (rig.get_node("HandRight/Wrist/Finger1/Finger2/Finger3/Seg") as MeshInstance3D).mesh
	var arrays := tip.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var free_edge := Color(0.97, 0.9, 0.86)
	var groove_col: Color = rig.skin_color.darkened(0.16)
	var plates := 0
	var groove := 0
	var nail_tip := 0
	var tip_end := INF
	for i in range(verts.size()):
		tip_end = minf(tip_end, verts[i].z)
		if _near(cols[i], free_edge):
			plates += 1
		if _near(cols[i], groove_col):
			groove += 1
		if _near(cols[i], rig.nail_color):
			nail_tip += 1
	ok(plates == 0 and groove == 0, "hands: no nail plates and no painted grooves on the finger block (%d / %d vertices)" % [plates, groove])
	ok(nail_tip > 0, "hands: the fingertip band wears the nail colour (%d vertices)" % nail_tip)
	# smooth tip curve on the right hand (thumb at -x): the little finger
	# side (+x) ends well behind the middle, the index side a little
	var mid_end := _min_z_near(tip, 0.0, 0.006)
	var little_end := _min_z_near(tip, 0.036, 0.004)
	var index_end := _min_z_near(tip, -0.036, 0.004)
	ok(little_end - mid_end > 0.004 and index_end - mid_end > 0.0 and little_end > index_end,
		"hands: the fingertips follow the first smooth curve (index %.1f, little %.1f mm behind the middle)" % [(index_end - mid_end) * 1000.0, (little_end - mid_end) * 1000.0])
	# M09 thick nails: the first row at one depth on the tip segment
	load("res://main/art/fp_mutation_hands.gd").apply_shape(rig, ["M09"])
	var thick := rig.get_node_or_null("HandRight/Wrist/Finger1/Finger2/Finger3/MutDeco_Nails") as MeshInstance3D
	ok(thick != null, "hands: M09 puts thick nails on the fingertip segment")
	if thick != null:
		var nb: AABB = thick.mesh.get_aabb()
		ok(absf(nb.get_center().z + 0.012) < 0.001 and absf(nb.size.z - 0.024) < 0.002 and nb.position.y > 0.01,
			"hands: M09 nails sit in the first row over the fingertips (centre z %.1f mm, %.1f mm long)" % [nb.get_center().z * 1000.0, nb.size.z * 1000.0])
		ok(nb.position.z > tip_end - 0.012, "hands: M09 nails stay on the fingertips (front %.1f mm, fingertip %.1f mm)" % [nb.position.z * 1000.0, tip_end * 1000.0])
	load("res://main/art/fp_mutation_hands.gd").apply_shape(rig, [])
	# the thumb tapers to its tip as it first did
	var thumb: Mesh = (rig.get_node("HandRight/Wrist/Thumb1/Thumb2/Thumb3/Seg") as MeshInstance3D).mesh
	var tb: AABB = thumb.get_aabb()
	ok(absf(tb.position.z + 0.032) < 0.0006, "hands: the thumb tip ends 7 mm past its last joint length (%.1f mm)" % (tb.position.z * 1000.0))
	ok(rig.skin_color.is_equal_approx(Color(0.88, 0.72, 0.62)) and rig.palm_color.is_equal_approx(Color(0.9, 0.68, 0.6)), "hands: body and palm colours are the approved ones")
	rig.free()

func mirror_body() -> void:
	var b := FPMirrorBody.new()
	root.add_child(b)
	b.build()
	b.apply([])
	ok(absf(b.part_center("face").y - 1.62) < 0.0005, "body: the face pivot is at 1.62 m")
	var head := b.part_node("face").get_node("Head") as MeshInstance3D
	ok(absf(1.62 + head.mesh.get_aabb().end.y - 1.758) < 0.0005, "body: the figure is 1.76 m tall (crown %.3f)" % (1.62 + head.mesh.get_aabb().end.y))
	ok(FPMirrorBody.TRUNK[0] == [0.97, 0.165, 0.098, 0.115], "body: the hip ring the belt is fitted to has not moved")
	var same_rows := FPMirrorBody.TRUNK_PLAIN.size() == FPMirrorBody.TRUNK_FIGURE.size()
	for i in range(mini(FPMirrorBody.TRUNK_PLAIN.size(), FPMirrorBody.TRUNK_FIGURE.size())):
		if not is_equal_approx(FPMirrorBody.TRUNK_PLAIN[i][0], FPMirrorBody.TRUNK_FIGURE[i][0]):
			same_rows = false
	ok(same_rows and FPMirrorBody.TRUNK_PLAIN[0] == FPMirrorBody.TRUNK_FIGURE[0], "body: both builds share the ring heights and the hips (one constant switches them)")
	var missing: Array = []
	for sub in ["hand_r", "hand_l", "fingers_r", "fingers_l", "forearm_r", "forearm_l", "upper_r", "upper_l", "shoulders", "jaw", "eyes", "nose"]:
		if b.sub_node(sub) == null:
			missing.append(sub)
	for part in ["face", "neck", "chest", "belly", "arms", "right_hand", "left_hand", "legs", "whole"]:
		if b.part_node(part) == null:
			missing.append(part)
	ok(missing.is_empty(), "body: every part and sub pivot the mutations use is there %s" % [missing])
	var hand := b.sub_node("hand_r")
	var fing := b.sub_node("fingers_r")
	ok(hand.scale.is_equal_approx(Vector3.ONE * 1.25) and fing.position.is_equal_approx(Vector3(0, 0.082, 0)) and hand.get_node_or_null("Palm") != null and fing.get_node_or_null("Fingers") != null,
		"body: hand scale 1.25, finger pivot y 0.082, Palm and Fingers meshes")
	var pale := 0
	var cols: PackedColorArray = (fing.get_node("Fingers") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for c in cols:
		if c.r > FPMirrorBody.SKIN.r + 0.01:
			pale += 1
	ok(pale == 0, "body: no pale fingertips on the figure (they read as claws)")
	ok(FPMirrorBody.FINGER_LEN[1] > FPMirrorBody.FINGER_LEN[2] and FPMirrorBody.FINGER_LEN[2] > FPMirrorBody.FINGER_LEN[0] and FPMirrorBody.FINGER_LEN[0] > FPMirrorBody.FINGER_LEN[3],
		"body: finger lengths step middle > ring > index > little")
	var sh: AABB = (b.sub_node("shoulders").get_node("Shoulders") as MeshInstance3D).mesh.get_aabb()
	var half: float = maxf(absf(sh.position.x), absf(sh.end.x))
	if FPMirrorBody.PLAIN_BUILD:
		ok(half < 0.235 and half > 0.2, "body: plain build, shoulders %.3f m half width (was 0.25)" % half)
		var waist := 1.0
		for r in FPMirrorBody.TRUNK:
			waist = minf(waist, r[1]) if r[0] < 1.3 else waist
		ok(waist / half > 0.64, "body: plain build, waist is %.2f of the shoulders (was 0.57)" % (waist / half))
	else:
		ok(absf(half - 0.25) < 0.002, "body: figure build, shoulders 0.25 m half width")
	ok(FPMirrorBody.SKIN.is_equal_approx(Color(0.88, 0.72, 0.62)), "body: the approved body colour")
	b.free()
