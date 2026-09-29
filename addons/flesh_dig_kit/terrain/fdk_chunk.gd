class_name FDKChunk
extends Node3D

## One cubic chunk of the density-grid terrain field. Owns its own density
## array, tissue-type array, mesh, and collision. Meshing uses naive surface
## nets: one quad per solid/empty cell boundary, with per-face flat normals
## and NO shared vertices between faces, which is what gives the low-poly
## faceted look the kit calls for.
##
## Density convention: 1.0 = fully solid tissue, 0.0 = fully carved out /
## empty. A cell is "solid" for meshing purposes when density >= iso_level.

signal remeshed(elapsed_ms: float)

## Grid coordinate of this chunk within the parent FDKTerrainField, in chunk units.
var chunk_coord: Vector3i = Vector3i.ZERO

var config: FDKTerrainConfig

## Flat array, size (chunk_size+1)^3, sampled at cell corners so neighbor
## chunks can share an exact boundary. Index via _corner_index().
var _density: PackedFloat32Array = PackedFloat32Array()

## Tissue type id per cell (chunk_size^3), used only for vertex coloring.
## 0 = flesh (red), 1 = nerve (yellow). Extend as new tissue types are added.
var _tissue: PackedByteArray = PackedByteArray()

## Original density at each corner, captured at chunk creation, used to
## regenerate carved cells back toward their starting value.
var _original_density: PackedFloat32Array = PackedFloat32Array()

var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D
var _static_body: StaticBody3D
var _dirty: bool = false

const TISSUE_COLORS: Array[Color] = [
	Color(0.72, 0.10, 0.14), # flesh
	Color(0.85, 0.78, 0.15), # nerve
]

func setup(p_chunk_coord: Vector3i, p_config: FDKTerrainConfig) -> void:
	chunk_coord = p_chunk_coord
	config = p_config
	var n := config.chunk_size + 1
	_density = PackedFloat32Array()
	_density.resize(n * n * n)
	_original_density = PackedFloat32Array()
	_original_density.resize(n * n * n)
	_tissue = PackedByteArray()
	_tissue.resize(config.chunk_size * config.chunk_size * config.chunk_size)

	_static_body = StaticBody3D.new()
	_static_body.name = "Body"
	add_child(_static_body)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Mesh"
	_static_body.add_child(_mesh_instance)

	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	_static_body.add_child(_collision)

func _corner_index(x: int, y: int, z: int) -> int:
	var n := config.chunk_size + 1
	return x + y * n + z * n * n

func _cell_index(x: int, y: int, z: int) -> int:
	var s := config.chunk_size
	return x + y * s + z * s * s

## Fill every corner with the given density and every cell with the given
## tissue id. Intended for initial world generation (e.g. a solid flesh wall,
## or an empty spherical room). Callers pass a lambda-like sampler via
## fill_from_callable instead when a spatially varying fill is needed.
func fill_uniform(density: float, tissue_id: int) -> void:
	for i in range(_density.size()):
		_density[i] = density
		_original_density[i] = density
	for i in range(_tissue.size()):
		_tissue[i] = tissue_id
	_dirty = true

