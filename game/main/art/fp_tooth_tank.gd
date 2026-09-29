extends Node3D

## Toilet water tank (the bank). Origin = bottom-centre of the tank. Lid
## hinges up on its back edge (-Z). Inside: dark water and a pile of human
## teeth whose height follows set_amount(0..1).
## Public: set_lid_open(0..1), play_open(), play_close(), set_amount(0..1),
## tooth_count().

const K := preload("res://main/art/fp_art_kit.gd")
const W := 0.22
const D := 0.095
const H := 0.34
const HANDFUL := 4
const MAX_TEETH := 260
## Height of the inner shelf the teeth rest on (tank-local).
const SHELF := H * 0.5

var _lid: Node3D
var _teeth: MultiMeshInstance3D
var _water: MeshInstance3D
var _amount := 0.35
var _slots: Array = []

func _ready() -> void:
    var ceramic := K.mat("tex_ceramic_128.png", 0.45, false)
    var white := Color(0.93, 0.94, 0.95)
    var shade := Color(0.8, 0.82, 0.84)
    # tank shell: 4 bevelled walls + floor (open top)
    var st := K.begin()
    var wall := 0.014
    K.rbox(st, K.T(Vector3(0, H * 0.5, D - wall)), Vector3(W, H * 0.5, wall), 0.01, white, shade)
    K.rbox(st, K.T(Vector3(0, H * 0.5, -D + wall)), Vector3(W, H * 0.5, wall), 0.01, white, shade)
    K.rbox(st, K.T(Vector3(W - wall, H * 0.5, 0)), Vector3(wall, H * 0.5, D - 0.004), 0.01, white, shade)
    K.rbox(st, K.T(Vector3(-W + wall, H * 0.5, 0)), Vector3(wall, H * 0.5, D - 0.004), 0.01, white, shade)
    K.rbox(st, K.T(Vector3(0, 0.01, 0)), Vector3(W, 0.01, D), 0.006, shade)
    # raised inner shelf just under the water line: the teeth pile on it, so
    # they sit high enough to be seen over the front wall from a standing eye
    K.rbox(st, K.T(Vector3(0, SHELF - 0.008, 0)), Vector3(W - wall * 2.0, 0.008, D - wall * 2.0), 0.004, shade)
    # flush lever on the front-left
    K.lathe(st, K.T(Vector3(-W + 0.05, H - 0.05, D + 0.002), Vector3(90, 0, 0)), [Vector2(0.0, -0.012), Vector2(0.018, -0.012), Vector2(0.018, 0.0), Vector2(0.0, 0.002)], 8, [Color(0.85, 0.86, 0.88)])
    K.tube(st, Transform3D.IDENTITY, [Vector3(-W + 0.05, H - 0.05, D + 0.012), Vector3(-W + 0.1, H - 0.052, D + 0.02), Vector3(-W + 0.12, H - 0.06, D + 0.022)], [0.006, 0.006, 0.008], 5, [Color(0.8, 0.82, 0.84)])
    K.add_mesh(self, "Tank", K.finish(st, 5.0), ceramic)
    # water: dark, right under the shelf the teeth lie on, so the ivory
    # teeth read against it from a standing eye
    st = K.begin()
    var wy := SHELF + 0.004
    K.quad(st, Transform3D.IDENTITY, Vector3(-W + 0.02, wy, -D + 0.02), Vector3(W - 0.02, wy, -D + 0.02), Vector3(W - 0.02, wy, D - 0.02), Vector3(-W + 0.02, wy, D - 0.02), Vector3.UP, Color(0.35, 0.45, 0.48))
    var wm := StandardMaterial3D.new()
    wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    wm.albedo_color = Color(0.1, 0.17, 0.19, 0.85)
    wm.roughness = 0.1
    wm.metallic_specular = 0.9
    _water = K.add_mesh(self, "Water", K.finish(st, 3.0), wm)
    # lid on its back hinge
    _lid = K.pivot(self, "LidHinge", Vector3(0, H + 0.012, -D - 0.008))
    st = K.begin()
    K.rbox(st, K.T(Vector3(0, 0.0, D + 0.008)), Vector3(W + 0.012, 0.014, D + 0.012), 0.012, white, shade)
    K.rbox(st, K.T(Vector3(0, 0.02, D + 0.008)), Vector3(W - 0.02, 0.008, D - 0.02), 0.008, white)
    K.add_mesh(_lid, "Lid", K.finish(st, 5.0), ceramic)
    # teeth
    _teeth = MultiMeshInstance3D.new()
    _teeth.name = "Teeth"
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = true
    mm.mesh = _tooth_mesh()
    mm.instance_count = MAX_TEETH
    _teeth.multimesh = mm
    _teeth.material_override = K.mat("tex_ceramic_64.png", 0.5, false)
    # fixed bounds: the multimesh AABB came out empty, so the pile was culled
    _teeth.custom_aabb = AABB(Vector3(-W, 0.0, -D), Vector3(W * 2.0, H, D * 2.0))
    add_child(_teeth)
    _build_slots()
    set_amount(_amount)

