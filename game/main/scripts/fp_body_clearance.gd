class_name FPBodyClearance
extends RefCounted

## Game-side crush clearance. Query the real current capsule, normal physics
## motion and the current surface-net triangles. Never modify terrain, create
## colliders, grow the body protection radius or relocate the player.
const SURFACE := preload("res://addons/flesh_dig_kit/terrain/fdk_surface_patch.gd")
const CONTACT_SKIN := 0.002
const AXES := [Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.DOWN, Vector3.UP]
var _signature: Array = []
var _faces := PackedVector3Array()
var _face_low := PackedVector3Array()
var _face_high := PackedVector3Array()
var _corners: Dictionary = {}
var _last_direction := Vector3.ZERO
var last_direction_queries := 0
var last_corner_reads := 0
var surface_rebuilds := 0
var surface_cache_hits := 0
var last_assess_us := 0
var last_motion_us := 0
var last_motion_corner_reads := 0
var _iso := 0.5
var _cell_size := 0.5

func assess(body: CharacterBody3D, field: FDKTerrainField, preferred: Vector3 = Vector3.ZERO) -> Dictionary:
	var started := Time.get_ticks_usec()
	last_direction_queries = 0
	last_corner_reads = 0
	var node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if node == null or not node.shape is CapsuleShape3D or not body.is_inside_tree():
		return {"trapped": false, "overlap": false, "motion": Vector3.ZERO, "reason": "no_current_capsule"}
	var shape := node.shape as CapsuleShape3D
	var xf := node.global_transform
	var radius := shape.radius * maxf(xf.basis.x.length(), xf.basis.z.length())
	var half_axis := maxf(0.0, shape.height * xf.basis.y.length() * 0.5 - radius)
	var up := xf.basis.y.normalized()
	var a := xf.origin - up * half_axis
	var b := xf.origin + up * half_axis
	var distance := maxf(radius, 0.18)
	var skin_radius := maxf(0.001, radius - CONTACT_SKIN)
	# A compact local density snapshot is reread every assessment. This also
	# catches regen/contraction, which do not necessarily advance dig_epoch.
	# Only unchanged values reuse triangles, never a cached escape verdict.
	_prepare_surface(field, a.min(b) - Vector3.ONE * (radius + distance), a.max(b) + Vector3.ONE * (radius + distance))
	var overlaps := _point_in_solid(xf.origin) or _touches_surface(a, b, skin_radius)
	var query_shape := shape.duplicate() as CapsuleShape3D
	query_shape.radius = maxf(0.001, shape.radius - CONTACT_SKIN)
	query_shape.height = maxf(query_shape.radius * 2.0, shape.height - CONTACT_SKIN * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = query_shape
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	query.margin = 0.0
	var directions: Array[Vector3] = []
	for first in [preferred, _last_direction]:
		if first.length_squared() > 0.001:
			var direction: Vector3 = first.normalized()
			if not directions.has(direction): directions.append(direction)
	for direction in AXES:
		if not directions.has(direction): directions.append(direction)
	# Axes normally exit early; diagonal searches are a bounded fallback.
	for x in [-1, 1]:
		for z in [-1, 1]:
			directions.append(Vector3(x, 0, z).normalized())
	for y in [-1, 1]:
		for horizontal in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			directions.append((horizontal + Vector3.UP * y).normalized())
	for direction in directions:
		last_direction_queries += 1
		# A nearer wall may bound a pocket that fully fits the capsule after
		# a short retreat. Each endpoint must clear the entire intrusion and
		# its continuous sweep; shortening is never a point-based escape.
		var lengths: Array[float] = [distance, distance * 0.5, distance * 0.25, distance * 0.125]
		for length in lengths:
			var motion: Vector3 = direction * length
			if _point_in_solid(xf.origin + motion): continue
			query.transform = Transform3D(xf.basis, xf.origin + motion)
			if not body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): continue
			if _touches_surface(a + motion, b + motion, skin_radius): continue
			# The actual (unshrunk) capsule must also pass normal body motion.
			if body.test_move(body.global_transform, motion, null, body.safe_margin, false): continue
			if not _sweep_clear(a, b, motion, skin_radius): continue
			_last_direction = direction
			last_assess_us = Time.get_ticks_usec() - started
			return {"trapped": false, "overlap": overlaps, "motion": motion, "reason": "capsule_path", "queries": last_direction_queries}
	_last_direction = Vector3.ZERO
	last_assess_us = Time.get_ticks_usec() - started
	return {"trapped": true, "overlap": overlaps, "motion": Vector3.ZERO, "reason": "no_capsule_path", "queries": last_direction_queries}

