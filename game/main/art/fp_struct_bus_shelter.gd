extends Node3D

## Structure: a 1980s city bus shelter swallowed into the surface shell,
## where the mass is mostly swallowed clothes pressed into wads. Square
## steel posts, a slanted roof with a fluorescent tube under it (still
## flickering), scratched safety-glass back panels with the middle one
## smashed out, a long slatted bench, a timetable frame on the side panel
## (coloured route bars only), and the stop pole with its round sign. The
## sign is the biome's warning: a bus with an upward arrow, the street is
## just above (the surface is close). Clothing wads bulge through the
## missing pane and sit on the roof, sleeves hang from the roof edge.
## Origin = pocket floor centre; back glass on the -Z side, mouth at +Z.
## Public: set_light(on), set_flicker(bool).

const K := preload("res://main/art/fp_art_kit.gd")
const POCKET_HALF := Vector3(1.6, 1.2, 0.9)
const PX := 1.45          # posts at +-PX
const ZB := -0.75         # back posts / glass line
const ZF := 0.45          # front posts
const ROOF_B := 2.32      # roof height at the back edge
const ROOF_F := 2.12      # roof height at the front edge
const RZ0 := -0.86
const RZ1 := 0.78
var _tube: MeshInstance3D
var _lamp: OmniLight3D
var _flicker := true
var _time := 0.0

func pocket_half() -> Vector3:
    return POCKET_HALF

func _roof_y(z: float) -> float:
    return lerpf(ROOF_B, ROOF_F, (z - RZ0) / (RZ1 - RZ0))

