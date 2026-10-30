extends Node3D

## Structure: a 1970s metro fare-gate line swallowed by the rib vault of the
## mantle. A strip of cream-and-green tiled station wall on -Z, a tiled
## floor, three steel tripod turnstiles in a row across X (token slot on top,
## a red "closed" lamp on each), a broken ceiling fluorescent fixture hanging
## by one chain, and a hanging pictogram sign. The gate let paying passengers
## down to the platforms; the sign now warns what the vault below needs: an
## arrow pointing down beside a knife ("below here you need a blade": the
## cartilage ribs do not give to bare hands). White-blue cartilage ribs have
## grown up over the tiles and arch across the ceiling. Origin = pocket floor
## centre, mouth +Z. Public: pocket_half(), set_light(on).

const K := preload("res://main/art/fp_art_kit.gd")
const POCKET_HALF := Vector3(1.8, 1.2, 1.0)
const CART_A := Color(0.82, 0.84, 0.9)
const CART_B := Color(0.7, 0.55, 0.6)
const STEEL := Color(0.66, 0.67, 0.69)
const STEEL_EDGE := Color(0.42, 0.43, 0.45)
const GATES := [-1.35, -0.25, 0.85]
var _glow: MeshInstance3D
var _lamp: OmniLight3D

func pocket_half() -> Vector3:
    return POCKET_HALF

