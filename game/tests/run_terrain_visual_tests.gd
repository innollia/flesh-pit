extends SceneTree

## What the flesh's own faces tell (kit terrain mesh + shader inputs, and the
## tear feel that reads the same tissue table). No Main, no save.
## A. A face shows the tissue of the cell an aimed tear takes from it
##    (findings: "면 텍스처와 잡기 대상 칸이 서로 다른 칸을 본다").
## B. New flesh: vertex colour r = 1 - regrowth progress of the wall's empty
##    side, only where it really regrows, equal on chunk-border duplicates,
##    never moving a vertex.
## C. The squeeze preview the shader draws (FDKTissueRules.contract_preview)
##    held against the real per-corner squeeze lists of the chunks.
## D. Per-tissue pull, wound, blood, strands and recoil from one table, with
##    plain flesh unchanged.
## The shader itself cannot run headless: its formulas have GDScript mirrors
## (FDKPullShape, FDKTissueRules.contract_preview) and the checks here read the
## shader text for the lines that must match them.

const SHADER := "res://addons/flesh_dig_kit/terrain/fdk_terrain_surface.gdshader"
const FAR := Vector3(1000, 1000, 1000)
const FPTearFeel := preload("res://main/scripts/fp_tear_feel.gd")

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

func make_field(density: Callable, tissue: Callable) -> FDKTerrainField:
	var field := FDKTerrainField.new()
	field.config = FDKTerrainConfig.new()
	field.density_sampler = density
	field.tissue_sampler = tissue
	root.add_child(field)
	return field

func solid(_p: Vector3) -> float:
	return 1.0

func tunnel(field: FDKTerrainField, from: Vector3, step: Vector3, count: int, wide: bool = false) -> void:
	var cs: float = field.config.cell_size
	for i in range(count):
		var p := from + step * cs * i
		field.dig_at(p, 1.0)
		if wide:
			var side := Vector3(0, 1, 0) if absf(step.y) < 0.5 else Vector3(1, 0, 0)
			var other := step.cross(side).abs()
			field.dig_at(p + side * cs, 1.0)
			field.dig_at(p + other * cs, 1.0)
			field.dig_at(p + (side + other) * cs, 1.0)

func shown_tissue(mesh: Mesh, surface: int) -> int:
	for t in range(FDKChunk.TISSUE_TEXTURES.size()):
		if mesh.surface_get_material(surface) == FDKChunk.terrain_material(t):
			return t
	return -1

## Every published triangle of the field's chunks:
## {tissue, a, b, c (world), ra, rb, rc (regrowth 0..1), chunk}.
func triangles(field: FDKTerrainField) -> Array:
	var out: Array = []
	for ch in field.get_chunks():
		var chunk: FDKChunk = ch
		var mesh: Mesh = chunk._mesh_instance.mesh
		if mesh == null:
			continue
		for si in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var has_color: bool = arrays[Mesh.ARRAY_COLOR] != null
			var k := PackedColorArray()
			if has_color:
				k = arrays[Mesh.ARRAY_COLOR]
			var t := shown_tissue(mesh, si)
			for i in range(0, v.size(), 3):
				out.append({
					"tissue": t, "chunk": chunk.chunk_coord, "colored": has_color,
					"a": chunk.position + v[i], "b": chunk.position + v[i + 1], "c": chunk.position + v[i + 2],
					"ra": 1.0 - k[i].r if has_color else 0.0,
					"rb": 1.0 - k[i + 1].r if has_color else 0.0,
					"rc": 1.0 - k[i + 2].r if has_color else 0.0,
				})
	return out

func near_cell_face(p: Vector3, cs: float, eps: float = 0.0005) -> bool:
	var q := p / cs
	for v in [q.x, q.y, q.z]:
		if absf(v - roundf(v)) < eps:
			return true
	return false

## Mismatches of shown tissue against the cell the game's aim takes
## (main.gd _terrain_target: hit + into * cell * 0.5, floored), sampled at the
## triangle centroid. Returns [wrong, counted, facings seen at a boundary].
func aim_mismatch(field: FDKTerrainField, tris: Array) -> Array:
	var cs: float = field.config.cell_size
	var wrong := 0
	var counted := 0
	var facings := {}
	for tri in tris:
		var a: Vector3 = tri.a
		var b: Vector3 = tri.b
		var c: Vector3 = tri.c
		var outward: Vector3 = -(b - a).cross(c - a).normalized()
		var sample: Vector3 = (a + b + c) / 3.0 - outward * cs * 0.5
		if near_cell_face(sample, cs):
			continue # the aim itself is undecided on a cell face
		counted += 1
		var cell: Vector3 = (sample / cs).floor()
		var aimed: int = field.tissue_at((cell + Vector3.ONE * 0.5) * cs)
		if aimed != int(tri.tissue):
			wrong += 1
		if aimed != FDKTissueRules.COMPRESSIVE:
			facings[Vector3i(outward.round())] = true
	return [wrong, counted, facings]

func layered(p: Vector3) -> int:
	if p.x >= 8.0:
		return FDKTissueRules.CONTRACTILE
	if p.x > 2.0 and p.x < 2.5:
		return FDKTissueRules.MEMBRANE
	if p.y > 1.5:
		return FDKTissueRules.NERVE
	return FDKTissueRules.COMPRESSIVE

