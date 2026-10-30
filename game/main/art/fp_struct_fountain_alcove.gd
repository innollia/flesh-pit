extends Node3D

## Structure: a 1950s public drinking-fountain alcove (a station or park
## underpass), swallowed by the gut folds of the mantle. A shallow recess
## tiled in pale blue and white, a vitreous-china wall fountain with a
## chrome bubbler and push button, a stained drain, its supply pipe going
## down into the floor, a small enamel wall lamp that still glows a sickly
## green-white. The muscle of the fold wall bulges through the tiles and
## hangs from the soffit. A pictogram plate warns about the biome's rhythm:
## a clock ring whose beat mark is a squeeze (the folds squeeze shut on a
## beat). Origin = pocket floor centre; the fountain is on the -Z wall,
## mouth at +Z. Public: set_light(on).

const K := preload("res://main/art/fp_art_kit.gd")
const POCKET_HALF := Vector3(0.9, 1.1, 0.8)
const BACK := -0.78      # tiled back wall plane
const SIDE := 0.86       # tiled side wall planes (+-x)
const FRONT := 0.25      # front edge of the recess
const TOP := 1.92        # soffit height
const TILE := 0.15
var _lamp: OmniLight3D
var _globe: MeshInstance3D

func pocket_half() -> Vector3:
    return POCKET_HALF

