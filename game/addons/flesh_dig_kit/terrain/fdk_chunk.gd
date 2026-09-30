class_name FDKChunk
extends Node3D

## One cubic chunk of the density-grid terrain field.
##
## Meshing: surface nets. Every cell whose 8 corners straddle the iso level
## gets one vertex (average of its edge crossings, plus a small stable
## jitter so walls read as organic facets instead of a grid). Every corner
## edge that crosses the iso level emits one quad joining the 4 cells around
## it. Triangles never share vertices, so each gets its own flat normal.
##
## PS1 tone (docs/tone-and-manner.md): crude low-poly shapes wearing real
## low-res textures, not flat vertex-colour shading. Each tissue id gets its
## own mesh surface with its own PS1 material (nearest-filtered, dithered,
## vertex-snapped); a world-aligned UV (two dominant axes of the face
## normal) keeps texture scale consistent across the organic geometry.
##
## The chunk reads a 1-corner border from its neighbours through its
## parent FDKTerrainField, and each corner edge is owned by exactly one
## chunk, so there are no seams between chunks.
##
## Density convention: 1.0 = solid tissue, 0.0 = empty. Solid when >= iso.

signal remeshed(elapsed_ms: float)

var chunk_coord: Vector3i = Vector3i.ZERO
var config: FDKTerrainConfig
## Parent field (set by FDKTerrainField). Null = standalone chunk, whose
## outside is treated as solid.
var field: Node = null

var _density: PackedFloat32Array = PackedFloat32Array()
## Tissue id per cell (chunk_size^3). See TISSUE_TEXTURES.
var _tissue: PackedByteArray = PackedByteArray()
var _original_density: PackedFloat32Array = PackedFloat32Array()
var _sealed: PackedByteArray = PackedByteArray()

var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D
var _static_body: StaticBody3D
var _dirty: bool = false

## P0 debug timing of the last remesh() in ms: density (padded read), mesh
## (surface nets), arraymesh (surfaces + assign), collider, total. Debug
## statistics only -- never shown on screen.
var last_stats: Dictionary = {}

## P1: the collider is kept apart from the visual mesh. A remesh that removes
## tissue (any padded corner lower than what the current collider was built
## from) rebuilds the collider at once; pure regrowth only refreshes the mesh
## and parks the new faces here until FDKTerrainField flushes them after a
## short delay under a per-frame budget. Growth inside the field's collision
## guard (around the player) always rebuilds at once, so the player never
## ends up inside or walks through flesh that is visibly closing in.
var _coll_density: PackedFloat32Array = PackedFloat32Array()
var _coll_pending: bool = false
var _coll_pending_age: float = 0.0
var _pending_faces: PackedVector3Array = PackedVector3Array()
var _pending_density: PackedFloat32Array = PackedFloat32Array()

## P2: corners still below their original density (the only ones regrowth
## has to visit). Rebuilt by a full scan only after something lowered
## density (dig, load, tissue edit); healed corners drop out as they finish.
var _regen_idx: PackedInt32Array = PackedInt32Array()
var _regen_scan: bool = true

## Tissue ids (docs/spec/02-world-tissue.md): 0 core/compressive (default flesh), 1 nerve
## bundle (surface shell precursor + door nerves), 2 fat band (shell-boundary
## signal), 3 membrane (inedible, around the restroom), 4 mantle/contractile
## (mantle shell). Placeholder textures only; final art is frontend scope.
## Textures from tools/bake_tissue_textures.py (asset-list TIS-01..05). Index
## = FDKTissueRules id; 5 (melted) skins faces that border a sprayed cell.
const TISSUE_TEXTURES: Array[String] = [
    "res://addons/flesh_dig_kit/textures/tissue_compressive_128.png",
    "res://addons/flesh_dig_kit/textures/tissue_nerve_128.png",
    "res://addons/flesh_dig_kit/textures/tex_fat_128.png",
    "res://addons/flesh_dig_kit/textures/tissue_membrane_128.png",
    "res://addons/flesh_dig_kit/textures/tissue_contractile_128.png",
    "res://addons/flesh_dig_kit/textures/tissue_melted_64.png",
]
const UV_SCALE := 0.9