func run() -> void:
	test_face_tissue()
	test_new_flesh()
	test_squeeze_preview()
	test_tissue_look()
	print("%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

# --- A ---------------------------------------------------------------------
func test_face_tissue() -> void:
	var field := make_field(solid, layered)
	# through the membrane slab both ways, across the chunk border at x = 8
	# where the tissue changes too, and up into the nerve layer
	tunnel(field, Vector3(-1.25, 0.25, 0.25), Vector3(1, 0, 0), 12, true)
	tunnel(field, Vector3(5.25, 0.25, -2.25), Vector3(-1, 0, 0), 8, true)
	tunnel(field, Vector3(6.25, 0.25, 3.25), Vector3(1, 0, 0), 9, true)
	tunnel(field, Vector3(-3.25, 0.25, 0.25), Vector3(0, 1, 0), 6, true)
	# two that stop at the slab, one from each side
	tunnel(field, Vector3(3.25, 0.25, 5.25), Vector3(-1, 0, 0), 2, true)
	tunnel(field, Vector3(1.25, 0.25, -5.25), Vector3(1, 0, 0), 2, true)
	# one with muscle under its floor
	tunnel(field, Vector3(9.25, 2.25, -3.25), Vector3(1, 0, 0), 4, true)
	field.remesh_all()
	var tris := triangles(field)
	var m := aim_mismatch(field, tris)
	check(int(m[1]) > 400, "the fixture has faces to judge (%d)" % int(m[1]))
	check(int(m[0]) == 0, "every face shows the tissue of the cell an aimed tear takes (%d of %d differ)" % [int(m[0]), int(m[1])])
	var facings: Dictionary = m[2]
	var axes := 0
	for f in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if facings.has(f):
			axes += 1
	check(axes == 6, "tissue borders are judged on faces looking all six ways (%d: %s)" % [axes, str(facings.keys())])
	var seen := {}
	for tri in tris:
		seen[int(tri.tissue)] = true
	check(seen.has(FDKTissueRules.MEMBRANE) and seen.has(FDKTissueRules.CONTRACTILE) and seen.has(FDKTissueRules.NERVE), "membrane, contractile and nerve faces are all in the fixture")
	# the s4 symptom: a wall of plain flesh in front of the membrane slab, seen
	# from the tunnel dug toward +x, must not wear the membrane pattern
	var cs: float = field.config.cell_size
	var plain_wall := 0
	var plain_wall_wrong := 0
	for tri in tris:
		var a: Vector3 = tri.a
		var b: Vector3 = tri.b
		var c: Vector3 = tri.c
		var outward: Vector3 = -(b - a).cross(c - a).normalized()
		var sample: Vector3 = (a + b + c) / 3.0 - outward * cs * 0.5
		if outward.x < -0.9 and sample.x > 1.55 and sample.x < 1.95:
			plain_wall += 1
			if int(tri.tissue) != FDKTissueRules.COMPRESSIVE:
				plain_wall_wrong += 1
	# the temporary tear patch draws the same faces by the same rule
	var patch := FDKSurfacePatch.new(field)
	root.add_child(patch)
	var ok_patch: bool = patch.build_region(Vector3i(2, -1, -1), Vector3i(6, 3, 3))
	var patch_wrong := 0
	var patch_counted := 0
	if ok_patch and patch.mesh != null:
		for si in range(patch.mesh.get_surface_count()):
			var v: PackedVector3Array = patch.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var t := shown_tissue(patch.mesh, si)
			var list: Array = []
			for i in range(0, v.size(), 3):
				list.append({"tissue": t, "a": v[i], "b": v[i + 1], "c": v[i + 2]})
			var pm := aim_mismatch(field, list)
			patch_wrong += int(pm[0])
			patch_counted += int(pm[1])
	check(patch_counted > 20 and patch_wrong == 0, "the tear patch shows the aimed cell's tissue too (%d of %d differ)" % [patch_wrong, patch_counted])
	patch.queue_free()
	# a wall dug up to the slab: the cell before it is plain flesh
	var f2 := make_field(solid, layered)
	tunnel(f2, Vector3(-0.75, 0.25, 0.25), Vector3(1, 0, 0), 5, true)
	f2.remesh_all()
	var end_plain := 0
	var end_other := 0
	for tri in triangles(f2):
		var a: Vector3 = tri.a
		var b: Vector3 = tri.b
		var c: Vector3 = tri.c
		var outward: Vector3 = -(b - a).cross(c - a).normalized()
		var sample: Vector3 = (a + b + c) / 3.0 - outward * cs * 0.5
		# the end wall of the tunnel (its last dug cell is x 1.0..1.5)
		if outward.x < -0.9 and sample.x > 1.55 and sample.x < 1.95:
			if int(tri.tissue) == FDKTissueRules.COMPRESSIVE:
				end_plain += 1
			else:
				end_other += 1
	check(end_plain > 0 and end_other == 0, "plain flesh in front of the membrane does not wear the membrane pattern (%d plain, %d other)" % [end_plain, end_other])
	check(plain_wall_wrong == 0, "nor inside the longer tunnel (%d of %d)" % [plain_wall_wrong, plain_wall])
	# a sprayed cell: the faces looking into it are melted, whichever way they face
	var f3 := make_field(solid, func(_p: Vector3) -> int: return FDKTissueRules.COMPRESSIVE)
	f3.spray_sphere(Vector3(1.25, 1.25, 1.25), 0.5)
	f3.remesh_all()
	var melted := 0
	var not_melted := 0
	for tri in triangles(f3):
		if int(tri.tissue) == FDKTissueRules.MELTED:
			melted += 1
		else:
			not_melted += 1
	check(melted > 0 and not_melted == 0, "faces round a sprayed cell are melted on every side (%d melted, %d not)" % [melted, not_melted])
	field.queue_free()
	f2.queue_free()
	f3.queue_free()

# --- B ---------------------------------------------------------------------
func max_regrow(tris: Array) -> float:
	var top := 0.0
	for tri in tris:
		top = maxf(top, maxf(float(tri.ra), maxf(float(tri.rb), float(tri.rc))))
	return top

func mean_regrow(tris: Array) -> float:
	var sum := 0.0
	var n := 0
	for tri in tris:
		for key in ["ra", "rb", "rc"]:
			sum += float(tri[key])
			n += 1
	return sum / maxf(1.0, float(n))

## The value the mesh should carry at world vertex p: the largest regrowth
## progress among the corners of the cell holding it.
func expected_regrow(field: FDKTerrainField, p: Vector3) -> float:
	var cs: float = field.config.cell_size
	var cell := Vector3i((p / cs).floor())
	var top := 0.0
	for k in range(8):
		top = maxf(top, field.corner_regrow_global(cell + Vector3i(k & 1, (k >> 1) & 1, (k >> 2) & 1)))
	return top

func test_new_flesh() -> void:
	var plain := func(_p: Vector3) -> int: return FDKTissueRules.COMPRESSIVE
	var field := make_field(solid, plain)
	var cs: float = field.config.cell_size
	# a tunnel through the chunk border at x = 8 and one along it at z = 0
	tunnel(field, Vector3(6.25, 0.25, 2.25), Vector3(1, 0, 0), 8, true)
	tunnel(field, Vector3(2.25, 0.25, -0.25), Vector3(1, 0, 0), 6, true)
	field.remesh_all()
	var fresh := triangles(field)
	check(fresh.size() > 100 and max_regrow(fresh) == 0.0, "a freshly torn wall carries no new-flesh tint (max %.3f)" % max_regrow(fresh))
	var fresh_colored := 0
	for tri in fresh:
		if tri.colored:
			fresh_colored += 1
	check(fresh_colored == 0, "nothing regrowing: no colour array is built at all (%d coloured triangles)" % fresh_colored)
	for i in range(20):
		field.regenerate_all(1.0, FAR, 0.0)
	field.remesh_all()
	var early := triangles(field)
	var early_mean := mean_regrow(early)
	check(max_regrow(early) > 0.1, "regrowth under way shows on the wall (max %.3f)" % max_regrow(early))
	# each vertex carries the progress of its cell's emptiest-side corner
	var off := 0
	var judged := 0
	for tri in early:
		for pair in [[tri.a, tri.ra], [tri.b, tri.rb], [tri.c, tri.rc]]:
			var p: Vector3 = pair[0]
			if near_cell_face(p, cs):
				continue
			judged += 1
			if absf(expected_regrow(field, p) - float(pair[1])) > 0.006:
				off += 1
	check(judged > 300 and off == 0, "vertex tint = progress of the nearest-to-closing corner of its cell (%d of %d off)" % [off, judged])
	# progress = that corner's own density over iso: an independent reading
	var chunk0: FDKChunk = field.get_chunk(field.world_to_chunk_coord(Vector3(6.75, 0.75, 2.75)))
	var lc := Vector3i(((Vector3(6.5, 0.5, 2.5) - chunk0.position) / cs).round())
	var d_corner: float = chunk0.get_density_at_corner(lc.x, lc.y, lc.z)
	var g_corner := Vector3i((Vector3(6.5, 0.5, 2.5) / cs).round())
	check(d_corner > 0.0 and d_corner < 0.5 and absf(field.corner_regrow_global(g_corner) - d_corner / 0.5) < 0.0001, "progress is the regrowing corner's density over iso (%.3f / 0.5)" % d_corner)
	# the same vertex drawn by two chunks has the same tint
	var by_pos := {}
	for tri in early:
		for pair in [[tri.a, tri.ra], [tri.b, tri.rb], [tri.c, tri.rc]]:
			var p: Vector3 = pair[0]
			var key := Vector3i((p * 2000.0).round())
			if not by_pos.has(key):
				by_pos[key] = {}
			var per_chunk: Dictionary = by_pos[key]
			per_chunk[tri.chunk] = float(pair[1])
	var shared := 0
	var split := 0
	var shared_tinted := 0
	for key in by_pos.keys():
		var per_chunk: Dictionary = by_pos[key]
		if per_chunk.size() < 2:
			continue
		shared += 1
		var vals: Array = per_chunk.values()
		for v in vals:
			if float(v) != float(vals[0]):
				split += 1
				break
		if float(vals[0]) > 0.0:
			shared_tinted += 1
	check(shared > 20 and shared_tinted > 5 and split == 0, "chunk-border duplicates carry one value (%d shared, %d tinted, %d split)" % [shared, shared_tinted, split])
	# colour only: the tinted mesh is the collider's triangles, vertex for vertex
	var moved := 0
	var compared := 0
	for ch in field.get_chunks():
		var chunk: FDKChunk = ch
		var mesh: Mesh = chunk._mesh_instance.mesh
		if mesh == null:
			continue
		var drawn := {}
		for si in range(mesh.get_surface_count()):
			for v in (mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				drawn[v] = int(drawn.get(v, 0)) + 1
		for v in chunk._surface_faces:
			compared += 1
			if int(drawn.get(v, 0)) <= 0:
				moved += 1
			else:
				drawn[v] = int(drawn[v]) - 1
	check(compared > 300 and moved == 0, "tinted faces are the published collision triangles, unmoved (%d of %d differ)" % [moved, compared])
	# closer to closing = stronger
	for i in range(8):
		field.regenerate_all(1.0, FAR, 0.0)
	field.remesh_all()
	var late := triangles(field)
	check(mean_regrow(late) > early_mean * 1.2 and max_regrow(late) <= 1.0, "the tint grows as the wall nears closing (%.3f -> %.3f)" % [early_mean, mean_regrow(late)])
	# where growth is held right now is the shader's to hide: the field hands it the spheres
	field.regen_blockers = [Vector4(3.0, 1.0, 0.0, 0.7)]
	field.regenerate_all(0.0, Vector3(7.0, 0.5, 2.5), 0.9)
	var holds = FDKChunk.terrain_material(FDKTissueRules.COMPRESSIVE).get_shader_parameter("regrow_hold")
	check(holds != null and (holds as PackedVector4Array).size() == FDKChunk.REGROW_HOLDS and holds[0] == Vector4(7.0, 0.5, 2.5, 0.9) and holds[1] == Vector4(3.0, 1.0, 0.0, 0.7) and holds[2] == Vector4.ZERO, "the body's protect sphere and the blockers reach the shader as holds")
	field.regen_blockers = []
	check(float(FDKChunk.terrain_material(FDKTissueRules.MELTED).get_shader_parameter("regrow_show")) == 0.0 and float(FDKChunk.terrain_material(FDKTissueRules.FAT).get_shader_parameter("regrow_show")) == 1.0, "melted faces never show new flesh, living tissue does")
	field.queue_free()
	# sprayed open: nothing grows, nothing is tinted; a dug cell beside it is
	var f2 := make_field(solid, plain)
	f2.spray_sphere(Vector3(2.25, 1.25, 1.25), 0.8)
	f2.dig_at(Vector3(5.25, 1.25, 1.25), 1.0)
	f2.remesh_all()
	for i in range(30):
		f2.regenerate_all(1.0, FAR, 0.0)
	f2.remesh_all()
	var sprayed_top := 0.0
	var dug_top := 0.0
	for tri in triangles(f2):
		var top := maxf(float(tri.ra), maxf(float(tri.rb), float(tri.rc)))
		if (tri.a as Vector3).x < 3.8:
			sprayed_top = maxf(sprayed_top, top)
		else:
			dug_top = maxf(dug_top, top)
	check(sprayed_top == 0.0 and dug_top > 0.2, "a sprayed opening shows no new flesh, a dug hole beside it does (%.3f, %.3f)" % [sprayed_top, dug_top])
	f2.queue_free()
	# a natural surface with part-filled corners was never dug: no tint, no array
	var f3 := make_field(func(p: Vector3) -> float: return clampf(0.3 + (1.0 - p.y) * 0.6, 0.0, 1.0), plain)
	f3.generate_region(AABB(Vector3(0.5, 0.0, 0.5), Vector3(2, 2, 2)))
	f3.remesh_all()
	for i in range(10):
		f3.regenerate_all(1.0, FAR, 0.0)
	for ch in f3.get_chunks():
		(ch as FDKChunk)._dirty = true
	f3.remesh_all()
	var natural := triangles(f3)
	var natural_colored := 0
	for tri in natural:
		if tri.colored:
			natural_colored += 1
	check(natural.size() > 50 and natural_colored == 0, "a natural half-dense surface is not new flesh (%d of %d coloured)" % [natural_colored, natural.size()])
	f3.queue_free()
	# tissue that never regrows, and the squeeze of muscle, are not new flesh
	var f4 := make_field(solid, func(p: Vector3) -> int: return FDKTissueRules.MEMBRANE if p.x < 4.0 else FDKTissueRules.CONTRACTILE)
	tunnel(f4, Vector3(1.25, 1.25, 1.25), Vector3(1, 0, 0), 3, true)
	tunnel(f4, Vector3(5.25, 1.25, 1.25), Vector3(1, 0, 0), 3, true)
	f4.remesh_all()
	for i in range(30):
		f4.regenerate_all(1.0, Vector3(6.0, 1.5, 1.5), 3.0) # muscle held, membrane free but inert
	# full squeeze on the muscle walls (density pushed up by CONTRACT_GAIN)
	f4.step_contraction(0.0, Vector3(6.0, 1.5, 1.5), 50.0)
	var squeezed := 0
	for step in range(80):
		f4.step_contraction(0.1, Vector3(6.0, 1.5, 1.5), 50.0)
		for ch in f4.get_chunks():
			if (ch as FDKChunk)._has_contract:
				squeezed += 1
	f4.remesh_all()
	check(squeezed > 0 and max_regrow(triangles(f4)) == 0.0, "membrane and a squeezing muscle wall carry no new-flesh tint (max %.3f)" % max_regrow(triangles(f4)))
	f4.queue_free()
	# the shader reads it the way the mesh writes it
	var code := FileAccess.get_file_as_string(SHADER)
	var vtx := code.substr(code.find("void vertex()"), code.find("void fragment()") - code.find("void vertex()"))
	var frag := code.substr(code.find("void fragment()"))
	check(vtx.contains("1.0 - COLOR.r") and vtx.contains("regrow_hold[i]"), "the shader takes 1 - COLOR.r and applies the holds")
	check(frag.contains("smoothstep(0.2, 1.0, vregrow) * (1.0 - wound)"), "the tint starts after regrowth is under way and yields to a fresh wound")
	var motion := vtx.substr(0, vtx.find("POSITION = clip"))
	check(not motion.contains("vregrow") and not motion.contains("vsqueeze") and not motion.contains("COLOR"), "new flesh and the squeeze preview move no vertex")

# --- C ---------------------------------------------------------------------
func test_squeeze_preview() -> void:
	var R := FDKTissueRules
	var muscle := func(_p: Vector3) -> int: return FDKTissueRules.CONTRACTILE
	var field := make_field(solid, muscle)
	var cs: float = field.config.cell_size
	var s: int = field.config.chunk_size
	tunnel(field, Vector3(1.25, 1.25, 1.25), Vector3(1, 0, 0), 22, true) # crosses x = 8
	tunnel(field, Vector3(3.25, 1.25, 3.25), Vector3(0, 0, 1), 8, true)
	field.remesh_all()
	var near := Vector3(5.0, 1.5, 1.5)
	field.step_contraction(0.0, near, 60.0)
	# the real squeeze lists: global corner -> phase
	var listed := {}
	var phase_wrong := 0
	for ch in field.get_chunks():
		var chunk: FDKChunk = ch
		var n := s + 1
		for k in range(chunk._contract_idx.size()):
			var i: int = chunk._contract_idx[k]
			var l := Vector3i(i % n, (i / n) % n, i / (n * n))
			var g := chunk.chunk_coord * s + l
			listed[g] = float(chunk._contract_phase[k])
			if absf(float(chunk._contract_phase[k]) - R.contract_phase(Vector3(g) * cs)) > 0.0001:
				phase_wrong += 1
	check(listed.size() > 100 and phase_wrong == 0, "the chunks squeeze each corner on FDKTissueRules.contract_phase of its own position (%d corners, %d off)" % [listed.size(), phase_wrong])
	# every published muscle vertex against the corners that really squeeze it
	var verts := {}
	for tri in triangles(field):
		if int(tri.tissue) != R.CONTRACTILE:
			continue
		for p in [tri.a, tri.b, tri.c]:
			if not near_cell_face(p, cs):
				verts[p] = true
	var live := 0
	var dead := 0
	var covered := 0 # the whole lead before the first real squeeze is previewed
	var blind := 0 # nothing at all shows in that lead
	var clench_samples := 0
	var clench_on := 0 # previewed while its first corner is already clenching
	var on_total := 0
	var lead_sum := 0.0
	var lead_max := 0.0
	var step := 0.05
	for p in verts.keys():
		var cell := Vector3i(((p as Vector3) / cs).floor())
		var starts: Array[float] = []
		for k in range(8):
			var g := cell + Vector3i(k & 1, (k >> 1) & 1, (k >> 2) & 1)
			if listed.has(g):
				# this corner starts to squeeze when time + phase = 0 (mod period)
				starts.append(fposmod(-float(listed[g]), R.CONTRACT_PERIOD))
		if starts.is_empty():
			dead += 1
			continue
		# the corners of one cell start in a run; the wall's first squeeze of
		# a cycle is the start that follows the longest rest
		starts.sort()
		var first_real: float = starts[0]
		var rest: float = starts[0] + R.CONTRACT_PERIOD - starts[starts.size() - 1]
		for i in range(1, starts.size()):
			if starts[i] - starts[i - 1] > rest:
				rest = starts[i] - starts[i - 1]
				first_real = starts[i]
		live += 1
		var base: float = R.CONTRACT_PERIOD * 4.0 + first_real
		var shown := 0
		var slots := int(R.CONTRACT_SHOW_LEAD / step) - 1
		for i in range(1, slots + 1):
			if R.contract_preview(p, base - step * i, cs, s) > 0.0:
				shown += 1
		if shown == slots:
			covered += 1
		if shown == 0:
			blind += 1
		# how long it has been on when the first corner starts
		var lead := 0.0
		for i in range(1, 160):
			if R.contract_preview(p, base - step * i, cs, s) <= 0.0:
				break
			lead = step * i
		lead_sum += lead
		lead_max = maxf(lead_max, lead)
		# its first corner rising and held: the wall moves, the preview is over
		for i in range(1, int((R.CONTRACT_RISE + R.CONTRACT_HOLD) / step)):
			clench_samples += 1
			if R.contract_preview(p, base + step * i, cs, s) > 0.0:
				clench_on += 1
		for i in range(160):
			if R.contract_preview(p, step * i, cs, s) > 0.0:
				on_total += 1
	var on_mean: float = float(on_total) * step / float(maxi(live, 1))
	var lead_mean: float = lead_sum / float(maxi(live, 1))
	print("  squeeze preview: %d vertices; whole lead shown on %d, nothing shown on %d, no squeezing corner in the cell %d; shown %.2f s before the first real squeeze on average (longest %.2f), on %.2f s of each %.1f s; still on while clenching %d of %d samples" % [live, covered, blind, dead, lead_mean, lead_max, on_mean, R.CONTRACT_PERIOD, clench_on, clench_samples])
	check(live > 200, "muscle walls with squeezing corners are in the fixture (%d vertices)" % live)
	check(blind == 0, "no wall starts to squeeze without having been previewed (%d of %d)" % [blind, live])
	check(float(covered) / float(live) > 0.95, "the whole %.1f s lead before a wall's first squeeze is previewed (%d of %d)" % [R.CONTRACT_SHOW_LEAD, covered, live])
	check(float(dead) / float(live + dead) < 0.05, "vertices previewed with no squeezing corner in their cell stay rare (%d of %d)" % [dead, live + dead])
	check(on_mean < R.CONTRACT_SHOW_LEAD * 1.5 and on_mean > R.CONTRACT_SHOW_LEAD * 0.8, "a wall is previewed for about the lead each cycle, not half of it (%.2f s)" % on_mean)
	# (a nearer corner that starts later may still be leading in)
	check(float(clench_on) / float(clench_samples) < 0.15, "the preview is mostly over once the wall's first corner clenches (%d of %d samples on)" % [clench_on, clench_samples])
	# one corner, exactly: its lead-in rises to the start and is gone at it
	var c0 := Vector3(4.0, 1.0, 1.0)
	var start0: float = R.CONTRACT_PERIOD * 2.0 - R.contract_phase(c0)
	check(absf(R.contract_lead_in(start0 - 0.4 + R.contract_phase(c0)) - 0.75) < 0.001 and R.contract_lead_in(start0 + 0.01 + R.contract_phase(c0)) == 0.0 and R.contract_lead_in(start0 - R.CONTRACT_SHOW_LEAD - 0.01 + R.contract_phase(c0)) == 0.0, "a corner's lead-in runs the lead time up to its start and ends there")
	check(R.contract_envelope(start0 - 0.4 + R.contract_phase(c0)) == 0.0 and R.contract_envelope(start0 + 0.4 + R.contract_phase(c0)) > 0.0, "the real squeeze of that corner is zero through its lead-in and rises after")
	# per point, not per chunk: two walls of one chunk 3 m apart are previewed at different times
	var p1 := Vector3(1.3, 1.1, 1.3)
	var p2 := Vector3(4.3, 1.1, 1.3)
	var differ := 0
	for i in range(160):
		var t := 0.05 * i
		if absf(R.contract_preview(p1, t, cs, s) - R.contract_preview(p2, t, cs, s)) > 0.2:
			differ += 1
	check(field.world_to_chunk_coord(p1) == field.world_to_chunk_coord(p2) and differ > 20, "the preview runs along the wall as a wave inside one chunk (%d of 160 samples differ)" % differ)
	# off the rest of the cycle
	var on := 0
	for i in range(160):
		if R.contract_preview(p1, 0.05 * i, cs, s) > 0.0:
			on += 1
	check(on > 0 and on < 120, "the preview is off for most of the cycle (%d of 160 samples on)" % on)
	# the shader gets the field's own clock, on the muscle material only
	field.step_contraction(0.25, near, 8.0)
	var mat := FDKChunk.terrain_material(R.CONTRACTILE)
	check(is_equal_approx(float(mat.get_shader_parameter("contract_clock")), field.contract_time) and field.contract_time > 0.0, "the shader's squeeze clock is the field's contract_time")
	check(mat.get_shader_parameter("contract_near") == Vector4(near.x, near.y, near.z, 8.0), "the preview is drawn only where the squeeze is stepped")
	check(float(mat.get_shader_parameter("contract_cell")) == cs and float(mat.get_shader_parameter("contract_chunk")) == float(s), "the shader steps on the field's grid")
	check(float(mat.get_shader_parameter("contract_show")) == 1.0 and float(FDKChunk.terrain_material(R.COMPRESSIVE).get_shader_parameter("contract_show")) == 0.0 and float(FDKChunk.terrain_material(R.NERVE).get_shader_parameter("contract_show")) == 0.0, "only muscle faces show the preview")
	check(float(mat.get_shader_parameter("contract_period")) == R.CONTRACT_PERIOD and float(mat.get_shader_parameter("contract_wave")) == R.CONTRACT_WAVE and float(mat.get_shader_parameter("contract_lead")) == R.CONTRACT_SHOW_LEAD and mat.get_shader_parameter("contract_dir") == R.CONTRACT_DIR and mat.get_shader_parameter("contract_wobble") == R.CONTRACT_WOBBLE, "period, wave, lead, direction and wobble come from FDKTissueRules")
	var code := FileAccess.get_file_as_string(SHADER)
	var vtx := code.substr(code.find("void vertex()"), code.find("void fragment()") - code.find("void vertex()"))
	check(vtx.contains("FDKTissueRules.contract_preview"), "the shader names its measured mirror")
	check(vtx.contains("(dot(cp, contract_dir) / contract_wave + sin(cp.x * contract_wobble.x + cp.z * contract_wobble.y) * contract_wobble.z) * contract_period"), "the shader's phase is contract_phase")
	check(vtx.contains("mod(contract_clock + phase, contract_period)") and vtx.contains("(t_in_cycle - (contract_period - contract_lead)) / contract_lead"), "the shader's lead-in is contract_lead_in on the field clock")
	check(vtx.contains("floor(q)") and vtx.contains("wpos / contract_cell") and vtx.contains("mod(corner, contract_chunk)"), "per point: the corners of the vertex's own cell, chunk-border corners left out")
	check(vtx.contains("1.0 - smoothstep(contract_reach.x, contract_reach.y, distance(q, corner))") and vtx.contains("if (t_in_cycle < contract_clench)") and vtx.contains("lead_in * (1.0 - busy)"), "near corners only, off while one clenches, as the mirror")
	check(float(mat.get_shader_parameter("contract_clench")) == R.CONTRACT_RISE + R.CONTRACT_HOLD and mat.get_shader_parameter("contract_reach") == Vector2(R.CONTRACT_NEAR_FROM, R.CONTRACT_NEAR_TO), "clench time and corner reach come from FDKTissueRules")
	check(R.CONTRACT_WARN == 1.0, "the sound's lead is untouched")
	field.queue_free()

# --- D ---------------------------------------------------------------------
func make_gore_stub() -> Node3D:
	var src := GDScript.new()
	src.source_code = "extends Node3D\nvar calls: Array = []\nfunc burst(at, out, bits, drops, color = Color.WHITE, speed = 1.0, cone = 0.7, size = 1.0) -> void:\n\tcalls.append([bits, drops, color])\n"
	src.reload()
	var stub := Node3D.new()
	stub.set_script(src)
	root.add_child(stub)
	return stub

func tear_once(tissue: int) -> Dictionary:
	var feel = FPTearFeel.new()
	root.add_child(feel)
	var gore := make_gore_stub()
	feel.gore = gore
	feel.on_tear(Vector3(0, 1, -2), Vector3(0, 1, 0), tissue)
	var snaps: Array = []
	var radii: Array = []
	for st in feel._strands:
		snaps.append(float(st.snap))
		radii.append(float(st.radius))
	feel.tick(0.05)
	var out := {"strands": feel.live_strands(), "snaps": snaps, "radii": radii, "calls": gore.get("calls"), "jolt": feel.jolt_offset().length(), "wounds": feel.wound_count()}
	feel.queue_free()
	gore.queue_free()
	return out

func test_tissue_look() -> void:
	var R := FDKTissueRules
	var plain := R.look(R.COMPRESSIVE)
	# plain flesh keeps the look it had before the table
	check(float(plain.pull_gain) == 1.0 and plain.wound_color == Vector3(0.46, 0.02, 0.04) and float(plain.wound_strength) == 0.85, "plain flesh: pull and wound as before")
	check(plain.blood == Color(0.86, 0.07, 0.1) and int(plain.drops) == 18 and int(plain.strands) == 5 and float(plain.snap_from) == 0.07 and float(plain.snap_to) == 0.23 and float(plain.recoil) == 1.0, "plain flesh: blood, drops, strands, snap and recoil as before")
	check(R.look(R.MELTED) == plain and R.look(99) == plain, "an unlisted tissue looks like plain flesh")
	var base := tear_once(R.COMPRESSIVE)
	check(int(base.strands) == 5 and (base.calls as Array).size() == 2 and base.calls[0] == [6, 18, Color(0.86, 0.07, 0.1)] and base.calls[1] == [2, 10, Color(0.86, 0.07, 0.1)], "a plain tear throws what it threw before (%s)" % str(base.calls))
	var default_feel = FPTearFeel.new()
	root.add_child(default_feel)
	default_feel.on_tear(Vector3(0, 1, -2), Vector3(0, 1, 0))
	check(default_feel.live_strands() == 5, "on_tear without a tissue is a plain tear")
	default_feel.queue_free()
	var in_range := true
	for sn in base.snaps:
		in_range = in_range and float(sn) >= 0.07 and float(sn) <= 0.23
	check(in_range, "plain strands break within 0.07..0.23 s")
	# the others differ from it, each its own way
	var fat := tear_once(R.FAT)
	var gristle := tear_once(R.CARTILAGE)
	var muscle := tear_once(R.CONTRACTILE)
	var nerve := tear_once(R.NERVE)
	var cloth := tear_once(R.CLOTH)
	var hair := tear_once(R.HAIR)
	check(int(fat.strands) == 8 and int(gristle.strands) == 0 and int(muscle.strands) == 3 and int(nerve.strands) == 7 and int(cloth.strands) == 0 and int(hair.strands) == 6, "strand counts follow the tissue")
	check(fat.calls[0][2] == Color(0.80, 0.66, 0.25) and int(fat.calls[0][1]) == 10, "fat weeps yellow, less of it")
	check(int(cloth.calls[0][1]) == 0 and int(cloth.calls[1][1]) == 0 and int(hair.calls[0][1]) == 0, "cloth and hair tear dry")
	check(int(gristle.calls[0][1]) == 4 and int(muscle.calls[0][1]) == 22, "gristle hardly bleeds, muscle bleeds most")
	check(absf(float(gristle.jolt) / float(base.jolt) - 1.4) < 0.001 and absf(float(fat.jolt) / float(base.jolt) - 0.7) < 0.001 and absf(float(muscle.jolt) / float(base.jolt) - 1.25) < 0.001, "the recoil scales with the tissue (gristle %.2f, fat %.2f)" % [float(gristle.jolt) / float(base.jolt), float(fat.jolt) / float(base.jolt)])
	var nerve_fast := true
	for sn in nerve.snaps:
		nerve_fast = nerve_fast and float(sn) >= 0.03 and float(sn) <= 0.08
	var fat_slow := true
	for sn in fat.snaps:
		fat_slow = fat_slow and float(sn) >= 0.15 and float(sn) <= 0.30
	check(nerve_fast and fat_slow, "nerve cords snap at once, fat strands hang on")
	var hair_thin := true
	for rr in hair.radii:
		hair_thin = hair_thin and float(rr) < 0.006
	check(hair_thin, "hair strands are thin")
	check(int(cloth.wounds) == 1, "the wound slot is still booked; the tissue's material decides what shows")
	# pull: one gain on every material, plain flesh's shape untouched
	var field := make_field(solid, func(_p: Vector3) -> int: return 0)
	field.set_press(Vector3(1, 1, 1), Vector3.BACK, 0.9, float(R.look(R.FAT).pull_gain))
	var same := true
	for t in range(FDKChunk.TISSUE_TEXTURES.size()):
		same = same and float(FDKChunk.terrain_material(t).get_shader_parameter("press_gain")) == 1.35
	check(same, "the held tissue's pull gain is the same on every material (no split at a tissue border)")
	field.set_press(Vector3(1, 1, 1), Vector3.BACK, 0.9)
	check(float(FDKChunk.terrain_material(R.FAT).get_shader_parameter("press_gain")) == 1.0, "a press without a tissue is plain flesh's")
	field.set_press(Vector3.ZERO, Vector3.BACK, 0.0)
	field.queue_free()
	var toward := Vector3(0, 0, 1)
	var peak_plain := FDKPullShape.offset(Vector3.ZERO, toward, 0.95, 1.0, 0.0).dot(toward)
	var peak_default := FDKPullShape.offset(Vector3.ZERO, toward, 0.95, 1.0, 0.0, 1.0).dot(toward)
	var want_plain := FDKPullShape.LIFT * FDKPullShape.pull_amount(0.95) - FDKPullShape.DENT * FDKPullShape.dent_amount(0.95)
	check(peak_plain == peak_default and absf(peak_plain - want_plain) < 0.000001, "plain flesh's pull is the shape it was (%.4f m)" % peak_plain)
	var peak_fat := FDKPullShape.offset(Vector3.ZERO, toward, 0.95, 1.0, 0.0, float(R.look(R.FAT).pull_gain)).dot(toward)
	var peak_gristle := FDKPullShape.offset(Vector3.ZERO, toward, 0.95, 1.0, 0.0, float(R.look(R.CARTILAGE).pull_gain)).dot(toward)
	check(peak_fat > peak_plain * 1.25 and peak_gristle < peak_plain * 0.35 and peak_gristle > 0.0, "fat stretches long, gristle hardly gives (%.3f, %.3f, %.3f m)" % [peak_fat, peak_plain, peak_gristle])
	var dent_fat := FDKPullShape.offset(Vector3.ZERO, toward, 0.3, 1.0, 0.0, 1.35)
	var dent_plain := FDKPullShape.offset(Vector3.ZERO, toward, 0.3, 1.0, 0.0)
	check(dent_fat == dent_plain, "the first dent is the same for every tissue")
	var side := FDKPullShape.offset(Vector3(0.3, 0.2, 0.0), toward, 0.95, 1.0, 0.0, 1.35)
	check((side - toward * side.dot(toward)).length() < 0.00001, "a stronger pull still moves nothing sideways")
	# wound colour per material; the shader uses it
	check(FDKChunk.terrain_material(R.COMPRESSIVE).get_shader_parameter("wound_color") == Vector3(0.46, 0.02, 0.04) and float(FDKChunk.terrain_material(R.COMPRESSIVE).get_shader_parameter("wound_strength")) == 0.85, "plain flesh's wound rim is the old blood red")
	check(FDKChunk.terrain_material(R.FAT).get_shader_parameter("wound_color") == R.look(R.FAT).wound_color and float(FDKChunk.terrain_material(R.CLOTH).get_shader_parameter("wound_strength")) == 0.0, "fat's rim is yellow, cloth shows none")
	var code := FileAccess.get_file_as_string(SHADER)
	check(code.contains("uniform vec3 wound_color = vec3(0.46, 0.02, 0.04);") and code.contains("uniform float wound_strength = 0.85;") and code.contains("uniform float press_gain = 1.0;"), "the shader's defaults are plain flesh")
	check(code.contains("col = mix(col, wound_color, wound * wound_strength);") and code.contains("0.30 * press_gain * pull"), "the shader draws the tissue's wound and pull")
