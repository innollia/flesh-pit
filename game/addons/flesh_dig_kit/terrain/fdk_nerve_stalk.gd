class_name FDKNerveStalk
extends Node3D

## A yellow nerve that sticks out of a flesh wall and wriggles like a garden
## eel (docs/spec/02-world-tissue.md: nerves are conspicuous, yellow, protruding, moving).
## Low-poly: a chain of tapered octagonal segments plus a knobbed tip, each
## segment on its own joint so the whole stalk sways in a travelling wave.
## Place it on a wall with `normal` = wall outward direction. If `terrain` is
## set, the stalk hides itself once the tissue at its base is eaten.

@export var length: float = 0.55
@export var radius: float = 0.035
@export var segments: int = 6
@export var color_a: Color = Color(0.95, 0.82, 0.18)
@export var color_b: Color = Color(0.78, 0.6, 0.08)
@export var wiggle_speed: float = 2.4
@export var wiggle_amount: float = 16.0

var terrain: Node = null
var base_probe: Vector3 = Vector3.ZERO
var _joints: Array[Node3D] = []
var _phase: float = 0.0
var _time: float = 0.0
var _built := false

func _ready() -> void:
    build()

## Points the stalk out of the wall along `normal`, rooted at `at`.
func place(at: Vector3, normal: Vector3) -> void:
    position = at
    var n := normal.normalized()
    var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
    var x := up.cross(n).normalized()
    var z := n.cross(x).normalized()
    basis = Basis(x, n, z)
    base_probe = at - n * 0.15

func build() -> void:
    if _built:
        return
    _built = true
    _phase = randf() * TAU
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.roughness = 0.25
    mat.metallic_specular = 0.8
    mat.emission_enabled = true
    mat.emission = Color(0.25, 0.18, 0.0)
    var seg_len := length / float(segments)
    var parent: Node3D = self
    var prof := FDKLowPoly.round_profile(6)
    for i in range(segments):
        var j := Node3D.new()
        j.name = "Seg%d" % i
        j.position = Vector3(0, 0 if i == 0 else seg_len, 0)
        parent.add_child(j)
        _joints.append(j)
        var r0 := radius * lerpf(1.25, 0.55, float(i) / segments)
        var r1 := radius * lerpf(1.25, 0.55, float(i + 1) / segments)
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        var rings := []
        for k in range(2):
            var rr := r0 if k == 0 else r1
            var y := 0.0 if k == 0 else seg_len
            var ring := PackedVector3Array()
            for p in prof:
                ring.append(Vector3(p.x * rr, y, p.y * rr))
            rings.append(ring)
        var c := color_a.lerp(color_b, float(i % 2) * 0.6)
        FDKLowPoly.loft(st, rings, [c], i == 0, false)
        if i == segments - 1:
            FDKLowPoly.add_blob(st, Vector3(0, seg_len + r1 * 0.6, 0), Vector3(r1, r1 * 1.6, r1) * 1.5, 0.25, i, color_a, color_b)
        var mi := MeshInstance3D.new()
        mi.mesh = st.commit()
        mi.material_override = mat
        j.add_child(mi)
        parent = j

signal disturbed(world_pos: Vector3)

## How strongly a disturbance shakes the stalk (added to wiggle for a burst,
## decaying back to the ambient wiggle_amount).
@export var disturb_kick: float = 55.0
@export var disturb_decay: float = 3.0

var _disturb_extra: float = 0.0

## docs/spec/02-world-tissue.md: touching/damaging a nerve can cause local tissue
## contraction/shifting, and the reaction must read as caused by the
## player's action. Call this when the chewer targets this stalk (or a cell
## adjacent to its base) instead of tearing it cleanly -- it kicks the
## wiggle amplitude up sharply (a visible flinch) and, if `terrain` supports
## dig_at, nudges nearby tissue to shift by digging a small amount at the
## stalk's own root so the wall visibly contracts/moves away from the poke.
func disturb(strength: float = 1.0) -> void:
    _disturb_extra += disturb_kick * clampf(strength, 0.0, 1.0)
    if terrain != null and terrain.has_method("dig_at"):
        # local contraction: the tissue right around the root recoils,
        # reading as the organism flinching away from the disturbance
        terrain.dig_at(base_probe, 0.12 * clampf(strength, 0.0, 1.0))
    disturbed.emit(global_position)

func _process(delta: float) -> void:
    if _disturb_extra > 0.0:
        _disturb_extra = maxf(0.0, _disturb_extra - disturb_decay * disturb_kick * delta)
    step(delta)

func step(delta: float) -> void:
    _time += delta
    for i in range(_joints.size()):
        var t := _time * wiggle_speed + _phase - float(i) * 0.7
        var a := deg_to_rad(wiggle_amount + _disturb_extra) * (0.4 + 0.6 * float(i) / _joints.size())
        _joints[i].rotation = Vector3(sin(t) * a, 0.0, cos(t * 0.8) * a * 0.7)
    if terrain != null and terrain.has_method("density_at"):
        visible = terrain.density_at(base_probe) >= 0.5
