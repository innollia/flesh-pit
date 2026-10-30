extends Node3D

## Biome structure: a 1950s barber shop corner swallowed into the hair
## thicket of the surface shell. A heavy hydraulic barber chair on a chrome
## pedestal (cracked red leatherette seat, headrest, footrest) faces a wall
## mirror that has gone dark, over a mint counter with a jar of combs. A red,
## white and blue striped pole hangs on the side wall. Its job was cutting
## hair; now the cut hair heaps on the checker floor and the hair the sphere
## grows mats over the corners, hanging in locks from pink scalp patches.
## A warm bulb burns over the mirror.
## Warning plate on the counter: scissors over hair (a blade cuts hair fast).
## Origin = pocket floor centre, mouth on +Z. Public: set_light(on), pocket_half().

const K := preload("res://main/art/fp_art_kit.gd")
const POCKET_HALF := Vector3(1.2, 1.1, 1.0)
const HAIR_DARK := Color(0.08, 0.06, 0.05)
const HAIR_BROWN := Color(0.2, 0.14, 0.11)
const SCALP := Color(0.66, 0.36, 0.36)
const CHAIR_POS := Vector3(0.28, 0.0, -0.05)
const CHAIR_YAW := -28.0
var _bulb: MeshInstance3D
var _lamp: OmniLight3D

func pocket_half() -> Vector3:
    return POCKET_HALF

func _ready() -> void:
    _build_room()
    _build_chrome()
    _build_leather()
    _build_mirror()
    _build_hair()
    _build_light()

func _build_room() -> void:
    var st := K.begin()
    # black and white checker floor, worn through in places
    for ix in range(8):
        for iz in range(7):
            if K.h(ix, iz, 3) < 0.12:
                continue
            var x0 := -1.2 + ix * 0.3
            var z0 := -1.0 + iz * (2.0 / 7.0)
            var z1 := z0 + 2.0 / 7.0
            var col := Color(0.78, 0.76, 0.7) if (ix + iz) % 2 == 0 else Color(0.1, 0.1, 0.1)
            col = col.darkened(K.h(ix, iz, 4) * 0.2)
            K.quad(st, Transform3D.IDENTITY, Vector3(x0, 0.004, z0), Vector3(x0, 0.004, z1), Vector3(x0 + 0.3, 0.004, z1), Vector3(x0 + 0.3, 0.004, z0), Vector3.UP, col)
    # mint counter under the mirror
    var mint := Color(0.55, 0.68, 0.6)
    K.rbox(st, K.T(Vector3(-0.2, 0.41, -0.8)), Vector3(0.62, 0.41, 0.2), 0.02, mint, mint.darkened(0.25))
    K.rbox(st, K.T(Vector3(-0.2, 0.84, -0.79)), Vector3(0.65, 0.025, 0.23), 0.012, Color(0.84, 0.82, 0.78), Color(0.6, 0.6, 0.6))
    for i in range(3):
        K.rbox(st, K.T(Vector3(-0.6 + i * 0.4, 0.6, -0.595)), Vector3(0.17, 0.12, 0.008), 0.006, mint.lightened(0.08), mint.darkened(0.3))
    # pictogram plate leaning on the mirror: scissors over hair
    var plate := K.T(Vector3(-0.5, 1.0, -0.93), Vector3(-10, 0, 0))
    K.rbox(st, plate, Vector3(0.15, 0.13, 0.01), 0.006, Color(0.88, 0.85, 0.74), Color(0.4, 0.38, 0.32))
    var steel := Color(0.25, 0.26, 0.28)
    for sx in [-1, 1]:
        # crossed blades
        K.quad(st, plate, Vector3(sx * 0.006, 0.03, 0.014), Vector3(sx * -0.08, 0.1, 0.014), Vector3(sx * -0.07, 0.11, 0.014), Vector3(sx * 0.016, 0.04, 0.014), Vector3.BACK, steel)
        # ring handles
        var ring: Array = []
        for k in range(9):
            var a := TAU * float(k) / 8.0
            ring.append(Vector3(sx * 0.04 + cos(a) * 0.022, -0.005 + sin(a) * 0.022, 0.014))
        K.tube(st, plate, ring, [0.005], 3, [steel], false)
        K.tube(st, plate, [Vector3(sx * 0.03, 0.013, 0.014), Vector3(sx * 0.006, 0.035, 0.014)], [0.005], 3, [steel], false)
    # cut hair under the blades, short tufts falling apart
    for k in range(9):
        var x := -0.09 + k * 0.0225
        var lean := (K.h(k, 91) - 0.5) * 0.03
        K.tube(st, plate, [Vector3(x, -0.115, 0.014), Vector3(x + lean, -0.065 - K.h(k, 92) * 0.02, 0.014)], [0.005, 0.002], 3, [HAIR_DARK], false)
    for k in range(4):
        K.tube(st, plate, [Vector3(-0.07 + k * 0.045, -0.045, 0.015), Vector3(-0.06 + k * 0.045, -0.035, 0.015)], [0.003], 3, [HAIR_DARK], false)
    # barber pole on the -X wall: chrome caps, striped glass cylinder
    var bp := Vector3(-1.08, 1.0, -0.35)
    K.rbox(st, K.T(bp + Vector3(-0.07, 0.38, 0)), Vector3(0.05, 0.03, 0.02), 0.008, Color(0.7, 0.72, 0.74))
    K.rbox(st, K.T(bp + Vector3(-0.07, 0.0, 0)), Vector3(0.05, 0.03, 0.02), 0.008, Color(0.7, 0.72, 0.74))
    _striped_cyl(st, bp + Vector3(0, 0.06, 0), 0.065, 0.66, 12, 16)
    var cap := Color(0.75, 0.77, 0.8)
    K.lathe(st, K.T(bp + Vector3(0, 0.72, 0)), [Vector2(0.075, 0.0), Vector2(0.075, 0.03), Vector2(0.05, 0.07), Vector2(0.0, 0.09)], 10, [cap])
    K.lathe(st, K.T(bp + Vector3(0, 0.06, 0), Vector3(180, 0, 0)), [Vector2(0.075, 0.0), Vector2(0.075, 0.03), Vector2(0.03, 0.06), Vector2(0.0, 0.065)], 10, [cap])
    K.add_mesh(self, "Room", K.finish(st, 3.0), K.mat("tex_tile_floor_128.png", 0.3, true))

