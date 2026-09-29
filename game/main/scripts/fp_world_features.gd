class_name FPWorldFeatures
extends RefCounted

## Fixed world layout for the prototype (docs/spec/02-world-tissue.md): 3 shells around
## the restroom, rest points (a swallowed construction container office,
## identical everywhere, several per shell) and tumors embedded in flesh.

const SHELL_THICKNESS := 9.0
const SHELL_COUNT := 3
const OUTER_RADIUS := SHELL_THICKNESS * SHELL_COUNT
## Container office interior half extents (a 20 ft container, roughly).
const CONTAINER_HALF := Vector3(1.1, 1.1, 2.2)
## Rest points (docs/spec/07-danger-navigation.md 6): 2 / 4 / 6 per shell, at
## the middle depth of each shell, spread evenly over the sphere with a
## per-game random rotation, same-shell points at least 90 degrees apart.
const REST_PER_SHELL := [2, 4, 6]
const REST_DEPTH := [4.5, 13.5, 22.5]
const REST_MIN_ANGLE_DEG := 90.0
## Restroom box half size + the membrane band around it (main.gd); a rest
## container must stay clear of it.
const ROOM_CLEAR_HALF := Vector3(1.5 + 1.55, 1.3 + 1.55, 1.5 + 1.55)
## Shell boundary membrane band (02-world-tissue.md 2) and the blend zone
## before it where the next shell's tissue starts to mix in.
const BOUNDARY_BAND := 0.9
const BLEND_ZONE := 1.8
const TUMORS_PER_SHELL := 4
const TUMOR_DEPTH := [6.8, 15.5, 24.0]

static func shell_of_depth(depth: float) -> int:
	return clampi(int(depth / SHELL_THICKNESS), 0, SHELL_COUNT - 1)

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

## Evenly spread sets that meet the 90 degree rule exactly when Fibonacci
## points cannot (6 points at >= 90 degrees is only the octahedron).
static func _regular_dirs(count: int) -> Array[Vector3]:
	match count:
		1: return [Vector3.UP]
		2: return [Vector3.UP, Vector3.DOWN]
		3: return [Vector3(1, 0, 0), Vector3(-0.5, 0, 0.866), Vector3(-0.5, 0, -0.866)]
		4: return [Vector3(1, 1, 1).normalized(), Vector3(1, -1, -1).normalized(), Vector3(-1, 1, -1).normalized(), Vector3(-1, -1, 1).normalized()]
		_: return [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]

static func min_angle_deg(dirs: Array[Vector3]) -> float:
	var best := 180.0
	for i in range(dirs.size()):
		for j in range(i + 1, dirs.size()):
			best = minf(best, rad_to_deg(dirs[i].angle_to(dirs[j])))
	return best

static func _rest_clear_of_room(center: Vector3, at: Vector3) -> bool:
	var q := (at - center).abs()
	var h := CONTAINER_HALF
	return q.x > ROOM_CLEAR_HALF.x + h.x or q.y > ROOM_CLEAR_HALF.y + h.y or q.z > ROOM_CLEAR_HALF.z + h.z

## One game's rest points. `seed` fixes the random rotation (saved with the
## game); a rotation that pushes a container into the restroom band or the
## door's corridor is re-rolled.
static func rest_points(center: Vector3, seed: int = 1) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	for s in range(SHELL_COUNT):
		var n: int = REST_PER_SHELL[s]
		var dirs := fibonacci_dirs(n)
		if min_angle_deg(dirs) < REST_MIN_ANGLE_DEG:
			dirs = _regular_dirs(n)
		rng.seed = hash([seed, s])
		# random rotations until every container clears the restroom and its
		# door corridor; always returns the full count (best try kept).
		var best: Array[Vector3] = []
		var best_bad := 1 << 30
		for attempt in range(512):
			var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			if axis.length() < 0.1:
				axis = Vector3.UP
			var b := Basis(axis.normalized(), rng.randf_range(0.0, TAU))
			var pts: Array[Vector3] = []
			var bad := 0
			for d in dirs:
				var p: Vector3 = center + (b * d).normalized() * REST_DEPTH[s]
				if not _rest_clear_of_room(center, p):
					bad += 2
				elif p.z - center.z > 0.0 and absf(p.x - center.x) < 2.6 and p.y - center.y < 3.4:
					bad += 1
				pts.append(p)
			if bad < best_bad:
				best_bad = bad
				best = pts
			if bad == 0:
				break
		out.append_array(best)
	return out

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
	if has_next and into > SHELL_THICKNESS - BOUNDARY_BAND - BLEND_ZONE:
		var k := (into - (SHELL_THICKNESS - BOUNDARY_BAND - BLEND_ZONE)) / BLEND_ZONE
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
	return out

static func in_container(p: Vector3, rests: Array[Vector3]) -> bool:
	for c in rests:
		var q := (p - c).abs()
		if q.x <= CONTAINER_HALF.x and q.y <= CONTAINER_HALF.y and q.z <= CONTAINER_HALF.z:
			return true
	return false

## Rest point: the main/art container office model (door on its long side),
## stretched to the logic box CONTAINER_HALF with its floor on the box floor.
static func build_container(parent: Node3D, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "RestPoint"
	root.position = at
	root.set_meta("rest_point", true)
	parent.add_child(root)
	var art: Node3D = (load("res://main/art/fp_rest_container.tscn") as PackedScene).instantiate()
	art.name = "ContainerArt"
	var h := CONTAINER_HALF
	# art frame: long side along X (half 1.5), width Z (half 1.2), height 1.3
	art.rotation.y = PI * 0.5
	art.scale = Vector3(h.z / 1.5, (h.y * 2.0) / 1.3, h.x / 1.2)
	art.position = Vector3(0, -h.y, 0)
	root.add_child(art)
	art.call("set_light", true)
	art.call("set_door_open", 0.8)
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

## Tumor: the main/art lump model, one of its 3 silhouettes per kind.
static func build_tumor(parent: Node3D, spot: Dictionary) -> Node3D:
	var t: Node3D = (load("res://main/art/fp_tumor.tscn") as PackedScene).instantiate()
	t.name = "Tumor_" + String(spot["kind"])
	t.position = spot["pos"]
	t.set_meta("kind", spot["kind"])
	parent.add_child(t)
	t.call("set_variant", maxi(0, FPProgression.TUMOR_KINDS.find(String(spot["kind"]))) % 3)
	t.call("set_pulse", true)
	return t
