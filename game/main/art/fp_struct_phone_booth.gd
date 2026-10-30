extends Node3D

## Structure: a 1960s public telephone booth swallowed by the fat caves of the
## core. Painted steel frame, kick panels and dark bluish glass (some panes
## cracked, some gone), a folding door on the +Z side left ajar, a coin wall
## phone with a rotary dial (finger holes only) and its handset hanging on the
## coiled cord, a little shelf with a chained directory, a fluorescent tube in
## the roof. It stood on a pavement so people could ring from the street;
## now soft yellow fat has grown over its roof and down one corner. The sticker
## on the front pane warns what this biome does: a handset with an arrow
## sinking into wavy flesh (things you drop here sink). Origin = pocket floor
## centre, mouth +Z. Public: pocket_half(), set_light(on).

const K := preload("res://main/art/fp_art_kit.gd")
const POCKET_HALF := Vector3(0.9, 1.2, 0.9)
const B := 0.72
const H := 2.2
const FAT_A := Color(0.86, 0.74, 0.38)
const FAT_B := Color(0.95, 0.86, 0.55)
const FRAME := Color(0.33, 0.44, 0.41)
const FRAME_EDGE := Color(0.25, 0.3, 0.28)
const GLASS := Color(0.17, 0.25, 0.33)
const CRACK := Color(0.55, 0.66, 0.72)
var _tube: MeshInstance3D
var _lamp: OmniLight3D

func pocket_half() -> Vector3:
    return POCKET_HALF

