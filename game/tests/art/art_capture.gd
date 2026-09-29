extends Node3D

## Capture stage for main/art models. Run WINDOWED (not headless):
##   Godot_console --path game --write-movie captures/art/<name>/f.png
##     --fixed-fps 10 --quit-after 14 res://tests/art/art_capture.tscn -- <name>
## Loads res://main/art/<name>.tscn, asks the model for capture_setup()
## (camera + lighting mood), and adds the kit's PS1 screen post.

func _ready() -> void:
    var args := OS.get_cmdline_user_args()
    var model_name: String = args[0] if args.size() > 0 else "fp_vent"
    var scene := load("res://main/art/%s.tscn" % model_name) as PackedScene
    var model: Node3D = scene.instantiate()
    add_child(model)
    var cfg: Dictionary = model.call("capture_setup") if model.has_method("capture_setup") else {}
    var mood: String = cfg.get("env", "dark")
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-50, 35, 0)
    match mood:
        "day":
            env.background_color = Color(0.62, 0.78, 0.95)
            env.ambient_light_color = Color(0.75, 0.78, 0.85)
            env.ambient_light_energy = 0.8
            sun.light_energy = 1.3
            sun.light_color = Color(1.0, 0.96, 0.88)
        "restroom":
            env.background_color = Color(0.42, 0.45, 0.47)
            env.ambient_light_color = Color(0.85, 0.9, 0.95)
            env.ambient_light_energy = 0.3
            sun.light_energy = 0.55
            sun.light_color = Color(0.92, 0.97, 1.0)
        "lit":
            env.background_color = Color(0.1, 0.1, 0.12)
            env.ambient_light_color = Color(0.9, 0.85, 0.8)
            env.ambient_light_energy = 1.6
            sun.light_energy = 2.4
        _:
            env.background_color = Color(0.1, 0.1, 0.12)
            env.ambient_light_color = Color(0.7, 0.55, 0.55)
            env.ambient_light_energy = 0.9
            sun.light_energy = 1.7
            sun.light_color = Color(1.0, 0.85, 0.75)
    var we := WorldEnvironment.new()
    we.environment = env
    add_child(we)
    add_child(sun)
    var fill := OmniLight3D.new()
    fill.position = cfg.get("cam_pos", Vector3(0, 1, 2)) + Vector3(0.3, 0.4, 0.2)
    fill.omni_range = 8.0
    fill.light_energy = float(cfg.get("fill_energy", 1.4))
    add_child(fill)
    var cam := Camera3D.new()
    cam.fov = cfg.get("fov", 55.0)
    cam.near = 0.02
    cam.far = 400.0
    add_child(cam)
    cam.position = cfg.get("cam_pos", Vector3(0, 1, 2))
    cam.look_at(cfg.get("look_at", Vector3.ZERO), Vector3.UP)
    cam.current = true
    add_child(FDKPs1ScreenPost.new())