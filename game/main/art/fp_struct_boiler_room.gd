extends Node3D

## Structure: a 1930s boiler-room fragment swallowed by the fat caves of the
## core. A squat riveted coal/oil boiler lies along X against the back (-Z)
## wall; it once fed steam to a building through the pipes that now climb the
## walls and vanish into the ceiling flesh. Firebox door with a draft grille,
## a pressure gauge (dial and needle, no digits), a red valve wheel, a coal
## shovel left leaning on the wall, a caged amber bulkhead lamp. Soft yellow
## rendered fat has grown over the pipes and drips from them. Two pictogram
## plates warn about what the player meets here: "hot pipe / do not touch"
## (hand, heat waves, slash) and "the gap closes" (two arrows meeting: the
## fat is soft and regrows quickly). Origin = pocket floor centre, mouth +Z.
## Public: pocket_half(), set_light(on).

const K := preload("res://main/art/fp_art_kit.gd")
const POCKET_HALF := Vector3(1.4, 1.2, 1.4)
const FAT_A := Color(0.86, 0.74, 0.38)
const FAT_B := Color(0.95, 0.86, 0.55)
var _bulb: MeshInstance3D
var _lamp: OmniLight3D

func pocket_half() -> Vector3:
    return POCKET_HALF

func _ready() -> void:
    var iron := Color(0.28, 0.3, 0.27)
    var rust := Color(0.42, 0.24, 0.14)
    var pipe := Color(0.4, 0.3, 0.24)
    var brass := Color(0.62, 0.5, 0.26)
    var st := K.begin()
    # --- boiler shell: a lathe whose axis (local +Y) is turned onto world +X
    var bt := K.T(Vector3(0, 0.72, -0.92), Vector3(0, 0, -90))
    K.lathe(st, bt, [Vector2(0.0, -1.12), Vector2(0.3, -1.1), Vector2(0.5, -1.04), Vector2(0.56, -0.96), Vector2(0.56, 0.96), Vector2(0.5, 1.04), Vector2(0.3, 1.1), Vector2(0.0, 1.12)], 14, [iron.darkened(0.15), iron, rust, iron, rust, iron, iron.darkened(0.15)])
    # riveted seam bands and their rivets
    for si in range(4):
        var y := -0.96 + si * 0.64
        K.lathe(st, bt, [Vector2(0.555, y - 0.035), Vector2(0.585, y - 0.035), Vector2(0.585, y + 0.035), Vector2(0.555, y + 0.035)], 14, [iron.darkened(0.2), iron.lerp(rust, 0.4), iron.darkened(0.2)])
        for ri in range(10):
            var a := TAU * (float(ri) + 0.5) / 10.0
            K.rbox(st, bt * K.T(Vector3(cos(a) * 0.595, y, sin(a) * 0.595)), Vector3(0.012, 0.012, 0.012), 0.0, iron.lerp(rust, K.h(si, ri, 5) * 0.7))
    # longitudinal rivet row along the upper front
    for ri in range(12):
        var a2 := PI * 0.75
        K.rbox(st, bt * K.T(Vector3(cos(a2) * 0.565, -0.88 + ri * 0.16, sin(a2) * 0.565)), Vector3(0.011, 0.011, 0.011), 0.0, iron.lerp(rust, K.h(ri, 9) * 0.6))
    # saddles
    for sx in [-0.7, 0.7]:
        K.rbox(st, K.T(Vector3(sx, 0.12, -0.92)), Vector3(0.08, 0.12, 0.38), 0.02, Color(0.24, 0.23, 0.22), rust)
    # --- firebox at the -X end, door on its +Z face with a draft grille
    K.rbox(st, K.T(Vector3(-0.72, 0.46, -0.33)), Vector3(0.3, 0.42, 0.1), 0.025, iron.darkened(0.25), rust)
    K.rbox(st, K.T(Vector3(-0.72, 0.5, -0.215)), Vector3(0.2, 0.2, 0.015), 0.012, Color(0.2, 0.2, 0.19), rust.darkened(0.2))
    K.quad(st, Transform3D.IDENTITY, Vector3(-0.85, 0.35, -0.199), Vector3(-0.59, 0.35, -0.199), Vector3(-0.59, 0.45, -0.199), Vector3(-0.85, 0.45, -0.199), Vector3.BACK, Color(0.04, 0.03, 0.03))
    for gi in range(6):
        var gx := -0.84 + gi * 0.048
        K.tube(st, Transform3D.IDENTITY, [Vector3(gx, 0.35, -0.193), Vector3(gx, 0.45, -0.193)], [0.008], 4, [Color(0.3, 0.29, 0.27)])
    for hy in [0.38, 0.62]:
        K.rbox(st, K.T(Vector3(-0.93, hy, -0.2)), Vector3(0.025, 0.03, 0.02), 0.006, Color(0.25, 0.24, 0.22))
    K.tube(st, Transform3D.IDENTITY, [Vector3(-0.56, 0.55, -0.2), Vector3(-0.56, 0.55, -0.15), Vector3(-0.56, 0.62, -0.15)], [0.012], 5, [Color(0.35, 0.33, 0.3)])
    # --- coal spilled in front of the firebox
    for ci in range(6):
        var cp := Vector3(-0.5 + K.h(ci, 1) * 0.5, 0.03, -0.12 + K.h(ci, 2) * 0.25)
        var cr := 0.05 + K.h(ci, 3) * 0.06
        K.blob(st, Transform3D.IDENTITY, cp, Vector3(cr, cr * 0.6, cr), 0.35, 40 + ci, Color(0.07, 0.07, 0.08), Color(0.15, 0.14, 0.14))
    # --- pipe runs climbing into the ceiling flesh
    var pipes := [
        [Vector3(-0.3, 1.2, -0.95), Vector3(-0.3, 1.6, -0.97), Vector3(-0.3, 2.0, -1.05), Vector3(-0.3, 2.3, -1.15), Vector3(-0.3, 2.62, -1.2)],
        [Vector3(1.08, 0.95, -0.85), Vector3(1.22, 0.95, -0.85), Vector3(1.3, 1.02, -0.85), Vector3(1.32, 1.4, -0.85), Vector3(1.32, 2.1, -0.85), Vector3(1.3, 2.62, -0.9)],
        [Vector3(-1.45, 2.06, -1.3), Vector3(-0.5, 2.06, -1.3), Vector3(0.6, 2.06, -1.3), Vector3(1.45, 2.06, -1.3)],
        [Vector3(-0.95, 0.88, -0.4), Vector3(-1.15, 0.92, -0.4), Vector3(-1.3, 1.05, -0.4), Vector3(-1.32, 1.6, -0.42), Vector3(-1.32, 2.62, -0.45)],
    ]
    for pi in range(pipes.size()):
        var pts: Array = pipes[pi]
        K.tube(st, Transform3D.IDENTITY, pts, [0.055], 7, [pipe.lerp(rust, K.h(pi, 3) * 0.5)])
        # flanges at every second joint
        for k in range(1, pts.size() - 1, 2):
            var a: Vector3 = pts[k - 1]
            var b: Vector3 = pts[k + 1]
            var d := (b - a).normalized()
            var p: Vector3 = pts[k]
            K.tube(st, Transform3D.IDENTITY, [p - d * 0.02, p + d * 0.02], [0.08], 7, [pipe.darkened(0.25)])
    # wall brackets on the long back pipe
    for bx in [-1.0, 0.0, 1.0]:
        K.rbox(st, K.T(Vector3(bx, 2.06, -1.38)), Vector3(0.03, 0.09, 0.06), 0.008, Color(0.25, 0.24, 0.22))
    # --- pressure gauge on a stub above the boiler (dial, ticks, needle)
    K.tube(st, Transform3D.IDENTITY, [Vector3(0.12, 1.2, -0.7), Vector3(0.12, 1.44, -0.7)], [0.02], 5, [brass.darkened(0.3)])
    var gt := K.T(Vector3(0.12, 1.56, -0.7), Vector3(90, 0, 0))
    K.lathe(st, gt, [Vector2(0.0, 0.0), Vector2(0.115, 0.0), Vector2(0.115, 0.045), Vector2(0.1, 0.05), Vector2(0.0, 0.05)], 12, [brass.darkened(0.2), brass, brass.lightened(0.2), Color(0.86, 0.83, 0.72)])
    var face := K.T(Vector3(0.12, 1.56, -0.7 + 0.052))
    for ti in range(9):
        var ang := deg_to_rad(225.0 - ti * 33.75)
        var dir := Vector2(cos(ang), sin(ang))
        var tick_col := Color(0.7, 0.08, 0.06) if ti >= 7 else Color(0.08, 0.08, 0.08)
        _bar(st, face, dir * 0.07, dir * 0.09, 0.008, 0.002, tick_col)
    var nd := Vector2(cos(deg_to_rad(-20.0)), sin(deg_to_rad(-20.0)))
    _bar(st, face, -nd * 0.015, nd * 0.085, 0.009, 0.004, Color(0.05, 0.05, 0.05))
    _poly(st, face, [Vector2(-0.012, -0.012), Vector2(0.012, -0.012), Vector2(0.012, 0.012), Vector2(-0.012, 0.012)], 0.005, Color(0.1, 0.1, 0.1))
    # --- red valve wheel on the right-hand riser, stem towards the room
    K.lathe(st, K.T(Vector3(1.32, 1.3, -0.85)), [Vector2(0.06, -0.08), Vector2(0.085, -0.04), Vector2(0.085, 0.04), Vector2(0.06, 0.08)], 7, [brass.darkened(0.35)])
    K.tube(st, Transform3D.IDENTITY, [Vector3(1.32, 1.3, -0.85), Vector3(1.32, 1.3, -0.58)], [0.014], 5, [Color(0.5, 0.48, 0.44)])
    var wheel_red := Color(0.62, 0.08, 0.06)
    var ring: Array = []
    for wi in range(13):
        var wa := TAU * float(wi) / 12.0
        ring.append(Vector3(1.32 + cos(wa) * 0.13, 1.3 + sin(wa) * 0.13, -0.6))
    K.tube(st, Transform3D.IDENTITY, ring, [0.016], 5, [wheel_red], false)
    for si2 in range(4):
        var sa := TAU * float(si2) / 4.0 + 0.4
        K.tube(st, Transform3D.IDENTITY, [Vector3(1.32, 1.3, -0.6), Vector3(1.32 + cos(sa) * 0.13, 1.3 + sin(sa) * 0.13, -0.6)], [0.01], 4, [wheel_red.darkened(0.2)])
    K.lathe(st, K.T(Vector3(1.32, 1.3, -0.62), Vector3(90, 0, 0)), [Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.04), Vector2(0.0, 0.04)], 6, [wheel_red.darkened(0.3)])
    # --- coal shovel leaning on the +X wall
    var top := Vector3(1.36, 1.12, 0.5)
    var bot := Vector3(1.06, 0.26, 0.5)
    K.tube(st, Transform3D.IDENTITY, [top, bot], [0.018], 5, [Color(0.45, 0.32, 0.18)])
    K.tube(st, Transform3D.IDENTITY, [top + Vector3(0.0, 0.0, -0.06), top + Vector3(0.03, 0.1, -0.05), top + Vector3(0.03, 0.1, 0.05), top + Vector3(0.0, 0.0, 0.06)], [0.012], 4, [Color(0.4, 0.28, 0.16)])
    K.rbox(st, K.T(Vector3(1.0, 0.13, 0.5), Vector3(0, 0, -18.4)), Vector3(0.012, 0.15, 0.13), 0.006, Color(0.3, 0.3, 0.3), rust)
    # --- caged bulkhead lamp on the -X wall (base, cage; the glass is a glow mesh)
    K.rbox(st, K.T(Vector3(-1.37, 1.75, 0.3)), Vector3(0.03, 0.1, 0.1), 0.01, Color(0.22, 0.22, 0.2))
    for ci2 in range(4):
        var ca := TAU * float(ci2) / 4.0 + PI * 0.25
        var o := Vector3(0, sin(ca), cos(ca))
        K.tube(st, Transform3D.IDENTITY, [Vector3(-1.34, 1.75, 0.3) + o * 0.085, Vector3(-1.26, 1.75, 0.3) + o * 0.085, Vector3(-1.2, 1.75, 0.3) + o * 0.05, Vector3(-1.19, 1.75, 0.3)], [0.007], 4, [Color(0.2, 0.2, 0.19)], false)
    # --- pictogram plates on the back wall above the boiler
    _hot_plate(st, K.T(Vector3(0.62, 1.78, -1.38)))
    _regrow_plate(st, K.T(Vector3(-0.92, 1.72, -1.38)))
    K.add_mesh(self, "Boiler", K.finish(st, 3.0), K.mat("tex_door_paint_128.png", 0.3, true))
    # --- the lamp glass (glow)
    st = K.begin()
    K.lathe(st, K.T(Vector3(-1.34, 1.75, 0.3), Vector3(0, 0, -90)), [Vector2(0.07, 0.0), Vector2(0.075, 0.05), Vector2(0.06, 0.11), Vector2(0.0, 0.13)], 8, [Color(1.0, 0.72, 0.4)])
    _bulb = K.add_mesh(self, "LampGlass", K.finish(st), K.glow(Color(1, 1, 1)))
    _lamp = OmniLight3D.new()
    _lamp.name = "Lamp"
    _lamp.position = Vector3(-1.12, 1.75, 0.3)
    _lamp.omni_range = 3.0
    _lamp.light_color = Color(1.0, 0.7, 0.35)
    _lamp.light_energy = 0.7
    _lamp.shadow_enabled = false
    _lamp.light_cull_mask = 0xFFFFF & ~FPRestroom.ROOM_VISUAL_LAYER & ~FPMirrorReflection.HANDS_ROOM_LAYER & ~FPMirrorReflection.MIRROR_BODY_LAYER & ~FPMirror.HOLO_LAYER
    add_child(_lamp)
    # --- rendered-fat overgrowth on pipes, ceiling corners and the boiler
    st = K.begin()
    var growth := [
        [Vector3(-0.3, 2.35, -1.15), 0.32], [Vector3(1.3, 2.35, -0.9), 0.3], [Vector3(-1.3, 2.3, -0.45), 0.3],
        [Vector3(1.15, 2.25, -1.3), 0.26], [Vector3(-1.25, 1.0, -1.25), 0.3], [Vector3(1.0, 1.1, -1.25), 0.24],
        [Vector3(-1.3, 0.2, 1.2), 0.3], [Vector3(1.3, 2.3, 1.2), 0.32], [Vector3(-0.2, 2.4, 0.4), 0.26],
    ]
    for i in range(growth.size()):
        var g: Array = growth[i]
        _growth(st, g[0], g[1], i, 0.45 if i < 6 else 0.25)
    K.add_mesh(self, "FatGrowth", K.finish(st, 3.0), K.mat("tex_fat_128.png", 0.8, true))

