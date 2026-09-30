extends SceneTree

## Situational hand motion tests (fp_hand_motions.gd): each motion starts,
## moves the hands (or the body camera), ends back at rest, and a cancel
## mid-way glides the hands home. Covers scoop, pour, take (one / two
## hands), toilet and floor vomit, wash (blood fades while rubbing), belt
## swap reach and the Tab cycle dip.
## Run: Godot_console.exe --headless --path <project> --script tests/run_motion_tests.gd

var _failures := 0
var _passed := 0
var _m: Node3D
var _frame := 0

func _assert(c: bool, msg: String) -> void:
    if c:
        _passed += 1
    else:
        _failures += 1
        print("FAIL: %s" % msg)

func _init() -> void:
    print("=== flesh-pit hand motion tests ===")
    _m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
    get_root().add_child(_m)

func _process(_d: float) -> bool:
    _frame += 1
    if _frame == 2:
        _m.finish_opening()
    if _frame < 6:
        return false
    _run()
    _m.queue_free()
    print("--- %d passed, %d failed ---" % [_passed, _failures])
    quit(1 if _failures > 0 else 0)
    return true

func _right() -> Vector3:
    return (_m.hands_rig.call("get_hand_root", "right") as Node3D).position

func _left() -> Vector3:
    return (_m.hands_rig.call("get_hand_root", "left") as Node3D).position

## Advance motions + rig together.
func _step(sec: float) -> void:
    var n := int(ceil(sec / (1.0 / 60.0)))
    for i in range(n):
        _m.hand_motions.tick(1.0 / 60.0)
        _m.hands_rig.call("step", 1.0 / 60.0)

func _settle() -> void:
    _step(0.6)

