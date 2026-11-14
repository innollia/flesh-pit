extends SceneTree

## Furniture and layout (2026-11-14):
## 1. the vent hangs on the door-toilet line, its ceiling hole and duct are
##    made from its centre, and the lamp and light disks stand on that line
##    clear of the open grille
## 2. the toilet is an eight-sided egg bowl (longer in front), with no second
##    lever under the tank's own
## 3. the door is framed on both faces with a lever handle each side and a
##    casing on the wall; its slab, hinge and collision are unchanged
## 4. the tub keeps its outline and gains a sloped inside and a wall tap
## 5. the basin is a bowl on a half pedestal, still under its triangle cap
## 6. the rest container is built at the size of the logic box (not
##    stretched), with the chair and bucket at their real sizes and the
##    bucket where Main judges "at the bucket"
## 7. the paper roll hangs on a bar, the shower hose is one line, and the
##    empty KoreanFixtures mesh is gone

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func world_aabb(mi: MeshInstance3D) -> AABB:
	return mi.global_transform * mi.mesh.get_aabb()

func tri_count(mi: MeshInstance3D) -> int:
	var total := 0
	for s in range(mi.mesh.get_surface_count()):
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		total += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return total

func verts(mi: MeshInstance3D) -> PackedVector3Array:
	return mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

func _run() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_room_furniture.json"
	m.save_path = "user://room-furniture-test.bin"
	root.add_child(m)
	await frames(6)
	m.finish_opening()
	var r: FPRestroom = m.restroom
	_test_vent_and_light(r)
	_test_toilet(r)
	_test_door(r)
	_test_tub(r)
	_test_basin(r)
	_test_small_fixtures(r)
	_test_container()
	_test_shell_seams(r)
	print("ROOM FURNITURE: %d passed, %d failed" % [passed, failed])
	m.queue_free()
	await frames(2)
	quit(1 if failed else 0)

## 8. the shell (floor, ceiling, four walls) stays closed under the screen
##    snap: every vertex on a shell plane is shared by all the planes and
##    pieces that meet there (no vertex part-way along another piece's edge),
##    and the ceiling snaps exactly as the walls do. A vertex the neighbour
##    lacks, or a plane that does not snap, parts the planes by a pixel or
##    two and the flesh outside shows through as dots (2026-11-14 review;
##    capture_room_seams.gd counts them on screen).
func _test_shell_seams(r: FPRestroom) -> void:
	var tiles: MeshInstance3D = r.get_node("Tiles")
	var h := FPRestroom.HALF
	# the shell's own triangles: all three corners on the room box
	var on_box := func(p: Vector3) -> bool:
		var q := (p - Vector3(0, h.y, 0)).abs()
		return q.x <= h.x + 1e-4 and q.y <= h.y + 1e-4 and q.z <= h.z + 1e-4 and (absf(q.x - h.x) < 1e-4 or absf(q.y - h.y) < 1e-4 or absf(q.z - h.z) < 1e-4)
	var tris: Array = []
	var points := {}
	for si in range(tiles.mesh.get_surface_count()):
		var v: PackedVector3Array = tiles.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for i in range(0, v.size(), 3):
			if on_box.call(v[i]) and on_box.call(v[i + 1]) and on_box.call(v[i + 2]):
				tris.append([v[i], v[i + 1], v[i + 2]])
				for k in range(3):
					points[v[i + k]] = true
	check(tris.size() > 40, "the shell is found (%d triangles)" % tris.size())
	var t_junctions := 0
	for t in tris:
		for k in range(3):
			var a: Vector3 = t[k]
			var b: Vector3 = t[(k + 1) % 3]
			var ab := b - a
			for p in points.keys():
				var w: float = (p - a).dot(ab) / ab.length_squared()
				if w > 0.001 and w < 0.999 and (a + ab * w).distance_to(p) < 1e-4:
					t_junctions += 1
	check(t_junctions == 0, "no shell vertex lies part-way along another shell edge (%d)" % t_junctions)
	# the cuts cover the hole and the doorway
	var xs := FPRestroom.shell_cuts(0)
	var ys := FPRestroom.shell_cuts(1)
	var zs := FPRestroom.shell_cuts(2)
	check(xs.size() == 6 and ys.size() == 3 and zs.size() == 4, "shell cuts: room faces, vent hole sides, doorway sides and top (%d, %d, %d)" % [xs.size(), ys.size(), zs.size()])
	var area := 0.0
	var ceil_area := 0.0
	var front_area := 0.0
	for t in tris:
		var ar: float = (t[1] - t[0]).cross(t[2] - t[0]).length() * 0.5
		area += ar
		if absf(t[0].y - 2.0 * h.y) < 1e-4 and absf(t[1].y - 2.0 * h.y) < 1e-4 and absf(t[2].y - 2.0 * h.y) < 1e-4:
			ceil_area += ar
		if absf(t[0].z - h.z) < 1e-4 and absf(t[1].z - h.z) < 1e-4 and absf(t[2].z - h.z) < 1e-4:
			front_area += ar
	check(absf(ceil_area - (4.0 * h.x * h.z - 0.52 * 0.52)) < 0.001, "the ceiling is whole but for the vent hole (%.3f m2)" % ceil_area)
	check(absf(front_area - (4.0 * h.x * h.y - 2.0 * FPRestroom.DOOR_HALF_W * FPRestroom.DOOR_H)) < 0.001, "the front wall is whole but for the doorway (%.3f m2)" % front_area)
	# the ceiling: plain, and snapped by the walls' own rule
	var wall := tiles.mesh.surface_get_material(0) as ShaderMaterial
	var ceil := tiles.mesh.surface_get_material(2) as ShaderMaterial
	check(ceil != null and ceil.get_shader_parameter("tile_mode") == null, "the ceiling is plain, no tile grid")
	check(ceil != null and wall != null and is_equal_approx(float(ceil.get_shader_parameter("snap_precision")), float(wall.get_shader_parameter("snap_precision"))), "the ceiling snaps on the walls' grid")
	var snap_lines := ["vec2 ndc = clip.xy / clip.w;", "float grid = max(snap_precision, 8.0);", "ndc = floor(ndc * grid + 0.5) / grid;", "clip.xy = ndc * clip.w;", "POSITION = clip;"]
	var kit_code := (load("res://addons/flesh_dig_kit/common/fdk_ps1_material.gdshader") as Shader).code
	var ceil_code := ceil.shader.code if ceil != null else ""
	for line in snap_lines:
		check(kit_code.contains(line) and ceil_code.contains(line), "walls and ceiling snap by the same line: %s" % line)
	var col: Color = ceil.get_shader_parameter("albedo") if ceil != null else Color.BLACK
	check(col.is_equal_approx(Color(0.92, 0.92, 0.90)), "the ceiling keeps its off-white")

