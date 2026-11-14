class_name FPWorldFeatures
extends RefCounted

## Fixed world layout for the prototype (docs/spec/02-world-tissue.md): 3 shells around
## the restroom, rest points (a swallowed construction container office,
## identical everywhere, at fixed places: REST_LAYOUT) and tumors embedded in flesh.

const SHELL_THICKNESS := 9.0
const SHELL_COUNT := 3
const OUTER_RADIUS := SHELL_THICKNESS * SHELL_COUNT
## Container office interior half extents (a 20 ft container, roughly), for a
## box whose long side lies along Z. REST_LAYOUT gives every rest its own.
const CONTAINER_HALF := Vector3(1.1, 1.1, 2.2)
## Fixed rest points (decision 0016, 2026-11-14): none in the core, three in
## the mantle, four in the surface shell. `offset` is the box centre from the
## restroom centre (the door axis is +Z), `yaw` the model's turn (its door is
## on its +Z long wall: PI faces the restroom down the door axis, +-PI/2 face
## across toward it), `half` the box half extents in the world, `loot` the
## spray can on its chair. The two stem rests sit straight ahead of the
## restroom door, just behind the membrane of the shell before them (door
## face 9.9 m and 18.9 m out, door opening centred on the door axis), and
## hold a cheap can; the side rests sit at the middle depth of their shell.
const REST_LAYOUT := [
	{"shell": 1, "name": "mantle_stem", "offset": Vector3(0.61, 0.0, 11.0), "yaw": PI, "half": Vector3(2.2, 1.1, 1.1), "loot": "spray_cheap"},
	{"shell": 1, "name": "mantle_left", "offset": Vector3(-13.04, 0.0, 3.49), "yaw": PI * 0.5, "half": Vector3(1.1, 1.1, 2.2), "loot": "spray_deep"},
	{"shell": 1, "name": "mantle_right", "offset": Vector3(13.04, 0.0, 3.49), "yaw": -PI * 0.5, "half": Vector3(1.1, 1.1, 2.2), "loot": "spray_deep"},
	{"shell": 2, "name": "surface_stem", "offset": Vector3(0.61, 0.0, 20.0), "yaw": PI, "half": Vector3(2.2, 1.1, 1.1), "loot": "spray_cheap"},
	{"shell": 2, "name": "surface_left_front", "offset": Vector3(-17.24, 0.0, 14.46), "yaw": PI * 0.5, "half": Vector3(1.1, 1.1, 2.2), "loot": "spray_deep"},
	{"shell": 2, "name": "surface_right", "offset": Vector3(21.73, 0.0, -5.82), "yaw": -PI * 0.5, "half": Vector3(1.1, 1.1, 2.2), "loot": "spray_deep"},
	{"shell": 2, "name": "surface_left_back", "offset": Vector3(-18.43, 0.0, -12.91), "yaw": PI * 0.5, "half": Vector3(1.1, 1.1, 2.2), "loot": "spray_deep"},
]
## Rest points per shell (the economy calculator reads this; a test ties it
## to REST_LAYOUT) and the middle depth of each shell (the default depth of
## biome structures, FPBiomes).
const REST_PER_SHELL := [0, 3, 4]
const REST_DEPTH := [4.5, 13.5, 22.5]
## The flesh stands this far off a container's walls, floor and roof (as it
## does off the restroom's, main.ROOM_MARGIN).
const REST_MARGIN := 0.04
## Shell boundary membrane band (02-world-tissue.md 2) and the blend zone
## before it where the next shell's tissue starts to mix in, per shell. The
## core mixes nothing in: its flesh stays bare-hand flesh up to its membrane,
## so the first expeditions fill the stomach before the knife is needed
## (decision 0008; the mantle's muscle would need a blade from 6.3 m).
const BOUNDARY_BAND := 0.9
const BLEND_ZONE := [0.0, 1.8, 1.8]
const TUMORS_PER_SHELL := 4
## One more tumor in the mantle and the surface (docs/spec/09-reward-scale.md
## D10/D18: 14 >= 6 codex kinds + 7 tumor mutations, and an encounter every
## 2~6 expeditions per shell). They come after the original 12 so saved
## spot indices keep pointing at the same tumors.
const EXTRA_TUMORS := [0, 1, 1]

static func tumors_in_shell(s: int) -> int:
	return TUMORS_PER_SHELL + int(EXTRA_TUMORS[s])