## Helical red/white/blue stripes as per-facet vertex colours.
func _striped_cyl(st: SurfaceTool, base: Vector3, r: float, h: float, sides: int, bands: int) -> void:
    var cols := [Color(0.7, 0.08, 0.08), Color(0.86, 0.84, 0.8), Color(0.12, 0.2, 0.55), Color(0.86, 0.84, 0.8)]
    for i in range(bands):
        var y0 := base.y + h * float(i) / bands
        var y1 := base.y + h * float(i + 1) / bands
        for j in range(sides):
            var a0 := TAU * float(j) / sides
            var a1 := TAU * float(j + 1) / sides
            var d0 := Vector3(cos(a0), 0, sin(a0))
            var d1 := Vector3(cos(a1), 0, sin(a1))
            var c: Color = cols[int(float(j + i) / 3.0) % 4]
            var b0 := Vector3(base.x, 0, base.z)
            K.quad(st, Transform3D.IDENTITY, b0 + d0 * r + Vector3(0, y0, 0), b0 + d0 * r + Vector3(0, y1, 0), b0 + d1 * r + Vector3(0, y1, 0), b0 + d1 * r + Vector3(0, y0, 0), (d0 + d1) * 0.5, c)

func _build_chrome() -> void:
    var st := K.begin()
    var chrome := Color(0.8, 0.82, 0.85)
    var c := K.T(CHAIR_POS, Vector3(0, CHAIR_YAW, 0))
    # heavy round foot and hydraulic column
    K.lathe(st, c, [Vector2(0.0, 0.0), Vector2(0.31, 0.0), Vector2(0.31, 0.03), Vector2(0.26, 0.055), Vector2(0.11, 0.07), Vector2(0.0, 0.075)], 14, [chrome.darkened(0.4), chrome, chrome, chrome])
    K.lathe(st, c * K.T(Vector3(0, 0.07, 0)), [Vector2(0.1, 0.0), Vector2(0.095, 0.2), Vector2(0.075, 0.23), Vector2(0.075, 0.36), Vector2(0.15, 0.4)], 12, [chrome, chrome.darkened(0.15), chrome, chrome.darkened(0.2)])
    # pump pedal
    K.tube(st, c, [Vector3(0.08, 0.12, 0.05), Vector3(0.28, 0.08, 0.12)], [0.014], 5, [chrome.darkened(0.2)])
    K.rbox(st, c * K.T(Vector3(0.31, 0.075, 0.13), Vector3(0, -20, 0)), Vector3(0.06, 0.012, 0.035), 0.006, Color(0.15, 0.15, 0.15))
    # seat pan frame
    K.rbox(st, c * K.T(Vector3(0, 0.49, 0)), Vector3(0.25, 0.035, 0.25), 0.012, chrome.darkened(0.1))
    # arm frames
    for sx in [-1, 1]:
        K.tube(st, c, [Vector3(sx * 0.29, 0.5, 0.2), Vector3(sx * 0.3, 0.72, 0.16), Vector3(sx * 0.3, 0.73, -0.2), Vector3(sx * 0.29, 0.52, -0.25)], [0.016], 6, [chrome])
    # headrest stalk
    K.tube(st, c, [Vector3(0, 1.13, 0.36), Vector3(0, 1.3, 0.39)], [0.018], 6, [chrome])
    # footrest bracket and ribbed plate
    K.tube(st, c, [Vector3(0, 0.47, -0.24), Vector3(0, 0.3, -0.36), Vector3(0, 0.16, -0.46)], [0.02], 6, [chrome])
    K.rbox(st, c * K.T(Vector3(0, 0.15, -0.5), Vector3(-8, 0, 0)), Vector3(0.2, 0.012, 0.08), 0.006, chrome.darkened(0.1))
    for i in range(4):
        K.rbox(st, c * K.T(Vector3(0, 0.165, -0.56 + i * 0.04), Vector3(-8, 0, 0)), Vector3(0.18, 0.004, 0.006), 0.002, Color(0.2, 0.2, 0.2))
    # jar of combs on the counter
    var jar := K.T(Vector3(0.22, 0.865, -0.8))
    K.lathe(st, jar, [Vector2(0.0, 0.0), Vector2(0.065, 0.0), Vector2(0.065, 0.2), Vector2(0.058, 0.215)], 10, [Color(0.1, 0.32, 0.3), Color(0.15, 0.45, 0.42), Color(0.12, 0.4, 0.38)])
    K.lathe(st, jar * K.T(Vector3(0, 0.205, 0)), [Vector2(0.07, 0.0), Vector2(0.07, 0.02), Vector2(0.0, 0.025)], 10, [chrome])
    for i in range(4):
        var lean := Vector3((K.h(i, 11) - 0.5) * 20.0, i * 40.0, (K.h(i, 12) - 0.5) * 24.0)
        K.rbox(st, jar * K.T(Vector3(-0.025 + i * 0.016, 0.24, (K.h(i, 13) - 0.5) * 0.04), lean), Vector3(0.004, 0.09, 0.022), 0.002, Color(0.07, 0.07, 0.08) if i % 2 == 0 else Color(0.35, 0.22, 0.12))
    # mirror frame and bulb bracket
    K.rbox(st, K.T(Vector3(-0.2, 1.4, -0.985)), Vector3(0.56, 0.4, 0.015), 0.01, chrome.darkened(0.15))
    K.tube(st, Transform3D.IDENTITY, [Vector3(-0.2, 1.93, -0.99), Vector3(-0.2, 1.95, -0.84), Vector3(-0.2, 1.9, -0.8)], [0.012], 5, [chrome.darkened(0.2)])
    K.lathe(st, K.T(Vector3(-0.2, 1.86, -0.8)), [Vector2(0.03, 0.0), Vector2(0.03, 0.04), Vector2(0.0, 0.045)], 8, [Color(0.6, 0.55, 0.4)])
    K.add_mesh(self, "Chrome", K.finish(st, 4.0), K.mat("tex_chrome_128.png", 0.6, true))