## "Hot pipe, do not touch": a pipe with heat waves and a hand inside a red
## circle-slash. The pipes here are the only warm things in the fat caves.
func _hot_plate(st: SurfaceTool, t: Transform3D) -> void:
    K.rbox(st, t, Vector3(0.24, 0.17, 0.01), 0.008, Color(0.86, 0.7, 0.16), Color(0.3, 0.26, 0.12))
    var ink := Color(0.06, 0.06, 0.06)
    var z := 0.012
    _bar(st, t, Vector2(-0.22, -0.12), Vector2(0.22, -0.12), 0.04, z, ink)
    for wi in range(2):
        var wx := -0.18 + wi * 0.07
        var prev := Vector2(wx, -0.09)
        for k in range(1, 7):
            var p := Vector2(wx + (0.018 if k % 2 == 1 else -0.018), -0.09 + k * 0.038)
            _bar(st, t, prev, p, 0.014, z, Color(0.75, 0.2, 0.05))
            prev = p
    # hand reaching down: palm, four fingers, thumb
    var hc := Vector2(0.08, 0.03)
    _poly(st, t, [hc + Vector2(-0.04, -0.01), hc + Vector2(0.04, -0.01), hc + Vector2(0.032, 0.07), hc + Vector2(-0.032, 0.07)], z, ink)
    for fi in range(4):
        var fx := hc.x - 0.039 + fi * 0.026
        _bar(st, t, Vector2(fx, hc.y), Vector2(fx + (fi - 1.5) * 0.008, hc.y - 0.085 + absf(fi - 1.5) * 0.014), 0.013, z, ink)
    _bar(st, t, hc + Vector2(0.035, 0.02), hc + Vector2(0.085, -0.01), 0.014, z, ink)
    # red circle and slash around the hand
    var red := Color(0.75, 0.06, 0.05)
    var rc := Vector2(0.08, 0.0)
    for k in range(16):
        var a0 := TAU * float(k) / 16.0
        var a1 := TAU * float(k + 1) / 16.0
        _bar(st, t, rc + Vector2(cos(a0), sin(a0)) * 0.125, rc + Vector2(cos(a1), sin(a1)) * 0.125, 0.018, z + 0.001, red)
    _bar(st, t, rc + Vector2(-0.088, 0.088), rc + Vector2(0.088, -0.088), 0.018, z + 0.002, red)
    _screws(st, t, Vector2(0.22, 0.15))

