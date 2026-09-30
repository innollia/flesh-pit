extends SceneTree

## Title screen, settings, pause - frames for review.
## Godot.exe --path <project> --windowed --resolution 1280x720 --write-movie <dir>/f.png --fixed-fps 10 --quit-after 70 --script tests/capture_menus.gd
## Frames: ~12 title, ~27 settings (over title), ~42 confirm, ~60 pause.

var _m: Node3D
var _f := 0

func _init() -> void:
    for a in OS.get_cmdline_user_args():
        if a.contains("x"):
            var wh := a.split("x")
            var sz := Vector2i(int(wh[0]), int(wh[1]))
            DisplayServer.window_set_size(sz)
            get_root().size = sz
    _m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
    _m.save_path = "user://capture_save.bin"
    get_root().add_child(_m)

func _process(_d: float) -> bool:
    _f += 1
    match _f:
        3:
            _m.finish_opening()
            _m.save_to_disk()
            _m.show_title()
        20:
            _m.open_settings()
            _m.settings_menu.sliders["music"].grab_focus()
        33:
            _m.settings_menu.close()
            _m.title_screen.request_new_game()
        48:
            _m.title_screen._show_confirm(false)
            _m.title_screen.close()
            _m._leave_title()
            _m.finish_opening()
        52:
            _m.open_pause_menu()
        65:
            DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture_save.bin"))
    return false