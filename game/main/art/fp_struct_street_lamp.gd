extends Node3D

## Biome structure: a 1960s cast-iron sodium street lamp swallowed into the
## hair thicket of the surface shell. A fluted cast base stands on a broken
## slab of pavement and kerb; across the kerb lie cracked asphalt chunks with
## a round manhole cover. Its job was lighting a street corner orange all
## night; the flesh pushed the pole until it bent over, and the lamp head still
## glows sodium orange. Matted dark hair grows over everything from pink scalp
## patches and hangs off the pole and lamp head in locks.
## Warning plate strapped to the pole: a circle of hair with an arrow closing
## it (hair closes fast behind you).
## Origin = pocket floor centre, mouth on +Z. Public: set_light(on), pocket_half().

const K := preload("res://main/art/fp_art_kit.gd")
const POCKET_HALF := Vector3(1.0, 1.6, 1.0)
const BASE := Vector3(-0.5, 0.09, -0.62)
const HAIR_DARK := Color(0.08, 0.06, 0.05)
const HAIR_BROWN := Color(0.2, 0.14, 0.11)
const SCALP := Color(0.66, 0.36, 0.36)
var _lens: MeshInstance3D
var _lamp: OmniLight3D
var _pole_pts: Array = []
var _head: Transform3D

func pocket_half() -> Vector3:
    return POCKET_HALF

func _ready() -> void:
    for p in [Vector3(0, 0, 0), Vector3(0, 0.6, 0), Vector3(0, 1.4, 0), Vector3(0, 2.05, 0.0), Vector3(0.06, 2.45, 0.06), Vector3(0.22, 2.74, 0.2), Vector3(0.46, 2.86, 0.42), Vector3(0.68, 2.8, 0.6)]:
        _pole_pts.append(BASE + p)
    var end: Vector3 = _pole_pts[_pole_pts.size() - 1]
    _head = K.T(end, Vector3(28, 48, 0))
    _build_ground()
    _build_lamp()
    _build_hair()

func _build_ground() -> void:
    var st := K.begin()
    var concrete := Color(0.42, 0.41, 0.39)
    var kerb := Color(0.55, 0.54, 0.5)
    var asphalt := Color(0.16, 0.16, 0.17)
    # broken pavement slab the base stands on, and the kerb stone
    K.rbox(st, K.T(Vector3(-0.05, 0.03, -0.62), Vector3(2, 0, -2)), Vector3(0.95, 0.06, 0.36), 0.02, concrete, concrete.darkened(0.2))
    K.rbox(st, K.T(Vector3(0.62, 0.02, -0.66), Vector3(-4, 8, 5)), Vector3(0.32, 0.05, 0.3), 0.02, concrete.darkened(0.08), concrete.darkened(0.25))
    K.rbox(st, K.T(Vector3(-0.1, 0.07, -0.2), Vector3(0, 0, -2)), Vector3(0.85, 0.1, 0.075), 0.02, kerb, kerb.darkened(0.2))
    K.rbox(st, K.T(Vector3(0.84, 0.03, -0.17), Vector3(0, 14, 9)), Vector3(0.16, 0.09, 0.07), 0.02, kerb.darkened(0.1), kerb.darkened(0.3))
    # cracked asphalt chunks across the kerb with a gap of flesh between
    var a1 := K.T(Vector3(-0.45, 0.0, 0.4), Vector3(2, 4, -3))
    var a2 := K.T(Vector3(0.52, -0.01, 0.42), Vector3(-3, -6, 4))
    K.rbox(st, a1, Vector3(0.5, 0.04, 0.5), 0.015, asphalt, asphalt.darkened(0.3))
    K.rbox(st, a2, Vector3(0.42, 0.04, 0.5), 0.015, asphalt.lightened(0.05), asphalt.darkened(0.3))
    # faded yellow road line on the first chunk
    K.quad(st, a1, Vector3(-0.45, 0.041, 0.3), Vector3(-0.45, 0.041, 0.36), Vector3(0.45, 0.041, 0.36), Vector3(0.45, 0.041, 0.3), Vector3.UP, Color(0.62, 0.52, 0.18))
    # round manhole cover set in the second chunk
    var mh := a2 * K.T(Vector3(-0.02, 0.04, -0.02))
    var iron := Color(0.13, 0.12, 0.11)
    K.lathe(st, mh, [Vector2(0.31, -0.005), Vector2(0.31, 0.008), Vector2(0.28, 0.014), Vector2(0.27, 0.012), Vector2(0.0, 0.016)], 14, [iron.darkened(0.3), iron.lightened(0.1), iron.darkened(0.3), iron])
    for i in range(5):
        var z := -0.18 + i * 0.09
        var hw := sqrt(maxf(0.25 * 0.25 - z * z, 0.0))
        K.rbox(st, mh * K.T(Vector3(0, 0.02, z)), Vector3(hw, 0.006, 0.012), 0.004, Color(0.24, 0.2, 0.16))
    K.add_mesh(self, "Ground", K.finish(st, 3.0), K.mat("tex_tile_floor_128.png", 0.25, true))

