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
var _mesh_snapshot: Dictionary = {}
var _mesh_missing_snapshot: Dictionary = {}
var _reading_mesh_snapshot := false
var _mesh_batch: Array = []
var _mesh_batch_cursor := 0
var _dig_epoch: int = 0
var _mesh_snapshot_epoch: int = 0

func get_dig_epoch() -> int:
    return _dig_epoch

func get_mesh_snapshot_epoch() -> int:
    return _mesh_snapshot_epoch
var _mesh_groups: Array = []
var _mesh_group_for: Dictionary = {}
var _mesh_group_remaining: Dictionary = {}
const SolidVolume = preload("res://addons/flesh_dig_kit/terrain/fdk_solid_volume.gd")
var _solid_volume
var _surface_patch: FDKSurfacePatch = null
var _surface_patch_cell := Vector3i.ZERO
var _surface_patch_min := Vector3i.ZERO
var _surface_patch_max := Vector3i.ZERO
var _surface_patch_revision := 0
var _surface_patch_state: Array = []
var _surface_patch_required_epoch: int = 0
var _surface_patch_is_aggregate: bool = false
var _surface_patch_tiles: Dictionary = {}

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        _clear_surface_patch()

func get_surface_patch_required_epoch() -> int:
    return _surface_patch_required_epoch

func _clear_surface_patch() -> void:
    _surface_patch_required_epoch = 0
    _surface_patch_is_aggregate = false
    for t_info in _surface_patch_tiles.values():
        var p: Object = t_info.get("patch", null)
        if is_instance_valid(p):
            if p.get_parent() != null:
                p.get_parent().remove_child(p)
            p.free()
    _surface_patch_tiles.clear()
    if _surface_patch != null:
        if _surface_patch.has_method("clear_tile_children"):
            _surface_patch.clear_tile_children()
        if _surface_patch.is_inside_tree():
            _surface_patch.get_parent().remove_child(_surface_patch)
        _surface_patch.free()
        _surface_patch = null
        _surface_patch_cell = Vector3i.ZERO
        _surface_patch_min = Vector3i.ZERO
        _surface_patch_max = Vector3i.ZERO
        _surface_patch_revision += 1
        _surface_patch_state.clear()

func _check_tear_fully_solid(tear_cell: Vector3i) -> bool:
    var s := config.chunk_size
    var iso := config.iso_level
    for kz in range(4):
        for ky in range(4):
            for kx in range(4):
                var gcorner := tear_cell - Vector3i.ONE + Vector3i(kx, ky, kz)
                var cc := Vector3i(_floordiv(gcorner.x, s), _floordiv(gcorner.y, s), _floordiv(gcorner.z, s))
                var chunk: FDKChunk = _chunks.get(cc, null)
                if chunk == null:
                    return false
                if corner_density_global(gcorner) < iso:
                    return false
    return true

func _compute_patch_state_region(min_cell: Vector3i, max_cell: Vector3i) -> Array:
    var state: Array = []
    var span_x := max_cell.x - min_cell.x + 1
    var span_y := max_cell.y - min_cell.y + 1
    var span_z := max_cell.z - min_cell.z + 1
    if span_x < 1 or span_x > 7 or span_y < 1 or span_y > 7 or span_z < 1 or span_z > 7:
        return state
    var nx := span_x + 1
    var ny := span_y + 1
    var nz := span_z + 1
    state.append(min_cell)
    state.append(max_cell)
    state.append(config.cell_size)
    state.append(config.iso_level)
    state.append(config.facet_jitter)
    for kz in range(nz):
        for ky in range(ny):
            for kx in range(nx):
                var gcorner := min_cell + Vector3i(kx, ky, kz)
                state.append(corner_density_global(gcorner))
    var s := config.chunk_size
    for cz in range(span_z):
        for cy in range(span_y):
            for cx in range(span_x):
                var gcell := min_cell + Vector3i(cx, cy, cz)
                var cc := Vector3i(_floordiv(gcell.x, s), _floordiv(gcell.y, s), _floordiv(gcell.z, s))
                var chunk: FDKChunk = _chunks.get(cc, null)
                var tissue := 0
                var sealed := false
                if chunk != null:
                    var lc := gcell - cc * s
                    tissue = chunk.get_tissue_at_cell(clampi(lc.x, 0, s - 1), clampi(lc.y, 0, s - 1), clampi(lc.z, 0, s - 1))
                    sealed = chunk.is_sealed_at_cell(clampi(lc.x, 0, s - 1), clampi(lc.y, 0, s - 1), clampi(lc.z, 0, s - 1))
                state.append(tissue)
                state.append(sealed)
    state.append(surface_constraint)
    return state