func _ready() -> void:
    var hx := POCKET_HALF.x
    var hz := POCKET_HALF.z
    var hh := POCKET_HALF.y * 2.0
    # --- tiled wall strip on -Z: dark green skirting, cream field, green band
    var st := K.begin()
    var wz := -hz + 0.02
    var bands := [[0.0, 0.18, Color(0.18, 0.36, 0.26)], [0.18, 1.0, Color(0.86, 0.83, 0.68)], [1.0, 1.16, Color(0.26, 0.5, 0.36)], [1.16, 1.22, Color(0.86, 0.83, 0.68)], [1.22, 1.28, Color(0.26, 0.5, 0.36)], [1.28, hh, Color(0.84, 0.8, 0.66)]]
    for b in bands:
        var y0: float = b[0]
        var y1: float = b[1]
        K.quad(st, Transform3D.IDENTITY, Vector3(-hx, y0, wz), Vector3(hx, y0, wz), Vector3(hx, y1, wz), Vector3(-hx, y1, wz), Vector3.BACK, b[2])
    # fallen tiles: flesh shows through
    for i in range(12):
        var tx := -hx + 0.2 + K.h(i, 3) * (hx * 2.0 - 0.4)
        var ty := 0.3 + K.h(i, 4) * 1.8
        var s := 0.12 + K.h(i, 5) * 0.12
        K.quad(st, Transform3D.IDENTITY, Vector3(tx, ty, wz + 0.004), Vector3(tx + s, ty, wz + 0.004), Vector3(tx + s, ty + s * 0.75, wz + 0.004), Vector3(tx, ty + s * 0.75, wz + 0.004), Vector3.BACK, Color(0.38, 0.09, 0.1).lerp(Color(0.2, 0.18, 0.15), K.h(i, 6)))
    K.add_mesh(self, "TileWall", K.finish(st, 4.0), K.mat("tex_tile_wall_128.png", 0.3, true))
    # --- tiled floor
    st = K.begin()
    K.quad(st, Transform3D.IDENTITY, Vector3(-hx, 0.004, -hz), Vector3(hx, 0.004, -hz), Vector3(hx, 0.004, hz), Vector3(-hx, 0.004, hz), Vector3.UP, Color(0.6, 0.58, 0.52))
    # worn yellow line along the gate line
    K.quad(st, Transform3D.IDENTITY, Vector3(-hx, 0.006, 0.55), Vector3(hx, 0.006, 0.55), Vector3(hx, 0.006, 0.62), Vector3(-hx, 0.006, 0.62), Vector3.UP, Color(0.75, 0.62, 0.2))
    K.add_mesh(self, "Floor", K.finish(st, 3.0), K.mat("tex_tile_floor_128.png", 0.3, true))
    # --- steel: turnstiles, sign, broken fixture
    st = K.begin()
    var glow_st := K.begin()
    for gi in range(GATES.size()):
        _turnstile(st, glow_st, GATES[gi], gi)
    # end panel closing the line against the -X flesh
    K.rbox(st, K.T(Vector3(-hx + 0.05, 0.5, 0.0)), Vector3(0.05, 0.5, 0.42), 0.015, STEEL.darkened(0.1), STEEL_EDGE)
    # hanging sign
    var sc := Vector3(0.3, 1.98, 0.45)
    for sx in [-0.36, 0.36]:
        K.tube(st, Transform3D.IDENTITY, [Vector3(sc.x + sx, hh + 0.2, sc.z), Vector3(sc.x + sx, sc.y + 0.1, sc.z)], [0.012], 5, [STEEL_EDGE])
    var sign_t := K.T(sc)
    K.rbox(st, sign_t, Vector3(0.46, 0.14, 0.03), 0.01, Color(0.12, 0.2, 0.42), Color(0.2, 0.22, 0.25))
    _blade_sign(st, sign_t * K.T(Vector3(0, 0, 0.032)))
    _blade_sign(st, sign_t * K.T(Vector3(0, 0, -0.032), Vector3(0, 180, 0)))
    # broken fluorescent fixture, fallen at one end
    var ft := K.T(Vector3(-0.95, 2.05, 0.2), Vector3(0, 0, -25))
    K.rbox(st, ft, Vector3(0.4, 0.03, 0.08), 0.01, Color(0.72, 0.72, 0.7), Color(0.5, 0.5, 0.48))
    var left_end: Vector3 = ft * Vector3(-0.36, 0.03, 0)
    var right_end: Vector3 = ft * Vector3(0.36, 0.03, 0)
    K.tube(st, Transform3D.IDENTITY, [left_end, Vector3(left_end.x, hh + 0.1, left_end.z)], [0.008], 4, [STEEL_EDGE])
    K.tube(st, Transform3D.IDENTITY, [right_end, right_end + Vector3(0.1, 0.25, 0.05), right_end + Vector3(0.05, 0.4, -0.02), Vector3(right_end.x + 0.1, hh + 0.1, right_end.z)], [0.006], 3, [Color(0.15, 0.15, 0.15)])
    # dead tube and the snapped stub of the lit one (dark glass)
    K.tube(st, ft, [Vector3(-0.35, -0.05, -0.03), Vector3(0.35, -0.05, -0.03)], [0.016], 5, [Color(0.55, 0.58, 0.6)])
    K.tube(st, ft, [Vector3(0.0, -0.05, 0.03), Vector3(0.07, -0.05, 0.03)], [0.016], 5, [Color(0.6, 0.62, 0.64)])
    K.tube(st, ft, [Vector3(0.35, -0.05, 0.03), Vector3(0.3, -0.05, 0.03)], [0.016], 5, [Color(0.6, 0.62, 0.64)])
    # glass shards on the floor below it
    for i in range(6):
        var p := Vector3(-0.75 + K.h(i, 11) * 0.5, 0.01, 0.0 + K.h(i, 12) * 0.5)
        var a := K.h(i, 13) * TAU
        K.tri(st, Transform3D.IDENTITY, p, p + Vector3(cos(a), 0, sin(a)) * 0.07, p + Vector3(cos(a + 1.2), 0, sin(a + 1.2)) * 0.05, Vector3.UP, Color(0.8, 0.85, 0.85))
    K.add_mesh(self, "Steel", K.finish(st, 3.0), K.mat("tex_chrome_128.png", 0.3, true))
    # glowing half of the broken tube
    K.tube(glow_st, ft, [Vector3(-0.35, -0.05, 0.03), Vector3(0.0, -0.05, 0.03)], [0.017], 6, [Color(0.85, 0.95, 1.0)])
    _glow = K.add_mesh(self, "Glow", K.finish(glow_st), K.glow(Color(1, 1, 1)))
    _lamp = OmniLight3D.new()
    _lamp.name = "Lamp"
    _lamp.position = Vector3(-0.8, 1.85, 0.25)
    _lamp.omni_range = 3.0
    _lamp.light_color = Color(0.8, 0.92, 1.0)
    _lamp.light_energy = 0.7
    _lamp.shadow_enabled = false
    _lamp.light_cull_mask = 0xFFFFF & ~FPRestroom.ROOM_VISUAL_LAYER & ~FPMirrorReflection.HANDS_ROOM_LAYER & ~FPMirrorReflection.MIRROR_BODY_LAYER & ~FPMirror.HOLO_LAYER
    add_child(_lamp)
    # --- cartilage: a spine along the wall top and ribs arching over the tiles
    st = K.begin()
    K.tube(st, Transform3D.IDENTITY, [Vector3(-hx - 0.15, 2.3, -hz + 0.1), Vector3(-0.6, 2.36, -hz + 0.12), Vector3(0.6, 2.32, -hz + 0.1), Vector3(hx + 0.15, 2.36, -hz + 0.12)], [0.11, 0.1], 7, [CART_A, CART_B], false)
    var ribs := [-1.55, -0.62, 0.42, 1.5]
    for ri in range(ribs.size()):
        var x: float = ribs[ri]
        var j := (K.h(ri, 21) - 0.5) * 0.12
        var pts := [Vector3(x + j, -0.1, -hz + 0.06), Vector3(x, 0.6, -hz + 0.08), Vector3(x - j, 1.4, -hz + 0.09), Vector3(x, 2.0, -hz + 0.12), Vector3(x + j, 2.36, -hz + 0.4), Vector3(x, 2.45, -0.1), Vector3(x - j, 2.42, 0.5), Vector3(x, 2.3, hz + 0.05)]
        K.tube(st, Transform3D.IDENTITY, pts, [0.14, 0.1, 0.085, 0.09, 0.085, 0.08, 0.07, 0.07], 6, [CART_A, CART_A, CART_A.lerp(CART_B, 0.3), CART_A], false, 0.6)
        _growth(st, Vector3(x, 0.12, -hz + 0.1), 0.22, ri, 1)
        _growth(st, Vector3(x, 2.3, -hz + 0.2), 0.14, ri + 10, 0)
        # short side ribs branching along the tiles
        if ri % 2 == 0:
            K.tube(st, Transform3D.IDENTITY, [Vector3(x, 1.2, -hz + 0.09), Vector3(x + 0.25, 1.35, -hz + 0.08), Vector3(x + 0.42, 1.7, -hz + 0.07)], [0.07, 0.05, 0.025], 5, [CART_A, CART_B], true, 0.6)
    _growth(st, Vector3(hx, 0.3, hz), 0.28, 30, 1)
    _growth(st, Vector3(-hx, 2.3, hz - 0.1), 0.26, 31, 1)
    _growth(st, Vector3(hx - 0.1, 2.3, -0.2), 0.24, 32, 1)
    K.add_mesh(self, "Cartilage", K.finish(st, 3.0), K.mat("tex_membrane_128.png", 0.5, true))