func _ready() -> void:
    # tiled recess
    var st := K.begin()
    var white := Color(0.82, 0.85, 0.84)
    var blue := Color(0.52, 0.68, 0.76)
    var grout := Color(0.32, 0.33, 0.3)
    # back wall
    _tiles(st, Vector3(-SIDE, 0, BACK), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), int(round(SIDE * 2.0 / TILE)), int(round(TOP / TILE)), white, blue, grout, 1)
    # side walls (run from the back wall forward to the recess front)
    var nz := int(round((FRONT - BACK) / TILE))
    _tiles(st, Vector3(-SIDE, 0, BACK), Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0), nz, int(round(TOP / TILE)), white, blue, grout, 2)
    _tiles(st, Vector3(SIDE, 0, FRONT), Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(-1, 0, 0), nz, int(round(TOP / TILE)), white, blue, grout, 3)
    # soffit
    _tiles(st, Vector3(-SIDE, TOP, BACK), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0), int(round(SIDE * 2.0 / TILE)), nz, white, white, grout, 4)
    K.add_mesh(self, "Tiles", K.finish(st, 1.0 / TILE), K.mat("tex_tile_wall_128.png", 0.35, true))
    # floor: small grey mosaic with a dark wet patch under the fountain
    st = K.begin()
    for ix in range(9):
        for iz in range(8):
            var x0 := -0.9 + ix * 0.2
            var z0 := -0.8 + iz * 0.2
            var c := Color(0.56, 0.56, 0.52).darkened(K.h(ix, iz, 21) * 0.18)
            var wet := clampf(1.0 - Vector2(x0 + 0.1, z0 + 0.1 + 0.55).length() * 2.2, 0.0, 1.0)
            c = c.lerp(Color(0.2, 0.17, 0.12), wet * 0.7)
            K.quad(st, Transform3D.IDENTITY, Vector3(x0, 0.004, z0), Vector3(x0 + 0.2, 0.004, z0), Vector3(x0 + 0.2, 0.004, z0 + 0.2), Vector3(x0, 0.004, z0 + 0.2), Vector3.UP, c)
    K.add_mesh(self, "Floor", K.finish(st, 2.5), K.mat("tex_tile_floor_128.png", 0.5, true))
    # porcelain fountain
    st = K.begin()
    var china := Color(0.86, 0.85, 0.8)
    var stain := Color(0.5, 0.4, 0.25)
    K.rbox(st, K.T(Vector3(0, 0.93, BACK + 0.02)), Vector3(0.24, 0.3, 0.02), 0.012, china, china.darkened(0.15))
    var bowl_c := Vector3(0, 0.82, -0.6)
    K.lathe(st, K.T(bowl_c), [
        Vector2(0.0, -0.26), Vector2(0.055, -0.26), Vector2(0.06, -0.13), Vector2(0.15, -0.05),
        Vector2(0.2, 0.04), Vector2(0.205, 0.09), Vector2(0.17, 0.095), Vector2(0.14, 0.03),
        Vector2(0.05, -0.02), Vector2(0.0, -0.02)], 12,
        [china, china, china, china, china.darkened(0.08), china.darkened(0.1), china.lerp(stain, 0.2), china.lerp(stain, 0.45), china.lerp(stain, 0.6)])
    # stained drain + rust run from the bubbler
    K.lathe(st, K.T(bowl_c + Vector3(0, -0.017, 0)), [Vector2(0.075, 0.0), Vector2(0.035, 0.002), Vector2(0.0, 0.002)], 10, [Color(0.36, 0.25, 0.14), Color(0.08, 0.07, 0.06)])
    for k in range(4):
        K.lathe(st, K.T(bowl_c + Vector3(-0.015 + k * 0.01, -0.012, -0.03 - k * 0.04)), [Vector2(0.018, 0.0), Vector2(0.0, 0.003)], 6, [Color(0.4, 0.27, 0.12)])
    K.add_mesh(self, "Fountain", K.finish(st, 4.0), K.mat("tex_ceramic_128.png", 0.6, true))
    # chrome: bubbler, push button, supply pipe, lamp base
    st = K.begin()
    var chrome := Color(0.72, 0.73, 0.74)
    K.lathe(st, K.T(bowl_c + Vector3(0, -0.02, -0.1)), [Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.026, 0.05), Vector2(0.018, 0.075), Vector2(0.008, 0.085), Vector2(0.0, 0.088)], 8, [chrome])
    K.tube(st, Transform3D.IDENTITY, [bowl_c + Vector3(0.03, 0.0, -0.1), bowl_c + Vector3(0.03, 0.1, -0.08), bowl_c + Vector3(0.0, 0.12, -0.06), bowl_c + Vector3(-0.03, 0.1, -0.08), bowl_c + Vector3(-0.03, 0.0, -0.1)], [0.006], 4, [chrome.darkened(0.1)])
    # push-button housing on the front lip, button facing the user
    K.rbox(st, K.T(bowl_c + Vector3(0, 0.06, 0.205)), Vector3(0.045, 0.03, 0.018), 0.008, chrome)
    K.lathe(st, K.T(bowl_c + Vector3(0, 0.06, 0.22), Vector3(90, 0, 0)), [Vector2(0.0, 0.0), Vector2(0.018, 0.0), Vector2(0.018, 0.012), Vector2(0.012, 0.018), Vector2(0.0, 0.018)], 8, [chrome.lightened(0.1)])
    # supply pipe from under the bowl down into the floor (slip nut + flange)
    var pipe := Color(0.55, 0.56, 0.55)
    K.tube(st, Transform3D.IDENTITY, [bowl_c + Vector3(0, -0.26, 0), Vector3(0, 0.42, -0.6), Vector3(0, 0.3, -0.63), Vector3(0, 0.12, -0.68), Vector3(0, -0.22, -0.68)], [0.022], 6, [pipe, pipe, pipe.lerp(stain, 0.4), pipe.lerp(stain, 0.6)])
    K.lathe(st, K.T(Vector3(0, 0.36, -0.61)), [Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.03, 0.04), Vector2(0.0, 0.04)], 6, [chrome.darkened(0.2)])
    K.lathe(st, K.T(Vector3(0, 0.0, -0.68)), [Vector2(0.07, 0.0), Vector2(0.06, 0.012), Vector2(0.0, 0.014)], 8, [pipe.lerp(stain, 0.5)])
    # wall lamp: chrome back plate + arm above the fountain
    var lamp_p := Vector3(0, 1.6, BACK)
    K.rbox(st, K.T(lamp_p + Vector3(0, 0, 0.012)), Vector3(0.06, 0.08, 0.012), 0.006, chrome.darkened(0.15))
    K.tube(st, Transform3D.IDENTITY, [lamp_p + Vector3(0, 0, 0.02), lamp_p + Vector3(0, 0.0, 0.09)], [0.012], 5, [chrome.darkened(0.15)])
    K.lathe(st, K.T(lamp_p + Vector3(0, 0.02, 0.1)), [Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.045, 0.035), Vector2(0.0, 0.04)], 8, [Color(0.25, 0.32, 0.28)])
    # pictogram plate (enamel) left of the fountain: a beat ring
    _rhythm_plate(st, K.T(Vector3(-0.48, 1.32, BACK + 0.022), Vector3.ZERO, Vector3.ONE * 1.4))
    # recess frame: pilasters + lintel (painted plaster/stone)
    var frame := Color(0.62, 0.6, 0.55)
    for sx: int in [-1, 1]:
        K.rbox(st, K.T(Vector3(sx * (SIDE - 0.02), TOP * 0.5, FRONT + 0.05)), Vector3(0.07, TOP * 0.5, 0.06), 0.015, frame, frame.darkened(0.25))
    K.rbox(st, K.T(Vector3(0, TOP + 0.06, FRONT + 0.05)), Vector3(SIDE + 0.05, 0.07, 0.07), 0.015, frame, frame.darkened(0.25))
    K.add_mesh(self, "Chrome", K.finish(st, 4.0), K.mat("tex_chrome_128.png", 0.3, true))
    # glowing globe + light
    st = K.begin()
    K.lathe(st, K.T(lamp_p + Vector3(0, -0.07, 0.1)), [Vector2(0.0, 0.0), Vector2(0.04, 0.02), Vector2(0.052, 0.055), Vector2(0.045, 0.085), Vector2(0.0, 0.09)], 8, [Color(0.8, 1.0, 0.75)])
    _globe = K.add_mesh(self, "Globe", K.finish(st), K.glow(Color(0.85, 1.0, 0.8)))
    _lamp = OmniLight3D.new()
    _lamp.position = lamp_p + Vector3(0, -0.05, 0.3)
    _lamp.omni_range = 2.2
    _lamp.light_color = Color(0.8, 1.0, 0.75)
    _lamp.light_energy = 0.5
    _lamp.light_cull_mask = 0xFFFFF & ~FPRestroom.ROOM_VISUAL_LAYER & ~FPMirrorReflection.HANDS_ROOM_LAYER & ~FPMirrorReflection.MIRROR_BODY_LAYER & ~FPMirror.HOLO_LAYER
    add_child(_lamp)
    _muscle()

