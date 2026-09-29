extends SceneTree

## W04 captures, run WINDOWED with the movie writer (never headless):
##   Godot_console --path game --windowed --resolution 1280x720
##     --write-movie <dir>/f.png --fixed-fps 10 --quit-after 30
##     --script res://tests/capture_settlement.gd -- <shot>
## Shots: settle (looking into the bowl before the lever, no text/numbers),
## tank (after the lever, tank lid open, teeth piled inside).

var _main: Node3D
var _shot := "settle"
var _frame := 0

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() > 0:
        _shot = args[0]
    _main = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
    get_root().add_child(_main)

func _process(_d: float) -> bool:
    _frame += 1
    if _frame == 3:
        var m = _main
        m.finish_opening()
        m.restroom.set_door_open(false, true)
        m.player.global_position = m.restroom.toilet.global_position + Vector3(0, 0.9, 0.6)
        m.stomach.add_flesh(90.0)
        m.progression.on_flesh_eaten(0, 90)
        m.request_vomit()
        if _shot == "tank":
            m.flush()
            m.progression.teeth += 24
            m.restroom.set_tank_open(true, true)
            var tank: Vector3 = (m.restroom.tank_art as Node3D).global_position if m.restroom.tank_art != null else m.restroom.toilet.global_position + Vector3(0, 0.95, -0.05)
            var eye := tank + Vector3(0.0, 0.7, 0.35)
            var cam: Camera3D = m.settle_camera
            cam.global_position = eye
            cam.look_at(tank, Vector3.UP)
            cam.current = true
    return false