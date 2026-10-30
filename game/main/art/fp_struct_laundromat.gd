extends Node3D

## Biome structure: a 1970s coin laundromat fragment swallowed into the
## clothing-wad stretch of the surface shell. Three white enamel front
## loaders stand in a row against the back (-Z) wall: chrome-ringed porthole
## doors with dark glass, coin slot plates, a beige control strip with plain
## knobs. Its job was washing strangers' clothes for coins; now one door hangs
## open and the swallowed clothes spill out of the drum onto an avocado lino
## strip. A folding table still holds a folded stack. Clothes the sphere ate
## are pressed into fabric wads with blood-brown creases on every corner, and
## sleeves and trouser legs dangle from them. A ceiling fluorescent hums.
## Warning plate: a clothes wad with a long slow arrow (clothes barely regrow).
## Origin = pocket floor centre, mouth on +Z. Public: set_light(on), pocket_half().

const K := preload("res://main/art/fp_art_kit.gd")
const POCKET_HALF := Vector3(1.5, 1.1, 0.9)
const MACHINE_X := [-0.75, 0.0, 0.75]
const FRONT_Z := -0.42
const PORT_Y := 0.47
const OPEN_MACHINE := 0
const DENIM := Color(0.36, 0.4, 0.52)
const BEIGE := Color(0.62, 0.58, 0.48)
const DULL_RED := Color(0.5, 0.16, 0.18)
const CREASE := Color(0.3, 0.07, 0.07)
var _tube: MeshInstance3D
var _lamp: OmniLight3D

func pocket_half() -> Vector3:
    return POCKET_HALF

func _ready() -> void:
    _build_machines()
    _build_chrome()
    _build_clothes()
    _build_light()

