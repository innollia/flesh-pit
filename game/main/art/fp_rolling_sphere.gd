extends Node3D

## The rolling human sphere seen from OUTSIDE (ending). One very round ball
## like a raw meatball: the SHAPE is a smooth, near-perfect sphere; the
## minced look is texture only (pinkish red meat densely dotted with white
## fat grains, main/art/textures/tex_minced_meat_128.png). No human shapes. Larger than the tallest building on the
## ending street (radius 34 m; tallest block ~26 m).
## Origin = sphere centre. Public: set_roll(angle_rad), set_radius(m),
## set_rolling(bool), roll_speed (m/s).

const K := preload("res://main/art/fp_art_kit.gd")
const SEG := 36
const RINGS := 22
@export var radius := 34.0
var roll_speed := 3.0
var _rolling := false
var _ball: Node3D
var _angle := 0.0

func _ready() -> void:
    _ball = K.pivot(self, "Ball")
    var st := K.begin()
    var pts: Array = []
    for r in range(RINGS + 1):
        var el := -PI * 0.5 + PI * r / RINGS
        var row: Array = []
        for s in range(SEG):
            var az := TAU * s / SEG
            var d := Vector3(cos(el) * cos(az), sin(el), cos(el) * sin(az))
            var bump := 1.0  # shape stays a clean sphere; mince is texture only
            row.append(d * bump)
        pts.append(row)
    var reds := [Color(0.78, 0.26, 0.28), Color(0.66, 0.16, 0.2), Color(0.86, 0.42, 0.42), Color(0.72, 0.22, 0.24)]
    var fat := Color(0.92, 0.78, 0.68)
    for r in range(RINGS):
        for s in range(SEG):
            var s2 := (s + 1) % SEG
            var a: Vector3 = pts[r][s]
            var b: Vector3 = pts[r][s2]
            var c: Vector3 = pts[r + 1][s2]
            var d: Vector3 = pts[r + 1][s]
            var hv := K.h(s, r, 7)
            var col: Color = Color(1, 1, 1).lerp(reds[int(hv * 40.0) % 4], 0.12)
            var mid := (a + b + c + d) * 0.25
            K.quad(st, Transform3D.IDENTITY, a, b, c, d, mid, col)
    K.add_mesh(_ball, "Body", K.finish(st, 3.0), FDKPs1Material.get_material("res://main/art/textures/tex_minced_meat_128.png", 1.0, true, 0.35, 0.6, 1.0, false))
    set_radius(radius)

func set_radius(r: float) -> void:
    radius = r
    _ball.scale = Vector3.ONE * r

func set_roll(angle: float) -> void:
    _angle = angle
    _ball.rotation = Vector3(0, 0, -angle)

func set_rolling(on: bool) -> void:
    _rolling = on

func _process(delta: float) -> void:
    if _rolling:
        position.x += roll_speed * delta
        set_roll(_angle + roll_speed * delta / maxf(radius, 0.01))

func capture_setup() -> Dictionary:
    set_roll(0.6)
    return {"cam_pos": Vector3(20, 8, 110), "look_at": Vector3(0, 0, 0), "env": "day", "fov": 50.0}