func _build_lamp() -> void:
    var st := K.begin()
    var cast := Color(0.17, 0.21, 0.19)
    var cast_hi := Color(0.26, 0.3, 0.27)
    var rust := Color(0.38, 0.22, 0.12)
    # fluted cast base: bell lathe + vertical flute ribs + collar
    K.lathe(st, K.T(BASE), [Vector2(0.21, 0.0), Vector2(0.21, 0.08), Vector2(0.17, 0.12), Vector2(0.135, 0.18), Vector2(0.12, 0.46), Vector2(0.095, 0.54), Vector2(0.07, 0.6), Vector2(0.0, 0.62)], 12, [cast_hi, cast, cast, cast, cast_hi, cast, cast])
    for i in range(12):
        var a := TAU * (float(i) + 0.5) / 12.0
        var d := Vector3(cos(a), 0, sin(a))
        K.tube(st, Transform3D.IDENTITY, [BASE + d * 0.14 + Vector3(0, 0.17, 0), BASE + d * 0.125 + Vector3(0, 0.46, 0)], [0.014], 3, [cast_hi.lerp(rust, K.h(i, 5) * 0.6)])
    K.lathe(st, K.T(BASE + Vector3(0, 0.6, 0)), [Vector2(0.09, 0.0), Vector2(0.09, 0.04), Vector2(0.0, 0.05)], 10, [cast_hi])
    # the pole, bent over by the flesh near the top
    var radii := [0.07, 0.065, 0.058, 0.054, 0.05, 0.048, 0.046, 0.045]
    K.tube(st, Transform3D.IDENTITY, _pole_pts, radii, 8, [cast, cast, cast.lerp(rust, 0.3), cast, cast.lerp(rust, 0.5), cast, cast])
    # crease rings where it buckled
    for k in [4, 5]:
        var along := (_pole_pts[k + 1] as Vector3) - (_pole_pts[k - 1] as Vector3)
        K.lathe(st, Transform3D(Basis.looking_at(along) * Basis.from_euler(Vector3(-PI * 0.5, 0, 0)), _pole_pts[k]),[Vector2(0.06, -0.015), Vector2(0.06, 0.015)], 8, [rust])
    # lamp head: a cast hood over a sodium bowl
    var hood := cast.lightened(0.05)
    K.rbox(st, _head * K.T(Vector3(0, 0.02, 0.2)), Vector3(0.13, 0.06, 0.24), 0.04, hood, cast_hi)
    K.rbox(st, _head * K.T(Vector3(0, 0.085, 0.16)), Vector3(0.05, 0.02, 0.16), 0.015, cast_hi)
    K.rbox(st, _head * K.T(Vector3(0, -0.035, 0.2)), Vector3(0.135, 0.012, 0.245), 0.006, Color(0.5, 0.5, 0.5))
    # pictogram plate strapped to the pole
    _build_plate(st)
    K.add_mesh(self, "Lamp", K.finish(st, 4.0), K.mat("tex_door_paint_128.png", 0.3, true))
    # glowing orange lens under the hood
    st = K.begin()
    K.lathe(st, _head * K.T(Vector3(0, -0.04, 0.2), Vector3(180, 0, 0), Vector3(1.0, 1.0, 1.9)), [Vector2(0.11, 0.0), Vector2(0.1, 0.035), Vector2(0.065, 0.065), Vector2(0.0, 0.078)], 10, [Color(1.0, 0.62, 0.3), Color(1.0, 0.7, 0.4), Color(1.0, 0.82, 0.55)])
    _lens = K.add_mesh(self, "Lens", K.finish(st), K.glow(Color(1.0, 0.6, 0.25)))
    _lamp = OmniLight3D.new()
    _lamp.position = _head * Vector3(0, -0.2, 0.2)
    _lamp.omni_range = 3.5
    _lamp.light_color = Color(1.0, 0.62, 0.3)
    _lamp.light_energy = 1.0
    _lamp.light_cull_mask = 0xFFFFF & ~FPRestroom.ROOM_VISUAL_LAYER & ~FPMirrorReflection.HANDS_ROOM_LAYER & ~FPMirrorReflection.MIRROR_BODY_LAYER & ~FPMirror.HOLO_LAYER
    add_child(_lamp)

