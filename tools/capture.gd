extends SceneTree

## Window-mode capture of the reference screens. Needs a real window (not
## --headless). Run:  Godot_console.exe --path <project> --windowed --script tools/capture.gd
## Writes res://captures/<W>x<H>/<stage>.png for each resolution, then quits.

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const STAGES := ["01_restroom", "02_flesh_wall", "03_dug_tunnel", "04_regrowing_tunnel", "05_hand_grab", "06_overfilled", "07_toilet_settlement", "08_carry_pile"]
const SETTLE := 40

var _stage := 0
var _frame := 0
var _main: Node3D

func _init() -> void:
    var packed: PackedScene = load("res://main/scenes/main.tscn")
    _main = packed.instantiate()
    get_root().add_child(_main)
    get_root().size = RESOLUTIONS[0]

func _process(_delta: float) -> bool:
    if _stage >= STAGES.size():
        return false
    if _frame == 0:
        _apply_stage(_stage)
    _per_frame(_stage)
    _frame += 1
    if _frame < SETTLE:
        return false
    _capture(STAGES[_stage])
    _stage += 1
    _frame = 0
    if _stage >= STAGES.size():
        print("=== capture complete ===")
        _main.queue_free()
        quit(0)
        return true
    return false

func _pose(pos: Vector3, yaw: float, pitch: float = 0.0) -> void:
    var p = _main.player
    p.global_position = pos
    p.set("_yaw", yaw)
    p.set("_pitch", pitch)
    p.rotation.y = yaw
    p.camera_pivot.rotation.x = pitch

func _dig_tunnel() -> void:
    var t = _main.terrain
    for zi in range(11):
        for xi in range(-1, 2):
            for yi in range(0, 4):
                t.dig_at(Vector3(xi * 0.5 + 0.25 - 0.5 * 0.0, yi * 0.5 + 0.25, 1.9 + zi * 0.5), 1.0)
    # a side pocket so the tunnel is not a clean box
    for p in [Vector3(1.0, 1.25, 3.4), Vector3(1.0, 0.75, 3.4), Vector3(-1.0, 1.75, 4.4), Vector3(0.25, 2.25, 5.0)]:
        t.dig_at(p, 1.0)
    t.remesh_all()

func _apply_stage(i: int) -> void:
    var m = _main
    match i:
        0:
            m.restroom.set_door_open(false, true)
            _pose(m.START_POS, m.START_YAW, deg_to_rad(-6.0))
        1:
            m.restroom.set_door_open(true, true)
            _pose(Vector3(0.0, 0.95, 0.4), PI, deg_to_rad(-4.0))
        2:
            _dig_tunnel()
            _pose(Vector3(0.0, 0.95, 2.6), PI, deg_to_rad(-3.0))
        3:
            for k in range(232):
                m.terrain.regenerate_all(0.1, Vector3(0, 1, 40.0), 0.5)
            m.terrain.remesh_all()
            _pose(Vector3(0.0, 0.95, 2.2), PI, deg_to_rad(-3.0))
        4:
            m.terrain.dig_at(Vector3(0.25, 1.25, 2.4), 1.0)
            _dig_tunnel()
            _pose(Vector3(0.0, 0.95, 4.2), -PI * 0.5, deg_to_rad(-6.0))
            m.player.camera.fov = 60.0
            m.hands_rig.on_grab_started(Vector3i.ZERO)
        5:
            m.player.camera.fov = 75.0
            m.hands_rig.on_released()
            m.stomach.add_flesh(m.stomach_config.capacity + m.stomach_config.overfill_capacity * 0.85)
            m.stomach_view.set_state(m.stomach.fill_ratio(), m.stomach.overfill_ratio())
            m.stomach_view.snap()
            _pose(Vector3(0.0, 0.95, 4.0), PI, deg_to_rad(-2.0))
        6:
            _pose(Vector3(0.75, 0.95, -0.6), 0.0)
            m.start_settlement()
        7:
            m.settlement.finish_counting()
            m._on_buy(0)
            m.end_settlement()
            m.has_blender = true
            m.toggle_carry()
            m.carried_flesh = 30.0
            _pose(Vector3(0.0, 0.95, 4.0), PI, deg_to_rad(-2.0))
    m.apply_atmosphere_now()

func _per_frame(i: int) -> void:
    var m = _main
    if i == 4:
        var r := clampf(float(_frame) / SETTLE * 1.1, 0.0, 0.8)
        m.hands_rig.on_chew_progress(r, Vector3i.ZERO)
        m.terrain.set_press(Vector3(0.95, 1.3, 4.2), Vector3(-1, 0, 0), r)
    if i == 5 and _frame == 0:
        m.terrain.set_press(Vector3.ZERO, Vector3.BACK, 0.0)
    if i == 6 and _frame == SETTLE - 2:
        m.settlement.finish_counting()

func _capture(stage_name: String) -> void:
    for res in RESOLUTIONS:
        get_root().size = res
        for k in range(4):
            RenderingServer.force_draw()
        var img := get_root().get_texture().get_image()
        var dir_path := "res://captures/%dx%d" % [res.x, res.y]
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
        var path := "%s/%s.png" % [dir_path, stage_name]
        var err := img.save_png(path)
        if err != OK:
            printerr("FAIL saving capture: %s (err=%d)" % [path, err])
        else:
            print("OK captured %s %dx%d" % [stage_name, img.get_width(), img.get_height()])
    get_root().size = RESOLUTIONS[0]
