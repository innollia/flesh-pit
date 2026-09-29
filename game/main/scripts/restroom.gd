class_name FPRestroom
extends Node3D

## The clean white restroom (docs/spec/03-restroom.md): low-poly tiled walls/floor,
## ceiling light panel, toilet with an openable tank lid, sink with mirror,
## and a hinged door in the +Z wall. Beyond the doorway the flesh wall
## begins right away. Built entirely in code, flat-shaded vertex colours.

## room half-size (floor at y = 0). 형님 2026-09-29: wider left-right (X, door is the front +Z wall): 4.5 x 2.6 x 3 m.
const HALF := Vector3(2.25, 1.3, 1.5)
const TILE := 0.3
const DOOR_HALF_W := 0.45
const DOOR_H := 2.05
## Ceiling opening for the art vent (main.gd places it at x=z=0.75, its
## grate opening is 0.52 m square): [x0, z0, x1, z1].
const VENT_HOLE := [0.49, 0.49, 1.01, 1.01]
## Where the vent sits (spec 03 §2): on the ceiling toward the wall facing
## the toilet wall, straight ahead of the seat, so lifting the head about
## 45 degrees on the toilet brings it into view. main.gd places FPVent here.
const VENT_CENTER := Vector3(0.75, 2.0 * 1.3, 0.75)
## The canary hole (spec 03 §2, §9): low on the -X wall, in the corner under
## the sink. The sink's half-pedestal apron hides it from standing height;
## it shows only when crouching or lying down.
const CANARY_HOLE := Vector3(-2.25, 0.09, -0.56)
const CANARY_HOLE_HALF := Vector2(0.065, 0.07) # half width (z), half height
## Bottom edge of the ceramic apron under the basin.
const APRON_BOTTOM := 0.34

var door_pivot: Node3D
var toilet: Node3D
var tank_lid: Node3D
var tank_items: Node3D
## main/art models: the tooth tank on the toilet and the mirror over the sink.
var tank_art: Node3D
var mirror_art: Node3D
var bowl_center: Vector3
var _door_target: float = 0.0
var _lid_target: float = 0.0
## Light that spills out of the open door into the flesh passage (spec 03
## §4: the open door is a lighthouse on the way back).
var door_spill: SpotLight3D
var door_spill_fill: OmniLight3D
const DOOR_SPILL_ENERGY := 3.2
const DOOR_FILL_ENERGY := 1.1

func _ready() -> void:
    build()

func build() -> void:
    var tile_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_tile_wall_128.png", 2.5, false, 0.2, 0.5, 1.0, false)
    var fixture_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_chrome_128.png", 1.5, false, 0.55, 0.2, 1.0, false)
    var floor_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_tile_floor_128.png", 2.5, false, 0.25, 0.45, 1.0, false)
    _build_tiles(tile_mat, floor_mat)
    # 형님 결정: 변기·세면대는 얼룩 없는 순백 도자기(약한 광택).
    var ceramic_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_ceramic_128.png", 1.0, false, 0.45, 0.25, 1.0, false)
    _build_toilet(ceramic_mat)
    _build_sink(ceramic_mat)
    _build_sink_apron(ceramic_mat)
    _build_canary_hole()
    var door_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_door_paint_128.png", 1.0, false, 0.2, 0.5, 1.0, false)
    _build_door(door_mat, fixture_mat)
    _build_korean(fixture_mat)
    _build_drawer(ceramic_mat, fixture_mat)
    _build_light()
    _build_collision()

# --- tiles ------------------------------------------------------------------