func _ready() -> void:
    var st := K.begin()
    var steel := Color(0.36, 0.38, 0.4)
    var rust := Color(0.38, 0.24, 0.15)
    # posts (square steel tube) up to the roof underside
    for sx: int in [-1, 1]:
        for z: float in [ZB, ZF]:
            var top := _roof_y(z) - 0.04
            K.rbox(st, K.T(Vector3(sx * PX, top * 0.5, z)), Vector3(0.04, top * 0.5, 0.04), 0.012, steel, rust)
            K.rbox(st, K.T(Vector3(sx * PX, 0.01, z)), Vector3(0.07, 0.01, 0.07), 0.005, steel.darkened(0.3))
    # slanted roof: deck + fascia + gutter at the back
    var slope := rad_to_deg(atan2(ROOF_B - ROOF_F, RZ1 - RZ0))
    var mid_z := (RZ0 + RZ1) * 0.5
    var mid_y := (ROOF_B + ROOF_F) * 0.5
    var half_len := (RZ1 - RZ0) * 0.5 / cos(deg_to_rad(slope))
    K.rbox(st, K.T(Vector3(0, mid_y, mid_z), Vector3(slope, 0, 0)), Vector3(1.56, 0.025, half_len), 0.01, Color(0.42, 0.44, 0.45), rust)
    K.rbox(st, K.T(Vector3(0, ROOF_F - 0.03, RZ1 - 0.01)), Vector3(1.58, 0.05, 0.02), 0.01, Color(0.24, 0.3, 0.42), rust)
    K.rbox(st, K.T(Vector3(0, ROOF_B - 0.03, RZ0 + 0.03)), Vector3(1.58, 0.05, 0.03), 0.01, Color(0.24, 0.3, 0.42), rust)
    # roof beams over the posts
    for sx: int in [-1, 1]:
        K.rbox(st, K.T(Vector3(sx * PX, mid_y - 0.06, mid_z), Vector3(slope, 0, 0)), Vector3(0.03, 0.04, half_len - 0.02), 0.01, steel)
    # tube housing under the roof
    var tz := -0.1
    var ty := _roof_y(tz) - 0.06
    K.rbox(st, K.T(Vector3(0, ty + 0.01, tz), Vector3(slope, 0, 0)), Vector3(0.62, 0.025, 0.06), 0.01, Color(0.6, 0.6, 0.58))
    # back glass frame: rails + mullions
    var xs := [-PX, -PX / 3.0, PX / 3.0, PX]
    for x: float in xs:
        K.rbox(st, K.T(Vector3(x, 1.08, ZB)), Vector3(0.022, 0.93, 0.022), 0.006, steel)
    for y: float in [0.15, 2.02]:
        K.rbox(st, K.T(Vector3(0, y, ZB)), Vector3(PX, 0.022, 0.022), 0.006, steel)
    # scratches on the two remaining panes (thin pale streaks on both faces)
    for p: int in [0, 2]:
        var x0: float = xs[p]
        for k in range(7):
            var cx := x0 + 0.12 + K.h(p, k, 11) * 0.72
            var cy := 0.4 + K.h(p, k, 12) * 1.4
            var ang := -40.0 + K.h(p, k, 13) * 80.0
            var ln := 0.06 + K.h(p, k, 14) * 0.18
            for sz: int in [-1, 1]:
                K.rbox(st, K.T(Vector3(cx, cy, ZB + sz * 0.007), Vector3(0, 0, ang)), Vector3(ln, 0.0025, 0.001), 0.0, Color(0.72, 0.74, 0.76))
    # side panel on the -x end (painted steel sheet, posts to posts)
    var panel := Color(0.24, 0.3, 0.42)
    K.rbox(st, K.T(Vector3(-PX, 1.1, (ZB + ZF) * 0.5)), Vector3(0.012, 0.92, (ZF - ZB) * 0.5 - 0.04), 0.004, panel, panel.darkened(0.3))
    _timetable(st, Transform3D(Basis.from_euler(Vector3(0, PI * 0.5, 0)), Vector3(-PX + 0.014, 1.35, -0.15)))
    # long bench: slats on two brackets, in front of the glass
    var bench := Color(0.6, 0.33, 0.16)
    for k in range(3):
        K.rbox(st, K.T(Vector3(0, 0.45 - k * 0.006, -0.62 + k * 0.085)), Vector3(1.05, 0.014, 0.035), 0.006, bench.darkened(K.h(k, 15) * 0.2), rust)
    for sx: int in [-1, 0, 1]:
        var bx := sx * 0.9
        K.rbox(st, K.T(Vector3(bx, 0.42, -0.54)), Vector3(0.02, 0.02, 0.15), 0.006, steel)
        K.rbox(st, K.T(Vector3(bx, 0.21, -0.66)), Vector3(0.02, 0.21, 0.02), 0.006, steel)
    # paving under the shelter + kerb at the mouth
    st = _paving(st)
    K.add_mesh(self, "Shelter", K.finish(st, 3.0), K.mat("tex_door_paint_128.png", 0.3, true))
    # glass panes (translucent; the middle one smashed, shards left in frame)
    st = K.begin()
    var glass := Color(0.62, 0.72, 0.74)
    for p: int in [0, 2]:
        var x0: float = xs[p] + 0.022
        var x1: float = xs[p + 1] - 0.022
        K.quad(st, Transform3D.IDENTITY, Vector3(x0, 0.17, ZB), Vector3(x1, 0.17, ZB), Vector3(x1, 2.0, ZB), Vector3(x0, 2.0, ZB), Vector3(0, 0, 1), glass)
    var m0: float = xs[1] + 0.022
    var m1: float = xs[2] - 0.022
    for k in range(4):
        var sx := lerpf(m0, m1, float(k) / 4.0)
        var w := 0.12 + K.h(k, 16) * 0.12
        var hgt := 0.08 + K.h(k, 17) * 0.2
        K.tri(st, Transform3D.IDENTITY, Vector3(sx, 0.17, ZB), Vector3(minf(sx + w, m1), 0.17, ZB), Vector3(sx + w * K.h(k, 18), 0.17 + hgt, ZB), Vector3(0, 0, 1), glass)
        var tw := 0.1 + K.h(k, 19) * 0.12
        K.tri(st, Transform3D.IDENTITY, Vector3(sx, 2.0, ZB), Vector3(minf(sx + tw, m1), 2.0, ZB), Vector3(sx + tw * K.h(k, 20), 2.0 - 0.05 - K.h(k, 21) * 0.14, ZB), Vector3(0, 0, 1), glass)
    var gm := StandardMaterial3D.new()
    gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    gm.vertex_color_use_as_albedo = true
    gm.albedo_color = Color(1, 1, 1, 0.3)
    gm.cull_mode = BaseMaterial3D.CULL_DISABLED
    gm.roughness = 0.2
    gm.metallic_specular = 0.8
    K.add_mesh(self, "Glass", st.commit(), gm)
    # stop pole + round sign at the front right corner
    st = K.begin()
    var pole_p := Vector3(1.32, 0, 0.72)
    K.tube(st, Transform3D.IDENTITY, [pole_p, pole_p + Vector3(0, 1.98, 0)], [0.03], 8, [Color(0.6, 0.6, 0.58)])
    K.lathe(st, K.T(pole_p), [Vector2(0.0, 0.0), Vector2(0.06, 0.0), Vector2(0.05, 0.06), Vector2(0.0, 0.06)], 8, [Color(0.3, 0.3, 0.3)])
    _stop_sign(st, pole_p + Vector3(0, 1.82, 0.04))
    K.add_mesh(self, "StopPole", K.finish(st, 4.0), K.mat("tex_chrome_128.png", 0.3, true))
    # fluorescent tube
    st = K.begin()
    K.tube(st, Transform3D.IDENTITY, [Vector3(-0.55, ty - 0.03, tz), Vector3(0.55, ty - 0.03, tz)], [0.018], 6, [Color(0.9, 0.95, 1.0)])
    _tube = K.add_mesh(self, "Tube", K.finish(st), K.glow(Color(1, 1, 1)))
    _lamp = OmniLight3D.new()
    _lamp.position = Vector3(0, ty - 0.15, tz)
    _lamp.omni_range = 3.0
    _lamp.light_color = Color(0.9, 0.95, 1.0)
    _lamp.light_energy = 0.6
    _lamp.light_cull_mask = 0xFFFFF & ~FPRestroom.ROOM_VISUAL_LAYER & ~FPMirrorReflection.HANDS_ROOM_LAYER & ~FPMirrorReflection.MIRROR_BODY_LAYER & ~FPMirror.HOLO_LAYER
    add_child(_lamp)
    _cloth()

