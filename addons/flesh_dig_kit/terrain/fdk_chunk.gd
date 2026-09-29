class_name FDKChunk
extends Node3D

## One cubic chunk of the density-grid terrain field.
##
## Meshing: surface nets. Every cell whose 8 corners straddle the iso level
## gets one vertex (average of its edge crossings, plus a small stable
## jitter so walls read as organic facets instead of a grid). Every corner
## edge that crosses the iso level emits one quad joining the 4 cells around
## it. Triangles never share vertices, so each gets its own flat normal:
## the faceted low-poly look. Vertex colors carry tissue type and a depth
## tone.
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
## Tissue id per cell (chunk_size^3). See TISSUE_COLORS.
var _tissue: PackedByteArray = PackedByteArray()
var _original_density: PackedFloat32Array = PackedFloat32Array()

var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D
var _static_body: StaticBody3D
var _dirty: bool = false

## 0 flesh, 1 nerve, 2 fat, 3 membrane (inedible, used around the restroom)
const TISSUE_COLORS: Array[Color] = [
    Color(0.72, 0.10, 0.14),
    Color(0.88, 0.76, 0.16),
    Color(0.86, 0.66, 0.46),
    Color(0.45, 0.16, 0.22),
]
## Deep-shell tint the flesh drifts toward with depth.
const DEEP_TINT := Color(0.32, 0.04, 0.12)

static var _shared_material: StandardMaterial3D

static func terrain_material() -> StandardMaterial3D:
    if _shared_material == null:
        var m := StandardMaterial3D.new()
        m.vertex_color_use_as_albedo = true
        m.roughness = 0.32
        m.metallic_specular = 0.75
        m.rim_enabled = true
        m.rim = 0.25
        m.rim_tint = 0.8
        _shared_material = m
    return _shared_material

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
    _static_body.set_meta("fdk_terrain_chunk", true)
    add_child(_static_body)
    _mesh_instance = MeshInstance3D.new()
    _mesh_instance.name = "Mesh"
    _mesh_instance.material_override = terrain_material()
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
    _dirty = true

func regenerate(delta: float, rate: float, protect_local_pos: Vector3, protect_radius: float) -> void:
    var n := config.chunk_size + 1
    var changed := false
    var r2 := protect_radius * protect_radius
    for i in range(_density.size()):
        var orig: float = _original_density[i]
        var cur: float = _density[i]
        if cur >= orig:
            continue
        var x := i % n
        var y := (i / n) % n
        var z := i / (n * n)
        var dx := x - protect_local_pos.x
        var dy := y - protect_local_pos.y
        var dz := z - protect_local_pos.z
        if dx * dx + dy * dy + dz * dz <= r2:
            continue
        _density[i] = minf(orig, cur + rate * delta)
        changed = true
    if changed:
        _dirty = true

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
                elif field != null:
                    v = field.corner_density_global(base + Vector3i(x, y, z))
                else:
                    v = 1.0
                out[(x + 1) + (y + 1) * p + (z + 1) * p * p] = v
    return out

func remesh() -> float:
    var start_usec := Time.get_ticks_usec()
    var s := config.chunk_size
    var cs := config.cell_size
    var iso := config.iso_level
    var p := s + 2
    var pp := p * p
    var d := _build_padded(s)

    # quick out: uniform chunk has no surface
    var first_solid := d[0] >= iso
    var uniform := true
    for i in range(d.size()):
        if (d[i] >= iso) != first_solid:
            uniform = false
            break

    var verts := PackedVector3Array()
    var normals := PackedVector3Array()
    var colors := PackedColorArray()

    if not uniform:
        # cell vertices for cells -1..s-1 (index c+1, s+1 per axis)
        var cp := s + 1
        var cell_vert := PackedVector3Array()
        cell_vert.resize(cp * cp * cp)
        var cell_has := PackedByteArray()
        cell_has.resize(cp * cp * cp)
        var jitter := config.facet_jitter * cs
        var gbase := chunk_coord * s
        for cz in range(cp):
            for cy in range(cp):
                for cx in range(cp):
                    # padded corner index of the cell's (0,0,0) corner: cell c -> corner c, padded c+1; cell index cx = c+1
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
                    # 12 edges
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
        # edges owned by this chunk: base corner 0..s-1 on every axis
        var chunk_world := position
        var depth_origin: Vector3 = field.depth_origin if field != null else Vector3.ZERO
        for z in range(s):
            for y in range(s):
                for x in range(s):
                    var i0 := (x + 1) + (y + 1) * p + (z + 1) * pp
                    var a0 := d[i0] >= iso
                    # X edge (x,y,z)-(x+1,y,z): cells (x, y-1..y, z-1..z)
                    if a0 != (d[i0 + 1] >= iso):
                        _emit_quad(verts, normals, colors, cell_vert, cell_has, cp,
                            Vector3i(x, y - 1, z - 1), Vector3i(x, y, z - 1), Vector3i(x, y, z), Vector3i(x, y - 1, z),
                            Vector3(1, 0, 0) * (1.0 if a0 else -1.0), x if a0 else x + 1, y, z, chunk_world, depth_origin)
                    if a0 != (d[i0 + p] >= iso):
                        _emit_quad(verts, normals, colors, cell_vert, cell_has, cp,
                            Vector3i(x - 1, y, z - 1), Vector3i(x, y, z - 1), Vector3i(x, y, z), Vector3i(x - 1, y, z),
                            Vector3(0, 1, 0) * (1.0 if a0 else -1.0), x, y if a0 else y + 1, z, chunk_world, depth_origin)
                    if a0 != (d[i0 + pp] >= iso):
                        _emit_quad(verts, normals, colors, cell_vert, cell_has, cp,
                            Vector3i(x - 1, y - 1, z), Vector3i(x, y - 1, z), Vector3i(x, y, z), Vector3i(x - 1, y, z),
                            Vector3(0, 0, 1) * (1.0 if a0 else -1.0), x, y, z if a0 else z + 1, chunk_world, depth_origin)

    if verts.size() > 0:
        var arrays := []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = verts
        arrays[Mesh.ARRAY_NORMAL] = normals
        arrays[Mesh.ARRAY_COLOR] = colors
        var mesh := ArrayMesh.new()
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        _mesh_instance.mesh = mesh
        var shape := ConcavePolygonShape3D.new()
        shape.set_faces(verts)
        _collision.shape = shape
    else:
        _mesh_instance.mesh = null
        _collision.shape = null

    _dirty = false
    var elapsed_ms := (Time.get_ticks_usec() - start_usec) / 1000.0
    remeshed.emit(elapsed_ms)
    return elapsed_ms