func _build_tiles(mat: Material, floor_mat: Material) -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var grout := Color(0.52, 0.55, 0.58)
    var h := HALF
    # grout planes (slightly behind tiles), then tiles
    _plane(st, Vector3(-h.x, 0, -h.z), Vector3(2 * h.x, 0, 0), Vector3(0, 0, 2 * h.z), Vector3.UP, grout)
    for r in _minus_hole([-h.x, -h.z, h.x, h.z]):
        _plane(st, Vector3(r[0], 2 * h.y, r[1]), Vector3(r[2] - r[0], 0, 0), Vector3(0, 0, r[3] - r[1]), Vector3.DOWN, grout)
    _plane(st, Vector3(-h.x, 0, -h.z), Vector3(2 * h.x, 0, 0), Vector3(0, 2 * h.y, 0), Vector3.BACK, grout)
    _plane(st, Vector3(-h.x, 0, -h.z), Vector3(0, 0, 2 * h.z), Vector3(0, 2 * h.y, 0), Vector3.RIGHT, grout)
    _plane(st, Vector3(h.x, 0, -h.z), Vector3(0, 0, 2 * h.z), Vector3(0, 2 * h.y, 0), Vector3.LEFT, grout)
    # front wall grout minus doorway: three pieces
    _plane(st, Vector3(-h.x, 0, h.z), Vector3(h.x - DOOR_HALF_W, 0, 0), Vector3(0, 2 * h.y, 0), Vector3.FORWARD, grout)
    _plane(st, Vector3(DOOR_HALF_W, 0, h.z), Vector3(h.x - DOOR_HALF_W, 0, 0), Vector3(0, 2 * h.y, 0), Vector3.FORWARD, grout)
    _plane(st, Vector3(-DOOR_HALF_W, DOOR_H, h.z), Vector3(2 * DOOR_HALF_W, 0, 0), Vector3(0, 2 * h.y - DOOR_H, 0), Vector3.FORWARD, grout)

    var gap := 0.012
    var inset := 0.004
    var nx := int(round(2 * h.x / TILE))
    var nz := int(round(2 * h.z / TILE))
    var ny := int(round(2 * h.y / TILE)) + 1
    for i in range(nx):
        for k in range(nz):
            var c := _tile_color(i, 0, k, true)
            var o := Vector3(-h.x + i * TILE + gap, inset, -h.z + k * TILE + gap)
            _tile(st, o, Vector3(TILE - 2 * gap, 0, 0), Vector3(0, 0, TILE - 2 * gap), Vector3.UP, c)
            var tx := -h.x + i * TILE + gap
            var tz := -h.z + k * TILE + gap
            for r in _minus_hole([tx, tz, tx + TILE - 2 * gap, tz + TILE - 2 * gap]):
                _tile(st, Vector3(r[0], 2 * h.y - inset, r[1]), Vector3(r[2] - r[0], 0, 0), Vector3(0, 0, r[3] - r[1]), Vector3.DOWN, Color(0.97, 0.97, 0.96))
    for i in range(nx):
        for j in range(ny):
            var y0 := j * TILE
            var y1 := minf(2 * h.y, y0 + TILE)
            if y1 - y0 < 0.05:
                continue
            var size_y := y1 - y0 - 2 * gap
            var x0 := -h.x + i * TILE
            # back wall
            _tile(st, Vector3(x0 + gap, y0 + gap, -h.z + inset), Vector3(TILE - 2 * gap, 0, 0), Vector3(0, size_y, 0), Vector3.BACK, _tile_color(i, j, 1, false))
            # front wall with doorway
            var in_door := x0 + TILE > -DOOR_HALF_W + 0.001 and x0 < DOOR_HALF_W - 0.001 and y0 < DOOR_H - 0.001
            if not in_door:
                _tile(st, Vector3(x0 + gap, y0 + gap, h.z - inset), Vector3(TILE - 2 * gap, 0, 0), Vector3(0, size_y, 0), Vector3.FORWARD, _tile_color(i, j, 2, false))
    for k in range(nz):
        for j in range(ny):
            var y0 := j * TILE
            var y1 := minf(2 * h.y, y0 + TILE)
            if y1 - y0 < 0.05:
                continue
            var size_y := y1 - y0 - 2 * gap
            var z0 := -h.z + k * TILE
            _tile(st, Vector3(-h.x + inset, y0 + gap, z0 + gap), Vector3(0, 0, TILE - 2 * gap), Vector3(0, size_y, 0), Vector3.RIGHT, _tile_color(k, j, 3, false))
            _tile(st, Vector3(h.x - inset, y0 + gap, z0 + gap), Vector3(0, 0, TILE - 2 * gap), Vector3(0, size_y, 0), Vector3.LEFT, _tile_color(k, j, 4, false))
    # door frame
    var frame := Color(0.9, 0.9, 0.88)
    FDKLowPoly.add_quad(st, Vector3(-DOOR_HALF_W, 0, h.z), Vector3(-DOOR_HALF_W, DOOR_H, h.z), Vector3(-DOOR_HALF_W, DOOR_H, h.z + 0.2), Vector3(-DOOR_HALF_W, 0, h.z + 0.2), Vector3.RIGHT, frame)
    FDKLowPoly.add_quad(st, Vector3(DOOR_HALF_W, 0, h.z), Vector3(DOOR_HALF_W, DOOR_H, h.z), Vector3(DOOR_HALF_W, DOOR_H, h.z + 0.2), Vector3(DOOR_HALF_W, 0, h.z + 0.2), Vector3.LEFT, frame)
    FDKLowPoly.add_quad(st, Vector3(-DOOR_HALF_W, DOOR_H, h.z), Vector3(DOOR_HALF_W, DOOR_H, h.z), Vector3(DOOR_HALF_W, DOOR_H, h.z + 0.2), Vector3(-DOOR_HALF_W, DOOR_H, h.z + 0.2), Vector3.DOWN, frame)
    # skirting strip
    for w in [[Vector3(-h.x, 0, -h.z + 0.005), Vector3(2 * h.x, 0, 0), Vector3.BACK], [Vector3(-h.x + 0.005, 0, -h.z), Vector3(0, 0, 2 * h.z), Vector3.RIGHT], [Vector3(h.x - 0.005, 0, -h.z), Vector3(0, 0, 2 * h.z), Vector3.LEFT]]:
        _tile(st, w[0], w[1], Vector3(0, 0.08, 0), w[2], Color(0.82, 0.84, 0.86))
    var tiles := MeshInstance3D.new()
    tiles.name = "Tiles"
    tiles.mesh = _split_floor(st.commit() as ArrayMesh, mat, floor_mat)
    add_child(tiles)

## Splits rect [x0, z0, x1, z1] into the parts outside VENT_HOLE.
func _minus_hole(r: Array) -> Array:
    var hx0: float = VENT_HOLE[0]
    var hz0: float = VENT_HOLE[1]
    var hx1: float = VENT_HOLE[2]
    var hz1: float = VENT_HOLE[3]
    if r[2] <= hx0 or r[0] >= hx1 or r[3] <= hz0 or r[1] >= hz1:
        return [r]
    var out: Array = []
    if r[0] < hx0:
        out.append([r[0], r[1], hx0, r[3]])
    if r[2] > hx1:
        out.append([hx1, r[1], r[2], r[3]])
    var mx0 := maxf(r[0], hx0)
    var mx1 := minf(r[2], hx1)
    if r[1] < hz0:
        out.append([mx0, r[1], mx1, hz0])
    if r[3] > hz1:
        out.append([mx0, hz1, mx1, r[3]])
    return out.filter(func(q): return q[2] - q[0] > 0.002 and q[3] - q[1] > 0.002)

