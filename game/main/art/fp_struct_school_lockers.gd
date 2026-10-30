extends Node3D

## Structure: a fragment of a 1960s school corridor swallowed by the gut
## folds of the mantle. Six tall steel pupils' lockers stood in a row along
## the corridor wall (alternating faded green / grey enamel, pressed vent
## slots, lift handles), a varnished wooden bench in front where children
## changed shoes, a strip of the corridor's linoleum. One locker door hangs
## open on a sprung hinge: empty inside, a shelf and a coat hook. The muscle
## of the fold wall has grown over the top of the row and pushes it forward,
## so the lockers lean into the corridor. A pictogram plate on one door
## warns about the biome: two walls squeeze a figure between them (the gut
## folds squeeze shut every few seconds). No light of its own.
## Origin = pocket floor centre; the row stands on the -Z wall, mouth at +Z.

const K := preload("res://main/art/fp_art_kit.gd")
const POCKET_HALF := Vector3(1.6, 1.1, 0.8)
const LW := 0.42        # locker width
const LD := 0.36        # locker depth
const LH := 1.8         # locker body height (above the kick plate)
const KICK := 0.08
const OPEN_IDX := 4

func pocket_half() -> Vector3:
    return POCKET_HALF

func set_light(_on: bool) -> void:
    pass

func _ready() -> void:
    var steel := K.mat("tex_door_paint_128.png", 0.25, true)
    var st := K.begin()
    var green := Color(0.4, 0.5, 0.4)
    var grey := Color(0.5, 0.52, 0.53)
    var rust := Color(0.4, 0.26, 0.16)
    for i in range(6):
        var xc := -1.05 + i * LW
        var lean := 4.0 + K.h(i, 7) * 5.0 + (2.0 if i == 2 or i == 3 else 0.0)
        var roll := (K.h(i, 8) - 0.5) * 3.0
        var t := Transform3D(Basis.from_euler(Vector3(deg_to_rad(lean), 0, deg_to_rad(roll))), Vector3(xc, 0, -0.8))
        var paint := green if i % 2 == 0 else grey
        paint = paint.lerp(Color(0.55, 0.5, 0.4), K.h(i, 9) * 0.3)
        if i == OPEN_IDX:
            _open_locker(st, t, paint, rust)
        else:
            _closed_locker(st, t, paint, rust, i)
        if i == 1:
            _squeeze_plate(st, t * K.T(Vector3(0, 1.32, LD + 0.016), Vector3.ZERO, Vector3.ONE * 1.35))
    # wooden bench in front of the row (slats + steel legs)
    var wood := Color(0.52, 0.36, 0.2)
    for k in range(2):
        K.rbox(st, K.T(Vector3(0.3, 0.44, -0.3 + k * 0.13)), Vector3(0.62, 0.016, 0.055), 0.008, wood.darkened(K.h(k, 3) * 0.15), wood.darkened(0.3))
    for sx: int in [-1, 1]:
        var lx := 0.3 + sx * 0.52
        K.rbox(st, K.T(Vector3(lx, 0.41, -0.235)), Vector3(0.02, 0.018, 0.14), 0.006, Color(0.28, 0.28, 0.3))
        for sz: int in [-1, 1]:
            K.tube(st, Transform3D.IDENTITY, [Vector3(lx, 0.4, -0.235 + sz * 0.11), Vector3(lx, 0.0, -0.235 + sz * 0.13)], [0.014], 5, [Color(0.3, 0.3, 0.32)])
        K.tube(st, Transform3D.IDENTITY, [Vector3(lx, 0.1, -0.36), Vector3(lx, 0.1, -0.11)], [0.01], 4, [Color(0.3, 0.3, 0.32)])
    # a dropped gym shoe under the bench
    K.rbox(st, K.T(Vector3(-0.05, 0.035, -0.12), Vector3(0, 35, 0)), Vector3(0.05, 0.035, 0.13), 0.02, Color(0.58, 0.55, 0.5), Color(0.3, 0.28, 0.26))
    K.add_mesh(self, "Lockers", K.finish(st, 3.0), steel)
    # linoleum floor strip (big worn checker, darker border by the lockers)
    st = K.begin()
    var lin_a := Color(0.6, 0.56, 0.46)
    var lin_b := Color(0.38, 0.42, 0.36)
    for ix in range(8):
        for iz in range(4):
            var x0 := -1.6 + ix * 0.4
            var z0 := -0.8 + iz * 0.4
            var c := lin_a if (ix + iz) % 2 == 0 else lin_b
            c = c.darkened(K.h(ix, iz, 5) * 0.2)
            if iz == 0:
                c = c.darkened(0.25)
            K.quad(st, Transform3D.IDENTITY, Vector3(x0, 0.004, z0), Vector3(x0 + 0.4, 0.004, z0), Vector3(x0 + 0.4, 0.004, z0 + 0.4), Vector3(x0, 0.004, z0 + 0.4), Vector3.UP, c)
    # skirting strip along the wall
    K.rbox(st, K.T(Vector3(0, 0.04, -0.79)), Vector3(1.6, 0.04, 0.012), 0.005, Color(0.22, 0.2, 0.18))
    K.add_mesh(self, "Linoleum", K.finish(st, 2.5), K.mat("tex_tile_floor_128.png", 0.35, true))
    _muscle()