func _run() -> void:
    var hm: FPHandMotions = _m.hand_motions
    _assert(hm != null and _m.hands_rig.get("pose_hook") == null or not hm.busy(), "motions exist, idle at start")
    _settle()
    var r0 := _right()
    var l0 := _left()
    var cam0: Vector3 = _m.player.camera.position
    var rot0: Vector3 = _m.player.camera.rotation

    # 1 scoop + pour
    hm.play_scoop()
    _assert(hm.busy() and hm.kind == "scoop", "scoop starts")
    _step(FPHandMotions.DUR["scoop"] * 0.5)
    _assert(_right().y < r0.y - 0.06, "scoop: the right hand dips into the tank")
    _step(FPHandMotions.DUR["scoop"])
    _settle()
    _assert(not hm.busy() and _right().distance_to(r0) < 0.02, "scoop: the hand is back")
    hm.play_pour(12)
    _step(FPHandMotions.DUR["pour"] * 0.62)
    _assert(_right().z < r0.z - 0.12, "pour: the arm reaches out to the grate")
    var roll: float = _m.hands_rig.call("get_joint_angles", "right")["wrist_roll"]
    _assert(roll < -20.0, "pour: the wrist turns to spill (%.0f)" % roll)
    _step(FPHandMotions.DUR["pour"])
    _settle()
    _assert(not hm.busy() and _right().distance_to(r0) < 0.02, "pour: the hand is back")

    # 2 take: small = one hand, big = both
    var at: Vector3 = _m.hands_rig.to_global(Vector3(0.05, 0.1, -0.7))
    hm.play_take(at, "spray_cheap")
    _assert(hm.kind == "take", "a spray is taken with one hand")
    _step(FPHandMotions.DUR["take"] * 0.52)
    _assert(_right().z < r0.z - 0.15 and _left().distance_to(l0) < 0.03, "take: only the right hand reaches")
    var curl: float = _m.hands_rig.call("get_joint_angles", "right")["f2"]
    _assert(curl > 45.0, "take: the fingers curl round it (%.0f)" % curl)
    _step(FPHandMotions.DUR["take"])
    _settle()
    _assert(not hm.busy() and _right().distance_to(r0) < 0.02, "take: pulled back to rest")
    hm.play_take(at, "saw_box")
    _assert(hm.kind == "take2", "a saw box needs both hands")
    _step(FPHandMotions.DUR["take2"] * 0.45)
    _assert(_left().z < l0.z - 0.15 and _right().z < r0.z - 0.15, "take2: both hands reach")
    _step(FPHandMotions.DUR["take2"])
    _settle()

    # 3 vomit on the floor: bow, heaves, straighten
    hm.play_vomit(false, 0.8)
    _step(FPHandMotions.DUR["vomit_floor"] * 0.4)
    _assert(_m.player.camera.position.y < cam0.y - 0.25, "floor vomit: the body bows down")
    _assert(_m.player.camera.rotation.x < rot0.x - 0.4, "floor vomit: the view tips toward the floor")
    _assert(absf(_m.player.camera.rotation.z) < 0.03, "camera shake stays small")
    var spills := 0
    for c in _m.get_children():
        if c.name.begins_with("Spill"):
            spills += 1
    _assert(spills > 0, "flesh falls out on a heave (%d)" % spills)
    _step(FPHandMotions.DUR["vomit_floor"])
    _assert(not hm.busy() and _m.player.camera.position.distance_to(cam0) < 0.001 and _m.player.camera.rotation.distance_to(rot0) < 0.001, "floor vomit: standing up again, camera exact")

    # 3b vomit at the toilet: bowl camera leans in, rim hands grip
    var sc: Camera3D = _m.settle_camera
    var sc0: Transform3D = sc.transform
    hm.play_vomit(true, 0.8)
    _assert(hm.rim_rig != null and hm.rim_rig.visible, "toilet vomit: hands on the rim appear")
    _step(FPHandMotions.DUR["vomit_toilet"] * 0.05)
    _assert(sc.transform.origin.distance_to(sc0.origin) > 0.1, "toilet vomit: starts upright above the bowl")
    _step(FPHandMotions.DUR["vomit_toilet"] * 0.45)
    var rim: Node3D = hm.rim_rig.call("get_hand_root", "left")
    _assert(rim.position.y > -0.3, "toilet vomit: the hands hold the rim in view (%.2f)" % rim.position.y)
    _step(FPHandMotions.DUR["vomit_toilet"])
    _assert(not hm.busy() and sc.transform.origin.distance_to(sc0.origin) < 0.001 and not hm.rim_rig.visible, "toilet vomit: back to the bowl view, rim hands gone")

    # 5 wash: blood fades while rubbing, W13 rule value already 0
    _m.hand_blood = 0.8
    _m.wash_hands()
    _assert(hm.kind == "wash" and _m.hand_blood == 0.0, "wash: the rule clears the blood at once")
    _assert(hm.blood_visual() > 0.7, "wash: the hands still look bloody at the start")
    _step(FPHandMotions.DUR["wash"] * 0.06)
    _assert(_right().x < r0.x - 0.08, "wash: the right hand goes to the tap")
    _step(FPHandMotions.DUR["wash"] * 0.4)
    _assert(absf(_right().x - _left().x) < 0.15, "wash: both hands together under the stream")
    var rub_a := _right().x
    _step(0.12)
    _assert(absf(_right().x - rub_a) > 0.005, "wash: the hands rub")
    _step(FPHandMotions.DUR["wash"] * 0.3)
    _assert(hm.blood_visual() < 0.05, "wash: the blood is gone after rubbing")
    _step(FPHandMotions.DUR["wash"])
    _settle()
    _assert(not hm.busy() and _right().distance_to(r0) < 0.02, "wash: hands back")

    # 4 cancel mid-way: wash cut short keeps the unwashed blood, hands glide home
    _m.hand_blood = 0.9
    _m.wash_hands()
    _step(FPHandMotions.DUR["wash"] * 0.35)
    hm.cancel()
    _assert(_m.hand_blood > 0.2, "cancelled wash: the blood that was not rubbed off stays (%.2f)" % _m.hand_blood)
    var mid := _right()
    _step(FPHandMotions.CANCEL_TIME * 0.5)
    _assert(_right().distance_to(r0) < mid.distance_to(r0), "cancel: the hand is on its way back")
    _step(FPHandMotions.CANCEL_TIME)
    _settle()
    _assert(not hm.busy() and _right().distance_to(r0) < 0.02, "cancel: the hand is home")
    hm.play_vomit(false, 0.5)
    _step(FPHandMotions.DUR["vomit_floor"] * 0.3)
    hm.cancel()
    _step(FPHandMotions.CANCEL_TIME + 0.05)
    _assert(not hm.busy() and _m.player.camera.position.distance_to(cam0) < 0.001, "cancelled vomit: the body straightens")
    hm.play_take(at, "knife")
    _step(0.2)
    hm.cancel()
    _step(FPHandMotions.CANCEL_TIME + 0.05)
    _settle()
    _assert(_right().distance_to(r0) < 0.02, "cancelled take: hand home")
    _m.hand_blood = 0.0

    # 6 belt swap reach and Tab cycle
    _assert(FPBeltSwap.SWAP_TIME >= 0.6 and FPBeltSwap.SWAP_TIME <= 0.9, "belt swap lasts 0.6-0.9 s")
    hm.play_belt(0)
    _assert(hm.kind == "belt" and is_equal_approx(hm.dur, FPBeltSwap.SWAP_TIME), "belt motion matches the swap time")
    _step(FPBeltSwap.SWAP_TIME * 0.2)
    var grip0: float = _m.hands_rig.call("get_joint_angles", "right")["f2"]
    _step(FPBeltSwap.SWAP_TIME * 0.3)
    var open0: float = _m.hands_rig.call("get_joint_angles", "right")["f2"]
    _assert(open0 < grip0 - 15.0, "belt: the hand lets go of the tool at the hook (%.0f -> %.0f)" % [grip0, open0])
    _step(FPBeltSwap.SWAP_TIME * 0.25)
    var grip1: float = _m.hands_rig.call("get_joint_angles", "right")["f2"]
    _assert(grip1 > open0 + 15.0, "belt: and closes on the other tool")
    _step(FPBeltSwap.SWAP_TIME)
    _settle()
    _assert(not hm.busy(), "belt motion ends")
    _m.progression.grant_item("knife")
    _m.cycle_tool()
    _assert(hm.kind == "cycle", "Tab cycling plays the short dip")
    _step(FPHandMotions.DUR["cycle"] * 0.5)
    _assert(_right().y < r0.y - 0.1, "cycle: the hand dips out of view")
    _step(FPHandMotions.DUR["cycle"])
    _settle()
    _assert(not hm.busy() and _right().distance_to(r0) < 0.02, "cycle: back")