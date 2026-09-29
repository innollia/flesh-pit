extends Node3D

## Big two-man crosscut saw, used two-handed for digging. Origin = centre of
## the blade; the blade runs along X, teeth point down (-Y). A wooden
## upright grip at each end (left and right hand).
## Public: set_stroke(-1..1) (push/pull offset along X), play_stroke(),
## grip_left()/grip_right() -> Vector3.

const K := preload("res://main/art/fp_art_kit.gd")
const L := 0.62

func _ready() -> void:
    var st := K.begin()
    var steel := Color(0.62, 0.62, 0.6)
    var rust := Color(0.5, 0.32, 0.2)
    var bright := Color(0.88, 0.88, 0.86)
    # blade: curved belly (deeper in the middle), thin plate, 2 facets thick
    var n := 14
    for i in range(n):
        var x0 := -L + 2.0 * L * i / n
        var x1 := -L + 2.0 * L * (i + 1) / n
        var d0 := 0.05 + 0.06 * cos(x0 / L * PI * 0.5)
        var d1 := 0.05 + 0.06 * cos(x1 / L * PI * 0.5)
        var col := steel.lerp(rust, K.h(i, 3) * 0.6)
        for sz in [-1, 1]:
            K.quad(st, Transform3D.IDENTITY, Vector3(x0, 0.03, sz * 0.0015), Vector3(x1, 0.03, sz * 0.0015), Vector3(x1, -d1, sz * 0.0008), Vector3(x0, -d0, sz * 0.0008), Vector3(0, 0, sz), col)
        # teeth along the belly: alternating set, pointed triangles
        var tn := 3
        for k in range(tn):
            var ta := lerpf(x0, x1, float(k) / tn)
            var tb := lerpf(x0, x1, float(k + 1) / tn)
            var dm := lerpf(d0, d1, (float(k) + 0.5) / tn)
            var set_z := 0.002 * (1 if (i * tn + k) % 2 == 0 else -1)
            K.tri(st, Transform3D.IDENTITY, Vector3(ta, -dm + 0.004, 0), Vector3(tb, -dm + 0.004, 0), Vector3((ta + tb) * 0.5, -dm - 0.018, set_z), Vector3(0, 0, 1), bright)
            K.tri(st, Transform3D.IDENTITY, Vector3(ta, -dm + 0.004, 0), Vector3(tb, -dm + 0.004, 0), Vector3((ta + tb) * 0.5, -dm - 0.018, set_z), Vector3(0, 0, -1), bright)
    K.quad(st, Transform3D.IDENTITY, Vector3(-L, 0.03, -0.0015), Vector3(L, 0.03, -0.0015), Vector3(L, 0.03, 0.0015), Vector3(-L, 0.03, 0.0015), Vector3.UP, steel)
    K.add_mesh(self, "Blade", K.finish(st, 8.0), K.mat("tex_chrome_128.png", 0.3, true))
    st = K.begin()
    var wood := Color(0.66, 0.44, 0.24)
    for sx in [-1, 1]:
        var base := Vector3(sx * (L + 0.01), 0.0, 0)
        K.tube(st, Transform3D.IDENTITY, [base + Vector3(0, -0.04, 0), base + Vector3(sx * 0.01, 0.05, 0), base + Vector3(sx * 0.02, 0.17, 0), base + Vector3(sx * 0.018, 0.2, 0)], [0.017, 0.02, 0.019, 0.015], 7, [wood])
        K.lathe(st, K.T(base + Vector3(0, 0.0, 0.004), Vector3(90, 0, 0)), [Vector2(0.0, -0.012), Vector2(0.008, -0.012), Vector2(0.008, 0.012), Vector2(0.0, 0.012)], 6, [Color(0.3, 0.3, 0.3)])
    K.add_mesh(self, "Grips", K.finish(st, 8.0), K.mat("tex_fixture_64.png", 0.2, true))

func set_stroke(s: float) -> void:
    position.x = 0.12 * clampf(s, -1.0, 1.0)

func play_stroke() -> void:
    var tw := create_tween().set_loops(2)
    tw.tween_method(set_stroke, -1.0, 1.0, 0.35).set_trans(Tween.TRANS_SINE)
    tw.tween_method(set_stroke, 1.0, -1.0, 0.35).set_trans(Tween.TRANS_SINE)

func grip_left() -> Vector3:
    return Vector3(-L - 0.02, 0.1, 0)

func grip_right() -> Vector3:
    return Vector3(L + 0.02, 0.1, 0)

func capture_setup() -> Dictionary:
    return {"cam_pos": Vector3(0.15, 0.25, 1.05), "look_at": Vector3(0, 0.0, 0), "env": "dark", "fov": 60.0}