func _build_machines() -> void:
    var st := K.begin()
    var enamel := Color(0.86, 0.84, 0.78)
    var enamel_edge := Color(0.7, 0.68, 0.6)
    var strip := Color(0.6, 0.55, 0.44)
    for i in range(MACHINE_X.size()):
        var cx: float = MACHINE_X[i]
        var yellowed := enamel.lerp(Color(0.78, 0.72, 0.55), K.h(i, 3) * 0.5)
        # cabinet, sunk a little into the back wall
        K.rbox(st, K.T(Vector3(cx, 0.43, -0.72)), Vector3(0.29, 0.43, 0.3), 0.025, yellowed, enamel_edge)
        # recessed dark kick plate
        K.rbox(st, K.T(Vector3(cx, 0.045, FRONT_Z - 0.01)), Vector3(0.26, 0.04, 0.012), 0.005, Color(0.2, 0.19, 0.18))
        # control strip (backsplash) with two plain knobs
        K.rbox(st, K.T(Vector3(cx, 0.94, -0.9)), Vector3(0.29, 0.09, 0.07), 0.015, strip, strip.darkened(0.25))
        for k in range(2):
            var kx := cx - 0.14 + k * 0.1
            K.lathe(st, K.T(Vector3(kx, 0.95, -0.83), Vector3(90, 0, 0)), [Vector2(0.0, 0.0), Vector2(0.032, 0.0), Vector2(0.032, 0.022), Vector2(0.026, 0.03), Vector2(0.0, 0.032)], 8, [Color(0.12, 0.11, 0.1)])
        # a grey indicator window (no text)
        K.rbox(st, K.T(Vector3(cx + 0.14, 0.95, -0.829)), Vector3(0.06, 0.025, 0.004), 0.003, Color(0.25, 0.27, 0.26))
        # drip rust streak down the front
        K.quad(st, Transform3D.IDENTITY, Vector3(cx - 0.2, 0.18, FRONT_Z + 0.002), Vector3(cx - 0.17, 0.18, FRONT_Z + 0.002), Vector3(cx - 0.18, 0.62, FRONT_Z + 0.002), Vector3(cx - 0.2, 0.62, FRONT_Z + 0.002), Vector3.BACK, Color(0.5, 0.36, 0.22))
    # lino strip: avocado / mustard checker, worn through in places
    var tile := 0.3
    for ix in range(10):
        for iz in range(5):
            if K.h(ix, iz, 7) < 0.14:
                continue
            var x0 := -1.5 + ix * tile
            var z0 := FRONT_Z + iz * 0.264
            var z1 := z0 + 0.264
            var col := Color(0.55, 0.5, 0.36) if (ix + iz) % 2 == 0 else Color(0.36, 0.4, 0.28)
            col = col.darkened(K.h(ix, iz, 8) * 0.25)
            K.quad(st, Transform3D.IDENTITY, Vector3(x0, 0.004, z0), Vector3(x0, 0.004, z1), Vector3(x0 + tile, 0.004, z1), Vector3(x0 + tile, 0.004, z0), Vector3.UP, col)
    # folding table along the +X wall, a folded stack on it
    var formica := Color(0.72, 0.68, 0.56)
    K.rbox(st, K.T(Vector3(1.22, 0.78, 0.08)), Vector3(0.22, 0.022, 0.46), 0.01, formica, Color(0.55, 0.55, 0.55))
    for sz in [-1, 1]:
        K.tube(st, Transform3D.IDENTITY, [Vector3(1.06, 0.0, 0.08 + sz * 0.4), Vector3(1.38, 0.76, 0.08 - sz * 0.05)], [0.012], 4, [Color(0.5, 0.5, 0.52)])
        K.tube(st, Transform3D.IDENTITY, [Vector3(1.38, 0.0, 0.08 + sz * 0.4), Vector3(1.06, 0.76, 0.08 - sz * 0.05)], [0.012], 4, [Color(0.5, 0.5, 0.52)])
    var stack := [BEIGE, DENIM, DULL_RED.lightened(0.15)]
    for i in range(stack.size()):
        K.rbox(st, K.T(Vector3(1.2 + i * 0.01, 0.825 + i * 0.045, -0.15), Vector3(0, i * 7.0, 0)), Vector3(0.14, 0.022, 0.12), 0.015, stack[i], (stack[i] as Color).darkened(0.3))
    # pictogram plate above the middle machine: clothes wad + long slow arrow
    var plate := K.T(Vector3(0.0, 1.42, -0.87))
    K.rbox(st, plate, Vector3(0.22, 0.16, 0.012), 0.008, Color(0.86, 0.82, 0.66), Color(0.4, 0.38, 0.32))
    var ink := Color(0.12, 0.1, 0.1)
    K.blob(st, plate, Vector3(-0.12, -0.08, 0.016), Vector3(0.06, 0.045, 0.012), 0.3, 77, DULL_RED.darkened(0.2), ink)
    var arc: Array = []
    for k in range(9):
        var a := lerpf(PI * 0.95, PI * 0.12, float(k) / 8.0)
        arc.append(Vector3(0.02 + cos(a) * 0.14, -0.1 + sin(a) * 0.17, 0.016))
    K.tube(st, plate, arc, [0.006], 4, [ink])
    var tip: Vector3 = arc[arc.size() - 1]
    var prev: Vector3 = arc[arc.size() - 2]
    var fwd := (tip - prev).normalized()
    var side := Vector3(-fwd.y, fwd.x, 0.0)
    K.tri(st, plate, tip + fwd * 0.04, tip + side * 0.025, tip - side * 0.025, Vector3.BACK, ink)
    # small dotted ticks along the arrow: slow, many steps
    for k in range(1, 8, 2):
        var p: Vector3 = arc[k]
        K.rbox(st, plate * K.T(p + Vector3(0, -0.03, 0)), Vector3(0.004, 0.004, 0.003), 0.001, ink)
    for sx in [-1, 1]:
        K.lathe(st, plate * K.T(Vector3(sx * 0.19, 0.13, 0.012), Vector3(90, 0, 0)), [Vector2(0.0, 0.0), Vector2(0.01, 0.0), Vector2(0.0, 0.006)], 5, [Color(0.5, 0.5, 0.48)])
    K.add_mesh(self, "Machines", K.finish(st, 3.0), K.mat("tex_ceramic_128.png", 0.35, true))