## Normal movement uses the same actual capsule and current triangles as crush.
## Surface-only physics has no collider inside a fully solid mass. Reject that
## interior displacement before ordinary physics, while preserving axis sliding.
## Already intruding bodies can still leave via assess()/relieve()'s verified
## complete escape sweep; a short endpoint inside flesh is not an escape.
func constrain_motion(body: CharacterBody3D, field: FDKTerrainField, motion: Vector3) -> Vector3:
	if motion.is_zero_approx(): return motion
	var started := Time.get_ticks_usec()
	last_corner_reads = 0
	var node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if node == null or not node.shape is CapsuleShape3D: return motion
	var shape := node.shape as CapsuleShape3D
	var xf := node.global_transform
	var radius := shape.radius * maxf(xf.basis.x.length(), xf.basis.z.length())
	var half_axis := maxf(0.0, shape.height * xf.basis.y.length() * 0.5 - radius)
	var up := xf.basis.y.normalized()
	var a := xf.origin - up * half_axis
	var b := xf.origin + up * half_axis
	var skin_radius := maxf(0.001, radius - CONTACT_SKIN)
	_prepare_surface(field, a.min(b).min(a + motion).min(b + motion) - Vector3.ONE * radius,
		a.max(b).max(a + motion).max(b + motion) + Vector3.ONE * radius)
	var allowed := Vector3.ZERO
	for axis in [Vector3(0, motion.y, 0), Vector3(motion.x, 0, 0), Vector3(0, 0, motion.z)]:
		if axis.is_zero_approx(): continue
		if _motion_clear(xf.origin, a, b, allowed, axis, skin_radius):
			allowed += axis
			continue
		# Keep normal physics contact instead of hovering one whole tick above
		# a surface. The skin leaves room for the actual collider safe margin.
		# A fully boxed starting centre has no legal partial displacement.
		if _point_in_solid(xf.origin + allowed): continue
		var low := 0.0
		var high := 1.0
		for step in range(7):
			var fraction := (low + high) * 0.5
			if _motion_clear(xf.origin, a, b, allowed, axis * fraction, skin_radius):
				low = fraction
			else:
				high = fraction
		allowed += axis * low
	# Axis candidates above may describe an L-shaped route. move_and_slide()
	# receives one combined velocity, so validate its actual straight sweep.
	# Otherwise return only a directly verified axis from the same origin.
	if not _motion_clear(xf.origin, a, b, Vector3.ZERO, allowed, skin_radius):
		var slide := Vector3.ZERO
		for axis in [Vector3(allowed.x,0,0), Vector3(0,allowed.y,0), Vector3(0,0,allowed.z)]:
			if axis.length_squared() <= slide.length_squared(): continue
			if _motion_clear(xf.origin, a, b, Vector3.ZERO, axis, skin_radius): slide = axis
		allowed = slide
	last_motion_us = Time.get_ticks_usec() - started
	last_motion_corner_reads = last_corner_reads
	return allowed

func _motion_clear(origin: Vector3, a: Vector3, b: Vector3, offset: Vector3, motion: Vector3, radius: float) -> bool:
	var next := offset + motion
	return not _point_in_solid(origin + next) and not _touches_surface(a + next, b + next, radius) and _sweep_clear(a + offset, b + offset, motion, radius)