func _ready() -> void:
    var st := K.begin()
    # --- floor plate, corner posts, roof
    K.rbox(st, K.T(Vector3(0, 0.03, 0)), Vector3(B + 0.02, 0.03, B + 0.02), 0.01, Color(0.3, 0.3, 0.3), Color(0.22, 0.22, 0.22))
    for sx in [-1, 1]:
        for sz in [-1, 1]:
            K.rbox(st, K.T(Vector3(sx * B, H * 0.5, sz * B)), Vector3(0.035, H * 0.5, 0.035), 0.01, FRAME, FRAME_EDGE)
    K.rbox(st, K.T(Vector3(0, H + 0.09, 0)), Vector3(B + 0.06, 0.09, B + 0.06), 0.02, FRAME, FRAME_EDGE)
    K.quad(st, Transform3D.IDENTITY, Vector3(-B, H - 0.001, -B), Vector3(B, H - 0.001, -B), Vector3(B, H - 0.001, B), Vector3(-B, H - 0.001, B), Vector3.DOWN, Color(0.75, 0.75, 0.7))
    # pale header band on the front fascia (where the lit sign was; no text)
    K.rbox(st, K.T(Vector3(0, H + 0.09, B + 0.065)), Vector3(0.5, 0.05, 0.008), 0.004, Color(0.86, 0.84, 0.7))
    # --- three glazed walls (-Z, +X, -X) and the fixed front pane (+Z, right)
    var walls := [
        [K.T(Vector3(0, 0, -B), Vector3(0, 180, 0)), -B, B, [0, 1, 0, 2]],
        [K.T(Vector3(B, 0, 0), Vector3(0, 90, 0)), -B, B, [1, 0, 0, 0]],
        [K.T(Vector3(-B, 0, 0), Vector3(0, -90, 0)), -B, B, [0, 2, 0, 1]],
        [K.T(Vector3(0, 0, B)), 0.2, B, [0, 1]],
    ]
    for wi in range(walls.size()):
        var w: Array = walls[wi]
        _wall(st, w[0], w[1], w[2], w[3], wi)
    # door jamb and header over the door opening
    K.rbox(st, K.T(Vector3(0.2, H * 0.5, B)), Vector3(0.03, H * 0.5, 0.03), 0.01, FRAME, FRAME_EDGE)
    K.rbox(st, K.T(Vector3(-0.26, H - 0.04, B)), Vector3(0.46, 0.04, 0.025), 0.008, FRAME, FRAME_EDGE)
    # --- back wall: phone on a backing board
    K.rbox(st, K.T(Vector3(0, 1.3, -B + 0.035)), Vector3(0.24, 0.42, 0.015), 0.006, Color(0.24, 0.24, 0.25))
    var black := Color(0.11, 0.11, 0.12)
    var chrome := Color(0.62, 0.63, 0.64)
    K.rbox(st, K.T(Vector3(0, 1.46, -B + 0.11)), Vector3(0.12, 0.17, 0.06), 0.02, black, chrome.darkened(0.3))
    K.quad(st, Transform3D.IDENTITY, Vector3(0.03, 1.631, -B + 0.1), Vector3(0.08, 1.631, -B + 0.1), Vector3(0.08, 1.631, -B + 0.115), Vector3(0.03, 1.631, -B + 0.115), Vector3.UP, Color(0.02, 0.02, 0.02))
    # rotary dial: chrome ring, cream plate, finger holes (no digits)
    var dial_c := Vector3(0.0, 1.48, -B + 0.17)
    K.lathe(st, K.T(dial_c - Vector3(0, 0, 0.0), Vector3(90, 0, 0)), [Vector2(0.0, 0.0), Vector2(0.07, 0.0), Vector2(0.07, 0.012), Vector2(0.0, 0.012)], 12, [chrome, chrome, Color(0.82, 0.8, 0.72)])
    var dial := K.T(dial_c + Vector3(0, 0, 0.012))
    for hi in range(10):
        var a := deg_to_rad(60.0 + hi * 27.0)
        var hc := Vector2(cos(a), sin(a)) * 0.048
        var pts: Array = []
        for k in range(6):
            var ak := TAU * float(k) / 6.0
            pts.append(hc + Vector2(cos(ak), sin(ak)) * 0.011)
        _poly(st, dial, pts, 0.002, Color(0.08, 0.08, 0.08))
    _bar(st, dial, Vector2(0.05, -0.05), Vector2(0.065, -0.03), 0.006, 0.003, chrome)
    # coin box with a return cup
    K.rbox(st, K.T(Vector3(0, 1.13, -B + 0.1)), Vector3(0.1, 0.12, 0.05), 0.015, chrome.darkened(0.15), chrome.darkened(0.4))
    K.rbox(st, K.T(Vector3(0, 1.06, -B + 0.155)), Vector3(0.04, 0.025, 0.012), 0.008, Color(0.1, 0.1, 0.1), chrome)
    # hook (empty) on the left side of the phone
    K.rbox(st, K.T(Vector3(-0.15, 1.52, -B + 0.12)), Vector3(0.03, 0.06, 0.03), 0.01, chrome)
    # handset hanging on its coiled cord
    var hs := K.T(Vector3(-0.17, 0.74, -B + 0.2), Vector3(0, 0, 8))
    K.tube(st, hs, [Vector3(0, 0.12, 0), Vector3(0, -0.12, 0)], [0.022], 6, [black])
    K.rbox(st, hs * K.T(Vector3(0, 0.14, 0.02)), Vector3(0.042, 0.035, 0.035), 0.015, black)
    K.rbox(st, hs * K.T(Vector3(0, -0.14, 0.02)), Vector3(0.04, 0.033, 0.035), 0.015, black)
    var ca := Vector3(-0.1, 1.31, -B + 0.12)
    var cb: Vector3 = hs * Vector3(0, -0.18, 0)
    var cord: Array = []
    var n := 44
    for k in range(n + 1):
        var tt := float(k) / float(n)
        var base := ca.lerp(cb, tt) + Vector3(-0.06, -0.12, 0.05) * sin(tt * PI)
        var ang := tt * TAU * 9.0
        cord.append(base + Vector3(cos(ang) * 0.013, 0.0, sin(ang) * 0.013))
    K.tube(st, Transform3D.IDENTITY, cord, [0.005], 3, [Color(0.08, 0.08, 0.08)], false)
    # shelf with a chained directory on the -X wall
    K.rbox(st, K.T(Vector3(-B + 0.13, 1.0, -0.3)), Vector3(0.12, 0.015, 0.24), 0.006, FRAME.darkened(0.2))
    K.rbox(st, K.T(Vector3(-B + 0.04, 0.92, -0.3)), Vector3(0.02, 0.08, 0.02), 0.005, FRAME_EDGE)
    K.rbox(st, K.T(Vector3(-B + 0.13, 1.04, -0.32), Vector3(0, 12, 0)), Vector3(0.08, 0.025, 0.11), 0.01, Color(0.72, 0.62, 0.3), Color(0.85, 0.82, 0.72))
    K.tube(st, Transform3D.IDENTITY, [Vector3(-B + 0.05, 1.0, -0.14), Vector3(-B + 0.1, 0.93, -0.15), Vector3(-B + 0.18, 1.02, -0.23)], [0.004], 3, [chrome])
    # --- folding door on +Z, hinged at the left post, ajar
    var hinge := Vector3(-0.68, 0.0, B)
    var leaf := 0.43
    var al := deg_to_rad(35.0)
    var e1 := hinge + Vector3(cos(al), 0, sin(al)) * leaf
    var e2 := e1 + Vector3(cos(al), 0, -sin(al)) * leaf
    _leaf(st, (hinge + e1) * 0.5, -35.0, leaf * 0.5, false)
    _leaf(st, (e1 + e2) * 0.5, 35.0, leaf * 0.5, true)
    K.tube(st, Transform3D.IDENTITY, [e2 + Vector3(-0.04, 0.9, 0.03), e2 + Vector3(-0.04, 1.2, 0.03)], [0.012], 5, [chrome])
    # --- the sticker on the fixed front pane
    _sink_plate(st, K.T(Vector3(0.46, 1.62, B + 0.03)))
    # lamp housing
    K.rbox(st, K.T(Vector3(0, H - 0.03, 0)), Vector3(0.36, 0.03, 0.08), 0.01, Color(0.7, 0.7, 0.68))
    K.add_mesh(self, "Booth", K.finish(st, 3.0), K.mat("tex_door_paint_128.png", 0.35, true))
    # --- fluorescent tube (glow) + light
    st = K.begin()
    K.tube(st, Transform3D.IDENTITY, [Vector3(-0.32, H - 0.08, 0), Vector3(0.32, H - 0.08, 0)], [0.018], 6, [Color(0.85, 1.0, 0.92)])
    _tube = K.add_mesh(self, "Tube", K.finish(st), K.glow(Color(1, 1, 1)))
    _lamp = OmniLight3D.new()
    _lamp.name = "Lamp"
    _lamp.position = Vector3(0, H - 0.25, 0)
    _lamp.omni_range = 2.5
    _lamp.light_color = Color(0.85, 1.0, 0.9)
    _lamp.light_energy = 0.6
    _lamp.shadow_enabled = false
    _lamp.light_cull_mask = 0xFFFFF & ~FPRestroom.ROOM_VISUAL_LAYER & ~FPMirrorReflection.HANDS_ROOM_LAYER & ~FPMirrorReflection.MIRROR_BODY_LAYER & ~FPMirror.HOLO_LAYER
    add_child(_lamp)
    # --- fat on the roof and down the back-right corner
    st = K.begin()
    var growth := [
        [Vector3(0.45, 2.42, -0.45), 0.3, 0.3], [Vector3(-0.4, 2.45, 0.1), 0.28, 0.2], [Vector3(-0.6, 2.4, -0.7), 0.24, 0.3],
        [Vector3(0.82, 1.85, -0.82), 0.24, 0.35], [Vector3(0.84, 1.1, -0.84), 0.22, 0.3], [Vector3(0.82, 0.35, -0.82), 0.26, 0.0],
        [Vector3(0.7, 2.38, 0.75), 0.22, 0.4],
    ]
    for i in range(growth.size()):
        var g: Array = growth[i]
        _growth(st, g[0], g[1], i, g[2])
    K.add_mesh(self, "FatGrowth", K.finish(st, 3.0), K.mat("tex_fat_128.png", 0.8, true))