func _tile_color(a: int, b: int, c: int, floor_tile: bool) -> Color:
    var hsh := FDKLowPoly.hash3(a, b, c)
    if floor_tile:
        return Color(0.9, 0.92, 0.93) if (a + b + c) % 2 == 0 else Color(0.82, 0.86, 0.9)
    return Color(0.9, 0.91, 0.92).darkened(hsh * 0.05)

func _plane(st: SurfaceTool, o: Vector3, u: Vector3, v: Vector3, n: Vector3, c: Color) -> void:
    FDKLowPoly.add_quad(st, o, o + u, o + u + v, o + v, n, c)

## A tile with a small bevel so it reads as a raised low-poly tile.
func _tile(st: SurfaceTool, o: Vector3, u: Vector3, v: Vector3, n: Vector3, c: Color) -> void:
    var b := 0.012
    var up := n * 0.006
    var ui := u.normalized() * b
    var vi := v.normalized() * b
    var a0 := o
    var a1 := o + u
    var a2 := o + u + v
    var a3 := o + v
    var t0 := a0 + ui + vi + up
    var t1 := a1 - ui + vi + up
    var t2 := a2 - ui - vi + up
    var t3 := a3 + ui - vi + up
    FDKLowPoly.add_quad(st, t0, t1, t2, t3, n, c)
    var side := c.darkened(0.06)
    FDKLowPoly.add_quad(st, a0, a1, t1, t0, n - v.normalized(), side)
    FDKLowPoly.add_quad(st, a1, a2, t2, t1, n + u.normalized(), side)
    FDKLowPoly.add_quad(st, a2, a3, t3, t2, n + v.normalized(), side)
    FDKLowPoly.add_quad(st, a3, a0, t0, t3, n - u.normalized(), side)

func _add(st: SurfaceTool, mat: Material, node_name: String, parent: Node3D = null) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.name = node_name
    mi.mesh = FDKLowPoly.planar_uv_mesh(st.commit() as ArrayMesh, 2.2)
    mi.material_override = mat
    (parent if parent != null else self).add_child(mi)
    return mi


## Splits a committed tile mesh into two surfaces by facing: up-facing
## triangles (the floor) wear the floor texture, everything else the wall
## texture. Planar UVs are generated per surface.
func _split_floor(mesh: ArrayMesh, wall_mat: Material, floor_mat: Material) -> ArrayMesh:
    var arr := mesh.surface_get_arrays(0)
    var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
    var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
    var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
    var parts := [[PackedVector3Array(), PackedVector3Array(), PackedColorArray()], [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]]
    for i in range(0, v.size(), 3):
        var is_floor := n[i].y > 0.9 and v[i].y < 0.1
        var p: Array = parts[1 if is_floor else 0]
        for k in range(3):
            p[0].append(v[i + k])
            p[1].append(n[i + k])
            p[2].append(c[i + k] if c.size() > i + k else Color.WHITE)
    var tmp := ArrayMesh.new()
    for p in parts:
        var a := []
        a.resize(Mesh.ARRAY_MAX)
        a[Mesh.ARRAY_VERTEX] = p[0]
        a[Mesh.ARRAY_NORMAL] = p[1]
        a[Mesh.ARRAY_COLOR] = p[2]
        tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
    var out := FDKLowPoly.planar_uv_mesh(tmp, 2.2)
    out.surface_set_material(0, wall_mat)
    out.surface_set_material(1, floor_mat)
    return out

# --- toilet -----------------------------------------------------------------

