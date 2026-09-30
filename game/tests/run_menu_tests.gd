extends SceneTree

## Title screen, settings file and Esc priority.
## Run: Godot_console.exe --headless --path <project> --script tests/run_menu_tests.gd

const TEST_SETTINGS := "user://test_settings.json"
const TEST_SAVE := "user://test_save.bin"

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
    print("=== flesh-pit menu tests ===")
    _m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
    get_root().add_child(_m)

func _process(_d: float) -> bool:
    _frame += 1
    if _frame == 2:
        _m.finish_opening()
    if _frame < 6:
        return false
    _m.save_path = TEST_SAVE
    _m.settings_menu.save_path = TEST_SETTINGS
    _settings_file()
    _settings_apply()
    _buses()
    _title()
    _esc()
    _disk_save()
    _layout()
    for p in [TEST_SETTINGS, TEST_SAVE]:
        if FileAccess.file_exists(p):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
    paused = false
    _m.queue_free()
    print("--- %d passed, %d failed ---" % [_passed, _failures])
    quit(1 if _failures > 0 else 0)
    return true

func _settings_file() -> void:
    if FileAccess.file_exists(TEST_SETTINGS):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
    var d := FPSettings.load_from(TEST_SETTINGS)
    _assert(d == FPSettings.defaults(), "no file -> defaults")
    d["master"] = 0.35
    d["music"] = 0.0
    d["mouse_sensitivity"] = 1.8
    d["invert_y"] = true
    d["fov"] = 90.0
    d["resolution"] = "1920x1080"
    _assert(FPSettings.save_to(d, TEST_SETTINGS), "settings saved")
    var raw = JSON.parse_string(FileAccess.get_file_as_string(TEST_SETTINGS))
    _assert(raw is Dictionary and int(raw["version"]) == FPSettings.VERSION, "file carries its version")
    var back := FPSettings.load_from(TEST_SETTINGS)
    _assert(is_equal_approx(float(back["master"]), 0.35) and float(back["music"]) == 0.0, "volumes come back")
    _assert(is_equal_approx(float(back["mouse_sensitivity"]), 1.8) and bool(back["invert_y"]), "look comes back")
    _assert(float(back["fov"]) == 90.0 and back["resolution"] == "1920x1080", "fov + resolution come back")
    var bad := FPSettings.sanitize({"master": 7, "fov": 10, "window_mode": "tv", "resolution": "3x3", "junk": 1})
    _assert(float(bad["master"]) == 1.0 and float(bad["fov"]) == FPSettings.FOV_MIN, "values clamped")
    _assert(bad["window_mode"] == "windowed" and bad["resolution"] == "1280x720" and not bad.has("junk"), "bad values dropped")
    var f := FileAccess.open(TEST_SETTINGS, FileAccess.WRITE)
    f.store_string("{not json")
    f.close()
    _assert(FPSettings.load_from(TEST_SETTINGS) == FPSettings.defaults(), "broken file -> defaults")

func _settings_apply() -> void:
    var sm: FPSettingsMenu = _m.settings_menu
    sm.set_value("mouse_sensitivity", 2.0)
    _assert(is_equal_approx(_m.player.config.mouse_sensitivity, FPSettings.BASE_SENSITIVITY * 2.0), "sensitivity applied to player")
    sm.set_value("fov", 84.0)
    _assert(is_equal_approx(_m.player.camera.fov, 84.0), "fov applied to camera")
    sm.step("invert_y", 1)
    _assert(_m.player.config.invert_y, "invert applied")
    sm.step("invert_y", 1)
    _assert(not _m.player.config.invert_y, "invert toggles back")
    sm.step("resolution", 1)
    _assert(sm.settings["resolution"] == "1600x900", "resolution steps forward")
    sm.step("resolution", -1)
    sm.step("resolution", -1)
    _assert(sm.settings["resolution"] == "2560x1440", "resolution wraps back")
    _assert(FPSettings.load_from(TEST_SETTINGS)["resolution"] == "2560x1440", "every change saved at once")
    sm.set_value("master", 0.5)
    var i := AudioServer.get_bus_index("Master")
    _assert(absf(AudioServer.get_bus_volume_db(i) - linear_to_db(0.5)) < 0.01, "master volume on the bus")
    sm.set_value("sfx", 0.0)
    _assert(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "zero sfx mutes")
    sm.set_value("sfx", 1.0)
    sm.set_value("fov", 75.0)
    sm.set_value("mouse_sensitivity", 1.0)
    sm.set_value("resolution", "1280x720")
    sm.open()
    _assert(sm.is_open() and sm.get_viewport().gui_get_focus_owner() != null, "settings opens with focus")
    sm.open_keys()
    _assert(_m.keybind_menu.is_open(), "key settings open from settings")
    _m.keybind_menu.close()
    sm.close()