func _test_vent_and_light(r: FPRestroom) -> void:
	var v: Vector3 = FPRestroom.VENT_CENTER
	check(is_equal_approx(v.x, FPRestroom.TOILET_X) and is_zero_approx(v.x), "vent on the door-toilet line (x %.2f)" % v.x)
	check(is_equal_approx(v.y, 2.0 * FPRestroom.HALF.y), "vent on the ceiling")
	var hole: Array = FPRestroom.VENT_HOLE
	check(is_equal_approx((hole[0] + hole[2]) * 0.5, v.x) and is_equal_approx((hole[1] + hole[3]) * 0.5, v.z), "ceiling hole centred on the vent")
	check(is_equal_approx(hole[2] - hole[0], 0.52) and is_equal_approx(hole[3] - hole[1], 0.52), "ceiling hole is the grate's 0.52 m square")
	check(m.vent.global_position.distance_to(v - Vector3(0, 0.03, 0)) < 0.001, "the vent being hangs at the vent centre")
	check(m.in_vent_duct(v + Vector3(0.2, 0.3, -0.2)) and not m.in_vent_duct(Vector3(-1.05, 2.9, -1.28)), "the duct follows the vent (none left at the old corner)")
	check(m._world_density(v + Vector3(0, 0.3, 0)) <= 0.0, "no flesh generated in the duct over the vent")
	# from the seat: straight ahead, and an offered hand (0.7 m down) inside a level gaze
	var eye: Vector3 = m.SEAT_POS + Vector3(0, 0.7, 0)
	var to_vent := v - eye
	check(absf(to_vent.x) < 0.01 and to_vent.z > 0.0, "from the seat the vent is straight ahead")
	var up := rad_to_deg(atan2(to_vent.y, Vector2(to_vent.x, to_vent.z).length()))
	check(up < 55.0, "from the seat the grille is %.0f degrees up (was 64 and 57 to the side)" % up)
	var hand := v - Vector3(0, 0.7, 0) - eye
	var hand_up := rad_to_deg(atan2(hand.y, Vector2(hand.x, hand.z).length()))
	check(hand_up < m.player.camera.fov * 0.5, "an offered hand is inside a level gaze from the seat (%.0f of %.1f degrees)" % [hand_up, m.player.camera.fov * 0.5])
	# from the door: under the top edge of a level gaze, the toilet below it
	var door_eye := Vector3(0, 1.65, FPRestroom.HALF.z - 0.2)
	var far_edge := Vector3(v.x, v.y, hole[1]) - door_eye
	check(rad_to_deg(atan2(far_edge.y, absf(far_edge.z))) < m.player.camera.fov * 0.5, "walking in, the grille reaches into the top of the view")
	# lamp and disks
	var lamp: OmniLight3D = r.get_node("RoomLight")
	check(is_zero_approx(lamp.position.x), "room lamp on the centre line")
	check(absf(lamp.position.z - v.z) > FPRestroom.VENT_HALF + 0.3, "room lamp clear of the open grille and the hand (%.2f m along the room)" % absf(lamp.position.z - v.z))
	check(is_equal_approx(lamp.light_energy, 0.3) and lamp.shadow_enabled and lamp.omni_range == 4.0, "room lamp keeps its energy, range and shadows")
	check(r.contains(lamp.position), "room lamp inside the room")
	var disks := r.find_children("*CeilingDownlight*", "MeshInstance3D", true, false)
	check(disks.size() == 2, "two ceiling light disks (%d)" % disks.size())
	var over_lamp := false
	var side_of_vent := 0
	for d in disks:
		var p: Vector3 = (d as Node3D).position
		check(is_zero_approx(p.x), "light disk on the centre line (z %.2f)" % p.z)
		check(absf(p.z - v.z) > FPRestroom.VENT_HALF + 0.11, "light disk clear of the grille (z %.2f)" % p.z)
		over_lamp = over_lamp or absf(p.z - lamp.position.z) < 0.01
		side_of_vent += 1 if p.z > v.z else -1
	check(over_lamp, "one disk sits over the real lamp")
	check(side_of_vent == 0, "one disk each side of the grille: disk, grille, disk")