## Closed locker in its leaning frame `t` (origin = back-bottom centre,
## front face at local z = LD).
func _closed_locker(st: SurfaceTool, t: Transform3D, paint: Color, rust: Color, i: int) -> void:
    K.rbox(st, t * K.T(Vector3(0, KICK * 0.5, LD * 0.5 - 0.02)), Vector3(LW * 0.5 - 0.005, KICK * 0.5, LD * 0.5 - 0.02), 0.006, Color(0.2, 0.2, 0.2))
    K.rbox(st, t * K.T(Vector3(0, KICK + LH * 0.5, LD * 0.5)), Vector3(LW * 0.5 - 0.004, LH * 0.5, LD * 0.5), 0.012, paint.darkened(0.12), rust)
    # proud door panel
    var door_col := paint.lerp(rust, K.h(i, 11) * 0.25)
    K.rbox(st, t * K.T(Vector3(0, KICK + LH * 0.5, LD + 0.006)), Vector3(LW * 0.5 - 0.03, LH * 0.5 - 0.035, 0.007), 0.004, door_col, door_col.darkened(0.2))
    _door_details(st, t * K.T(Vector3(0, 0, LD + 0.013)), i)

## Vent slots, handle and hinge pins on a door face (frame: x across door
## centre, y up from floor, +z out of the face).
func _door_details(st: SurfaceTool, t: Transform3D, i: int) -> void:
    var slot := Color(0.06, 0.06, 0.07)
    for k in range(4):
        _flat(st, t, Vector2(0, KICK + 1.55 + k * 0.045), Vector2(0.11, 0.009), 0.002, slot)
        _flat(st, t, Vector2(0, KICK + 0.12 + k * 0.045), Vector2(0.11, 0.009), 0.002, slot)
    # recessed lift handle + latch
    K.rbox(st, t * K.T(Vector3(0.13, KICK + 0.95, 0.004)), Vector3(0.022, 0.07, 0.006), 0.003, Color(0.15, 0.15, 0.16))
    K.rbox(st, t * K.T(Vector3(0.13, KICK + 0.95, 0.012), Vector3(0, 0, -8.0 + K.h(i, 12) * 16.0)), Vector3(0.012, 0.045, 0.008), 0.004, Color(0.68, 0.68, 0.66))
    # a dent on some doors (darker smear)
    if K.h(i, 13) > 0.5:
        K.rbox(st, t * K.T(Vector3(-0.05, KICK + 0.6 + K.h(i, 14) * 0.5, 0.002), Vector3(0, 0, 20)), Vector3(0.05, 0.03, 0.002), 0.002, Color(0.3, 0.28, 0.26))