func _compute_patch_state(center: Vector3i) -> Array:
    return _compute_patch_state_region(center - Vector3i.ONE, center + Vector3i.ONE)

func _get_tile_origins_reading_corner(gcorner: Vector3i) -> Array[Vector3i]:
    var tx0 := int(floor(float(gcorner.x - 1) / 4.0)) * 4
    var tx1 := int(floor(float(gcorner.x + 1) / 4.0)) * 4
    var ty0 := int(floor(float(gcorner.y - 1) / 4.0)) * 4
    var ty1 := int(floor(float(gcorner.y + 1) / 4.0)) * 4
    var tz0 := int(floor(float(gcorner.z - 1) / 4.0)) * 4
    var tz1 := int(floor(float(gcorner.z + 1) / 4.0)) * 4
    var xs := [tx0] if tx0 == tx1 else [tx0, tx1]
    var ys := [ty0] if ty0 == ty1 else [ty0, ty1]
    var zs := [tz0] if tz0 == tz1 else [tz0, tz1]
    var res: Array[Vector3i] = []
    for z in zs:
        for y in ys:
            for x in xs:
                res.append(Vector3i(x, y, z))
    return res

func _get_tile_origins_for_cell(cell: Vector3i) -> Array[Vector3i]:
    var tile_dict: Dictionary = {}
    for dz in range(2):
        for dy in range(2):
            for dx in range(2):
                var gc := cell + Vector3i(dx, dy, dz)
                for to in _get_tile_origins_reading_corner(gc):
                    tile_dict[to] = true
    var res: Array[Vector3i] = []
    for to in tile_dict.keys():
        res.append(to)
    return res

func _is_tile_published(tile_origin: Vector3i, required_epoch: int) -> bool:
    var info: Dictionary = _surface_patch_tiles.get(tile_origin, {})
    if not info.is_empty() and info.patch.faces.is_empty():
        return _compute_tile_state(tile_origin) == info.state
    var s := config.chunk_size
    var iso := config.iso_level
    var min_corner := tile_origin - Vector3i.ONE
    for kz in range(6):
        for ky in range(6):
            for kx in range(6):
                var gcorner := min_corner + Vector3i(kx, ky, kz)
                # Read the actual edge owner's published padding, including
                # corners whose canonical provider has not streamed in yet.
                var owner_cell := Vector3i(clampi(gcorner.x, tile_origin.x, tile_origin.x + 3), clampi(gcorner.y, tile_origin.y, tile_origin.y + 3), clampi(gcorner.z, tile_origin.z, tile_origin.z + 3))
                var cc := Vector3i(_floordiv(owner_cell.x, s), _floordiv(owner_cell.y, s), _floordiv(owner_cell.z, s))
                var chunk: FDKChunk = _chunks.get(cc, null)
                if chunk == null or chunk._surface_density.is_empty():
                    return false
                var lc := gcorner - cc * s
                var published_d := chunk.get_published_corner_density(lc.x, lc.y, lc.z)
                var current_d := corner_density_global(gcorner)
                if (published_d >= iso) != (current_d >= iso):
                    return false
                if absf(published_d - current_d) > 0.00001:
                    if chunk._surface_edit_epoch < required_epoch:
                        return false
    return true