## Optional gentle relief when real flesh has already intruded. The caller
## supplies a fresh assessment and performs this in the normal physics loop.
## move_and_collide keeps architecture and published terrain collisions live.
func relieve(body: CharacterBody3D, assessment: Dictionary, delta: float) -> Vector3:
	if assessment.get("trapped", true) or not assessment.get("overlap", false): return Vector3.ZERO
	var motion: Vector3 = assessment.get("motion", Vector3.ZERO)
	if motion.is_zero_approx() or delta <= 0.0: return Vector3.ZERO
	var before := body.global_position
	body.move_and_collide(motion.limit_length(minf(0.5 * delta, motion.length())))
	return body.global_position - before

func _prepare_surface(field: FDKTerrainField, lo: Vector3, hi: Vector3) -> void:
	_cell_size = field.config.cell_size
	_iso = field.config.iso_level
	var first := Vector3i((lo / _cell_size).floor()) - Vector3i.ONE
	var last := Vector3i((hi / _cell_size).floor()) + Vector3i.ONE
	var next: Array = [field.get_instance_id(), first, last, _cell_size, _iso, field.config.facet_jitter, field.surface_constraint]
	_corners.clear()
	for z in range(first.z, last.z + 2):
		for y in range(first.y, last.y + 2):
			for x in range(first.x, last.x + 2):
				var corner := Vector3i(x, y, z)
				var value := field.corner_density_global(corner)
				_corners[corner] = value
				next.append(value)
				last_corner_reads += 1
	if next == _signature:
		surface_cache_hits += 1
		return
	_signature = next
	_faces = PackedVector3Array()
	_face_low = PackedVector3Array()
	_face_high = PackedVector3Array()
	# The existing bounded builder emits the same real surface-net triangles
	# as the terrain/temporary patches, including constraints and jitter.
	# Overlap two cells so split blocks also cover triangles at block borders.
	for z in range(first.z, last.z + 1, 5):
		for y in range(first.y, last.y + 1, 5):
			for x in range(first.x, last.x + 1, 5):
				var start := Vector3i(x, y, z)
				var patch := SURFACE.new(field)
				patch.build_region(start, start + Vector3i(6, 6, 6).min(last - start))
				_faces.append_array(patch.faces)
				patch.free()
	for i in range(0, _faces.size(), 3):
		_face_low.append(_faces[i].min(_faces[i+1]).min(_faces[i+2]))
		_face_high.append(_faces[i].max(_faces[i+1]).max(_faces[i+2]))
	surface_rebuilds += 1