## Hair warning plate: a ring of hair with a red arrow closing its gap.
func _build_plate(st: SurfaceTool) -> void:
    var py := 1.45
    var pole := BASE + Vector3(0, py - BASE.y, 0)
    var plate := K.T(pole + Vector3(0, 0, 0.085))
    K.rbox(st, plate, Vector3(0.17, 0.17, 0.01), 0.006, Color(0.82, 0.7, 0.22), Color(0.3, 0.26, 0.12))
    # two straps around pole + plate
    for sy in [-1, 1]:
        var y: float = sy * 0.12
        K.lathe(st, K.T(pole + Vector3(0, y - 0.012, 0)), [Vector2(0.078, 0.0), Vector2(0.078, 0.024)], 8, [Color(0.35, 0.35, 0.36)])
        K.rbox(st, plate * K.T(Vector3(0, y, 0.012)), Vector3(0.18, 0.012, 0.003), 0.002, Color(0.35, 0.35, 0.36))
    var ink := HAIR_DARK
    var red := Color(0.62, 0.1, 0.08)
    var arc: Array = []
    for k in range(11):
        var a := deg_to_rad(120.0 + 270.0 * float(k) / 10.0)
        arc.append(Vector3(cos(a) * 0.095, sin(a) * 0.095, 0.014))
    K.tube(st, plate, arc, [0.012], 4, [ink])
    # hair tufts bristling outward round the ring
    for k in range(arc.size()):
        var p: Vector3 = arc[k]
        var out := Vector3(p.x, p.y, 0).normalized()
        K.tube(st, plate, [p, p + out * 0.035 + Vector3(0.01 * sin(k * 2.0), 0, 0)], [0.005, 0.002], 3, [ink], false)
    # red arrow sweeping across the gap to close it
    var gap: Array = []
    for k in range(5):
        var a := deg_to_rad(30.0 + 85.0 * float(k) / 4.0)
        gap.append(Vector3(cos(a) * 0.095, sin(a) * 0.095, 0.017))
    K.tube(st, plate, gap, [0.008], 4, [red])
    var tip: Vector3 = gap[gap.size() - 1]
    var fwd := (tip - (gap[gap.size() - 2] as Vector3)).normalized()
    var side := Vector3(-fwd.y, fwd.x, 0)
    K.tri(st, plate, tip + fwd * 0.04, tip + side * 0.028, tip - side * 0.028, Vector3.BACK, red)