static func terrain_material(tissue_id: int) -> ShaderMaterial:
    var path: String = TISSUE_TEXTURES[tissue_id % TISSUE_TEXTURES.size()]
    return FDKPs1Material.get_material(path, UV_SCALE, false, 0.55, 0.6)

## Applies the chew-press deformation to the material of every tissue this
## chunk currently uses (kept as a single call site so main.gd's per-frame
## set_press still works with one material per tissue).
static func set_press_all(center: Vector3, toward: Vector3, amount: float) -> void:
    for i in range(TISSUE_TEXTURES.size()):
        var m := terrain_material(i)
        m.set_shader_parameter("press_center", center)
        m.set_shader_parameter("press_amount", amount)

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
    _sealed = PackedByteArray()
    _sealed.resize(config.chunk_size * config.chunk_size * config.chunk_size)

    _static_body = StaticBody3D.new()
    _static_body.name = "Body"
    _static_body.set_meta("fdk_terrain_chunk", true)
    add_child(_static_body)
    _mesh_instance = MeshInstance3D.new()
    _mesh_instance.name = "Mesh"
    _static_body.add_child(_mesh_instance)
    _collision = CollisionShape3D.new()
    _collision.name = "Collision"
    _static_body.add_child(_collision)

func get_body() -> StaticBody3D:
    return _static_body

func _corner_index(x: int, y: int, z: int) -> int:
    var n := config.chunk_size + 1
    return x + y * n + z * n * n

func _cell_index(x: int, y: int, z: int) -> int:
    var s := config.chunk_size
    return x + y * s + z * s * s

func fill_uniform(density: float, tissue_id: int) -> void:
    for i in range(_density.size()):
        _density[i] = density
        _original_density[i] = density
    for i in range(_tissue.size()):
        _tissue[i] = tissue_id
    tissue_changed()
    _dirty = true

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
    tissue_changed()
    _dirty = true

func get_density_at_corner(x: int, y: int, z: int) -> float:
    var n := config.chunk_size + 1
    if x < 0 or y < 0 or z < 0 or x >= n or y >= n or z >= n:
        return 1.0
    return _density[_corner_index(x, y, z)]

func set_density_at_corner(x: int, y: int, z: int, d: float) -> void:
    var n := config.chunk_size + 1
    if x < 0 or y < 0 or z < 0 or x >= n or y >= n or z >= n:
        return
    _density[_corner_index(x, y, z)] = d
    _regen_scan = true
    _dirty = true

func get_tissue_at_cell(x: int, y: int, z: int) -> int:
    var s := config.chunk_size
    if x < 0 or y < 0 or z < 0 or x >= s or y >= s or z >= s:
        return 0
    return _tissue[_cell_index(x, y, z)]

func set_tissue_at_cell(x: int, y: int, z: int, tissue_id: int) -> void:
    var s := config.chunk_size
    if x < 0 or y < 0 or z < 0 or x >= s or y >= s or z >= s:
        return
    _tissue[_cell_index(x, y, z)] = tissue_id
    tissue_changed()
    _dirty = true

## Lowers density at the 8 corners of one local cell. When the chunk has a
## parent field, use FDKTerrainField.dig_at instead so shared border
## corners in neighbour chunks change too.
func dig_cell(local_cell: Vector3i, amount: float) -> void:
    var s := config.chunk_size
    if local_cell.x < 0 or local_cell.y < 0 or local_cell.z < 0 \
            or local_cell.x >= s or local_cell.y >= s or local_cell.z >= s:
        return
    for dz in range(2):
        for dy in range(2):
            for dx in range(2):
                var idx := _corner_index(local_cell.x + dx, local_cell.y + dy, local_cell.z + dz)
                _density[idx] = clampf(_density[idx] - amount, 0.0, 1.0)
    _regen_scan = true
    _dirty = true

var _any_sealed: bool = false

