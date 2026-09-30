class_name FPSettings
extends RefCounted

## Player settings: volume, look, screen. Stored as versioned JSON in
## user://settings.json, applied at start and after every change.
## Keys live in user://keybinds.json (main.gd), not here.

const PATH := "user://settings.json"
const VERSION := 1
## FDKPlayerConfig.mouse_sensitivity at 1.0x.
const BASE_SENSITIVITY := 0.0025
const RESOLUTIONS := ["1280x720", "1600x900", "1920x1080", "2560x1440"]
const WINDOW_MODES := ["windowed", "fullscreen"]
const FOV_MIN := 60.0
const FOV_MAX := 100.0
const SENS_MIN := 0.2
const SENS_MAX := 3.0

static func defaults() -> Dictionary:
    return {
        "version": VERSION,
        "master": 0.8,
        "sfx": 1.0,
        "music": 0.8,
        "mouse_sensitivity": 1.0,
        "invert_y": false,
        "fov": 75.0,
        "window_mode": "windowed",
        "resolution": "1280x720",
    }

## Unknown keys dropped, missing keys filled, every value clamped.
static func sanitize(d: Dictionary) -> Dictionary:
    var out := defaults()
    for k in out:
        if k != "version" and d.has(k):
            out[k] = d[k]
    for k in ["master", "sfx", "music"]:
        out[k] = clampf(float(out[k]), 0.0, 1.0)
    out["mouse_sensitivity"] = clampf(float(out["mouse_sensitivity"]), SENS_MIN, SENS_MAX)
    out["invert_y"] = bool(out["invert_y"])
    out["fov"] = clampf(float(out["fov"]), FOV_MIN, FOV_MAX)
    if not WINDOW_MODES.has(String(out["window_mode"])):
        out["window_mode"] = "windowed"
    if not RESOLUTIONS.has(String(out["resolution"])):
        out["resolution"] = "1280x720"
    out["version"] = VERSION
    return out

static func load_from(path: String = PATH) -> Dictionary:
    if not FileAccess.file_exists(path):
        return defaults()
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not parsed is Dictionary:
        return defaults()
    return sanitize(_migrate(parsed))

## Older versions come here first. v1 is the first one.
static func _migrate(d: Dictionary) -> Dictionary:
    return d

static func save_to(s: Dictionary, path: String = PATH) -> bool:
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        return false
    f.store_string(JSON.stringify(sanitize(s), "  "))
    f.close()
    return true

static func resolution_size(s: Dictionary) -> Vector2i:
    var parts := String(s.get("resolution", "1280x720")).split("x")
    if parts.size() != 2:
        return Vector2i(1280, 720)
    return Vector2i(int(parts[0]), int(parts[1]))

# --- applying -----------------------------------------------------------------

static func ensure_buses() -> void:
    for bus_name in ["SFX", "Music"]:
        if AudioServer.get_bus_index(bus_name) < 0:
            var i := AudioServer.bus_count
            AudioServer.add_bus(i)
            AudioServer.set_bus_name(i, bus_name)
            AudioServer.set_bus_send(i, &"Master")

static func apply_audio(s: Dictionary) -> void:
    ensure_buses()
    _set_bus("Master", float(s["master"]))
    _set_bus("SFX", float(s["sfx"]))
    _set_bus("Music", float(s["music"]))

static func _set_bus(bus_name: String, lin: float) -> void:
    var i := AudioServer.get_bus_index(bus_name)
    if i < 0:
        return
    AudioServer.set_bus_volume_db(i, linear_to_db(maxf(lin, 0.0001)))
    AudioServer.set_bus_mute(i, lin <= 0.001)

## Beds (the long ambience layers) go to Music, the rest on Master to SFX.
static func route_player(n: Node) -> void:
    if not is_instance_valid(n):
        return
    if n is AudioStreamPlayer or n is AudioStreamPlayer3D or n is AudioStreamPlayer2D:
        if String(n.get("bus")) != "Master":
            return
        n.set("bus", &"Music" if String(n.name).begins_with("Bed_") else &"SFX")

static func apply_look(s: Dictionary, player: Node) -> void:
    if player == null:
        return
    var cfg = player.get("config")
    if cfg != null:
        cfg.mouse_sensitivity = BASE_SENSITIVITY * float(s["mouse_sensitivity"])
        cfg.invert_y = bool(s["invert_y"])
    var cam = player.get("camera")
    if cam is Camera3D:
        (cam as Camera3D).fov = float(s["fov"])

static func apply_window(s: Dictionary) -> void:
    if DisplayServer.get_name() == "headless":
        return
    if String(s["window_mode"]) == "fullscreen":
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
        return
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    var size := resolution_size(s)
    var screen := DisplayServer.screen_get_usable_rect()
    if screen.size.x > 0:
        size = Vector2i(mini(size.x, screen.size.x), mini(size.y, screen.size.y))
    DisplayServer.window_set_size(size)
    DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)