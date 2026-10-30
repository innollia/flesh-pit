extends Node3D

## Structure: a 1950s service elevator car swallowed by the rib vault of the
## mantle. Brushed steel walls with a handrail, centre-opening sliding doors
## on the +Z side stuck half open, a floor indicator over the door made of a
## row of round lamps with only the lowest one lit (no digits), a button panel
## of plain round buttons, a domed ceiling lamp, and the roof hatch forced up
## by white-blue cartilage pushing down into the car. It carried goods and
## staff between floors; now a cartilage rib frames its doorway. The plate on
## the back wall tells what the player meets here: a car with an up arrow,
## crossed out (the way up is closed; you can only go on down).
## Origin = pocket floor centre, mouth +Z. Public: pocket_half(), set_light(on).

const K := preload("res://main/art/fp_art_kit.gd")
const POCKET_HALF := Vector3(1.0, 1.2, 1.0)
const C := 0.85
const H := 2.2
const CART_A := Color(0.82, 0.84, 0.9)
const CART_B := Color(0.7, 0.55, 0.6)
const STEEL := Color(0.66, 0.66, 0.64)
const STEEL_D := Color(0.45, 0.45, 0.44)
const LIT_FLOOR := 0
var _glow: MeshInstance3D
var _lamp: OmniLight3D

func pocket_half() -> Vector3:
    return POCKET_HALF