## Per-corner regrowth multiplier: tissue regen (FDKTissueRules.REGEN) x the
## spray-neighbourhood boost (06-tools.md 5: x2.0 within 1.0 m of a melted
## cell). Rebuilt lazily when tissue or boost changes.
var _regen_mult: PackedFloat32Array = PackedFloat32Array()
var _regen_mult_dirty: bool = true
## Per-corner spray boost (1.0 = none). Set by FDKTerrainField.spray_surface.
var _boost: PackedFloat32Array = PackedFloat32Array()

## Contractile squeeze (02-world-tissue.md 3): corners of contractile cells
## that touch an empty cell, their phase, and the density currently added.
var _contract: PackedFloat32Array = PackedFloat32Array()
var _has_contract: bool = false
var _contract_idx: PackedInt32Array = PackedInt32Array()
var _contract_phase: PackedFloat32Array = PackedFloat32Array()
var _contract_list_age: float = 999.0
var _has_contractile_tissue: int = -1 ## -1 unknown, 0 no, 1 yes

func _rebuild_regen_mult() -> void:
    var n := config.chunk_size + 1
    var s := config.chunk_size
    if _regen_mult.size() != n * n * n:
        _regen_mult.resize(n * n * n)
    if _boost.size() != n * n * n:
        _boost.resize(n * n * n)
        _boost.fill(1.0)
    for z in range(n):
        var cz := mini(z, s - 1)
        for y in range(n):
            var cy := mini(y, s - 1)
            for x in range(n):
                var t: int = _tissue[mini(x, s - 1) + cy * s + cz * s * s]
                var i := x + y * n + z * n * n
                _regen_mult[i] = FDKTissueRules.regen_multiplier(t) * _boost[i]
    _regen_mult_dirty = false

## Sets the spray boost on one corner (x1.0 .. x2.0).
func set_corner_boost(idx: int, mult: float) -> void:
    var n := config.chunk_size + 1
    if _boost.size() != n * n * n:
        _boost.resize(n * n * n)
        _boost.fill(1.0)
    if mult > _boost[idx]:
        _boost[idx] = mult
        _regen_mult_dirty = true

func corner_regen_multiplier(x: int, y: int, z: int) -> float:
    if _regen_mult_dirty:
        _rebuild_regen_mult()
    var n := config.chunk_size + 1
    return _regen_mult[x + y * n + z * n * n]

func has_contractile_tissue() -> bool:
    if _has_contractile_tissue < 0:
        _has_contractile_tissue = 1 if _tissue.has(FDKTissueRules.CONTRACTILE) else 0
    return _has_contractile_tissue == 1

## Advances the contractile squeeze to `time`. Returns true if the shape
## changed enough to need a remesh (the chunk is then marked dirty).
func step_contraction(time: float, delta: float) -> bool:
    if not has_contractile_tissue():
        return false
    var n := config.chunk_size + 1
    var s := config.chunk_size
    _contract_list_age += delta
    if _contract_list_age >= 1.0:
        _contract_list_age = 0.0
        _rebuild_contract_list()
    if _contract.size() != n * n * n:
        _contract.resize(n * n * n)
    var changed := false
    if _contract_idx.is_empty():
        if _has_contract:
            _contract.fill(0.0)
            _has_contract = false
            _dirty = true
            return true
        return false
    var any := false
    for k in range(_contract_idx.size()):
        var i: int = _contract_idx[k]
        var v := FDKTissueRules.CONTRACT_GAIN * FDKTissueRules.contract_envelope(time + _contract_phase[k])
        if absf(v - _contract[i]) > 0.02 or (v == 0.0 and _contract[i] != 0.0):
            _contract[i] = v
            changed = true
        if v > 0.0:
            any = true
    _has_contract = any or changed
    if changed:
        _dirty = true
    return changed