func _test_toilet(r: FPRestroom) -> void:
	var body: MeshInstance3D = r.toilet.get_node("Body")
	var tris := tri_count(body)
	check(tris <= 260, "toilet body stays low-poly (%d triangles)" % tris)
	var bb := body.mesh.get_aabb()
	check(bb.size.x <= 0.45, "toilet body inside its collision width (%.2f)" % bb.size.x)
	check(bb.end.z >= 0.57 and bb.end.z <= 0.60, "bowl reaches 0.58 m out, longer than it is wide (%.2f)" % bb.end.z)
	check(is_equal_approx(bb.end.y, 0.47), "seat top stays 0.45 with only the hinges above it (%.2f)" % bb.end.y)
	# eight-sided, flat in front: the outermost front vertices form an edge, not a point
	var front := 0
	var lever := false
	for p in verts(body):
		if is_equal_approx(p.y, 0.45) and p.z > bb.end.z - 0.001:
			front += 1
		# the old extra lever box sat at x -0.2..-0.12, y 0.72..0.745
		lever = lever or p.y > 0.6
	check(front >= 2, "the bowl's front is a flat face")
	check(not lever, "no second lever on the body: the tank model carries the only one")
	check(r.tank_art != null and r.tank_art.position.is_equal_approx(Vector3(0, 0.42, 0.085)), "tank model stands where it did")
	check(r.bowl_center.is_equal_approx(r.toilet.transform * Vector3(0, 0.3, 0.3)), "bowl centre unchanged")
	check(FPRestroom.TOILET_BOX == Vector3(0.45, 0.8, 0.5) and is_equal_approx(m.SEAT_POS.y, 0.55), "toilet box and seat unchanged")