func set_light(on: bool) -> void:
    _globe.visible = on
    _lamp.visible = on

## Tile grid: starts at `o`, `nu` tiles along `u`, `nv` along `v`, facing
## `n`. A grout backing quad, then each tile slightly proud and inset.
## A blue band at dado height, grime towards the floor, some tiles missing
## or cracked (deterministic).
func _tiles(st: SurfaceTool, o: Vector3, u: Vector3, v: Vector3, n: Vector3, nu: int, nv: int, white: Color, blue: Color, grout: Color, seed: int) -> void:
    var wu := u * (nu * TILE)
    var wv := v * (nv * TILE)
    K.quad(st, Transform3D.IDENTITY, o, o + wu, o + wu + wv, o + wv, n, grout)
    var g := 0.008
    for i in range(nu):
        for j in range(nv):
            var hh := K.h(i, j, 70 + seed)
            # holes where the muscle has pushed tiles off
            if hh > 0.95:
                continue
            var c := white
            if j == 6 or j == 7 or (seed == 4 and (i + j) % 3 == 0):
                c = blue
            elif (i + j) % 7 == 0:
                c = white.lerp(blue, 0.5)
            c = c.darkened(maxf(0.0, 0.3 - j * 0.06) + K.h(i, j, 80 + seed) * 0.08)
            if hh > 0.88:
                c = c.lerp(Color(0.6, 0.5, 0.3), 0.4)
            var p := o + u * (i * TILE + g) + v * (j * TILE + g) + n * 0.012
            var a := u * (TILE - 2.0 * g)
            var b := v * (TILE - 2.0 * g)
            K.quad(st, Transform3D.IDENTITY, p, p + a, p + a + b, p + b, n, c)

## Enamel plate (frame: centre, +z out of the face): a clock ring with four
## beat ticks; the top beat is a red squeeze (two bars, inward arrows), the
## hand points at it.
func _rhythm_plate(st: SurfaceTool, t: Transform3D) -> void:
    K.rbox(st, t, Vector3(0.12, 0.12, 0.005), 0.004, Color(0.88, 0.86, 0.74), Color(0.3, 0.32, 0.4))
    var ink := Color(0.1, 0.1, 0.14)
    var red := Color(0.75, 0.1, 0.08)
    var z := 0.012
    var ring: Array = []
    for k in range(17):
        var a := TAU * float(k) / 16.0
        ring.append(Vector3(cos(a) * 0.07, sin(a) * 0.07 - 0.01, z))
    K.tube(st, t, ring, [0.006], 4, [ink], false)
    for k in range(1, 4):
        var a := PI * 0.5 + TAU * float(k) / 4.0
        var d := Vector3(cos(a), sin(a), 0)
        var ctr := Vector3(0, -0.01, z)
        K.tube(st, t, [ctr + d * 0.056, ctr + d * 0.084], [0.008], 4, [ink])
    # hand pointing at the top beat
    K.tube(st, t, [Vector3(0, -0.01, z), Vector3(0, 0.045, z)], [0.006], 4, [ink])
    # the squeeze at the top beat: two bars pressing together
    for sx: int in [-1, 1]:
        K.quad(st, t, Vector3(sx * 0.03, 0.065, z), Vector3(sx * 0.018, 0.065, z), Vector3(sx * 0.018, 0.115, z), Vector3(sx * 0.03, 0.115, z), Vector3(0, 0, 1), red)
        K.tri(st, t, Vector3(sx * 0.05, 0.1, z), Vector3(sx * 0.05, 0.08, z), Vector3(sx * 0.034, 0.09, z), Vector3(0, 0, 1), red)
        K.quad(st, t, Vector3(sx * 0.07, 0.087, z), Vector3(sx * 0.05, 0.087, z), Vector3(sx * 0.05, 0.093, z), Vector3(sx * 0.07, 0.093, z), Vector3(0, 0, 1), red)