## "The gap closes": two arrows driving at each other between walls of fat.
## The fat is soft to dig but regrows quickly behind you.
func _regrow_plate(st: SurfaceTool, t: Transform3D) -> void:
    K.rbox(st, t, Vector3(0.2, 0.15, 0.01), 0.008, Color(0.86, 0.7, 0.16), Color(0.3, 0.26, 0.12))
    var ink := Color(0.06, 0.06, 0.06)
    var z := 0.012
    var fat := Color(0.78, 0.5, 0.22)
    _poly(st, t, [Vector2(-0.18, -0.12), Vector2(-0.12, -0.12), Vector2(-0.1, 0.0), Vector2(-0.12, 0.12), Vector2(-0.18, 0.12)], z, fat)
    _poly(st, t, [Vector2(0.18, -0.12), Vector2(0.18, 0.12), Vector2(0.12, 0.12), Vector2(0.1, 0.0), Vector2(0.12, -0.12)], z, fat)
    for s in [-1.0, 1.0]:
        _bar(st, t, Vector2(0.105 * s, 0.0), Vector2(0.06 * s, 0.0), 0.04, z + 0.001, ink)
        _poly(st, t, [Vector2(0.065 * s, 0.075), Vector2(0.065 * s, -0.075), Vector2(0.008 * s, 0.0)], z + 0.001, ink)
    _screws(st, t, Vector2(0.18, 0.13))