func _build_leather() -> void:
    var st := K.begin()
    var red := Color(0.58, 0.08, 0.08)
    var red_edge := Color(0.38, 0.05, 0.06)
    var crack := Color(0.12, 0.03, 0.03)
    var foam := Color(0.78, 0.68, 0.42)
    var c := K.T(CHAIR_POS, Vector3(0, CHAIR_YAW, 0))
    K.rbox(st, c * K.T(Vector3(0, 0.59, -0.01)), Vector3(0.26, 0.065, 0.27), 0.045, red, red_edge)
    var back := c * K.T(Vector3(0, 0.9, 0.27), Vector3(12, 0, 0))
    K.rbox(st, back, Vector3(0.25, 0.3, 0.06), 0.04, red, red_edge)
    K.rbox(st, c * K.T(Vector3(0, 1.36, 0.4), Vector3(12, 0, 0)), Vector3(0.13, 0.06, 0.05), 0.03, red, red_edge)
    for sx in [-1, 1]:
        K.rbox(st, c * K.T(Vector3(sx * 0.3, 0.765, -0.02)), Vector3(0.045, 0.025, 0.2), 0.018, red, red_edge)
    # cracks across the seat and back, a split showing yellow foam
    for i in range(5):
        var yaw := (K.h(i, 21) - 0.5) * 120.0
        K.rbox(st, c * K.T(Vector3((K.h(i, 22) - 0.5) * 0.36, 0.656, (K.h(i, 23) - 0.5) * 0.36), Vector3(0, yaw, 0)), Vector3(0.06 + K.h(i, 24) * 0.05, 0.003, 0.004), 0.001, crack)
    for i in range(3):
        K.rbox(st, back * K.T(Vector3((K.h(i, 25) - 0.5) * 0.3, (K.h(i, 26) - 0.5) * 0.4, -0.061), Vector3(0, 0, (K.h(i, 27) - 0.5) * 140.0)), Vector3(0.07, 0.004, 0.003), 0.001, crack)
    K.rbox(st, c * K.T(Vector3(0.08, 0.656, -0.12), Vector3(0, 25, 0)), Vector3(0.07, 0.004, 0.025), 0.002, foam)
    K.add_mesh(self, "Leather", K.finish(st, 3.0), K.mat("tex_door_paint_128.png", 0.5, true))

