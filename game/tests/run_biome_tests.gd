extends SceneTree

## Biome layer tests (fp_biomes.gd, main/data/biomes.json, decision 0010):
## every biome exists in its shell and has its structures; hollows never
## touch the restroom, the door corridor, tumors, the membrane bands or the
## sphere's outside; the biome tissue replaces only the shell's own tissue;
## structure pockets are real empty space in the live terrain and the vent
## line slots exist. Structures past the core lie in a membrane skin
## (decision 0018): the skin is membrane and solid all round, the core has
## none, and on the live terrain it only opens where it is torn with a blade.
## Main runs on an isolated save path.
## Run: godot_console --headless --path game --script res://tests/run_biome_tests.gd

var _failures := 0
var _passed := 0
var _m: Node3D
var _frame := 0
const SAVE := "user://test-biomes.bin"
## Structure models are a few hundred triangles with every detail painted
## (tools/struct_models); the glow box and the lamp come on top.
const MAX_TRIS := 400

func _assert(c: bool, msg: String) -> void:
	if c:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: %s" % msg)

func _init() -> void:
	print("=== flesh-pit biome tests ===")
	_static_tests()
	_wrap_static_tests()
	_m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	_m.user_keybinds_path = "user://keybinds_test_biome.json"
	_m.save_path = SAVE
	get_root().add_child(_m)

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 2:
		_m.finish_opening()
	if _frame < 6:
		return false
	_main_tests()
	_wrap_terrain_tests()
	_m.queue_free()
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("--- %d passed, %d failed ---" % [_passed, _failures])
	quit(1 if _failures > 0 else 0)
	return true

