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
    # flat blade plate: inner sharpened edge on the pivot line, curved spine
    # on side s, tapering to a point (reads as a blade, not a rod)
    var n := 8
    var hy := 0.0014
    for i in range(n):
        var t0 := float(i) / n
        var t1 := float(i + 1) / n
        var z0 := lerpf(0.012, -0.16, t0)
        var z1 := lerpf(0.012, -0.16, t1)
        var w0 := 0.017 * (1.0 - pow(t0, 1.4)) + 0.0008
        var w1 := 0.017 * (1.0 - pow(t1, 1.4)) + 0.0008
        var ex0 := -s * 0.0015
        var ex1 := -s * 0.0015
        K.quad(st, Transform3D.IDENTITY, Vector3(s * 0.004, hy, z0), Vector3(s * 0.004, hy, z1), Vector3(s * w1, hy, z1), Vector3(s * w0, hy, z0), Vector3.UP, steel)
        K.quad(st, Transform3D.IDENTITY, Vector3(s * 0.004, -hy, z0), Vector3(s * 0.004, -hy, z1), Vector3(s * w1, -hy, z1), Vector3(s * w0, -hy, z0), Vector3.DOWN, steel)
        K.quad(st, Transform3D.IDENTITY, Vector3(s * w0, hy, z0), Vector3(s * w1, hy, z1), Vector3(s * w1, -hy, z1), Vector3(s * w0, -hy, z0), Vector3(s, 0, 0), steel)
        # bevelled cutting edge
        K.quad(st, Transform3D.IDENTITY, Vector3(s * 0.004, hy, z0), Vector3(s * 0.004, hy, z1), Vector3(ex1, 0, z1), Vector3(ex0, 0, z0), Vector3(-s, 0.6, 0), edge)
        K.quad(st, Transform3D.IDENTITY, Vector3(s * 0.004, -hy, z0), Vector3(s * 0.004, -hy, z1), Vector3(ex1, 0, z1), Vector3(ex0, 0, z0), Vector3(-s, -0.6, 0), edge)
    # round tang plate around the pivot joins blade, shank and screw
    K.lathe(st, Transform3D.IDENTITY, [Vector2(0.0, -hy), Vector2(0.014, -hy), Vector2(0.014, hy), Vector2(0.0, hy)], 10, [steel])
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