func _ready() -> void:
    var st := K.begin()
    var glow_st := K.begin()
    # --- floor, walls (back, sides), front jambs and header
    K.rbox(st, K.T(Vector3(0, 0.03, 0)), Vector3(C + 0.02, 0.03, C + 0.02), 0.01, Color(0.24, 0.24, 0.23), Color(0.18, 0.18, 0.18))
    K.rbox(st, K.T(Vector3(0, H * 0.5, -C)), Vector3(C + 0.02, H * 0.5, 0.02), 0.008, STEEL, STEEL_D)
    for sx in [-1.0, 1.0]:
        K.rbox(st, K.T(Vector3(sx * C, H * 0.5, 0)), Vector3(0.02, H * 0.5, C), 0.008, STEEL, STEEL_D)
        K.rbox(st, K.T(Vector3(sx * 0.675, H * 0.5, C)), Vector3(0.175 + 0.02, H * 0.5, 0.02), 0.008, STEEL, STEEL_D)
    K.rbox(st, K.T(Vector3(0, 2.1, C)), Vector3(0.5, 0.1, 0.02), 0.008, STEEL, STEEL_D)
    K.rbox(st, K.T(Vector3(0, 0.065, C - 0.01)), Vector3(0.55, 0.008, 0.04), 0.004, Color(0.55, 0.5, 0.35))
    # panel seams and kick plates on the inner faces
    for i in range(2):
        var s := -0.28 + i * 0.56
        K.rbox(st, K.T(Vector3(s, H * 0.5, -C + 0.022)), Vector3(0.006, H * 0.5 - 0.02, 0.003), 0.0, STEEL_D)
        for sx in [-1.0, 1.0]:
            K.rbox(st, K.T(Vector3(sx * (C - 0.022), H * 0.5, s)), Vector3(0.003, H * 0.5 - 0.02, 0.006), 0.0, STEEL_D)
    K.rbox(st, K.T(Vector3(0, 0.15, -C + 0.025)), Vector3(C - 0.02, 0.09, 0.006), 0.003, STEEL_D.darkened(0.2))
    for sx in [-1.0, 1.0]:
        K.rbox(st, K.T(Vector3(sx * (C - 0.025), 0.15, 0)), Vector3(0.006, 0.09, C - 0.02), 0.003, STEEL_D.darkened(0.2))
    # --- ceiling with a hatch opening (x -0.05..0.45, z -0.55..-0.05)
    var cy := H + 0.03
    K.rbox(st, K.T(Vector3(0, cy, -0.7)), Vector3(C + 0.02, 0.03, 0.17), 0.008, STEEL.darkened(0.1))
    K.rbox(st, K.T(Vector3(0, cy, 0.4)), Vector3(C + 0.02, 0.03, 0.47), 0.008, STEEL.darkened(0.1))
    K.rbox(st, K.T(Vector3(-0.45, cy, -0.3)), Vector3(0.4, 0.03, 0.25), 0.008, STEEL.darkened(0.1))
    K.rbox(st, K.T(Vector3(0.65, cy, -0.3)), Vector3(0.2, 0.03, 0.25), 0.008, STEEL.darkened(0.1))
    # hatch lid forced up on its +X hinge
    var lid := K.T(Vector3(0.45, H + 0.06, -0.3)) * K.T(Vector3.ZERO, Vector3(0, 0, -55)) * K.T(Vector3(-0.25, 0.0, 0.0))
    K.rbox(st, lid, Vector3(0.25, 0.015, 0.25), 0.006, STEEL.darkened(0.2), STEEL_D)
    # --- handrails with brackets
    var rail := Color(0.75, 0.74, 0.7)
    K.tube(st, Transform3D.IDENTITY, [Vector3(-0.68, 0.9, -C + 0.07), Vector3(0.68, 0.9, -C + 0.07)], [0.02], 6, [rail])
    for sx in [-1.0, 1.0]:
        K.tube(st, Transform3D.IDENTITY, [Vector3(sx * (C - 0.07), 0.9, -0.68), Vector3(sx * (C - 0.07), 0.9, 0.45)], [0.02], 6, [rail])
        for bz in [-0.55, 0.35]:
            K.tube(st, Transform3D.IDENTITY, [Vector3(sx * (C - 0.02), 0.9, bz), Vector3(sx * (C - 0.07), 0.9, bz)], [0.012], 4, [STEEL_D])
        K.tube(st, Transform3D.IDENTITY, [Vector3(sx * 0.55, 0.9, -C + 0.02), Vector3(sx * 0.55, 0.9, -C + 0.07)], [0.012], 4, [STEEL_D])
    # --- sliding doors stuck half open (just inside the front wall)
    for sx in [-1.0, 1.0]:
        K.rbox(st, K.T(Vector3(sx * 0.6, 1.0, C - 0.045)), Vector3(0.25, 1.0, 0.015), 0.006, STEEL.darkened(0.08), STEEL_D)
        K.rbox(st, K.T(Vector3(sx * 0.36, 1.0, C - 0.045)), Vector3(0.012, 0.98, 0.02), 0.004, Color(0.12, 0.12, 0.12))
    # --- floor indicator: a row of round lamps, outside (+Z) and inside (-Z)
    for side in [1.0, -1.0]:
        var pz: float = C + 0.025 * side
        K.rbox(st, K.T(Vector3(0, 2.1, pz)), Vector3(0.44, 0.065, 0.008), 0.004, Color(0.62, 0.5, 0.26), Color(0.4, 0.32, 0.16))
        for li in range(7):
            var lx := -0.36 + li * 0.12
            var rx: Vector3 = Vector3(90.0 * side, 0, 0)
            K.lathe(st, K.T(Vector3(lx, 2.1, pz + 0.006 * side), rx), [Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.04, 0.012), Vector2(0.03, 0.014)], 8, [Color(0.15, 0.13, 0.1)])
            var lamp_prof := [Vector2(0.03, 0.0), Vector2(0.028, 0.012), Vector2(0.0, 0.02)]
            if li == LIT_FLOOR:
                K.lathe(glow_st, K.T(Vector3(lx, 2.1, pz + 0.018 * side), rx), lamp_prof, 8, [Color(1.0, 0.75, 0.35)])
            else:
                K.lathe(st, K.T(Vector3(lx, 2.1, pz + 0.018 * side), rx), lamp_prof, 8, [Color(0.32, 0.24, 0.16)])
    # --- button panel on the +X wall by the door (plain round buttons)
    K.rbox(st, K.T(Vector3(C - 0.03, 1.22, 0.55)), Vector3(0.008, 0.3, 0.08), 0.004, Color(0.6, 0.5, 0.28), Color(0.4, 0.32, 0.16))
    for bi in range(9):
        var by := 1.46 - floorf(bi / 2.0) * 0.1
        var bz := 0.52 + (bi % 2) * 0.06
        if bi == 8:
            bz = 0.55
        var bcol := Color(0.72, 0.12, 0.1) if bi == 8 else Color(0.86, 0.83, 0.72)
        K.lathe(st, K.T(Vector3(C - 0.038, by, bz), Vector3(0, 0, 90)), [Vector2(0.0, 0.0), Vector2(0.02, 0.0), Vector2(0.018, 0.012), Vector2(0.0, 0.016)], 6, [bcol])
    # --- warning plate on the back wall
    _up_closed_plate(st, K.T(Vector3(0, 1.5, -C + 0.03)))
    # --- ceiling lamp housing
    K.lathe(st, K.T(Vector3(-0.35, H - 0.01, 0.35)), [Vector2(0.0, 0.0), Vector2(0.15, 0.0), Vector2(0.15, 0.02), Vector2(0.0, 0.02)], 10, [STEEL_D])
    K.add_mesh(self, "Car", K.finish(st, 3.0), K.mat("tex_chrome_128.png", 0.3, true))
    K.lathe(glow_st, K.T(Vector3(-0.35, H - 0.01, 0.35), Vector3(180, 0, 0)), [Vector2(0.12, 0.0), Vector2(0.1, 0.05), Vector2(0.0, 0.07)], 8, [Color(1.0, 0.96, 0.84)])
    _glow = K.add_mesh(self, "Glow", K.finish(glow_st), K.glow(Color(1, 1, 1)))
    _lamp = OmniLight3D.new()
    _lamp.name = "Lamp"
    _lamp.position = Vector3(-0.3, H - 0.3, 0.3)
    _lamp.omni_range = 2.5
    _lamp.light_color = Color(1.0, 0.95, 0.8)
    _lamp.light_energy = 0.6
    _lamp.shadow_enabled = false
    _lamp.light_cull_mask = 0xFFFFF & ~FPRestroom.ROOM_VISUAL_LAYER & ~FPMirrorReflection.HANDS_ROOM_LAYER & ~FPMirrorReflection.MIRROR_BODY_LAYER & ~FPMirror.HOLO_LAYER
    add_child(_lamp)
    # --- cartilage: a mass pushing down through the hatch, a rib over the door
    st = K.begin()
    _growth(st, Vector3(0.2, 2.42, -0.3), 0.3, 0, 0)
    _growth(st, Vector3(0.18, 2.12, -0.32), 0.17, 1, 2)
    var rib := [Vector3(-0.98, -0.1, 0.98), Vector3(-0.97, 1.0, 0.99), Vector3(-0.93, 1.9, 1.0), Vector3(-0.6, 2.36, 1.02), Vector3(0.0, 2.48, 1.0), Vector3(0.6, 2.38, 1.02), Vector3(0.94, 1.9, 0.99), Vector3(0.98, 0.9, 0.98), Vector3(0.99, -0.1, 0.97)]
    K.tube(st, Transform3D.IDENTITY, rib, [0.13, 0.11, 0.1, 0.09, 0.085, 0.09, 0.1, 0.11, 0.13], 7, [CART_A, CART_A, CART_A.lerp(CART_B, 0.3), CART_A], true, 0.65)
    var rib2 := [Vector3(-0.99, 2.0, -0.95), Vector3(-0.6, 2.42, -0.98), Vector3(0.1, 2.5, -0.99), Vector3(0.7, 2.4, -0.97), Vector3(0.99, 1.9, -0.98)]
    K.tube(st, Transform3D.IDENTITY, rib2, [0.09, 0.08, 0.075, 0.08, 0.09], 6, [CART_A, CART_B.lerp(CART_A, 0.5)], true, 0.65)
    _growth(st, Vector3(-0.98, 0.15, 0.98), 0.2, 2, 1)
    _growth(st, Vector3(0.98, 1.95, 0.98), 0.18, 3, 1)
    _growth(st, Vector3(-0.98, 2.3, -0.98), 0.24, 4, 1)
    K.add_mesh(self, "Cartilage", K.finish(st, 3.0), K.mat("tex_membrane_128.png", 0.5, true))