## The open locker: hollow shell (empty), shelf, coat hook, door hanging
## open on its left hinge.
func _open_locker(st: SurfaceTool, t: Transform3D, paint: Color, rust: Color) -> void:
    var hw := LW * 0.5 - 0.004
    var inner := Color(0.3, 0.31, 0.3)
    var y0 := KICK
    K.rbox(st, t * K.T(Vector3(0, KICK * 0.5, LD * 0.5 - 0.02)), Vector3(hw, KICK * 0.5, LD * 0.5 - 0.02), 0.006, Color(0.2, 0.2, 0.2))
    K.rbox(st, t * K.T(Vector3(0, y0 + LH * 0.5, 0.008)), Vector3(hw, LH * 0.5, 0.008), 0.003, inner.darkened(0.3))
    for sx: int in [-1, 1]:
        K.rbox(st, t * K.T(Vector3(sx * (hw - 0.008), y0 + LH * 0.5, LD * 0.5)), Vector3(0.008, LH * 0.5, LD * 0.5), 0.003, paint.darkened(0.12), rust)
    K.rbox(st, t * K.T(Vector3(0, y0 + LH - 0.008, LD * 0.5)), Vector3(hw, 0.008, LD * 0.5), 0.003, paint.darkened(0.2))
    K.rbox(st, t * K.T(Vector3(0, y0 + 0.008, LD * 0.5)), Vector3(hw, 0.008, LD * 0.5), 0.003, inner.darkened(0.2))
    K.rbox(st, t * K.T(Vector3(0, y0 + 1.48, LD * 0.5)), Vector3(hw - 0.016, 0.008, LD * 0.5 - 0.01), 0.003, inner)
    # front frame lip
    K.rbox(st, t * K.T(Vector3(0, y0 + LH - 0.02, LD)), Vector3(hw, 0.02, 0.006), 0.003, paint.darkened(0.15))
    # coat hook under the shelf
    var hook := Color(0.62, 0.6, 0.55)
    K.tube(st, t, [Vector3(0, y0 + 1.4, 0.02), Vector3(0, y0 + 1.38, 0.08), Vector3(0, y0 + 1.41, 0.11), Vector3(0, y0 + 1.45, 0.11)], [0.008], 4, [hook])
    K.rbox(st, t * K.T(Vector3(0, y0 + 1.4, 0.018)), Vector3(0.018, 0.025, 0.004), 0.002, hook.darkened(0.3))
    # rust streak inside on the floor plate
    K.rbox(st, t * K.T(Vector3(0.04, y0 + 0.018, 0.12)), Vector3(0.07, 0.002, 0.05), 0.001, rust.darkened(0.2))
    # the door: hinge on the -x edge, swung ~105 deg out, sagging on a
    # broken lower hinge
    var hinge := t * Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(-105.0), deg_to_rad(2.5))), Vector3(-hw, 0, LD + 0.008))
    var dc := paint.lerp(rust, 0.15)
    K.rbox(st, hinge * K.T(Vector3(hw, KICK + LH * 0.5, 0)), Vector3(hw - 0.01, LH * 0.5 - 0.035, 0.008), 0.004, dc, dc.darkened(0.25))
    # inner face of the door is plain grey
    K.rbox(st, hinge * K.T(Vector3(hw, KICK + LH * 0.5, -0.009)), Vector3(hw - 0.04, LH * 0.5 - 0.08, 0.002), 0.001, inner.lightened(0.1))
    _door_details(st, hinge * K.T(Vector3(hw, 0, 0.009)), OPEN_IDX)
    for k in range(3):
        K.tube(st, t, [Vector3(-hw - 0.006, KICK + 0.2 + k * 0.7, LD + 0.004), Vector3(-hw - 0.006, KICK + 0.3 + k * 0.7, LD + 0.004)], [0.007], 4, [Color(0.35, 0.35, 0.35)])