## One tripod turnstile: cabinet along Z at x = cx, hub on its +X side with
## three arms, the top one horizontal across the lane.
func _turnstile(st: SurfaceTool, glow_st: SurfaceTool, cx: float, gi: int) -> void:
    var dent := K.h(gi, 51) * 0.08
    K.rbox(st, K.T(Vector3(cx, 0.47, 0.0)), Vector3(0.13, 0.47, 0.42), 0.03, STEEL.darkened(dent), STEEL_EDGE)
    K.rbox(st, K.T(Vector3(cx, 0.955, 0.0)), Vector3(0.15, 0.015, 0.44), 0.008, Color(0.22, 0.22, 0.24))
    K.rbox(st, K.T(Vector3(cx, 0.03, 0.0)), Vector3(0.15, 0.03, 0.44), 0.01, Color(0.2, 0.2, 0.21))
    # token slot plate on top, at the +Z end
    K.rbox(st, K.T(Vector3(cx, 0.975, 0.3)), Vector3(0.07, 0.006, 0.06), 0.004, Color(0.75, 0.6, 0.3))
    K.quad(st, Transform3D.IDENTITY, Vector3(cx - 0.035, 0.982, 0.29), Vector3(cx + 0.035, 0.982, 0.29), Vector3(cx + 0.035, 0.982, 0.31), Vector3(cx - 0.035, 0.982, 0.31), Vector3.UP, Color(0.03, 0.03, 0.03))
    # a red "closed" lamp on the +Z end face
    K.lathe(glow_st, K.T(Vector3(cx, 0.8, 0.42), Vector3(90, 0, 0)), [Vector2(0.0, 0.0), Vector2(0.028, 0.0), Vector2(0.028, 0.01), Vector2(0.0, 0.016)], 8, [Color(1.0, 0.18, 0.12)])
    # hub on a stub, arms
    var hub := Vector3(cx + 0.36, 0.92, 0.05)
    K.tube(st, Transform3D.IDENTITY, [Vector3(cx + 0.12, 0.92, 0.05), hub], [0.05], 6, [STEEL_EDGE])
    var ht := K.T(hub, Vector3(45, 0, 0))
    K.lathe(st, ht, [Vector2(0.0, -0.05), Vector2(0.08, -0.05), Vector2(0.08, 0.04), Vector2(0.05, 0.06), Vector2(0.0, 0.06)], 8, [STEEL, STEEL, STEEL, STEEL.lightened(0.2)])
    var rot := deg_to_rad(K.h(gi, 52) * 20.0 - 10.0)
    for k in range(3):
        var phi := TAU * float(k) / 3.0 + rot
        var d := Vector3(cos(phi), 0, sin(phi))
        K.tube(st, ht, [d * 0.06, d * 0.47], [0.02], 6, [STEEL.lightened(0.1)])