func _compute_tile_state(tile_origin: Vector3i) -> Array:
    var state: Array = []
    state.append(tile_origin)
    state.append(config.cell_size)
    state.append(config.iso_level)
    state.append(config.facet_jitter)
    var min_corner := tile_origin - Vector3i.ONE
    for kz in range(6):
        for ky in range(6):
            for kx in range(6):
                var gcorner := min_corner + Vector3i(kx, ky, kz)
                state.append(corner_density_global(gcorner))
    var s := config.chunk_size
    for cz in range(5):
        for cy in range(5):
            for cx in range(5):
                var gcell := tile_origin - Vector3i.ONE + Vector3i(cx, cy, cz)
                var cc := Vector3i(_floordiv(gcell.x, s), _floordiv(gcell.y, s), _floordiv(gcell.z, s))
                var chunk: FDKChunk = _chunks.get(cc, null)
                var tissue := 0
                var sealed := false
                if chunk != null:
                    var lc := gcell - cc * s
                    tissue = chunk.get_tissue_at_cell(clampi(lc.x, 0, s - 1), clampi(lc.y, 0, s - 1), clampi(lc.z, 0, s - 1))
                    sealed = chunk.is_sealed_at_cell(clampi(lc.x, 0, s - 1), clampi(lc.y, 0, s - 1), clampi(lc.z, 0, s - 1))
                state.append(tissue)
                state.append(sealed)
    state.append(surface_constraint)
    return state

func _rebuild_aggregate_tiles(new_tile_states: Dictionary = {}) -> void:
    if _surface_patch == null:
        return
    _surface_patch.faces = PackedVector3Array()
    _surface_patch.mesh = null
    var sorted_origins := _surface_patch_tiles.keys()
    sorted_origins.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
        if a.z != b.z: return a.z < b.z
        if a.y != b.y: return a.y < b.y
        return a.x < b.x
    )
    for origin in sorted_origins:
        var t_info: Dictionary = _surface_patch_tiles[origin]
        var patch: FDKSurfacePatch = t_info.patch
        patch.build_tile(origin)
        if new_tile_states.has(origin):
            t_info.state = new_tile_states[origin]
        else:
            t_info.state = _compute_tile_state(origin)
        if patch.faces.size() > 0:
            if _surface_patch.has_method("add_tile_child"):
                _surface_patch.add_tile_child(origin, patch)
            else:
                if patch.get_parent() != _surface_patch:
                    _surface_patch.add_child(patch)
            _surface_patch.faces.append_array(patch.faces)
        else:
            if patch.get_parent() == _surface_patch:
                _surface_patch.remove_child(patch)
    _surface_patch_revision += 1
    if _surface_patch.faces.is_empty():
        _clear_surface_patch()

func _refresh_or_clear_aggregate_patch() -> void:
    if _surface_patch_tiles.is_empty():
        _clear_surface_patch()
        return

    var all_published := true
    for origin in _surface_patch_tiles.keys():
        var t_info: Dictionary = _surface_patch_tiles[origin]
        if not _is_tile_published(origin, t_info.required_epoch):
            all_published = false
            break

    if all_published:
        _clear_surface_patch()
        return

    var any_state_changed := false
    var new_states: Dictionary = {}
    for origin in _surface_patch_tiles.keys():
        var s := _compute_tile_state(origin)
        new_states[origin] = s
        if s != _surface_patch_tiles[origin].state:
            any_state_changed = true

    if any_state_changed:
        _rebuild_aggregate_tiles(new_states)

