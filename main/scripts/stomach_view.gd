class_name FPStomachView
extends Node3D

## Stomach state without any text (design-core 1 Overfilling): a lumpy mass
## of flesh swells up from the bottom of the screen between the hands as the
## stomach fills, pulsing like a gut. Past capacity it keeps rising toward
## the throat, and torn-off chunks pile up at the bottom edge of the screen
## instead of disappearing. Attach under the Camera3D.

const PILE_MAX := 14

var fill_ratio: float = 0.0
var overfill_ratio: float = 0.0
var _shown_fill: float = 0.0
var _shown_over: float = 0.0
var _time: float = 0.0
var _mass: MeshInstance3D
var _pile: Array[MeshInstance3D] = []
var _material: ShaderMaterial

func _ready() -> void:
    build()

func build() -> void:
    if _mass != null:
        return
    _material = ShaderMaterial.new()
    _material.shader = load("res://addons/flesh_dig_kit/common/fdk_viewmodel.gdshader")
    _material.set_shader_parameter("wet", 0.7)
    _material.set_shader_parameter("rim_strength", 0.5)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var a := Color(0.58, 0.08, 0.12)
    var b := Color(0.86, 0.3, 0.3)
    FDKLowPoly.add_blob(st, Vector3.ZERO, Vector3(0.2, 0.12, 0.08), 0.22, 21, a, b)
    FDKLowPoly.add_blob(st, Vector3(-0.12, 0.03, 0.01), Vector3(0.1, 0.08, 0.06), 0.3, 22, a, b)
    FDKLowPoly.add_blob(st, Vector3(0.13, 0.02, 0.0), Vector3(0.09, 0.075, 0.06), 0.3, 23, a, b)
    # a pale fatty streak and a darker vein ridge so it reads as organ, not ball
    FDKLowPoly.add_blob(st, Vector3(0.04, 0.07, 0.04), Vector3(0.07, 0.025, 0.03), 0.2, 24, Color(0.9, 0.7, 0.55), Color(0.8, 0.55, 0.45))
    FDKLowPoly.add_blob(st, Vector3(-0.06, 0.08, 0.03), Vector3(0.05, 0.012, 0.02), 0.2, 25, Color(0.4, 0.05, 0.12), Color(0.5, 0.08, 0.15))
    _mass = MeshInstance3D.new()
    _mass.name = "Mass"
    _mass.mesh = st.commit()
    _mass.material_override = _material
    add_child(_mass)
    for i in range(PILE_MAX):
        var ps := SurfaceTool.new()
        ps.begin(Mesh.PRIMITIVE_TRIANGLES)
        var r := 0.035 + FDKLowPoly.hash3(i, 3, 9) * 0.03
        FDKLowPoly.add_blob(ps, Vector3.ZERO, Vector3(r * 1.3, r, r), 0.4, 40 + i, Color(0.55, 0.05, 0.08), Color(0.85, 0.22, 0.2))
        var mi := MeshInstance3D.new()
        mi.name = "Pile%d" % i
        mi.mesh = ps.commit()
        mi.material_override = _material
        mi.visible = false
        var u := (float(i) + 0.5) / PILE_MAX
        var row := i % 2
        mi.position = Vector3(lerpf(-0.24, 0.24, u) + (FDKLowPoly.hash3(i, 1, 1) - 0.5) * 0.04, -0.255 + row * 0.035, -0.33 - row * 0.01)
        mi.rotation = Vector3(FDKLowPoly.hash3(i, 2, 2) * 3.0, FDKLowPoly.hash3(i, 3, 3) * 3.0, 0)
        add_child(mi)
        _pile.append(mi)
    _apply(0.0)

## Connect to FDKStomach.fill_changed, or call with ratios directly.
func set_state(p_fill_ratio: float, p_overfill_ratio: float) -> void:
    fill_ratio = maxf(0.0, p_fill_ratio)
    overfill_ratio = clampf(p_overfill_ratio, 0.0, 1.0)

func snap() -> void:
    _shown_fill = fill_ratio
    _shown_over = overfill_ratio
    _apply(0.0)

func _process(delta: float) -> void:
    _time += delta
    var k := 1.0 - exp(-delta * 4.0)
    _shown_fill = lerpf(_shown_fill, fill_ratio, k)
    _shown_over = lerpf(_shown_over, overfill_ratio, k)
    _apply(delta)

func _apply(_delta: float) -> void:
    var f := clampf(_shown_fill, 0.0, 1.0)
    _mass.visible = _shown_fill > 0.02
    # screen bottom at z=-0.34 is about y=-0.26 (fov 75)
    var rise := lerpf(-0.36, -0.25, f) + 0.07 * _shown_over
    var swell := lerpf(0.55, 1.0, f) * (1.0 + 0.45 * _shown_over)
    var pulse := 1.0 + sin(_time * (2.2 + 3.0 * _shown_over)) * (0.02 + 0.05 * _shown_over)
    _mass.position = Vector3(0, rise, -0.34)
    _mass.scale = Vector3(swell * pulse, swell / pulse, swell)
    var count := int(round(_shown_over * PILE_MAX))
    for i in range(_pile.size()):
        _pile[i].visible = i < count
        if _pile[i].visible:
            _pile[i].scale = Vector3.ONE * (1.0 + sin(_time * 3.0 + i) * 0.04)