const TUMOR_DEPTH := [6.8, 15.5, 24.0]

static func shell_of_depth(depth: float) -> int:
	return clampi(int(depth / SHELL_THICKNESS), 0, SHELL_COUNT - 1)

## Distance from p to the outside of the restroom box (main.gd's ROOM_MARGIN /
## door-gap rules use this to know how close a point is to the room walls).
static func room_dist(p: Vector3, room_half: Vector3) -> float:
	var q := Vector3(absf(p.x) - room_half.x, maxf(-p.y, p.y - 2.0 * room_half.y), absf(p.z) - room_half.z)
	return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()

## True inside the restroom box + membrane margin (or the wider door gap
## when p is in front of the door), false once past the outer shells or
## inside a rest-point container -- i.e. "carve this to zero density".
## `halves` are the rests' own box half extents (rest_halves(); left out, the
## layout's when `rests` is the layout, else CONTAINER_HALF).
static func world_density(p: Vector3, room_half: Vector3, door_half_w: float, door_h: float,
		room_margin: float, door_gap: float, center: Vector3, outer_radius: float,
		rests: Array[Vector3], halves: Array[Vector3] = []) -> float:
	if p.distance_to(center) >= outer_radius:
		return 0.0
	if halves.is_empty():
		halves = _halves_for(rests.size())
	# A container's hollow is ramped like the room's: the iso crossing falls
	# REST_MARGIN outside the steel instead of up to half a cell to either
	# side of it (flesh used to show through the rear wall).
	for i in range(rests.size()):
		var q: Vector3 = (p - rests[i]).abs() - halves[i]
		var m := maxf(q.x, maxf(q.y, q.z))
		if m >= 0.5 + REST_MARGIN:
			continue
		var sd := (Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() if m > 0.0 else m) - REST_MARGIN
		if sd < 0.5:
			return clampf(0.5 + sd, 0.0, 1.0)
	var margin := room_margin
	if p.z > room_half.z and absf(p.x) < door_half_w and p.y > -0.1 and p.y < door_h:
		margin = door_gap
	# Restore the original irregular surface at the exposed door opening.
	if p.z > room_half.z - 0.2 and absf(p.x) < door_half_w + 0.1 and p.y > 0.0 and p.y < door_h:
		return 1.0 if p.z > room_half.z + door_gap else 0.0
	var signed_distance := maxf(absf(p.x) - room_half.x, maxf(maxf(-p.y, p.y - 2.0 * room_half.y), absf(p.z) - room_half.z)) - margin
	if signed_distance < 0.5:
		# Interpolated iso crossings fall on the wall instead of half a grid
		# cell beyond it. A binary carve created a visible perimeter air gap.
		return clampf(0.5 + signed_distance, 0.0, 1.0)
	return 1.0

## True in the corridor in front of (and a bit behind) the door -- the
## column that must stay carved out for the player to walk through.
static func in_door_column(p: Vector3, door_half_w: float, door_h: float) -> bool:
	return p.z > 0.0 and absf(p.x) < door_half_w + 0.9 and p.y < door_h + 0.9

## Tissue ids: 0 flesh, 1 nerve bundle, 2 fat band (shell boundary),
## 3 membrane (restroom shell), 4 contractile fibers (mantle, needs a blade).
## `room_membrane` is true when p is within membrane_thickness + room_margin
## of the restroom box and not in the door column (main.gd computes this).
static func world_tissue_at(p: Vector3, center: Vector3, noise: float, room_membrane: bool) -> int:
	return world_tissue(p, center, noise, room_membrane)

## Depth-danger regen multiplier at p (FDKDepthDanger, keyed by distance
## from the restroom center against the shell thickness).
static func regen_scale(p: Vector3, center: Vector3, shell_thickness: float) -> float:
	return FDKDepthDanger.danger_multiplier(p.distance_to(center), shell_thickness)