func _fit(c: Vector3, r: Vector3, lumps: float) -> Vector3:
    var lim := POCKET_HALF + Vector3(0.28, 0.0, 0.28)
    var k := 1.0 + lumps
    var out := r
    out.x = minf(out.x, (lim.x - absf(c.x)) / k)
    out.z = minf(out.z, (lim.z - absf(c.z)) / k)
    out.y = minf(out.y, minf((POCKET_HALF.y * 2.0 + 0.28 - c.y) / k, (c.y + 0.28) / k))
    return out.max(Vector3(0.03, 0.03, 0.03))

## Gut-fold muscle: masses over the lintel and corners, a mass bursting
## through the tiles low on the right, folds hanging from above the
## soffit, fibres running down the tiles.
func _muscle() -> void:
    var st := K.begin()
    var fa := Color(0.5, 0.08, 0.1)
    var fb := Color(0.66, 0.2, 0.2)
    var masses := [Vector3(-0.75, 2.05, 0.35), Vector3(0.7, 2.1, 0.4), Vector3(0.0, 2.12, 0.55), Vector3(0.82, 0.35, -0.55), Vector3(-0.85, 1.6, -0.72), Vector3(0.6, 2.1, -0.5)]
    for i in range(masses.size()):
        var c: Vector3 = masses[i]
        var r := 0.26 + K.h(i, 61) * 0.14
        var rr := _fit(c, Vector3(r, r * 0.7, r * 0.8), 0.35)
        K.blob(st, Transform3D.IDENTITY, c, rr, 0.35, 500 + i, fa, fb)
        for j in range(3):
            var off := Vector3(K.h(i, j, 62) - 0.5, (K.h(i, j, 63) - 0.5) * 0.6, K.h(i, j, 64) - 0.5).normalized() * rr * 0.7
            var sr := rr.x * (0.35 + K.h(i, j, 65) * 0.25)
            K.blob(st, Transform3D.IDENTITY, c + off, _fit(c + off, Vector3(sr, sr * 0.8, sr), 0.4), 0.4, 600 + i * 5 + j, fb, fa)
    # folds along x in front of the lintel and above the soffit edge
    for f in range(2):
        var pts: Array = []
        var radii: Array = []
        for k in range(7):
            var x := -1.05 + k * 0.35
            pts.append(Vector3(x, 2.12 - f * 0.05 + sin(k * 1.4 + f) * 0.03, 0.42 + f * 0.25 + sin(k + f) * 0.04))
            radii.append(0.1 + K.h(k, f, 66) * 0.05)
        K.tube(st, Transform3D.IDENTITY, pts, radii, 7, [fa, fb, fa], true, 1.3)
        for s in range(3):
            var spts: Array = []
            for k in range(7):
                spts.append((pts[k] as Vector3) + Vector3(0, -(radii[k] as float) * 0.92, (s - 1) * (radii[k] as float) * 0.6))
            K.tube(st, Transform3D.IDENTITY, spts, [0.01], 3, [fb.lightened(0.1)], false)
    # fibres creeping down the tiles from the corners and the soffit
    var starts := [Vector3(-0.83, 1.9, -0.7), Vector3(-0.83, 1.9, -0.2), Vector3(0.83, 1.9, -0.6), Vector3(0.83, 1.9, 0.1), Vector3(-0.4, 1.9, -0.76), Vector3(0.45, 1.9, -0.76)]
    for i in range(starts.size()):
        var s0: Vector3 = starts[i]
        var drop := 0.5 + K.h(i, 67) * 0.8
        var pts: Array = []
        for k in range(6):
            var tt := float(k) / 5.0
            var wob := sin(tt * 6.0 + i) * 0.04
            var p := s0 + Vector3(0, -drop * tt, 0)
            if absf(s0.x) > 0.8:
                p.z += wob
            else:
                p.x += wob
            pts.append(p)
        K.tube(st, Transform3D.IDENTITY, pts, [0.04, 0.032, 0.025, 0.018, 0.01, 0.004], 5, [fa, fb.darkened(0.1)])
    K.add_mesh(self, "Overgrowth", K.finish(st, 3.0), K.mat("tex_flesh_128.png", 0.7, true))
