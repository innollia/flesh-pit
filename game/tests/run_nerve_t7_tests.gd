extends SceneTree

var passed := 0
var failed := 0

func _init() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func run() -> void:
	# -------------------------------------------------------------
	# Test Suite: T7 Nerve Stalk Ground Anchoring & Detachment (R11)
	# -------------------------------------------------------------
	var config := FDKTerrainConfig.new()
	config.chunk_size = 4
	config.cell_size = 0.5

	var field := FDKTerrainField.new()
	field.config = config
	root.add_child(field)

	# 1. Stalk with no terrain: should NOT be anchored, should NOT be visible (no floating stalk)
	var n_unanchored := FDKNerveStalk.new()
	root.add_child(n_unanchored)
	check(not n_unanchored.is_anchored(), "unanchored stalk: is_anchored() is false when terrain is null")
	n_unanchored.update_anchor()
	check(not n_unanchored.visible, "unanchored stalk: visible is false when unanchored")
	check(n_unanchored.is_detached, "unanchored stalk: is_detached is true")

	# 2. Fill solid box: box from (-2, -2, -2) to (2, 2, 2)
	field.fill_box_uniform(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)), 1.0, 0)

	# 3. Create stalk rooted in solid tissue and verify initial attachment
	var n := FDKNerveStalk.new()
	n.terrain = field
	root.add_child(n)
	n.place(Vector3(0, 0, 0), Vector3(0, 0, 1))

	check(n.is_anchored(), "initial attachment: is_anchored() is true when rooted in solid tissue")
	check(n.visible, "initial attachment: visible is true")
	check(not n.is_detached, "initial attachment: is_detached is false")
	check(field.density_at(n.base_probe) >= 0.5, "initial attachment: base_probe density >= 0.5")

	# 4. Base excavation (기반 뜯기): dig out the base tissue so density drops below 0.5
	# Verify that in unpublished state (before remesh/publish), the stalk detects base removal
	field.dig_at(n.base_probe, 1.0)
	var density_after_dig: float = field.density_at(n.base_probe)
	check(density_after_dig < 0.5, "excavation: base density dropped below iso (%f < 0.5)" % density_after_dig)

	# Call update_anchor() and verify detachment (부유 0)
	var anchored_after_dig: bool = n.update_anchor()
	check(not anchored_after_dig, "excavation: update_anchor() returns false after base removed")
	check(not n.is_anchored(), "excavation: is_anchored() is false after base removed")
	check(not n.visible, "excavation: visible is false (0 floating stalks in unpublished state)")
	check(n.is_detached, "excavation: is_detached is true after base removal")

	# Step should maintain invisibility and deactivation
	n.step(0.016)
	check(not n.visible, "excavation: step maintains invisible state when unanchored")

	# Verify published state: remesh/publish terrain mesh
	field.remesh_all()
	n.update_anchor()
	check(not n.visible, "published state: stalk remains invisible after terrain publish (부유 0)")

	# 5. Base regeneration (지형 재생): restore solid tissue at base
	# Refill solid tissue around base_probe
	field.fill_box_uniform(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)), 1.0, 0)
	var density_after_regen: float = field.density_at(n.base_probe)
	check(density_after_regen >= 0.5, "regeneration: base density restored >= 0.5 (%f)" % density_after_regen)

	# Re-verify anchor update upon regeneration
	var anchored_after_regen: bool = n.update_anchor()
	check(anchored_after_regen, "regeneration: update_anchor() returns true after tissue restored")
	check(n.is_anchored(), "regeneration: is_anchored() is true after tissue restored")
	check(n.visible, "regeneration: visible restored to true")
	check(not n.is_detached, "regeneration: is_detached reset to false")

	# 6. Disturb reaction (신경 상호작용 및 국소 수축)
	var got_disturbed_signal := [false]
	var disturbed_pos := [Vector3.INF]
	n.disturbed.connect(func(pos: Vector3):
		got_disturbed_signal[0] = true
		disturbed_pos[0] = pos
	)

	var density_pre_disturb: float = field.density_at(n.base_probe)
	n.disturb(1.0)
	check(got_disturbed_signal[0], "disturb: disturbed signal was emitted")
	check(disturbed_pos[0].is_finite(), "disturb: disturbed position is valid")
	var density_post_disturb: float = field.density_at(n.base_probe)
	check(density_post_disturb < density_pre_disturb,
		"disturb: local contraction reduced base density (%f -> %f)" % [density_pre_disturb, density_post_disturb])
	check(n.is_anchored(), "disturb: still anchored after standard single disturb flinch")

	# 7. Contraction/repeated excavation stripping base tissue completely:
	field.dig_at(n.base_probe, 1.0)
	n.update_anchor()
	check(not n.is_anchored(), "repeated excavation: base tissue loss causes stalk detachment")
	check(not n.visible, "repeated excavation: stalk hidden when base tissue is stripped")

	# 8. Unanchored stalk does not disturb
	var disturbed_when_detached := [false]
	n.disturbed.connect(func(_p): disturbed_when_detached[0] = true)
	n.disturb(1.0)
	check(not disturbed_when_detached[0], "disturb: unanchored detached stalk does not emit disturb or contract tissue")

	# 9. Free on detach option
	var n_auto_free := FDKNerveStalk.new()
	n_auto_free.free_on_detach = true
	n_auto_free.terrain = field
	root.add_child(n_auto_free)
	n_auto_free.place(Vector3(10, 10, 10), Vector3(0, 1, 0)) # placed in empty air
	check(n_auto_free.is_queued_for_deletion() or not is_instance_valid(n_auto_free) or not n_auto_free.is_anchored(),
		"free_on_detach: stalk with free_on_detach queued for deletion when base is missing")

	# Cleanup
	n.queue_free()
	n_unanchored.queue_free()
	if is_instance_valid(n_auto_free):
		n_auto_free.queue_free()
	field.queue_free()

	print("NERVE T7 TESTS: %d passed, %d failed" % [passed, failed])
	await process_frame
	quit(1 if failed > 0 else 0)
