extends Node3D

## Forearm with arm hairs (mutation points). Origin = elbow; the forearm
## runs toward -Z to the wrist (the same direction the first-person hands
## point), top of the arm is +Y. Hairs sprout on the top/outer skin, one
## strand per point, coloured by kind: common (black) and one colour per
## biome tissue. Spent hairs fall out: set_hair() simply shows fewer.
## Public: set_hair(common:int, biome:Dictionary{core,mantle,surface}),
## drop_hairs(n) (plays a short fall), hair_total().

const K := preload("res://main/art/fp_art_kit.gd")
const LEN := 0.26
const MAX_SLOTS := 90
const SHAGGY_AT := 40
const COLORS := {
    "common": Color(0.05, 0.035, 0.03),
    "core": Color(0.93, 0.33, 0.55),     # compressive tissue: deep pink (spec 02)
    "mantle": Color(0.36, 0.12, 0.46),   # contractile tissue: bruise purple
    "surface": Color(0.86, 0.76, 0.12),  # nerve tissue: bile/nerve yellow
}

var _hair_mi: MeshInstance3D
var _slots: Array = []
var _counts := {"common": 0, "core": 0, "mantle": 0, "surface": 0}

func _ready() -> void:
    var st := K.begin()
    var skin := Color(0.86, 0.7, 0.6)
    var under := Color(0.9, 0.74, 0.66)
    var pts: Array = []
    var radii: Array = []
    for i in range(7):
        var t := float(i) / 6.0
        pts.append(Vector3(0, sin(t * PI) * 0.006, -LEN * t))
        radii.append(lerpf(0.042, 0.028, t) + sin(t * PI) * 0.004)
    K.tube(st, Transform3D.IDENTITY, pts, radii, 9, [skin, skin, under], true, 1.2)
    # no wrist knob here: the rig's own palm starts at the wrist, and a
    # fixed blob there stuck out as a dark lump whenever the wrist bent
    K.add_mesh(self, "Forearm", K.finish(st, 6.0), K.mat("tex_skin_128.png", 0.3, false))
    for i in range(MAX_SLOTS):
        var along := 0.03 + K.h(i, 11) * (LEN - 0.04)
        var ang := lerpf(-1.1, 1.3, K.h(i, 12))  # around the top / outer side
        var t := along / LEN
        var r := lerpf(0.042, 0.028, t) * 1.0
        var base := Vector3(sin(ang) * r * 1.2, cos(ang) * r, -along)
        var normal := Vector3(sin(ang) * 1.2, cos(ang), 0).normalized()
        _slots.append([base, normal, K.h(i, 13)])
    _hair_mi = K.add_mesh(self, "Hairs", ArrayMesh.new(), K.mat("tex_nerve_64.png", 0.2, false))
    set_hair(6, {"core": 3, "mantle": 2, "surface": 2})

func set_hair(common: int, biome: Dictionary) -> void:
    _counts = {"common": maxi(common, 0), "core": int(biome.get("core", 0)), "mantle": int(biome.get("mantle", 0)), "surface": int(biome.get("surface", 0))}
    _rebuild()

func hair_total() -> int:
    var n := 0
    for k in _counts:
        n += int(_counts[k])
    return mini(n, MAX_SLOTS)

func _rebuild() -> void:
    var st := K.begin()
    var slot := 0
    var any := false
    # spec 04 §2: past 40 strands the arm reads as a shaggy tuft
    var shaggy := hair_total() > SHAGGY_AT
    for kind in ["common", "core", "mantle", "surface"]:
        for n in range(int(_counts[kind])):
            if slot >= MAX_SLOTS:
                break
            var s: Array = _slots[slot]
            var base: Vector3 = s[0]
            var nrm: Vector3 = s[1]
            var length := (0.02 + float(s[2]) * 0.014) * (1.7 if shaggy else 1.0)
            # hairs lie back toward the elbow (+Z) and curl a little
            var lean := Vector3(0, 0, 1)
            var p1 := base + nrm * length * 0.45 + lean * length * 0.35
            var p2 := base + nrm * length * 0.6 + lean * length * 0.9 + Vector3(0.004 * (float(s[2]) - 0.5), 0, 0)
            K.tube(st, Transform3D.IDENTITY, [base - nrm * 0.001, p1, p2], [0.0032 if shaggy else 0.0028, 0.0022, 0.0009], 3, [COLORS[kind]], false)
            slot += 1
            any = true
    _hair_mi.mesh = K.finish(st, 40.0) if any else ArrayMesh.new()

func drop_hairs(n: int) -> void:
    for k in ["surface", "mantle", "core", "common"]:
        while n > 0 and int(_counts[k]) > 0:
            _counts[k] = int(_counts[k]) - 1
            n -= 1
    _rebuild()

func capture_setup() -> Dictionary:
    set_hair(14, {"core": 8, "mantle": 7, "surface": 8})
    return {"cam_pos": Vector3(0.2, 0.17, -0.02), "look_at": Vector3(0, 0.0, -0.14), "env": "restroom", "fov": 50.0}