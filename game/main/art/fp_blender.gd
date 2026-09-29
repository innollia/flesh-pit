extends Node3D

## Kitchen blender (one-handed tool, held in the LEFT hand). Origin = base
## bottom centre, +Y up. Motor base, ribbed jar with a four-wing blade, lid
## with a pour cap. Contents (blended flesh) fill 0..1.
## Public: set_fill(0..1), set_spin(bool), play_drink() (tilt to the mouth
## and drain), set_tilt(0..1), hand_grip() -> Vector3 (where the left hand
## wraps the jar).

const K := preload("res://main/art/fp_art_kit.gd")
var _jar: Node3D
var _blade: Node3D
var _fill_mi: MeshInstance3D
var _fill := 0.0
var _spin := false
var _time := 0.0
## -1 when the blender is mounted turned 180 degrees about Y (handle on the
## outer side for the left hand), so drinking still tips it toward the mouth.
var tilt_dir := 1.0

func _ready() -> void:
    var st := K.begin()
    var body := Color(0.86, 0.84, 0.78)   # old cream plastic
    var dark := Color(0.25, 0.24, 0.23)
    K.lathe(st, Transform3D.IDENTITY, [Vector2(0.0, 0.0), Vector2(0.075, 0.0), Vector2(0.08, 0.012), Vector2(0.072, 0.09), Vector2(0.06, 0.11), Vector2(0.05, 0.115), Vector2(0.0, 0.115)], 8, [dark, body, body, body, dark])
    # speed dial + two buttons on the front
    K.lathe(st, K.T(Vector3(0, 0.06, 0.074), Vector3(90, 0, 0)), [Vector2(0.0, -0.01), Vector2(0.018, -0.01), Vector2(0.016, 0.004), Vector2(0.0, 0.006)], 8, [Color(0.7, 0.12, 0.1)])
    for sx in [-1, 1]:
        K.rbox(st, K.T(Vector3(sx * 0.035, 0.035, 0.068), Vector3(0, sx * 20, 0)), Vector3(0.01, 0.006, 0.006), 0.003, Color(0.9, 0.9, 0.88))
    # power cord out of the back, ending in a two-prong plug (it is charged
    # by plugging it into nerve-dense tissue, docs/spec/06-tools.md)
    K.tube(st, Transform3D.IDENTITY, [Vector3(0, 0.02, -0.075), Vector3(0.0, 0.01, -0.12), Vector3(0.04, 0.005, -0.17), Vector3(0.09, 0.012, -0.19), Vector3(0.12, 0.02, -0.17)], [0.005], 4, [dark], false)
    K.rbox(st, K.T(Vector3(0.13, 0.022, -0.16), Vector3(0, -50, 0)), Vector3(0.012, 0.01, 0.018), 0.004, Color(0.15, 0.15, 0.15))
    for sx in [-1, 1]:
        K.rbox(st, K.T(Vector3(0.13, 0.022, -0.16), Vector3(0, -50, 0)) * K.T(Vector3(sx * 0.005, 0, 0.026)), Vector3(0.0015, 0.004, 0.009), 0.0005, Color(0.85, 0.75, 0.4))
    K.add_mesh(self, "Base", K.finish(st, 6.0), K.mat("tex_fixture_128.png", 0.2, false))
    _jar = K.pivot(self, "Jar", Vector3(0, 0.115, 0))
    st = K.begin()
    var glass := Color(0.62, 0.72, 0.72)
    K.lathe(st, Transform3D.IDENTITY, [Vector2(0.045, 0.0), Vector2(0.05, 0.02), Vector2(0.062, 0.1), Vector2(0.072, 0.19), Vector2(0.074, 0.2)], 8, [glass], 0.0)
    # handle
    K.tube(st, Transform3D.IDENTITY, [Vector3(0.06, 0.17, 0), Vector3(0.11, 0.16, 0), Vector3(0.115, 0.08, 0), Vector3(0.056, 0.05, 0)], [0.012, 0.014, 0.014, 0.012], 6, [glass])
    # lid + cap
    K.lathe(st, K.T(Vector3(0, 0.2, 0)), [Vector2(0.078, 0.0), Vector2(0.078, 0.012), Vector2(0.03, 0.016), Vector2(0.026, 0.03), Vector2(0.0, 0.032)], 8, [dark, dark, Color(0.3, 0.3, 0.3)])
    var jm := StandardMaterial3D.new()
    jm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    jm.vertex_color_use_as_albedo = true
    jm.albedo_color = Color(1, 1, 1, 0.55)
    jm.roughness = 0.15
    jm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    jm.cull_mode = BaseMaterial3D.CULL_DISABLED
    K.add_mesh(_jar, "Glass", K.finish(st, 5.0), jm)
    _blade = K.pivot(_jar, "Blade", Vector3(0, 0.03, 0))
    st = K.begin()
    for i in range(4):
        var a := i * 90.0
        K.rbox(st, K.T(Vector3(cos(deg_to_rad(a)) * 0.022, 0.004 * (i % 2), sin(deg_to_rad(a)) * 0.022), Vector3(0, -a, 20 if i % 2 == 0 else -20)), Vector3(0.022, 0.002, 0.007), 0.001, Color(0.8, 0.82, 0.84))
    K.lathe(st, Transform3D.IDENTITY, [Vector2(0.0, -0.01), Vector2(0.01, -0.01), Vector2(0.008, 0.008), Vector2(0.0, 0.01)], 6, [Color(0.6, 0.6, 0.62)])
    K.add_mesh(_blade, "BladeMesh", K.finish(st, 8.0), K.mat("tex_chrome_64.png", 0.5, false))
    _fill_mi = K.add_mesh(_jar, "Contents", ArrayMesh.new(), K.mat("tex_torn_chunk_64.png", 0.8, false))
    set_fill(0.0)
    _build_lights()