func _build_chrome() -> void:
    var st := K.begin()
    var chrome := Color(0.78, 0.8, 0.82)
    var glass := Color(0.05, 0.06, 0.08)
    var door_prof := [Vector2(0.0, 0.0), Vector2(0.22, 0.0), Vector2(0.22, 0.03), Vector2(0.155, 0.045), Vector2(0.15, 0.03), Vector2(0.0, 0.036)]
    var door_cols := [chrome.darkened(0.4), chrome, chrome, chrome.darkened(0.3), glass]
    for i in range(MACHINE_X.size()):
        var cx: float = MACHINE_X[i]
        if i == OPEN_MACHINE:
            # opening: chrome rim around a dark drum mouth
            K.lathe(st, K.T(Vector3(cx, PORT_Y, FRONT_Z), Vector3(90, 0, 0)), [Vector2(0.2, 0.0), Vector2(0.2, 0.012), Vector2(0.17, 0.016), Vector2(0.17, 0.0), Vector2(0.0, -0.02)], 12, [chrome, chrome, chrome.darkened(0.5), Color(0.03, 0.03, 0.035)])
            # the door swung out to the left on its hinge
            var hinge := K.T(Vector3(cx - 0.22, PORT_Y, FRONT_Z + 0.01), Vector3(0, -105, 0))
            K.lathe(st, hinge * K.T(Vector3(0.22, 0.0, 0.0), Vector3(90, 0, 0)), door_prof, 12, door_cols)
            K.rbox(st, K.T(Vector3(cx - 0.225, PORT_Y, FRONT_Z + 0.005)), Vector3(0.012, 0.05, 0.012), 0.004, chrome.darkened(0.2))
        else:
            K.lathe(st, K.T(Vector3(cx, PORT_Y, FRONT_Z), Vector3(90, 0, 0)), door_prof, 12, door_cols)
            # door latch handle
            K.rbox(st, K.T(Vector3(cx + 0.2, PORT_Y, FRONT_Z + 0.03)), Vector3(0.014, 0.05, 0.02), 0.006, chrome)
        # coin slot plate with slide
        K.rbox(st, K.T(Vector3(cx + 0.19, 0.78, FRONT_Z + 0.008)), Vector3(0.07, 0.05, 0.01), 0.005, chrome, chrome.darkened(0.3))
        K.rbox(st, K.T(Vector3(cx + 0.19, 0.795, FRONT_Z + 0.019)), Vector3(0.004, 0.022, 0.003), 0.001, Color(0.04, 0.04, 0.04))
        K.rbox(st, K.T(Vector3(cx + 0.19, 0.75, FRONT_Z + 0.026)), Vector3(0.045, 0.009, 0.016), 0.004, chrome.darkened(0.15))
    # fluorescent fixture housing
    K.rbox(st, K.T(Vector3(0.0, 2.16, -0.2)), Vector3(0.62, 0.03, 0.09), 0.01, Color(0.6, 0.6, 0.58))
    K.add_mesh(self, "Chrome", K.finish(st, 4.0), K.mat("tex_chrome_128.png", 0.6, true))

func _build_clothes() -> void:
    var st := K.begin()
    var fabrics := [DENIM, BEIGE, DULL_RED]
    # spill: from the open drum down onto the lino in a wad
    var cx: float = MACHINE_X[OPEN_MACHINE]
    var spill := [
        [Vector3(cx, PORT_Y - 0.02, FRONT_Z + 0.02), Vector3(0.14, 0.12, 0.1)],
        [Vector3(cx + 0.04, 0.3, FRONT_Z + 0.14), Vector3(0.17, 0.13, 0.15)],
        [Vector3(cx + 0.1, 0.13, -0.08), Vector3(0.32, 0.14, 0.26)],
        [Vector3(cx + 0.38, 0.08, 0.08), Vector3(0.2, 0.09, 0.18)],
    ]
    for i in range(spill.size()):
        var c: Vector3 = spill[i][0]
        var r: Vector3 = spill[i][1]
        var fa: Color = fabrics[i % 3]
        K.blob(st, Transform3D.IDENTITY, c, r, 0.35, 300 + i, fa, fa.lerp(CREASE, 0.55))
        for j in range(3):
            var off := Vector3(K.h(i, j, 51) - 0.5, (K.h(i, j, 52) - 0.5) * 0.5, K.h(i, j, 53) - 0.5).normalized() * r.x * 0.6
            var fb: Color = fabrics[(i + j + 1) % 3]
            K.blob(st, Transform3D.IDENTITY, c + off, r * (0.45 + K.h(i, j, 54) * 0.2), 0.4, 320 + i * 5 + j, fb, CREASE)
    # a sleeve hanging out of the drum, a trouser leg across the floor
    K.tube(st, Transform3D.IDENTITY, [Vector3(cx + 0.1, PORT_Y - 0.06, FRONT_Z + 0.04), Vector3(cx + 0.16, 0.3, FRONT_Z + 0.1), Vector3(cx + 0.2, 0.12, FRONT_Z + 0.22), Vector3(cx + 0.24, 0.03, FRONT_Z + 0.36)], [0.045, 0.042, 0.04, 0.046], 6, [BEIGE, BEIGE.darkened(0.15), BEIGE.lerp(CREASE, 0.3)])
    K.tube(st, Transform3D.IDENTITY, [Vector3(cx + 0.45, 0.06, 0.12), Vector3(cx + 0.7, 0.05, 0.28), Vector3(cx + 0.95, 0.045, 0.32), Vector3(cx + 1.15, 0.05, 0.45)], [0.075, 0.068, 0.062, 0.066], 6, [DENIM, DENIM.darkened(0.15), DENIM.lerp(CREASE, 0.35)])
    # wads of swallowed clothes pressed into the walls and ceiling
    var growth := [
        Vector3(1.5, 2.2, -0.9), Vector3(-1.5, 2.2, -0.9), Vector3(-1.5, 1.9, 0.9),
        Vector3(1.5, 2.0, 0.9), Vector3(0.45, 1.05, -0.9), Vector3(-1.5, 0.6, -0.6),
        Vector3(-0.4, 2.2, 0.2), Vector3(1.5, 1.2, -0.75), Vector3(-1.1, 1.15, -0.9),
    ]
    for i in range(growth.size()):
        var r := 0.24 + K.h(i, 2, 9) * 0.14
        var gp := _fit(growth[i], r * 1.6)
        var fa: Color = fabrics[i % 3]
        var fb: Color = fabrics[(i + 1) % 3]
        K.blob(st, Transform3D.IDENTITY, gp, Vector3(r, r * 0.75, r), 0.35, 400 + i, fa, fa.lerp(CREASE, 0.5))
        for j in range(4):
            var off := Vector3(K.h(i, j, 61) - 0.5, (K.h(i, j, 62) - 0.5) * 0.6, K.h(i, j, 63) - 0.5).normalized() * r * 0.75
            var sr := r * (0.35 + K.h(i, j, 64) * 0.3)
            var sc: Color = fb if j % 2 == 0 else fa.lerp(fb, 0.5)
            K.blob(st, Transform3D.IDENTITY, gp + off, Vector3(sr, sr * 0.7, sr), 0.4, 500 + i * 7 + j, sc, CREASE)
        # blood-brown crease seams between the folds
        K.blob(st, Transform3D.IDENTITY, gp + Vector3(0, -r * 0.35, 0), Vector3(r * 0.75, r * 0.3, r * 0.75), 0.3, 560 + i, CREASE, CREASE.lightened(0.1))
        # sleeves / trouser legs dangling out of the wad
        var inward := Vector3(-gp.x, 0.0, -gp.z).normalized()
        if inward.length() < 0.1:
            inward = Vector3.BACK
        for j in range(2):
            var tang := inward.cross(Vector3.UP) * (K.h(i, j, 71) - 0.5) * r * 1.4
            var root := gp + inward * r * 0.55 + tang + Vector3(0, -r * 0.4, 0)
            var drop := 0.2 + K.h(i, j, 72) * 0.35
            drop = minf(drop, root.y - 0.1)
            if drop < 0.15:
                continue
            var leg := K.h(i, j, 73) > 0.6
            var col: Color = DENIM if leg else fabrics[(i + j + 2) % 3]
            var rad := 0.06 if leg else 0.04
            var pts: Array = []
            for k in range(4):
                var t := float(k) / 3.0
                pts.append(root + inward * t * 0.08 + Vector3(sin(t * 3.0 + i) * 0.04, -drop * t, cos(t * 2.0 + j) * 0.04))
            K.tube(st, Transform3D.IDENTITY, pts, [rad, rad * 0.95, rad * 0.9, rad * 1.1], 5, [col, col.darkened(0.15), col.lerp(CREASE, 0.4)])
    # membrane, not flesh: the dark flesh texture crushed the fabric colours to
    # near-black lumps in the render check
    K.add_mesh(self, "Clothes", K.finish(st, 3.0), K.mat("tex_membrane_128.png", 0.4, true))