func _screws(st: SurfaceTool, t: Transform3D, at: Vector2) -> void:
    for sx in [-1.0, 1.0]:
        for sy in [-1.0, 1.0]:
            K.rbox(st, t * K.T(Vector3(at.x * sx, at.y * sy, 0.012)), Vector3(0.008, 0.008, 0.004), 0.0, Color(0.4, 0.38, 0.33))

## Fat mass with fused satellites and drips hanging from it.
func _growth(st: SurfaceTool, gp: Vector3, r: float, i: int, drip: float) -> void:
    var c := _keep(gp, r * 1.45)
    K.blob(st, Transform3D.IDENTITY, c, Vector3(r, r * 0.7, r), 0.4, 90 + i, FAT_A, FAT_B)
    for j in range(3):
        var off := Vector3(K.h(i, j, 31) - 0.5, (K.h(i, j, 32) - 0.5) * 0.6, K.h(i, j, 33) - 0.5).normalized() * r * 0.75
        var sr := r * (0.35 + K.h(i, j, 34) * 0.3)
        K.blob(st, Transform3D.IDENTITY, _keep(c + off, sr * 1.45), Vector3(sr, sr * 0.8, sr), 0.45, 200 + i * 7 + j, FAT_B, FAT_A)
    for j in range(2):
        var ang := K.h(i, j, 41) * TAU
        var side := Vector3(cos(ang), 0, sin(ang)) * r * 0.55
        var drop := drip * (0.6 + K.h(i, j, 42) * 0.8)
        var pts: Array = []
        for k in range(5):
            var tt := float(k) / 4.0
            pts.append(_keep(c + side * (1.0 + tt * 0.3) + Vector3(sin(tt * 3.0 + j) * 0.03, -r * 0.4 - drop * tt, cos(tt * 2.0 + i) * 0.03), 0.06))
        K.tube(st, Transform3D.IDENTITY, pts, [0.05, 0.035, 0.026, 0.02, 0.028], 5, [FAT_A, FAT_B])
        K.blob(st, Transform3D.IDENTITY, pts[4], Vector3(0.035, 0.05, 0.035), 0.2, 300 + i * 5 + j, FAT_B, FAT_A)

