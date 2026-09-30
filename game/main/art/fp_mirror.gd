extends Node3D

## Restroom mirror over the sink. Origin = floor under the sink front; the
## wall is the z=0 plane, the room is +Z. Clean chrome, pale glass, a small
## ceramic basin with a tap. The mirror itself is an interactable surface
## (the player must press on it), so set_focus() brightens the glass edge.
## Public: set_focus(bool), mirror_center() -> Vector3.

const K := preload("res://main/art/fp_art_kit.gd")
var _glass: MeshInstance3D
var _glow: MeshInstance3D

func _ready() -> void:
    var chrome := K.mat("tex_chrome_128.png", 0.5, false)
    var ceramic := K.mat("tex_ceramic_128.png", 0.45, false)
    var st := K.begin()
    # frame: 4 rounded chrome bars (octagonal tubes) around the glass
    var w := 0.3
    var hh := 0.38
    var cy := 1.45
    var c := Color(0.82, 0.84, 0.86)
    var corners := [Vector3(-w, cy - hh, 0.02), Vector3(w, cy - hh, 0.02), Vector3(w, cy + hh, 0.02), Vector3(-w, cy + hh, 0.02)]
    for i in range(4):
        K.tube(st, Transform3D.IDENTITY, [corners[i], corners[(i + 1) % 4]], [0.018], 8, [c])
        K.lathe(st, K.T(corners[i], Vector3(90, 0, 0)), [Vector2(0, -0.02), Vector2(0.018, -0.018), Vector2(0.022, 0.0), Vector2(0.018, 0.018), Vector2(0, 0.02)], 8, [c])
    # shelf under the mirror
    K.rbox(st, K.T(Vector3(0, cy - hh - 0.06, 0.05)), Vector3(0.26, 0.008, 0.05), 0.006, Color(0.9, 0.92, 0.94))
    # tap
    K.lathe(st, K.T(Vector3(0, 0.86, 0.06)), [Vector2(0.02, 0.0), Vector2(0.018, 0.08), Vector2(0.0, 0.085)], 8, [c])
    K.tube(st, Transform3D.IDENTITY, [Vector3(0, 0.93, 0.06), Vector3(0, 0.95, 0.12), Vector3(0, 0.92, 0.17)], [0.011, 0.01, 0.009], 6, [c])
    for sx in [-1, 1]:
        K.lathe(st, K.T(Vector3(sx * 0.09, 0.86, 0.06)), [Vector2(0.018, 0.0), Vector2(0.014, 0.03), Vector2(0.024, 0.04), Vector2(0.0, 0.05)], 6, [c])
    K.add_mesh(self, "Chrome", K.finish(st, 6.0), chrome)
    # glass: slight vertical gradient, a few diagonal highlight streaks
    st = K.begin()
    var g0 := Color(0.62, 0.7, 0.74)
    var g1 := Color(0.78, 0.84, 0.87)
    var rows := 4
    for r in range(rows):
        var y0 := cy - hh + 2.0 * hh * r / rows
        var y1 := cy - hh + 2.0 * hh * (r + 1) / rows
        K.quad(st, Transform3D.IDENTITY, Vector3(-w, y0, 0.012), Vector3(w, y0, 0.012), Vector3(w, y1, 0.012), Vector3(-w, y1, 0.012), Vector3.BACK, g0.lerp(g1, float(r) / rows))
    for i in range(2):
        var x0 := -0.18 + i * 0.12
        K.quad(st, Transform3D.IDENTITY, Vector3(x0, cy - 0.2, 0.014), Vector3(x0 + 0.05, cy - 0.2, 0.014), Vector3(x0 + 0.17, cy + 0.2, 0.014), Vector3(x0 + 0.12, cy + 0.2, 0.014), Vector3.BACK, Color(0.9, 0.94, 0.96))
    _glass = K.add_mesh(self, "Glass", K.finish(st, 2.0), K.mat("tex_chrome_64.png", 0.95, false))
    # interaction glow rim (hidden until focused)
    st = K.begin()
    K.quad(st, Transform3D.IDENTITY, Vector3(-w - 0.03, cy - hh - 0.03, 0.005), Vector3(w + 0.03, cy - hh - 0.03, 0.005), Vector3(w + 0.03, cy + hh + 0.03, 0.005), Vector3(-w - 0.03, cy + hh + 0.03, 0.005), Vector3.BACK, Color(1, 1, 1))
    _glow = K.add_mesh(self, "FocusRim", K.finish(st), K.glow(Color(0.85, 0.95, 1.0)))
    _glow.visible = false
    # basin: a lathed bowl, cut by the wall (built full, pushed half into it)
    st = K.begin()
    var cw := Color(0.94, 0.95, 0.96)
    var ci := Color(0.78, 0.8, 0.82)
    K.lathe(st, K.T(Vector3(0, 0.62, 0.12), Vector3.ZERO, Vector3(1.0, 1.0, 0.75)), [Vector2(0.03, 0.0), Vector2(0.12, 0.08), Vector2(0.21, 0.2), Vector2(0.23, 0.24), Vector2(0.21, 0.25)], 12, [cw, cw, cw, ci])
    K.lathe(st, K.T(Vector3(0, 0.62, 0.12), Vector3(180, 0, 0), Vector3(1.0, 1.0, 0.75)), [Vector2(0.0, -0.25), Vector2(0.2, -0.25), Vector2(0.11, -0.12), Vector2(0.03, -0.05), Vector2(0.0, -0.05)], 12, [ci, ci, Color(0.55, 0.57, 0.6)])
    # basin sits wall-mounted (modern vanity look, 형님 2026-09-30): no floor
    # pedestal column -- one was here as a lathe with an unclosed bottom cap
    # (K.lathe never closes radius>0 ends), which read as a hollow cylinder
    # under the basin.
    K.add_mesh(self, "Basin", K.finish(st, 5.0), ceramic)

func set_focus(on: bool) -> void:
    _glow.visible = on

func mirror_center() -> Vector3:
    return Vector3(0, 1.45, 0.02)

func capture_setup() -> Dictionary:
    # capture only: the tiled wall behind
    var st := K.begin()
    K.quad(st, Transform3D.IDENTITY, Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(1, 2.2, 0), Vector3(-1, 2.2, 0), Vector3.BACK, Color(0.85, 0.87, 0.88))
    K.add_mesh(self, "CaptureWall", K.finish(st, 3.0), K.mat("tex_tile_wall_128.png", 0.2, false))
    return {"cam_pos": Vector3(0.9, 1.4, 2.3), "look_at": Vector3(0, 1.1, 0), "env": "restroom", "fov": 55.0}