## One glazed wall in its own frame (local +Z = outward, x from x0 to x1):
## kick panel, mid and top rails, a mullion, two rows of panes.
## `states` per pane: 0 intact, 1 cracked, 2 missing.
func _wall(st: SurfaceTool, t: Transform3D, x0: float, x1: float, states: Array, seed: int) -> void:
    var xm := (x0 + x1) * 0.5
    var hw := (x1 - x0) * 0.5
    K.rbox(st, t * K.T(Vector3(xm, 0.25, 0)), Vector3(hw, 0.2, 0.012), 0.006, FRAME.darkened(0.1), FRAME_EDGE)
    for ry in [0.46, 1.35, H - 0.04]:
        K.rbox(st, t * K.T(Vector3(xm, ry, 0)), Vector3(hw, 0.025, 0.025), 0.008, FRAME, FRAME_EDGE)
    var cols := 2 if states.size() >= 4 else 1
    if cols == 2:
        K.rbox(st, t * K.T(Vector3(xm, (0.46 + H) * 0.5, 0)), Vector3(0.02, (H - 0.46) * 0.5, 0.02), 0.006, FRAME, FRAME_EDGE)
    var idx := 0
    for row in range(2):
        var y0: float = [0.485, 1.375][row]
        var y1: float = [1.325, H - 0.065][row]
        for c in range(cols):
            var px0 := x0 + c * hw + (0.02 if c > 0 else 0.0)
            var px1 := (x0 + (c + 1) * hw) - (0.02 if c < cols - 1 else 0.0)
            _pane(st, t, px0, px1, y0, y1, states[idx], seed * 10 + idx)
            idx += 1