func _handle_aggregate_dig(tear_cell: Vector3i, union_min: Vector3i, union_max: Vector3i) -> void:
    var prev_min := _surface_patch_min
    var prev_max := _surface_patch_max
    _surface_patch_min = union_min
    _surface_patch_max = union_max
    _surface_patch_required_epoch = _dig_epoch

    if not _surface_patch_is_aggregate:
        _surface_patch_is_aggregate = true
        _surface_patch.mesh = null
        if _surface_patch.has_method("clear_tile_children"):
            _surface_patch.clear_tile_children()
        _surface_patch_tiles.clear()

        var old_tile_dict: Dictionary = {}
        for kz in range(prev_min.z, prev_max.z + 2):
            for ky in range(prev_min.y, prev_max.y + 2):
                for kx in range(prev_min.x, prev_max.x + 2):
                    var gc := Vector3i(kx, ky, kz)
                    if corner_density_global(gc) < 0.9999:
                        for to in _get_tile_origins_reading_corner(gc):
                            old_tile_dict[to] = true
        for to in _get_tile_origins_for_cell(_surface_patch_cell):
            old_tile_dict[to] = true

        for to in old_tile_dict.keys():
            var p := FDKSurfacePatch.new(self)
            _surface_patch_tiles[to] = {
                "patch": p,
                "required_epoch": _surface_patch_required_epoch,
                "state": []
            }

    var new_origins := _get_tile_origins_for_cell(tear_cell)
    for to in new_origins:
        if not _surface_patch_tiles.has(to):
            var p := FDKSurfacePatch.new(self)
            _surface_patch_tiles[to] = {
                "patch": p,
                "required_epoch": _dig_epoch,
                "state": []
            }
        else:
            _surface_patch_tiles[to].required_epoch = _dig_epoch

    _rebuild_aggregate_tiles()

func _refresh_or_clear_surface_patch() -> void:
    if _surface_patch == null:
        return
    if _surface_patch_is_aggregate:
        _refresh_or_clear_aggregate_patch()
        return
    var s := config.chunk_size
    var iso := config.iso_level
    var span_x := _surface_patch_max.x - _surface_patch_min.x + 1
    var span_y := _surface_patch_max.y - _surface_patch_min.y + 1
    var span_z := _surface_patch_max.z - _surface_patch_min.z + 1
    if span_x < 1 or span_x > 7 or span_y < 1 or span_y > 7 or span_z < 1 or span_z > 7:
        _clear_surface_patch()
        return
    var nx := span_x + 1
    var ny := span_y + 1
    var nz := span_z + 1
    var all_published := true
    for kz in range(nz):
        if not all_published:
            break
        for ky in range(ny):
            if not all_published:
                break
            for kx in range(nx):
                var gcorner := _surface_patch_min + Vector3i(kx, ky, kz)
                var cc := Vector3i(_floordiv(gcorner.x, s), _floordiv(gcorner.y, s), _floordiv(gcorner.z, s))
                var chunk: FDKChunk = _chunks.get(cc, null)
                if chunk == null or chunk._surface_density.is_empty():
                    all_published = false
                    break
                var lc := gcorner - cc * s
                var published_d := chunk.get_published_corner_density(lc.x, lc.y, lc.z)
                var current_d := corner_density_global(gcorner)
                if (published_d >= iso) != (current_d >= iso):
                    all_published = false
                    break
                if absf(published_d - current_d) > 0.00001:
                    if chunk._surface_edit_epoch < _surface_patch_required_epoch:
                        all_published = false
                        break
    if all_published:
        _clear_surface_patch()
        return
    var new_state := _compute_patch_state_region(_surface_patch_min, _surface_patch_max)
    if new_state != _surface_patch_state:
        _surface_patch_state = new_state
        _surface_patch.build_region(_surface_patch_min, _surface_patch_max)
        _surface_patch_revision += 1
        if _surface_patch.faces.is_empty():
            _clear_surface_patch()

