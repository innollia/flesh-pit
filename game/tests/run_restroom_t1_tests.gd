extends SceneTree

## Unit and regression tests for T1:
## - Bathtub length 1.7m (starts at HALF.x - 0.025 - 1.7 to HALF.x - 0.025)
## - Bathtub collision matches new size (1.7, 0.56, 0.86) and position (HALF.x - 0.875, 0.28, -HALF.z + 0.43)
## - Bathtub entry is completely blocked (no glitching inside or permanent float)
## - Open floor restored where old 4.45m bathtub was (left side of room)
## - Outer walls generated in 6 directions (DOWN, UP, FORWARD, LEFT, RIGHT, BACK) with doorway open
## - Outer walls on ROOM_VISUAL_LAYER

var _failures: int = 0
var _passed: int = 0
var _restroom: FPRestroom
var _to_free: Array = []

func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failures += 1
		print("FAIL: %s" % message)

func _track(n: Node) -> Node:
	_to_free.append(n)
	return n

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	print("=== flesh-pit restroom T1 regression tests ===")
	_restroom = _track(FPRestroom.new()) as FPRestroom
	_restroom.name = "Restroom"
	root.add_child(_restroom)

	_test_bathtub_visual_length()
	_test_bathtub_collision()
	_test_bathtub_entry_blocked_and_left_floor_open()
	_test_outer_walls_presence_and_directions()
	_test_doorway_not_blocked()
	_test_outer_walls_render_layer()

	for n in _to_free:
		if is_instance_valid(n):
			n.free()
	_to_free.clear()

	print("--- %d passed, %d failed ---" % [_passed, _failures])
	quit(1 if _failures > 0 else 0)

func _test_bathtub_visual_length() -> void:
	var bath: MeshInstance3D = _restroom.get_node_or_null("Bathtub") as MeshInstance3D
	_assert(bath != null, "bathtub: Bathtub MeshInstance3D exists")
	if bath == null or bath.mesh == null:
		return

	_assert(is_equal_approx(FPRestroom.BATH_LENGTH, 1.7), "bathtub: BATH_LENGTH constant is 1.7m")
	var aabb: AABB = bath.mesh.get_aabb()
	_assert(is_equal_approx(aabb.size.x, 1.7), "bathtub: visual mesh length X is 1.7m (got %.4f)" % aabb.size.x)
	var expected_right := FPRestroom.HALF.x - 0.025
	var expected_left := expected_right - FPRestroom.BATH_LENGTH
	_assert(is_equal_approx(aabb.position.x, expected_left), "bathtub: visual mesh left X is %.3f (got %.4f)" % [expected_left, aabb.position.x])
	_assert(is_equal_approx(aabb.end.x, expected_right), "bathtub: visual mesh right X is %.3f (got %.4f)" % [expected_right, aabb.end.x])
	_assert(is_equal_approx(aabb.size.y, 0.56), "bathtub: visual mesh height Y is 0.56m (got %.4f)" % aabb.size.y)

func _test_bathtub_collision() -> void:
	var room_body: StaticBody3D = _restroom.get_node_or_null("RoomBody") as StaticBody3D
	_assert(room_body != null, "collision: RoomBody exists")
	if room_body == null:
		return

	var bath_shape: BoxShape3D = null
	var bath_cs: CollisionShape3D = null
	var old_bath_found := false

	var expected_pos := Vector3(FPRestroom.HALF.x - 0.875, 0.28, -FPRestroom.HALF.z + 0.43)
	var expected_size := Vector3(1.7, 0.56, 0.86)

	for child in room_body.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			var bs: BoxShape3D = child.shape
			if is_equal_approx(bs.size.x, 2.0 * FPRestroom.HALF.x - 0.05):
				old_bath_found = true
			if is_equal_approx(bs.size.x, expected_size.x) and is_equal_approx(bs.size.y, expected_size.y) and is_equal_approx(bs.size.z, expected_size.z):
				bath_shape = bs
				bath_cs = child

	_assert(not old_bath_found, "collision: old 4.45m bathtub collider is removed")
	_assert(bath_shape != null, "collision: new 1.7m bathtub collider exists with size (1.7, 0.56, 0.86)")
	if bath_cs != null:
		_assert(bath_cs.position.is_equal_approx(expected_pos), "collision: bathtub collider position is %s (got %s)" % [expected_pos, bath_cs.position])