## Charge shown as lamps on the base's side (06-tools.md 2: no numbers).
## One lamp per blend: full charge = 10 lit.
const LIGHT_COUNT := 10
var _lights: Array[MeshInstance3D] = []
var _lit := -1
var _lamp_on: StandardMaterial3D
var _lamp_off: StandardMaterial3D

func _build_lights() -> void:
    _lamp_on = StandardMaterial3D.new()
    _lamp_on.albedo_color = Color(0.55, 1.0, 0.35)
    _lamp_on.emission_enabled = true
    _lamp_on.emission = Color(0.45, 1.0, 0.25)
    _lamp_on.emission_energy_multiplier = 3.0
    _lamp_off = StandardMaterial3D.new()
    _lamp_off.albedo_color = Color(0.12, 0.16, 0.1)
    var bm := BoxMesh.new()
    bm.size = Vector3(0.009, 0.007, 0.004)
    for i in range(LIGHT_COUNT):
        # a row wrapping round the left-front of the base, 0.08 m up
        var a := deg_to_rad(-70.0 + float(i) * 14.0)
        var mi := MeshInstance3D.new()
        mi.name = "ChargeLight%d" % i
        mi.mesh = bm
        mi.position = Vector3(sin(a) * 0.075, 0.085, cos(a) * 0.075)
        mi.rotation.y = a
        mi.material_override = _lamp_off
        add_child(mi)
        _lights.append(mi)
    set_charge_lights(0)

func set_charge_lights(n: int) -> void:
    n = clampi(n, 0, LIGHT_COUNT)
    if n == _lit:
        return
    _lit = n
    for i in range(_lights.size()):
        _lights[i].material_override = _lamp_on if i < n else _lamp_off

func charge_lights_lit() -> int:
    return maxi(0, _lit)

func set_fill(amount: float) -> void:
    _fill = clampf(amount, 0.0, 1.0)
    if _fill <= 0.01:
        _fill_mi.visible = false
        return
    _fill_mi.visible = true
    var top := 0.02 + 0.17 * _fill
    var r_top := lerpf(0.048, 0.07, top / 0.19) - 0.004
    var st := K.begin()
    var red := Color(0.55, 0.06, 0.09)
    var froth := Color(0.78, 0.3, 0.3)
    K.lathe(st, Transform3D.IDENTITY, [Vector2(0.0, 0.006), Vector2(0.043, 0.006), Vector2(r_top, top), Vector2(r_top * 0.6, top + 0.006), Vector2(0.0, top + 0.004)], 8, [red, red, froth, froth])
    _fill_mi.mesh = K.finish(st, 6.0)

func set_spin(on: bool) -> void:
    _spin = on

func set_tilt(t: float) -> void:
    # tip the whole blender toward the viewer (+Z) and up, as when drinking
    rotation_degrees.x = 115.0 * clampf(t, 0.0, 1.0) * tilt_dir

func play_drink() -> void:
    var tw := create_tween()
    tw.tween_method(set_tilt, 0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    tw.tween_method(set_fill, _fill, 0.0, 0.9)
    tw.tween_method(set_tilt, 1.0, 0.0, 0.4)

func hand_grip() -> Vector3:
    return Vector3(0.11, 0.23, 0.0)

func _process(delta: float) -> void:
    _time += delta
    if _spin:
        _blade.rotate_y(delta * 60.0)
        position.x = sin(_time * 70.0) * 0.0015
        if _fill_mi.visible:
            _fill_mi.rotate_y(delta * 9.0)

func capture_setup() -> Dictionary:
    set_fill(0.6)
    return {"cam_pos": Vector3(0.32, 0.36, 0.42), "look_at": Vector3(0, 0.17, 0), "env": "dark", "fov": 50.0}