func _static_tests() -> void:
	var center := Vector3(0, 1, 0)
	var b := FPBiomes.new(center)
	_assert(b.biome_ids.size() == 5, "five biomes in biomes.json (got %d)" % b.biome_ids.size())
	# the direction table is filled only where something asked
	var filled := 0
	for row in b._table:
		for c in row:
			filled += 1 if c != FPBiomes.UNSET else 0
	_assert(filled < FPBiomes.TABLE_U * FPBiomes.TABLE_V, "direction table filled lazily (%d cells after setup)" % filled)
	# same layout every time (saves rely on it)
	var b2 := FPBiomes.new(center)
	_assert(b2.structures.size() == b.structures.size(), "structure layout is deterministic")
	for i in range(mini(b.structures.size(), b2.structures.size())):
		_assert((b.structures[i]["pos"] as Vector3).is_equal_approx(b2.structures[i]["pos"]), "structure %d same place" % i)
	# each biome is found on its own shell and owns every structure it lists
	var dirs := FPWorldFeatures.fibonacci_dirs(2000)
	for id in b.biome_ids:
		var bd := b.biome(id)
		var s := int(bd["shell"])
		var depth := float(FPWorldFeatures.REST_DEPTH[s])
		var hits := 0
		for d in dirs:
			if b.biome_at(center + d * depth) == id:
				hits += 1
		_assert(hits > 100, "%s covers part of shell %d (%d/2000 dirs)" % [id, s, hits])
		_assert(hits < 1000, "%s leaves the shell's base biome most of the room (%d/2000)" % [id, hits])
		var want := 0
		for sd in bd["structures"]:
			want += int(sd["count"])
		var got := 0
		for st in b.structures:
			if st["biome"] == id:
				got += 1
				_assert(b.biome_at((st["pos"] as Vector3) + Vector3(0, (st["half"] as Vector3).y, 0)) == id, "%s structure %s sits in its biome" % [id, st["kind"]])
		_assert(got == want, "%s has all %d structures placed (got %d)" % [id, want, got])
	_assert(b.biome_at(center + Vector3(0, 0, 6.0)) == "core", "door side of the core stays base")
	# structure pockets stay inside their shell's carve window and apart
	for i in range(b.structures.size()):
		var st: Dictionary = b.structures[i]
		var box := FPBiomes.pocket_aabb(st["pos"], st["half"])
		var w := FPBiomes.carve_window(int(b.biome(st["biome"])["shell"]))
		if int(b.biome(st["biome"])["shell"]) == 0:
			w.x = FPBiomes.CORE_STRUCT_MIN
		for k in range(8):
			var dd := box.get_endpoint(k).distance_to(center)
			_assert(dd >= w.x - 0.001 and dd <= w.y + 0.001, "structure %d corner in carve window (%.2f not in %.2f..%.2f)" % [i, dd, w.x, w.y])
		for j in range(i + 1, b.structures.size()):
			_assert(not box.intersects(FPBiomes.pocket_aabb(b.structures[j]["pos"], b.structures[j]["half"])), "structures %d and %d do not overlap" % [i, j])
		_assert(ResourceLoader.exists("res://main/art/fp_struct_%s.gd" % st["kind"]), "art exists for %s" % st["kind"])
		_assert(ResourceLoader.exists("res://main/art/structures/%s.glb" % st["kind"]), "model exists for %s" % st["kind"])
		_assert(ResourceLoader.exists("res://main/art/structures/%s.png" % st["kind"]), "painted atlas exists for %s" % st["kind"])
	# hollows: sample points; any hollow point must be inside a window, away
	# from tumors, the door column and the restroom
	var tumors: Array[Vector3] = []
	for spot in FPWorldFeatures.tumor_spots(center):
		tumors.append(spot["pos"])
	var hollow := 0
	var bad := 0
	var r := RandomNumberGenerator.new()
	r.seed = 99
	for i in range(40000):
		var p := center + Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)).normalized() * r.randf_range(0.0, 27.5)
		var d := b.shape_density(p, 1.0)
		if d >= 0.5 or b.in_pocket(p):
			continue
		hollow += 1
		var depth := p.distance_to(center)
		var s := FPWorldFeatures.shell_of_depth(depth)
		var w := FPBiomes.carve_window(s)
		var ok := depth >= w.x and depth <= w.y
		ok = ok and not FPWorldFeatures.in_door_column(p, FPRestroom.DOOR_HALF_W, FPRestroom.DOOR_H)
		for t in tumors:
			ok = ok and p.distance_to(t) >= FPBiomes.TUMOR_CLEAR
		# the membrane band and the outside stay solid
		var into := fposmod(depth, FPWorldFeatures.SHELL_THICKNESS)
		if s < FPWorldFeatures.SHELL_COUNT - 1 and into > FPWorldFeatures.SHELL_THICKNESS - FPWorldFeatures.BOUNDARY_BAND:
			ok = false
		ok = ok and depth < FPWorldFeatures.OUTER_RADIUS - 1.0 and depth > 4.0
		if not ok:
			bad += 1
	_assert(hollow > 200, "biomes make real hollows (%d of 40000 samples)" % hollow)
	_assert(bad == 0, "no hollow outside the allowed windows (%d bad)" % bad)
	# tissue: biome replaces the shell's own tissue, membrane and nerve bundles stay
	var fat_p := Vector3.INF
	for d in dirs:
		var p := center + d * 6.0
		if b.biome_at(p) == "fat_caves":
			fat_p = p
			break
	_assert(fat_p != Vector3.INF, "found a fat cave point")
	if fat_p != Vector3.INF:
		_assert(b.tissue_at(fat_p, FDKTissueRules.COMPRESSIVE, 0.0) == FDKTissueRules.FAT, "core flesh becomes fat in fat caves")
		_assert(b.tissue_at(fat_p, FDKTissueRules.MEMBRANE, 0.0) == FDKTissueRules.MEMBRANE, "membrane stays membrane")
		_assert(b.tissue_at(fat_p, FDKTissueRules.NERVE, 0.9) == FDKTissueRules.NERVE, "nerve bundles stay")
	# the knife gate: gristle needs a blade like muscle, the rest can be torn by hand
	_assert(not FDKTissueRules.can_grab(FDKTissueRules.CARTILAGE, ""), "cartilage refuses bare hands")
	_assert(FDKTissueRules.can_grab(FDKTissueRules.CARTILAGE, "knife"), "cartilage takes a knife")
	for t in [FDKTissueRules.FAT, FDKTissueRules.CLOTH, FDKTissueRules.HAIR]:
		_assert(FDKTissueRules.can_grab(t, ""), "tissue %d torn by hand" % t)
	_assert(FDKChunk.TISSUE_TEXTURES.size() > FDKTissueRules.HAIR, "every biome tissue has a texture")
	# vent line slots for every biome and structure kind
	var lines = JSON.parse_string(FileAccess.get_file_as_string("res://main/data/vent_biome_lines.json"))
	var ids := {}
	for l in lines["lines"]:
		ids[String(l["id"])] = true
	for id in b.biome_ids:
		for n in range(1, 4):
			_assert(ids.has("biome.%s.%d" % [id, n]), "line slot biome.%s.%d" % [id, n])
	for k in FPBiomes.POCKETS.keys():
		for n in range(1, 3):
			_assert(ids.has("struct.%s.%d" % [k, n]), "line slot struct.%s.%d" % [k, n])