func _test_bathtub_entry_blocked_and_left_floor_open() -> void:
	var room_body: StaticBody3D = _restroom.get_node_or_null("RoomBody") as StaticBody3D
	if room_body == null:
		return

	# Point inside the bathtub volume
	var inside_bath := Vector3(FPRestroom.HALF.x - 0.875, 0.28, -FPRestroom.HALF.z + 0.43)
	# Point on the left where the old bathtub used to block
	var left_restored := Vector3(-FPRestroom.HALF.x + 0.5, 0.28, -FPRestroom.HALF.z + 0.43)

	var inside_hits := 0
	var left_hits := 0

	for child in room_body.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			var bs: BoxShape3D = child.shape
			var pos: Vector3 = child.position
			var half_size: Vector3 = bs.size * 0.5
			var box_min := pos - half_size
			var box_max := pos + half_size

			# Check if inside_bath is within this box
			if inside_bath.x >= box_min.x and inside_bath.x <= box_max.x and \
			   inside_bath.y >= box_min.y and inside_bath.y <= box_max.y and \
			   inside_bath.z >= box_min.z and inside_bath.z <= box_max.z:
				inside_hits += 1

			# Check if left_restored is within this box
			if left_restored.x >= box_min.x and left_restored.x <= box_max.x and \
			   left_restored.y >= box_min.y and left_restored.y <= box_max.y and \
			   left_restored.z >= box_min.z and left_restored.z <= box_max.z:
				left_hits += 1

	_assert(inside_hits > 0, "collision: bathtub volume is blocked by solid collision (hits=%d)" % inside_hits)
	_assert(left_hits == 0, "collision: left floor area at Y=0.28 is clear of bathtub collider (hits=%d)" % left_hits)

func _test_outer_walls_presence_and_directions() -> void:
	var outer: MeshInstance3D = _restroom.get_node_or_null("OuterWalls") as MeshInstance3D
	_assert(outer != null, "outer_walls: OuterWalls MeshInstance3D exists")
	if outer == null or outer.mesh == null:
		return

	var mesh: Mesh = outer.mesh
	var has_down := false
	var has_up := false
	var has_forward := false
	var has_left := false
	var has_right := false
	var has_back := false

	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for n in normals:
			if n.dot(Vector3.DOWN) > 0.9:
				has_down = true
			elif n.dot(Vector3.UP) > 0.9:
				has_up = true
			elif n.dot(Vector3.FORWARD) > 0.9:
				has_forward = true
			elif n.dot(Vector3.LEFT) > 0.9:
				has_left = true
			elif n.dot(Vector3.RIGHT) > 0.9:
				has_right = true
			elif n.dot(Vector3.BACK) > 0.9:
				has_back = true

	_assert(has_down, "outer_walls: has floor face facing DOWN")
	_assert(has_up, "outer_walls: has ceiling face facing UP")
	_assert(has_forward, "outer_walls: has back wall face facing FORWARD (-Z)")
	_assert(has_left, "outer_walls: has left wall face facing LEFT (-X)")
	_assert(has_right, "outer_walls: has right wall face facing RIGHT (+X)")
	_assert(has_back, "outer_walls: has front wall face facing BACK (+Z)")

func _test_doorway_not_blocked() -> void:
	var outer: MeshInstance3D = _restroom.get_node_or_null("OuterWalls") as MeshInstance3D
	if outer == null or outer.mesh == null:
		return

	# Check that no vertex in OuterWalls is inside the doorway opening
	# Doorway opening: X in (-DOOR_HALF_W, DOOR_HALF_W), Y in (0.01, DOOR_H - 0.01), Z near HALF.z
	var mesh: Mesh = outer.mesh
	var door_blocked := false
	var dw := FPRestroom.DOOR_HALF_W - 0.05
	var dh := FPRestroom.DOOR_H - 0.05

	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(verts.size()):
			var v := verts[i]
			var n := normals[i]
			if n.dot(Vector3.BACK) > 0.9 and absf(v.z - FPRestroom.HALF.z) < 0.05:
				# It is on the front wall
				if absf(v.x) < dw and v.y > 0.05 and v.y < dh:
					door_blocked = true

	_assert(not door_blocked, "outer_walls: doorway opening is not blocked by front outer wall")

func _test_outer_walls_render_layer() -> void:
	var outer: MeshInstance3D = _restroom.get_node_or_null("OuterWalls") as MeshInstance3D
	if outer == null:
		return
	_assert(outer.layers == FPRestroom.ROOM_VISUAL_LAYER, "outer_walls: sits on ROOM_VISUAL_LAYER (got %d vs %d)" % [outer.layers, FPRestroom.ROOM_VISUAL_LAYER])
