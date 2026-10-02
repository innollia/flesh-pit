extends Node3D

## Tumor-mutation variants on the kit's first-person hands (FDKHandsRig):
##   extra_arm      - a third arm pushing in from below between the two
##   palm_mouth     - a lipped mouth with teeth opening in the RIGHT palm
##   swollen_torso  - a bloated, veined belly/chest bulging up into view
## Origin = the eye (the rig sits here exactly as under the camera).
## Hair-bought mutations that reshape the hands (05-mutations.md) are put on
## ANY FDKHandsRig with apply_shape(rig, ids): wider palm (M07), webbing
## (M08), thick yellow nails (M09), a longer finger joint (M10), thick
## forearm (M12), suction wrinkles (M13), muscle (M14), mole spade (M18),
## plated left forearm (M21), twitching left hand (M22), bristles (M23),
## finger buds (M26), boneless left arm (M28); M27 hangs a trunk tip at the
## bottom of the view. Only shapes change, never the rig's poses or grab.
## Public: set_mutation(kind, on), play_mouth(), set_mouth_open(0..1),
## rig() -> FDKHandsRig, apply_all(rigs, ids), set_trunk_target(dir).

const TUMOR_KIND := {"T2": "extra_arm", "T3": "palm_mouth", "T4": "swollen_torso"}

const K := preload("res://main/art/fp_art_kit.gd")
var _rig: FDKHandsRig
var _extra: Node3D
var _mouth: Node3D
var _jaw: Node3D
var _torso: MeshInstance3D
var _time := 0.0
var _mouth_open := 0.4

func _ready() -> void:
    _rig = FDKHandsRig.new()
    _rig.name = "HandsRig"
    add_child(_rig)
    _rig.build()
    var skin_mat := FDKSkinMaterial.make(0.18)
    # extra arm: a copy of the right hand's whole chain, entering from below
    var src := _rig.get_hand_root("right")
    _extra = src.duplicate() as Node3D
    _extra.name = "ExtraArm"
    _rig.add_child(_extra)
    _extra.visible = false
    # palm mouth on the right wrist/palm
    var wrist := src.get_node("Wrist") as Node3D
    _mouth = K.pivot(wrist, "PalmMouth", Vector3(0, -0.02, -0.05))
    var st := K.begin()
    var lip := Color(0.62, 0.22, 0.24)
    var inner := Color(0.25, 0.02, 0.04)
    for sy in [-1, 1]:
        var arc: Array = []
        for i in range(7):
            var a := PI * i / 6.0
            arc.append(Vector3(cos(a) * 0.024, 0, sy * sin(a) * 0.012 - sy * 0.001))
        K.tube(st, Transform3D.IDENTITY, arc, [0.004, 0.006, 0.007, 0.007, 0.007, 0.006, 0.004], 5, [lip])
    K.blob(st, Transform3D.IDENTITY, Vector3(0, 0.004, 0), Vector3(0.02, 0.004, 0.01), 0.1, 3, inner, inner)
    K.add_mesh(_mouth, "Lips", K.finish(st, 8.0), skin_mat)
    _jaw = K.pivot(_mouth, "Teeth")
    st = K.begin()
    for sy in [-1, 1]:
        for i in range(6):
            var x := -0.016 + i * 0.0064
            K.lathe(st, K.T(Vector3(x, -0.002, sy * 0.006), Vector3(0, 0, 180)), [Vector2(0.0, -0.001), Vector2(0.0028, -0.001), Vector2(0.0022, 0.005), Vector2(0.0, 0.006)], 4, [Color(0.95, 0.9, 0.75)])
    K.add_mesh(_jaw, "TeethMesh", K.finish(st, 20.0), K.mat("tex_ceramic_64.png", 0.4, true))
    _mouth.visible = false
    # swollen torso: bloated mass low in the view, with dark veins
    st = K.begin()
    K.blob(st, Transform3D.IDENTITY, Vector3(0, -0.46, -0.2), Vector3(0.3, 0.2, 0.22), 0.18, 77, Color(0.84, 0.66, 0.58), Color(0.72, 0.5, 0.48))
    for v in range(5):
        var pts: Array = []
        for k in range(6):
            var t := float(k) / 5.0
            var a := -1.2 + v * 0.6 + sin(t * 4.0 + v) * 0.15
            pts.append(Vector3(sin(a) * 0.3 * (0.9 + t * 0.1), -0.46 + 0.19 * cos(t * 1.4), -0.2 - cos(a) * 0.22 * 0.6 + t * 0.02))
        K.tube(st, Transform3D.IDENTITY, pts, [0.004, 0.006, 0.005, 0.006, 0.004, 0.002], 3, [Color(0.35, 0.18, 0.35)])
    _torso = K.add_mesh(self, "SwollenTorso", K.finish(st, 5.0), skin_mat)
    _torso.position = Vector3(0, 0.11, -0.13)
    _torso.visible = false

