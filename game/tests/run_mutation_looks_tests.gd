extends SceneTree

## How the protagonist's mutations, tumor bumps and hair are drawn: the
## first-person belly (bumps, M01 / T4 / M16 forms), the mirror/Tab body's
## extra pieces and their materials, the sense bristles and the arm hair
## tufts. Builds the models alone; no game scene and no save file. Run
## headless:
##   godot_console --headless --path game --script res://tests/run_mutation_looks_tests.gd

const Belt := preload("res://main/art/fp_belt.gd")

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

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func run() -> void:
	print("=== mutation looks tests ===")
	belly_rings()
	await belly()
	mirror_body()
	hands()
	arm_hair()
	print("mutation looks tests: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func belly_rings() -> void:
	var worst := -1.0
	var waist_kept := true
	for mask in range(16):
		var ids: Array = []
		for k in range(4):
			if mask & (1 << k):
				ids.append(["M01", "M16", "M19", "T4"][k])
		var rings: Array = Belt.belly_rings(ids)
		waist_kept = waist_kept and rings[0] == Belt.TORSO_RINGS[0]
		for i in range(1, rings.size()):
			worst = maxf(worst, float(rings[i][2]) - Belt.front_cap(float(rings[i][0])))
	ok(worst <= 0.00001, "belly: in all 16 combinations no ring comes further forward than the cap that keeps the belt in view (worst %.4f)" % worst)
	ok(waist_kept, "belly: the waist ring the belt is fitted round never changes")
	var base: Array = Belt.belly_rings([])
	var m01: Array = Belt.belly_rings(["M01"])
	var t4: Array = Belt.belly_rings(["T4"])
	ok(base == Belt.TORSO_RINGS, "belly: without a belly mutation the rings are the plain belly")
	ok(float(m01[3][2]) > float(base[3][2]) + 0.03 and float(m01[3][1]) == float(base[3][1]), "belly: M01 hangs %.3f m further forward mid-belly, no wider" % (float(m01[3][2]) - float(base[3][2])))
	ok(float(t4[3][1]) > float(m01[3][1]) * 1.09 and float(t4[5][0]) > float(m01[5][0]) * 1.19 and float(t4[4][2]) > float(m01[4][2]), "belly: T4 is wider, taller and fuller than M01")
	ok(Belt.belly_rings(["M16", "M19"]) == base, "belly: M16 / M19 churn the plain belly, they do not reshape it")

func belly() -> void:
	var belt: Node3D = load("res://main/art/fp_belt.tscn").instantiate()
	root.add_child(belt)
	await frames(2)
	var torso := belt.get_node("Torso") as MeshInstance3D
	ok(int(belt.call("bump_count")) == 0, "bumps: a fresh belly has none")
	var named := true
	var counted := true
	for n in [1, 3, 7, 0, 2]:
		belt.call("set_bumps", n)
		counted = counted and int(belt.call("bump_count")) == n
		for i in range(n):
			named = named and torso.get_node_or_null("TumorBump%d" % i) is MeshInstance3D
	ok(counted, "bumps: n bumps owned draw n bumps on the first-person belly (1, 3, 7, 0, 2)")
	ok(named, "bumps: each is a TumorBump<i> mesh on the Torso, so it moves with the belly")
	belt.call("set_bumps", 7)
	var eye: float = Belt.EYE_OVER_BELT
	for form in [[], ["M01"], ["T4"]]:
		belt.call("set_belly_form", form)
		ok(int(belt.call("bump_count")) == 7, "bumps: all 7 stay through belly form %s" % [form])
		var over := -1.0
		var right := true
		for i in range(7):
			var mi := torso.get_node("TumorBump%d" % i) as MeshInstance3D
			var box := mi.get_aabb()
			var limit: float = (Belt.RZF + (0.0 if form.is_empty() else Belt.BAND_OUT)) * (eye - box.get_center().y) / eye
			over = maxf(over, -box.position.z - limit)
			right = right and box.get_center().x > 0.0
			if i == 0:
				ok(mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and mi.material_overlay != null, "bumps: a bump casts no shadow and takes the body's blood paint (form %s)" % [form])
		ok(over <= 0.0, "bumps: no bump stands in front of the belt %s (form %s, worst %.4f)" % ["band's inner edge" if form.is_empty() else "band", form, over])
		ok(right, "bumps: on the player's right of the navel, as in the mirror (form %s)" % [form])
	# hair grows back on a rebuilt belly
	belt.call("set_belly_form", [])
	belt.call("set_body_hair", {"common": 40, "core": 20, "mantle": 0, "surface": 0})
	var before := (torso.get_node("BodyHair") as MeshInstance3D).mesh
	belt.call("set_belly_form", ["M01"])
	var hair := torso.get_node("BodyHair") as MeshInstance3D
	ok(hair.visible and hair.mesh != before and hair.mesh.get_surface_count() > 0, "belly: the navel hair is grown again on the reshaped belly")
	ok(torso.name == "Torso" and torso.material_overlay != null, "belly: the reshaped belly keeps its node and its blood/hair paint")
	# T4 shows veins: more triangles than the M01 belly of the same rings
	var m01_tris: int = (torso.mesh as ArrayMesh).surface_get_array_len(0)
	belt.call("set_belly_form", ["T4"])
	ok((torso.mesh as ArrayMesh).surface_get_array_len(0) > m01_tris, "belly: T4 adds its veins to the belly itself")
	ok(String(belt.call("belly_form")) == "T4", "belly: the form is the owned belly mutations")
	# churn
	belt.call("set_belly_form", ["M16"])
	await frames(4)
	ok(not torso.scale.is_equal_approx(Vector3.ONE) and absf(torso.scale.x - 1.0) <= 0.0301 and torso.scale.y == 1.0, "belly: M16 churns the belly within 3%% (scale %s)" % torso.scale)
	belt.call("set_belly_form", [])
	await frames(2)
	ok(torso.scale.is_equal_approx(Vector3.ONE), "belly: the churn stops with the mutation")
	# the belt and what hangs on it did not move
	ok((belt.get_node("Belt") as Node3D).position == Vector3.ZERO and belt.get_node_or_null("Hook0") != null and belt.get_node_or_null("Canary") != null, "belly: belt band, hooks and canary are untouched")
	belt.queue_free()
	await frames(1)

func _piece(b: FPMirrorBody, pname: String) -> MeshInstance3D:
	var found := b.find_children(pname, "MeshInstance3D", true, false)
	return found[0] as MeshInstance3D if not found.is_empty() else null

func mirror_body() -> void:
	var b := FPMirrorBody.new()
	root.add_child(b)
	b.apply([], 3)
	var bumps := b.tumor_bumps()
	ok(bumps.size() == 3 and bumps[0].name == "TumorBump0", "mirror: 3 bumps, named TumorBump<i>")
	if bumps.size() == 3:
		var box := bumps[0].get_aabb()
		ok(box.position.z < FPMirrorBody.BELLY_FRONT - 0.02 and box.end.z > box.position.z + 0.015, "mirror: the bump's rim is sunk in the belly side, not a ball on a flat plane (z %.3f..%.3f)" % [box.position.z, box.end.z])
		ok(b.tumor_center().distance_to(bumps[0].global_transform * box.get_center()) < 0.001, "mirror: the Tab pick point is still the first bump's middle")
	# materials: bone / tooth / nail are not skin, mouths and roots are wet
	for id in ["M09", "T3", "T6", "T7", "M03"]:
		b.apply([id])
		var hard := _piece(b, "Mut_%s_Hard" % id)
		ok(hard != null and hard.material_override is StandardMaterial3D and hard.material_override != b._skin, "mirror: %s has hard pieces in their own material (a StandardMaterial3D the Tab doll can light)" % id)
	for id in ["M15", "T1", "T3", "T6", "T7"]:
		b.apply([id])
		var wet := _piece(b, "Mut_%s_Wet" % id)
		ok(wet != null and wet.material_override is StandardMaterial3D, "mirror: %s has wet pieces in their own material" % id)
	b.apply(["M03"])
	var filings := _piece(b, "Mut_M03_Hard")
	ok(filings != null and filings.visible and not (b.sub_node("eyes").get_node("EyeImageLeft") as MeshInstance3D).visible, "mirror: M03 filings show over the eyes (they were hidden with the eye images)")
	if filings != null:
		ok(filings.get_aabb().size.y >= 0.05, "mirror: M03 filings span %.0f mm, more than 2 mirror texels thick" % (filings.get_aabb().size.y * 1000.0))
	b.apply(["T7"])
	var ribs := _piece(b, "Mut_T7_Hard")
	if ribs != null:
		var rb := ribs.get_aabb()
		var half: float = maxf(absf(rb.position.x), absf(rb.end.x))
		ok(half <= FPMirrorBody.T7_HALF_SPAN + 0.02 and half > 0.3, "mirror: T7 ribs reach %.2f m from the spine (were 0.52)" % half)
		ok(rb.end.z > 0.22, "mirror: T7 ribs curve forward off the chest (z %.2f)" % rb.end.z)
	ok(_piece(b, "Mut_T7") == null, "mirror: T7 has no skin-coloured piece")
	b.apply(["T2"])
	var arm := _piece(b, "Mut_T2")
	if arm != null:
		var ab := arm.get_aabb()
		ok(ab.size.x > 0.15 and ab.size.y > 0.2 and ab.end.z < 0.36, "mirror: the third arm reads from the front (%.2f wide, %.2f tall) and no longer points at the viewer (z %.2f, was 0.47)" % [ab.size.x, ab.size.y, ab.end.z])
	ok(arm != null, "mirror: T2 third arm is there")
	b.apply(["M23"])
	var whiskers := _piece(b, "Mut_M23")
	ok(whiskers != null and maxf(absf(whiskers.get_aabb().position.x), absf(whiskers.get_aabb().end.x)) > 0.3, "mirror: sense bristles stand clear of the arm's outline")
	b.apply(["M20"])
	var elbow := b.part_node("right_hand")
	ok(absf(elbow.rotation_degrees.x - FPMirrorBody.M20_ELBOW) < 0.01, "mirror: M20 folds the right elbow the wrong way")
	b.apply([])
	var left := 0
	for e in b.find_children("Mut_*", "MeshInstance3D", true, false):
		left += 0 if e.is_queued_for_deletion() else 1
	ok(elbow.rotation.is_equal_approx(Vector3.ZERO) and left == 0, "mirror: shedding the mutations puts the arm back and removes the pieces")
	var g := b.ghost("T7")
	ok(g != null and not g.find_children("Mut_T7_Hard", "MeshInstance3D", true, false).is_empty(), "mirror: the hover preview builds the split pieces too")
	b.free()

func hands() -> void:
	var mh: Node3D = load("res://main/art/fp_mutation_hands.tscn").instantiate()
	root.add_child(mh)
	ok(mh.get_node_or_null("SwollenTorso") == null, "hands: no swollen mass rides the camera any more (T4 is the belly itself)")
	mh.call("set_mutation", "T4", true)
	ok(true, "hands: set_mutation('T4') is still accepted")
	var rig: Node3D = mh.call("rig")
	mh.call("apply_all", [rig], ["M23", "M26"])
	var both := 0
	var tall := true
	for side in ["HandRight", "HandLeft"]:
		var br := rig.get_node(side).get_node_or_null("MutDeco_Bristles") as MeshInstance3D
		if br != null:
			both += 1
			tall = tall and br.get_aabb().size.y >= 0.05
	ok(both == 2, "hands: M23 bristles on both forearms, under the name the shiver looks for")
	ok(tall, "hands: the bristles stand at least 50 mm off the arm (arm hair lies within 12 mm)")
	ok(not rig.find_children("MutDeco_Buds", "MeshInstance3D", true, false).is_empty(), "hands: M26 buds are there")
	mh.call("apply_all", [rig], [])
	ok(rig.find_children("MutDeco_*", "", true, false).is_empty(), "hands: shedding the mutations removes the pieces")
	mh.free()

func arm_hair() -> void:
	var arm: Node3D = load("res://main/art/fp_arm_hair.tscn").instantiate()
	root.add_child(arm)
	arm.call("set_hair", 200, {"core": 30, "mantle": 20, "surface": 6})
	ok(int(arm.call("hair_total")) == 256 and int(arm.call("strand_count")) == 240 * 3, "hair: 256 hairs still fill 240 points x 3 strands")
	arm.call("set_hair", 0, {"core": 1, "mantle": 0, "surface": 0})
	var mesh: Mesh = (arm.get_node("Hairs") as MeshInstance3D).mesh
	var box := mesh.get_aabb()
	ok(maxf(box.size.x, maxf(box.size.y, box.size.z)) < 0.05, "hair: the three strands of one hair point grow from one follicle (tuft %.0f mm across)" % (maxf(box.size.x, maxf(box.size.y, box.size.z)) * 1000.0))
	var cols: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var lo := 9.0
	var hi := 0.0
	for c in cols:
		lo = minf(lo, c.r)
		hi = maxf(hi, c.r)
	ok(hi > lo + 0.15, "hair: a core hair is dark at the root and pink toward the tip (red %.2f..%.2f)" % [lo, hi])
	arm.call("set_hair", 1, {})
	cols = (arm.get_node("Hairs") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	hi = 0.0
	for c in cols:
		hi = maxf(hi, maxf(c.r, maxf(c.g, c.b)))
	ok(hi < 0.12, "hair: a common hair stays dark to the tip (brightest %.2f)" % hi)
	arm.call("set_hair", 4, {"core": 2})
	arm.call("set_blink", "core", 2)
	ok(int(arm.call("blink_count")) == 2 and (arm.get_node("BlinkHairs") as MeshInstance3D).mesh.get_surface_count() > 0, "hair: the hairs a purchase would pull still blink")
	arm.free()