func _buses() -> void:
    _assert(AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("Music") >= 0, "SFX + Music buses exist")
    var bed := AudioStreamPlayer.new()
    bed.name = "Bed_test"
    FPSettings.route_player(bed)
    var hit := AudioStreamPlayer3D.new()
    FPSettings.route_player(hit)
    _assert(bed.bus == &"Music" and hit.bus == &"SFX", "beds -> Music, the rest -> SFX")
    bed.free()
    hit.free()

func _title() -> void:
    _assert(not _m.title_wanted(), "no title under --script")
    var ts: FPTitleScreen = _m.title_screen
    _assert(not ts.is_open(), "title hidden in tests")
    if FileAccess.file_exists(TEST_SAVE):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
    _m.show_title()
    _assert(ts.is_open() and paused, "title up, world held")
    _assert(not ts.continue_button.visible, "no save -> no 이어하기")
    _assert(_m.esc_target() == "", "Esc does nothing on the title")
    var got := {"new": 0}
    var cb := func(): got["new"] += 1
    ts.new_game_requested.connect(cb)
    ts.request_new_game()
    _assert(got["new"] == 1 and not ts.is_confirming(), "no save -> new game at once")
    ts.close()
    _m.save_to_disk()
    _m.show_title()
    _assert(ts.continue_button.visible, "save -> 이어하기 shown")
    _assert(ts.get_viewport().gui_get_focus_owner() == ts.continue_button, "이어하기 has focus")
    ts.request_new_game()
    _assert(got["new"] == 1 and ts.is_confirming(), "save -> asks before new game")
    ts.confirm_no.pressed.emit()
    _assert(not ts.is_confirming() and got["new"] == 1, "취소 keeps the save")
    ts.request_new_game()
    ts.confirm_yes.pressed.emit()
    _assert(got["new"] == 2, "지우고 시작 starts")
    ts.new_game_requested.disconnect(cb)
    _m._leave_title()
    _assert(_m.is_opening(), "새로 시작 plays the opening")
    _m.finish_opening()
    _assert(not paused and not ts.is_open(), "leaving the title lets the world run")

func _esc() -> void:
    _m._esc_guard_frame = -10
    _assert(_m.esc_target() == "pause", "plain play: Esc = pause")
    _assert(_m.handle_esc() == "pause" and _m.pause_menu.is_open() and paused, "pause opens, world held")
    _m.open_settings()
    _assert(_m.esc_target() == "settings", "settings over pause closes first")
    _m.settings_menu.open_keys()
    _assert(_m.esc_target() == "keys", "key screen closes before settings")
    _m.handle_esc()
    _assert(_m.settings_menu.is_open() and not _m.keybind_menu.is_open(), "Esc closed only the key screen")
    _m.handle_esc()
    _assert(_m.pause_menu.is_open() and not _m.settings_menu.is_open(), "Esc closed only settings")
    _assert(_m.handle_esc() == "resume" and not paused, "Esc resumes")
    _assert(_m.esc_target() == "", "same Esc does not reopen pause")
    _m._esc_guard_frame = -10
    _m._seated = true
    _assert(_m.esc_target() == "seat", "seated: Esc stands up first")
    _m._seated = false
    _m._mirror_open = true
    _assert(_m.esc_target() == "mirror", "mirror: Esc closes the mirror first")
    _m._mirror_open = false
    _m._settling = true
    _assert(_m.esc_target() == "settle", "toilet view: Esc leaves it first")
    _m._settling = false
    _m.open_mirror()
    _assert(_m.handle_esc() == "mirror" and not _m._mirror_open, "Esc really closed the mirror")
    _assert(not _m.pause_menu.is_open() and _m.esc_target() == "", "and did not open pause")
    _m._esc_guard_frame = -10

func _disk_save() -> void:
    _m.progression.teeth = 41
    _assert(_m.save_to_disk() and _m.has_save_file(), "saved to disk")
    _m.progression.teeth = 3
    _assert(_m.load_from_disk() and _m.progression.teeth == 41, "disk save comes back")

## Every menu fits inside 1280x720 and 1920x1080 at its scale.
func _layout() -> void:
    for size in [Vector2(1280, 720), Vector2(1920, 1080)]:
        for layer in [_m.title_screen, _m.pause_menu, _m.settings_menu]:
            var root: Control = layer.root
            var k: float = size.y / FPMenuKit.BASE_H
            layer.scale = Vector2(k, k)
            root.size = (size as Vector2) / k
            _assert(root.size.x >= 1280.0 - 0.5 and absf(root.size.y - 720.0) < 0.5, "%s layout box at %s" % [layer.name, size])
    _m.settings_menu.open()
    var panel_min: Vector2 = (_m.settings_menu.root.get_child(1).get_child(0) as Control).get_combined_minimum_size()
    _assert(panel_min.x <= 1280.0 and panel_min.y <= 720.0, "settings plate fits 720p (%s)" % panel_min)
    _m.settings_menu.close()

func await_frame_free() -> void:
    pass