extends Node3D

## Intact tumor lump (carried whole or eaten). Three readable kinds so the
## codex has distinct silhouettes, all about basketball-to-melon size:
##   0 grape cluster  - bunched glossy cysts
##   1 tooth lump     - fatty mass with human teeth and black hair specks
##   2 nerve sac      - smooth taut sac wrapped in yellow nerve veins
## Origin = centre. Public: set_variant(0..2), variant(), set_pulse(bool),
## static build_mesh(kind) -> ArrayMesh (reused by the tumor bag).

const K := preload("res://main/art/fp_art_kit.gd")
const R := 0.11
var _mi: MeshInstance3D
var _variant := 0
var _pulse := true
var _time := 0.0

func _ready() -> void:
    _mi = K.add_mesh(self, "Tumor", ArrayMesh.new(), K.mat("tex_skin_128.png", 0.75, true))
    set_variant(_variant)

static func build_mesh(kind: int) -> ArrayMesh:
    var st := K.begin()
    var I := Transform3D.IDENTITY
    match kind:
        0:
            K.blob(st, I, Vector3.ZERO, Vector3(R * 0.8, R * 0.7, R * 0.75), 0.25, 31, Color(0.45, 0.08, 0.14), Color(0.6, 0.12, 0.2))
            for i in range(11):
                var d := Vector3(K.h(i, 1) - 0.5, K.h(i, 2) - 0.4, K.h(i, 3) - 0.5).normalized()
                var r := R * (0.3 + K.h(i, 4) * 0.25)
                K.blob(st, I, d * R * 0.72, Vector3(r, r * 0.9, r), 0.12, 40 + i, Color(0.62, 0.2, 0.32), Color(0.78, 0.4, 0.45))
        1:
            K.blob(st, I, Vector3.ZERO, Vector3(R, R * 0.8, R * 0.9), 0.45, 57, Color(0.72, 0.52, 0.28), Color(0.55, 0.12, 0.1))
            K.blob(st, I, Vector3(R * 0.5, R * 0.35, 0.02), Vector3(R * 0.5, R * 0.45, R * 0.5), 0.4, 58, Color(0.7, 0.45, 0.25), Color(0.5, 0.1, 0.1))
            for i in range(7):
                var d := Vector3(K.h(i, 7) - 0.5, K.h(i, 8) * 0.8, K.h(i, 9) - 0.5).normalized()
                var p := d * R * 0.82
                K.lathe(st, Transform3D(Basis(Quaternion(Vector3.UP, d)), p), [Vector2(0.0, -0.012), Vector2(0.012, -0.004), Vector2(0.014, 0.008), Vector2(0.008, 0.016), Vector2(0.0, 0.015)], 6, [Color(0.9, 0.84, 0.66)])
            for i in range(30):
                var d := Vector3(K.h(i, 17) - 0.5, K.h(i, 18) - 0.5, K.h(i, 19) - 0.5).normalized()
                K.tube(st, I, [d * R * 0.78, d * R * 0.95 + Vector3(0, 0.01, 0)], [0.002, 0.0008], 3, [Color(0.03, 0.02, 0.02)], false)
        _:
            K.blob(st, I, Vector3.ZERO, Vector3(R * 0.85, R * 1.05, R * 0.85), 0.08, 71, Color(0.62, 0.36, 0.4), Color(0.72, 0.46, 0.46))
            for v in range(6):
                var pts: Array = []
                var a0 := v * TAU / 6.0
                for k in range(8):
                    var t := float(k) / 7.0
                    var el := lerpf(-1.2, 1.2, t)
                    var az := a0 + sin(t * 5.0 + v) * 0.35
                    var rr := R * 0.9 * (1.0 + 0.04 * sin(t * 9.0))
                    pts.append(Vector3(cos(az) * cos(el) * rr * 0.97, sin(el) * rr * 1.18, sin(az) * cos(el) * rr * 0.97))
                K.tube(st, I, pts, [0.004, 0.007, 0.006, 0.008, 0.006, 0.007, 0.005, 0.003], 4, [Color(0.9, 0.78, 0.2)])
    return K.finish(st, 7.0)

func set_variant(v: int) -> void:
    _variant = clampi(v, 0, 2)
    if _mi != null:
        _mi.mesh = build_mesh(_variant)

func variant() -> int:
    return _variant

func set_pulse(on: bool) -> void:
    _pulse = on

func _process(delta: float) -> void:
    _time += delta
    if _pulse:
        var s := 1.0 + sin(_time * 3.1) * 0.025
        scale = Vector3(s, 1.0 / s, s)

func capture_setup() -> Dictionary:
    # capture only: all three kinds side by side
    set_variant(0)
    for i in [1, 2]:
        var m := K.add_mesh(self, "CaptureKind%d" % i, build_mesh(i), K.mat("tex_skin_128.png", 0.75, true))
        m.position = Vector3((i - 0) * 0.28, 0, 0)
    position.x = -0.28
    return {"cam_pos": Vector3(0.0, 0.16, 0.6), "look_at": Vector3(0, 0, 0), "env": "lit", "fov": 55.0}