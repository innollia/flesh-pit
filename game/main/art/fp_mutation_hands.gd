extends Node3D

## Tumor-mutation variants on the kit's first-person hands (FDKHandsRig):
##   extra_arm      - a third arm pushing in from below between the two
##   palm_mouth     - a lipped mouth with teeth opening in the RIGHT palm
##   swollen_torso  - a bloated, veined belly/chest bulging up into view
## Origin = the eye (the rig sits here exactly as under the camera).
## Public: set_mutation(kind, on), play_mouth(), set_mouth_open(0..1),
## rig() -> FDKHandsRig.

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
    var skin_mat := FDKPs1Material.get_material("res://addons/flesh_dig_kit/textures/tex_skin_128.png", 6.0, false, 0.32, 0.55, 0.18)
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
    return {"cam_pos": Vector3(0, 0, 0.0001), "look_at": Vector3(0, -0.12, -0.5), "env": "dark", "fov": 70.0}