## Emits one quad (two flat triangles) joining 4 cell vertices around a
## crossing edge. `outward` points from solid toward empty. (tx,ty,tz) is
## the solid-side corner, used to pick the tissue colour.
func _emit_quad(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
        cell_vert: PackedVector3Array, cell_has: PackedByteArray, cp: int,
        c0: Vector3i, c1: Vector3i, c2: Vector3i, c3: Vector3i, outward: Vector3,
        tx: int, ty: int, tz: int, chunk_world: Vector3, depth_origin: Vector3) -> void:
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
    var cell := Vector3i(clampi(tx, 0, s - 1), clampi(ty, 0, s - 1), clampi(tz, 0, s - 1))
    # tissue of the solid-side cell nearest the corner (look at the 8 cells
    # around it and take the rarest non-flesh one so nerves show)
    var tissue := 0
    for oz in range(-1, 1):
        for oy in range(-1, 1):
            for ox in range(-1, 1):
                var t := get_tissue_at_cell(clampi(tx + ox, 0, s - 1), clampi(ty + oy, 0, s - 1), clampi(tz + oz, 0, s - 1))
                if t > tissue and t != 3:
                    tissue = t
                elif t == 3 and tissue == 0:
                    tissue = 3
    var base: Color = TISSUE_COLORS[tissue % TISSUE_COLORS.size()]
    var mid := (v0 + v1 + v2 + v3) * 0.25
    var depth := (chunk_world + mid).distance_to(depth_origin)
    var tone := clampf(depth / maxf(config.depth_tone_distance, 0.01), 0.0, 1.0)
    if tissue == 0:
        base = base.lerp(DEEP_TINT, tone * 0.8)
    var g := chunk_coord * s + cell
    _tri(verts, normals, colors, v0, v1, v2, outward, base, g, 0)
    _tri(verts, normals, colors, v0, v2, v3, outward, base, g, 1)

func _tri(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
        a: Vector3, b: Vector3, c: Vector3, outward: Vector3, base: Color, g: Vector3i, k: int) -> void:
    var n := (b - a).cross(c - a)
    if n.length_squared() < 1e-12:
        return
    if n.dot(outward) > 0.0:
        var tmp := b
        b = c
        c = tmp
        n = -n
    var nn := -n.normalized()
    var h := FDKLowPoly.hash3(g.x * 2 + k, g.y, g.z)
    var col := base.darkened(h * 0.22) if h > 0.5 else base.lightened((0.5 - h) * 0.18)
    verts.append(a)
    verts.append(b)
    verts.append(c)
    normals.append(nn)
    normals.append(nn)
    normals.append(nn)
    colors.append(col)
    colors.append(col)
    colors.append(col)

func serialize() -> Dictionary:
    return {
        "chunk_coord": [chunk_coord.x, chunk_coord.y, chunk_coord.z],
        "density": Array(_density),
        "tissue": Array(_tissue),
    }

func deserialize(data: Dictionary) -> void:
    var dd: Array = data.get("density", [])
    var t: Array = data.get("tissue", [])
    for i in range(min(dd.size(), _density.size())):
        _density[i] = float(dd[i])
    for i in range(min(t.size(), _tissue.size())):
        _tissue[i] = int(t[i])
    _dirty = true