func _rebuild_contract_list() -> void:
    var n := config.chunk_size + 1
    var s := config.chunk_size
    var iso := FDKTissueRules.EMPTY_DENSITY
    var keep := {}
    for k in range(_contract_idx.size()):
        keep[_contract_idx[k]] = true
    var idx := PackedInt32Array()
    var ph := PackedFloat32Array()
    var origin := Vector3(chunk_coord) * s * config.cell_size
    for z in range(1, n - 1):
        for y in range(1, n - 1):
            for x in range(1, n - 1):
                var i := x + y * n + z * n * n
                var t: int = _tissue[mini(x, s - 1) + mini(y, s - 1) * s + mini(z, s - 1) * s * s]
                if t != FDKTissueRules.CONTRACTILE:
                    continue
                if _sealed_corner_touches_sealed_cell(x, y, z, s):
                    continue
                var touches := _density[i] < iso or _density[i - 1] < iso or _density[i + 1] < iso \
                    or _density[i - n] < iso or _density[i + n] < iso \
                    or _density[i - n * n] < iso or _density[i + n * n] < iso
                if not touches:
                    continue
                idx.append(i)
                ph.append(FDKTissueRules.contract_phase(origin + Vector3(x, y, z) * config.cell_size))
    # corners that dropped off the list relax back to 0
    if _contract.size() == n * n * n:
        for i in keep.keys():
            if not ph.is_empty() and idx.has(i):
                continue
            if _contract[i] != 0.0:
                _contract[i] = 0.0
                _dirty = true
    _contract_idx = idx
    _contract_phase = ph

## Current squeeze offset at a corner (0 when none).
func contract_at_corner(idx: int) -> float:
    if not _has_contract or _contract.size() <= idx:
        return 0.0
    return _contract[idx]

func regenerate(delta: float, rate: float, protect_local_pos: Vector3, protect_radius: float, blockers: Array = []) -> void:
    if _regen_mult_dirty:
        _rebuild_regen_mult()
    var n := config.chunk_size + 1
    var s := config.chunk_size
    var changed := false
    var r2 := protect_radius * protect_radius
    if _regen_scan:
        _regen_scan = false
        _regen_idx = PackedInt32Array()
        for i in range(_density.size()):
            if _density[i] < _original_density[i]:
                _regen_idx.append(i)
    if _regen_idx.is_empty():
        return
    var healed := 0
    for k in range(_regen_idx.size()):
        var i: int = _regen_idx[k]
        var orig: float = _original_density[i]
        var cur: float = _density[i]
        if cur >= orig:
            healed += 1
            continue
        var x := i % n
        var y := (i / n) % n
        var z := i / (n * n)
        var dx := x - protect_local_pos.x
        var dy := y - protect_local_pos.y
        var dz := z - protect_local_pos.z
        if dx * dx + dy * dy + dz * dz <= r2:
            continue
        var blocked := false
        for b in blockers:
            var bv: Vector4 = b
            if (x - bv.x) * (x - bv.x) + (y - bv.y) * (y - bv.y) + (z - bv.z) * (z - bv.z) <= bv.w * bv.w:
                blocked = true
                break
        if blocked:
            continue
        if _sealed_corner_touches_sealed_cell(x, y, z, s):
            continue
        var m: float = _regen_mult[i]
        if m <= 0.0:
            continue
        # P4: compressive tissue grows faster where the void is crowded by
        # solid neighbours, so narrow tunnels pinch shut before broad rooms.
        if _tissue[mini(x, s - 1) + mini(y, s - 1) * s + mini(z, s - 1) * s * s] == 0:
            m *= crowd_growth_factor(_solid_neighbours(x, y, z, n))
        _density[i] = minf(orig, cur + rate * m * delta)
        if _density[i] >= orig:
            healed += 1
        changed = true
    if healed > 0:
        var keep := PackedInt32Array()
        for k in range(_regen_idx.size()):
            var i: int = _regen_idx[k]
            if _density[i] < _original_density[i]:
                keep.append(i)
        _regen_idx = keep
    if changed:
        _dirty = true

## P4 neighbourhood growth term for compressive tissue. Extra regen gain for
## an empty corner with this many solid face neighbours (0..6): a wide room
## (0-1 solid) keeps the base rate, a one-corner tunnel (4+) grows ~2.5x.
const CROWD_GAIN := 1.5
static func crowd_growth_factor(solid_neighbours: int) -> float:
    return 1.0 + CROWD_GAIN * clampf(float(solid_neighbours - 1) / 3.0, 0.0, 1.0)

