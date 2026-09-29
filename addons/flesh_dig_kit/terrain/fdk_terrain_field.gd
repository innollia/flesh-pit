class_name FDKTerrainField
extends Node3D

## Owns a set of FDKChunk children, indexed by chunk-grid coordinate.
## Provides world-space dig/regenerate operations that route to the right
## chunk(s), and a concentric-shell depth_at() helper for depth-band logic.

@export var config: FDKTerrainConfig = FDKTerrainConfig.new()

## World-space origin that depth_at() measures distance from (typically the
## restroom's center point).
@export var depth_origin: Vector3 = Vector3.ZERO

var _chunks: Dictionary = {} # Vector3i -> FDKChunk

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	for chunk in _chunks.values():
		if chunk.is_dirty():
			chunk.remesh()

## Returns the chunk at chunk_coord, creating an empty one (all density 0,
## i.e. fully carved out) if it does not exist yet.
func get_or_create_chunk(chunk_coord: Vector3i) -> FDKChunk:
	if _chunks.has(chunk_coord):
		return _chunks[chunk_coord]
	var chunk := FDKChunk.new()
	chunk.name = "Chunk_%d_%d_%d" % [chunk_coord.x, chunk_coord.y, chunk_coord.z]
	add_child(chunk)
	chunk.position = Vector3(chunk_coord) * config.chunk_size * config.cell_size
	chunk.setup(chunk_coord, config)
	_chunks[chunk_coord] = chunk
	return chunk

func get_chunk(chunk_coord: Vector3i) -> FDKChunk:
	return _chunks.get(chunk_coord, null)

func world_to_chunk_coord(world_pos: Vector3) -> Vector3i:
	var chunk_world_size := config.chunk_size * config.cell_size
	return Vector3i(
		int(floor(world_pos.x / chunk_world_size)),
		int(floor(world_pos.y / chunk_world_size)),
		int(floor(world_pos.z / chunk_world_size))
	)

## Returns [chunk_coord, local_cell] for the cell containing world_pos.
func world_to_cell(world_pos: Vector3) -> Array:
	var chunk_coord := world_to_chunk_coord(world_pos)
	var chunk_origin := Vector3(chunk_coord) * config.chunk_size * config.cell_size
	var local := (world_pos - chunk_origin) / config.cell_size
	var local_cell := Vector3i(int(floor(local.x)), int(floor(local.y)), int(floor(local.z)))
	return [chunk_coord, local_cell]

## Carves at world_pos by amount (0..1 density removed). Creates the chunk
## if needed so digging into unvisited space works.
func dig_at(world_pos: Vector3, amount: float) -> void:
	var result := world_to_cell(world_pos)
	var chunk_coord: Vector3i = result[0]
	var local_cell: Vector3i = result[1]
	var chunk := get_or_create_chunk(chunk_coord)
	chunk.dig_cell(local_cell, amount)

## Regenerates every loaded chunk. protect_world_pos/protect_radius (world
## units) keep tissue near the player from healing solid.
func regenerate_all(delta: float, protect_world_pos: Vector3, protect_radius: float) -> void:
	for chunk_coord in _chunks.keys():
		var chunk: FDKChunk = _chunks[chunk_coord]
		var chunk_origin: Vector3 = Vector3(chunk_coord) * config.chunk_size * config.cell_size
		var local_protect: Vector3 = (protect_world_pos - chunk_origin) / config.cell_size
		var local_radius: float = protect_radius / config.cell_size
		chunk.regenerate(delta, config.regen_rate, local_protect, local_radius)

## Concentric-shell depth: distance from depth_origin, in world units.
## Depth bands (biome shells) are defined by the game as ranges over this
## value; the kit only provides the raw distance.
func depth_at(world_pos: Vector3) -> float:
	return world_pos.distance_to(depth_origin)

## Fills a spherical room of given radius (in world units) around center
## with density 0.0 (fully empty/carved), tissue_id ignored since it is
## empty space. Chunks touching the sphere are created on demand.
func carve_sphere(center: Vector3, radius: float) -> void:
	var chunk_world_size := config.chunk_size * config.cell_size
	var min_coord := world_to_chunk_coord(center - Vector3.ONE * radius)
	var max_coord := world_to_chunk_coord(center + Vector3.ONE * radius)
	for cz in range(min_coord.z, max_coord.z + 1):
		for cy in range(min_coord.y, max_coord.y + 1):
			for cx in range(min_coord.x, max_coord.x + 1):
				var chunk_coord := Vector3i(cx, cy, cz)
				var chunk := get_or_create_chunk(chunk_coord)
				var n := config.chunk_size + 1
				var origin: Vector3 = Vector3(chunk_coord) * config.chunk_size * config.cell_size
				for z in range(n):
					for y in range(n):
						for x in range(n):
							var world_corner: Vector3 = origin + Vector3(x, y, z) * config.cell_size
							if world_corner.distance_to(center) <= radius:
								var idx := x + y * n + z * n * n
								var arr_idx_ok := idx < chunk._density.size()
								if arr_idx_ok:
									chunk._density[idx] = 0.0
									chunk._original_density[idx] = 0.0
				chunk._dirty = true

## Fills a solid rectangular slab (world-space AABB) with the given density
## and tissue id. Used for the initial flesh wall blocking the restroom door.
func fill_box_uniform(aabb: AABB, density: float, tissue_id: int) -> void:
	var chunk_world_size := config.chunk_size * config.cell_size
	var min_coord := world_to_chunk_coord(aabb.position)
	var max_coord := world_to_chunk_coord(aabb.position + aabb.size)
	for cz in range(min_coord.z, max_coord.z + 1):
		for cy in range(min_coord.y, max_coord.y + 1):
			for cx in range(min_coord.x, max_coord.x + 1):
				var chunk_coord := Vector3i(cx, cy, cz)
				var chunk := get_or_create_chunk(chunk_coord)
				var n := config.chunk_size + 1
				var origin: Vector3 = Vector3(chunk_coord) * config.chunk_size * config.cell_size
				for z in range(n):
					for y in range(n):
						for x in range(n):
							var world_corner: Vector3 = origin + Vector3(x, y, z) * config.cell_size
							if aabb.has_point(world_corner):
								var idx := x + y * n + z * n * n
								if idx < chunk._density.size():
									chunk._density[idx] = density
									chunk._original_density[idx] = density
				var s := config.chunk_size
				for z in range(s):
					for y in range(s):
						for x in range(s):
							var world_cell_center: Vector3 = origin + (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * config.cell_size
							if aabb.has_point(world_cell_center):
								var cidx := x + y * s + z * s * s
								if cidx < chunk._tissue.size():
									chunk._tissue[cidx] = tissue_id
				chunk._dirty = true

func serialize() -> Dictionary:
	var chunks_data: Array = []
	for chunk_coord in _chunks.keys():
		chunks_data.append(_chunks[chunk_coord].serialize())
	return {"version": 1, "chunks": chunks_data}

func deserialize(data: Dictionary) -> void:
	var chunks_data: Array = data.get("chunks", [])
	for entry in chunks_data:
		var coord_arr: Array = entry.get("chunk_coord", [0, 0, 0])
		var chunk_coord := Vector3i(int(coord_arr[0]), int(coord_arr[1]), int(coord_arr[2]))
		var chunk := get_or_create_chunk(chunk_coord)
		chunk.deserialize(entry)
