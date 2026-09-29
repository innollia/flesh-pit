extends SceneTree

## W06 capture: crayon tumor drawings on the wall after a lever settlement.
## Run WINDOWED with the movie writer (never headless):
##   Godot_console --path game --windowed --resolution 1280x720
##     --write-movie <dir>/f.png --fixed-fps 10 --quit-after 30
##     --script res://tests/capture_drawings.gd

var _main: Node3D
var _frame := 0

func _init() -> void:
    _main = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
    get_root().add_child(_main)

func _process(_d: float) -> bool:
    _frame += 1
    if _frame == 3:
        var m = _main
        m.finish_opening()
        m.restroom.set_door_open(false, true)
        m.player.global_position = m.restroom.toilet.global_position + Vector3(0, 0.9, 0.6)
        m.stomach.add_flesh(40.0)
        m.request_vomit()
        m.flush()
        m.vent.on_tumors_settled(["core_knot", "mantle_coil", "surface_star", "core_bulb"])
        var mid: Vector3 = m.restroom.to_global(FPVent.drawing_spot(1) + Vector3(0, 0, 0.13))
        var cam: Camera3D = m.settle_camera
        cam.global_position = mid + Vector3(-1.1, -0.05, 0.0)
        cam.look_at(mid, Vector3.UP)
        cam.current = true
    if _frame == 20:
        var m = _main
        print("CAM ", m.get_viewport().get_camera_3d().name, " ", m.get_viewport().get_camera_3d().global_position)
        for n in m.drawing_nodes:
            print("PAPER ", n.name, " ", n.global_position, " vis ", n.is_visible_in_tree(), " inside ", n.is_inside_tree())
        print("ROOM ", m.restroom.global_position)
        var d0: MeshInstance3D = m.drawing_nodes[0]
        print("MESH ", d0.mesh, " aabb ", d0.get_aabb(), " layers ", d0.layers, " cull ", m.get_viewport().get_camera_3d().cull_mask, " scale ", d0.global_transform.basis.get_scale(), " fwd ", -m.get_viewport().get_camera_3d().global_transform.basis.z)
    return false