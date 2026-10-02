class_name FDKTerrainField
extends Node3D

## Optional world-space surface constraint for authored architecture.
var surface_constraint: Callable

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
## Extra no-regen spheres (Vector4: world xyz + radius), e.g. placed
## barriers holding a tunnel open. Game code refreshes this list each frame.
var regen_blockers: Array = []
## Optional Callable(world_pos: Vector3) -> float regen-rate multiplier,
## sampled once per chunk (e.g. danger rising per shell).
var regen_rate_scale: Callable

var _chunks: Dictionary = {}
var _urgent_chunks: Dictionary = {}
var _remesh_cursor := 0

func _ready() -> void:
    set_process(true)

## Per-frame remesh time budget (ms). At least one dirty chunk is always
## remeshed; more only while the frame stays under this budget, so a burst
## of dirty chunks (contraction wave, spray) never stalls a frame.
var remesh_ms_per_frame: float = 8.0
## Seconds of simulated time for the contractile squeeze clock.
var contract_time: float = 0.0
## Emitted once per chunk per squeeze cycle, CONTRACT_WARN seconds before the
## squeeze starts there (the sound plays 1 s early -- 02-world-tissue.md 3).
signal contraction_warning(world_pos: Vector3)
var _warned: Dictionary = {}

## P1 regrowth collider lag: a chunk whose collider only waits on regrowth
## gets it rebuilt after this many seconds, at most `collision_flush_per_frame`
## chunks per frame. Removal and growth near the player never wait.
var collision_delay: float = 0.4
var collision_flush_per_frame: int = 2
## Extra metres added to the regen protect radius for the collision guard:
## growth this close to the player rebuilds the collider at once.
var collision_guard_margin: float = 1.2
var _guard_pos: Vector3 = Vector3.ZERO
var _guard_radius: float = -1.0

func _process(delta: float) -> void:
    var done := 0
    var start := Time.get_ticks_usec()
    var ordered: Array = []
    for chunk in _urgent_chunks.values():
        if is_instance_valid(chunk) and chunk.is_dirty(): ordered.append(chunk)
    var chunks := _chunks.values()
    for i in range(chunks.size()):
        var chunk: FDKChunk = chunks[(_remesh_cursor + i) % chunks.size()]
        if chunk.is_dirty() and not _urgent_chunks.has(chunk.chunk_coord): ordered.append(chunk)
    for chunk in ordered:
        chunk.remesh()
        _urgent_chunks.erase(chunk.chunk_coord)
        done += 1
        _remesh_cursor = (chunks.find(chunk) + 1) % maxi(chunks.size(), 1)
        if done >= remesh_budget_per_frame or (Time.get_ticks_usec() - start) / 1000.0 >= remesh_ms_per_frame * 0.5:
            break
    step_collision(delta)

## Ages parked regrowth colliders and rebuilds the due ones (oldest first,
## budgeted). Returns how many were rebuilt.
func step_collision(delta: float) -> int:
    var due: Array = []
    for chunk in _chunks.values():
        if chunk.is_collision_pending():
            chunk._coll_pending_age += delta
            if chunk._coll_pending_age >= collision_delay:
                due.append(chunk)
    if due.is_empty():
        return 0
    due.sort_custom(func(a, b): return a._coll_pending_age > b._coll_pending_age)
    var n := mini(due.size(), maxi(collision_flush_per_frame, 1))
    for i in range(n):
        due[i].flush_collision()
    return n

## Sets the world sphere inside which regrowth rebuilds colliders at once.
func set_collision_guard(world_pos: Vector3, radius: float) -> void:
    _guard_pos = world_pos
    _guard_radius = radius

## The collision guard in `chunk`'s local corner units (w < 0 = none).
func collision_guard_local(chunk: FDKChunk) -> Vector4:
    if _guard_radius <= 0.0:
        return Vector4(0, 0, 0, -1.0)
    var l := (_guard_pos - chunk.position) / config.cell_size
    return Vector4(l.x, l.y, l.z, _guard_radius / config.cell_size)