func _build_toilet(mat: Material) -> void:
    toilet = Node3D.new()
    toilet.name = "Toilet"
    toilet.position = Vector3(0.75, 0, -HALF.z)
    add_child(toilet)
    var white := Color(0.97, 0.97, 0.98)
    var shade := Color(0.88, 0.89, 0.91)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var prof := FDKLowPoly.round_profile(12)
    # pedestal: stacked rings (y up); ring() builds in XY, so build manually
    var ped := []
    for r in [[0.0, 0.17, 0.2], [0.18, 0.13, 0.16], [0.32, 0.16, 0.2], [0.4, 0.21, 0.25]]:
        ped.append(_yring(prof, Vector3(0, r[0], 0.3), r[1], r[2]))
    FDKLowPoly.loft(st, ped, [shade, white, white], true, false)
    # bowl: rim ring and inner funnel
    var rim_o := _yring(prof, Vector3(0, 0.42, 0.3), 0.21, 0.26)
    var rim_i := _yring(prof, Vector3(0, 0.42, 0.3), 0.15, 0.2)
    var in_mid := _yring(prof, Vector3(0, 0.3, 0.29), 0.11, 0.14)
    var in_low := _yring(prof, Vector3(0, 0.22, 0.27), 0.06, 0.07)
    FDKLowPoly.loft(st, [ped[3], rim_o], [white], false, false)
    _ring_band(st, rim_o, rim_i, Vector3.UP, white)
    _ring_band_inner(st, rim_i, in_mid, Vector3(0, 0.3, 0.29), shade)
    _ring_band_inner(st, in_mid, in_low, Vector3(0, 0.22, 0.27), shade.darkened(0.05))
    # water
    var water := Color(0.62, 0.8, 0.9)
    var wring := _yring(prof, Vector3(0, 0.28, 0.285), 0.1, 0.125)
    for i in range(wring.size()):
        FDKLowPoly.add_tri(st, Vector3(0, 0.28, 0.285), wring[i], wring[(i + 1) % wring.size()], Vector3.UP, water.lightened(0.05 * (i % 2)))
    bowl_center = toilet.position + Vector3(0, 0.3, 0.3)
    # seat (a flat ring slightly above the rim)
    var seat_o := _yring(prof, Vector3(0, 0.45, 0.31), 0.22, 0.27)
    var seat_i := _yring(prof, Vector3(0, 0.45, 0.31), 0.14, 0.19)
    _ring_band(st, seat_o, seat_i, Vector3.UP, Color(0.99, 0.99, 1.0))
    FDKLowPoly.loft(st, [_yring(prof, Vector3(0, 0.42, 0.31), 0.22, 0.27), seat_o], [shade], false, false)
    # tank: the main/art tooth tank model (added below), not a plain box
    # flush lever
    _box(st, Vector3(-0.2, 0.72, 0.17), Vector3(-0.12, 0.745, 0.2), Color(0.75, 0.77, 0.8), Color(0.6, 0.62, 0.66))
    _add(st, mat, "Body", toilet)
    # tank lid on a hinge at the back so it can open to show purchased items
    tank_lid = Node3D.new()
    tank_lid.name = "TankLid"
    tank_lid.position = Vector3(0, 0.8, 0.0)
    toilet.add_child(tank_lid)
    # the lid pivot stays as the logic handle; the art tank draws its own lid
    tank_art = (load("res://main/art/fp_tooth_tank.tscn") as PackedScene).instantiate()
    tank_art.name = "ToothTank"
    tank_art.position = Vector3(0, 0.42, 0.085)
    tank_art.scale = Vector3(1.0, 1.1, 1.0)
    toilet.add_child(tank_art)
    tank_art.call("set_amount", 0.0)
    tank_items = Node3D.new()
    tank_items.name = "TankItems"
    tank_items.position = Vector3(0, 0.72, 0.085)
    toilet.add_child(tank_items)

func _yring(prof: PackedVector2Array, c: Vector3, rx: float, rz: float) -> PackedVector3Array:
    var out := PackedVector3Array()
    for p in prof:
        out.append(c + Vector3(p.x * rx, 0, -p.y * rz))
    return out

func _ring_band(st: SurfaceTool, outer: PackedVector3Array, inner: PackedVector3Array, n: Vector3, c: Color) -> void:
    for i in range(outer.size()):
        var k := (i + 1) % outer.size()
        FDKLowPoly.add_quad(st, outer[i], outer[k], inner[k], inner[i], n, c)

func _ring_band_inner(st: SurfaceTool, top: PackedVector3Array, low: PackedVector3Array, axis: Vector3, c: Color) -> void:
    for i in range(top.size()):
        var k := (i + 1) % top.size()
        var mid := (top[i] + top[k] + low[i] + low[k]) * 0.25
        var inward := Vector3(axis.x, mid.y, axis.z) - mid
        FDKLowPoly.add_quad(st, top[i], top[k], low[k], low[i], inward, c.darkened(0.04 * (i % 2)))

func _box(st: SurfaceTool, a: Vector3, b: Vector3, c: Color, side: Color) -> void:
    var p := [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z),
        Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]
    FDKLowPoly.add_quad(st, p[3], p[2], p[6], p[7], Vector3.UP, c)
    FDKLowPoly.add_quad(st, p[4], p[5], p[6], p[7], Vector3.BACK, c)
    FDKLowPoly.add_quad(st, p[0], p[1], p[2], p[3], Vector3.FORWARD, side)
    FDKLowPoly.add_quad(st, p[0], p[4], p[7], p[3], Vector3.LEFT, side)
    FDKLowPoly.add_quad(st, p[1], p[5], p[6], p[2], Vector3.RIGHT, side)
    FDKLowPoly.add_quad(st, p[0], p[1], p[5], p[4], Vector3.DOWN, side)


# --- modern Korean restroom fixtures (wet-room style: shower on the wall,
# floor drain, paper holder, ceiling vent) ---------------------------------