func _point_in_solid(p: Vector3) -> bool:
	var cell := Vector3i((p / _cell_size).floor())
	var low := INF
	var high := -INF
	for z in range(2):
		for y in range(2):
			for x in range(2):
				var value: float = _corners.get(cell + Vector3i(x, y, z), 1.0)
				low = minf(low, value)
				high = maxf(high, value)
	if low >= _iso: return true
	if high < _iso: return false
	# Mixed cells use an actual oriented surface crossing, not max-of-eight
	# density or a trilinear approximation to the surface-net triangles.
	var target := Vector3.ZERO
	var closest := INF
	for i in range(0, _faces.size(), 3):
		var centroid := (_faces[i] + _faces[i + 1] + _faces[i + 2]) / 3.0
		var distance := p.distance_squared_to(centroid)
		if distance < closest:
			closest = distance
			target = centroid
	if closest == INF: return false
	var direction := (target - p).normalized()
	var first_distance := INF
	var outward := Vector3.ZERO
	for i in range(0, _faces.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(p, direction, _faces[i], _faces[i + 1], _faces[i + 2])
		if hit == null: continue
		var distance: float = (hit - p).dot(direction)
		if distance <= 0.000001 or distance >= first_distance: continue
		first_distance = distance
		outward = -(_faces[i + 1] - _faces[i]).cross(_faces[i + 2] - _faces[i]).normalized()
	return first_distance < INF and outward.dot(direction) > 0.000001

func _touches_surface(a: Vector3, b: Vector3, radius: float) -> bool:
	var lo := a.min(b) - Vector3.ONE * radius
	var hi := a.max(b) + Vector3.ONE * radius
	for i in range(0, _faces.size(), 3):
		var f_lo := _face_low[i / 3]
		var f_hi := _face_high[i / 3]
		if f_lo.x > hi.x or f_hi.x < lo.x or f_lo.y > hi.y or f_hi.y < lo.y or f_lo.z > hi.z or f_hi.z < lo.z: continue
		var u := _faces[i]
		var v := _faces[i + 1]
		var w := _faces[i + 2]
		if _segment_triangle_distance_squared(a, b, u, v, w) < radius * radius: return true
	return false

func _sweep_clear(a: Vector3, b: Vector3, motion: Vector3, radius: float) -> bool:
	var lo := a.min(b).min(a + motion).min(b + motion) - Vector3.ONE * radius
	var hi := a.max(b).max(a + motion).max(b + motion) + Vector3.ONE * radius
	for i in range(0, _faces.size(), 3):
		var u := _faces[i]
		var v := _faces[i + 1]
		var w := _faces[i + 2]
		var f_lo := _face_low[i / 3]
		var f_hi := _face_high[i / 3]
		if f_lo.x > hi.x or f_hi.x < lo.x or f_lo.y > hi.y or f_hi.y < lo.y or f_lo.z > hi.z or f_hi.z < lo.z: continue
		if _segment_triangle_distance_squared(a, b, u, v, w) < radius * radius:
			# An existing intrusion may only be left toward its real empty side.
			var outward := -(v - u).cross(w - u).normalized()
			if outward.dot(motion) <= 0.000001: return false
			continue
		# Sweeping the capsule's axis creates a parallelogram, whose exact
		# triangle distance plus radius describes the continuous swept volume.
		# For axial movement that parallelogram is a single extended segment.
		var distance := INF
		if (b - a).cross(motion).length_squared() < 0.0000001:
			var axis := (b - a).normalized() if a != b else motion.normalized()
			var points: Array[Vector3] = [a, b, a + motion, b + motion]
			var first := points[0]
			var last := points[0]
			for point in points:
				if point.dot(axis) < first.dot(axis): first = point
				if point.dot(axis) > last.dot(axis): last = point
			distance = _segment_triangle_distance_squared(first, last, u, v, w)
		else:
			distance = minf(_triangle_distance_squared(a, b, b + motion, u, v, w), _triangle_distance_squared(a, b + motion, a + motion, u, v, w))
		if distance < radius * radius: return false
	return true

static func _triangle_distance_squared(a: Vector3, b: Vector3, c: Vector3, u: Vector3, v: Vector3, w: Vector3) -> float:
	var result := INF
	for edge in [[a, b], [b, c], [c, a]]:
		result = minf(result, _segment_triangle_distance_squared(edge[0], edge[1], u, v, w))
	for edge in [[u, v], [v, w], [w, u]]:
		result = minf(result, _segment_triangle_distance_squared(edge[0], edge[1], a, b, c))
	return result

static func _segment_triangle_distance_squared(a: Vector3, b: Vector3, u: Vector3, v: Vector3, w: Vector3) -> float:
	if Geometry3D.segment_intersects_triangle(a, b, u, v, w) != null: return 0.0
	var result := minf(a.distance_squared_to(_closest_triangle(a, u, v, w)), b.distance_squared_to(_closest_triangle(b, u, v, w)))
	for edge in [[u, v], [v, w], [w, u]]:
		var points := Geometry3D.get_closest_points_between_segments(a, b, edge[0], edge[1])
		result = minf(result, points[0].distance_squared_to(points[1]))
	return result

static func _closest_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0: return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3: return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0: return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6: return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0: return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0: return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var inverse := 1.0 / (va + vb + vc)
	return a + ab * (vb * inverse) + ac * (vc * inverse)