func _solid_neighbours(x: int, y: int, z: int, n: int) -> int:
    var iso := config.iso_level
    var c := 0
    if x > 0 and _density[i_of(x - 1, y, z, n)] >= iso: c += 1
    if x < n - 1 and _density[i_of(x + 1, y, z, n)] >= iso: c += 1
    if y > 0 and _density[i_of(x, y - 1, z, n)] >= iso: c += 1
    if y < n - 1 and _density[i_of(x, y + 1, z, n)] >= iso: c += 1
    if z > 0 and _density[i_of(x, y, z - 1, n)] >= iso: c += 1
    if z < n - 1 and _density[i_of(x, y, z + 1, n)] >= iso: c += 1
    return c

static func i_of(x: int, y: int, z: int, n: int) -> int:
    return x + y * n + z * n * n

## True if any of the (up to 8) cells sharing corner (x,y,z) is sealed. A
## sealed corner never regenerates, so sprayed tissue stays open permanently.
func _sealed_corner_touches_sealed_cell(x: int, y: int, z: int, s: int) -> bool:
    for dz in range(-1, 1):
        for dy in range(-1, 1):
            for dx in range(-1, 1):
                var cx := x + dx
                var cy := y + dy
                var cz := z + dz
                if cx < 0 or cy < 0 or cz < 0 or cx >= s or cy >= s or cz >= s:
                    continue
                if _sealed[_cell_index(cx, cy, cz)] != 0:
                    return true
    return false

func is_sealed_at_cell(x: int, y: int, z: int) -> bool:
    var s := config.chunk_size
    if x < 0 or y < 0 or z < 0 or x >= s or y >= s or z >= s:
        return false
    return _sealed[_cell_index(x, y, z)] != 0

func seal_cell(x: int, y: int, z: int) -> void:
    var s := config.chunk_size
    if x < 0 or y < 0 or z < 0 or x >= s or y >= s or z >= s:
        return
    _sealed[_cell_index(x, y, z)] = 1
    _any_sealed = true

## Call after writing _tissue directly: drops the cached per-tissue tables.
func tissue_changed() -> void:
    _regen_mult_dirty = true
    _regen_scan = true
    _has_contractile_tissue = -1
    _contract_list_age = 999.0

func is_dirty() -> bool:
    return _dirty

## Padded corner density, coords -1..s (size s+2 per axis).
func _build_padded(s: int) -> PackedFloat32Array:
    var n := s + 1
    var p := s + 2
    var out := PackedFloat32Array()
    out.resize(p * p * p)
    var base := chunk_coord * s
    for z in range(-1, s + 1):
        for y in range(-1, s + 1):
            var inside_yz := y >= 0 and z >= 0 and y < n and z < n
            for x in range(-1, s + 1):
                var v: float
                if inside_yz and x >= 0 and x < n:
                    v = _density[x + y * n + z * n * n]
                    if _has_contract:
                        v += _contract[x + y * n + z * n * n]
                elif field != null:
                    v = field.corner_density_global(base + Vector3i(x, y, z))
                else:
                    v = 1.0
                out[(x + 1) + (y + 1) * p + (z + 1) * p * p] = v
    return out

