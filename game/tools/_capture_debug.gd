extends "res://tools/capture.gd"
# Debug views: args after -- are yaw_deg pitch_deg x y z
func _apply_stage(i: int) -> void:
    var a := OS.get_cmdline_user_args()
    _main.restroom.set_door_open(a.size() > 5, true)
    _pose(Vector3(float(a[2]), float(a[3]), float(a[4])), deg_to_rad(float(a[0])), deg_to_rad(float(a[1])))
    _main.apply_atmosphere_now()
func _process(_delta: float) -> bool:
    if _frame == 0:
        _apply_stage(0)
    _frame += 1
    if _frame < 30:
        return false
    RenderingServer.force_draw()
    get_root().get_texture().get_image().save_png("res://captures/_debug.png")
    quit(0)
    return true
