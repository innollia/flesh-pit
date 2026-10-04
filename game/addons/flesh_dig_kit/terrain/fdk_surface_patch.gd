class_name FDKSurfacePatch
extends MeshInstance3D

## Local surface-nets mesh builder covering the 27 cells touching 8 corners
## of a local excavation without regenerating or modifying terrain chunks.

var field: Node3D = null
var faces: PackedVector3Array = PackedVector3Array()
var read_corner_count: int = 0
var is_aggregate: bool = false
var tile_children: Dictionary = {}

func clear_tile_children() -> void:
	for child in tile_children.values():
		if is_instance_valid(child):
			if child.get_parent() == self:
				remove_child(child)
			child.queue_free()
	tile_children.clear()

func add_tile_child(origin: Vector3i, child: MeshInstance3D) -> void:
	is_aggregate = true
	mesh = null
	if tile_children.has(origin):
		var old = tile_children[origin]
		if old != child and is_instance_valid(old):
			if old.get_parent() == self:
				remove_child(old)
			old.queue_free()
	tile_children[origin] = child
	if child.get_parent() != self:
		add_child(child)

func _init(p_field: Node3D = null) -> void:
	field = p_field
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

static func _floordiv(a: int, b: int) -> int:
	return int(floor(float(a) / float(b)))

func build(center: Vector3i) -> void:
	build_region(center - Vector3i.ONE, center + Vector3i.ONE)

func build_tile(tile_origin: Vector3i) -> bool:
	return _build_region(tile_origin - Vector3i.ONE, tile_origin + Vector3i(3, 3, 3), true, tile_origin)

func build_region(min_cell: Vector3i, max_cell: Vector3i) -> bool:
	return _build_region(min_cell, max_cell)