## Deterministic, well-spread directions (golden spiral), skipping the
## straight-up and straight-down poles and the door's +Z opening cone.
static func _dirs(count: int, offset: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var i := 0
	var k := 0
	while out.size() < count and k < 200:
		var t := (float(k) + 0.5 + offset) / float(count + 6)
		var y := clampf(1.0 - 2.0 * t, -0.7, 0.7) * 0.6
		var r := sqrt(1.0 - y * y)
		var a := float(k) * 2.39996 + offset * 3.1
		var d := Vector3(cos(a) * r, y, sin(a) * r).normalized()
		k += 1
		if d.z > 0.8:
			continue
		out.append(d)
		i += 1
	return out

## Fibonacci-sphere directions (even spread over the whole sphere).
static func fibonacci_dirs(count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for k in range(count):
		var y := 1.0 - 2.0 * (float(k) + 0.5) / float(count)
		var r := sqrt(maxf(0.0, 1.0 - y * y))
		var a := float(k) * 2.39996323
		out.append(Vector3(cos(a) * r, y, sin(a) * r))
	return out

## Shell of rest point `i` (REST_LAYOUT order).
static func rest_shell(i: int) -> int:
	return int(REST_LAYOUT[clampi(i, 0, REST_LAYOUT.size() - 1)]["shell"])

static func rest_count() -> int:
	return REST_LAYOUT.size()

## Box centres of the rest points, REST_LAYOUT order. The same every game.
static func rest_points(center: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for r in REST_LAYOUT:
		out.append(center + (r["offset"] as Vector3))
	return out

## Each rest's box half extents in the world (its long side along X or Z).
static func rest_halves() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for r in REST_LAYOUT:
		out.append(r["half"])
	return out

static var _layout_halves: Array[Vector3] = []
static var _plain_halves: Array[Vector3] = []
static func _halves_for(count: int) -> Array[Vector3]:
	if count == REST_LAYOUT.size():
		if _layout_halves.is_empty():
			_layout_halves = rest_halves()
		return _layout_halves
	while _plain_halves.size() < count:
		_plain_halves.append(CONTAINER_HALF)
	return _plain_halves

static func rest_yaw(i: int) -> float:
	return float(REST_LAYOUT[i]["yaw"])

static func rest_loot(i: int) -> String:
	return String(REST_LAYOUT[i]["loot"])

## A point of the container model (its own frame: origin at the floor centre,
## long side along X, door on +Z) in the frame of rest `i`'s box centre.
static func rest_local(i: int, art_point: Vector3) -> Vector3:
	var half: Vector3 = REST_LAYOUT[i]["half"]
	return Basis(Vector3.UP, rest_yaw(i)) * art_point + Vector3(0.0, -half.y, 0.0)

## Tissue at p (02-world-tissue.md 1-3). `noise` is a -1..1 world noise
## value at p, `room_membrane` true inside the membrane around the restroom.
static func world_tissue(p: Vector3, center: Vector3, noise: float, room_membrane: bool) -> int:
	if room_membrane:
		return FDKTissueRules.MEMBRANE
	var depth := p.distance_to(center)
	var shell := shell_of_depth(depth)
	var into := fposmod(depth, SHELL_THICKNESS)
	var has_next := shell < SHELL_COUNT - 1
	if has_next and into > SHELL_THICKNESS - BOUNDARY_BAND:
		return FDKTissueRules.MEMBRANE
	var t: int = FDKTissueRules.SHELL_TISSUE[shell]
	# the next shell's tissue mixes in gradually just before the band
	var blend: float = BLEND_ZONE[shell]
	if has_next and blend > 0.0 and into > SHELL_THICKNESS - BOUNDARY_BAND - blend:
		var k := (into - (SHELL_THICKNESS - BOUNDARY_BAND - blend)) / blend
		if noise * 0.5 + 0.5 < k:
			t = FDKTissueRules.SHELL_TISSUE[shell + 1]
	# a few nerve bundles everywhere, packed in the surface shell
	var nerve_cut := 0.12 if t == FDKTissueRules.NERVE else 0.42
	if noise > nerve_cut:
		return FDKTissueRules.NERVE
	return t

## Returns [{pos, kind, shell}].
static func tumor_spots(center: Vector3) -> Array:
	var out: Array = []
	for s in range(SHELL_COUNT):
		var kinds: Array[String] = [FPProgression.TUMOR_KINDS[s * 2], FPProgression.TUMOR_KINDS[s * 2 + 1]]
		var dirs := _dirs(TUMORS_PER_SHELL, float(s) * 0.61 + 0.2)
		for i in range(dirs.size()):
			out.append({"pos": center + dirs[i] * TUMOR_DEPTH[s], "kind": kinds[i % 2], "shell": s})
	for s in range(SHELL_COUNT):
		var dirs := _dirs(TUMORS_PER_SHELL, float(s) * 0.61 + 0.2)
		for e in range(int(EXTRA_TUMORS[s])):
			# halfway between two of the shell's tumors, so it is a new direction
			var d: Vector3 = (dirs[e % dirs.size()] + dirs[(e + 1) % dirs.size()]).normalized()
			out.append({"pos": center + d * TUMOR_DEPTH[s], "kind": FPProgression.TUMOR_KINDS[s * 2 + 1], "shell": s})
	return out

## Index of the rest container p is inside (-1 = none). `halves` as in
## world_density.
static func rest_at(p: Vector3, rests: Array[Vector3], halves: Array[Vector3] = []) -> int:
	if halves.is_empty():
		halves = _halves_for(rests.size())
	for i in range(rests.size()):
		var q: Vector3 = (p - rests[i]).abs()
		var h: Vector3 = halves[i]
		if q.x <= h.x and q.y <= h.y and q.z <= h.z:
			return i
	return -1

static func in_container(p: Vector3, rests: Array[Vector3], halves: Array[Vector3] = []) -> bool:
	return rest_at(p, rests, halves) >= 0

## Rest point: the main/art container office model (door on its long side),
## at its real size (never stretched: that bent the chair and bucket inside),
## turned by `yaw` so its long side lies along the long side of `half`, its
## floor on the box floor. `loot` = the spray can left on its chair ("" none).
static func build_container(parent: Node3D, at: Vector3, yaw: float = PI * 0.5, half: Vector3 = CONTAINER_HALF, loot: String = "") -> Node3D:
	var root := Node3D.new()
	root.name = "RestPoint"
	root.position = at
	root.set_meta("rest_point", true)
	parent.add_child(root)
	var art: Node3D = (load("res://main/art/fp_rest_container.tscn") as PackedScene).instantiate()
	art.name = "ContainerArt"
	# art frame: long side along X, width Z, height 2 half.y, door on +Z
	art.rotation.y = yaw
	art.position = Vector3(0, -half.y, 0)
	root.add_child(art)
	art.call("set_light", true)
	art.call("set_door_open", 0.8)
	if loot != "":
		# standing on the chair seat
		var can := FPConsumable.make(loot)
		can.name = "LootCan"
		can.set_meta("loot", loot)
		root.add_child(can)
		can.position = art.transform * (art.call("chair_point") as Vector3) + Vector3(0, 0.08, 0)
		can.rotation.y = 0.6
	return root

## Old placeholder container (kept for reference, no longer called).
static func build_container_placeholder(parent: Node3D, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "RestPoint"
	root.position = at
	parent.add_child(root)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.45, 0.55)
	var h := CONTAINER_HALF
	for spec in [[Vector3(0, -h.y, 0), Vector3(h.x * 2, 0.05, h.z * 2)], [Vector3(0, h.y, 0), Vector3(h.x * 2, 0.05, h.z * 2)],
			[Vector3(-h.x, 0, 0), Vector3(0.05, h.y * 2, h.z * 2)], [Vector3(h.x, 0, 0), Vector3(0.05, h.y * 2, h.z * 2)],
			[Vector3(0, 0, -h.z), Vector3(h.x * 2, h.y * 2, 0.05)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[1]
		mi.mesh = bm
		mi.material_override = m
		mi.position = spec[0]
		root.add_child(mi)
	var bucket := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.15
	cm.height = 0.35
	bucket.mesh = cm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.85, 0.85, 0.8)
	bucket.material_override = bmat
	bucket.name = "Bucket"
	bucket.position = Vector3(0, -h.y + 0.2, -h.z + 0.5)
	root.add_child(bucket)
	return root

## Tumor: the main/art lump model of its kind (03-restroom.md 10).
static func build_tumor(parent: Node3D, spot: Dictionary) -> Node3D:
	var t: Node3D = (load("res://main/art/fp_tumor.tscn") as PackedScene).instantiate()
	t.name = "Tumor_" + String(spot["kind"])
	t.position = spot["pos"]
	t.set_meta("kind", spot["kind"])
	parent.add_child(t)
	t.call("set_variant", maxi(0, FPProgression.TUMOR_KINDS.find(String(spot["kind"]))))
	t.call("set_pulse", true)
	return t