func _pane(st: SurfaceTool, t: Transform3D, x0: float, x1: float, y0: float, y1: float, state: int, seed: int) -> void:
    if state == 2:
        # gone: a few shards left in the frame
        _shard(st, t, Vector3(x0, y0, 0), Vector3(x0 + 0.12 + K.h(seed, 1) * 0.1, y0, 0), Vector3(x0, y0 + 0.18 + K.h(seed, 2) * 0.15, 0))
        _shard(st, t, Vector3(x1, y1, 0), Vector3(x1 - 0.1 - K.h(seed, 3) * 0.1, y1, 0), Vector3(x1, y1 - 0.12 - K.h(seed, 4) * 0.12, 0))
        _shard(st, t, Vector3(x1, y0, 0), Vector3(x1 - 0.08, y0, 0), Vector3(x1, y0 + 0.1, 0))
        return
    var g := GLASS.lerp(Color(0.1, 0.14, 0.18), K.h(seed, 7) * 0.5)
    for s in [1.0, -1.0]:
        K.quad(st, t, Vector3(x0, y0, 0), Vector3(x1, y0, 0), Vector3(x1, y1, 0), Vector3(x0, y1, 0), Vector3(0, 0, s), g)
    if state == 1:
        var c := Vector2(lerpf(x0, x1, 0.3 + K.h(seed, 5) * 0.4), lerpf(y0, y1, 0.3 + K.h(seed, 6) * 0.4))
        for k in range(6):
            var a := TAU * (float(k) + K.h(seed, k, 8) * 0.6) / 6.0
            var l := 0.12 + K.h(seed, k, 9) * 0.2
            var mid := c + Vector2(cos(a), sin(a)) * l * 0.5 + Vector2(-sin(a), cos(a)) * 0.02
            var e := c + Vector2(cos(a), sin(a)) * l
            e = Vector2(clampf(e.x, x0, x1), clampf(e.y, y0, y1))
            mid = Vector2(clampf(mid.x, x0, x1), clampf(mid.y, y0, y1))
            for s in [1.0, -1.0]:
                _bar(st, t, c, mid, 0.006, 0.003 * s, CRACK, s)
                _bar(st, t, mid, e, 0.004, 0.003 * s, CRACK, s)

func _shard(st: SurfaceTool, t: Transform3D, a: Vector3, b: Vector3, c: Vector3) -> void:
    K.tri(st, t, a, b, c, Vector3.BACK, GLASS)
    K.tri(st, t, a, b, c, Vector3.FORWARD, GLASS)

## One folding-door leaf centred at `c`, turned `yaw` degrees, half width hw.
func _leaf(st: SurfaceTool, c: Vector3, yaw: float, hw: float, cracked: bool) -> void:
    var t := K.T(c, Vector3(0, yaw, 0))
    for sx in [-1.0, 1.0]:
        K.rbox(st, t * K.T(Vector3(sx * (hw - 0.02), H * 0.5 - 0.01, 0)), Vector3(0.02, H * 0.5 - 0.04, 0.02), 0.006, FRAME, FRAME_EDGE)
    K.rbox(st, t * K.T(Vector3(0, 0.25, 0)), Vector3(hw, 0.2, 0.012), 0.006, FRAME.darkened(0.1), FRAME_EDGE)
    for ry in [0.46, 1.35, H - 0.07]:
        K.rbox(st, t * K.T(Vector3(0, ry, 0)), Vector3(hw - 0.02, 0.022, 0.02), 0.006, FRAME, FRAME_EDGE)
    _pane(st, t, -hw + 0.04, hw - 0.04, 0.48, 1.33, 1 if cracked else 0, 77 if cracked else 78)
    _pane(st, t, -hw + 0.04, hw - 0.04, 1.37, H - 0.09, 0, 79)