## Pictogram: an arrow pointing down to a floor line, then a knife.
func _blade_sign(st: SurfaceTool, t: Transform3D) -> void:
    var w := Color(0.92, 0.92, 0.88)
    _bar(st, t, Vector2(-0.3, 0.09), Vector2(-0.3, -0.02), 0.04, 0.0, w)
    _poly(st, t, [Vector2(-0.37, -0.01), Vector2(-0.23, -0.01), Vector2(-0.3, -0.085)], 0.0, w)
    _bar(st, t, Vector2(-0.41, -0.1), Vector2(-0.19, -0.1), 0.014, 0.0, w)
    # knife: handle, guard, blade
    _poly(st, t, [Vector2(-0.12, -0.025), Vector2(-0.01, -0.025), Vector2(-0.01, 0.03), Vector2(-0.12, 0.03)], 0.0, Color(0.9, 0.7, 0.2))
    _bar(st, t, Vector2(0.005, -0.05), Vector2(0.005, 0.055), 0.016, 0.0, w)
    _poly(st, t, [Vector2(0.02, -0.03), Vector2(0.27, -0.03), Vector2(0.38, 0.045), Vector2(0.02, 0.045)], 0.0, w)

## Cartilage knot with fused satellites (and a few short spurs when spurs > 0).
func _growth(st: SurfaceTool, gp: Vector3, r: float, i: int, spurs: int) -> void:
    var c := _keep(gp, r * 1.45)
    K.blob(st, Transform3D.IDENTITY, c, Vector3(r, r * 0.75, r), 0.35, 90 + i, CART_A, CART_B)
    for j in range(3):
        var off := Vector3(K.h(i, j, 31) - 0.5, (K.h(i, j, 32) - 0.5) * 0.6, K.h(i, j, 33) - 0.5).normalized() * r * 0.75
        var sr := r * (0.35 + K.h(i, j, 34) * 0.3)
        K.blob(st, Transform3D.IDENTITY, _keep(c + off, sr * 1.45), Vector3(sr, sr * 0.8, sr), 0.4, 200 + i * 7 + j, CART_B, CART_A)
    for j in range(spurs * 3):
        var ang := K.h(i, j, 41) * TAU
        var d := Vector3(cos(ang), K.h(i, j, 42) - 0.5, sin(ang)).normalized()
        var p0 := c + d * r * 0.7
        var p1 := _keep(p0 + d * (0.25 + K.h(i, j, 43) * 0.2) + Vector3(0, -0.05, 0), 0.04)
        K.tube(st, Transform3D.IDENTITY, [p0, (p0 + p1) * 0.5 + Vector3(0, 0.04, 0), p1], [0.045, 0.03, 0.012], 5, [CART_A, CART_B])

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
