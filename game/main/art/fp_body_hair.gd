class_name FPBodyHair
extends RefCounted

## Body hair strands that grow with the arm hair (the mutation-point
## currency, fp_arm_hair.gd). The same dark strand colour, lightly tinted per
## hair kind in the same proportions as the arm, so the body reads as one
## hairy person: the more arm hair, the more strands on legs, chest, belly
## and arms. Low-poly 3-sided strands on the real skin triangles of a part.
## Painted dashes (FPBodyMarks) carry the density where strands are too
## small to read (the low-res mirror).

const K := preload("res://main/art/fp_art_kit.gd")
const ArmHair := preload("res://main/art/fp_arm_hair.gd")

## Arm hair points at which the body is fully hairy. The arm grows past it
## (fp_arm_hair MAX_SLOTS, thicker hairs) and the body stays at its fullest.
const BODY_FULL := 120
## Hair kinds in arm order (fp_arm_hair.gd).
const KINDS := ["common", "core", "mantle", "surface"]

## Hair kinds in arm order, one entry per arm hair point up to BODY_FULL;
## past it every kind keeps its share (at least one while it has any).
static func kinds(counts: Dictionary) -> Array:
	var order := KINDS
	var total := 0
	for kind in order:
		total += maxi(0, int(counts.get(kind, 0)))
	var share := {}
	if total <= BODY_FULL:
		for kind in order:
			share[kind] = maxi(0, int(counts.get(kind, 0)))
	else:
		var used := 0
		var big: String = order[0]
		for kind in order:
			var c := maxi(0, int(counts.get(kind, 0)))
			share[kind] = 0 if c == 0 else maxi(1, int(floor(float(c) / float(total) * float(BODY_FULL))))
			used += int(share[kind])
			if c > int(counts.get(big, 0)):
				big = kind
		share[big] = int(share[big]) + BODY_FULL - used
	var out: Array = []
	for kind in order:
		for i in range(int(share[kind])):
			out.append(kind)
	return out

static func colour(kind: String) -> Color:
	return ArmHair.HAIR.lerp(ArmHair.COLORS.get(kind, ArmHair.HAIR), ArmHair.TINT * 0.35)

## `n` strands on the skin of `mesh` (its own local space). `filter(pos,
## normal) -> float` (0..1) says how hairy each spot is; `lean` is the
## direction the strands lie toward; `length`/`radius` in metres.
static func grow(mesh: Mesh, n: int, kinds_list: Array, seed: int, filter: Callable, lean: Vector3, length: float, radius: float) -> ArrayMesh:
	if mesh == null or n <= 0 or kinds_list.is_empty():
		return ArrayMesh.new()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var tris: Array = []
	var areas := PackedFloat32Array()
	var total := 0.0
	var count := idx.size() / 3 if idx.size() > 0 else verts.size() / 3
	for t in range(count):
		var a := verts[idx[t * 3]] if idx.size() > 0 else verts[t * 3]
		var b := verts[idx[t * 3 + 1]] if idx.size() > 0 else verts[t * 3 + 1]
		var c := verts[idx[t * 3 + 2]] if idx.size() > 0 else verts[t * 3 + 2]
		var ar := (b - a).cross(c - a).length() * 0.5
		if ar <= 1e-8:
			continue
		tris.append([a, b, c])
		total += ar
		areas.append(total)
	if tris.is_empty():
		return ArrayMesh.new()
	# outward = away from the part's own centre (the kit lofts are closed tubes)
	var centre := mesh.get_aabb().get_center()
	var st := K.begin()
	var made := 0
	var tries := 0
	while made < n and tries < n * 8:
		var i := tries
		tries += 1
		var pick := K.h(i, seed, 1) * total
		var lo := 0
		var hi := areas.size() - 1
		while lo < hi:
			var mid := (lo + hi) / 2
			if areas[mid] < pick:
				lo = mid + 1
			else:
				hi = mid
		var tri: Array = tris[lo]
		var u := K.h(i, seed, 2)
		var v := K.h(i, seed, 3)
		if u + v > 1.0:
			u = 1.0 - u
			v = 1.0 - v
		var a3: Vector3 = tri[0]
		var b3: Vector3 = tri[1]
		var c3: Vector3 = tri[2]
		var pos := a3 + (b3 - a3) * u + (c3 - a3) * v
		var nrm := (b3 - a3).cross(c3 - a3).normalized()
		var out := pos - Vector3(centre.x, pos.y, centre.z) if absf(lean.y) > 0.5 else pos - centre
		if nrm.dot(out) < 0.0:
			nrm = -nrm
		if K.h(i, seed, 4) > float(filter.call(pos, nrm)):
			continue
		var kind: String = kinds_list[mini(made * kinds_list.size() / n, kinds_list.size() - 1)]
		var tang := lean - nrm * lean.dot(nrm)
		if tang.length_squared() < 1e-6:
			tang = Vector3.UP.cross(nrm)
		tang = tang.normalized()
		var ln := length * (0.7 + 0.6 * K.h(i, seed, 5))
		var p1 := pos + nrm * ln * 0.45 + tang * ln * 0.35
		var p2 := pos + nrm * ln * 0.6 + tang * ln * 0.9 + nrm.cross(tang) * ln * 0.15 * (K.h(i, seed, 6) - 0.5)
		K.tube(st, Transform3D.IDENTITY, [pos - nrm * 0.001, p1, p2], [radius, radius * 0.75, radius * 0.3], 3, [colour(kind)], false)
		made += 1
	if made == 0:
		return ArrayMesh.new()
	return K.finish(st, 40.0)

## The arm hair counts of a progression, keyed like set_hair()/kinds().
static func counts_of(prog: Object) -> Dictionary:
	if prog == null:
		return {}
	var out := {}
	for kind in KINDS:
		out[kind] = int(prog.call("hairs", kind))
	return out