func rig() -> FDKHandsRig:
    return _rig

func set_mutation(kind: String, on: bool) -> void:
    kind = String(TUMOR_KIND.get(kind, kind))
    match kind:
        "extra_arm":
            _extra.visible = on
        "palm_mouth":
            _mouth.visible = on
        "swollen_torso":
            _torso.visible = on

func set_mouth_open(t: float) -> void:
    _mouth_open = clampf(t, 0.0, 1.0)
    _mouth.scale = Vector3(1.0, 1.0, lerpf(0.5, 1.6, _mouth_open))

func play_mouth() -> void:
    var tw := create_tween()
    tw.tween_method(set_mouth_open, 0.2, 1.0, 0.25)
    tw.tween_method(set_mouth_open, 1.0, 0.1, 0.15)
    tw.tween_method(set_mouth_open, 0.1, 0.4, 0.3)

func _process(delta: float) -> void:
    _time += delta
    _animate_shapes(delta)
    if _extra != null and _extra.visible:
        var src := _rig.get_hand_root("right")
        # mirror the right hand's pose, lowered and pushed inward and forward
        _extra.transform = src.transform.translated(Vector3(-0.1, -0.1, -0.03)).rotated_local(Vector3.FORWARD, 0.5)
        for jn in ["Wrist", "Wrist/Finger1", "Wrist/Finger1/Finger2", "Wrist/Thumb1"]:
            (_extra.get_node(jn) as Node3D).transform = (src.get_node(jn) as Node3D).transform
    if _mouth.visible:
        set_mouth_open(0.45 + sin(_time * 2.2) * 0.35)

func capture_setup() -> Dictionary:
    set_mutation("extra_arm", true)
    set_mutation("palm_mouth", true)
    set_mutation("swollen_torso", true)
    # turn the right palm up so the mouth faces the eye
    var w := _rig.get_hand_root("right").get_node("Wrist") as Node3D
    w.rotation_degrees.z = 150.0
    _rig.set_process(false)
    return {"cam_pos": Vector3(0, 0, 0.0001), "look_at": Vector3(0, -0.12, -0.5), "env": "dark", "fov": 70.0, "fill_energy": 0.3}
# --- hair mutations on the hands ------------------------------------------------

var _shaped: Array = [] ## rigs carrying shape mutations
var _shape_ids: Array = []
var _trunk: Node3D
var _trunk_target := Vector3.ZERO

func apply_all(rigs: Array, ids: Array) -> void:
    _shape_ids = ids.duplicate()
    _shaped.clear()
    for r in rigs:
        if r != null:
            apply_shape(r, ids)
            _shaped.append(r)
    _set_trunk("M27" in ids)

static func _seg(rig: Node3D, side: String, path: String) -> Node3D:
    var root := "HandRight" if side == "right" else "HandLeft"
    return rig.get_node_or_null(root if path == "" else root + "/" + path) as Node3D

static func _rescale(n: Node3D, s: Vector3) -> void:
    if n == null:
        return
    if not n.has_meta("mut_base_scale"):
        n.set_meta("mut_base_scale", n.scale)
        n.set_meta("mut_base_pos", n.position)
        n.set_meta("mut_base_rot", n.rotation)
    n.scale = (n.get_meta("mut_base_scale") as Vector3) * s

