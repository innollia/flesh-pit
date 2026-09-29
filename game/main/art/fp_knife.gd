extends Node3D

## Kitchen knife (one-handed). Origin = the grip point; blade points -Z,
## edge down (-Y). Riveted wooden handle, bolster, bevelled blade whose
## cross-section is a wedge (so the flat catches light, the edge darkens).
## Public: set_bloody(0..1), grip_point() -> Vector3.

const K := preload("res://main/art/fp_art_kit.gd")
var _blood: MeshInstance3D

func _ready() -> void:
    var st := K.begin()
    var wood := Color(0.38, 0.22, 0.12)
    var steel := Color(0.8, 0.82, 0.85)
    var edge := Color(0.95, 0.96, 0.98)
    # handle: flattened 6-sided tube, slight belly
    K.tube(st, Transform3D.IDENTITY, [Vector3(0, 0, 0.06), Vector3(0, -0.003, 0.03), Vector3(0, 0, -0.01), Vector3(0, 0.002, -0.035)], [0.011, 0.014, 0.013, 0.012], 6, [wood], true, 0.62)
    for z in [0.04, 0.0]:
        K.lathe(st, K.T(Vector3(0.008, 0.0, z), Vector3(0, 0, -90)), [Vector2(0.0, 0.0), Vector2(0.004, 0.0), Vector2(0.003, 0.002), Vector2(0.0, 0.002)], 6, [steel])
    K.lathe(st, K.T(Vector3(0, 0.001, -0.04), Vector3(90, 0, 0)), [Vector2(0.0, -0.006), Vector2(0.014, -0.006), Vector2(0.015, 0.004), Vector2(0.0, 0.006)], 6, [steel])
    # blade: spine at y=+0.012, edge at y=-0.02..0, tapering to a point
    var n := 6
    for i in range(n):
        var t0 := float(i) / n
        var t1 := float(i + 1) / n
        var z0 := -0.045 - t0 * 0.17
        var z1 := -0.045 - t1 * 0.17
        var hgt0 := lerpf(0.034, 0.0, pow(t0, 2.2))
        var hgt1 := lerpf(0.034, 0.0, pow(t1, 2.2))
        var sp0 := 0.012 - pow(t0, 1.6) * 0.012
        var sp1 := 0.012 - pow(t1, 1.6) * 0.012
        var e0 := sp0 - hgt0
        var e1 := sp1 - hgt1
        var th0 := 0.0022 * (1.0 - t0 * 0.7)
        var th1 := 0.0022 * (1.0 - t1 * 0.7)
        for sx in [-1, 1]:
            K.quad(st, Transform3D.IDENTITY, Vector3(sx * th0, sp0, z0), Vector3(sx * th1, sp1, z1), Vector3(sx * th1, (sp1 + e1) * 0.5, z1), Vector3(sx * th0, (sp0 + e0) * 0.5, z0), Vector3(sx, 0.1, 0), steel)
            K.quad(st, Transform3D.IDENTITY, Vector3(sx * th0, (sp0 + e0) * 0.5, z0), Vector3(sx * th1, (sp1 + e1) * 0.5, z1), Vector3(0, e1, z1), Vector3(0, e0, z0), Vector3(sx, -0.4, 0), edge)
        K.quad(st, Transform3D.IDENTITY, Vector3(-th0, sp0, z0), Vector3(th0, sp0, z0), Vector3(th1, sp1, z1), Vector3(-th1, sp1, z1), Vector3.UP, steel)
    K.add_mesh(self, "Knife", K.finish(st, 12.0), K.mat("tex_chrome_128.png", 0.5, false))
    st = K.begin()
    K.blob(st, Transform3D.IDENTITY, Vector3(0, -0.006, -0.16), Vector3(0.004, 0.012, 0.05), 0.4, 5, Color(0.4, 0.02, 0.04), Color(0.6, 0.05, 0.07))
    _blood = K.add_mesh(self, "Blood", K.finish(st, 8.0), K.mat("tex_torn_chunk_64.png", 0.9, true))
    _blood.visible = false

func set_bloody(amount: float) -> void:
    _blood.visible = amount > 0.05
    _blood.scale = Vector3.ONE * lerpf(0.5, 1.2, clampf(amount, 0.0, 1.0))

func grip_point() -> Vector3:
    return Vector3.ZERO

func capture_setup() -> Dictionary:
    set_bloody(0.8)
    return {"cam_pos": Vector3(0.22, 0.12, -0.05), "look_at": Vector3(0, 0, -0.08), "env": "dark", "fov": 50.0}