## Remeshes the chunk. `force_collision` rebuilds the collider now even for
## pure regrowth (start-up, capture tools).
func remesh(force_collision: bool = false) -> float:
    var start_usec := Time.get_ticks_usec()
    var s := config.chunk_size
    var cs := config.cell_size
    var iso := config.iso_level
    var p := s + 2
    var pp := p * p
    var d := _build_padded(s)
    var t_density := Time.get_ticks_usec()

    var first_solid := d[0] >= iso
    var uniform := true
    for i in range(d.size()):
        if (d[i] >= iso) != first_solid:
            uniform = false
            break

    # one bucket per tissue id, so each can get its own textured surface
    var n_tissues := FDKChunk.TISSUE_TEXTURES.size()
    var verts: Array = []
    var normals: Array = []
    var uvs: Array = []
    for i in range(n_tissues):
        verts.append(PackedVector3Array())
        normals.append(PackedVector3Array())
        uvs.append(PackedVector2Array())
    var all_verts := PackedVector3Array() # for the single collision shape

    if not uniform:
        var cp := s + 1
        var cell_vert := PackedVector3Array()
        cell_vert.resize(cp * cp * cp)
        var cell_has := PackedByteArray()
        cell_has.resize(cp * cp * cp)
        var gbase := chunk_coord * s
        for cz in range(cp):
            for cy in range(cp):
                for cx in range(cp):
                    var i0 := cx + cy * p + cz * pp
                    var c000 := d[i0]
                    var c100 := d[i0 + 1]
                    var c010 := d[i0 + p]
                    var c110 := d[i0 + p + 1]
                    var c001 := d[i0 + pp]
                    var c101 := d[i0 + pp + 1]
                    var c011 := d[i0 + pp + p]
                    var c111 := d[i0 + pp + p + 1]
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
                            sum += (ed[2] as Vector3).lerp(ed[3], t)
                            cnt += 1
                    var local := sum / float(cnt)
                    var gx := gbase.x + cx - 1
                    var gy := gbase.y + cy - 1
                    var gz := gbase.z + cz - 1
                    local += Vector3(
                        FDKLowPoly.hash3(gx, gy, gz) - 0.5,
                        FDKLowPoly.hash3(gy, gz, gx) - 0.5,
                        FDKLowPoly.hash3(gz, gx, gy) - 0.5) * 2.0 * config.facet_jitter
                    var ci := cx + cy * cp + cz * cp * cp
                    cell_vert[ci] = (Vector3(cx - 1, cy - 1, cz - 1) + local) * cs
                    cell_has[ci] = 1
        for z in range(s):
            for y in range(s):
                for x in range(s):
                    var i0 := (x + 1) + (y + 1) * p + (z + 1) * pp
                    var a0 := d[i0] >= iso
                    if a0 != (d[i0 + 1] >= iso):
                        _emit_quad(verts, normals, uvs, all_verts, cell_vert, cell_has, cp,
                            Vector3i(x, y - 1, z - 1), Vector3i(x, y, z - 1), Vector3i(x, y, z), Vector3i(x, y - 1, z),
                            Vector3(1, 0, 0) * (1.0 if a0 else -1.0), x if a0 else x + 1, y, z)
                    if a0 != (d[i0 + p] >= iso):
                        _emit_quad(verts, normals, uvs, all_verts, cell_vert, cell_has, cp,
                            Vector3i(x - 1, y, z - 1), Vector3i(x, y, z - 1), Vector3i(x, y, z), Vector3i(x - 1, y, z),
                            Vector3(0, 1, 0) * (1.0 if a0 else -1.0), x, y if a0 else y + 1, z)
                    if a0 != (d[i0 + pp] >= iso):
                        _emit_quad(verts, normals, uvs, all_verts, cell_vert, cell_has, cp,
                            Vector3i(x - 1, y - 1, z), Vector3i(x, y - 1, z), Vector3i(x, y, z), Vector3i(x - 1, y, z),
                            Vector3(0, 0, 1) * (1.0 if a0 else -1.0), x, y, z if a0 else z + 1)

    var t_mesh := Time.get_ticks_usec()
    var mesh := ArrayMesh.new()
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
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        mesh.surface_set_material(mesh.get_surface_count() - 1, FDKChunk.terrain_material(i))

    _mesh_instance.mesh = mesh if have_any else null
    if not have_any:
        all_verts = PackedVector3Array()
    var t_arraymesh := Time.get_ticks_usec()

    if force_collision or field == null or _needs_immediate_collision(d):
        _apply_collision(all_verts, d)
    else:
        if not _coll_pending:
            _coll_pending_age = 0.0
        _coll_pending = true
        _pending_faces = all_verts
        _pending_density = d
    var t_end := Time.get_ticks_usec()

    _dirty = false
    var elapsed_ms := (t_end - start_usec) / 1000.0
    last_stats = {
        "density_ms": (t_density - start_usec) / 1000.0,
        "mesh_ms": (t_mesh - t_density) / 1000.0,
        "arraymesh_ms": (t_arraymesh - t_mesh) / 1000.0,
        "collider_ms": (t_end - t_arraymesh) / 1000.0,
        "total_ms": elapsed_ms,
    }
    remeshed.emit(elapsed_ms)
    return elapsed_ms

