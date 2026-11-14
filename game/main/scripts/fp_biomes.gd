class_name FPBiomes
extends RefCounted

## Several biomes per shell (docs/spec/02-world-tissue.md 1-1, data in
## main/data/biomes.json). Each shell is split into direction slots around
## the restroom; a slot is either the shell's own tissue ("base") or a biome
## with its own tissue, generator-made hollows (carve), half-swallowed human
## structures in carved pockets, and a light/fog/sound mood.
## The layout is fixed (not per game), so the generator gives the same world
## on every load. Only whether a structure is shown depends on the game's
## rest points: a structure whose pocket would overlap a rest container is
## left out for that game.
## Hollows stay out of the membrane band and the blend zone before it, the
## restroom's surroundings, the door corridor and tumors, so the knife gate
## (decision 0008) and the restroom rules are unchanged.

const DATA_PATH := "res://main/data/biomes.json"
const BASE := "base"
## Shell base biome names (FPProgression.BIOMES): what "base" reports.
const SHELL_BASE: Array[String] = ["core", "mantle", "surface"]
## Pocket half extents per structure kind (main/art/fp_struct_<kind>.gd
## POCKET_HALF). Origin = pocket floor centre.
const POCKETS := {
	"boiler_room": Vector3(1.4, 1.2, 1.4),
	"phone_booth": Vector3(0.9, 1.2, 0.9),
	"subway_turnstile": Vector3(1.8, 1.2, 1.0),
	"elevator_car": Vector3(1.0, 1.2, 1.0),
	"school_lockers": Vector3(1.6, 1.1, 0.8),
	"fountain_alcove": Vector3(0.9, 1.1, 0.8),
	"bus_shelter": Vector3(1.6, 1.2, 0.9),
	"laundromat": Vector3(1.5, 1.1, 0.9),
	"street_lamp": Vector3(1.0, 1.6, 1.0),
	"barber_chair": Vector3(1.2, 1.1, 1.0),
}
## Hollows start this far past the restroom centre in the core (room box
## corner + membrane is ~4.0 m) and keep this far from a tumor.
const CORE_CARVE_MIN := 4.8
## Structure pockets may come a little closer (still clear of the room's
## membrane, which ends ~4.0 m out): the core is too thin for them otherwise.
const CORE_STRUCT_MIN := 4.2
const TUMOR_CLEAR := 1.6
## Hollow edges fade in over this many metres at the window ends.
const WINDOW_FADE := 0.8
## Structures keep this gap to tumors, rest containers and each other.
const STRUCT_GAP := 1.0
const STRUCT_TUMOR_GAP := 2.0

var center: Vector3
var data: Dictionary = {}
var biome_ids: Array[String] = []
## Per shell: slot directions and their biome names (the generator calls
## biome_at for every corner, so these are packed arrays, not dictionaries).
var _slot_dirs: Array[PackedVector3Array] = []
var _slot_names: Array[PackedStringArray] = []
var _windows: Array[Vector2] = []
## Per shell: biome name index for every direction cell (u = longitude,
## v = height of the unit direction), each cell filled from the slot search at
## the shell's middle depth the first time biome_at reads it.
const TABLE_U := 192
const TABLE_V := 96
var _table: Array[PackedByteArray] = []
var _table_names := PackedStringArray()
var _table_index := {}
const UNSET := 255
## Enabled pockets as boxes, and the depth band they all lie in (cheap reject).
var _pockets: Array[AABB] = []
var _pocket_depth := Vector2(INF, -INF)
var _noise := FastNoiseLite.new()
var _wobble := 0.12
var _tumors: Array[Vector3] = []
## Tumors per shell (shape_density only checks its own shell's) and each
## biome's carve table, read once.
var _shell_tumors: Array[PackedVector3Array] = []
var _carves: Dictionary = {}
## [{kind, biome, pos (floor centre), half, enabled}]
var structures: Array = []

