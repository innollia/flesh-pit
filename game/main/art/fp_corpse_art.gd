extends RefCounted

## What the flesh did to a body left out there (decision 0017). The skin
## coloured lump Main builds stays as it is; on its back lies a mat of the
## player's own dark hair ("this was me"), and every coloured hair the death
## left on it has grown out into one stalk with a bud of that hair's colour.
## Stalks = hairs to take back, nothing else: no growth over time, no sway,
## no light, no sound. Only shows FDKDeathDrop.items["hairs"]; the rules are
## FPProgression's (take_death_payload / restore_death_payload). Loaded by
## path (Main's FPCorpseArt), like the other scripts added after the class
## cache was built.
##
## Everything is in the "Body" mesh's local space. The capsule lies on its
## side (Z 90 degrees), so local +X is the world's up and local Y the body's
## long axis.

const K := preload("res://main/art/fp_art_kit.gd")
const ArmHair := preload("res://main/art/fp_arm_hair.gd")

## Turn this off when the mat reads wrong ("the dark hair is lost too", or it
## hides the skin): the stalks stay.
const SHOW_FUZZ := true
const FUZZ_STRANDS := 90
const FUZZ_LEN := 0.10 ## m; grow() scatters it 0.7..1.3 times
const FUZZ_RADIUS := 0.006
const MAX_STALKS := 24
const STALK_LEN := Vector2(0.22, 0.40)
const STALK_RADII := [0.012, 0.009, 0.004] ## root, middle, end
const TIP_RADIUS := 0.014
const TIP_LEN := 0.04
## Past MAX_STALKS the stalks only get thicker, up to this many times.
const MAX_THICKEN := 2.0
## The lump Main builds (Main._new_death_drop): where the stalks root.
const BODY_RADIUS := 0.17
const BODY_SPAN := 0.33 ## stalks root this far along the long axis, each way
const BODY_ARC := 0.9 ## and this far round the back, each way (rad)

## SHOW_FUZZ for this run (a check turns it off to see the stalks alone).
static var show_fuzz := SHOW_FUZZ

## Rebuilds the mat, the stalks and their buds from what lies on the body.
## Calling it again leaves one of each.
static func dress(drop: FDKDeathDrop) -> void:
	if drop == null:
		return
	var body := drop.get_node_or_null("Body") as MeshInstance3D
	if body == null or body.mesh == null:
		return
	for part in ["Fuzz", "Stalks", "Tips"]:
		var old := body.get_node_or_null(part)
		if old != null:
			# a freed node keeps its name until the frame ends
			body.remove_child(old)
			old.queue_free()
	var seed := look_seed(drop.last_known_position)
	if show_fuzz:
		# dense on the back (up), thin on the flanks, none underneath: the
		# skin colour still shows from the side
		var back := func(_p: Vector3, nrm: Vector3) -> float: return clampf(0.25 + nrm.x * 0.9, 0.0, 1.0)
		var mat_mesh := FPBodyHair.grow(_skin_of(body.mesh), FUZZ_STRANDS, ["common"], seed, back, Vector3.DOWN, FUZZ_LEN, FUZZ_RADIUS)
		K.add_mesh(body, "Fuzz", mat_mesh, _hair_material())
	var pools := stalk_pools(drop.items)
	if pools.is_empty():
		return
	var thick := thickness(FPProgression.payload_hairs(drop.items))
	var st := K.begin()
	var tips := K.begin()
	for i in range(pools.size()):
		var pool: String = pools[i]
		var kind: Color = ArmHair.COLORS.get(pool, ArmHair.HAIR)
		var root: Color = ArmHair.HAIR.lerp(kind, ArmHair.TINT)
		var a := lerpf(-BODY_ARC, BODY_ARC, K.h(i, seed, 2))
		var nrm := Vector3(cos(a), 0.0, sin(a))
		var base := Vector3(BODY_RADIUS * cos(a), lerpf(-BODY_SPAN, BODY_SPAN, K.h(i, seed, 1)), BODY_RADIUS * sin(a))
		# up out of the back, each leaning its own way a little
		var dir := (nrm * 0.35 + Vector3.RIGHT * 0.65 + Vector3.UP * (K.h(i, seed, 3) - 0.5) * 0.3).normalized()
		var length := lerpf(STALK_LEN.x, STALK_LEN.y, K.h(i, seed, 4))
		var side := dir.cross(Vector3.UP)
		side = side.normalized() if side.length_squared() > 1e-6 else Vector3.BACK
		var bend := side * length * 0.08 * (1.0 if K.h(i, seed, 5) > 0.5 else -1.0)
		var end := base + dir * length
		K.tube(st, Transform3D.IDENTITY, [base - nrm * 0.01, base + dir * length * 0.5 + bend, end],
			[STALK_RADII[0] * thick, STALK_RADII[1] * thick, STALK_RADII[2] * thick], 3, [root, root.lerp(kind, 0.5)], false)
		K.tube(tips, Transform3D.IDENTITY, [end - dir * TIP_LEN * 0.25, end + dir * TIP_LEN * 0.25, end + dir * TIP_LEN * 0.75],
			[STALK_RADII[2] * thick, TIP_RADIUS * thick, TIP_RADIUS * 0.2 * thick], 4, [kind], true)
	var stalks := K.add_mesh(body, "Stalks", K.finish(st, 40.0), _hair_material())
	stalks.set_meta("stalks", pools.size())
	# the bud is drawn unshaded so its colour reads in a dark tunnel and in
	# fog; it lights nothing around it (no lamp: the stake has the only one)
	K.add_mesh(body, "Tips", K.finish(tips, 40.0), K.glow(Color(1, 1, 1)))