func _update_solid_volume(eye: Vector3) -> void:
    if _solid_volume == null:
        _solid_volume = SolidVolume.new()
        _solid_volume.field = self
        add_child(_solid_volume)
    var started := Time.get_ticks_usec()
    _solid_volume.update_eye(eye)
    _solid_volume.last_prepare_us = Time.get_ticks_usec()-started

## Local filled-mass contact for an eye proven inside solid mass. Ordinary
func solid_contact_ray(from: Vector3, to: Vector3) -> Dictionary:
    _refresh_or_clear_surface_patch()
    _update_solid_volume(from)
    var hit_vol: Dictionary = _solid_volume.contact_ray(from, to)
    var hit_patch: Dictionary = {}
    if _surface_patch != null and not _surface_patch.faces.is_empty():
        hit_patch = _surface_patch.contact_ray(from, to)
    if not hit_vol.is_empty() and not hit_patch.is_empty():
        var d_vol: float = from.distance_to(hit_vol.position)
        var d_patch: float = from.distance_to(hit_patch.position)
        return hit_patch if d_patch < d_vol else hit_vol
    elif not hit_patch.is_empty():
        return hit_patch
    return hit_vol

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
    _refresh_or_clear_surface_patch()
    var done := 0
    var start := Time.get_ticks_usec()
    if _mesh_batch.is_empty():
        _begin_mesh_batch()
    while _mesh_batch_cursor < _mesh_batch.size():
        var chunk: FDKChunk = _mesh_batch[_mesh_batch_cursor]
        _reading_mesh_snapshot = true
        chunk.remesh(false, true)
        _reading_mesh_snapshot = false
        var group_id: int = _mesh_group_for[chunk.chunk_coord]
        _mesh_group_remaining[group_id] -= 1
        if _mesh_group_remaining[group_id] == 0:
            for ready in _mesh_groups[group_id]:
                ready.publish_staged_mesh()
            _refresh_or_clear_surface_patch()
        _mesh_batch_cursor += 1
        done += 1
        if done >= remesh_budget_per_frame or (Time.get_ticks_usec() - start) / 1000.0 >= remesh_ms_per_frame * 0.5:
            break
    if not _mesh_batch.is_empty() and _mesh_batch_cursor == _mesh_batch.size():
        _mesh_batch.clear()
        _mesh_snapshot.clear()
        _mesh_missing_snapshot.clear()
    step_collision(delta)
    _refresh_or_clear_surface_patch()

