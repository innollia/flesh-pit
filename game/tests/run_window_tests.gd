extends SceneTree

## Real window resize from the settings menu, and the saved size surviving a
## restart. Needs a real window (NOT --headless):
##   Godot_console.exe --windowed --resolution 1280x720 --path <project> --script tests/run_window_tests.gd

const TEST_SETTINGS := "user://test_window_settings.json"

var _failures := 0
var _passed := 0
var _m: Node3D
var _frame := 0
var _want := Vector2i.ZERO

func _assert(c: bool, msg: String) -> void:
    if c:
        _passed += 1
    else:
        _failures += 1
        print("FAIL: %s" % msg)

func _init() -> void:
    print("=== flesh-pit window tests ===")
    _m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
    get_root().add_child(_m)

func _process(_d: float) -> bool:
    _frame += 1
    if DisplayServer.get_name() == "headless":
        print("--- skipped (headless) ---")
        quit(0)
        return true
    match _frame:
        5:
            _m.settings_menu.save_path = TEST_SETTINGS
            _m.settings_menu.set_value("window_mode", "windowed")
            _m.settings_menu.set_value("resolution", "1600x900")
            _want = FPSettings.windowed_size(_m.settings_menu.settings)
        10:
            _assert(DisplayServer.window_get_size() == _want, "menu resize applies at once (%s vs %s)" % [DisplayServer.window_get_size(), _want])
            var scr := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
            var mid := DisplayServer.window_get_position() + _want / 2
            _assert(absi(mid.x - (scr.position.x + scr.size.x / 2)) <= 2, "window centred")
            _assert(FPSettings.load_from(TEST_SETTINGS)["resolution"] == "1600x900", "resolution saved")
            # "Restart": shrink the window, then apply what the file says.
            DisplayServer.window_set_size(Vector2i(1152, 648))
        12:
            FPSettings.apply_window(FPSettings.load_from(TEST_SETTINGS))
        16:
            _assert(DisplayServer.window_get_size() == _want, "saved size restored after restart")
            _m.settings_menu.set_value("window_mode", "fullscreen")
        24:
            _assert(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "fullscreen mode applies")
            _m.settings_menu.set_value("window_mode", "windowed")
            _m.settings_menu.set_value("resolution", "1280x720")
            _want = FPSettings.windowed_size(_m.settings_menu.settings)
        34:
            _assert(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "back to windowed")
            _assert(DisplayServer.window_get_size() == _want, "size right after leaving fullscreen (%s)" % DisplayServer.window_get_size())
            if FileAccess.file_exists(TEST_SETTINGS):
                DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
            _m.queue_free()
            print("--- %d passed, %d failed ---" % [_passed, _failures])
            quit(1 if _failures > 0 else 0)
            return true
    return false