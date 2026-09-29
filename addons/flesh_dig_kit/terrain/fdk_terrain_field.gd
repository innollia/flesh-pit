class_name FDKTerrainField
extends Node3D

## Owns a set of FDKChunk children, indexed by chunk-grid coordinate.
## Provides world-space dig/regenerate operations that route to the right
## chunk(s) (including shared border corners), a concentric-shell depth_at()
## helper, and optional world generators so digging into a not-yet-created
## chunk finds tissue instead of empty space.

@export var config: FDKTerrainConfig = FDKTerrainConfig.new()
@export var depth_origin: Vector3 = Vector3.ZERO

## Optional generators: Callable(world_pos: Vector3) -> float density, and
## Callable(world_pos: Vector3) -> int tissue id. Used for new chunks and for
## reading corners of chunks that do not exist yet.
var density_sampler: Callable
var tissue_sampler: Callable
## Tissue ids the chewer must not eat (e.g. the membrane around the restroom).
var inedible_tissues: PackedInt32Array = PackedInt32Array([3])
## Max chunks remeshed per frame (keeps a frame from stalling).
var remesh_budget_per_frame: int = 6

var _chunks: Dictionary = {}

func _ready() -> void:
    set_process(true)

func _process(_delta: float) -> void:
    var done := 0
    for chunk in _chunks.values():
        if chunk.is_dirty():
            chunk.remesh()
            done += 1
            if done >= remesh_budget_per_frame:
                break

## Remeshes every dirty chunk now (used at start-up and by capture tools).
func remesh_all() -> void:
    for chunk in _chunks.values():
        if chunk.is_dirty():
            chunk.remesh()

func get_or_create_chunk(chunk_coord: Vector3i) -> FDKChunk:
    if _chunks.has(chunk_coord):
        return _chunks[chunk_coord]
    var chunk := FDKChunk.new()
    chunk.name = "Chunk_%d_%d_%d" % [chunk_coord.x, chunk_coord.y, chunk_coord.z]
    chunk.field = self
    add_child(chunk)
    chunk.position = Vector3(chunk_coord) * config.chunk_size * config.cell_size
    chunk.setup(chunk_coord, config)
    _chunks[chunk_coord] = chunk
    if density_sampler.is_valid():
        var ts: Callable = tissue_sampler if tissue_sampler.is_valid() else func(_p): return 0
        chunk.fill_from_callable(density_sampler, ts)
    # neighbours read this chunk's corners for their border
    for dz in range(-1, 2):
        for dy in range(-1, 2):
            for dx in range(-1, 2):
                var nb: FDKChunk = _chunks.get(chunk_coord + Vector3i(dx, dy, dz), null)
                if nb != null:
                    nb._dirty = true
    return chunk

## Creates (and fills from the samplers) every chunk overlapping aabb.
func generate_region(aabb: AABB) -> void:
    var a := world_to_chunk_coord(aabb.position)
    var b := world_to_chunk_coord(aabb.end)
    for cz in range(a.z, b.z + 1):
        for cy in range(a.y, b.y + 1):
            for cx in range(a.x, b.x + 1):
                get_or_create_chunk(Vector3i(cx, cy, cz))

func get_chunk(chunk_coord: Vector3i) -> FDKChunk:
    return _chunks.get(chunk_coord, null)

func get_chunks() -> Array:
    return _chunks.values()

func world_to_chunk_coord(world_pos: Vector3) -> Vector3i:
    var chunk_world_size := config.chunk_size * config.cell_size
    return Vector3i(
        int(floor(world_pos.x / chunk_world_size)),
        int(floor(world_pos.y / chunk_world_size)),
        int(floor(world_pos.z / chunk_world_size)))

func world_to_cell(world_pos: Vector3) -> Array:
    var chunk_coord := world_to_chunk_coord(world_pos)
    var chunk_origin := Vector3(chunk_coord) * config.chunk_size * config.cell_size
    var local := (world_pos - chunk_origin) / config.cell_size
    var local_cell := Vector3i(int(floor(local.x)), int(floor(local.y)), int(floor(local.z)))
    local_cell = local_cell.clamp(Vector3i.ZERO, Vector3i.ONE * (config.chunk_size - 1))
    return [chunk_coord, local_cell]

func _floordiv(a: int, b: int) -> int:
    return int(floor(float(a) / float(b)))