func _init(p_center: Vector3 = Vector3(0, 1, 0), p_data: Dictionary = {}) -> void:
	center = p_center
	data = p_data if not p_data.is_empty() else load_data()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = int(data.get("noise_seed", 7331))
	_noise.frequency = 1.0
	_wobble = float(data.get("edge_wobble", 0.12))
	for id in (data.get("biomes", {}) as Dictionary).keys():
		biome_ids.append(String(id))
	var shells: Array = data.get("shells", [])
	for s in range(FPWorldFeatures.SHELL_COUNT):
		var sd: Dictionary = shells[s] if s < shells.size() else {"slots": [BASE]}
		var names: Array = sd.get("slots", [BASE])
		var dirs := FPWorldFeatures.fibonacci_dirs(names.size())
		var b := Basis(Vector3(0.3, 1.0, 0.2).normalized(), float(sd.get("turn", 0.0)))
		var row_dirs := PackedVector3Array()
		var row_names := PackedStringArray()
		for i in range(names.size()):
			row_dirs.append((b * dirs[i]).normalized())
			row_names.append(SHELL_BASE[s] if String(names[i]) == BASE else String(names[i]))
		_slot_dirs.append(row_dirs)
		_slot_names.append(row_names)
		_windows.append(carve_window(s))
	for s in range(FPWorldFeatures.SHELL_COUNT):
		_shell_tumors.append(PackedVector3Array())
	for spot in FPWorldFeatures.tumor_spots(center):
		_tumors.append(spot["pos"])
		# a tumor near a shell edge is listed for both shells
		var dd: float = (spot["pos"] as Vector3).distance_to(center)
		for s in range(FPWorldFeatures.SHELL_COUNT):
			if absf(dd - clampf(dd, s * FPWorldFeatures.SHELL_THICKNESS, (s + 1) * FPWorldFeatures.SHELL_THICKNESS)) < TUMOR_CLEAR:
				_shell_tumors[s].append(spot["pos"])
	for id in biome_ids:
		_carves[id] = biome(id).get("carve", {})
	_build_table()
	_place_structures()
	_index_pockets()