## True when the collider must follow this remesh at once: first build, any
## padded corner lower than the collider's (tissue removed -- the player must
## be able to walk into a fresh hole), or growth inside the field's guard
## sphere around the player.
func _needs_immediate_collision(d: PackedFloat32Array) -> bool:
    if _coll_density.size() != d.size():
        return true
    var p := config.chunk_size + 2
    var pp := p * p
    var guard := Vector4(0, 0, 0, -1.0)
    if field != null and field.has_method("collision_guard_local"):
        guard = field.collision_guard_local(self)
    var g2 := guard.w * guard.w
    for i in range(d.size()):
        var v: float = d[i]
        var o: float = _coll_density[i]
        if v == o:
            continue
        if v < o:
            return true
        if guard.w > 0.0:
            var gx := float(i % p - 1) - guard.x
            var gy := float((i / p) % p - 1) - guard.y
            var gz := float(i / pp - 1) - guard.z
            if gx * gx + gy * gy + gz * gz <= g2:
                return true
    return false

func _apply_collision(faces: PackedVector3Array, d: PackedFloat32Array) -> void:
    if faces.is_empty():
        _collision.shape = null
    else:
        var shape := ConcavePolygonShape3D.new()
        shape.set_faces(faces)
        _collision.shape = shape
    _coll_density = d
    _coll_pending = false
    _coll_pending_age = 0.0
    _pending_faces = PackedVector3Array()
    _pending_density = PackedFloat32Array()

## True while the collider lags behind the visual mesh (regrowth only).
func is_collision_pending() -> bool:
    return _coll_pending

## Builds the parked regrowth collider now. Returns true if one was built.
func flush_collision() -> bool:
    if not _coll_pending:
        return false
    _apply_collision(_pending_faces, _pending_density)
    return true