## Advances the contractile squeeze (only chunks within `radius` of `near`,
## which is where the player can see or feel it). Returns chunks changed.
func step_contraction(delta: float, near: Vector3, radius: float = 14.0) -> int:
    contract_time += delta
    # keep the (wider) regen guard when it is already centred on the player
    if _guard_radius <= 0.0 or _guard_pos.distance_to(near) > 0.01:
        set_collision_guard(near, collision_guard_margin)
    var chunk_world := float(config.chunk_size) * config.cell_size
    var changed := 0
    for cc in _chunks.keys():
        var chunk: FDKChunk = _chunks[cc]
        var mid: Vector3 = chunk.position + Vector3.ONE * chunk_world * 0.5
        if mid.distance_to(near) > radius + chunk_world:
            continue
        if chunk.step_contraction(contract_time, delta):
            changed += 1
        if chunk.has_contractile_tissue() and not chunk._contract_idx.is_empty():
            var k: int = chunk._contract_idx.size() / 2
            var phase: float = chunk._contract_phase[k]
            var tt := contract_time + phase
            var cycle := int(floor((tt + FDKTissueRules.CONTRACT_WARN) / FDKTissueRules.CONTRACT_PERIOD))
            if fposmod(tt, FDKTissueRules.CONTRACT_PERIOD) >= FDKTissueRules.CONTRACT_PERIOD - FDKTissueRules.CONTRACT_WARN and int(_warned.get(cc, -1)) != cycle:
                _warned[cc] = cycle
                contraction_warning.emit(mid)
    return changed

## Remeshes every dirty chunk now (used at start-up and by capture tools).
func remesh_all() -> void:
    for chunk in _chunks.values():
        if chunk.is_dirty():
            chunk.remesh(true)
        elif chunk.is_collision_pending():
            chunk.flush_collision()

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
        var ci := chunk._corner_index(l.x, l.y, l.z)
        return chunk._density[ci] + chunk.contract_at_corner(ci)
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
                chunk._regen_scan = true
                chunk._contract_list_dirty = true
                chunk._dirty = true
                _urgent_chunks[cc] = chunk

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
## Sprayed cells report FDKTissueRules.MELTED ("���� ��").
func tissue_at(world_pos: Vector3) -> int:
    var result := world_to_cell(world_pos)
    var chunk: FDKChunk = _chunks.get(result[0], null)
    if chunk == null:
        if tissue_sampler.is_valid():
            return int(tissue_sampler.call(world_pos))
        return 0
    var lc: Vector3i = result[1]
    if chunk.is_sealed_at_cell(lc.x, lc.y, lc.z):
        return FDKTissueRules.MELTED
    return chunk.get_tissue_at_cell(lc.x, lc.y, lc.z)