## sampler_density: Callable(Vector3) -> float, world position -> density.
## sampler_tissue: Callable(Vector3) -> int, world position -> tissue id.
func fill_from_callable(sampler_density: Callable, sampler_tissue: Callable) -> void:
	var n := config.chunk_size + 1
	var origin := Vector3(chunk_coord) * config.chunk_size * config.cell_size
	for z in range(n):
		for y in range(n):
			for x in range(n):
				var world_pos: Vector3 = origin + Vector3(x, y, z) * config.cell_size
				var d: float = sampler_density.call(world_pos)
				var idx := _corner_index(x, y, z)
				_density[idx] = d
				_original_density[idx] = d
	var s := config.chunk_size
	for z in range(s):
		for y in range(s):
			for x in range(s):
				var world_pos: Vector3 = origin + (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * config.cell_size
				_tissue[_cell_index(x, y, z)] = int(sampler_tissue.call(world_pos))
	_dirty = true

func get_density_at_corner(x: int, y: int, z: int) -> float:
	var n := config.chunk_size + 1
	if x < 0 or y < 0 or z < 0 or x >= n or y >= n or z >= n:
		return 1.0
	return _density[_corner_index(x, y, z)]

func get_tissue_at_cell(x: int, y: int, z: int) -> int:
	var s := config.chunk_size
	if x < 0 or y < 0 or z < 0 or x >= s or y >= s or z >= s:
		return 0
	return _tissue[_cell_index(x, y, z)]

## Reduce density at every corner touching the given local cell coordinate
## by amount, clamped to [0, 1]. Marks the chunk dirty for remeshing.
func dig_cell(local_cell: Vector3i, amount: float) -> void:
	var s := config.chunk_size
	if local_cell.x < 0 or local_cell.y < 0 or local_cell.z < 0 \
			or local_cell.x >= s or local_cell.y >= s or local_cell.z >= s:
		return
	for dz in range(2):
		for dy in range(2):
			for dx in range(2):
				var cx := local_cell.x + dx
				var cy := local_cell.y + dy
				var cz := local_cell.z + dz
				var idx := _corner_index(cx, cy, cz)
				_density[idx] = clampf(_density[idx] - amount, 0.0, 1.0)
	_dirty = true

## Regenerate every corner toward its original density, at rate units/sec,
## for delta seconds. protect_local_pos/protect_radius (in local cell units)
## exclude cells near the player from healing solid, so the player is never
## sealed in.
func regenerate(delta: float, rate: float, protect_local_pos: Vector3, protect_radius: float) -> void:
	var n := config.chunk_size + 1
	var changed := false
	for z in range(n):
		for y in range(n):
			for x in range(n):
				var idx := _corner_index(x, y, z)
				var orig: float = _original_density[idx]
				var cur: float = _density[idx]
				if cur >= orig:
					continue
				var dist := Vector3(x, y, z).distance_to(protect_local_pos)
				if dist <= protect_radius:
					continue
				_density[idx] = minf(orig, cur + rate * delta)
				changed = true
	if changed:
		_dirty = true

func is_dirty() -> bool:
	return _dirty

## Rebuilds the render mesh and collision shape from the current density
## field. Returns elapsed time in milliseconds and also emits `remeshed`.
##
## Performance note: corner density is read into a padded local bit array
## exactly once per remesh (corner_solid, size (s+2)^3), and every later
## lookup (cell-solid test, face-neighbor test) is a direct PackedByteArray
## index into it -- no get_density_at_corner() calls, no Callables, in the
## hot per-cell/per-face loops. The first version called get_density_at_corner
## (a bounds-checked method call) up to 48 times per solid cell and measured
## ~18ms/remesh at chunk_size=16, over the 8ms budget; this version is the
## fix. Re-measure with tests/measure_remesh.gd.
func remesh() -> float:
	var start_usec := Time.get_ticks_usec()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var s := config.chunk_size
	var cs := config.cell_size
	var iso := config.iso_level
	var n := s + 1 # corners per axis

	# corner_solid[x,y,z] for x,y,z in [0, n) : whether that corner's density
	# is >= iso. Direct 1:1 copy of _density thresholded, same indexing as
	# _corner_index so no coordinate remapping is needed here.
	var corner_solid := PackedByteArray()
	corner_solid.resize(n * n * n)
	for i in range(_density.size()):
		corner_solid[i] = 1 if _density[i] >= iso else 0

	# cell_solid[x,y,z] for x,y,z in [-1, s] mapped into a padded (s+2)^3
	# array: true if any of the cell's 8 corners is solid. Cells outside
	# [0, s) are always false (a neighbor chunk owns its own boundary face).
	var pad := s + 2
	var cell_solid := PackedByteArray()
	cell_solid.resize(pad * pad * pad)
	for z in range(s):
		for y in range(s):
			for x in range(s):
				var c000 := corner_solid[x + y * n + z * n * n]
				var c100 := corner_solid[(x + 1) + y * n + z * n * n]
				var c010 := corner_solid[x + (y + 1) * n + z * n * n]
				var c001 := corner_solid[x + y * n + (z + 1) * n * n]
				var c110 := corner_solid[(x + 1) + (y + 1) * n + z * n * n]
				var c101 := corner_solid[(x + 1) + y * n + (z + 1) * n * n]
				var c011 := corner_solid[x + (y + 1) * n + (z + 1) * n * n]
				var c111 := corner_solid[(x + 1) + (y + 1) * n + (z + 1) * n * n]
				var is_solid := (c000 | c100 | c010 | c001 | c110 | c101 | c011 | c111) != 0
				var pidx := (x + 1) + (y + 1) * pad + (z + 1) * pad * pad
				cell_solid[pidx] = 1 if is_solid else 0

	for z in range(s):
		for y in range(s):
			for x in range(s):
				var pidx := (x + 1) + (y + 1) * pad + (z + 1) * pad * pad
				if cell_solid[pidx] == 0:
					continue
				var color: Color = TISSUE_COLORS[get_tissue_at_cell(x, y, z) % TISSUE_COLORS.size()]
				_emit_cell_faces_fast(st, x, y, z, cs, color, cell_solid, pad)

	st.generate_normals()
	var mesh := st.commit()
	_mesh_instance.mesh = mesh

	if mesh.get_surface_count() > 0 and mesh.surface_get_array_len(0) > 0:
		var shape := mesh.create_trimesh_shape()
		_collision.shape = shape
	else:
		_collision.shape = null

	_dirty = false
	var elapsed_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
	remeshed.emit(elapsed_ms)
	return elapsed_ms

## Emits faces for the 6 sides of local cell (x,y,z) that border an empty
## neighbor cell (a "surface nets"-style boundary face). Each face gets its
## own 4 vertices (no sharing) so generate_normals() produces hard, faceted
## low-poly shading rather than smooth interpolation.
func _emit_cell_faces_fast(st: SurfaceTool, x: int, y: int, z: int, cs: float, color: Color, cell_solid: PackedByteArray, pad: int) -> void:
	var base := Vector3(x, y, z) * cs

	var neighbors := [
		[Vector3i(1, 0, 0), [Vector3(cs, 0, 0), Vector3(cs, cs, 0), Vector3(cs, cs, cs), Vector3(cs, 0, cs)]],
		[Vector3i(-1, 0, 0), [Vector3(0, 0, cs), Vector3(0, cs, cs), Vector3(0, cs, 0), Vector3(0, 0, 0)]],
		[Vector3i(0, 1, 0), [Vector3(0, cs, 0), Vector3(0, cs, cs), Vector3(cs, cs, cs), Vector3(cs, cs, 0)]],
		[Vector3i(0, -1, 0), [Vector3(cs, 0, 0), Vector3(cs, 0, cs), Vector3(0, 0, cs), Vector3(0, 0, 0)]],
		[Vector3i(0, 0, 1), [Vector3(cs, 0, cs), Vector3(cs, cs, cs), Vector3(0, cs, cs), Vector3(0, 0, cs)]],
		[Vector3i(0, 0, -1), [Vector3(0, 0, 0), Vector3(0, cs, 0), Vector3(cs, cs, 0), Vector3(cs, 0, 0)]],
	]

	for entry in neighbors:
		var offset: Vector3i = entry[0]
		var quad: Array = entry[1]
		var nx := x + offset.x
		var ny := y + offset.y
		var nz := z + offset.z
		var pidx := (nx + 1) + (ny + 1) * pad + (nz + 1) * pad * pad
		if pidx < 0 or pidx >= cell_solid.size():
			continue # out-of-range neighbor (shouldn't happen with the +1 pad, kept as a safety net)
		if cell_solid[pidx] != 0:
			continue
		st.set_color(color)
		var v0: Vector3 = base + (quad[0] as Vector3)
		var v1: Vector3 = base + (quad[1] as Vector3)
		var v2: Vector3 = base + (quad[2] as Vector3)
		var v3: Vector3 = base + (quad[3] as Vector3)
		st.add_vertex(v0)
		st.add_vertex(v1)
		st.add_vertex(v2)
		st.add_vertex(v0)
		st.add_vertex(v2)
		st.add_vertex(v3)

## For save/load: exports the raw density and tissue arrays.
func serialize() -> Dictionary:
	return {
		"chunk_coord": [chunk_coord.x, chunk_coord.y, chunk_coord.z],
		"density": Array(_density),
		"tissue": Array(_tissue),
	}

func deserialize(data: Dictionary) -> void:
	var d: Array = data.get("density", [])
	var t: Array = data.get("tissue", [])
	for i in range(min(d.size(), _density.size())):
		_density[i] = float(d[i])
	for i in range(min(t.size(), _tissue.size())):
		_tissue[i] = int(t[i])
	_dirty = true