## Pictogram plate (frame: centre of the plate, +z out of the face): two
## walls with inward arrows squeezing a stick figure.
func _squeeze_plate(st: SurfaceTool, t: Transform3D) -> void:
    K.rbox(st, t, Vector3(0.13, 0.1, 0.004), 0.003, Color(0.85, 0.82, 0.68), Color(0.35, 0.32, 0.25))
    var z := 0.009
    var ink := Color(0.08, 0.07, 0.07)
    var red := Color(0.72, 0.1, 0.08)
    # the two walls (wavy fold edge drawn as stacked bars)
    for sx: int in [-1, 1]:
        for k in range(5):
            var wob := 0.006 * (1.0 if k % 2 == 0 else -1.0)
            _flat(st, t, Vector2(sx * (0.105 + wob), -0.07 + k * 0.035), Vector2(0.014, 0.018), z, ink)
        # arrow pointing inward
        _flat(st, t, Vector2(sx * 0.07, 0.0), Vector2(0.022, 0.007), z, red)
        K.tri(st, t, Vector3(sx * 0.048, 0.022, z), Vector3(sx * 0.048, -0.022, z), Vector3(sx * 0.025, 0.0, z), Vector3(0, 0, 1), red)
    # stick figure between
    _flat(st, t, Vector2(0, 0.05), Vector2(0.011, 0.011), z, ink)
    _flat(st, t, Vector2(0, 0.012), Vector2(0.005, 0.03), z, ink)
    _flat(st, t, Vector2(0, 0.02), Vector2(0.018, 0.004), z, ink)
    for sx: int in [-1, 1]:
        K.quad(st, t, Vector3(sx * 0.002, -0.018, z), Vector3(sx * 0.009, -0.018, z), Vector3(sx * 0.016, -0.075, z), Vector3(sx * 0.009, -0.075, z), Vector3(0, 0, 1), ink)

## Flat rectangle on the z plane of `t` (centre, half size).
func _flat(st: SurfaceTool, t: Transform3D, c: Vector2, hs: Vector2, z: float, col: Color) -> void:
    K.quad(st, t, Vector3(c.x - hs.x, c.y - hs.y, z), Vector3(c.x + hs.x, c.y - hs.y, z), Vector3(c.x + hs.x, c.y + hs.y, z), Vector3(c.x - hs.x, c.y + hs.y, z), Vector3(0, 0, 1), col)

## Shrinks a blob's radius so its lumpy hull stays inside the pocket box
## grown by 0.28 m (parts may sink up to 0.3 m into the flesh).
func _fit(c: Vector3, r: Vector3, lumps: float) -> Vector3:
    var lim := POCKET_HALF + Vector3(0.28, 0.0, 0.28)
    var k := 1.0 + lumps
    var out := r
    out.x = minf(out.x, (lim.x - absf(c.x)) / k)
    out.z = minf(out.z, (lim.z - absf(c.z)) / k)
    out.y = minf(out.y, minf((POCKET_HALF.y * 2.0 + 0.28 - c.y) / k, (c.y + 0.28) / k))
    return out.max(Vector3(0.03, 0.03, 0.03))