## A car outline with an up arrow, crossed out in red.
func _up_closed_plate(st: SurfaceTool, t: Transform3D) -> void:
    K.rbox(st, t, Vector3(0.16, 0.16, 0.008), 0.005, Color(0.88, 0.86, 0.78), Color(0.35, 0.33, 0.3))
    var ink := Color(0.06, 0.06, 0.06)
    var z := 0.01
    var b0 := Vector2(-0.075, -0.115)
    var b1 := Vector2(0.075, 0.035)
    _bar(st, t, Vector2(b0.x - 0.007, b0.y), Vector2(b1.x + 0.007, b0.y), 0.014, z, ink)
    _bar(st, t, Vector2(b0.x - 0.007, b1.y), Vector2(-0.025, b1.y), 0.014, z, ink)
    _bar(st, t, Vector2(0.025, b1.y), Vector2(b1.x + 0.007, b1.y), 0.014, z, ink)
    _bar(st, t, Vector2(b0.x, b0.y), Vector2(b0.x, b1.y), 0.014, z, ink)
    _bar(st, t, Vector2(b1.x, b0.y), Vector2(b1.x, b1.y), 0.014, z, ink)
    _bar(st, t, Vector2(0, -0.085), Vector2(0, 0.08), 0.026, z, ink)
    _poly(st, t, [Vector2(-0.05, 0.07), Vector2(0.05, 0.07), Vector2(0.0, 0.135)], z, ink)
    var red := Color(0.78, 0.07, 0.05)
    _bar(st, t, Vector2(-0.12, -0.12), Vector2(0.12, 0.12), 0.026, z + 0.002, red)
    _bar(st, t, Vector2(-0.12, 0.12), Vector2(0.12, -0.12), 0.026, z + 0.002, red)