func _build_korean(mat: Material) -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var chrome := Color(0.8, 0.82, 0.86)
    var chrome_d := Color(0.6, 0.62, 0.67)
    var x := -HALF.x
    var sz := 1.0
    # shower mixer on the left wall, riser bar, head, hose
    _box(st, Vector3(x, 0.95, sz - 0.08), Vector3(x + 0.06, 1.05, sz + 0.08), chrome, chrome_d)
    _box(st, Vector3(x + 0.06, 0.98, sz - 0.02), Vector3(x + 0.12, 1.02, sz + 0.02), chrome, chrome_d)
    _box(st, Vector3(x + 0.02, 1.05, sz - 0.015), Vector3(x + 0.05, 1.95, sz + 0.015), chrome, chrome_d)
    var prof := FDKLowPoly.round_profile(8)
    var hc := Vector3(x + 0.11, 1.9, sz)
    var head_a := PackedVector3Array()
    var head_b := PackedVector3Array()
    for p in prof:
        head_a.append(hc + Vector3(-0.02, p.x * 0.06, p.y * 0.06))
        head_b.append(hc + Vector3(0.02, p.x * 0.07, p.y * 0.07))
    FDKLowPoly.loft(st, [head_a, head_b], [chrome], true, true)
    _box(st, Vector3(x + 0.05, 1.88, sz - 0.012), Vector3(x + 0.1, 1.9, sz + 0.012), chrome, chrome_d)
    # hose: a sagging chain of small boxes from the mixer
    var prev := Vector3(x + 0.08, 0.95, sz)
    for i in range(1, 9):
        var t := float(i) / 8.0
        var q := Vector3(x + 0.08 + sin(t * PI) * 0.06, 0.95 - sin(t * PI) * 0.45 + t * 0.9, sz + t * 0.05)
        var mid := (prev + q) * 0.5
        _box(st, mid - Vector3(0.008, 0.06, 0.008), mid + Vector3(0.008, 0.06, 0.008), chrome_d, chrome_d.darkened(0.1))
        prev = q
    # floor drain: square stainless grate slightly sunk into the floor tiles
    var dc := Vector3(-0.9, 0.012, 1.0)
    _box(st, dc - Vector3(0.1, 0.004, 0.1), dc + Vector3(0.1, 0.0, 0.1), chrome_d, chrome_d)
    for i in range(5):
        var gx := dc.x - 0.08 + i * 0.04
        _box(st, Vector3(gx - 0.006, dc.y, dc.z - 0.08), Vector3(gx + 0.006, dc.y + 0.003, dc.z + 0.08), Color(0.35, 0.36, 0.38), Color(0.3, 0.3, 0.32))
    # toilet paper holder on the right wall beside the toilet
    var px := HALF.x
    _box(st, Vector3(px - 0.03, 0.7, -0.95), Vector3(px, 0.78, -0.75), chrome, chrome_d)
    var roll_a := PackedVector3Array()
    var roll_b := PackedVector3Array()
    for p in prof:
        roll_a.append(Vector3(px - 0.1 + p.x * 0.055, 0.66 + p.y * 0.055, -0.93))
        roll_b.append(Vector3(px - 0.1 + p.x * 0.055, 0.66 + p.y * 0.055, -0.8))
    FDKLowPoly.loft(st, [roll_a, roll_b], [Color(0.98, 0.98, 0.97)], true, true)
    # ceiling exhaust vent: the main/art vent model sits in VENT_HOLE (main.gd)
    _add(st, mat, "KoreanFixtures")

# --- sink, door, light, collision ---------------------------------------------

func _build_sink(mat: Material) -> void:
    # sink + mirror: the main/art model on the -X wall, facing into the room
    mirror_art = (load("res://main/art/fp_mirror.tscn") as PackedScene).instantiate()
    mirror_art.name = "MirrorSink"
    mirror_art.position = Vector3(-HALF.x, 0.0, -0.35)
    mirror_art.rotation.y = PI * 0.5
    add_child(mirror_art)

## Half-pedestal apron (a common Korean sink shroud): a curved ceramic skirt
## hanging from the basin to APRON_BOTTOM. It hides the pipes and, with
## them, the canary hole in the corner behind it from standing height.
func _build_sink_apron(mat: Material) -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var x0 := -HALF.x
    var cz := -0.35
    var white := Color(0.97, 0.97, 0.98)
    var shade := Color(0.88, 0.89, 0.91)
    var top := 0.62
    var seg := 10
    # half-ellipse in the XZ plane: out 0.34 from the wall, 0.25 each side
    var pts := PackedVector3Array()
    for i in range(seg + 1):
        var a := PI * float(i) / seg
        pts.append(Vector3(x0 + sin(a) * 0.34, 0, cz - cos(a) * 0.25))
    for i in range(seg):
        var a := pts[i]
        var b := pts[i + 1]
        var mid := (a + b) * 0.5
        var n := Vector3(mid.x - x0, 0, mid.z - cz).normalized()
        var c := white if i % 2 == 0 else white.darkened(0.02)
        FDKLowPoly.add_quad(st, Vector3(a.x, APRON_BOTTOM, a.z), Vector3(b.x, APRON_BOTTOM, b.z), Vector3(b.x, top, b.z), Vector3(a.x, top, a.z), n, c)
        # inside face so the back of the skirt is not see-through
        FDKLowPoly.add_quad(st, Vector3(b.x, APRON_BOTTOM, b.z), Vector3(a.x, APRON_BOTTOM, a.z), Vector3(a.x, top, a.z), Vector3(b.x, top, b.z), -n, shade.darkened(0.25))
        # rolled bottom lip
        var lip_o := n * 0.012
        FDKLowPoly.add_quad(st, Vector3(a.x, APRON_BOTTOM, a.z), Vector3(a.x, APRON_BOTTOM, a.z) + lip_o + Vector3(0, 0.012, 0), Vector3(b.x, APRON_BOTTOM, b.z) + lip_o + Vector3(0, 0.012, 0), Vector3(b.x, APRON_BOTTOM, b.z), Vector3.DOWN, shade)
    _add(st, mat, "SinkApron")