func _main_tests() -> void:
	var m = _m
	_assert(m.biomes != null and m.biome_life != null, "main has the biome layer")
	_assert(m.structure_nodes.size() == m.biomes.structures.size(), "one anchor per structure")
	# art only where the player can see it: the restroom looks at no pocket
	m.biome_life._check()
	var built := 0
	var far_built := 0
	for n in m.structure_nodes:
		if n.get_child_count() == 0:
			continue
		built += 1
		var ns: Dictionary = m.biomes.structures[int(n.get_meta("structure"))]
		if FPBiomes._point_box_dist(m.player.global_position, FPBiomes.pocket_aabb(ns["pos"], ns["half"])) > FPBiomes.ART_FAR:
			far_built += 1
	_assert(far_built == 0, "no art past the fog from the restroom (%d)" % far_built)
	_assert(built == 0, "no structure art built from the restroom, all pockets are behind flesh (%d)" % built)
	# a pocket in sight is built, one behind flesh is not
	var probe: Dictionary = m.biomes.structures[0]
	var pbox := FPBiomes.pocket_aabb(probe["pos"], probe["half"])
	var inside_p := pbox.get_center()
	m.terrain.carve_sphere(inside_p, 0.01)
	_assert(m.biomes._in_sight(m.terrain, inside_p + Vector3(0, 0, 0.2), pbox), "the inside of a pocket sees the pocket")
	_assert(not m.biomes._in_sight(m.terrain, m.RESTROOM_CENTER, pbox), "the restroom does not see %s" % probe["kind"])
	var shown := 0
	for n in m.structure_nodes:
		var s: Dictionary = m.biomes.structures[int(n.get_meta("structure"))]
		_assert(n.visible == bool(s["enabled"]), "structure visibility follows its rest-point check")
		if not n.visible:
			continue
		shown += 1
		# the pocket is real empty space in the live terrain
		var mid: Vector3 = (s["pos"] as Vector3) + Vector3(0, (s["half"] as Vector3).y, 0)
		m.terrain.carve_sphere(mid, 0.01) # streams the chunk in
		_assert(m.terrain.density_at(mid) < 0.5, "pocket of %s is empty in the terrain" % s["kind"])
		m.biomes.stream_art(m.structure_nodes, mid)
		_assert(n.get_child_count() > 0, "%s art built when the player is there" % s["kind"])
		var tris := _tris(n)
		_assert(tris > 0 and tris <= MAX_TRIS, "%s is low-poly (%d triangles)" % [s["kind"], tris])
		var others := 0
		for o in m.structure_nodes:
			if o != n and o.get_child_count() > 0 and (o.position - n.position).length() > 30.0:
				others += 1
		_assert(others == 0, "far structures have no art while at %s" % s["kind"])
	# far out on the surface shell, everything near the core is freed
	var away: Vector3 = m.RESTROOM_CENTER + Vector3(0, -1, 0) * 26.0
	m.biomes.stream_art(m.structure_nodes, away)
	var left := 0
	for n in m.structure_nodes:
		var ns: Dictionary = m.biomes.structures[int(n.get_meta("structure"))]
		if n.get_child_count() > 0 and FPBiomes._point_box_dist(away, FPBiomes.pocket_aabb(ns["pos"], ns["half"])) > FPBiomes.ART_FAR:
			left += 1
	_assert(left == 0, "moving away frees the art (%d left)" % left)
	_assert(shown >= m.structure_nodes.size() - 2, "most structures shown (%d of %d)" % [shown, m.structure_nodes.size()])
	# the fixed rest layout (decision 0016) leaves every structure in
	var b: FPBiomes = m.biomes
	var left_out := 0
	b.apply_rest_points(FPWorldFeatures.rest_points(m.RESTROOM_CENTER), FPWorldFeatures.rest_halves())
	for s in b.structures:
		if not s["enabled"]:
			left_out += 1
	_assert(b.structures.size() == 16 and left_out == 0, "the seven fixed rests leave all 16 structures in (%d of %d left out)" % [left_out, b.structures.size()])
	b.apply_rest_points(m.rest_points, m.rest_halves)
	# the generator gives biome tissue in a biome
	var found := false
	for d in FPWorldFeatures.fibonacci_dirs(400):
		var p: Vector3 = m.RESTROOM_CENTER + d * 20.0
		if m.biomes.biome_at(p) == "cloth_wads" and m._world_density(p) >= 1.0:
			var t: int = m._world_tissue(p)
			if t == FDKTissueRules.CLOTH:
				found = true
				break
	_assert(found, "generator puts cloth wad tissue in the clothing wads")
	# visiting is tracked, saved and handed to the vent
	var st: Dictionary = {}
	for s in m.biomes.structures:
		if s["enabled"]:
			st = s
			break
	m.player.global_position = (st["pos"] as Vector3) + Vector3(0, 0.2, 0)
	m.biome_life._check()
	_assert(m.biome_life.visited_biomes.has(st["biome"]), "entering a biome is remembered")
	_assert(m.biome_life.visited_structures.has(st["kind"]), "entering a structure is remembered")
	_assert(String(m.vent.player_state.get("new_struct", "")) == st["kind"], "the vent hears about the structure")
	var data: Dictionary = m.serialize()
	_assert((data["biome_visits"]["structures"] as Array).has(st["kind"]), "visits saved")
	_assert(m.biome_life.current_bed() == String(m.biomes.biome(st["biome"])["bed"]), "biome bed chosen in a biome")