func _build_light() -> void:
    var st := K.begin()
    for sz in [-1, 1]:
        K.tube(st, Transform3D.IDENTITY, [Vector3(-0.56, 2.115, -0.2 + sz * 0.035), Vector3(0.56, 2.115, -0.2 + sz * 0.035)], [0.016], 6, [Color(0.9, 0.96, 1.0)])
    _tube = K.add_mesh(self, "Tube", K.finish(st), K.glow(Color(1, 1, 1)))
    _lamp = OmniLight3D.new()
    _lamp.position = Vector3(0.0, 1.95, -0.15)
    _lamp.omni_range = 3.0
    _lamp.light_color = Color(0.92, 0.97, 1.0)
    _lamp.light_energy = 0.6
    _lamp.light_cull_mask = 0xFFFFF & ~FPRestroom.ROOM_VISUAL_LAYER & ~FPMirrorReflection.HANDS_ROOM_LAYER & ~FPMirrorReflection.MIRROR_BODY_LAYER & ~FPMirror.HOLO_LAYER
    add_child(_lamp)

## Keeps a mass centre far enough from the pocket box (grown by the 0.3 m
## sink allowance) that the mass with its satellites stays inside it.
func _fit(p: Vector3, margin: float) -> Vector3:
    var lo := Vector3(-POCKET_HALF.x - 0.3, -0.3, -POCKET_HALF.z - 0.3) + Vector3.ONE * margin
    var hi := Vector3(POCKET_HALF.x + 0.3, POCKET_HALF.y * 2.0 + 0.3, POCKET_HALF.z + 0.3) - Vector3.ONE * margin
    return p.clamp(lo, hi)

func set_light(on: bool) -> void:
    _tube.visible = on
    _lamp.visible = on