## The canary hole: a small arched gap at the foot of the wall, dark inside,
## with a few chipped tile edges round it. Only visible from low down.
func _build_canary_hole() -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var hw := CANARY_HOLE_HALF.x
    var hh := CANARY_HOLE_HALF.y
    var cx := CANARY_HOLE.x + 0.013 # just proud of the raised tiles
    var cz := CANARY_HOLE.z
    var y0 := CANARY_HOLE.y - hh
    # outline: flat bottom, straight sides, round arch top
    var outline := PackedVector2Array() # (z, y)
    outline.append(Vector2(cz - hw, y0))
    var arch_y := y0 + hh * 2.0 - hw
    for i in range(9):
        var a := PI * float(i) / 8.0
        outline.append(Vector2(cz - cos(a) * hw, arch_y + sin(a) * hw))
    outline.append(Vector2(cz + hw, y0))
    var black := Color(0.015, 0.012, 0.012)
    var inner := Color(0.07, 0.06, 0.06)
    # the wall tiles are solid, so the hole is a flat dark arch laid just in front of them (reads as depth from its dark inner band)
    var depth := -0.002
    var center := Vector3(cx, y0 + hh * 0.9, cz)
    # tunnel walls going into the wall (-X), dark grey fading to black
    for i in range(outline.size()):
        var p := outline[i]
        var q := outline[(i + 1) % outline.size()]
        var a := Vector3(cx, p.y, p.x)
        var b := Vector3(cx, q.y, q.x)
        var n := Vector3(0, center.y - (p.y + q.y) * 0.5, center.z - (p.x + q.x) * 0.5).normalized()
        FDKLowPoly.add_quad(st, a, b, b + Vector3(-depth, 0, 0), a + Vector3(-depth, 0, 0), n, inner)
    # back: pure black
    for i in range(1, outline.size() - 1):
        var p0 := outline[0]
        var p1 := outline[i]
        var p2 := outline[i + 1]
        FDKLowPoly.add_tri(st, Vector3(cx - depth, p0.y, p0.x), Vector3(cx - depth, p2.y, p2.x), Vector3(cx - depth, p1.y, p1.x), Vector3.RIGHT, black)
    # chipped rim: a thin broken-tile frame just outside the opening
    var rim := Color(0.74, 0.76, 0.78)
    for i in range(outline.size() - 1):
        var p := outline[i]
        var q := outline[i + 1]
        var mid := (p + q) * 0.5
        var out := (mid - Vector2(cz, center.y)).normalized()
        var w := 0.008 + 0.01 * FDKLowPoly.hash3(i, 7, 3)
        var a := Vector3(cx + 0.004, p.y, p.x)
        var b := Vector3(cx + 0.004, q.y, q.x)
        FDKLowPoly.add_quad(st, a, b, b + Vector3(0, out.y * w, out.x * w), a + Vector3(0, out.y * w, out.x * w), Vector3.RIGHT, rim.darkened(0.1 * FDKLowPoly.hash3(i, 2, 9)))
    var m := StandardMaterial3D.new()
    m.vertex_color_use_as_albedo = true
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.roughness = 1.0
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    var mi := MeshInstance3D.new()
    mi.name = "CanaryHole"
    mi.mesh = st.commit()
    mi.material_override = m
    add_child(mi)

## Wall drawer unit (형님 2026-09-29): a white two-drawer cabinet hung on the
## +X wall, chrome bar pulls. Decorative for now; the drawers are nodes
## (DrawerTop / DrawerBottom) so they can be opened later.
const DRAWER_CENTER := Vector3(2.25, 0.95, 0.45) # on the +X wall, centre of the back face
const DRAWER_SIZE := Vector3(0.36, 0.5, 0.62)   # depth (x), height, width (z)
var drawers: Array[Node3D] = []

func _build_drawer(mat: Material, chrome_mat: Material) -> void:
    var root := Node3D.new()
    root.name = "WallDrawer"
    root.position = DRAWER_CENTER
    add_child(root)
    var d := DRAWER_SIZE
    var white := Color(0.96, 0.96, 0.95)
    var side := Color(0.86, 0.87, 0.88)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    # carcass: back at x=0, front open toward -X (into the room)
    var t := 0.018
    _box(st, Vector3(-d.x, -d.y * 0.5, -d.z * 0.5), Vector3(0, -d.y * 0.5 + t, d.z * 0.5), white, side)
    _box(st, Vector3(-d.x, d.y * 0.5 - t, -d.z * 0.5), Vector3(0, d.y * 0.5, d.z * 0.5), white, side)
    _box(st, Vector3(-d.x, -d.y * 0.5, -d.z * 0.5), Vector3(0, d.y * 0.5, -d.z * 0.5 + t), white, side)
    _box(st, Vector3(-d.x, -d.y * 0.5, d.z * 0.5 - t), Vector3(0, d.y * 0.5, d.z * 0.5), white, side)
    _box(st, Vector3(-d.x + 0.02, -0.006, -d.z * 0.5), Vector3(0, 0.006, d.z * 0.5), side, side)
    _add(st, mat, "Carcass", root)
    for i in range(2):
        var dr := Node3D.new()
        dr.name = "DrawerTop" if i == 0 else "DrawerBottom"
        var cy := d.y * 0.25 * (1 if i == 0 else -1)
        dr.position = Vector3(-d.x, cy, 0)
        root.add_child(dr)
        var fs := SurfaceTool.new()
        fs.begin(Mesh.PRIMITIVE_TRIANGLES)
        var hh := d.y * 0.25 - 0.012
        var hw := d.z * 0.5 - 0.012
        # front panel with a slight raised centre
        _box(fs, Vector3(-0.022, -hh, -hw), Vector3(0.0, hh, hw), white, side)
        _box(fs, Vector3(-0.028, -hh + 0.03, -hw + 0.03), Vector3(-0.022, hh - 0.03, hw - 0.03), Color(0.98, 0.98, 0.97), side)
        # drawer box behind the front
        _box(fs, Vector3(0.0, -hh + 0.01, -hw + 0.02), Vector3(d.x - 0.03, -hh + 0.022, hw - 0.02), side, side.darkened(0.1))
        _add(fs, mat, "Front", dr)
        var ps := SurfaceTool.new()
        ps.begin(Mesh.PRIMITIVE_TRIANGLES)
        _box(ps, Vector3(-0.06, -0.008, -0.1), Vector3(-0.05, 0.008, 0.1), Color(1, 1, 1), Color(0.88, 0.9, 0.92))
        _box(ps, Vector3(-0.05, -0.006, -0.09), Vector3(-0.028, 0.006, -0.075), Color(0.9, 0.9, 0.92), Color(0.8, 0.8, 0.84))
        _box(ps, Vector3(-0.05, -0.006, 0.075), Vector3(-0.028, 0.006, 0.09), Color(0.9, 0.9, 0.92), Color(0.8, 0.8, 0.84))
        _add(ps, chrome_mat, "Pull", dr)
        drawers.append(dr)