static func load_data() -> Dictionary:
	if FileAccess.file_exists(DATA_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if d is Dictionary:
			return d
	return {}

func biome(id: String) -> Dictionary:
	return (data.get("biomes", {}) as Dictionary).get(id, {})

## Biome id at p: a key of biomes.json "biomes", or the shell's base name
## (core / mantle / surface). The core's door corridor side stays base.
func biome_at(p: Vector3) -> String:
	var off := p - center
	var depth := off.length()
	var shell := FPWorldFeatures.shell_of_depth(depth)
	if depth < 0.001:
		return SHELL_BASE[shell]
	var d := off / depth
	if shell == 0 and d.z > 0.6:
		return SHELL_BASE[0]
	var u := int((atan2(d.z, d.x) / TAU + 0.5) * TABLE_U) % TABLE_U
	var v := clampi(int((d.y * 0.5 + 0.5) * TABLE_V), 0, TABLE_V - 1)
	var i := u + v * TABLE_U
	var c: int = _table[shell][i]
	if c == UNSET:
		c = _table_cell(shell, u, v)
		_table[shell][i] = c
	return _table_names[c]

## Cells are worked out the first time something asks for them: the
## generator and the structure placement only ever touch a small part of
## each shell's sphere.
func _build_table() -> void:
	_table.clear()
	_table_names = PackedStringArray()
	_table_index.clear()
	for s in range(FPWorldFeatures.SHELL_COUNT):
		var row := PackedByteArray()
		row.resize(TABLE_U * TABLE_V)
		row.fill(UNSET)
		_table.append(row)

func _table_cell(shell: int, u: int, v: int) -> int:
	var depth := (float(shell) + 0.5) * FPWorldFeatures.SHELL_THICKNESS
	var y := (float(v) + 0.5) / TABLE_V * 2.0 - 1.0
	var r := sqrt(maxf(0.0, 1.0 - y * y))
	var a := ((float(u) + 0.5) / TABLE_U - 0.5) * TAU
	var d := Vector3(cos(a) * r, y, sin(a) * r)
	var name := _slot_search(shell, d, center + d * depth)
	if not _table_index.has(name):
		_table_index[name] = _table_names.size()
		_table_names.append(name)
	return int(_table_index[name])

## The slot nearest to direction d, its edges wobbled by noise at p.
func _slot_search(shell: int, d: Vector3, p: Vector3) -> String:
	var dirs: PackedVector3Array = _slot_dirs[shell]
	var n := _noise.get_noise_3dv(p * 0.22) * _wobble
	var best := -INF
	var bi := 0
	for i in range(dirs.size()):
		var v := d.dot(dirs[i]) + (n if i % 2 == 0 else -n)
		if v > best:
			best = v
			bi = i
	return _slot_names[shell][bi]

func is_base(id: String) -> bool:
	return SHELL_BASE.has(id)

## Depth window [lo, hi] (from the restroom centre) where shell `s` may be
## hollowed: past the restroom in the core, before the blend zone and the
## membrane band, and a metre and more inside the sphere's outside.
static func carve_window(s: int) -> Vector2:
	var t := FPWorldFeatures.SHELL_THICKNESS
	var start := float(s) * t
	var lo := CORE_CARVE_MIN if s == 0 else start + 1.0
	var hi: float
	if s < FPWorldFeatures.SHELL_COUNT - 1:
		hi = start + t - FPWorldFeatures.BOUNDARY_BAND - float(FPWorldFeatures.BLEND_ZONE[s]) - 0.3
	else:
		hi = FPWorldFeatures.OUTER_RADIUS - 1.2
	return Vector2(lo, hi)

## Generator density with this biome's hollows and enabled structure pockets
## taken out. `d` is FPWorldFeatures.world_density at p; only full flesh
## (1.0) is changed, so the restroom wall blend and containers stay as they are.
func shape_density(p: Vector3, d: float) -> float:
	if d < 1.0:
		return d
	var depth := p.distance_to(center)
	if depth >= _pocket_depth.x - 0.5 and depth <= _pocket_depth.y + 0.5:
		# interpolated so the wall lands on the box face, not up to half a
		# cell inside it (a hard 0/1 carve shrank pockets onto the body)
		var sd := INF
		for box in _pockets:
			var q := (p - box.get_center()).abs() - box.size * 0.5
			var outside := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()
			sd = minf(sd, outside + minf(maxf(q.x, maxf(q.y, q.z)), 0.0))
		if sd < 0.5:
			return clampf(0.5 + sd, 0.0, 1.0)
	# cheap rejects before the biome lookup
	var shell := FPWorldFeatures.shell_of_depth(depth)
	var w: Vector2 = _windows[shell]
	if depth < w.x or depth > w.y:
		return d
	var id := biome_at(p)
	var carve: Dictionary = _carves.get(id, {})
	if carve.is_empty():
		return d # base biome, or a biome without hollows
	var kind := String(carve["kind"])
	if FPWorldFeatures.in_door_column(p, FPRestroom.DOOR_HALF_W, FPRestroom.DOOR_H):
		return d
	for t in _shell_tumors[shell]:
		if p.distance_squared_to(t) < TUMOR_CLEAR * TUMOR_CLEAR:
			return d
	# 0 inside the window, rising to 1 over WINDOW_FADE at both ends
	var edge := clampf(minf(depth - w.x, w.y - depth) / WINDOW_FADE, 0.0, 1.0)
	var open := _openness(p, kind, carve)
	# open > 0 means hollow; the fade shrinks it to nothing at the window edge
	open -= (1.0 - edge) * 0.6
	return clampf(0.5 - open * 2.5, 0.0, 1.0)

## > 0 where the biome's hollow shape is open at p (its margin in noise units).
func _openness(p: Vector3, kind: String, carve: Dictionary) -> float:
	var f := float(carve.get("freq", 0.2))
	var thr := float(carve.get("threshold", 0.4))
	match kind:
		"blobs":
			# bubble caves where the noise is high
			return _noise.get_noise_3dv(p * f) - thr
		"tunnels":
			# worm burrows where two noise sheets cross
			var a := absf(_noise.get_noise_3dv(p * f))
			var b := absf(_noise.get_noise_3dv(p * f + Vector3(31.7, 7.3, -12.9)))
			return thr - maxf(a, b)
		"ribs":
			# one big vault, crossed by solid rib plates across the slot direction
			var cave := _noise.get_noise_3dv(p * f) - thr
			var axis := (p - center).normalized().cross(Vector3.UP)
			if axis.length_squared() < 0.01:
				axis = Vector3.RIGHT
			axis = axis.normalized()
			var spacing := float(carve.get("spacing", 2.6))
			var thick := float(carve.get("thick", 0.7))
			var k := absf(fposmod(p.dot(axis), spacing) - spacing * 0.5)
			if k > spacing * 0.5 - thick * 0.5:
				return minf(cave, -0.05)
			return cave
		"folds":
			# layered slits around the restroom that the muscle squeezes shut
			var depth := p.distance_to(center)
			var spacing := float(carve.get("spacing", 2.8))
			var gap := float(carve.get("gap", 0.22))
			var n := _noise.get_noise_3dv(p * f)
			if n < thr:
				return -1.0
			var s := absf(sin((depth / spacing + n * 0.35) * PI))
			return gap - s
	return -1.0

## Tissue at p for a biome: `t` is FPWorldFeatures.world_tissue at p and
## `noise` the same -1..1 world noise it used. Membranes, the next shell's
## blend tissue and nerve bundles stay; the shell's own tissue becomes the
## biome's.
func tissue_at(p: Vector3, t: int, noise: float) -> int:
	if t == FDKTissueRules.MEMBRANE:
		return t
	if t == FDKTissueRules.NERVE and noise > 0.42:
		return t # a few nerve bundles everywhere
	var shell := FPWorldFeatures.shell_of_depth(p.distance_to(center))
	if t != int(FDKTissueRules.SHELL_TISSUE[shell]):
		return t # blend zone: the next shell's tissue
	var id := biome_at(p)
	if is_base(id):
		return t
	return int(biome(id).get("tissue", t))

# --- structures -----------------------------------------------------------

func in_pocket(p: Vector3) -> bool:
	for s in structures:
		if not s["enabled"]:
			continue
		var h: Vector3 = s["half"]
		var q: Vector3 = p - (s["pos"] as Vector3) - Vector3(0, h.y, 0)
		if absf(q.x) <= h.x and absf(q.y) <= h.y and absf(q.z) <= h.z:
			return true
	return false

## The structure the point is inside (index), or -1.
func structure_at(p: Vector3) -> int:
	for i in range(structures.size()):
		var s: Dictionary = structures[i]
		if not s["enabled"]:
			continue
		var h: Vector3 = s["half"]
		var q: Vector3 = p - (s["pos"] as Vector3) - Vector3(0, h.y, 0)
		if absf(q.x) <= h.x and absf(q.y) <= h.y and absf(q.z) <= h.z:
			return i
	return -1

static func pocket_aabb(pos: Vector3, half: Vector3) -> AABB:
	return AABB(pos - Vector3(half.x, 0, half.z), half * 2.0)

## Deterministic placement: for each biome structure, the candidate direction
## inside the biome whose pocket fits the carve window and is farthest from
## what is already placed. Every structure then gets up to ALT_SPOTS - 1
## alternate spots the same way; the game uses the first spot that clears the
## rest containers (apply_rest_points), so few are left out.
const ALT_SPOTS := 5
## Candidate directions a structure spot is searched over.
const STRUCT_DIRS := 900

func _place_structures() -> void:
	structures.clear()
	var dirs := FPWorldFeatures.fibonacci_dirs(STRUCT_DIRS)
	var placed_boxes: Array[AABB] = []
	for id in biome_ids:
		var b := biome(id)
		for sd in b.get("structures", []):
			var kind := String(sd.get("kind", ""))
			if not POCKETS.has(kind):
				continue
			for n in range(int(sd.get("count", 1))):
				var pos := _best_spot(id, POCKETS[kind], dirs, placed_boxes)
				if pos == Vector3.INF:
					continue
				placed_boxes.append(pocket_aabb(pos, POCKETS[kind]))
				structures.append({"kind": kind, "biome": id, "pos": pos, "half": POCKETS[kind], "enabled": true, "spots": [pos]})
	for k in range(ALT_SPOTS - 1):
		for st in structures:
			var pos := _best_spot(st["biome"], st["half"], dirs, placed_boxes)
			if pos == Vector3.INF:
				continue
			placed_boxes.append(pocket_aabb(pos, st["half"]))
			(st["spots"] as Array).append(pos)

func _best_spot(id: String, half: Vector3, dirs: Array[Vector3], placed: Array[AABB]) -> Vector3:
	var best_score := -INF
	var best_pos := Vector3.INF
	for box in _spot_boxes(id, half, dirs):
		var score := INF
		for o in placed:
			score = minf(score, _box_gap(box, o))
		if score < STRUCT_GAP:
			continue
		if score > best_score:
			best_score = score
			best_pos = box.position + Vector3(half.x, 0, half.z)
	return best_pos

## The pocket boxes of one size that fit a biome, worked out once per size:
## every later spot only measures the gap to what is already placed.
var _spot_cache := {}
func _spot_boxes(id: String, half: Vector3, dirs: Array[Vector3]) -> Array[AABB]:
	var key := "%s|%s" % [id, half]
	if _spot_cache.has(key):
		return _spot_cache[key]
	var b := biome(id)
	var shell := int(b.get("shell", 0))
	var depth := float(b.get("structure_depth", FPWorldFeatures.REST_DEPTH[shell]))
	var w := carve_window(shell)
	if shell == 0:
		w.x = CORE_STRUCT_MIN
	var out: Array[AABB] = []
	for d in dirs:
		var mid: Vector3 = center + d * depth
		if biome_at(mid) != id:
			continue
		var box := pocket_aabb(mid - Vector3(0, half.y, 0), half)
		if _box_ok(box, w, shell):
			out.append(box)
	_spot_cache[key] = out
	return out

func _box_ok(box: AABB, w: Vector2, shell: int) -> bool:
	for i in range(8):
		var c := box.get_endpoint(i)
		var dd := c.distance_to(center)
		if dd < w.x or dd > w.y:
			return false
		if FPWorldFeatures.shell_of_depth(dd) != shell:
			return false
	for t in _tumors:
		if _point_box_dist(t, box) < STRUCT_TUMOR_GAP:
			return false
	# the core's door corridor
	var mid := box.get_center() - center
	if shell == 0 and mid.normalized().z > 0.55:
		return false
	# core structures keep to the sides of the restroom (the core once had
	# rest containers above and below it; the placement is kept as it was)
	if shell == 0 and absf(mid.normalized().y) > 0.6:
		return false
	return true

static func _point_box_dist(p: Vector3, box: AABB) -> float:
	var q := (p - box.get_center()).abs() - box.size * 0.5
	return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()

static func _box_gap(a: AABB, b: AABB) -> float:
	var q := (a.get_center() - b.get_center()).abs() - (a.size + b.size) * 0.5
	return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()

## Puts each structure on its first spot clear of the rest containers (each
## with its own box, FPWorldFeatures.REST_LAYOUT), or leaves it out when none
## is. Returns true when anything moved.
func apply_rest_points(rests: Array[Vector3], halves: Array[Vector3] = []) -> bool:
	var changed := false
	if halves.is_empty():
		halves = FPWorldFeatures._halves_for(rests.size())
	for s in structures:
		var chosen := Vector3.INF
		for spot in s["spots"]:
			var box := pocket_aabb(spot, s["half"])
			var ok := true
			for i in range(rests.size()):
				if _box_gap(box, AABB(rests[i] - halves[i], halves[i] * 2.0)) < STRUCT_GAP:
					ok = false
					break
			if ok:
				chosen = spot
				break
		var on := chosen != Vector3.INF
		if on != bool(s["enabled"]) or (on and not (chosen as Vector3).is_equal_approx(s["pos"])):
			changed = true
		s["enabled"] = on
		if on:
			s["pos"] = chosen
	# A structure whose every spot lies against a rest container (the stem
	# rests stand on the door axis, where a biome can be crowded) takes the
	# spot of its biome farthest from the rests and from the structures that
	# kept theirs, so the fixed layout leaves none out. The others stay put.
	for s in structures:
		if bool(s["enabled"]):
			continue
		var taken: Array[AABB] = []
		for i in range(rests.size()):
			taken.append(AABB(rests[i] - halves[i], halves[i] * 2.0))
		for o in structures:
			if bool(o["enabled"]):
				taken.append(pocket_aabb(o["pos"], o["half"]))
		var spot := _best_spot(s["biome"], s["half"], FPWorldFeatures.fibonacci_dirs(STRUCT_DIRS), taken)
		if spot == Vector3.INF:
			continue
		(s["spots"] as Array).append(spot)
		s["pos"] = spot
		s["enabled"] = true
		changed = true
	_index_pockets()
	return changed


func _index_pockets() -> void:
	_pockets.clear()
	_pocket_depth = Vector2(INF, -INF)
	for s in structures:
		if not s["enabled"]:
			continue
		var box := pocket_aabb(s["pos"], s["half"])
		_pockets.append(box)
		for i in range(8):
			var dd := box.get_endpoint(i).distance_to(center)
			_pocket_depth.x = minf(_pocket_depth.x, dd - 0.01)
			_pocket_depth.y = maxf(_pocket_depth.y, dd + 0.01)
		# a box's nearest point can be closer than any corner
		_pocket_depth.x = minf(_pocket_depth.x, _point_box_dist(center, box))

## One empty anchor per structure under `parent` (hidden when disabled).
## The art itself is built only near the player (stream_art): the pockets
## sit inside solid flesh, past the fog, until someone digs to them.
func build_structures(parent: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for i in range(structures.size()):
		var s: Dictionary = structures[i]
		var n := Node3D.new()
		n.name = "Structure_%d_%s" % [i, s["kind"]]
		n.position = s["pos"]
		n.set_meta("structure", i)
		n.set_meta("kind", s["kind"])
		n.set_meta("biome", s["biome"])
		n.visible = bool(s["enabled"])
		parent.add_child(n)
		out.append(n)
	return out

## Art is built when the player can see into a pocket: within ART_NEAR
## (the terrain fog is full at 11 m, FDKPs1Settings.fog_distance) with no
## flesh in between, or within ART_TOUCH whatever is in between. It is freed
## past ART_FAR; the gap keeps it from building and freeing at the edge.
const ART_NEAR := 11.0
const ART_FAR := 14.0
const ART_TOUCH := 2.0

## Builds or frees each anchor's art for a player at p. With `terrain`
## (an FDKTerrainField) a pocket behind solid flesh is not built, and at
## most `max_builds` are built in one call (-1 no limit); without it every
## pocket within ART_NEAR is. Returns how many structures have art.
func stream_art(nodes: Array[Node3D], p: Vector3, terrain: Node = null, max_builds: int = -1) -> int:
	var built := 0
	var builds := 0
	for n in nodes:
		var s: Dictionary = structures[int(n.get_meta("structure"))]
		var has := n.get_child_count() > 0
		var box := pocket_aabb(s["pos"], s["half"])
		var dist := _point_box_dist(p, box)
		if n.visible and has and dist < ART_FAR:
			built += 1
		elif n.visible and not has and dist < ART_NEAR and builds != max_builds:
			if terrain == null or dist < ART_TOUCH or _in_sight(terrain, p, box):
				_build_art(n, String(s["kind"]))
				builds += 1
				built += 1
		elif has:
			for c in n.get_children():
				n.remove_child(c)
				c.queue_free()
	return built

## Open flesh all the way from p to the pocket (its nearest point or its
## middle): every half metre on the way is below the surface level.
func _in_sight(terrain: Node, p: Vector3, box: AABB) -> bool:
	var near := p.clamp(box.position, box.end)
	var inward := box.get_center() - near
	near += inward.limit_length(0.3)
	for target in [near, box.get_center()]:
		var ray: Vector3 = target - p
		var length := ray.length()
		var open := true
		var t := 0.4
		while t < length - 0.3:
			if float(terrain.density_at(p + ray * (t / length))) >= 0.5:
				open = false
				break
			t += 0.5
		if open:
			return true
	return false

func _build_art(anchor: Node3D, kind: String) -> void:
	var path := "res://main/art/fp_struct_%s.gd" % kind
	if not ResourceLoader.exists(path):
		return
	var art := (load(path) as GDScript).new() as Node3D
	art.name = "Art"
	anchor.add_child(art)
	if art.has_method("set_light"):
		art.call("set_light", true)