func _tris(n: Node) -> int:
	var t := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		for i in range(mesh.get_surface_count()):
			var a := mesh.surface_get_arrays(i)
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			t += (idx.size() if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	for c in n.get_children():
		t += _tris(c)
	return t

# --- the membrane skin round structures (decision 0018) ---------------------------

func _wrap_static_tests() -> void:
	var R := FDKTissueRules
	var center := Vector3(0, 1, 0)
	var b := FPBiomes.new(center)
	var rests := FPWorldFeatures.rest_points(center)
	var halves := FPWorldFeatures.rest_halves()
	b.apply_rest_points(rests, halves)
	_assert(is_equal_approx(FPBiomes.WRAP_BAND, FPWorldFeatures.BOUNDARY_BAND), "the skin is as thick as every other membrane (%.2f m)" % FPBiomes.WRAP_BAND)
	# which structures: every one past the core, none in it (counted from the data)
	var want := 0
	for id in b.biome_ids:
		if int(b.biome(id)["shell"]) >= FPBiomes.WRAP_FROM_SHELL:
			for sd in b.biome(id)["structures"]:
				want += int(sd["count"])
	var wrapped := 0
	var flags_ok := true
	var on := 0
	for st in b.structures:
		var shell := int(b.biome(st["biome"])["shell"])
		flags_ok = flags_ok and bool(st["wrap"]) == (shell >= FPBiomes.WRAP_FROM_SHELL)
		on += 1 if st["enabled"] else 0
		if st["enabled"] and st["wrap"]:
			wrapped += 1
	_assert(flags_ok, "structures past the core are wrapped, core structures are not")
	_assert(want > 0 and wrapped == want and b._wrap_outer.size() == want, "all %d structures past the core are wrapped (%d, %d boxes)" % [want, wrapped, b._wrap_outer.size()])
	_assert(on == b.structures.size(), "wrapping leaves every structure in beside the fixed rests (%d of %d)" % [on, b.structures.size()])
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	for i in range(b.structures.size()):
		var st: Dictionary = b.structures[i]
		if not st["enabled"]:
			continue
		var shell := int(b.biome(st["biome"])["shell"])
		var box := FPBiomes.pocket_aabb(st["pos"], st["half"])
		if not st["wrap"]:
			# a core structure: bare-hand flesh right up to it (decision 0008)
			var skin := 0
			var around := box.grow(1.0)
			for n in range(2000):
				var p := around.position + Vector3(r.randf(), r.randf(), r.randf()) * around.size
				if b.in_wrap(p) or b.tissue_at(p, R.COMPRESSIVE, 0.0) == R.MEMBRANE or not R.can_grab(b.tissue_at(p, R.COMPRESSIVE, 0.0), ""):
					skin += 1
			_assert(skin == 0, "core structure %s has no skin, its flesh tears by hand (%d of 2000)" % [st["kind"], skin])
			continue
		var outer := box.grow(FPBiomes.WRAP_BAND)
		var inner := box.grow(-FPBiomes.WRAP_INNER)
		var solid := box.grow(FPBiomes.WRAP_SOLID)
		var base: int = R.SHELL_TISSUE[shell]
		var area := solid.grow(0.3)
		var band := 0
		var not_membrane := 0
		var stray := 0
		var hollow := 0
		var packed := 0
		var past_outside := 0
		for n in range(2000):
			var p := area.position + Vector3(r.randf(), r.randf(), r.randf()) * area.size
			var depth := p.distance_to(center)
			if outer.has_point(p) and not inner.has_point(p):
				if depth <= FPWorldFeatures.OUTER_RADIUS - FPBiomes.WRAP_OUTSIDE_CLEAR:
					band += 1
					# even where a nerve bundle would be (noise 0.9)
					if b.tissue_at(p, base, 0.9) != R.MEMBRANE or not b.in_wrap(p):
						not_membrane += 1
				elif b.in_wrap(p):
					past_outside += 1
			else:
				var near_other := false
				for o in b._wrap_outer:
					if o.grow(0.05).has_point(p):
						near_other = true
				if not near_other and b.in_wrap(p):
					stray += 1
			if solid.has_point(p) and not b.in_pocket(p):
				packed += 1
				if b.shape_density(p, 1.0) < 0.5:
					hollow += 1
		_assert(band > 300 and not_membrane == 0, "%s %d: its skin is membrane all round (%d of %d not)" % [st["kind"], i, not_membrane, band])
		_assert(stray == 0, "%s %d: no skin outside the grown box (%d)" % [st["kind"], i, stray])
		_assert(past_outside == 0, "%s %d: no skin within %.1f m of the sphere's outside (%d)" % [st["kind"], i, FPBiomes.WRAP_OUTSIDE_CLEAR, past_outside])
		_assert(packed > 300 and hollow == 0, "%s %d: the skin is packed flesh, no hollow against it (%d of %d hollow)" % [st["kind"], i, hollow, packed])
		_assert(b.shape_density(box.get_center(), 1.0) < 0.5, "%s %d: the pocket inside is still empty" % [st["kind"], i])
		for k in range(rests.size()):
			var gap := FPBiomes._box_gap(box, AABB(rests[k] - halves[k], halves[k] * 2.0))
			_assert(gap >= FPBiomes.WRAP_REST_GAP - 0.001, "%s %d keeps %.1f m from rest %d (%.2f)" % [st["kind"], i, FPBiomes.WRAP_REST_GAP, k, gap])
		# a skin that reaches the shell's own membrane is torn in one go with it
		var nearest := FPBiomes._point_box_dist(center, outer)
		var joins := nearest < shell * FPWorldFeatures.SHELL_THICKNESS
		print("INFO wrap %d %s shell %d: skin from %.2f m%s" % [i, st["kind"], shell, nearest, " (joins the shell membrane that ends at %.1f m)" % (shell * FPWorldFeatures.SHELL_THICKNESS) if joins else ""])
	# the core, and the way from the door to its membrane, have no skin at all
	var core_skin := 0
	var core_end := FPWorldFeatures.SHELL_THICKNESS - FPWorldFeatures.BOUNDARY_BAND
	for n in range(20000):
		var p := center + Vector3(r.randf_range(-1, 1), r.randf_range(-1, 1), r.randf_range(-1, 1)).normalized() * r.randf_range(0.0, core_end)
		if b.in_wrap(p):
			core_skin += 1
	_assert(core_skin == 0, "no structure skin anywhere in the core before its membrane (%d of 20000)" % core_skin)
	var door_skin := 0
	var z := FPRestroom.HALF.z
	while z < core_end:
		for y in [0.3, 1.0, 1.7]:
			if b.in_wrap(Vector3(0.0, y, z)):
				door_skin += 1
		z += 0.1
	_assert(door_skin == 0, "the way out of the door stays bare to the core's membrane (%d)" % door_skin)

## Real density at a point: the eight corners round it, blended.
func _dens(f: FDKTerrainField, p: Vector3) -> float:
	var q := p / f.config.cell_size
	var g := Vector3i(q.floor())
	var t := q - Vector3(g)
	var d := 0.0
	for dz in range(2):
		for dy in range(2):
			for dx in range(2):
				var w := (t.x if dx == 1 else 1.0 - t.x) * (t.y if dy == 1 else 1.0 - t.y) * (t.z if dz == 1 else 1.0 - t.z)
				d += w * f.corner_density_global(g + Vector3i(dx, dy, dz))
	return d

## Density on the grid plane x = gx cells, on the line through the middle of
## the cell row at (y, z): the four corners round the line, averaged. Between
## two planes the line's density runs straight from one value to the other.
func _plane(f: FDKTerrainField, gx: int, y: float, z: float) -> float:
	var cs: float = f.config.cell_size
	var gy := int(floor(y / cs))
	var gz := int(floor(z / cs))
	var d := 0.0
	for dz in range(2):
		for dy in range(2):
			d += f.corner_density_global(Vector3i(gx, gy + dy, gz + dz)) * 0.25
	return d

func _cell_mid(f: FDKTerrainField, p: Vector3) -> Vector3:
	var cs: float = f.config.cell_size
	return ((p / cs).floor() + Vector3.ONE * 0.5) * cs

## Tears away every cell round `on` that is not skin, the way a digger eating
## the flesh beside a pocket would. Returns how many.
func _eat_round(f: FDKTerrainField, on: Vector3, box: AABB, reach: float) -> int:
	var cs: float = f.config.cell_size
	f.generate_region(AABB(on - Vector3.ONE * (reach + 1.0), Vector3.ONE * (reach + 1.0) * 2.0))
	var n := 0
	var steps := int(ceil(reach / cs)) + 1
	var mid := _cell_mid(f, on)
	for dz in range(-steps, steps + 1):
		for dy in range(-steps, steps + 1):
			for dx in range(-steps, steps + 1):
				var p := mid + Vector3(dx, dy, dz) * cs
				if p.distance_to(on) > reach or box.has_point(p):
					continue
				if f.tissue_at(p) == FDKTissueRules.MEMBRANE or f.density_at(p) < 0.5:
					continue
				f.dig_at(p, 1.0)
				n += 1
	return n

## The weakest line out of the pocket: for each start, the most solid point
## on the first WRAP_BAND metres along its direction. Under 0.5 the skin is
## open there.
func _weakest(f: FDKTerrainField, starts: Array, dirs: Array) -> Array:
	var worst := INF
	var where := Vector3.ZERO
	for i in range(starts.size()):
		var best := 0.0
		var t := 0.0
		while t <= FPBiomes.WRAP_BAND + 0.001:
			best = maxf(best, _dens(f, (starts[i] as Vector3) + (dirs[i] as Vector3) * t))
			t += 0.05
		if best < worst:
			worst = best
			where = starts[i]
	return [worst, where]

func _wrap_terrain_tests() -> void:
	var m = _m
	var R := FDKTissueRules
	var f: FDKTerrainField = m.terrain
	var b: FPBiomes = m.biomes
	var tools = m.tissue_tools
	var prog: FPProgression = m.progression
	m.player.global_position = m.START_POS
	m.stomach.vomit()
	var refused := [0]
	m.grab_refused.connect(func(_t, _p): refused[0] += 1)
	var torn := [0]
	m.chewer.cell_torn.connect(func(_p): torn[0] += 1)
	for shell in range(FPBiomes.WRAP_FROM_SHELL, FPWorldFeatures.SHELL_COUNT):
		var st: Dictionary = {}
		for s in b.structures:
			if s["enabled"] and s["wrap"] and int(b.biome(s["biome"])["shell"]) == shell:
				st = s
				break
		_assert(not st.is_empty(), "a wrapped structure in shell %d" % shell)
		if st.is_empty():
			continue
		var box := FPBiomes.pocket_aabb(st["pos"], st["half"])
		var h: Vector3 = st["half"]
		var mid := box.get_center()
		var tag := "%s (shell %d)" % [st["kind"], shell]
		# a face, an edge and a corner: eat everything beside the skin, then
		# look from the pocket for a way out through it
		var face_on := mid + Vector3(h.x, 0, 0)
		var sites := [["face", face_on, Vector3(1, 0, 0)], ["edge", mid + Vector3(h.x, 0, h.z), Vector3(1, 0, 1).normalized()], ["corner", mid + h, Vector3(1, 1, 1).normalized()]]
		for site in sites:
			var on: Vector3 = site[1]
			var dir: Vector3 = site[2]
			var eaten := _eat_round(f, on, box, 1.5)
			var starts: Array = []
			var dirs: Array = []
			for k in range(25):
				var u := float(k % 5) / 4.0 - 0.5
				var v := float(k / 5) / 4.0 - 0.5
				match String(site[0]):
					"face":
						starts.append(on + Vector3(0, u * minf(1.0, h.y * 1.6), v * minf(1.0, h.z * 1.6)))
						dirs.append(dir)
					"edge":
						starts.append(on + Vector3(0, (float(k) / 24.0 - 0.5) * minf(1.0, h.y * 1.6), 0))
						dirs.append(dir)
					_:
						starts.append(on)
						dirs.append((dir + Vector3(u, v, -u - v) * 0.5).normalized())
			var weak := _weakest(f, starts, dirs)
			_assert(eaten > 0 and float(weak[0]) >= 0.5, "%s %s: with the flesh beside it eaten (%d cells) no line leaves the pocket without crossing skin (weakest %.2f at %s)" % [tag, site[0], eaten, weak[0], str(weak[1])])
		# the knife gate on the bared face
		var first := Vector3.INF
		var t := FPBiomes.WRAP_BAND + 0.3
		while t > -0.5 and first == Vector3.INF:
			var p := face_on + Vector3(t, 0, 0)
			if f.density_at(p) >= 0.5 and f.tissue_at(p) == R.MEMBRANE:
				first = _cell_mid(f, p)
			t -= 0.05
		_assert(first != Vector3.INF, "%s: the bared face is membrane" % tag)
		if first == Vector3.INF:
			continue
		m.equip_tool("")
		refused[0] = 0
		tools.set("_refuse_frame", Engine.get_process_frames() - 10)
		var d0: float = f.density_at(first)
		tools.chew_at(first, first, Vector3(-1, 0, 0), 1.0 / 60.0)
		_assert(not tools.can_grab_at(first) and refused[0] == 1 and f.density_at(first) >= d0 - 0.001, "%s: bare hands slip off the skin (refused %d)" % [tag, refused[0]])
		prog.grant_item("knife")
		_assert(m.equip_tool("knife") and is_equal_approx(tools.chew_time_at(first), R.chew_time(R.MEMBRANE, "knife")) and is_equal_approx(tools.chew_time_at(first), 0.75), "%s: the knife takes a skin cell in %.2f s" % [tag, tools.chew_time_at(first)])
		var tears := 0
		var open := false
		var honest := true
		var skin_only := true
		# the line through that cell row, from the eaten space outside to the
		# middle of the pocket; a wall of any thickness shows on a grid plane
		var cs: float = f.config.cell_size
		var g_out := int(floor((box.end.x + FPBiomes.WRAP_BAND + 0.3) / cs))
		var g_in := int(ceil(mid.x / cs))
		while tears < 4 and not open:
			# the outermost solid plane, and the wall face the digger sees on it
			var solid := g_in - 1
			for gx in range(g_out, g_in - 1, -1):
				if _plane(f, gx, first.y, first.z) >= 0.5:
					solid = gx
					break
			if solid < g_in:
				open = true
				break
			var v0 := _plane(f, solid, first.y, first.z)
			var v1 := _plane(f, solid + 1, first.y, first.z)
			var hit_x := (float(solid) + (v0 - 0.5) / maxf(v0 - v1, 0.0001)) * cs
			# the aim takes the cell half a cell past the hit (Main's dig target)
			var target := _cell_mid(f, Vector3(hit_x - cs * 0.5, first.y, first.z))
			skin_only = skin_only and f.tissue_at(target) == R.MEMBRANE
			var fill0: float = m.stomach.fill
			torn[0] = 0
			var spent := 0.0
			while torn[0] == 0 and spent < 3.0:
				tools.chew_at(target, target, Vector3(-1, 0, 0), 1.0 / 60.0)
				spent += 1.0 / 60.0
			tears += 1
			honest = honest and torn[0] == 1 and m.chewer.last_units > 0.0 and is_equal_approx(m.stomach.fill - fill0, m.chewer.last_units)
		m.chewer.stop()
		_assert(open and tears >= 1 and tears <= 3, "%s: %d knife tears on one line open the pocket" % [tag, tears])
		_assert(skin_only, "%s: every cell on the way in was skin" % tag)
		_assert(honest, "%s: every tear puts what it removed in the stomach" % tag)
		# torn skin does not grow back shut
		var away: Vector3 = m.RESTROOM_CENTER
		for i in range(300):
			f.regenerate_all(2.0, away, 0.0)
		# the planes within 0.4 m of the pocket face stay open; the ones out to
		# the skin's outer edge are only reported (the corners on that edge
		# belong to the flesh outside the skin and grow back with it)
		var inner_max := 0.0
		var outer_max := 0.0
		for gx in range(g_in, g_out + 1):
			var off := float(gx) * cs - box.end.x
			if off < -0.5 or off > FPBiomes.WRAP_BAND + cs:
				continue
			var dn := _plane(f, gx, first.y, first.z)
			if off <= 0.4:
				inner_max = maxf(inner_max, dn)
			else:
				outer_max = maxf(outer_max, dn)
		_assert(inner_max < 0.5, "%s: 600 s later the torn skin is still open at the pocket (%.2f)" % [tag, inner_max])
		print("INFO wrap regrowth %s: %d tears; after 600 s the torn line is %.2f at most within 0.4 m of the pocket face, %.2f from there to the skin's outer edge (%.1f m and the next grid plane)" % [tag, tears, inner_max, outer_max, FPBiomes.WRAP_BAND])
		m.equip_tool("")
		m.stomach.vomit()
