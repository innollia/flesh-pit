extends SceneTree

## Biome layer tests (fp_biomes.gd, main/data/biomes.json, decision 0010):
## every biome exists in its shell and has its structures; hollows never
## touch the restroom, the door corridor, tumors, the membrane bands or the
## sphere's outside; the biome tissue replaces only the shell's own tissue;
## structure pockets are real empty space in the live terrain and the vent
## line slots exist. Main runs on an isolated save path.
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
	# over many games, alternate spots keep almost every structure in
	var b: FPBiomes = m.biomes
	var left_out := 0
	for seed in range(1, 41):
		b.apply_rest_points(FPWorldFeatures.rest_points(m.RESTROOM_CENTER, seed))
		for s in b.structures:
			if not s["enabled"]:
				left_out += 1
	_assert(left_out <= 40, "alternate spots: %d of %d structures left out over 40 games" % [left_out, 40 * b.structures.size()])
	b.apply_rest_points(m.rest_points)
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
