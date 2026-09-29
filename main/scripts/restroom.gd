class_name FPRestroom
extends Node3D

## The clean white restroom (design-core 8): low-poly tiled walls/floor,
## ceiling light panel, toilet with an openable tank lid, sink with mirror,
## and a hinged door in the +Z wall. Beyond the doorway the flesh wall
## begins right away. Built entirely in code, flat-shaded vertex colours.

const HALF := Vector3(1.5, 1.3, 1.5) # room half-size (floor at y = 0)
const TILE := 0.3
const DOOR_HALF_W := 0.45
const DOOR_H := 2.05

var door_pivot: Node3D
var toilet: Node3D
var tank_lid: Node3D
var tank_items: Node3D
var bowl_center: Vector3
var _door_target: float = 0.0
var _lid_target: float = 0.0

func _ready() -> void:
    build()

func build() -> void:
    var tile_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_tile_wall_128.png", 2.5, false, 0.2, 0.5, 1.0, false)
    var fixture_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_fixture_128.png", 1.5, false, 0.35, 0.35, 1.0, false)
    var floor_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_tile_floor_128.png", 2.5, false, 0.25, 0.45, 1.0, false)
    _build_tiles(tile_mat, floor_mat)
    # 형님 결정: 변기·세면대는 얼룩 없는 순백 도자기(약한 광택).
    var ceramic_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_ceramic_128.png", 1.0, false, 0.45, 0.25, 1.0, false)
    _build_toilet(ceramic_mat)
    _build_sink(ceramic_mat)
    _build_door(fixture_mat)
    _build_korean(fixture_mat)
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
    _plane(st, Vector3(-h.x, 2 * h.y, -h.z), Vector3(2 * h.x, 0, 0), Vector3(0, 0, 2 * h.z), Vector3.DOWN, grout)
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
            var oc := Vector3(-h.x + i * TILE + gap, 2 * h.y - inset, -h.z + k * TILE + gap)
            _tile(st, oc, Vector3(TILE - 2 * gap, 0, 0), Vector3(0, 0, TILE - 2 * gap), Vector3.DOWN, Color(0.97, 0.97, 0.96))
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
    # tank
    _box(st, Vector3(-0.22, 0.42, 0.0), Vector3(0.22, 0.8, 0.17), white, shade)
    # flush lever
    _box(st, Vector3(-0.2, 0.72, 0.17), Vector3(-0.12, 0.745, 0.2), Color(0.75, 0.77, 0.8), Color(0.6, 0.62, 0.66))
    _add(st, mat, "Body", toilet)
    # tank lid on a hinge at the back so it can open to show purchased items
    tank_lid = Node3D.new()
    tank_lid.name = "TankLid"
    tank_lid.position = Vector3(0, 0.8, 0.0)
    toilet.add_child(tank_lid)
    var ls := SurfaceTool.new()
    ls.begin(Mesh.PRIMITIVE_TRIANGLES)
    _box(ls, Vector3(-0.235, 0.0, -0.01), Vector3(0.235, 0.035, 0.185), white, shade)
    _add(ls, mat, "Lid", tank_lid)
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
    # ceiling exhaust vent
    var cy := 2 * HALF.y - 0.005
    _box(st, Vector3(0.6, cy - 0.02, 0.6), Vector3(0.9, cy, 0.9), Color(0.93, 0.93, 0.94), Color(0.85, 0.85, 0.86))
    for i in range(4):
        var vz := 0.64 + i * 0.07
        _box(st, Vector3(0.63, cy - 0.024, vz), Vector3(0.87, cy - 0.02, vz + 0.025), Color(0.55, 0.56, 0.58), Color(0.5, 0.5, 0.52))
    _add(st, mat, "KoreanFixtures")

# --- sink, door, light, collision ---------------------------------------------

func _build_sink(mat: Material) -> void:
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

func _build_door(mat: Material) -> void:
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
        FDKLowPoly.add_quad(st, Vector3(0.12, pr[0], -0.021), Vector3(w - 0.12, pr[0], -0.021), Vector3(w - 0.12, pr[1], -0.021), Vector3(0.12, pr[1], -0.021), Vector3.FORWARD, Color(0.9, 0.9, 0.89))
    # handle
    _box(st, Vector3(w - 0.14, 0.98, -0.07), Vector3(w - 0.05, 1.01, -0.02), Color(0.75, 0.77, 0.8), Color(0.6, 0.62, 0.66))
    _add(st, mat, "Door", door_pivot)
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

## Is this world point inside the room box?
func contains(p: Vector3) -> bool:
    var l := p - global_position
    return absf(l.x) <= HALF.x and l.y >= 0.0 and l.y <= 2 * HALF.y and absf(l.z) <= HALF.z