## Keep the old closed surface until all meshes that share changed cells are
## ready. Density changes arriving during this bounded batch stay dirty for
## the next batch; continuous regeneration must never restart work in flight.
func _begin_mesh_batch() -> void:
    var targets := {}
    var links := {}
    var s := config.chunk_size
    var n := s + 1
    for chunk in _chunks.values():
        if not chunk.is_dirty():
            continue
        targets[chunk.chunk_coord] = chunk
        if not links.has(chunk.chunk_coord):
            links[chunk.chunk_coord] = {}
        var source: PackedFloat32Array = chunk.effective_density()
        var changed_indices: PackedInt32Array = range(source.size()) if chunk._regen_scan or chunk._mesh_source.is_empty() or not chunk._contract.is_empty() else chunk._regen_idx
        if not chunk._mesh_regen_indices.is_empty():
            changed_indices = changed_indices.duplicate()
            changed_indices.append_array(chunk._mesh_regen_indices)
        for i in changed_indices:
            if chunk._mesh_source.size() == source.size() and source[i] == chunk._mesh_source[i]:
                continue
            var local := Vector3i(i % n, (i / n) % n, i / (n * n))
            if local.x > 0 and local.x < s - 1 and local.y > 0 and local.y < s - 1 and local.z > 0 and local.z < s - 1:
                continue
            var g: Vector3i = chunk.chunk_coord * s + local
            # A mesh reads corners -1..s. Include padding readers even if
            # they do not store the changed corner themselves.
            for z in range(-1, 2):
                for y in range(-1, 2):
                    for x in range(-1, 2):
                        var cc: Vector3i = chunk.chunk_coord + Vector3i(x, y, z)
                        var p: Vector3i = g - cc * s
                        if p.x < -1 or p.y < -1 or p.z < -1 or p.x > s or p.y > s or p.z > s:
                            continue
                        if _chunks.has(cc):
                            targets[cc] = _chunks[cc]
                            links[chunk.chunk_coord][cc] = true
                            if not links.has(cc): links[cc] = {}
                            links[cc][chunk.chunk_coord] = true
    if targets.is_empty():
        return
    _mesh_snapshot_epoch = _dig_epoch
    # Capture only the target meshes' density providers, not the whole world.
    for cc in targets.keys():
        for z in range(-1, 2):
            for y in range(-1, 2):
                for x in range(-1, 2):
                    var provider: Vector3i = cc + Vector3i(x, y, z)
                    if _chunks.has(provider) and not _mesh_snapshot.has(provider):
                        _mesh_snapshot[provider] = _chunks[provider].effective_density()
                    elif not _chunks.has(provider):
                        # Freeze only the absent provider's corners actually
                        # read by this target (-1..s), without generating it.
                        var base: Vector3i = cc * s
                        var lo := base + Vector3i(-1 if x < 0 else (s if x > 0 else 0), -1 if y < 0 else (s if y > 0 else 0), -1 if z < 0 else (s if z > 0 else 0))
                        var hi := lo + Vector3i(s if x == 0 else 1, s if y == 0 else 1, s if z == 0 else 1)
                        for gz in range(lo.z, hi.z):
                            for gy in range(lo.y, hi.y):
                                for gx in range(lo.x, hi.x):
                                    var g := Vector3i(gx, gy, gz)
                                    if not _mesh_missing_snapshot.has(g):
                                        _mesh_missing_snapshot[g] = float(density_sampler.call(Vector3(g) * config.cell_size)) if density_sampler.is_valid() else 1.0
    _mesh_batch = targets.values()
    _mesh_batch.sort_custom(func(a, b): return _urgent_chunks.has(a.chunk_coord) and not _urgent_chunks.has(b.chunk_coord))
    _mesh_batch_cursor = 0
    _mesh_groups.clear()
    _mesh_group_for.clear()
    _mesh_group_remaining.clear()
    # Separate holes can publish independently. Only the meshes connected
    # through a changed shared cell wait for one another.
    for chunk in _mesh_batch:
        if _mesh_group_for.has(chunk.chunk_coord): continue
        var id := _mesh_groups.size()
        var group: Array = []
        var pending: Array = [chunk.chunk_coord]
        _mesh_group_for[chunk.chunk_coord] = id
        while not pending.is_empty():
            var cc: Vector3i = pending.pop_back()
            group.append(targets[cc])
            for neighbor in links.get(cc, {}).keys():
                if not _mesh_group_for.has(neighbor):
                    _mesh_group_for[neighbor] = id
                    pending.append(neighbor)
        _mesh_groups.append(group)
        _mesh_group_remaining[id] = group.size()
    for chunk in _mesh_batch:
        chunk._dirty = false
        chunk._mesh_source = _mesh_snapshot[chunk.chunk_coord]
        chunk._mesh_regen_indices = chunk._regen_idx.duplicate()
        _urgent_chunks.erase(chunk.chunk_coord)

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
    for chunk in _mesh_batch:
        chunk._dirty = true
    _mesh_batch.clear()
    _mesh_snapshot.clear()
    _mesh_missing_snapshot.clear()
    for chunk in _chunks.values():
        if chunk.is_dirty() or not chunk._staged_density.is_empty():
            chunk.remesh(true)
        elif chunk.is_collision_pending():
            chunk.flush_collision()
    _refresh_or_clear_surface_patch()

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
    if _reading_mesh_snapshot and _mesh_snapshot.has(cc):
        var l := g - cc * s
        var values: PackedFloat32Array = _mesh_snapshot[cc]
        return values[chunk._corner_index(l.x, l.y, l.z)]
    if _reading_mesh_snapshot:
        # Streaming + digging a neighbor during a batch must not inject its
        # live density into only the later meshes, even for a mutable sampler.
        return float(_mesh_missing_snapshot[g])
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
    var tear_cell: Vector3i = chunk_coord * config.chunk_size + (result[1] as Vector3i)
    var was_fully_solid := _check_tear_fully_solid(tear_cell)
    _dig_epoch += 1
    for dz in range(2):
        for dy in range(2):
            for dx in range(2):
                _add_corner_global(tear_cell + Vector3i(dx, dy, dz), -amount)
    if _surface_patch != null:
        var new_min := tear_cell - Vector3i.ONE
        var new_max := tear_cell + Vector3i.ONE
        var union_min := Vector3i(mini(_surface_patch_min.x, new_min.x), mini(_surface_patch_min.y, new_min.y), mini(_surface_patch_min.z, new_min.z))
        var union_max := Vector3i(maxi(_surface_patch_max.x, new_max.x), maxi(_surface_patch_max.y, new_max.y), maxi(_surface_patch_max.z, new_max.z))
        var span_x := union_max.x - union_min.x + 1
        var span_y := union_max.y - union_min.y + 1
        var span_z := union_max.z - union_min.z + 1
        if not _surface_patch_is_aggregate and span_x <= 7 and span_y <= 7 and span_z <= 7:
            _surface_patch_min = union_min
            _surface_patch_max = union_max
            _surface_patch_required_epoch = _dig_epoch
            _surface_patch.build_region(_surface_patch_min, _surface_patch_max)
            _surface_patch_revision += 1
            _surface_patch_state = _compute_patch_state_region(_surface_patch_min, _surface_patch_max)
            if _surface_patch.faces.is_empty():
                _clear_surface_patch()
        else:
            _handle_aggregate_dig(tear_cell, union_min, union_max)
    elif was_fully_solid:
        var patch := FDKSurfacePatch.new(self)
        _surface_patch_cell = tear_cell
        _surface_patch_min = tear_cell - Vector3i.ONE
        _surface_patch_max = tear_cell + Vector3i.ONE
        patch.build_region(_surface_patch_min, _surface_patch_max)
        if patch.faces.size() > 0:
            _surface_patch = patch
            _surface_patch_is_aggregate = false
            _surface_patch_revision += 1
            _surface_patch_required_epoch = _dig_epoch
            _surface_patch_state = _compute_patch_state_region(_surface_patch_min, _surface_patch_max)
            add_child(_surface_patch)
        else:
            patch.free()
            _surface_patch_min = Vector3i.ZERO
            _surface_patch_max = Vector3i.ZERO
            _surface_patch_required_epoch = 0

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

