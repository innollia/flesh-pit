class_name FPWorldFeatures
extends RefCounted

## Fixed world layout for the prototype (design-core 7/9): 3 shells around
## the restroom, rest points (a swallowed construction container office,
## identical everywhere, several per shell) and tumors embedded in flesh.

const SHELL_THICKNESS := 9.0
const SHELL_COUNT := 3
const OUTER_RADIUS := SHELL_THICKNESS * SHELL_COUNT
## Container office interior half extents (a 20 ft container, roughly).
const CONTAINER_HALF := Vector3(1.1, 1.1, 2.2)
const REST_PER_SHELL := [2, 3, 4]
const REST_DEPTH := [5.8, 13.5, 22.5]
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

static func rest_points(center: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for s in range(SHELL_COUNT):
		for d in _dirs(REST_PER_SHELL[s], float(s) * 0.37):
			out.append(center + d * REST_DEPTH[s])
	return out

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