## Old code-built sink (kept for reference, no longer called).
func _build_sink_placeholder(mat: Material) -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var x := -HALF.x
    var white := Color(0.97, 0.97, 0.98)
    var shade := Color(0.86, 0.87, 0.9)
    var prof := FDKLowPoly.round_profile(10)
    var c := Vector3(x + 0.27, 0.86, -0.35)
    var top_o := _yring(prof, c, 0.25, 0.2)
    var top_i := _yring(prof, c, 0.19, 0.15)
    var low := _yring(prof, c + Vector3(0, -0.1, 0), 0.09, 0.07)
    var under := _yring(prof, c + Vector3(0, -0.14, 0), 0.2, 0.16)
    _ring_band(st, top_o, top_i, Vector3.UP, white)
    _ring_band_inner(st, top_i, low, c + Vector3(0, -0.1, 0), shade)
    FDKLowPoly.loft(st, [under, top_o], [shade], true, false)
    # pedestal column
    var col := []
    for r in [[0.0, 0.1], [0.6, 0.07], [0.72, 0.12]]:
        col.append(_yring(prof, Vector3(x + 0.22, r[0], -0.35), r[1], r[1]))
    FDKLowPoly.loft(st, col, [white, shade], true, true)
    # tap
    _box(st, Vector3(x + 0.02, 0.9, -0.38), Vector3(x + 0.14, 0.94, -0.32), Color(0.78, 0.8, 0.84), Color(0.6, 0.62, 0.66))
    # mirror (pale blue-gray, framed)
    _box(st, Vector3(x + 0.005, 1.15, -0.72), Vector3(x + 0.03, 1.85, 0.02), Color(0.88, 0.9, 0.92), Color(0.8, 0.82, 0.85))
    FDKLowPoly.add_quad(st, Vector3(x + 0.032, 1.19, -0.68), Vector3(x + 0.032, 1.19, -0.02), Vector3(x + 0.032, 1.81, -0.02), Vector3(x + 0.032, 1.81, -0.68), Vector3.RIGHT, Color(0.72, 0.8, 0.86))
    _add(st, mat, "Sink")

func _build_door(mat: Material, handle_mat: Material) -> void:
    door_pivot = Node3D.new()
    door_pivot.name = "DoorPivot"
    door_pivot.position = Vector3(-DOOR_HALF_W, 0, HALF.z + 0.02)
    add_child(door_pivot)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var w := 2 * DOOR_HALF_W - 0.01
    var white := Color(0.95, 0.95, 0.94)
    _box(st, Vector3(0.005, 0.005, -0.02), Vector3(w, DOOR_H - 0.01, 0.02), white, Color(0.86, 0.86, 0.85))
    # two recessed panels
    for pr in [[0.25, 0.95], [1.1, 1.85]]:
        # panels sit 4 mm proud of the slab (was 1 mm: z-fighting streaks)
        FDKLowPoly.add_quad(st, Vector3(0.12, pr[0], -0.024), Vector3(w - 0.12, pr[0], -0.024), Vector3(w - 0.12, pr[1], -0.024), Vector3(0.12, pr[1], -0.024), Vector3.FORWARD, Color(0.93, 0.93, 0.92))
    _add(st, mat, "Door", door_pivot)
    # chrome handle as its own mesh so it gets the chrome material
    var hs := SurfaceTool.new()
    hs.begin(Mesh.PRIMITIVE_TRIANGLES)
    _box(hs, Vector3(w - 0.14, 0.98, -0.07), Vector3(w - 0.05, 1.01, -0.02), Color(1, 1, 1), Color(0.9, 0.9, 0.92))
    _box(hs, Vector3(w - 0.14, 0.98, 0.02), Vector3(w - 0.05, 1.01, 0.07), Color(1, 1, 1), Color(0.9, 0.9, 0.92))
    _add(hs, handle_mat, "Handle", door_pivot)
    var body := StaticBody3D.new()
    body.name = "DoorBody"
    var cs := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = Vector3(w, DOOR_H, 0.04)
    cs.shape = bs
    cs.position = Vector3(w * 0.5, DOOR_H * 0.5, 0)
    body.add_child(cs)
    door_pivot.add_child(body)