## Biosecurity spray (06-tools.md 5): melts the wall the player aims at.
## Cells within `radius` of the aim line and from just in front of the
## surface to `depth` metres into it are melted (density 0, sealed, never
## regrow, inedible). Every corner within `boost_range` of a melted cell
## regrows `boost_mult` times faster, so the flesh beside a sprayed tunnel
## squeezes in from the side. Returns the number of cells melted.
func spray_surface(hit: Vector3, into: Vector3, radius: float, depth: float,
        boost_range: float = 1.0, boost_mult: float = 2.0) -> int:
    var n_dir := into.normalized()
    var reach := maxf(radius, depth) + boost_range + config.cell_size
    var min_coord := world_to_chunk_coord(hit - Vector3.ONE * reach)
    var max_coord := world_to_chunk_coord(hit + Vector3.ONE * reach)
    var s := config.chunk_size
    var n := s + 1
    var melted: Array[Vector3] = []
    for cz in range(min_coord.z, max_coord.z + 1):
        for cy in range(min_coord.y, max_coord.y + 1):
            for cx in range(min_coord.x, max_coord.x + 1):
                var chunk := get_or_create_chunk(Vector3i(cx, cy, cz))
                var origin: Vector3 = chunk.position
                var any := false
                for z in range(s):
                    for y in range(s):
                        for x in range(s):
                            var c: Vector3 = origin + (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * config.cell_size
                            var v := c - hit
                            var along := v.dot(n_dir)
                            if along < -config.cell_size * 0.5 or along > depth:
                                continue
                            if (v - n_dir * along).length() > radius:
                                continue
                            if chunk.is_sealed_at_cell(x, y, z):
                                continue
                            chunk.seal_cell(x, y, z)
                            melted.append(c)
                            any = true
                            for dz in range(2):
                                for dy in range(2):
                                    for dx in range(2):
                                        var idx := (x + dx) + (y + dy) * n + (z + dz) * n * n
                                        chunk._density[idx] = 0.0
                                        chunk._original_density[idx] = 0.0
                if any:
                    chunk.tissue_changed()
                    chunk._dirty = true
    if melted.is_empty():
        return 0
    # regrowth boost ring (corners in neighbour chunks too)
    for cz in range(min_coord.z, max_coord.z + 1):
        for cy in range(min_coord.y, max_coord.y + 1):
            for cx in range(min_coord.x, max_coord.x + 1):
                var chunk: FDKChunk = _chunks.get(Vector3i(cx, cy, cz), null)
                if chunk == null:
                    continue
                var origin: Vector3 = chunk.position
                for z in range(n):
                    for y in range(n):
                        for x in range(n):
                            var p: Vector3 = origin + Vector3(x, y, z) * config.cell_size
                            if p.distance_to(hit) > reach:
                                continue
                            for m in melted:
                                if p.distance_to(m) <= boost_range:
                                    chunk.set_corner_boost(x + y * n + z * n * n, boost_mult)
                                    break
    return melted.size()

## Regrowth multiplier at a world corner (tissue x spray boost). For tests.
func regen_multiplier_at(world_pos: Vector3) -> float:
    var cc := world_to_chunk_coord(world_pos)
    var chunk: FDKChunk = _chunks.get(cc, null)
    if chunk == null:
        return 1.0
    var l := Vector3i(((world_pos - chunk.position) / config.cell_size).round())
    l = l.clamp(Vector3i.ZERO, Vector3i.ONE * config.chunk_size)
    return chunk.corner_regen_multiplier(l.x, l.y, l.z)

func is_edible_at(world_pos: Vector3) -> bool:
    if is_sealed_at(world_pos):
        return false
    return not inedible_tissues.has(tissue_at(world_pos))

## True where biosecurity spray has permanently dissolved tissue (docs/spec/02-world-tissue.md
## 2): the cell is neither edible nor eligible for regeneration ever again.
func is_sealed_at(world_pos: Vector3) -> bool:
    var result := world_to_cell(world_pos)
    var chunk: FDKChunk = _chunks.get(result[0], null)
    if chunk == null:
        return false
    var lc: Vector3i = result[1]
    return chunk.is_sealed_at_cell(lc.x, lc.y, lc.z)

## Permanently dissolves tissue in a sphere: clears density to 0 (like
## carve_sphere) AND marks every cell whose center falls inside the sphere as
## sealed, so it is inedible and never regenerates. Used by the biosecurity
## spray can; radius depends on the can tier (cheap = surface only, expensive
## = deeper). Returns the number of cells sealed (for tests / tuning).
func spray_sphere(center: Vector3, radius: float) -> int:
    var min_coord := world_to_chunk_coord(center - Vector3.ONE * radius)
    var max_coord := world_to_chunk_coord(center + Vector3.ONE * radius)
    var sealed_count := 0
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
                var s := config.chunk_size
                for z in range(s):
                    for y in range(s):
                        for x in range(s):
                            var c: Vector3 = origin + (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) * config.cell_size
                            if c.distance_to(center) <= radius and not chunk.is_sealed_at_cell(x, y, z):
                                chunk.seal_cell(x, y, z)
                                sealed_count += 1
                chunk._dirty = true
    return sealed_count

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
    set_collision_guard(protect_world_pos, protect_radius + collision_guard_margin)
    for chunk_coord in _chunks.keys():
        var chunk: FDKChunk = _chunks[chunk_coord]
        if not chunk._regen_scan and chunk._regen_idx.is_empty():
            continue
        var chunk_origin: Vector3 = Vector3(chunk_coord) * config.chunk_size * config.cell_size
        var local_protect: Vector3 = (protect_world_pos - chunk_origin) / config.cell_size
        var local_radius: float = protect_radius / config.cell_size
        var rate: float = config.regen_rate
        var chunk_world := float(config.chunk_size) * config.cell_size
        if regen_rate_scale.is_valid():
            rate *= float(regen_rate_scale.call(chunk_origin + Vector3.ONE * chunk_world * 0.5))
        var local_blockers: Array = []
        for b in regen_blockers:
            var bv: Vector4 = b
            var bc := Vector3(bv.x, bv.y, bv.z)
            var closest := bc.clamp(chunk_origin, chunk_origin + Vector3.ONE * chunk_world)
            if closest.distance_to(bc) <= bv.w:
                var lc := (bc - chunk_origin) / config.cell_size
                local_blockers.append(Vector4(lc.x, lc.y, lc.z, bv.w / config.cell_size))
        chunk.regenerate(delta, rate, local_protect, local_radius, local_blockers)

## Chew press visual: dents then stretches the wall around `center` toward
## `toward` (usually the player) as amount goes 0..1. amount 0 = off.
func set_press(center: Vector3, toward: Vector3, amount: float) -> void:
    FDKChunk.set_press_all(center, toward, clampf(amount, 0.0, 1.0))

func get_press_amount() -> float:
    var v = FDKChunk.terrain_material(0).get_shader_parameter("press_amount")
    return float(v) if v != null else 0.0

## Strong local contraction (docs/spec/02-world-tissue.md, nerve tissue): the tunnel
## squeezes shut around `center` -- density jumps back toward its original
## value by up to `amount` (more at the middle). Sprayed cells stay open.
## Returns how many corners moved.
func contract_sphere(center: Vector3, radius: float, amount: float) -> int:
    var moved := 0
    var min_coord := world_to_chunk_coord(center - Vector3.ONE * radius)
    var max_coord := world_to_chunk_coord(center + Vector3.ONE * radius)
    var n := config.chunk_size + 1
    var s := config.chunk_size
    for cz in range(min_coord.z, max_coord.z + 1):
        for cy in range(min_coord.y, max_coord.y + 1):
            for cx in range(min_coord.x, max_coord.x + 1):
                var chunk: FDKChunk = _chunks.get(Vector3i(cx, cy, cz), null)
                if chunk == null:
                    continue
                var origin: Vector3 = Vector3(cx, cy, cz) * s * config.cell_size
                var lc := (center - origin) / config.cell_size
                var lr := radius / config.cell_size
                var x0 := maxi(0, int(floor(lc.x - lr)))
                var x1 := mini(n - 1, int(ceil(lc.x + lr)))
                var y0 := maxi(0, int(floor(lc.y - lr)))
                var y1 := mini(n - 1, int(ceil(lc.y + lr)))
                var z0 := maxi(0, int(floor(lc.z - lr)))
                var z1 := mini(n - 1, int(ceil(lc.z + lr)))
                var changed := false
                for z in range(z0, z1 + 1):
                    for y in range(y0, y1 + 1):
                        for x in range(x0, x1 + 1):
                            var dist := Vector3(x - lc.x, y - lc.y, z - lc.z).length()
                            if dist > lr:
                                continue
                            var idx := x + y * n + z * n * n
                            var orig: float = chunk._original_density[idx]
                            var cur: float = chunk._density[idx]
                            if cur >= orig or chunk._sealed_corner_touches_sealed_cell(x, y, z, s):
                                continue
                            chunk._density[idx] = minf(orig, cur + amount * (1.0 - dist / lr))
                            moved += 1
                            changed = true
                if changed:
                    chunk._dirty = true
    return moved

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
                chunk.tissue_changed()
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