## Clamp a point so a part reaching `r` around it stays in the pocket + 0.28 m.
func _keep(p: Vector3, r: float) -> Vector3:
    var g := 0.28 - r
    return p.clamp(Vector3(-POCKET_HALF.x - g, -g, -POCKET_HALF.z - g), Vector3(POCKET_HALF.x + g, POCKET_HALF.y * 2.0 + g, POCKET_HALF.z + g))

## Flat convex polygon in a plate's local XY plane at depth z, facing +Z.
func _poly(st: SurfaceTool, t: Transform3D, pts: Array, z: float, col: Color) -> void:
    var a: Vector2 = pts[0]
    for i in range(1, pts.size() - 1):
        var b: Vector2 = pts[i]
        var c: Vector2 = pts[i + 1]
        K.tri(st, t, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(c.x, c.y, z), Vector3.BACK, col)

## Thick 2D stroke from a to b on a plate.
func _bar(st: SurfaceTool, t: Transform3D, a: Vector2, b: Vector2, w: float, z: float, col: Color) -> void:
    var d := (b - a).normalized()
    var n := Vector2(-d.y, d.x) * w * 0.5
    _poly(st, t, [a - n, b - n, b + n, a + n], z, col)

func set_light(on: bool) -> void:
    _bulb.visible = on
    _lamp.visible = on
