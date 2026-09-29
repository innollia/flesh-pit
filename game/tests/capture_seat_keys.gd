extends SceneTree

## Capture: seated on the toilet, and the Esc key settings screen.
## Run WINDOWED with the movie writer (never headless):
##   Godot_console --path game --windowed --resolution 1280x720
##     --write-movie <dir>/f.png --fixed-fps 10 --quit-after 30
##     --script res://tests/capture_seat_keys.gd -- <seat|keys|wait>

var _main: Node3D
var _frame := 0
var _shot := "keys"

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    if not args.is_empty():
        _shot = args[0]
    _main = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
    get_root().add_child(_main)

func _process(_d: float) -> bool:
    _frame += 1
    if _frame == 3:
        var m = _main
        m.finish_opening()
        m.reset_keybinds()
        if _shot == "seat":
            m.sit_down()
        else:
            m.open_keybind_menu()
            if _shot == "wait":
                m.keybind_menu.start_wait("fp_interact")
    return false