func _build_hair() -> void:
    var st := K.begin()
    var masses := [
        [Vector3(1.0, 3.2, -1.0), 0.36], [Vector3(-1.0, 3.2, -1.0), 0.34], [Vector3(-1.0, 3.2, 1.0), 0.3],
        [Vector3(1.0, 3.0, 1.0), 0.3], [Vector3(-1.0, 1.6, -1.0), 0.32], [Vector3(1.0, 1.2, -0.7), 0.3],
        [Vector3(0.2, 3.2, -0.3), 0.3], [Vector3(-1.0, 0.3, 0.6), 0.26],
    ]
    for i in range(masses.size()):
        var r: float = masses[i][1]
        _hair_mass(st, _fit(masses[i][0], r * 1.6), r, i, 9)
    # hair grown onto the bend of the pole and over the lamp head
    _hair_mass(st, _pole_pts[5], 0.17, 20, 8)
    _hair_mass(st, _head * Vector3(0.02, 0.1, 0.12), 0.16, 21, 9)
    _hair_mass(st, BASE + Vector3(0.02, 2.0, 0.0), 0.12, 22, 6)
    # locks draped over the arm, hanging straight down
    for i in range(10):
        var t := 0.15 + 0.85 * float(i) / 9.0
        var k := 4 + int(t * 2.99)
        var p := (_pole_pts[k] as Vector3).lerp(_pole_pts[k + 1], t * 3.0 - floorf(t * 3.0))
        _strand(st, p + Vector3(0, -0.03, 0), 0.4 + K.h(i, 81) * 0.7, 30 + i)
    K.add_mesh(self, "Hair", K.finish(st, 3.0), K.mat("tex_flesh_128.png", 0.3, true))

## A matted hair mass: dark lumps over a pink scalp patch, locks hanging.
func _hair_mass(st: SurfaceTool, gp: Vector3, r: float, seed: int, strands: int) -> void:
    var inward := Vector3(-gp.x, 0.0, -gp.z)
    inward = inward.normalized() if inward.length() > 0.05 else Vector3.BACK
    var tang := inward.cross(Vector3.UP)
    K.blob(st, Transform3D.IDENTITY, gp, Vector3(r, r * 0.75, r), 0.4, 700 + seed, HAIR_DARK, HAIR_BROWN)
    for j in range(3):
        var off := Vector3(K.h(seed, j, 31) - 0.5, (K.h(seed, j, 32) - 0.5) * 0.6, K.h(seed, j, 33) - 0.5).normalized() * r * 0.7
        var sr := r * (0.4 + K.h(seed, j, 34) * 0.25)
        K.blob(st, Transform3D.IDENTITY, gp + off, Vector3(sr, sr * 0.8, sr), 0.45, 720 + seed * 5 + j, HAIR_BROWN, HAIR_DARK)
    # pink scalp showing at the root where the hair parts
    var sp := gp + inward * r * 0.55 + tang * r * 0.35 + Vector3(0, r * 0.25, 0)
    K.blob(st, Transform3D.IDENTITY, sp, Vector3(r * 0.42, r * 0.3, r * 0.42), 0.3, 760 + seed, SCALP, SCALP.darkened(0.2))
    for j in range(strands):
        var root := gp + inward * r * (0.3 + K.h(seed, j, 41) * 0.5) + tang * (K.h(seed, j, 42) - 0.5) * r * 1.5 + Vector3(0, -r * 0.45, 0)
        _strand(st, root, 0.25 + K.h(seed, j, 43) * 0.75, seed * 31 + j)

## One lock of hair hanging from `root` (flattened 3-sided ribbon).
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

func _fit(p: Vector3, margin: float) -> Vector3:
    var lo := Vector3(-POCKET_HALF.x - 0.3, -0.3, -POCKET_HALF.z - 0.3) + Vector3.ONE * margin
    var hi := Vector3(POCKET_HALF.x + 0.3, POCKET_HALF.y * 2.0 + 0.3, POCKET_HALF.z + 0.3) - Vector3.ONE * margin
    return p.clamp(lo, hi)

func set_light(on: bool) -> void:
    _lens.visible = on
    _lamp.visible = on