## Paving slabs (grey, a few darker) with a kerb strip at the mouth edge.
func _paving(st: SurfaceTool) -> SurfaceTool:
    for ix in range(8):
        for iz in range(4):
            var x0 := -1.6 + ix * 0.4
            var z0 := -0.9 + iz * 0.4
            var z1 := minf(z0 + 0.4, 0.62)
            if z0 >= 0.62:
                continue
            var c := Color(0.5, 0.49, 0.46).darkened(K.h(ix, iz, 22) * 0.2)
            K.quad(st, Transform3D.IDENTITY, Vector3(x0 + 0.006, 0.004, z0 + 0.006), Vector3(x0 + 0.394, 0.004, z0 + 0.006), Vector3(x0 + 0.394, 0.004, z1 - 0.006), Vector3(x0 + 0.006, 0.004, z1 - 0.006), Vector3.UP, c)
    K.rbox(st, K.T(Vector3(0, 0.0, 0.7)), Vector3(1.6, 0.03, 0.08), 0.015, Color(0.58, 0.57, 0.53), Color(0.4, 0.39, 0.36))
    # dark gum spots
    for k in range(9):
        var p := Vector3(-1.4 + K.h(k, 23) * 2.8, 0.006, -0.4 + K.h(k, 24) * 0.9)
        K.quad(st, Transform3D.IDENTITY, p + Vector3(-0.02, 0, -0.02), p + Vector3(0.02, 0, -0.02), p + Vector3(0.02, 0, 0.02), p + Vector3(-0.02, 0, 0.02), Vector3.UP, Color(0.22, 0.21, 0.2))
    return st

## Timetable frame (frame: centre, +z out of the face = into the shelter):
## aluminium frame, pale sheet, rows of coloured route bars, no text.
func _timetable(st: SurfaceTool, t: Transform3D) -> void:
    K.rbox(st, t, Vector3(0.24, 0.32, 0.012), 0.008, Color(0.7, 0.7, 0.68))
    K.rbox(st, t * K.T(Vector3(0, 0, 0.013)), Vector3(0.21, 0.29, 0.002), 0.0, Color(0.8, 0.78, 0.68))
    var cols := [Color(0.7, 0.15, 0.12), Color(0.15, 0.3, 0.6), Color(0.2, 0.5, 0.25), Color(0.8, 0.62, 0.12)]
    for r in range(9):
        var c: Color = cols[r % 4] if r % 3 != 2 else cols[(r * 7) % 4]
        var x := -0.19 + K.h(r, 25) * 0.08
        var w := 0.06 + K.h(r, 26) * 0.24
        w = minf(w, 0.19 - x)
        var y := 0.24 - r * 0.055
        K.quad(st, t, Vector3(x, y - 0.014, 0.016), Vector3(x + w, y - 0.014, 0.016), Vector3(x + w, y + 0.014, 0.016), Vector3(x, y + 0.014, 0.016), Vector3(0, 0, 1), c.darkened(0.15))
        # small leading colour square (the route mark)
        K.quad(st, t, Vector3(-0.205, y - 0.014, 0.016), Vector3(-0.2 + 0.0, y - 0.014, 0.016), Vector3(-0.2, y + 0.014, 0.016), Vector3(-0.205, y + 0.014, 0.016), Vector3(0, 0, 1), c)

