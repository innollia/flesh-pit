extends SceneTree

## The protagonist's look (first-person hand rig, skin texture, mirror/Tab
## body): what the reshaping must keep and what it must show. Builds the
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
	var path := "res://addons/flesh_dig_kit/textures/tex_skin_body_128.png"
	ok(FDKSkinMaterial.SKIN_TEX == path, "skin: the body material wears the protagonist's own texture")
	ok(FileAccess.file_exists("res://addons/flesh_dig_kit/textures/tex_skin_128.png"), "skin: the old texture stays for the tumours and the canary")
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	ok(img != null and img.get_width() == 128 and img.get_height() == 128, "skin: body texture is 128 x 128")
	if img == null:
		return
	var n := 128
	var sum := Vector3.ZERO
	var lum: Array[float] = []
	for y in range(n):
		for x in range(n):
			var c := img.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b) * 255.0
			lum.append((0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * 255.0)
	var mean := sum / float(n * n)
	# the old texture's mean: the body colour on screen must not move
	var want := Vector3(219, 179, 152)
	ok(absf(mean.x - want.x) <= 2.0 and absf(mean.y - want.y) <= 2.0 and absf(mean.z - want.z) <= 2.0,
		"skin: mean colour stays (219, 179, 152) +-2, got (%.1f, %.1f, %.1f)" % [mean.x, mean.y, mean.z])
	var lm := 0.0
	for v in lum:
		lm += v
	lm /= float(lum.size())
	var var_sum := 0.0
	for v in lum:
		var_sum += (v - lm) * (v - lm)
	var std := sqrt(var_sum / float(lum.size()))
	ok(std >= 20.0 and std <= 26.0, "skin: brightness spread shows through the half-strength mix (std %.1f, 20..26)" % std)
	# tileable: a step across the wrap is no bigger than a step inside
	var inner := 0.0
	var seam := 0.0
	for i in range(n):
		seam += absf(lum[i * n] - lum[i * n + n - 1]) + absf(lum[i] - lum[(n - 1) * n + i])
		inner += absf(lum[i * n + 40] - lum[i * n + 41]) + absf(lum[40 * n + i] - lum[41 * n + i])
	ok(seam <= inner * 1.25, "skin: no seam where the texture repeats (edge step %.1f, inner step %.1f)" % [seam / (2.0 * n), inner / (2.0 * n)])

func skin_shader() -> void:
	var code := FDKSkinMaterial.SHADER
	var gloss_lines := 0
	var dry_safe := true
	for line in code.split("\n"):
		if "spec" in line and "ALBEDO" in line:
			gloss_lines += 1
			if not "* wet *" in line:
				dry_safe = false
	ok(gloss_lines == 1 and dry_safe, "skin: the highlight is added only times wet (a dry hand is untouched)")
	ok("48.0" in code and "floor(spec * 3.0 + 0.5) / 3.0" in code, "skin: the wet highlight is small, sharp and stepped")
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
	# wrist narrower than both the forearm and the hand
	var fverts: PackedVector3Array = (rig.get_node("HandRight/Forearm") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var width := {}
	for v in fverts:
		var key := snappedf(v.z, 0.001)
		width[key] = maxf(width.get(key, 0.0), absf(v.x))
	ok(width.get(0.03, 1.0) < width.get(0.008, 0.0) and width.get(0.03, 1.0) < width.get(0.25, 0.0) and width.get(0.25, 0.0) > width.get(0.34, 1.0),
		"hands: the forearm swells, narrows to a wrist and flares into the hand")
	# fingertip stair on the right hand (thumb at -x, so the index is at -x)
	var tip: Mesh = (rig.get_node("HandRight/Wrist/Finger1/Finger2/Finger3/Seg") as MeshInstance3D).mesh
	var ends: Array = []
	for row in range(4):
		ends.append(_min_z_near(tip, FDKHandsRig.FINGER_ROWS[row] * -1.0 * 0.03, 0.004))
	var steps := [ends[0] - ends[1], ends[2] - ends[1], ends[3] - ends[1]]
	ok(absf(steps[0] - 0.006) < 0.0012 and absf(steps[1] - 0.004) < 0.0012 and absf(steps[2] - 0.016) < 0.0012,
		"hands: fingertips end in a stair behind the middle finger (index %.1f, ring %.1f, little %.1f mm)" % [steps[0] * 1000.0, steps[1] * 1000.0, steps[2] * 1000.0])
	# nails: plates on the back of the fingertips only
	var arrays := tip.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var nail_back := 0
	var nail_palm := 0
	var groove := 0
	for i in range(verts.size()):
		if _near(cols[i], rig.nail_color):
			if verts[i].y > 0.0:
				nail_back += 1
			else:
				nail_palm += 1
		if _near(cols[i], rig.skin_color.darkened(0.16)):
			groove += 1
	ok(nail_back >= 4 * 12 and nail_palm == 0, "hands: four nails on the back of the fingertips, none on the palm side (%d / %d vertices)" % [nail_back, nail_palm])
	ok(groove > 0, "hands: the grooves between the fingers are shaded")
	# thumb tip is blunt: still two thirds of its width 6 mm past the last joint length
	var thumb: Mesh = (rig.get_node("HandRight/Wrist/Thumb1/Thumb2/Thumb3/Seg") as MeshInstance3D).mesh
	var tverts: PackedVector3Array = thumb.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var base_w := 0.0
	var end_w := 0.0
	for v in tverts:
		if v.z > -0.001:
			base_w = maxf(base_w, absf(v.x))
		if absf(v.z + 0.031) < 0.0005 and v.y < 0.01:
			end_w = maxf(end_w, absf(v.x))
	ok(end_w > base_w * 0.66, "hands: the thumb ends blunt, not in a spike (%.1f mm wide at the end, %.1f at the joint)" % [end_w * 2000.0, base_w * 2000.0])
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
