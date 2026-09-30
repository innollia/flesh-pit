extends SceneTree

## Hand motion captures, run WINDOWED with the movie writer (never headless):
##   Godot_console --path game --windowed --resolution 1280x720
##     --write-movie <dir>/f.png --fixed-fps 10 --quit-after 40
##     --script res://tests/capture_motions.gd -- <shot>
## Shots: pour, take, vomit_toilet, vomit_floor, wash, belt, cycle.

var _m: Node3D
var _shot := "take"
var _frame := 0

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() > 0:
        _shot = args[0]
    _m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
    get_root().add_child(_m)

func _face(yaw: float, pitch: float) -> void:
    _m.player.set("_yaw", yaw)
    _m.player.rotation.y = yaw
    _m.player.set("_pitch", pitch)
    _m.player.camera_pivot.rotation.x = pitch
    _m.player.camera.current = true

func _look_at_point(p: Vector3) -> void:
    var eye: Vector3 = _m.player.camera.global_position
    var d := p - eye
    _face(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))

func _process(_d: float) -> bool:
    _frame += 1
    var m = _m
    if _frame == 3:
        m.finish_opening()
        m.restroom.set_door_open(false, true)
        match _shot:
            "pour", "take":
                m.player.global_position = m.restroom.toilet.global_position + Vector3(0, 0.9, 0.6)
                m.progression.teeth_in_hand = 30
                m.vent.open(30)
                m.vent.close()
                m.vent.open(30)
            "vomit_toilet":
                m.player.global_position = m.restroom.toilet.global_position + Vector3(0, 0.9, 0.6)
                m.stomach.add_flesh(90.0)
                m.progression.on_flesh_eaten(0, 90)
            "vomit_floor":
                m.player.global_position = Vector3(0.2, 0.9, 0.9)
                _face(0.0, -0.1)
                m.stomach.add_flesh(90.0)
                m.progression.on_flesh_eaten(0, 90)
            "wash":
                m.player.global_position = Vector3(-FPRestroom.HALF.x + 0.75, 0.9, -0.35)
                _face(PI * 0.5, -0.5)
                m.hand_blood = 0.9
            "belt", "cycle":
                m.player.global_position = Vector3(0.2, 0.9, 0.9)
                m.progression.grant_item("knife")
                m.progression.grant_item("blender")
                _face(0.0, -0.1 if _shot == "cycle" else -1.25)
    if _frame == 5:
        match _shot:
            "pour", "take":
                _look_at_point(m.vent.global_position)
                if _shot == "pour":
                    m.place_teeth_at_vent()
                else:
                    m.place_teeth_at_vent()
            "vomit_toilet", "vomit_floor":
                m.request_vomit()
            "wash":
                m.wash_hands()
            "belt":
                var found := false
                for yi in range(-12, 13):
                    for pi in range(0, 12):
                        _face(yi * 0.08, -1.05 - pi * 0.04)
                        m.player.force_update_transform()
                        m.player.camera.force_update_transform()
                        if m.belt_swap.aimed_hook() == 1:
                            found = true
                            break
                    if found:
                        break
                if not (found and m.belt_swap.begin()):
                    m.hand_motions.play_belt(1)
            "cycle":
                m.cycle_tool()
    if _frame == 16 and _shot == "take":
        var best := Vector3.ZERO
        for n in m.vent.offer_nodes():
            best = (n as Node3D).global_position
        _look_at_point(best + Vector3(0, -0.05, 0))
        m.take_vent_offer()
    if _frame >= 4:
        var cam: Camera3D = m.get_viewport().get_camera_3d()
        var rigs: Array = [m.hands_rig]
        if m.hand_motions.rim_rig != null and m.hand_motions.rim_rig.visible:
            rigs.append(m.hand_motions.rim_rig)
        var line := "SHOT %s f%d %s u=%.2f cam=%s" % [_shot, _frame, m.hand_motions.kind, m.hand_motions.progress(), cam.name]
        for r in rigs:
            for side in ["right", "left"]:
                var h: Node3D = r.call("get_hand_root", side)
                var on: bool = r.is_visible_in_tree() and not cam.is_position_behind(h.global_position)
                var sp: Vector2 = cam.unproject_position(h.global_position) if on else Vector2(-1, -1)
                line += " %s%s=(%d,%d)" % [str(r.name).left(4), side.left(1), int(sp.x), int(sp.y)]
        print(line)
    return false