## Round stop sign facing +z at `c`: green rim, yellow face, dark bus
## silhouette with an upward arrow above it.
func _stop_sign(st: SurfaceTool, c: Vector3) -> void:
    var disc := K.T(c, Vector3(90, 0, 0))
    K.lathe(st, disc, [Vector2(0.0, -0.012), Vector2(0.21, -0.012), Vector2(0.21, 0.012), Vector2(0.0, 0.012)], 14, [Color(0.15, 0.4, 0.22), Color(0.15, 0.4, 0.22), Color(0.15, 0.4, 0.22)])
    K.lathe(st, K.T(c + Vector3(0, 0, 0.02), Vector3(90, 0, 0)), [Vector2(0.17, 0.0), Vector2(0.0, 0.0005)], 14, [Color(0.88, 0.75, 0.2)])
    var t := Transform3D(Basis.IDENTITY, c)
    var z := 0.028
    var ink := Color(0.1, 0.18, 0.12)
    # bus body, windows, wheels
    _flat(st, t, Vector2(0, -0.05), Vector2(0.105, 0.045), z, ink)
    for k in range(4):
        _flat(st, t, Vector2(-0.07 + k * 0.047, -0.03), Vector2(0.017, 0.014), z + 0.004, Color(0.88, 0.75, 0.2))
    for sx: int in [-1, 1]:
        K.lathe(st, K.T(Vector3(c.x + sx * 0.06, c.y - 0.1, c.z + z), Vector3(90, 0, 0)), [Vector2(0.022, 0.0), Vector2(0.0, 0.002)], 7, [ink])
    # upward arrow
    _flat(st, t, Vector2(0, 0.06), Vector2(0.012, 0.035), z, Color(0.7, 0.12, 0.1))
    K.tri(st, t, Vector3(-0.045, 0.09, z), Vector3(0.045, 0.09, z), Vector3(0, 0.145, z), Vector3(0, 0, 1), Color(0.7, 0.12, 0.1))
    # back of the sign: plain grey
    K.lathe(st, K.T(c + Vector3(0, 0, -0.02), Vector3(-90, 0, 0)), [Vector2(0.2, 0.0), Vector2(0.0, 0.0005)], 14, [Color(0.5, 0.5, 0.5)])
    # clamp to the pole
    K.rbox(st, K.T(c + Vector3(0, 0, -0.03)), Vector3(0.04, 0.05, 0.02), 0.008, Color(0.4, 0.4, 0.4))

func _flat(st: SurfaceTool, t: Transform3D, c: Vector2, hs: Vector2, z: float, col: Color) -> void:
    K.quad(st, t, Vector3(c.x - hs.x, c.y - hs.y, z), Vector3(c.x + hs.x, c.y - hs.y, z), Vector3(c.x + hs.x, c.y + hs.y, z), Vector3(c.x - hs.x, c.y + hs.y, z), Vector3(0, 0, 1), col)

func _fit(c: Vector3, r: Vector3, lumps: float) -> Vector3:
    var lim := POCKET_HALF + Vector3(0.28, 0.0, 0.28)
    var k := 1.0 + lumps
    var out := r
    out.x = minf(out.x, (lim.x - absf(c.x)) / k)
    out.z = minf(out.z, (lim.z - absf(c.z)) / k)
    out.y = minf(out.y, minf((POCKET_HALF.y * 2.0 + 0.28 - c.y) / k, (c.y + 0.28) / k))
    return out.max(Vector3(0.03, 0.03, 0.03))