func _build_mirror() -> void:
    # dark glossy panel only: it reflects nothing
    var st := K.begin()
    K.rbox(st, K.T(Vector3(-0.2, 1.4, -0.968)), Vector3(0.5, 0.35, 0.006), 0.003, Color(0.04, 0.05, 0.06), Color(0.1, 0.11, 0.12))
    K.add_mesh(self, "Mirror", K.finish(st, 2.0), K.mat("tex_chrome_128.png", 1.0, true))

func _build_hair() -> void:
    var st := K.begin()
    var masses := [
        [Vector3(1.2, 2.2, -1.0), 0.34], [Vector3(-1.2, 2.2, -1.0), 0.32], [Vector3(-1.2, 2.2, 1.0), 0.28],
        [Vector3(1.2, 2.0, 1.0), 0.28], [Vector3(0.45, 2.2, -1.0), 0.26], [Vector3(1.2, 0.9, -0.6), 0.3],
        [Vector3(-0.75, 2.2, 0.45), 0.26], [Vector3(-1.2, 0.4, 0.55), 0.26],
    ]
    for i in range(masses.size()):
        var r: float = masses[i][1]
        _hair_mass(st, _fit(masses[i][0], r * 1.6), r, i, 8)
    # cut hair heaped on the floor round the chair and swept into a corner
    var shades := [HAIR_DARK, HAIR_BROWN, Color(0.42, 0.3, 0.18), Color(0.5, 0.48, 0.45)]
    var heaps := [
        [CHAIR_POS + Vector3(-0.32, 0.03, 0.2), Vector3(0.2, 0.04, 0.16)],
        [CHAIR_POS + Vector3(0.28, 0.03, -0.3), Vector3(0.16, 0.035, 0.14)],
        [Vector3(0.9, 0.06, -0.75), Vector3(0.24, 0.09, 0.2)],
        [Vector3(-0.75, 0.04, 0.35), Vector3(0.17, 0.05, 0.15)],
    ]
    for i in range(heaps.size()):
        var hp: Vector3 = heaps[i][0]
        var hr: Vector3 = heaps[i][1]
        K.blob(st, Transform3D.IDENTITY, hp, hr, 0.45, 800 + i, shades[i % 4], shades[(i + 1) % 4])
        for j in range(7):
            var a := K.h(i, j, 1) * TAU
            var p := hp + Vector3(cos(a), 0, sin(a)) * hr.x * (0.6 + K.h(i, j, 2) * 0.6)
            p.y = 0.012
            var d := Vector3(cos(a + 1.3), 0.0, sin(a + 1.3)) * (0.05 + K.h(i, j, 3) * 0.06)
            K.tube(st, Transform3D.IDENTITY, [p, p + d], [0.006, 0.003], 3, [shades[j % 4]], false)
    K.add_mesh(self, "Hair", K.finish(st, 3.0), K.mat("tex_flesh_128.png", 0.3, true))

