extends SceneTree

## Art model self-tests (no GUT). Run:
##   Godot_console --path game --script tests/art/run_art_tests.gd
## For every scene in MODELS: it loads, builds real geometry, its public
## functions run without error, and it is not a bare box (many distinct
## facet normals). Exit 0 = all passed.

const MODELS := {
    "fp_vent": [["set_open", [1.0]], ["blink", []], ["set_offer_items", [["knife", "junk"]]], ["play_offer", []], ["take_item", [0]]],
    "fp_tooth_tank": [["set_lid_open", [1.0]], ["set_amount", [0.0]], ["set_amount", [1.0]], ["set_handfuls", [3]], ["play_open", []]],
    "fp_mirror": [["set_focus", [true]]],
    "fp_arm_hair": [["set_hair", [5, {"core": 3, "mantle": 2, "surface": 4}]], ["set_hair", [0, {}]]],
    "fp_blender": [["set_fill", [0.7]], ["set_spin", [true]], ["play_drink", []]],
    "fp_knife": [],
    "fp_scissors": [["set_open", [0.8]]],
    "fp_big_saw": [["set_stroke", [0.5]]],
    "fp_belt": [["set_spray_count", [2, 1]], ["set_canary", [true]]],
    "fp_tumor_bag": [["set_tumor", [true]], ["set_tumor", [false]]],
    "fp_tumor": [["set_variant", [0]], ["set_variant", [1]], ["set_variant", [2]]],
    "fp_mutation_hands": [["set_mutation", ["extra_arm", true]], ["set_mutation", ["palm_mouth", true]], ["set_mutation", ["swollen_torso", true]], ["play_mouth", []]],
    "fp_rest_container": [["set_door_open", [0.6]]],
    "fp_barrier_stages": [["set_stage", [0]], ["set_stage", [3]], ["play_break", []]],
    "fp_ending_street": [["set_roll", [0.5]], ["play_roll_away", []]],
    "fp_rolling_sphere": [["set_roll", [1.2]]],
}

var _passed := 0
var _failed := 0
var _nodes: Array = []
var _frames := 0

func _initialize() -> void:
    print("=== flesh-pit art tests ===")
    for model_name in MODELS.keys():
        var path := "res://main/art/%s.tscn" % model_name
        var ps := load(path) as PackedScene
        if ps == null:
            _fail("%s: scene does not load" % model_name)
            continue
        var n: Node = ps.instantiate()
        root.add_child(n)
        _nodes.append([model_name, n])

func _process(_delta: float) -> bool:
    _frames += 1
    if _frames == 2:
        for pair in _nodes:
            _check(pair[0], pair[1])
    if _frames == 40:
        for pair in _nodes:
            var n: Node = pair[1]
            if not is_instance_valid(n):
                _fail("%s: freed itself" % pair[0])
        print("art tests: %d passed, %d failed" % [_passed, _failed])
        quit(0 if _failed == 0 else 1)
    return false

func _check(model_name: String, n: Node) -> void:
    var normals := {}
    var tris := 0
    for mi in n.find_children("*", "MeshInstance3D", true, false):
        var m: Mesh = (mi as MeshInstance3D).mesh
        if m == null:
            continue
        for s in range(m.get_surface_count()):
            var arr := m.surface_get_arrays(s)
            var nv: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
            tris += nv.size() / 3
            for v in nv:
                normals[Vector3i(roundi(v.x * 20), roundi(v.y * 20), roundi(v.z * 20))] = true
    for mmi in n.find_children("*", "MultiMeshInstance3D", true, false):
        if (mmi as MultiMeshInstance3D).multimesh != null:
            tris += 1
    if tris < 40:
        _fail("%s: too little geometry (%d tris)" % [model_name, tris])
    elif normals.size() < 24:
        _fail("%s: reads as a box (%d distinct normals)" % [model_name, normals.size()])
    else:
        _pass("%s: %d tris, %d facet directions" % [model_name, tris, normals.size()])
    if not n.has_method("capture_setup"):
        _fail("%s: no capture_setup()" % model_name)
    for c in MODELS[model_name]:
        if not n.has_method(c[0]):
            _fail("%s: missing %s()" % [model_name, c[0]])
            continue
        n.callv(c[0], c[1])
    _pass("%s: public api ran" % model_name)

func _pass(msg: String) -> void:
    _passed += 1
    print("  PASS " + msg)

func _fail(msg: String) -> void:
    _failed += 1
    print("  FAIL " + msg)