## Clothing wads: swallowed clothes pressed into lumpy masses (denim,
## beige, dull red) with dark blood-brown creases; sleeves hang from the
## roof edge.
func _cloth() -> void:
    var st := K.begin()
    var fabrics := [Color(0.36, 0.4, 0.52), Color(0.62, 0.58, 0.48), Color(0.5, 0.16, 0.18)]
    var crease := Color(0.22, 0.08, 0.06)
    var wads := [
        Vector3(-0.1, 1.05, -0.9), Vector3(0.2, 0.55, -0.88), Vector3(-0.3, 1.6, -0.9),
        Vector3(-1.0, 2.5, -0.3), Vector3(0.4, 2.52, 0.1), Vector3(1.2, 2.45, -0.6),
        Vector3(1.55, 0.4, -0.7), Vector3(-1.55, 0.5, 0.6), Vector3(-1.5, 1.9, -0.75), Vector3(1.6, 1.4, 0.2)]
    for i in range(wads.size()):
        var c: Vector3 = wads[i]
        var fab: Color = fabrics[i % 3]
        var r := 0.3 + K.h(i, 71) * 0.15
        var rr := _fit(c, Vector3(r, r * 0.65, r * 0.85), 0.3)
        K.blob(st, Transform3D.IDENTITY, c, rr, 0.3, 700 + i, fab, fab.darkened(0.3))
        # pressed layers: flattened satellite wads in other fabrics
        for j in range(3):
            var off := Vector3(K.h(i, j, 72) - 0.5, (K.h(i, j, 73) - 0.5) * 0.7, K.h(i, j, 74) - 0.5).normalized() * rr * 0.75
            var sf: Color = fabrics[(i + j + 1) % 3]
            var sr := rr.x * (0.4 + K.h(i, j, 75) * 0.25)
            K.blob(st, Transform3D.IDENTITY, c + off, _fit(c + off, Vector3(sr, sr * 0.55, sr * 0.9), 0.3), 0.3, 800 + i * 5 + j, sf, sf.darkened(0.25))
        # creases: dark blood-brown grooves across the visible side
        for j in range(3):
            var a0 := K.h(i, j, 76) * TAU
            var pts: Array = []
            for k in range(5):
                var a := a0 + float(k) * 0.35
                var el := (float(k) - 2.0) * 0.25 + (K.h(i, j, 77) - 0.5) * 0.6
                var d := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el))
                var p := c + Vector3(d.x * rr.x, d.y * rr.y, d.z * rr.z) * 1.02
                pts.append(p)
            K.tube(st, Transform3D.IDENTITY, pts, [0.012, 0.018, 0.02, 0.016, 0.01], 4, [crease, crease.lightened(0.05)], false)
    # sleeves hanging from the roof's front and side edges
    var hangs := [Vector3(-0.75, 0.0, -0.45), Vector3(0.55, 0.0, -0.5), Vector3(-1.5, 0.0, -0.3), Vector3(1.5, 0.0, 0.1), Vector3(-1.35, 0.0, 0.66), Vector3(1.05, 0.0, 0.68)]
    for i in range(hangs.size()):
        var h0: Vector3 = hangs[i]
        var top := _roof_y(h0.z) + 0.02
        var fab: Color = fabrics[(i + 1) % 3]
        var ln := 0.3 + K.h(i, 78) * 0.35
        var pts: Array = []
        var radii: Array = []
        for k in range(6):
            var tt := float(k) / 5.0
            pts.append(Vector3(h0.x + sin(tt * 2.5 + i) * 0.05, top - ln * tt, h0.z + sin(tt * 3.0 + i * 2.0) * 0.04))
            radii.append(lerpf(0.05, 0.036, tt))
        K.tube(st, Transform3D.IDENTITY, pts, radii, 6, [fab, fab.darkened(0.1), fab, fab.darkened(0.2), fab.darkened(0.15)], true, 0.6)
        # cuff
        var cp: Vector3 = pts[5]
        K.tube(st, Transform3D.IDENTITY, [cp + Vector3(0, 0.03, 0), cp + Vector3(0, -0.02, 0)], [0.04], 6, [fab.darkened(0.35)], true, 0.6)
        # knot of cloth where the sleeve leaves the roof
        K.blob(st, Transform3D.IDENTITY, Vector3(h0.x, top + 0.04, h0.z), Vector3(0.1, 0.06, 0.09), 0.3, 900 + i, fab, crease)
    K.add_mesh(self, "Overgrowth", K.finish(st, 3.0), K.mat("tex_membrane_128.png", 0.4, true))

func set_light(on: bool) -> void:
    _tube.visible = on
    _lamp.visible = on

func set_flicker(on: bool) -> void:
    _flicker = on

func _process(delta: float) -> void:
    _time += delta
    if _flicker and _lamp.visible:
        var f := 1.0 if fmod(_time * 1.3, 4.0) > 0.3 else 0.15 + 0.35 * absf(sin(_time * 70.0))
        _lamp.light_energy = 0.6 * f
        _tube.visible = f > 0.3