func _build_region(min_cell: Vector3i, max_cell: Vector3i, tile_owned: bool = false, tile_origin: Vector3i = Vector3i.ZERO) -> bool:
	read_corner_count = 0
	faces = PackedVector3Array()
	mesh = null

	var span_x := max_cell.x - min_cell.x + 1
	var span_y := max_cell.y - min_cell.y + 1
	var span_z := max_cell.z - min_cell.z + 1

	if span_x < 1 or span_x > 7 or span_y < 1 or span_y > 7 or span_z < 1 or span_z > 7:
		return false

	if field == null:
		return false

	var s: int = field.config.chunk_size
	var cs: float = field.config.cell_size
	var iso: float = field.config.iso_level
	var facet_jitter: float = field.config.facet_jitter

	var nx := span_x + 1
	var ny := span_y + 1
	var nz := span_z + 1
	var slice_stride := nx * ny
	var total_corners := nx * ny * nz

	# Sample density for corners bounded by min_cell to max_cell + 1
	var min_corner := min_cell
	var d_grid := PackedFloat32Array()
	d_grid.resize(total_corners)
	var any_below_iso := false
	var any_above_iso := false

	for kz in range(nz):
		for ky in range(ny):
			for kx in range(nx):
				var gcorner := min_corner + Vector3i(kx, ky, kz)
				var density := 1.0
				if field.has_method("corner_density_global"):
					density = field.corner_density_global(gcorner)
				d_grid[kx + ky * nx + kz * slice_stride] = density
				read_corner_count += 1
				if density < iso:
					any_below_iso = true
				else:
					any_above_iso = true

	# Full mass or completely empty: early exit with empty mesh
	if not any_below_iso or not any_above_iso:
		return true

	# Compute vertex for each cell in the region
	var cell_vert: Dictionary = {}
	for cz in range(span_z):
		for cy in range(span_y):
			for cx in range(span_x):
				var gcell := min_cell + Vector3i(cx, cy, cz)

				var c000: float = d_grid[cx + cy * nx + cz * slice_stride]
				var c100: float = d_grid[(cx + 1) + cy * nx + cz * slice_stride]
				var c010: float = d_grid[cx + (cy + 1) * nx + cz * slice_stride]
				var c110: float = d_grid[(cx + 1) + (cy + 1) * nx + cz * slice_stride]
				var c001: float = d_grid[cx + cy * nx + (cz + 1) * slice_stride]
				var c101: float = d_grid[(cx + 1) + cy * nx + (cz + 1) * slice_stride]
				var c011: float = d_grid[cx + (cy + 1) * nx + (cz + 1) * slice_stride]
				var c111: float = d_grid[(cx + 1) + (cy + 1) * nx + (cz + 1) * slice_stride]

				var mask := 0
				if c000 >= iso: mask |= 1
				if c100 >= iso: mask |= 2
				if c010 >= iso: mask |= 4
				if c110 >= iso: mask |= 8
				if c001 >= iso: mask |= 16
				if c101 >= iso: mask |= 32
				if c011 >= iso: mask |= 64
				if c111 >= iso: mask |= 128
				if mask == 0 or mask == 255:
					continue

				var sum := Vector3.ZERO
				var cnt := 0
				var e := [
					[c000, c100, Vector3(0, 0, 0), Vector3(1, 0, 0)],
					[c010, c110, Vector3(0, 1, 0), Vector3(1, 1, 0)],
					[c001, c101, Vector3(0, 0, 1), Vector3(1, 0, 1)],
					[c011, c111, Vector3(0, 1, 1), Vector3(1, 1, 1)],
					[c000, c010, Vector3(0, 0, 0), Vector3(0, 1, 0)],
					[c100, c110, Vector3(1, 0, 0), Vector3(1, 1, 0)],
					[c001, c011, Vector3(0, 0, 1), Vector3(0, 1, 1)],
					[c101, c111, Vector3(1, 0, 1), Vector3(1, 1, 1)],
					[c000, c001, Vector3(0, 0, 0), Vector3(0, 0, 1)],
					[c100, c101, Vector3(1, 0, 0), Vector3(1, 0, 1)],
					[c010, c011, Vector3(0, 1, 0), Vector3(0, 1, 1)],
					[c110, c111, Vector3(1, 1, 0), Vector3(1, 1, 1)],
				]
				for ed in e:
					var a: float = ed[0]
					var b: float = ed[1]
					if (a >= iso) != (b >= iso):
						var t := clampf((iso - a) / (b - a), 0.0, 1.0)
						sum += (ed[2] as Vector3).lerp(ed[3] as Vector3, t)
						cnt += 1
				var local := sum / float(cnt)
				var gx := gcell.x
				var gy := gcell.y
				var gz := gcell.z
				var jitter := Vector3(
					FDKLowPoly.hash3(gx, gy, gz) - 0.5,
					FDKLowPoly.hash3(gy, gz, gx) - 0.5,
					FDKLowPoly.hash3(gz, gx, gy) - 0.5) * 2.0 * facet_jitter
				var clearance := minf(minf(local.x, minf(local.y, local.z)), minf(1.0 - local.x, minf(1.0 - local.y, 1.0 - local.z)))
				var limit := maxf(0.0, clearance * 0.9)
				if jitter.length() > limit:
					jitter = jitter.limit_length(limit)
				local += jitter
				var vertex := (Vector3(gx, gy, gz) + local) * cs
				if field != null and field.surface_constraint.is_valid():
					vertex = field.surface_constraint.call(vertex)
				cell_vert[gcell] = vertex

	if cell_vert.is_empty():
		return true

	var n_tissues := FDKChunk.TISSUE_TEXTURES.size()
	var verts: Array = []
	var normals: Array = []
	var uvs: Array = []
	for i in range(n_tissues):
		verts.append(PackedVector3Array())
		normals.append(PackedVector3Array())
		uvs.append(PackedVector2Array())
	var all_verts := PackedVector3Array()

	# Emit quads along the internal axis edges
	# Iterate over corners in the region block
	for kz in range(nz):
		for ky in range(ny):
			for kx in range(nx):
				var K := min_corner + Vector3i(kx, ky, kz)
				if tile_owned and (K.x < tile_origin.x or K.x > tile_origin.x + 3 or K.y < tile_origin.y or K.y > tile_origin.y + 3 or K.z < tile_origin.z or K.z > tile_origin.z + 3):
					continue
				var i0 := kx + ky * nx + kz * slice_stride
				var a0 := d_grid[i0] >= iso

				# X-edge
				if kx < span_x:
					var a1 := d_grid[(kx + 1) + ky * nx + kz * slice_stride] >= iso
					if a0 != a1:
						var c0 := K + Vector3i(0, -1, -1)
						var c1 := K + Vector3i(0, 0, -1)
						var c2 := K + Vector3i(0, 0, 0)
						var c3 := K + Vector3i(0, -1, 0)
						if cell_vert.has(c0) and cell_vert.has(c1) and cell_vert.has(c2) and cell_vert.has(c3):
							var outward := Vector3(1, 0, 0) * (1.0 if a0 else -1.0)
							var solid_k := K if a0 else K + Vector3i(1, 0, 0)
							var tissue := _get_tissue(K, solid_k, outward, s)
							_emit_quad(verts, normals, uvs, all_verts, cell_vert, c0, c1, c2, c3, outward, tissue)

				# Y-edge
				if ky < span_y:
					var a1 := d_grid[kx + (ky + 1) * nx + kz * slice_stride] >= iso
					if a0 != a1:
						var c0 := K + Vector3i(-1, 0, -1)
						var c1 := K + Vector3i(0, 0, -1)
						var c2 := K + Vector3i(0, 0, 0)
						var c3 := K + Vector3i(-1, 0, 0)
						if cell_vert.has(c0) and cell_vert.has(c1) and cell_vert.has(c2) and cell_vert.has(c3):
							var outward := Vector3(0, 1, 0) * (1.0 if a0 else -1.0)
							var solid_k := K if a0 else K + Vector3i(0, 1, 0)
							var tissue := _get_tissue(K, solid_k, outward, s)
							_emit_quad(verts, normals, uvs, all_verts, cell_vert, c0, c1, c2, c3, outward, tissue)

				# Z-edge
				if kz < span_z:
					var a1 := d_grid[kx + ky * nx + (kz + 1) * slice_stride] >= iso
					if a0 != a1:
						var c0 := K + Vector3i(-1, -1, 0)
						var c1 := K + Vector3i(0, -1, 0)
						var c2 := K + Vector3i(0, 0, 0)
						var c3 := K + Vector3i(-1, 0, 0)
						if cell_vert.has(c0) and cell_vert.has(c1) and cell_vert.has(c2) and cell_vert.has(c3):
							var outward := Vector3(0, 0, 1) * (1.0 if a0 else -1.0)
							var solid_k := K if a0 else K + Vector3i(0, 0, 1)
							var tissue := _get_tissue(K, solid_k, outward, s)
							_emit_quad(verts, normals, uvs, all_verts, cell_vert, c0, c1, c2, c3, outward, tissue)

	var mesh_obj := ArrayMesh.new()
	var have_any := false
	for i in range(n_tissues):
		if verts[i].size() == 0:
			continue
		have_any = true
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts[i]
		arrays[Mesh.ARRAY_NORMAL] = normals[i]
		arrays[Mesh.ARRAY_TEX_UV] = uvs[i]
		mesh_obj.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh_obj.surface_set_material(mesh_obj.get_surface_count() - 1, FDKChunk.terrain_material(i))

	mesh = mesh_obj if have_any else null
	faces = all_verts
	return true