func _build_light() -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var y := 2 * HALF.y - 0.01
    FDKLowPoly.add_quad(st, Vector3(-0.4, y, -0.4), Vector3(0.4, y, -0.4), Vector3(0.4, y, 0.4), Vector3(-0.4, y, 0.4), Vector3.DOWN, Color(1, 1, 1))
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.albedo_color = Color(1, 1, 0.97)
    _add(st, m, "LightPanel")
    var l := OmniLight3D.new()
    l.name = "RoomLight"
    l.position = Vector3(0, 2 * HALF.y - 0.3, 0)
    l.omni_range = 6.0
    l.light_energy = 0.42
    l.shadow_enabled = true
    l.light_color = Color(0.95, 0.98, 1.0) # cold fluorescent
    add_child(l)
    # door spill: a cold cone of tube light thrown out into the passage, and
    # a soft fill just past the threshold. Both scale with how open the door is.
    door_spill = SpotLight3D.new()
    door_spill.name = "DoorSpill"
    door_spill.position = Vector3(0, DOOR_H - 0.1, HALF.z - 0.25)
    door_spill.rotation = Vector3(deg_to_rad(-8.0), PI, 0) # spot points -Z; turn it to +Z
    door_spill.spot_range = 9.0
    door_spill.spot_angle = 34.0
    door_spill.spot_attenuation = 0.8
    door_spill.light_color = Color(0.9, 0.96, 1.0)
    door_spill.light_energy = 0.0
    door_spill.shadow_enabled = true
    add_child(door_spill)
    door_spill_fill = OmniLight3D.new()
    door_spill_fill.name = "DoorSpillFill"
    door_spill_fill.position = Vector3(0, 1.2, HALF.z + 0.35)
    door_spill_fill.omni_range = 2.2
    door_spill_fill.light_color = Color(0.88, 0.94, 1.0)
    door_spill_fill.light_energy = 0.0
    add_child(door_spill_fill)

func _build_collision() -> void:
    var body := StaticBody3D.new()
    body.name = "RoomBody"
    add_child(body)
    var h := HALF
    var t := 0.1
    var boxes := [
        [Vector3(0, -t * 0.5, 0), Vector3(2 * h.x, t, 2 * h.z)],
        [Vector3(0, 2 * h.y + t * 0.5, 0), Vector3(2 * h.x, t, 2 * h.z)],
        [Vector3(0, h.y, -h.z - t * 0.5), Vector3(2 * h.x, 2 * h.y, t)],
        [Vector3(-h.x - t * 0.5, h.y, 0), Vector3(t, 2 * h.y, 2 * h.z)],
        [Vector3(h.x + t * 0.5, h.y, 0), Vector3(t, 2 * h.y, 2 * h.z)],
        [Vector3(-(h.x + DOOR_HALF_W) * 0.5, h.y, h.z + t * 0.5), Vector3(h.x - DOOR_HALF_W, 2 * h.y, t)],
        [Vector3((h.x + DOOR_HALF_W) * 0.5, h.y, h.z + t * 0.5), Vector3(h.x - DOOR_HALF_W, 2 * h.y, t)],
        [Vector3(0, (DOOR_H + 2 * h.y) * 0.5, h.z + t * 0.5), Vector3(2 * DOOR_HALF_W, 2 * h.y - DOOR_H, t)],
        [toilet.position + Vector3(0, 0.4, 0.2), Vector3(0.45, 0.8, 0.5)],
        [Vector3(-h.x + 0.25, 0.45, -0.35), Vector3(0.5, 0.9, 0.45)],
        [DRAWER_CENTER + Vector3(-DRAWER_SIZE.x * 0.5, 0, 0), DRAWER_SIZE],
    ]
    for b in boxes:
        var cs := CollisionShape3D.new()
        var bs := BoxShape3D.new()
        bs.size = b[1]
        cs.shape = bs
        cs.position = b[0]
        body.add_child(cs)

# --- runtime --------------------------------------------------------------------

func set_door_open(open: bool, instant: bool = false) -> void:
    _door_target = deg_to_rad(100.0) if open else 0.0
    if instant:
        door_pivot.rotation.y = _door_target
        _update_door_spill()

func is_door_open() -> bool:
    return absf(_door_target) > 0.01

func set_tank_open(open: bool, instant: bool = false) -> void:
    _lid_target = deg_to_rad(-75.0) if open else 0.0
    if instant:
        tank_lid.rotation.x = _lid_target

func _process(delta: float) -> void:
    var k := 1.0 - exp(-delta * 6.0)
    door_pivot.rotation.y = lerpf(door_pivot.rotation.y, _door_target, k)
    tank_lid.rotation.x = lerpf(tank_lid.rotation.x, _lid_target, k)
    if tank_art != null:
        tank_art.call("set_lid_open", tank_lid.rotation.x / deg_to_rad(-75.0))
    _update_door_spill()

## 0 (shut) .. 1 (fully open), from the door's actual swing.
func door_open_amount() -> float:
    return clampf(door_pivot.rotation.y / deg_to_rad(100.0), 0.0, 1.0)

func _update_door_spill() -> void:
    if door_spill == null:
        return
    var k := door_open_amount()
    door_spill.light_energy = DOOR_SPILL_ENERGY * k
    door_spill_fill.light_energy = DOOR_FILL_ENERGY * k
    door_spill.visible = k > 0.01
    door_spill_fill.visible = k > 0.01

## Is this world point inside the room box?
func contains(p: Vector3) -> bool:
    var l := p - global_position
    return absf(l.x) <= HALF.x and l.y >= 0.0 and l.y <= 2 * HALF.y and absf(l.z) <= HALF.z