static func _reset(rig: Node3D) -> void:
    for n in rig.find_children("*", "Node3D", true, false):
        if n.has_meta("mut_base_scale"):
            n.scale = n.get_meta("mut_base_scale")
            n.position = n.get_meta("mut_base_pos")
            n.rotation = n.get_meta("mut_base_rot")
    for d in rig.find_children("MutDeco*", "", true, false):
        d.get_parent().remove_child(d)
        d.queue_free()

static func _deco(parent: Node3D, dname: String, st: SurfaceTool, col_tex: String = "tex_skin_128.png") -> MeshInstance3D:
    if parent == null:
        return null
    var mi := K.add_mesh(parent, "MutDeco_" + dname, K.finish(st, 8.0), FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/" + col_tex, 6.0, false, 0.32, 0.55, 0.18))
    return mi

## Reshape one rig for the given mutation ids (idempotent).
static func apply_shape(rig: Node3D, ids: Array) -> void:
    _reset(rig)
    var I := Transform3D.IDENTITY
    var skin := Color(0.88, 0.72, 0.62)
    var skin_d := Color(0.75, 0.58, 0.5)
    var both := ["right", "left"]
    for side in both:
        var bulk := 1.15 if "M14" in ids else 1.0
        var fa_s := Vector3.ONE * bulk
        if side == "right" and "M12" in ids:
            fa_s *= Vector3(1.55, 1.55, 1.0)
        if side == "left" and "M28" in ids:
            fa_s *= Vector3(0.78, 0.7, 1.0)
        _rescale(_seg(rig, side, "Forearm"), fa_s)
        var palm_s := Vector3.ONE * bulk
        if side == "right" and "M07" in ids:
            palm_s *= Vector3(1.32, 1.05, 1.08)
        if side == "right" and "M18" in ids:
            palm_s *= Vector3(1.45, 0.8, 1.12)
        _rescale(_seg(rig, side, "Wrist/Palm"), palm_s)
        var fw := palm_s.x
        for p in ["Wrist/Finger1/Seg", "Wrist/Finger1/Finger2/Seg", "Wrist/Finger1/Finger2/Finger3/Seg"]:
            _rescale(_seg(rig, side, p), Vector3(fw, bulk, 1.0))
        if side == "right" and "M18" in ids:
            var palm := _seg(rig, side, "Wrist/Palm")
            if palm != null:
                palm.rotation.z = (palm.get_meta("mut_base_rot") as Vector3).z + deg_to_rad(-22.0)
    # M10: one finger joint grows longer (reach +0.4 m)
    if "M10" in ids:
        _rescale(_seg(rig, "right", "Wrist/Finger1/Finger2/Seg"), Vector3((1.32 if "M07" in ids else 1.0), 1.0, 1.55))
        var f3 := _seg(rig, "right", "Wrist/Finger1/Finger2/Finger3")
        if f3 != null:
            _rescale(f3, Vector3.ONE)
            f3.position = (f3.get_meta("mut_base_pos") as Vector3) * 1.55
    var st: SurfaceTool
    if "M08" in ids: # webbing between thumb and finger block
        st = K.begin()
        K.tri(st, I, Vector3(-0.036, -0.004, -0.02), Vector3(-0.045, -0.002, -0.09), Vector3(-0.07, -0.006, -0.06), Vector3.UP, Color(0.95, 0.62, 0.58))
        K.tri(st, I, Vector3(-0.036, -0.004, -0.02), Vector3(-0.07, -0.006, -0.06), Vector3(-0.045, -0.002, -0.09), Vector3.DOWN, Color(0.9, 0.55, 0.52))
        _deco(_seg(rig, "right", "Wrist"), "Web", st)
    if "M09" in ids: # thick yellow nails on the finger block tip
        st = K.begin()
        for i in range(4):
            var x := -0.033 + i * 0.022
            K.rbox(st, K.T(Vector3(x, 0.02, -0.012)), Vector3(0.0095, 0.0045, 0.012), 0.002, Color(0.86, 0.76, 0.32), Color(0.66, 0.55, 0.2))
        _deco(_seg(rig, "right", "Wrist/Finger1/Finger2/Finger3"), "Nails", st, "tex_ceramic_64.png")
    if "M13" in ids: # suction wrinkles on the palm side
        st = K.begin()
        for k in range(5):
            var z := -0.012 - k * 0.014
            K.tube(st, I, [Vector3(-0.036, -0.024, z), Vector3(0.0, -0.028, z - 0.003), Vector3(0.036, -0.024, z)], [0.0025, 0.003, 0.0025], 4, [skin_d])
        _deco(_seg(rig, "right", "Wrist"), "Wrinkles", st)
    if "M21" in ids: # plate muscle bands on the left forearm
        st = K.begin()
        for k in range(5):
            K.rbox(st, K.T(Vector3(0, 0.03, 0.06 + k * 0.05)), Vector3(0.03, 0.006, 0.016), 0.003, Color(0.8, 0.6, 0.52), Color(0.6, 0.42, 0.36))
        _deco(_seg(rig, "left", ""), "Plates", st)
    if "M23" in ids: # stiff bristles along both forearms
        for side in both:
            st = K.begin()
            for k in range(14):
                var z := 0.03 + k * 0.022
                var x := sin(k * 2.3) * 0.022
                K.tube(st, I, [Vector3(x, 0.03, z), Vector3(x * 1.3, 0.055, z + 0.01)], [0.0016, 0.0006], 3, [Color(0.12, 0.09, 0.07)], false)
            _deco(_seg(rig, side, ""), "Bristles", st)
    if "M26" in ids: # tiny fingers budding on the right hand's edge
        st = K.begin()
        for k in range(3):
            K.tube(st, I, [Vector3(0.046, 0.0, -0.03 - k * 0.02), Vector3(0.058, 0.004, -0.034 - k * 0.02)], [0.005, 0.0035], 4, [skin])
        _deco(_seg(rig, "right", "Wrist"), "Buds", st)
    if "M14" in ids: # muscle knots on the forearms
        for side in both:
            st = K.begin()
            K.blob(st, I, Vector3(0, 0.02, 0.16), Vector3(0.04, 0.03, 0.07), 0.3, 91, skin, skin_d)
            _deco(_seg(rig, side, ""), "Muscle", st)

func _set_trunk(on: bool) -> void:
    if on and _trunk == null:
        _trunk = K.pivot(self, "Trunk", Vector3(0, -0.07, -0.05))
        var st := K.begin()
        var pts: Array = []
        for k in range(7):
            var t := float(k) / 6.0
            pts.append(Vector3(0, -t * 0.12, -t * 0.12 - t * t * 0.05))
        K.tube(st, Transform3D.IDENTITY, pts, [0.03, 0.028, 0.025, 0.022, 0.019, 0.016, 0.013], 8, [Color(0.86, 0.7, 0.6), Color(0.75, 0.58, 0.5)])
        K.add_mesh(_trunk, "TrunkMesh", K.finish(st, 5.0), FDKSkinMaterial.make(0.18))
    if _trunk != null:
        _trunk.visible = on

func has_trunk() -> bool:
    return _trunk != null and _trunk.visible

## M27: camera-local direction to the nearest tumor within 10 m (ZERO = none).
func set_trunk_target(dir: Vector3) -> void:
    _trunk_target = dir

func _animate_shapes(delta: float) -> void:
    if _trunk != null and _trunk.visible:
        var twitch := 0.0
        if _trunk_target != Vector3.ZERO:
            twitch = sin(_time * 14.0) * 0.12
            _trunk.rotation.y = lerpf(_trunk.rotation.y, clampf(-_trunk_target.x, -0.6, 0.6) + twitch, 1.0 - exp(-delta * 8.0))
        else:
            _trunk.rotation.y = lerpf(_trunk.rotation.y, 0.0, 1.0 - exp(-delta * 3.0))
    for r in _shaped:
        if not is_instance_valid(r):
            continue
        if "M22" in _shape_ids:
            var seg := _seg(r, "left", "Wrist/Finger1/Seg")
            if seg != null:
                seg.rotation.x = sin(_time * 11.0) * 0.18 * maxf(0.0, sin(_time * 0.9))
        if "M28" in _shape_ids:
            var fa := _seg(r, "left", "Forearm")
            if fa != null:
                fa.rotation.z = sin(_time * 2.0) * 0.08