func _get_tissue(edge_k: Vector3i, solid_k: Vector3i, outward: Vector3, s: int) -> int:
	var cc := Vector3i(_floordiv(edge_k.x, s), _floordiv(edge_k.y, s), _floordiv(edge_k.z, s))
	var chunk: FDKChunk = field.get_chunk(cc) if field != null and field.has_method("get_chunk") else null
	var local_k := solid_k - cc * s
	var lx := clampi(local_k.x, 0, s - 1)
	var ly := clampi(local_k.y, 0, s - 1)
	var lz := clampi(local_k.z, 0, s - 1)

	var tissue := 0
	if chunk != null:
		tissue = chunk.get_tissue_at_cell(lx, ly, lz)
		if chunk._any_sealed:
			var ex := clampi(local_k.x + int(round(outward.x)), 0, s - 1)
			var ey := clampi(local_k.y + int(round(outward.y)), 0, s - 1)
			var ez := clampi(local_k.z + int(round(outward.z)), 0, s - 1)
			if chunk.is_sealed_at_cell(ex, ey, ez):
				tissue = FDKTissueRules.MELTED
	elif field != null and field.tissue_sampler.is_valid():
		var cell_world: Vector3 = (Vector3(cc * s + Vector3i(lx, ly, lz)) + Vector3.ONE * 0.5) * float(field.config.cell_size)
		tissue = int(field.tissue_sampler.call(cell_world))
	return tissue

