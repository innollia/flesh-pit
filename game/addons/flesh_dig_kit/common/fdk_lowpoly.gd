class_name FDKLowPoly
extends RefCounted

## Small helpers for building faceted low-poly meshes in code (no imported
## models). Every triangle gets its own three vertices and one flat normal,
## so lighting shows hard facets. Winding follows Godot's front-face rule
## (clockwise seen from the outside); callers pass an "outward" direction and
## the helper orders each triangle to match, so a caller never has to think
## about winding.

## Adds one flat-shaded triangle whose visible side faces `outward`.
static func add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
    var n := (b - a).cross(c - a)
    if n.length_squared() < 1e-14:
        return
    # Godot front faces are clockwise from the viewer, so the right-handed
    # cross product must point AWAY from the viewer (checked with
    # tools/_winding_check.gd).
    if n.dot(outward) > 0.0:
        var tmp := b
        b = c
        c = tmp
        n = -n
    var normal := -n.normalized()
    st.set_color(color)
    st.set_normal(normal)
    st.add_vertex(a)
    st.set_color(color)
    st.set_normal(normal)
    st.add_vertex(b)
    st.set_color(color)
    st.set_normal(normal)
    st.add_vertex(c)

## Adds a quad a-b-c-d as two flat triangles (each keeps its own normal, so a
## non-planar quad reads as a folded facet).
static func add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, color: Color) -> void:
    add_tri(st, a, b, c, outward, color)
    add_tri(st, a, c, d, outward, color)

## PS1 tone: builds planar (world/local-position) UVs for a committed mesh
## that only has vertex colours, so it can wear a low-res tiled texture
## instead. Call after st.commit(). uv_scale controls texture repeats per
## metre. Cheap CPU pass; fine for the small kit meshes (hands, fixtures).
static func planar_uv_mesh(mesh: ArrayMesh, uv_scale: float = 3.0) -> ArrayMesh:
    var out := ArrayMesh.new()
    for surf in range(mesh.get_surface_count()):
        var arrays := mesh.surface_get_arrays(surf)
        var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
        var uvs := PackedVector2Array()
        uvs.resize(verts.size())
        for i in range(verts.size()):
            var n: Vector3 = normals[i] if normals.size() > i else Vector3.UP
            var v: Vector3 = verts[i]
            var ax := absf(n.x)
            var ay := absf(n.y)
            var az := absf(n.z)
            var uv: Vector2
            if ax >= ay and ax >= az:
                uv = Vector2(v.z, v.y)
            elif ay >= ax and ay >= az:
                uv = Vector2(v.x, v.z)
            else:
                uv = Vector2(v.x, v.y)
            uvs[i] = uv * uv_scale
        arrays[Mesh.ARRAY_TEX_UV] = uvs
        out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return out

## Builds a ring of points from a 2D profile (x = width axis, y = thickness
## axis) placed in the XY plane at depth z, scaled, and offset.
static func ring(profile: PackedVector2Array, z: float, scale: Vector2, offset: Vector2 = Vector2.ZERO) -> PackedVector3Array:
    var out := PackedVector3Array()
    for p in profile:
        out.append(Vector3(p.x * scale.x + offset.x, p.y * scale.y + offset.y, z))
    return out

## A rounded n-gon profile of unit radius (x in -1..1, y in -1..1).
static func round_profile(sides: int, flatten_bottom: float = 0.0) -> PackedVector2Array:
    var out := PackedVector2Array()
    for i in range(sides):
        var a := TAU * float(i) / float(sides) + PI * 0.5
        var p := Vector2(cos(a), sin(a))
        if p.y < 0.0:
            p.y *= (1.0 - flatten_bottom)
        out.append(p)
    return out

## Connects consecutive rings (all the same point count) into a closed tube,
## optionally capping the first and last ring with a fan. `colors` may hold
## one Color per ring (the band between ring i and i+1 uses colors[i]); if it
## is shorter, the last entry repeats.
static func loft(st: SurfaceTool, rings: Array, colors: Array, cap_start: bool = true, cap_end: bool = true) -> void:
    if rings.size() < 2:
        return
    var count: int = (rings[0] as PackedVector3Array).size()
    for i in range(rings.size() - 1):
        var r0: PackedVector3Array = rings[i]
        var r1: PackedVector3Array = rings[i + 1]
        var c0 := _center(r0)
        var c1 := _center(r1)
        var col: Color = colors[mini(i, colors.size() - 1)]
        for j in range(count):
            var k := (j + 1) % count
            var face_center := (r0[j] + r0[k] + r1[j] + r1[k]) * 0.25
            var axis_center := (c0 + c1) * 0.5
            var outward := face_center - axis_center
            add_quad(st, r0[j], r0[k], r1[k], r1[j], outward, col)
    if cap_start:
        _cap(st, rings[0], _center(rings[0]) - _center(rings[1]), colors[0])
    if cap_end:
        var last: PackedVector3Array = rings[rings.size() - 1]
        var prev: PackedVector3Array = rings[rings.size() - 2]
        _cap(st, last, _center(last) - _center(prev), colors[mini(rings.size() - 2, colors.size() - 1)])

static func _cap(st: SurfaceTool, r: PackedVector3Array, outward: Vector3, color: Color) -> void:
    var c := _center(r)
    # push the fan center outward a little so the cap reads rounded
    var tip := c + outward.normalized() * 0.0
    for j in range(r.size()):
        var k := (j + 1) % r.size()
        add_tri(st, tip, r[j], r[k], outward, color)

static func _center(r: PackedVector3Array) -> Vector3:
    var s := Vector3.ZERO
    for p in r:
        s += p
    return s / float(maxi(r.size(), 1))

## Cheap deterministic hash in 0..1 from an integer lattice position. Used
## for stable per-face jitter (same input -> same output across remeshes).
static func hash3(x: int, y: int, z: int) -> float:
    var h: int = x * 73856093 ^ y * 19349663 ^ z * 83492791
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return float(h & 0xFFFF) / 65535.0

## A low-poly blob (subdivided octahedron pushed out to a lumpy sphere).
## `lumps` 0..1 controls how uneven the surface is; `seed` varies the shape.
static func add_blob(st: SurfaceTool, center: Vector3, radius: Vector3, lumps: float, seed: int, color_a: Color, color_b: Color) -> void:
    var base := [
        Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
        Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
    ]
    var faces := [
        [0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4],
        [2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5],
    ]
    for f in faces:
        var a: Vector3 = base[f[0]]
        var b: Vector3 = base[f[1]]
        var c: Vector3 = base[f[2]]
        var ab := (a + b).normalized()
        var bc := (b + c).normalized()
        var ca := (c + a).normalized()
        for tri in [[a, ab, ca], [ab, b, bc], [ca, bc, c], [ab, bc, ca]]:
            var pts: Array = []
            for v in tri:
                var dir: Vector3 = v
                var hq := hash3(int(dir.x * 97.0) + seed, int(dir.y * 97.0) - seed, int(dir.z * 97.0) + seed * 3)
                var r := 1.0 + (hq - 0.5) * 2.0 * lumps
                pts.append(center + Vector3(dir.x * radius.x, dir.y * radius.y, dir.z * radius.z) * r)
            var mid: Vector3 = (pts[0] + pts[1] + pts[2]) / 3.0
            var hc := hash3(int(mid.x * 311.0) + seed, int(mid.y * 311.0), int(mid.z * 311.0))
            add_tri(st, pts[0], pts[1], pts[2], mid - center, color_a.lerp(color_b, hc))