## Sticker: a handset with an arrow sinking into wavy flesh.
func _sink_plate(st: SurfaceTool, t: Transform3D) -> void:
    K.rbox(st, t, Vector3(0.17, 0.2, 0.006), 0.004, Color(0.88, 0.74, 0.18), Color(0.3, 0.26, 0.12))
    var ink := Color(0.06, 0.06, 0.06)
    var z := 0.008
    # handset: grip bar with ear and mouth cups
    _bar(st, t, Vector2(-0.09, 0.14), Vector2(0.09, 0.14), 0.03, z, ink)
    _poly(st, t, [Vector2(-0.13, 0.08), Vector2(-0.065, 0.08), Vector2(-0.07, 0.155), Vector2(-0.125, 0.155)], z, ink)
    _poly(st, t, [Vector2(0.065, 0.08), Vector2(0.13, 0.08), Vector2(0.125, 0.155), Vector2(0.07, 0.155)], z, ink)
    # arrow down
    _bar(st, t, Vector2(0, 0.07), Vector2(0, -0.04), 0.03, z, ink)
    _poly(st, t, [Vector2(-0.055, -0.035), Vector2(0.055, -0.035), Vector2(0.0, -0.1)], z, ink)
    # wavy flesh at the bottom
    var red := Color(0.62, 0.1, 0.1)
    for k in range(8):
        var xa := -0.16 + k * 0.04
        var xb := xa + 0.04
        var ya := -0.11 + sin(k * 1.6) * 0.015
        var yb := -0.11 + sin((k + 1) * 1.6) * 0.015
        _poly(st, t, [Vector2(xa, -0.185), Vector2(xb, -0.185), Vector2(xb, yb), Vector2(xa, ya)], z + 0.001, red)

## Fat mass with fused satellites and drips hanging from it.
func _growth(st: SurfaceTool, gp: Vector3, r: float, i: int, drip: float) -> void:
    var c := _keep(gp, r * 1.45)
    K.blob(st, Transform3D.IDENTITY, c, Vector3(r, r * 0.7, r), 0.4, 90 + i, FAT_A, FAT_B)
    for j in range(3):
        var off := Vector3(K.h(i, j, 31) - 0.5, (K.h(i, j, 32) - 0.5) * 0.6, K.h(i, j, 33) - 0.5).normalized() * r * 0.75
        var sr := r * (0.35 + K.h(i, j, 34) * 0.3)
        K.blob(st, Transform3D.IDENTITY, _keep(c + off, sr * 1.45), Vector3(sr, sr * 0.8, sr), 0.45, 200 + i * 7 + j, FAT_B, FAT_A)
    if drip <= 0.0:
        return
    for j in range(2):
        var ang := K.h(i, j, 41) * TAU
        var side := Vector3(cos(ang), 0, sin(ang)) * r * 0.55
        var drop := drip * (0.6 + K.h(i, j, 42) * 0.8)
        var pts: Array = []
        for k in range(5):
            var tt := float(k) / 4.0
            pts.append(_keep(c + side * (1.0 + tt * 0.3) + Vector3(sin(tt * 3.0 + j) * 0.03, -r * 0.4 - drop * tt, cos(tt * 2.0 + i) * 0.03), 0.06))
        K.tube(st, Transform3D.IDENTITY, pts, [0.045, 0.032, 0.024, 0.018, 0.026], 5, [FAT_A, FAT_B])
        K.blob(st, Transform3D.IDENTITY, pts[4], Vector3(0.032, 0.045, 0.032), 0.2, 300 + i * 5 + j, FAT_B, FAT_A)

## Clamp a point so a part reaching `r` around it stays in the pocket + 0.28 m.
func _keep(p: Vector3, r: float) -> Vector3:
    var g := 0.28 - r
    return p.clamp(Vector3(-POCKET_HALF.x - g, -g, -POCKET_HALF.z - g), Vector3(POCKET_HALF.x + g, POCKET_HALF.y * 2.0 + g, POCKET_HALF.z + g))

## Flat convex polygon in a local XY plane at depth z, facing +Z (or -Z).
func _poly(st: SurfaceTool, t: Transform3D, pts: Array, z: float, col: Color, facing: float = 1.0) -> void:
    var a: Vector2 = pts[0]
    for i in range(1, pts.size() - 1):
        var b: Vector2 = pts[i]
        var c: Vector2 = pts[i + 1]
        K.tri(st, t, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(c.x, c.y, z), Vector3(0, 0, facing), col)

## Thick 2D stroke from a to b.
func _bar(st: SurfaceTool, t: Transform3D, a: Vector2, b: Vector2, w: float, z: float, col: Color, facing: float = 1.0) -> void:
    var d := (b - a).normalized()
    var n := Vector2(-d.y, d.x) * w * 0.5
    _poly(st, t, [a - n, b - n, b + n, a + n], z, col, facing)

func set_light(on: bool) -> void:
    _tube.visible = on
    _lamp.visible = on