## Contact-driven eye clearance, leaving the body and desired hand-motion
## transform intact. Call after camera animation, before aiming/rendering.
## The anchor is the capsule center. Shallow full burial resolves only a real
## nearby surface, bounded by the eye offset; deep solid without such a
## contact cannot invent an empty destination or relocate the body.
func constrain_eye(desired_eye: Vector3, body_anchor: Vector3, near: float) -> Vector3:
    if not is_inside_tree():
        return desired_eye
    var offset := desired_eye - body_anchor
    var length := offset.length()
    if length < 0.00001:
        _update_solid_volume(desired_eye)
        return desired_eye
    var direction := offset / length
    var margin := 0.055 + maxf(near, 0.001) * 2.0 + 0.005
    var side := direction.cross(Vector3.UP)
    if side.length_squared() < 0.001:
        side = direction.cross(Vector3.RIGHT)
    side = side.normalized() * 0.001
    var other := direction.cross(side)
    var distance := length
    for epsilon in [Vector3.ZERO, side, -side, other, -other]:
        var hit := _eye_terrain_ray(body_anchor + epsilon, desired_eye + direction * margin + epsilon)
        if hit.is_empty() or _eye_surface_outward(hit).dot(direction) >= 0:
            continue
        distance = minf(distance, maxf(0.0, (hit.position - body_anchor - epsilon).dot(direction) - margin))
    if distance < length:
        var guarded := body_anchor + direction * distance
        _update_solid_volume(guarded)
        return guarded
    # Strong contraction can physically put the capsule and eye on the
    # solid side together. Resolve only a nearby real surface contact; this
    # never moves the body or searches for a remote escape destination.
    var closest := desired_eye
    var best := INF
    var limit := minf(0.85, length + 0.15)
    for z in range(-1, 2):
        for y in range(-1, 2):
            for x in range(-1, 2):
                if x == 0 and y == 0 and z == 0: continue
                var ray := Vector3(x, y, z).normalized()
                var hit := _eye_terrain_ray(desired_eye, desired_eye + ray * limit)
                if hit.is_empty(): continue
                var outward := _eye_surface_outward(hit)
                # Backface normals in intersect_ray are flipped toward the
                # ray. Read the triangle's actual solid-to-empty orientation.
                if outward.dot(ray) <= 0.0001: continue
                var candidate: Vector3 = hit.position + outward * margin
                var correction := candidate.distance_to(desired_eye)
                if correction < best and correction <= limit:
                    closest = candidate
                    best = correction
    _update_solid_volume(closest)
    return closest