func _test_door(r: FPRestroom) -> void:
	var door: MeshInstance3D = r.door_pivot.get_node("Door")
	var bb := door.mesh.get_aabb()
	var w := 2.0 * FPRestroom.DOOR_HALF_W - 0.01
	check(bb.position.x >= 0.0 and bb.end.x <= w + 0.001 and bb.end.y <= FPRestroom.DOOR_H, "door leaf keeps its outline (%.2f x %.2f)" % [bb.size.x, bb.size.y])
	check(bb.position.z < -0.023 and bb.end.z > 0.023 and bb.size.z < 0.06, "rails stand proud on both faces (z %.3f..%.3f)" % [bb.position.z, bb.end.z])
	var handle: MeshInstance3D = r.door_pivot.get_node("Handle")
	var hb := handle.mesh.get_aabb()
	check(hb.position.z < -0.08 and hb.end.z > 0.08, "a lever handle on each face")
	check(hb.size.x > 0.1 and hb.end.x < w and hb.get_center().x < w - 0.075, "the levers reach toward the hinge")
	check(absf(hb.get_center().y - 1.0) < 0.01, "handles at 1.0 m")
	var casing: MeshInstance3D = r.get_node_or_null("DoorCasing")
	check(casing != null, "door casing exists")
	if casing != null:
		var cb := casing.mesh.get_aabb()
		check(cb.end.z <= FPRestroom.HALF.z + 0.001 and cb.position.z >= FPRestroom.HALF.z - 0.02, "casing lies on the room side of the door wall")
		check(is_equal_approx(cb.size.x, 2.0 * FPRestroom.DOOR_HALF_W + 0.12) and cb.position.y >= 0.0, "casing frames the doorway")
		var inside_opening := false
		for p in verts(casing):
			inside_opening = inside_opening or (absf(p.x) < FPRestroom.DOOR_HALF_W - 0.001 and p.y < FPRestroom.DOOR_H - 0.001)
		check(not inside_opening, "casing leaves the doorway clear (no threshold)")
	var shape := r.door_pivot.get_node("DoorBody").get_child(0) as CollisionShape3D
	check((shape.shape as BoxShape3D).size.is_equal_approx(Vector3(w, FPRestroom.DOOR_H, 0.04)), "door collision unchanged")
	check(r.door_pivot.position.is_equal_approx(Vector3(-FPRestroom.DOOR_HALF_W, 0, FPRestroom.HALF.z + 0.02)), "hinge unchanged")

func _test_tub(r: FPRestroom) -> void:
	var tub: MeshInstance3D = r.get_node("Bathtub")
	var bb := tub.mesh.get_aabb()
	var right := FPRestroom.HALF.x - 0.025
	check(is_equal_approx(bb.size.x, FPRestroom.BATH_LENGTH) and is_equal_approx(bb.end.x, right), "tub keeps its length and place")
	check(is_equal_approx(bb.size.y, 0.56) and is_equal_approx(bb.position.y, 0.0), "tub keeps its height")
	check(is_equal_approx(bb.position.z, -FPRestroom.HALF.z + 0.025) and is_equal_approx(bb.end.z, -FPRestroom.HALF.z + 0.86), "tub keeps its depth")
	check(tri_count(tub) <= 180, "tub stays low-poly (%d triangles)" % tri_count(tub))
	# a floor well below the rim, narrower than the opening (sloped walls)
	var floor_min := INF
	var floor_max := -INF
	for p in verts(tub):
		if is_equal_approx(p.y, 0.17):
			floor_min = minf(floor_min, p.x)
			floor_max = maxf(floor_max, p.x)
	var left := right - FPRestroom.BATH_LENGTH
	check(floor_min > left + 0.09 + 0.05 and floor_max < right - 0.09 - 0.2, "tub floor is narrower than its opening, with a long backrest slope")
	var fit: MeshInstance3D = r.get_node_or_null("BathFittings")
	check(fit != null, "tub drain and wall tap exist")
	if fit != null:
		var fb := fit.mesh.get_aabb()
		check(fb.position.z >= -FPRestroom.HALF.z - 0.001 and fb.end.x < right and fb.position.x > left, "tap hangs on the back wall over the tub")
		check(fb.end.y < 0.9, "tap stays low on the wall")

func _test_basin(r: FPRestroom) -> void:
	var art: Node3D = r.mirror_art
	var body: MeshInstance3D = art.get_node("Basin")
	var bowl: MeshInstance3D = art.get_node("BasinBowl")
	check(tri_count(body) + tri_count(bowl) <= 60, "basin under its triangle cap (%d)" % (tri_count(body) + tri_count(bowl)))
	# bowl and pedestal are two steps: wide down to 0.70, then folded in by 0.66
	var wide_at_mid := 0.0
	var wide_at_neck := 0.0
	for p in verts(body):
		if is_equal_approx(p.y, 0.70):
			wide_at_mid = maxf(wide_at_mid, absf(p.x))
		if is_equal_approx(p.y, 0.66):
			wide_at_neck = maxf(wide_at_neck, absf(p.x))
	check(wide_at_mid >= 0.26, "bowl body still wide 0.18 m under the rim (half %.2f)" % wide_at_mid)
	check(wide_at_neck > 0.0 and wide_at_neck <= 0.14, "bowl folds in to a neck over the half pedestal (half %.2f)" % wide_at_neck)