## Muscle of the gut fold: fibrous masses pressing the top of the row,
## layered folds along the ceiling and down the side walls, fibres creeping
## between the lockers.
func _muscle() -> void:
    var st := K.begin()
    var fa := Color(0.5, 0.08, 0.1)
    var fb := Color(0.66, 0.2, 0.2)
    var masses := [Vector3(-1.3, 2.0, -0.62), Vector3(-0.55, 2.08, -0.6), Vector3(0.2, 2.05, -0.58), Vector3(0.9, 2.1, -0.62), Vector3(1.4, 1.95, -0.55), Vector3(1.48, 0.5, -0.5), Vector3(-1.5, 1.1, -0.45)]
    for i in range(masses.size()):
        var c: Vector3 = masses[i]
        var r := 0.32 + K.h(i, 51) * 0.18
        var rr := _fit(c, Vector3(r, r * 0.6, r * 0.8), 0.35)
        K.blob(st, Transform3D.IDENTITY, c, rr, 0.35, 300 + i, fa, fb)
        for j in range(3):
            var off := Vector3(K.h(i, j, 52) - 0.5, (K.h(i, j, 53) - 0.5) * 0.5, K.h(i, j, 54) - 0.5).normalized() * rr * 0.7
            var sr := rr.x * (0.35 + K.h(i, j, 55) * 0.25)
            K.blob(st, Transform3D.IDENTITY, c + off, _fit(c + off, Vector3(sr, sr * 0.8, sr), 0.4), 0.4, 400 + i * 5 + j, fb, fa)
        # fibre tendrils running down over the locker fronts
        for j in range(2):
            var x0 := c.x + (K.h(i, j, 56) - 0.5) * rr.x * 1.4
            if absf(x0 + 0.63) < 0.2:
                x0 = -0.84 if x0 < -0.63 else -0.42
            var drop := 0.4 + K.h(i, j, 57) * 0.7
            var pts: Array = []
            for k in range(5):
                var tt := float(k) / 4.0
                pts.append(Vector3(x0 + sin(tt * 3.0 + j) * 0.03, maxf(0.03, c.y - rr.y * 0.4 - drop * tt), c.z + rr.z * 0.8 + tt * 0.06))
            K.tube(st, Transform3D.IDENTITY, pts, [0.03, 0.024, 0.018, 0.011, 0.005], 5, [fa, fb.darkened(0.15)])
    # layered folds: thick ridges along x hugging the ceiling, each with
    # pale fibre striations running along it
    var folds := [[2.12, -0.25, 0.13], [2.14, 0.15, 0.1], [2.1, 0.55, 0.12]]
    for f in range(folds.size()):
        var fy: float = folds[f][0]
        var fz: float = folds[f][1]
        var fr: float = folds[f][2]
        var pts: Array = []
        var radii: Array = []
        for k in range(9):
            var x := -1.75 + k * (3.5 / 8.0)
            pts.append(Vector3(x, fy + sin(k * 1.3 + f) * 0.03, fz + sin(k * 0.9 + f * 2.0) * 0.05))
            radii.append(fr * (0.8 + K.h(k, f, 58) * 0.4))
        K.tube(st, Transform3D.IDENTITY, pts, radii, 7, [fa, fb, fa], true, 1.4)
        for s in range(2):
            var spts: Array = []
            for k in range(9):
                var p: Vector3 = pts[k]
                spts.append(p + Vector3(0, -radii[k] * 0.92, (s - 1) * radii[k] * 0.7))
            K.tube(st, Transform3D.IDENTITY, spts, [0.012], 3, [fb.lightened(0.1)], false)
    # vertical folds on both side walls
    for sx: int in [-1, 1]:
        for f in range(3):
            var pts: Array = []
            var radii: Array = []
            var z := -0.55 + f * 0.5
            for k in range(6):
                var y := 0.15 + k * 0.42
                pts.append(Vector3(sx * (1.66 + sin(k + f) * 0.03), y, z + sin(k * 1.1 + f) * 0.06))
                radii.append(0.12 + K.h(k, f, 59 + sx) * 0.06)
            K.tube(st, Transform3D.IDENTITY, pts, radii, 6, [fb, fa], true, 0.8)
    # fibres creeping down the gaps between lockers
    for i in range(5):
        var x := -0.84 + i * LW
        var pts: Array = []
        for k in range(5):
            var tt := float(k) / 4.0
            var y := 2.0 - tt * (0.9 + K.h(i, 60) * 0.6)
            pts.append(Vector3(x + sin(tt * 5.0 + i) * 0.015, y, -0.4 + y * 0.13))
        K.tube(st, Transform3D.IDENTITY, pts, [0.035, 0.028, 0.02, 0.012, 0.005], 5, [fa, fb])
    K.add_mesh(self, "Overgrowth", K.finish(st, 3.0), K.mat("tex_flesh_128.png", 0.7, true))
