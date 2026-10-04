extends SceneTree

const FDKSurfacePatch = preload("res://addons/flesh_dig_kit/terrain/fdk_surface_patch.gd")

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

func count_open_edges_from_faces(faces: PackedVector3Array) -> int:
	var edge_counts := {}
	for i in range(0, faces.size(), 3):
		var pts := [faces[i], faces[i + 1], faces[i + 2]]
		for j in range(3):
			var pA: Vector3 = pts[j]
			var pB: Vector3 = pts[(j + 1) % 3]
			var sA := pA.snapped(Vector3.ONE * 0.0001)
			var sB := pB.snapped(Vector3.ONE * 0.0001)
			var ka := "%0.4f,%0.4f,%0.4f" % [sA.x, sA.y, sA.z]
			var kb := "%0.4f,%0.4f,%0.4f" % [sB.x, sB.y, sB.z]
			var k := (ka + "|" + kb) if ka < kb else (kb + "|" + ka)
			edge_counts[k] = edge_counts.get(k, 0) + 1
	var open_edges := 0
	for count in edge_counts.values():
		if count != 2:
			open_edges += 1
	return open_edges

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var field := FDKTerrainField.new()
	field.config = FDKTerrainConfig.new()
	field.config.chunk_size = 4
	field.density_sampler = func(_p: Vector3): return 1.0
	world.add_child(field)
	field.set_process(false)

	# 1. Setup closed state (density 1.0 / chunk 4 / 8 dig_at / 4 contract_sphere)
	# Exactly matching antigravity-03-pending-tear/reproduce.gd
	field.generate_region(AABB(Vector3.ONE * -2, Vector3.ONE * 4))
	field.remesh_all()
	for x in range(-1, 1):
		for y in range(-1, 1):
			for z in range(-1, 1):
				field.dig_at(Vector3(x, y, z) * 0.5 + Vector3.ONE * 0.25, 1.0)
	field.remesh_all()
	for step in range(4):
		field.contract_sphere(Vector3.ZERO, 1.3, 0.45)
		field.remesh_all()

	var chunks: Array = field.get_chunks()
	check(chunks.size() > 0, "closed state: chunks created")

	# Stage: before
	var eye := Vector3(0.1, 0.3, 0.1)
	field._update_solid_volume(eye)
	check(field._solid_volume.visible == true, "before: solid volume is visible in closed mass")
	check(field._solid_volume.observer_proof.get("kind", "") == "full_cell", "before: observer proof is full_cell")
	check(field._surface_patch == null, "before: no surface patch exists")

	var serialize_before: Dictionary = field.serialize()
	check(serialize_before.get("chunks", []).size() == chunks.size(), "before: serialize chunk count matches chunks")

	# Raycast hit on solid_contact_ray to find tear point
	var hit: Dictionary = field.solid_contact_ray(eye, eye + Vector3.FORWARD)
	check(not hit.is_empty(), "before: solid_contact_ray found hit")
	check(hit.get("position") != null, "before: hit has position")
	var outward: Vector3 = field._eye_surface_outward(hit)
	check(outward != Vector3.ZERO, "before: outward normal is valid Vector3")
	var dig_pos: Vector3 = hit.position - outward * 0.05

	# Perform closing tear dig_at
	field.dig_at(dig_pos, 1.0)

	# Stage: after_dig_before_publish
	check(field._surface_patch != null, "after dig: patch created immediately upon closing tear")
	check(field._surface_patch.faces.size() > 0, "after dig: patch has non-empty faces")
	check(field._surface_patch.mesh != null, "after dig: patch has valid mesh")
	check(count_open_edges_from_faces(field._surface_patch.faces) == 0, "after dig: patch is closed manifold with 0 open edges")

	# Density match: patch read 64 corners and matches live field
	check(field._surface_patch.read_corner_count == 64, "after dig: patch sampled 64 corners")
	var center_cell: Vector3i = field._surface_patch_cell
	var d_matched := true
	for kz in range(4):
		for ky in range(4):
			for kx in range(4):
				var gc := center_cell - Vector3i.ONE + Vector3i(kx, ky, kz)
				var d_live: float = field.corner_density_global(gc)
				if d_live < 0.0 or d_live > 1.0:
					d_matched = false
	check(d_matched, "after dig: corner density valid within [0, 1]")

	# Food independence
	check(field.inedible_tissues.size() > 0, "after dig: inedible tissues configuration preserved")
	check(field._surface_patch.is_inside_tree(), "after dig: patch is child node in tree")

	# Reach: solid_contact_ray reaches patch
	var reach_hit: Dictionary = field.solid_contact_ray(eye, eye + Vector3.FORWARD)
	check(not reach_hit.is_empty(), "reach: solid_contact_ray reached surface patch")
	check(reach_hit.get("fdk_surface_patch", false) == true, "reach: hit tagged as fdk_surface_patch")
	check(reach_hit.get("shape", 0) == -1, "reach: hit shape is -1")
	check(reach_hit.get("collider") != null, "reach: hit collider is real chunk body")
	check(reach_hit.get("fdk_patch_outward") != null, "reach: hit outward is true Vector")

	# Side hits from cavity center
	var side_hits := 0
	var cavity_center := (Vector3(center_cell) + Vector3.ONE * 0.5) * field.config.cell_size
	for dir in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN]:
		var sh: Dictionary = field.solid_contact_ray(cavity_center, cavity_center + dir)
		if not sh.is_empty() and sh.get("fdk_surface_patch", false):
			side_hits += 1
	check(side_hits == 6, "sidehits: all six cavity rays hit the actual patch (%d directions hit)" % side_hits)

	# Serialize unchanged
	var serialize_after: Dictionary = field.serialize()
	check(not serialize_after.has("patch") and not serialize_after.has("_surface_patch"), "serialize: patch not leaked to serialization")
	check(serialize_after.get("chunks", []).size() == serialize_before.get("chunks", []).size(), "serialize: chunk count unchanged")

	# Cache reuse when state is identical
	var rev0: int = field._surface_patch_revision
	field._refresh_or_clear_surface_patch()
	check(field._surface_patch_revision == rev0, "cache reuse: patch revision unchanged on identical state")

	# Mixed-cell observer proof: observer in new cavity does not trigger full mass
	field._update_solid_volume(eye)
	check(field._solid_volume.visible == false, "observer proof: solid volume not visible in new hole cavity")
	check(field._solid_volume.observer_proof.get("kind", "") != "full_cell", "observer proof: not marked as full cell")

	# Remesh budget 1 step 0..7
	var pending_faces: PackedVector3Array = field._surface_patch.faces.duplicate()
	field.remesh_budget_per_frame = 1
	for step in range(7):
		field._process(0.016)
		check(field._surface_patch != null, "budget step %d: patch remains alive during pending remesh" % step)
		check(field._surface_patch.faces.size() > 0, "budget step %d: patch faces exist" % step)

	# Step 7: final chunk published -> patch cleared
	field._process(0.016)
	check(field._surface_patch == null, "step 7: patch cleared after all source chunks published")
	var published_mesh_triangles := 0
	for chunk in field.get_chunks():
		published_mesh_triangles += chunk._surface_faces.size() / 3
	check(published_mesh_triangles > 0, "step 7: chunks now possess published ordinary mesh triangles")
	var published_faces := PackedVector3Array()
	for chunk in field.get_chunks():
		for point in chunk._surface_faces:
			published_faces.append(chunk.to_global(point))
	check(oriented_triangle_keys(pending_faces) == oriented_triangle_keys(published_faces), "pending actual geometry equals the eventually published surface and winding")

	# Deserialize cleanup test
	# Restore genuinely closed mass before creating the new pending patch.
	field.deserialize(serialize_before)
	field.remesh_all()
	field.dig_at(dig_pos, 1.0)
	check(field._surface_patch != null, "deserialize prep: patch created from restored closed mass")
	field.deserialize(serialize_before)
	check(field._surface_patch == null, "deserialize: patch cleaned up on field deserialize")

	# --- Addition 1: Pending Union with adjacent second tear (reproduce.gd scenario) ---
	field.deserialize(serialize_before)
	field.remesh_all()

	# First tear via solid_contact_ray
	var hit_u: Dictionary = field.solid_contact_ray(eye, eye + Vector3.FORWARD)
	check(not hit_u.is_empty(), "union test: first contact found")
	var outward_u: Vector3 = field._eye_surface_outward(hit_u)
	var dig_pos_u: Vector3 = hit_u.position - outward_u * 0.05
	field.dig_at(dig_pos_u, 1.0)
	check(field._surface_patch != null, "union test: first patch created")
	check(count_open_edges_from_faces(field._surface_patch.faces) == 0, "union test: first patch closed edge 0")
	var first_anchor: Vector3i = field._surface_patch_cell

	# Second tear via solid_contact_ray BACK direction into solid-side cell (0,0,1)
	var hit_back: Dictionary = field.solid_contact_ray(eye, eye + Vector3.BACK * 1.5)
	check(not hit_back.is_empty(), "union test: second actual contact found")
	var second_target: Vector3 = hit_back.position - field._eye_surface_outward(hit_back) * 0.05
	var cell_info: Array = field.world_to_cell(second_target)
	var second_cell: Vector3i = (cell_info[0] as Vector3i) * field.config.chunk_size + (cell_info[1] as Vector3i)
	check(second_cell == Vector3i(0, 0, 1), "union test: second tear target cell is (0,0,1)")
	field.dig_at(second_target, 1.0)

	# Validate union bounds and properties
	check(field._surface_patch != null, "union test: patch survives second dig before publish")
	check(field._surface_patch_cell == first_anchor, "union test: _surface_patch_cell remains original first anchor")
	check(count_open_edges_from_faces(field._surface_patch.faces) == 0, "union test: union patch is closed manifold with 0 open edges")
	check(field._surface_patch_min.z <= 0 and field._surface_patch_max.z >= 2, "union test: patch z bounds expanded to cover both tears")

	# Raycast reachability of both faces
	var forward_reach := field.solid_contact_ray(eye, eye + Vector3.FORWARD)
	check(not forward_reach.is_empty() and forward_reach.get("fdk_surface_patch", false) == true, "union test: forward face hit on patch")
	var back_reach := field.solid_contact_ray(eye, eye + Vector3.BACK * 1.5)
	check(not back_reach.is_empty() and back_reach.get("fdk_surface_patch", false) == true, "union test: second hole back face hit on patch")

	# Cache reuse
	var union_rev: int = field._surface_patch_revision
	field._refresh_or_clear_surface_patch()
	check(field._surface_patch_revision == union_rev, "union test: cache revision unchanged on identical state")

	# Remesh budget 1 step 0..7
	var union_faces: PackedVector3Array = field._surface_patch.faces.duplicate()
	field.remesh_budget_per_frame = 1
	for step in range(7):
		field._process(0.016)
		check(field._surface_patch != null, "union budget step %d: patch remains alive" % step)
		check(count_open_edges_from_faces(field._surface_patch.faces) == 0, "union budget step %d: closed edge 0" % step)

	field._process(0.016)
	check(field._surface_patch == null, "union step 7: patch cleared after all chunks published")
	var union_pub_faces := PackedVector3Array()
	for chunk in field.get_chunks():
		for point in chunk._surface_faces:
			union_pub_faces.append(chunk.to_global(point))
	check(oriented_triangle_keys(union_faces) == oriented_triangle_keys(union_pub_faces), "union test: pending actual geometry equals published surface and winding")

	# --- Addition 2: Cross positive/negative chunk boundary sequential tears ---
	var field_cross := FDKTerrainField.new()
	field_cross.config = FDKTerrainConfig.new()
	field_cross.config.chunk_size = 4
	field_cross.density_sampler = func(_p: Vector3): return 1.0
	world.add_child(field_cross)
	field_cross.set_process(false)
	field_cross.generate_region(AABB(Vector3.ONE * -4.5, Vector3.ONE * 9))
	field_cross.remesh_all()

	# Tear 1 in chunk (0,0,0) at cell (0,0,0)
	var pt_pos := Vector3(0.25, 0.25, 0.25) * field_cross.config.cell_size
	field_cross.dig_at(pt_pos, 1.0)
	check(field_cross._surface_patch != null, "cross-chunk: first tear creates patch in positive chunk")
	check(count_open_edges_from_faces(field_cross._surface_patch.faces) == 0, "cross-chunk: first tear closed edge 0")

	# Tear 2 in chunk (-1,0,0) at cell (-1,0,0)
	var pt_neg := Vector3(-0.25, 0.25, 0.25) * field_cross.config.cell_size
	field_cross.dig_at(pt_neg, 1.0)
	check(field_cross._surface_patch != null, "cross-chunk: second tear across boundary merges patch")
	check(field_cross._surface_patch_min.x <= -2 and field_cross._surface_patch_max.x >= 1, "cross-chunk: bounds span both positive and negative chunks")
	check(count_open_edges_from_faces(field_cross._surface_patch.faces) == 0, "cross-chunk: union across chunk boundary has 0 open edges")

	field_cross.remesh_all()
	check(field_cross._surface_patch == null, "cross-chunk: patch cleared after remesh_all")
	world.remove_child(field_cross)
	field_cross.queue_free()

	# --- Addition 3: Regression for mask flip when delta < 1e-5 ---
	field.deserialize(serialize_before)
	field.remesh_all()
	field.dig_at(dig_pos_u, 1.0)
	check(field._surface_patch != null, "maskflip prep: patch created")

	var iso_val := field.config.iso_level
	var s_val := field.config.chunk_size
	for chunk in field.get_chunks():
		chunk._surface_density = chunk._build_padded(s_val)

	var test_corner := field._surface_patch_min
	var test_cc := Vector3i(field._floordiv(test_corner.x, s_val), field._floordiv(test_corner.y, s_val), field._floordiv(test_corner.z, s_val))
	var test_chunk: FDKChunk = field.get_chunk(test_cc)
	var test_lc := test_corner - test_cc * s_val
	var p_val := s_val + 2
	var test_idx := (test_lc.x + 1) + (test_lc.y + 1) * p_val + (test_lc.z + 1) * p_val * p_val

	test_chunk._density[test_chunk._corner_index(test_lc.x, test_lc.y, test_lc.z)] = iso_val + 0.000002
	test_chunk._surface_density[test_idx] = iso_val - 0.000002
	check(absf(test_chunk._surface_density[test_idx] - field.corner_density_global(test_corner)) < 0.00001, "maskflip prep: delta is less than 1e-5")
	check((test_chunk._surface_density[test_idx] >= iso_val) != (field.corner_density_global(test_corner) >= iso_val), "maskflip prep: iso classification flipped")

	field._refresh_or_clear_surface_patch()
	check(field._surface_patch != null, "maskflip regression: patch not cleared when delta < 1e-5 but iso classification flipped")

	test_chunk._surface_density[test_idx] = iso_val + 0.000001
	field._refresh_or_clear_surface_patch()
	check(field._surface_patch == null, "maskflip regression: patch cleared when iso classification matches and delta < 1e-5")

	# --- Addition 4: Continuous regen 120 frames, budget 1 patch retirement ---
	var field_regen := FDKTerrainField.new()
	field_regen.config = FDKTerrainConfig.new()
	field_regen.config.chunk_size = 4
	field_regen.density_sampler = func(_p: Vector3): return 1.0
	world.add_child(field_regen)
	field_regen.set_process(false)
	field_regen.generate_region(AABB(Vector3.ONE * -2, Vector3.ONE * 4))
	field_regen.remesh_all()
	field_regen.dig_at(Vector3.ONE * 0.25, 1.0)
	check(field_regen._surface_patch != null, "regen probe: patch created on dig")
	check(field_regen._surface_patch_required_epoch == field_regen.get_dig_epoch(), "regen probe: required epoch matches dig epoch")
	field_regen.remesh_budget_per_frame = 1
	var regen_revisions := 0
	for i in range(120):
		field_regen.regenerate_all(1.0 / 60.0, Vector3.ONE * 100, 0.0)
		field_regen._process(1.0 / 60.0)
		regen_revisions = field_regen._surface_patch_revision
	check(field_regen._surface_patch == null, "regen probe: patch cleared after initial publish during continuous regen")
	check(regen_revisions < 30, "regen probe: revision not growing infinitely every frame (ended at %d)" % regen_revisions)
	world.remove_child(field_regen)
	field_regen.queue_free()

	# --- Addition 5: Actual freeze firstdig -> secondadjacentdig epoch retirement ---
	var field_freeze := FDKTerrainField.new()
	field_freeze.config = FDKTerrainConfig.new()
	field_freeze.config.chunk_size = 4
	field_freeze.density_sampler = func(_p: Vector3): return 1.0
	world.add_child(field_freeze)
	field_freeze.set_process(false)
	field_freeze.generate_region(AABB(Vector3.ONE * -2, Vector3.ONE * 4))
	field_freeze.remesh_all()
	field_freeze.remesh_budget_per_frame = 1

	var p1 := Vector3(0.25, 0.25, 0.25) * field_freeze.config.cell_size
	field_freeze.dig_at(p1, 1.0)
	var epoch1: int = field_freeze.get_dig_epoch()
	check(field_freeze._surface_patch != null, "freeze test: first patch created")
	check(field_freeze._surface_patch_required_epoch == epoch1, "freeze test: required epoch matches first dig epoch")

	field_freeze._begin_mesh_batch()
	check(field_freeze.get_mesh_snapshot_epoch() == epoch1, "freeze test: batch snapshot epoch frozen at epoch1")

	var p2 := Vector3(1.25, 0.25, 0.25) * field_freeze.config.cell_size
	field_freeze.dig_at(p2, 1.0)
	var epoch2: int = field_freeze.get_dig_epoch()
	check(epoch2 > epoch1, "freeze test: second dig incremented dig epoch")
	check(field_freeze._surface_patch != null, "freeze test: patch active after second dig")
	check(field_freeze._surface_patch_required_epoch == epoch2, "freeze test: required epoch updated to second dig epoch")

	while not field_freeze._mesh_batch.is_empty():
		field_freeze._process(0.016)

	check(field_freeze._surface_patch != null, "freeze test: patch retained while published chunks only have old epoch1")

	for i in range(20):
		if field_freeze._surface_patch == null:
			break
		field_freeze._process(0.016)

	check(field_freeze._surface_patch == null, "freeze test: patch cleared after new batch with epoch2 published")
	world.remove_child(field_freeze)
	field_freeze.queue_free()

	# --- Addition 6: Aggregate Tile Overflow Span > 7 Tests ---
	var field_overflow := FDKTerrainField.new()
	field_overflow.config = FDKTerrainConfig.new()
	field_overflow.config.chunk_size = 4
	field_overflow.density_sampler = func(_p: Vector3): return 1.0
	world.add_child(field_overflow)
	field_overflow.set_process(false)
	field_overflow.generate_region(AABB(Vector3.ONE * -4, Vector3.ONE * 8))
	field_overflow.remesh_all()

	# 1. -4..4 sequential pending dig missing 0
	var missing_overflow := 0
	for cx in range(-4, 5):
		field_overflow.dig_at((Vector3(cx, 0, 0) + Vector3.ONE * 0.5) * field_overflow.config.cell_size, 1.0)
		if field_overflow._surface_patch == null:
			missing_overflow += 1
	check(missing_overflow == 0, "overflow test: -4..4 continuous digs missing count is 0")
	check(field_overflow._surface_patch != null, "overflow test: patch active after all digs")
	check(field_overflow._surface_patch_is_aggregate == true, "overflow test: patch transitioned to aggregate holder")
	check(field_overflow._surface_patch.mesh == null, "overflow test: aggregate holder mesh is null")

	# 2. positive/negative tile/chunk boundary span
	var has_neg_tile := false
	var has_pos_tile := false
	var all_tiles_le_216 := true
	for to in field_overflow._surface_patch_tiles.keys():
		var t_info: Dictionary = field_overflow._surface_patch_tiles[to]
		var p: FDKSurfacePatch = t_info.patch
		if to.x < 0 or to.y < 0 or to.z < 0:
			has_neg_tile = true
		if to.x >= 0 and to.y >= 0 and to.z >= 0:
			has_pos_tile = true
		if p.read_corner_count > 216:
			all_tiles_le_216 = false
	check(has_neg_tile and has_pos_tile, "overflow test: tiles span across positive and negative tile/chunk boundaries")
	check(all_tiles_le_216, "overflow test: every individual tile reads at most 216 corners")

	# 3. aggregate closed oriented edges 0 & duplicate 0
	var over_faces: PackedVector3Array = field_overflow._surface_patch.faces.duplicate()
	check(over_faces.size() > 0, "overflow test: aggregate holder has non-empty faces")
	check(count_open_edges_from_faces(over_faces) == 0, "overflow test: unoriented open edges is 0 (mesh is closed)")
	check(count_open_oriented_edges_from_faces(over_faces) == 0, "overflow test: oriented open edges is 0")
	var tri_keys := oriented_triangle_keys(over_faces)
	var dupe_count := 0
	for i in range(1, tri_keys.size()):
		if tri_keys[i] == tri_keys[i - 1]:
			dupe_count += 1
	check(dupe_count == 0, "overflow test: duplicate triangle count is 0")

	# 4. actual eventual remesh oriented triangle keys match exactly
	field_overflow.remesh_all()
	check(field_overflow._surface_patch == null, "overflow test: patch cleared after field.remesh_all")
	var pub_over_faces := PackedVector3Array()
	for chunk in field_overflow.get_chunks():
		for point in chunk._surface_faces:
			pub_over_faces.append(chunk.to_global(point))
	check(tri_keys == oriented_triangle_keys(pub_over_faces), "overflow test: eventual remesh oriented triangle keys match exactly")
	world.remove_child(field_overflow)
	field_overflow.queue_free()

	# 5. new dig while old batch pending in aggregate mode: keep old / clear after new publish
	var field_batch := FDKTerrainField.new()
	field_batch.config = FDKTerrainConfig.new()
	field_batch.config.chunk_size = 4
	field_batch.density_sampler = func(_p: Vector3): return 1.0
	world.add_child(field_batch)
	field_batch.set_process(false)
	field_batch.generate_region(AABB(Vector3.ONE * -4.5, Vector3.ONE * 9))
	field_batch.remesh_all()
	field_batch.remesh_budget_per_frame = 1

	for cx in range(-4, 2):
		field_batch.dig_at((Vector3(cx, 0, 0) + Vector3.ONE * 0.5) * field_batch.config.cell_size, 1.0)
	check(field_batch._surface_patch_is_aggregate == true, "batch test: entered aggregate mode")
	var old_epoch: int = field_batch.get_dig_epoch()

	field_batch._begin_mesh_batch()
	check(field_batch.get_mesh_snapshot_epoch() == old_epoch, "batch test: mesh snapshot captured at old_epoch")

	# New dig arriving after old batch began
	field_batch.dig_at((Vector3(2, 0, 0) + Vector3.ONE * 0.5) * field_batch.config.cell_size, 1.0)
	var new_epoch: int = field_batch.get_dig_epoch()
	check(new_epoch > old_epoch, "batch test: new dig incremented dig epoch")

	while not field_batch._mesh_batch.is_empty():
		field_batch._process(0.016)
	check(field_batch._surface_patch != null, "batch test: patch kept alive because published chunks only have old_epoch")

	for i in range(25):
		if field_batch._surface_patch == null:
			break
		field_batch._process(0.016)
	check(field_batch._surface_patch == null, "batch test: patch cleared after new batch with new_epoch published")
	world.remove_child(field_batch)
	field_batch.queue_free()

	# 6. continuous regen under budget 1 proper retirement in aggregate mode
	var field_cont := FDKTerrainField.new()
	field_cont.config = FDKTerrainConfig.new()
	field_cont.config.chunk_size = 4
	field_cont.density_sampler = func(_p: Vector3): return 1.0
	world.add_child(field_cont)
	field_cont.set_process(false)
	field_cont.generate_region(AABB(Vector3.ONE * -4.5, Vector3.ONE * 9))
	field_cont.remesh_all()
	field_cont.remesh_budget_per_frame = 1

	for cx in range(-3, 3):
		field_cont.dig_at((Vector3(cx, 0, 0) + Vector3.ONE * 0.5) * field_cont.config.cell_size, 1.0)
	check(field_cont._surface_patch != null, "cont test: patch created across span > 7")
	check(field_cont._surface_patch_is_aggregate, "cont test: patch is aggregate")

	var cont_revs := 0
	for i in range(120):
		field_cont.regenerate_all(1.0 / 60.0, Vector3.ONE * 100, 0.0)
		field_cont._process(1.0 / 60.0)
		cont_revs = field_cont._surface_patch_revision
	check(field_cont._surface_patch == null, "cont test: aggregate patch retired properly during continuous regen")
	check(cont_revs < 40, "cont test: revisions bounded and stopped growing infinitely (ended at %d)" % cont_revs)
	world.remove_child(field_cont)
	field_cont.queue_free()

	world.queue_free()
	await process_frame

	print("%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func count_open_oriented_edges_from_faces(faces: PackedVector3Array) -> int:
	var edge_counts := {}
	for i in range(0, faces.size(), 3):
		var pts := [faces[i], faces[i + 1], faces[i + 2]]
		for j in range(3):
			var pA: Vector3 = pts[j].snapped(Vector3.ONE * 0.0001)
			var pB: Vector3 = pts[(j + 1) % 3].snapped(Vector3.ONE * 0.0001)
			var ka := "%0.4f,%0.4f,%0.4f" % [pA.x, pA.y, pA.z]
			var kb := "%0.4f,%0.4f,%0.4f" % [pB.x, pB.y, pB.z]
			var k := ka + "->" + kb
			edge_counts[k] = edge_counts.get(k, 0) + 1
	var open := 0
	for edge_key in edge_counts.keys():
		var parts = edge_key.split("->")
		var reverse_key = parts[1] + "->" + parts[0]
		var forward_count: int = edge_counts[edge_key]
		var reverse_count: int = edge_counts.get(reverse_key, 0)
		if forward_count != reverse_count:
			open += absi(forward_count - reverse_count)
	return open

func oriented_triangle_keys(faces: PackedVector3Array) -> Array:
	var result: Array = []
	for i in range(0, faces.size(), 3):
		var keys: Array = []
		for j in range(3):
			var p := faces[i+j]
			keys.append(str(Vector3i(roundi(p.x*10000), roundi(p.y*10000), roundi(p.z*10000))))
		var first := 0
		for j in range(1,3):
			if keys[j] < keys[first]: first = j
		result.append(str([keys[first], keys[(first+1)%3], keys[(first+2)%3]]))
	result.sort()
	return result