func _eye_terrain_ray(from: Vector3, to: Vector3) -> Dictionary:
    _refresh_or_clear_surface_patch()
    var query := PhysicsRayQueryParameters3D.create(from, to)
    query.hit_back_faces = true
    # Props keep their own layers and behavior. They must not hide a terrain
    # contact from this terrain-only camera guard.
    var hit_phys := Dictionary()
    for attempt in range(16):
        var hit := get_world_3d().direct_space_state.intersect_ray(query)
        if hit.is_empty() or hit.collider.has_meta("fdk_terrain_chunk"):
            hit_phys = hit
            break
        var excluded := query.exclude
        excluded.append(hit.rid)
        query.exclude = excluded
    var hit_patch: Dictionary = {}
    if _surface_patch != null and not _surface_patch.faces.is_empty():
        hit_patch = _surface_patch.contact_ray(from, to)
    if not hit_phys.is_empty() and not hit_patch.is_empty():
        if from.distance_to(hit_patch.position) < from.distance_to(hit_phys.position):
            return hit_patch
        return hit_phys
    elif not hit_patch.is_empty():
        return hit_patch
    return hit_phys

func _eye_surface_outward(hit: Dictionary) -> Vector3:
    if hit.get("fdk_surface_patch", false):
        return hit.get("fdk_patch_outward", Vector3.ZERO)
    if hit.get("fdk_solid_volume", false):
        return hit.get("fdk_volume_outward", Vector3.ZERO)
    var chunk := hit.collider.get_parent() as FDKChunk
    if chunk == null or chunk._collision.shape == null:
        return Vector3.ZERO
    var index := int(hit.get("face_index", -1)) * 3
    var faces: PackedVector3Array = chunk._collision.shape.get_faces()
    if index < 0 or index + 2 >= faces.size():
        return Vector3.ZERO
    return -(faces[index + 1] - faces[index]).cross(faces[index + 2] - faces[index]).normalized()

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
    _clear_surface_patch()
    var chunks_data: Array = data.get("chunks", [])
    for entry in chunks_data:
        var coord_arr: Array = entry.get("chunk_coord", [0, 0, 0])
        var chunk_coord := Vector3i(int(coord_arr[0]), int(coord_arr[1]), int(coord_arr[2]))
        var chunk := get_or_create_chunk(chunk_coord)
        chunk.deserialize(entry)