## Cartilage knot with fused satellites and `spurs` x 3 short hanging spurs.
func _growth(st: SurfaceTool, gp: Vector3, r: float, i: int, spurs: int) -> void:
    var c := _keep(gp, r * 1.45)
    K.blob(st, Transform3D.IDENTITY, c, Vector3(r, r * 0.75, r), 0.35, 90 + i, CART_A, CART_B)
    for j in range(3):
        var off := Vector3(K.h(i, j, 31) - 0.5, (K.h(i, j, 32) - 0.5) * 0.6, K.h(i, j, 33) - 0.5).normalized() * r * 0.75
        var sr := r * (0.35 + K.h(i, j, 34) * 0.3)
        K.blob(st, Transform3D.IDENTITY, _keep(c + off, sr * 1.45), Vector3(sr, sr * 0.8, sr), 0.4, 200 + i * 7 + j, CART_B, CART_A)
    for j in range(spurs * 3):
        var ang := K.h(i, j, 41) * TAU
        var d := Vector3(cos(ang), -0.6 - K.h(i, j, 42) * 0.6, sin(ang)).normalized()
        var p0 := c + d * r * 0.7
        var p1 := _keep(p0 + d * (0.2 + K.h(i, j, 43) * 0.2), 0.04)
        K.tube(st, Transform3D.IDENTITY, [p0, (p0 + p1) * 0.5 + Vector3(0.03, 0.0, 0.0), p1], [0.045, 0.03, 0.012], 5, [CART_A, CART_B])

## Clamp a point so a part reaching `r` around it stays in the pocket + 0.28 m.
func _keep(p: Vector3, r: float) -> Vector3:
    var g := 0.28 - r
    return p.clamp(Vector3(-POCKET_HALF.x - g, -g, -POCKET_HALF.z - g), Vector3(POCKET_HALF.x + g, POCKET_HALF.y * 2.0 + g, POCKET_HALF.z + g))

## Flat convex polygon in a local XY plane at depth z, facing +Z.
func _poly(st: SurfaceTool, t: Transform3D, pts: Array, z: float, col: Color) -> void:
    var a: Vector2 = pts[0]
    for i in range(1, pts.size() - 1):
        var b: Vector2 = pts[i]
        var c: Vector2 = pts[i + 1]
        K.tri(st, t, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(c.x, c.y, z), Vector3.BACK, col)

## Thick 2D stroke from a to b.
func _bar(st: SurfaceTool, t: Transform3D, a: Vector2, b: Vector2, w: float, z: float, col: Color) -> void:
    var d := (b - a).normalized()
    var n := Vector2(-d.y, d.x) * w * 0.5
    _poly(st, t, [a - n, b - n, b + n, a + n], z, col)

func set_light(on: bool) -> void:
    _glow.visible = on
    _lamp.visible = on