func _test_small_fixtures(r: FPRestroom) -> void:
	check(r.get_node_or_null("KoreanFixtures") == null, "the empty KoreanFixtures mesh is gone")
	for n in ["Shower", "FloorDrain", "PaperHolder"]:
		check(r.get_node_or_null(n) is MeshInstance3D, "%s exists" % n)
	var holder: MeshInstance3D = r.get_node("PaperHolder")
	var hb := holder.mesh.get_aabb()
	check(hb.position.y <= 0.571 and hb.end.x >= -0.001, "paper holder reaches the wall and a sheet hangs from the roll")
	var shower := world_aabb(r.get_node("Shower"))
	check(shower.position.x < -FPRestroom.HALF.x + 0.01 and shower.end.x < -FPRestroom.HALF.x + 0.25, "shower stays on the -X wall")
	for mi in r.find_children("*", "MeshInstance3D", true, false):
		var mat := (mi as MeshInstance3D).material_override
		if mi.name in ["Body", "Bathtub", "BathFittings", "Door", "Handle", "DoorCasing", "Shower", "PaperHolder", "FloorDrain"]:
			check(mat is ShaderMaterial, "%s wears the PS1 material" % mi.name)
			check((mi as MeshInstance3D).layers == FPRestroom.ROOM_VISUAL_LAYER, "%s is on the room-only render layer" % mi.name)

func _test_container() -> void:
	# the mantle stem rest lies with its long side along world X (decision 0016)
	var h: Vector3 = m.rest_halves[0]
	check(h.is_equal_approx(Vector3(2.2, 1.1, 1.1)), "the stem rest's box lies along X")
	var rest: Node3D = m.rest_cans[0].get_parent()
	var art: Node3D = rest.get_node("ContainerArt")
	check(art.scale.is_equal_approx(Vector3.ONE), "container model is not stretched")
	check(art.position.is_equal_approx(Vector3(0, -h.y, 0)), "container floor on the box floor")
	var shell: MeshInstance3D = art.get_node("Shell")
	var bb: AABB = art.transform * shell.mesh.get_aabb()
	check(absf(bb.size.x - 2.0 * h.x) < 0.25 and absf(bb.size.z - 2.0 * h.z) < 0.25, "container shell is the logic box's footprint (%.2f x %.2f)" % [bb.size.x, bb.size.z])
	check(bb.end.y > h.y and bb.end.y < h.y + 0.1 and bb.position.y > -h.y - 0.1, "container shell is the logic box's height")
	var seat: Vector3 = art.call("chair_point")
	check(is_equal_approx(seat.y, 0.44), "chair seat 0.44 m up (it was stretched to 0.71)")
	var can: Node3D = m.rest_cans[0]
	check(can.position.is_equal_approx(art.transform * seat + Vector3(0, 0.08, 0)), "the spray can stands on the chair seat")
	check(FPWorldFeatures.in_container(can.global_position, m.rest_points, m.rest_halves), "the can is inside the container")
	var bucket: Vector3 = art.transform * (art.call("drain_point") as Vector3)
	var judged: Vector3 = m.rest_buckets[0] - m.rest_points[0] - Vector3(0, 0.3, 0)
	check(m.rest_stand_point(0).distance_to(m.rest_points[0] + bucket + Vector3(0, 0.9, 0)) < 0.01, "the vomit spot is body height over the bucket")
	check(bucket.distance_to(judged) < 0.01, "bucket stands where Main judges 'at the bucket' (%s)" % str(bucket))
	# real-size props: nothing in the shell is taller than the box or a metre-wide seat
	var seat_w := 0.0
	var c: Vector3 = art.get("CHAIR_AT")
	for p in verts(shell):
		if absf(p.y - 0.44) < 0.001 and Vector2(p.x - c.x, p.z - c.z).length() < 0.4:
			seat_w = maxf(seat_w, Vector2(p.x - c.x, p.z - c.z).length())
	check(seat_w > 0.2 and seat_w < 0.3, "chair seat is 0.40 m square (corner %.2f m from its middle)" % seat_w)
	var lamp: OmniLight3D = null
	for n in art.get_children():
		if n is OmniLight3D:
			lamp = n
	check(lamp != null and (lamp.light_cull_mask & FPRestroom.ROOM_VISUAL_LAYER) == 0, "container lamp still leaves the restroom layer out")