## A matted hair mass: dark lumps over a pink scalp patch, locks hanging.
func _hair_mass(st: SurfaceTool, gp: Vector3, r: float, seed: int, strands: int) -> void:
    var inward := Vector3(-gp.x, 0.0, -gp.z)
    inward = inward.normalized() if inward.length() > 0.05 else Vector3.BACK
    var tang := inward.cross(Vector3.UP)
    K.blob(st, Transform3D.IDENTITY, gp, Vector3(r, r * 0.75, r), 0.4, 900 + seed, HAIR_DARK, HAIR_BROWN)
    for j in range(3):
        var off := Vector3(K.h(seed, j, 31) - 0.5, (K.h(seed, j, 32) - 0.5) * 0.6, K.h(seed, j, 33) - 0.5).normalized() * r * 0.7
        var sr := r * (0.4 + K.h(seed, j, 34) * 0.25)
        K.blob(st, Transform3D.IDENTITY, gp + off, Vector3(sr, sr * 0.8, sr), 0.45, 920 + seed * 5 + j, HAIR_BROWN, HAIR_DARK)
    var sp := gp + inward * r * 0.55 + tang * r * 0.35 + Vector3(0, r * 0.25, 0)
    K.blob(st, Transform3D.IDENTITY, sp, Vector3(r * 0.42, r * 0.3, r * 0.42), 0.3, 960 + seed, SCALP, SCALP.darkened(0.2))
    for j in range(strands):
        var root := gp + inward * r * (0.3 + K.h(seed, j, 41) * 0.5) + tang * (K.h(seed, j, 42) - 0.5) * r * 1.5 + Vector3(0, -r * 0.45, 0)
        _strand(st, root, 0.2 + K.h(seed, j, 43) * 0.45, seed * 37 + j)

func _strand(st: SurfaceTool, root: Vector3, length: float, seed: int) -> void:
    var drop := minf(length, root.y - 0.03)
    if drop < 0.08:
        return
    var pts: Array = []
    var sway := Vector3(K.h(seed, 1) - 0.5, 0, K.h(seed, 2) - 0.5) * 0.12
    for k in range(4):
        var t := float(k) / 3.0
        pts.append(root + sway * t * t + Vector3(sin(t * 3.0 + seed) * 0.02, -drop * t, 0))
    var col := HAIR_DARK if K.h(seed, 3) < 0.6 else HAIR_BROWN
    K.tube(st, Transform3D.IDENTITY, pts, [0.02, 0.014, 0.008, 0.003], 3, [col], false, 0.35)

func _build_light() -> void:
    var st := K.begin()
    K.lathe(st, K.T(Vector3(-0.2, 1.86, -0.8), Vector3(180, 0, 0)), [Vector2(0.03, 0.0), Vector2(0.045, 0.03), Vector2(0.04, 0.07), Vector2(0.0, 0.09)], 8, [Color(1.0, 0.9, 0.7)])
    _bulb = K.add_mesh(self, "Bulb", K.finish(st), K.glow(Color(1.0, 0.88, 0.7)))
    _lamp = OmniLight3D.new()
    _lamp.position = Vector3(-0.2, 1.7, -0.7)
    _lamp.omni_range = 2.5
    _lamp.light_color = Color(1.0, 0.85, 0.65)
    _lamp.light_energy = 0.6
    _lamp.light_cull_mask = 0xFFFFF & ~FPRestroom.ROOM_VISUAL_LAYER & ~FPMirrorReflection.HANDS_ROOM_LAYER & ~FPMirrorReflection.MIRROR_BODY_LAYER & ~FPMirror.HOLO_LAYER
    add_child(_lamp)

func _fit(p: Vector3, margin: float) -> Vector3:
    var lo := Vector3(-POCKET_HALF.x - 0.3, -0.3, -POCKET_HALF.z - 0.3) + Vector3.ONE * margin
    var hi := Vector3(POCKET_HALF.x + 0.3, POCKET_HALF.y * 2.0 + 0.3, POCKET_HALF.z + 0.3) - Vector3.ONE * margin
    return p.clamp(lo, hi)

func set_light(on: bool) -> void:
    _bulb.visible = on
    _lamp.visible = on