## Stalks drawn on a body right now.
static func stalk_count(drop: FDKDeathDrop) -> int:
	if drop == null:
		return 0
	var stalks := drop.get_node_or_null("Body/Stalks")
	return int(stalks.get_meta("stalks", 0)) if stalks != null else 0

## One pool name per stalk: a stalk for every hair on the body, biome pools in
## FPProgression.BIOMES order and any other pool after them. Past MAX_STALKS
## every pool keeps its share of the MAX_STALKS (one at least while it has any).
static func stalk_pools(items: Dictionary) -> Array[String]:
	var hairs: Dictionary = items.get("hairs", {})
	var order: Array[String] = []
	for b in FPProgression.BIOMES:
		if hairs.has(b):
			order.append(b)
	var rest: Array[String] = []
	for k in hairs.keys():
		if not order.has(String(k)):
			rest.append(String(k))
	rest.sort()
	order.append_array(rest)
	var counts := {}
	var total := 0
	for pool in order:
		# values read back from a save are floats
		var c := maxi(0, int(hairs[pool]))
		counts[pool] = c
		total += c
	if total > MAX_STALKS:
		var used := 0
		var big := ""
		for pool in order:
			var c: int = counts[pool]
			if big == "" or c > int(hairs[big]):
				big = pool
			counts[pool] = 0 if c == 0 else maxi(1, int(floor(float(c) / float(total) * float(MAX_STALKS))))
			used += int(counts[pool])
		counts[big] = int(counts[big]) + MAX_STALKS - used
	var out: Array[String] = []
	for pool in order:
		for i in range(int(counts[pool])):
			out.append(pool)
	return out

## How much thicker the stalks are drawn for `hairs` hairs on the body.
static func thickness(hairs: int) -> float:
	return clampf(float(hairs) / float(MAX_STALKS), 1.0, MAX_THICKEN)

## The same body looks the same after a save and load: its look comes from
## where the death happened.
static func look_seed(at: Vector3) -> int:
	return int(absf(at.x * 73.0 + at.y * 37.0 + at.z * 131.0)) % 9973

## A primitive mesh has no stored surface for grow() to read.
static func _skin_of(mesh: Mesh) -> Mesh:
	if mesh is PrimitiveMesh:
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, (mesh as PrimitiveMesh).get_mesh_arrays())
		return am
	return mesh

## Vertex-coloured, matt. Not the arm's hair material: that one squashes its
## depth toward the eye for the hands rig and would flatten a thing in the world.
static func _hair_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