## Emits one quad (two flat triangles) into the tissue-appropriate bucket,
## joining 4 cell vertices around a crossing edge. `outward` points from
## solid toward empty. (tx,ty,tz) is the solid-side corner (used to pick the
## tissue and to build a world-aligned UV using the two axes closest to the
## face plane, which keeps texel size roughly constant across the terrain).
func _emit_quad(verts: Array, normals: Array, uvs: Array, all_verts: PackedVector3Array,
        cell_vert: PackedVector3Array, cell_has: PackedByteArray, cp: int,
        c0: Vector3i, c1: Vector3i, c2: Vector3i, c3: Vector3i, outward: Vector3,
        tx: int, ty: int, tz: int) -> void:
    var i0 := (c0.x + 1) + (c0.y + 1) * cp + (c0.z + 1) * cp * cp
    var i1 := (c1.x + 1) + (c1.y + 1) * cp + (c1.z + 1) * cp * cp
    var i2 := (c2.x + 1) + (c2.y + 1) * cp + (c2.z + 1) * cp * cp
    var i3 := (c3.x + 1) + (c3.y + 1) * cp + (c3.z + 1) * cp * cp
    if cell_has[i0] == 0 or cell_has[i1] == 0 or cell_has[i2] == 0 or cell_has[i3] == 0:
        return
    var v0 := cell_vert[i0]
    var v1 := cell_vert[i1]
    var v2 := cell_vert[i2]
    var v3 := cell_vert[i3]
    var s := config.chunk_size
    var tissue := get_tissue_at_cell(clampi(tx, 0, s - 1), clampi(ty, 0, s - 1), clampi(tz, 0, s - 1))
    if _any_sealed:
        # the empty cell this face looks into was sprayed: show melted flesh
        var ex := clampi(tx + int(round(outward.x)), 0, s - 1)
        var ey := clampi(ty + int(round(outward.y)), 0, s - 1)
        var ez := clampi(tz + int(round(outward.z)), 0, s - 1)
        if _sealed[_cell_index(ex, ey, ez)] != 0:
            tissue = FDKTissueRules.MELTED
    # world-aligned planar UV: pick the two axes with the least outward
    # component (i.e. the plane the face roughly lies in)
    var ax := absf(outward.x)
    var ay := absf(outward.y)
    var az := absf(outward.z)
    var world_off := chunk_coord * s * config.cell_size
    var uv0: Vector2
    var uv1: Vector2
    var uv2: Vector2
    var uv3: Vector2
    if ax >= ay and ax >= az:
        uv0 = Vector2((v0 + world_off).z, (v0 + world_off).y)
        uv1 = Vector2((v1 + world_off).z, (v1 + world_off).y)
        uv2 = Vector2((v2 + world_off).z, (v2 + world_off).y)
        uv3 = Vector2((v3 + world_off).z, (v3 + world_off).y)
    elif ay >= ax and ay >= az:
        uv0 = Vector2((v0 + world_off).x, (v0 + world_off).z)
        uv1 = Vector2((v1 + world_off).x, (v1 + world_off).z)
        uv2 = Vector2((v2 + world_off).x, (v2 + world_off).z)
        uv3 = Vector2((v3 + world_off).x, (v3 + world_off).z)
    else:
        uv0 = Vector2((v0 + world_off).x, (v0 + world_off).y)
        uv1 = Vector2((v1 + world_off).x, (v1 + world_off).y)
        uv2 = Vector2((v2 + world_off).x, (v2 + world_off).y)
        uv3 = Vector2((v3 + world_off).x, (v3 + world_off).y)
    all_verts.append(v0); all_verts.append(v1); all_verts.append(v2)
    all_verts.append(v0); all_verts.append(v2); all_verts.append(v3)
    _tri(verts[tissue], normals[tissue], uvs[tissue], v0, v1, v2, uv0, uv1, uv2, outward)
    _tri(verts[tissue], normals[tissue], uvs[tissue], v0, v2, v3, uv0, uv2, uv3, outward)

func _tri(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array,
        a: Vector3, b: Vector3, c: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2, outward: Vector3) -> void:
    var n := (b - a).cross(c - a)
    if n.length_squared() < 1e-12:
        return
    if n.dot(outward) > 0.0:
        var tmp_v := b
        b = c
        c = tmp_v
        var tmp_uv := uvb
        uvb = uvc
        uvc = tmp_uv
        n = -n
    var nn := -n.normalized()
    verts.append(a); verts.append(b); verts.append(c)
    normals.append(nn); normals.append(nn); normals.append(nn)
    uvs.append(uva); uvs.append(uvb); uvs.append(uvc)

func serialize() -> Dictionary:
    return {
        "chunk_coord": [chunk_coord.x, chunk_coord.y, chunk_coord.z],
        "density": Array(_density),
        "tissue": Array(_tissue),
        "sealed": Array(_sealed),
        "boost": _boost_sparse(),
    }

func _boost_sparse() -> Array:
    var out: Array = []
    for i in range(_boost.size()):
        if _boost[i] > 1.0:
            out.append([i, _boost[i]])
    return out

func deserialize(data: Dictionary) -> void:
    var dd: Array = data.get("density", [])
    var t: Array = data.get("tissue", [])
    var sl: Array = data.get("sealed", [])
    for i in range(min(dd.size(), _density.size())):
        _density[i] = float(dd[i])
    for i in range(min(t.size(), _tissue.size())):
        _tissue[i] = int(t[i])
    for i in range(min(sl.size(), _sealed.size())):
        _sealed[i] = int(sl[i])
    _any_sealed = _sealed.has(1)
    for e in (data.get("boost", []) as Array):
        set_corner_boost(int(e[0]), float(e[1]))
    tissue_changed()
    _dirty = true
