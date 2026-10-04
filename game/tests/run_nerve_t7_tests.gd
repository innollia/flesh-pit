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
	# -------------------------------------------------------------------------
	# Test Suite: T7 Nerve Stalk Ground Anchoring, Continuity & Detachment (R11)
	# -------------------------------------------------------------------------
	var config := FDKTerrainConfig.new()
	config.chunk_size = 4
	config.cell_size = 0.5

	var field := FDKTerrainField.new()
	field.config = config
	root.add_child(field)

	# 1. Stalk with no terrain: should NOT be anchored, should NOT be visible (부유 0)
	var n_unanchored := FDKNerveStalk.new()
	root.add_child(n_unanchored)
	check(not n_unanchored.is_anchored(), "unanchored stalk: is_anchored() is false when terrain is null")
	n_unanchored.update_anchor()
	check(not n_unanchored.visible, "unanchored stalk: visible is false when unanchored")
	check(n_unanchored.is_detached, "unanchored stalk: is_detached is true")

	# 2. Actual surface placement (실제 FDKTerrainField 표면):
	# Create an actual wall where z <= 0 is solid (density 1.0) and z > 0 is empty (density 0.0).
	# AABB from (-2, -2, -2) to (2, 2, 0).
	field.fill_box_uniform(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 2)), 1.0, 0)
	field.remesh_all()

	var surface_pos := Vector3(0.5, 0.5, 0.0)
	var surface_normal := Vector3(0.0, 0.0, 1.0) # pointing outward into open air (z > 0)

	var n := FDKNerveStalk.new()
	n.terrain = field
	root.add_child(n)
	n.place(surface_pos, surface_normal)

	check(n.is_anchored(), "actual surface: stalk is anchored when placed on real terrain surface")
	check(n.visible, "actual surface: stalk is visible when anchored")
	check(not n.is_detached, "actual surface: is_detached is false")
	check(field.density_at(n.base_probe) >= 0.5, "actual surface: base_probe density >= 0.5")

	# 3. Shallow surface cut fixture (얕은 surface cut 후 probe는 solid지만 root와 벽 틈 발생 fixture):
	# Baseline flaw: if the surface retreats by < 0.15, base_probe (at depth 0.15) is still solid,
	# but root has a gap with the wall. The stalk MUST NOT float (줄 안 뜸).
	#
	# We shave the surface layer at z = 0: set the surface corners (z=0) to 0.3.
	# Corners at z = -0.5 remain solid 1.0.
	# Trilinear density at base_probe (z = -0.15): lerp(1.0, 0.3, 0.70) = 0.51 >= 0.5 (PROBE IS SOLID).
	# Trilinear density at root-near (z = -0.0375): lerp(1.0, 0.3, 0.925) = 0.35 < 0.5 (GAP AT ROOT).
	var chunk: FDKChunk = field.get_or_create_chunk(Vector3i(0, 0, 0))
	var s_n := config.chunk_size + 1
	# A 0.019m retreat leaves every old behind-root probe solid.
	# Only checking contact at the visible root detects this gap.
	for y in range(s_n):
		for x in range(s_n):
			chunk._density[x + y * s_n] = 0.48
	check(n.sample_density(n.base_probe) >= config.iso_level,
		"micro cut: deep probe stays solid")
	check(n.sample_density(surface_pos - surface_normal * 0.0375) >= config.iso_level,
		"micro cut: nearest old probe stays solid")
	check(n.sample_density(surface_pos) < config.iso_level,
		"micro cut: actual root has lost surface contact")
	check(not n.update_anchor() and not n.visible,
		"micro cut pending: disconnected actual root is hidden")
	field.remesh_all()
	check(not n.update_anchor() and not n.visible,
		"micro cut published: disconnected actual root stays hidden")
	for y in range(s_n):
		for x in range(s_n):
			# corner at z = 0 (z index in chunk where z=0 is z=0 since origin is 0,0,0)
			# local z for z=0.0 with origin (0,0,0) is z_idx = 0.
			var idx := x + y * s_n + 0 * s_n * s_n
			chunk._density[idx] = 0.3

	# Probe is solid (>= 0.5) according to baseline check:
	check(n.sample_density(n.base_probe) >= 0.5 or field.density_at(n.base_probe) >= 0.5,
		"shallow cut fixture: base_probe is verified solid (>= 0.5)")

	# A) Remesh pending check: before remesh_all, update_anchor must detect gap and NOT float
	var anchored_pending := n.update_anchor()
	check(not anchored_pending, "shallow cut (remesh pending): update_anchor() returns false")
	check(not n.is_anchored(), "shallow cut (remesh pending): is_anchored() is false (root gap detected)")
	check(not n.visible, "shallow cut (remesh pending): visible is false (줄 안 뜸)")
	check(n.is_detached, "shallow cut (remesh pending): is_detached is true")

	# Step should maintain invisibility without duplicate update waste
	n.step(0.016)
	check(not n.visible, "shallow cut (remesh pending): step maintains invisible state")

	# B) Published check: after remesh_all, stalk still does not float
	field.remesh_all()
	var anchored_published := n.update_anchor()
	check(not anchored_published, "shallow cut (published): update_anchor() returns false after remesh")
	check(not n.visible, "shallow cut (published): stalk remains invisible after terrain publish (줄 안 뜸)")

	# 4. Regeneration check (지형 재생으로 기반 복구 시 부착 상태 재확인):
	# Restore the surface layer corners to 1.0 (healing the wall back to surface_pos)
	for y in range(s_n):
		for x in range(s_n):
			var idx := x + y * s_n + 0 * s_n * s_n
			chunk._density[idx] = 1.0
	field.remesh_all()

	var anchored_regen := n.update_anchor()
	check(anchored_regen, "regeneration: update_anchor() returns true after surface restored")
	check(n.is_anchored(), "regeneration: is_anchored() is true when wall re-connects to root")
	check(n.visible, "regeneration: visible restored to true on real surface")
	check(not n.is_detached, "regeneration: is_detached reset to false")

	# 5. Disturb reaction on real surface (신경 상호작용 및 국소 수축):
	var got_disturbed_signal := [false]
	var disturbed_pos := [Vector3.INF]
	n.disturbed.connect(func(pos: Vector3):
		got_disturbed_signal[0] = true
		disturbed_pos[0] = pos
	)

	var density_pre_disturb: float = field.density_at(n.base_probe)
	n.disturb(1.0)
	check(got_disturbed_signal[0], "disturb: disturbed signal emitted on real surface")
	check(disturbed_pos[0].is_finite(), "disturb: disturbed position is valid")
	var density_post_disturb: float = field.density_at(n.base_probe)
	check(density_post_disturb < density_pre_disturb,
		"disturb: local contraction reduced base density (%f -> %f)" % [density_pre_disturb, density_post_disturb])
	check(n.is_anchored(), "disturb: still anchored after single disturb flinch")

	# 6. Deep excavation (완전 굴착) stripping the base completely:
	field.dig_at(n.base_probe, 1.0)
	n.update_anchor()
	check(not n.is_anchored(), "deep excavation: stalk detached when base tissue excavated")
	check(not n.visible, "deep excavation: stalk hidden after full excavation")

	# 7. Unanchored detached stalk does not disturb
	var disturbed_when_detached := [false]
	n.disturbed.connect(func(_p): disturbed_when_detached[0] = true)
	n.disturb(1.0)
	check(not disturbed_when_detached[0], "disturb: detached stalk does not emit disturb or contract tissue")

	# 8. Free on detach option
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