## A single molar-ish tooth: faceted crown with cusps + two tapering roots.
func _tooth_mesh() -> ArrayMesh:
    var st := K.begin()
    var enamel := Color(0.9, 0.84, 0.66)
    var root := Color(0.7, 0.55, 0.38)
    K.lathe(st, Transform3D.IDENTITY, [Vector2(0.0, -0.004), Vector2(0.0075, -0.003), Vector2(0.009, 0.002), Vector2(0.008, 0.006), Vector2(0.004, 0.0085), Vector2(0.0, 0.007)], 6, [root, enamel, enamel, enamel, enamel])
    for sx in [-1, 1]:
        K.tube(st, Transform3D.IDENTITY, [Vector3(sx * 0.0035, -0.002, 0), Vector3(sx * 0.0045, -0.009, 0.001), Vector3(sx * 0.003, -0.015, 0.0)], [0.0035, 0.0025, 0.0008], 4, [root])
    return K.finish(st, 60.0)

## Pile layout: a heap packed from the bottom, higher toward the middle, so
## a partial amount reads as a mound. Slots are grouped 4 at a time into a tight cluster (one handful), not a flat layer.
func _build_slots() -> void:
    _slots.clear()
    var i := 0
    var layer := 0
    while _slots.size() < MAX_TEETH:
        var y := SHELF + 0.022 + layer * 0.026
        var shrink := clampf(float(layer) / 11.0, 0.0, 0.85)
        var cols := 5
        var rows := 3
        for r in range(rows):
            for c in range(cols):
                var x := (float(c) / (cols - 1) - 0.5) * 2.0 * (W - 0.035)
                var z := (float(r) / (rows - 1) - 0.5) * 2.0 * (D - 0.03)
                if Vector2(x / W, z / D).length() > (1.25 - shrink):
                    continue
                var jx := (K.h(i, 1) - 0.5) * 0.02
                var jz := (K.h(i, 2) - 0.5) * 0.014
                var jy := K.h(i, 3) * 0.008
                var rot := Vector3(K.h(i, 4) * 360.0, K.h(i, 5) * 360.0, K.h(i, 6) * 360.0)
                for q in range(HANDFUL):
                    var qo := Vector3((q % 2 - 0.5) * 0.024, (q / 2) * 0.011, ((q / 2) - 0.5) * 0.018)
                    var qr := rot + Vector3(q * 71.0, q * 43.0, q * 29.0)
                    _slots.append(Transform3D(Basis.from_euler(qr * PI / 180.0).scaled(Vector3.ONE * 2.4), Vector3(x + jx, y + jy, z + jz) + qo))
                i += 1
                if _slots.size() >= MAX_TEETH:
                    break
            if _slots.size() >= MAX_TEETH:
                break
        layer += 1
    for k in range(MAX_TEETH):
        _teeth.multimesh.set_instance_transform(k, _slots[k])
        var yellow := K.h(k, 9)
        _teeth.multimesh.set_instance_color(k, Color(0.9, 0.78 - yellow * 0.1, 0.55 - yellow * 0.15))

func set_amount(amount: float) -> void:
    _amount = clampf(amount, 0.0, 1.0)
    # teeth are always shown in whole handfuls of 4 (one scoop = 4 teeth)
    var n := int(round(_amount * MAX_TEETH / float(HANDFUL))) * HANDFUL
    _teeth.multimesh.visible_instance_count = mini(n, MAX_TEETH)

## Handful-based API: n handfuls = n * 4 teeth.
func set_handfuls(n: int) -> void:
    set_amount(float(maxi(n, 0) * HANDFUL) / float(MAX_TEETH))

func handful_count() -> int:
    return tooth_count() / HANDFUL

func tooth_count() -> int:
    return _teeth.multimesh.visible_instance_count

func set_lid_open(t: float) -> void:
    _lid.rotation_degrees.x = -105.0 * clampf(t, 0.0, 1.0)

func play_open() -> void:
    create_tween().tween_method(set_lid_open, 0.0, 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func play_close() -> void:
    create_tween().tween_method(set_lid_open, 1.0, 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func capture_setup() -> Dictionary:
    set_lid_open(1.0)
    set_amount(0.75)
    return {"cam_pos": Vector3(0.32, 0.78, 0.7), "look_at": Vector3(0, 0.18, 0), "env": "restroom", "fov": 50.0, "fill_energy": 0.25}