func _emit_quad(verts: Array, normals: Array, uvs: Array, all_verts: PackedVector3Array,
		cell_vert: Dictionary, c0: Vector3i, c1: Vector3i, c2: Vector3i, c3: Vector3i,
		outward: Vector3, tissue: int) -> void:
	var v0: Vector3 = cell_vert[c0]
	var v1: Vector3 = cell_vert[c1]
	var v2: Vector3 = cell_vert[c2]
	var v3: Vector3 = cell_vert[c3]

	var ax := absf(outward.x)
	var ay := absf(outward.y)
	var az := absf(outward.z)
	var uv0: Vector2
	var uv1: Vector2
	var uv2: Vector2
	var uv3: Vector2
	if ax >= ay and ax >= az:
		uv0 = Vector2(v0.z, v0.y)
		uv1 = Vector2(v1.z, v1.y)
		uv2 = Vector2(v2.z, v2.y)
		uv3 = Vector2(v3.z, v3.y)
	elif ay >= ax and ay >= az:
		uv0 = Vector2(v0.x, v0.z)
		uv1 = Vector2(v1.x, v1.z)
		uv2 = Vector2(v2.x, v2.z)
		uv3 = Vector2(v3.x, v3.z)
	else:
		uv0 = Vector2(v0.x, v0.y)
		uv1 = Vector2(v1.x, v1.y)
		uv2 = Vector2(v2.x, v2.y)
		uv3 = Vector2(v3.x, v3.y)

	var grid_normal := Vector3(c1 - c0).cross(Vector3(c2 - c0))
	if grid_normal.dot(outward) > 0.0:
		var quality := minf(-(v2 - v0).cross(v1 - v0).dot(outward), -(v3 - v0).cross(v2 - v0).dot(outward))
		var alternate := minf(-(v3 - v0).cross(v1 - v0).dot(outward), -(v3 - v1).cross(v2 - v1).dot(outward))
		if quality < 0 and alternate > quality:
			_tri(verts[tissue], normals[tissue], uvs[tissue], all_verts, v0, v3, v1, uv0, uv3, uv1, outward)
			_tri(verts[tissue], normals[tissue], uvs[tissue], all_verts, v1, v3, v2, uv1, uv3, uv2, outward)
		else:
			_tri(verts[tissue], normals[tissue], uvs[tissue], all_verts, v0, v2, v1, uv0, uv2, uv1, outward)
			_tri(verts[tissue], normals[tissue], uvs[tissue], all_verts, v0, v3, v2, uv0, uv3, uv2, outward)
	else:
		var quality := minf(-(v1 - v0).cross(v2 - v0).dot(outward), -(v2 - v0).cross(v3 - v0).dot(outward))
		var alternate := minf(-(v1 - v0).cross(v3 - v0).dot(outward), -(v2 - v1).cross(v3 - v1).dot(outward))
		if quality < 0 and alternate > quality:
			_tri(verts[tissue], normals[tissue], uvs[tissue], all_verts, v0, v1, v3, uv0, uv1, uv3, outward)
			_tri(verts[tissue], normals[tissue], uvs[tissue], all_verts, v1, v2, v3, uv1, uv2, uv3, outward)
		else:
			_tri(verts[tissue], normals[tissue], uvs[tissue], all_verts, v0, v1, v2, uv0, uv1, uv2, outward)
			_tri(verts[tissue], normals[tissue], uvs[tissue], all_verts, v0, v2, v3, uv0, uv2, uv3, outward)

func _tri(t_verts: PackedVector3Array, t_normals: PackedVector3Array, t_uvs: PackedVector2Array,
		all_v: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3,
		uva: Vector2, uvb: Vector2, uvc: Vector2, _outward: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	var nn := -n.normalized()
	var la := to_local(a) if is_inside_tree() else (a - position)
	var lb := to_local(b) if is_inside_tree() else (b - position)
	var lc := to_local(c) if is_inside_tree() else (c - position)
	t_verts.append(la); t_verts.append(lb); t_verts.append(lc)
	all_v.append(a); all_v.append(b); all_v.append(c)
	t_normals.append(nn); t_normals.append(nn); t_normals.append(nn)
	t_uvs.append(uva); t_uvs.append(uvb); t_uvs.append(uvc)

func contact_ray(from: Vector3, to: Vector3) -> Dictionary:
	var offset := to - from
	var length := offset.length()
	if length < 0.00001:
		return {}
	var direction := offset / length
	var best := INF
	var result := {}
	for i in range(0, faces.size(), 3):
		var p0: Vector3 = faces[i]
		var p1: Vector3 = faces[i + 1]
		var p2: Vector3 = faces[i + 2]
		var point = Geometry3D.ray_intersects_triangle(from, direction, p0, p1, p2)
		if point == null:
			continue
		var distance: float = (point - from).dot(direction)
		if distance < 0.0001 or distance > length or distance >= best:
			continue
		var outward := -(p1 - p0).cross(p2 - p0).normalized()
		var normal := outward
		if normal.dot(direction) > 0:
			normal = -normal
		var body: StaticBody3D = null
		var rid: RID = RID()
		var collider_id: int = 0
		if field != null and field.has_method("world_to_cell"):
			var sample_pt: Vector3 = point - outward * (field.config.cell_size * 0.1)
			var cell_info: Array = field.world_to_cell(sample_pt)
			var chunk = field.get_chunk(cell_info[0])
			if chunk == null:
				var direct_info: Array = field.world_to_cell(point)
				chunk = field.get_chunk(direct_info[0])
			if chunk == null:
				for dz in range(-1, 2):
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							var nearby = field.get_chunk(cell_info[0] + Vector3i(dx, dy, dz))
							if chunk == null and nearby != null:
								chunk = nearby
			if chunk != null:
				body = chunk.get_body()
				rid = body.get_rid()
				collider_id = body.get_instance_id()
		if body == null:
			continue
		best = distance
		result = {
			"position": point,
			"normal": normal,
			"collider": body,
			"collider_id": collider_id,
			"rid": rid,
			"shape": -1,
			"face_index": i / 3,
			"fdk_surface_patch": true,
			"fdk_patch_outward": outward
		}
	return result
