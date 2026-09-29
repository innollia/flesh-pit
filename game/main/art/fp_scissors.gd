extends Node3D

## Big tailor's scissors (one-handed cutting tool). Origin = pivot screw;
## blades point -Z, the two halves rotate about Y.
## Public: set_open(0..1), play_snip().

const K := preload("res://main/art/fp_art_kit.gd")
var _a: Node3D
var _b: Node3D

func _ready() -> void:
    _a = K.pivot(self, "HalfA")
    _b = K.pivot(self, "HalfB")
    _b.position.y = -0.005
    _half(_a, 1.0)
    _half(_b, -1.0)
    var st := K.begin()
    K.lathe(st, K.T(Vector3(0, 0.004, 0)), [Vector2(0.0, -0.012), Vector2(0.007, -0.012), Vector2(0.008, 0.0), Vector2(0.0, 0.002)], 8, [Color(0.6, 0.6, 0.62)])
    K.add_mesh(self, "Screw", K.finish(st), K.mat("tex_chrome_64.png", 0.4, false))
    set_open(0.35)

func _half(parent: Node3D, s: float) -> void:
    var st := K.begin()
    var steel := Color(0.8, 0.82, 0.85)
    var edge := Color(0.95, 0.96, 0.98)
    var handle := Color(0.55, 0.1, 0.08)
    # blade: long tapered wedge along -Z on one side of the pivot line
    var pts := [Vector3(s * 0.004, 0, 0.01), Vector3(s * 0.006, 0, -0.04), Vector3(s * 0.005, 0, -0.1), Vector3(s * 0.001, 0, -0.15)]
    K.tube(st, Transform3D.IDENTITY, pts, [0.009, 0.008, 0.005, 0.0015], 4, [steel, steel, edge], true, 1.0)
    # handle loop behind the pivot (+Z), bent outward to side s
    var loop: Array = []
    for i in range(9):
        var a := TAU * i / 8.0
        loop.append(Vector3(-s * 0.03 + cos(a) * 0.022 * s, 0, 0.06 + sin(a) * 0.028))
    K.tube(st, Transform3D.IDENTITY, loop, [0.006], 6, [handle], false)
    K.tube(st, Transform3D.IDENTITY, [Vector3(0, 0, 0.005), Vector3(-s * 0.012, 0, 0.03), Vector3(-s * 0.01, 0, 0.034)], [0.006, 0.006, 0.006], 6, [steel])
    K.add_mesh(parent, "Half", K.finish(st, 10.0), K.mat("tex_chrome_128.png", 0.45, false))

func set_open(t: float) -> void:
    var a := 28.0 * clampf(t, 0.0, 1.0)
    _a.rotation_degrees.y = a * 0.5
    _b.rotation_degrees.y = -a * 0.5

func play_snip() -> void:
    var tw := create_tween()
    tw.tween_method(set_open, 1.0, 0.0, 0.12)
    tw.tween_method(set_open, 0.0, 0.8, 0.25)

func capture_setup() -> Dictionary:
    set_open(0.7)
    return {"cam_pos": Vector3(0.05, 0.28, 0.02), "look_at": Vector3(0, 0, -0.03), "env": "dark", "fov": 50.0}