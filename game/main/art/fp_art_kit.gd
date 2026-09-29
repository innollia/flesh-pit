class_name FPArtKit
extends RefCounted

## Shared helpers for the flesh-pit prop models (main/art). Everything is
## code-built low-poly geometry: flat-shaded facets, vertex colours, planar
## UVs, worn by the kit's PS1 material (nearest low-res texture + vertex snap).
## Every helper takes a Transform3D so parts can be placed/rotated freely.

const TEX := "res://addons/flesh_dig_kit/textures/"

static func begin() -> SurfaceTool:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    return st

static func finish(st: SurfaceTool, uv_scale: float = 4.0) -> ArrayMesh:
    return FDKLowPoly.planar_uv_mesh(st.commit(), uv_scale)

## PS1 material. `tex` is a file name in the kit texture folder.
## fog=false for the clean restroom and the daylight ending.
static func mat(tex: String, wet: float = 0.3, fog: bool = false) -> ShaderMaterial:
    return FDKPs1Material.get_material(TEX + tex, 1.0, true, wet, 0.6, 1.0, fog)

## Unshaded glow material (eyes in the dark, fluorescent tubes, sky).
static func glow(col: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.vertex_color_use_as_albedo = true
    m.albedo_color = col
    m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    return m

static func add_mesh(parent: Node, mesh_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.name = mesh_name
    mi.mesh = mesh
    mi.material_override = material
    parent.add_child(mi)
    return mi

static func pivot(parent: Node, pivot_name: String, pos: Vector3 = Vector3.ZERO) -> Node3D:
    var n := Node3D.new()
    n.name = pivot_name
    n.position = pos
    parent.add_child(n)
    return n

static func tri(st: SurfaceTool, t: Transform3D, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, col: Color) -> void:
    FDKLowPoly.add_tri(st, t * a, t * b, t * c, t.basis * outward, col)

static func quad(st: SurfaceTool, t: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, col: Color) -> void:
    tri(st, t, a, b, c, outward, col)
    tri(st, t, a, c, d, outward, col)

## Chamfered box: 6 faces + 12 bevel strips + 8 corner facets, so even boxy
## things (tank, container) catch light on their edges instead of reading as
## a bare cube. `bev` is the chamfer width (clamped to the half size).
static func rbox(st: SurfaceTool, t: Transform3D, half: Vector3, bev: float, col: Color, col_edge: Color = Color(-1, 0, 0)) -> void:
    var ce := col if col_edge.r < 0.0 else col_edge
    var b := minf(bev, minf(half.x, minf(half.y, half.z)) * 0.95)
    var P := func(sx: int, sy: int, sz: int, ax: int) -> Vector3:
        return Vector3(
            sx * (half.x - (0.0 if ax == 0 else b)),
            sy * (half.y - (0.0 if ax == 1 else b)),
            sz * (half.z - (0.0 if ax == 2 else b)))
    var s := [-1, 1]
    for sx in s:
        quad(st, t, P.call(sx, -1, -1, 0), P.call(sx, 1, -1, 0), P.call(sx, 1, 1, 0), P.call(sx, -1, 1, 0), Vector3(sx, 0, 0), col)
    for sy in s:
        quad(st, t, P.call(-1, sy, -1, 1), P.call(1, sy, -1, 1), P.call(1, sy, 1, 1), P.call(-1, sy, 1, 1), Vector3(0, sy, 0), col)
    for sz in s:
        quad(st, t, P.call(-1, -1, sz, 2), P.call(1, -1, sz, 2), P.call(1, 1, sz, 2), P.call(-1, 1, sz, 2), Vector3(0, 0, sz), col)
    if b <= 0.0001:
        return
    for sx in s:
        for sy in s:
            quad(st, t, P.call(sx, sy, -1, 0), P.call(sx, sy, 1, 0), P.call(sx, sy, 1, 1), P.call(sx, sy, -1, 1), Vector3(sx, sy, 0), ce)
    for sx in s:
        for sz in s:
            quad(st, t, P.call(sx, -1, sz, 0), P.call(sx, 1, sz, 0), P.call(sx, 1, sz, 2), P.call(sx, -1, sz, 2), Vector3(sx, 0, sz), ce)
    for sy in s:
        for sz in s:
            quad(st, t, P.call(-1, sy, sz, 1), P.call(1, sy, sz, 1), P.call(1, sy, sz, 2), P.call(-1, sy, sz, 2), Vector3(0, sy, sz), ce)
    for sx in s:
        for sy in s:
            for sz in s:
                tri(st, t, P.call(sx, sy, sz, 0), P.call(sx, sy, sz, 1), P.call(sx, sy, sz, 2), Vector3(sx, sy, sz), ce)

## Surface of revolution around local +Y. `prof` = Array of Vector2(radius, y)
## from bottom to top, walked along the OUTSIDE (so the right-hand normal of
## each step is the visible side). `cols` = one colour per band (last repeats).
## Radius 0 at an end closes that end to a point.
static func lathe(st: SurfaceTool, t: Transform3D, prof: Array, sides: int, cols: Array, twist: float = 0.0) -> void:
    for i in range(prof.size() - 1):
        var p0: Vector2 = prof[i]
        var p1: Vector2 = prof[i + 1]
        var d := p1 - p0
        var n2 := Vector2(d.y, -d.x)
        var col: Color = cols[mini(i, cols.size() - 1)]
        for j in range(sides):
            var a0 := TAU * float(j) / float(sides) + twist * i
            var a1 := TAU * float(j + 1) / float(sides) + twist * i
            var a0n := TAU * float(j) / float(sides) + twist * (i + 1)
            var a1n := TAU * float(j + 1) / float(sides) + twist * (i + 1)
            var am := (a0 + a1) * 0.5
            var radial := Vector3(cos(am), 0, sin(am))
            var outward := radial * n2.x + Vector3.UP * n2.y
            var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
            var v01 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
            var v10 := Vector3(cos(a0n) * p1.x, p1.y, sin(a0n) * p1.x)
            var v11 := Vector3(cos(a1n) * p1.x, p1.y, sin(a1n) * p1.x)
            if p0.x > 0.00001:
                tri(st, t, v00, v01, v11, outward, col)
            if p1.x > 0.00001:
                tri(st, t, v00, v11, v10, outward, col)

## Tube along a polyline `pts` with per-point radius; `sides` facets around.
## Optional flatten squashes the cross-section on the frame's side axis.
static func tube(st: SurfaceTool, t: Transform3D, pts: Array, radii: Array, sides: int, cols: Array, caps: bool = true, flatten: float = 1.0) -> void:
    if pts.size() < 2:
        return
    var rings: Array = []
    var ref_up := Vector3.UP
    for i in range(pts.size()):
        var p: Vector3 = pts[i]
        var dir: Vector3
        if i == 0:
            dir = (pts[1] as Vector3) - p
        elif i == pts.size() - 1:
            dir = p - (pts[i - 1] as Vector3)
        else:
            dir = (pts[i + 1] as Vector3) - (pts[i - 1] as Vector3)
        dir = dir.normalized()
        if absf(dir.dot(ref_up)) > 0.95:
            ref_up = Vector3.RIGHT
        var side := dir.cross(ref_up).normalized()
        var up := side.cross(dir).normalized()
        ref_up = up
        var r: float = radii[mini(i, radii.size() - 1)]
        var ring := PackedVector3Array()
        for j in range(sides):
            var a := TAU * float(j) / float(sides)
            ring.append(t * (p + side * cos(a) * r * flatten + up * sin(a) * r))
        rings.append(ring)
    FDKLowPoly.loft(st, rings, cols, caps, caps)

## Low-poly lumpy blob (kit helper) placed through a transform.
static func blob(st: SurfaceTool, t: Transform3D, center: Vector3, radius: Vector3, lumps: float, seed: int, ca: Color, cb: Color) -> void:
    var tmp := SurfaceTool.new()
    tmp.begin(Mesh.PRIMITIVE_TRIANGLES)
    FDKLowPoly.add_blob(tmp, center, radius, lumps, seed, ca, cb)
    var arr := tmp.commit().surface_get_arrays(0)
    var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
    var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
    var i := 0
    while i + 2 < v.size():
        var mid := (v[i] + v[i + 1] + v[i + 2]) / 3.0
        tri(st, t, v[i], v[i + 1], v[i + 2], mid - center, c[i])
        i += 3

## Deterministic 0..1 random from ints.
static func h(a: int, b: int = 0, c: int = 0) -> float:
    return FDKLowPoly.hash3(a, b, c)

static func T(pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> Transform3D:
    var b := Basis.from_euler(rot_deg * (PI / 180.0)).scaled(scl)
    return Transform3D(b, pos)