## Density at a global corner coordinate (chunk_coord * chunk_size + local).
func corner_density_global(g: Vector3i) -> float:
    var s := config.chunk_size
    var cc := Vector3i(_floordiv(g.x, s), _floordiv(g.y, s), _floordiv(g.z, s))
    var chunk: FDKChunk = _chunks.get(cc, null)
    if chunk != null:
        var l := g - cc * s
        return chunk._density[chunk._corner_index(l.x, l.y, l.z)]
    if density_sampler.is_valid():
        return float(density_sampler.call(Vector3(g) * config.cell_size))
    return 1.0

## Changes one global corner in every chunk that stores it (a corner on a
## chunk face/edge/vertex is stored by up to 8 chunks).
func _add_corner_global(g: Vector3i, delta_density: float) -> void:
    var s := config.chunk_size
    for dz in range(2):
        for dy in range(2):
            for dx in range(2):
                var cc := Vector3i(_floordiv(g.x, s) - dx, _floordiv(g.y, s) - dy, _floordiv(g.z, s) - dz)
                var l := g - cc * s
                if l.x < 0 or l.y < 0 or l.z < 0 or l.x > s or l.y > s or l.z > s:
                    continue
                if dx == 1 and l.x != s: continue
                if dy == 1 and l.y != s: continue
                if dz == 1 and l.z != s: continue
                var chunk: FDKChunk = _chunks.get(cc, null)
                if chunk == null:
                    if dx == 0 and dy == 0 and dz == 0:
                        chunk = get_or_create_chunk(cc)
                    else:
                        continue
                var idx := chunk._corner_index(l.x, l.y, l.z)
                chunk._density[idx] = clampf(chunk._density[idx] + delta_density, 0.0, 1.0)
                chunk._dirty = true

func dig_at(world_pos: Vector3, amount: float) -> void:
    var result := world_to_cell(world_pos)
    var chunk_coord: Vector3i = result[0]
    get_or_create_chunk(chunk_coord)
    var g: Vector3i = chunk_coord * config.chunk_size + (result[1] as Vector3i)
    for dz in range(2):
        for dy in range(2):
            for dx in range(2):
                _add_corner_global(g + Vector3i(dx, dy, dz), -amount)

## Tissue id at a world position (cell center lookup).
func tissue_at(world_pos: Vector3) -> int:
    var result := world_to_cell(world_pos)
    var chunk: FDKChunk = _chunks.get(result[0], null)
    if chunk == null:
        if tissue_sampler.is_valid():
            return int(tissue_sampler.call(world_pos))
        return 0
    var lc: Vector3i = result[1]
    return chunk.get_tissue_at_cell(lc.x, lc.y, lc.z)

func is_edible_at(world_pos: Vector3) -> bool:
    return not inedible_tissues.has(tissue_at(world_pos))

## Density at a world position (nearest lower corner of its cell, max of 8).
func density_at(world_pos: Vector3) -> float:
    var result := world_to_cell(world_pos)
    var g: Vector3i = (result[0] as Vector3i) * config.chunk_size + (result[1] as Vector3i)
    var m := 0.0
    for dz in range(2):
        for dy in range(2):
            for dx in range(2):
                m = maxf(m, corner_density_global(g + Vector3i(dx, dy, dz)))
    return m

func regenerate_all(delta: float, protect_world_pos: Vector3, protect_radius: float) -> void:
    for chunk_coord in _chunks.keys():
        var chunk: FDKChunk = _chunks[chunk_coord]
        var chunk_origin: Vector3 = Vector3(chunk_coord) * config.chunk_size * config.cell_size
        var local_protect: Vector3 = (protect_world_pos - chunk_origin) / config.cell_size
        var local_radius: float = protect_radius / config.cell_size
        chunk.regenerate(delta, config.regen_rate, local_protect, local_radius)

func depth_at(world_pos: Vector3) -> float:
    return world_pos.distance_to(depth_origin)

func carve_sphere(center: Vector3, radius: float) -> void:
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
                                chunk._density[idx] = 0.0
                                chunk._original_density[idx] = 0.0
                chunk._dirty = true

func fill_box_uniform(aabb: AABB, density: float, tissue_id: int) -> void:
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
                                chunk._density[idx] = density
                                chunk._original_density[idx] = density
                var s := config.chunk_size
                for z in range(s):
                    for y in range(s):
                        for x in range(s):
                            var c: Vector3 = origin + (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * config.cell_size
                            if aabb.has_point(c):
                                chunk._tissue[x + y * s + z * s * s] = tissue_id
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
