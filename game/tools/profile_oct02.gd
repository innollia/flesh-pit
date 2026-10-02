extends SceneTree
var m: Node3D
func _init():
    m = load("res://main/scenes/main.tscn").instantiate()
    root.add_child(m)
    run.call_deferred()
func run():
    for i in range(10): await process_frame
    m.finish_opening()
    m.set_process(false)
    m.player.set_physics_process(false)
    for method in ["_stream_world", "_update_atmosphere", "_update_restroom_front", "_update_hands_room_layer", "_vent_watch", "_update_tank_teeth", "step_world"]:
        var begin = Time.get_ticks_usec()
        for i in range(120):
            if method in ["_update_atmosphere", "_vent_watch", "step_world"]: m.call(method, 1.0 / 60.0)
            else: m.call(method)
        print(method, " us/call: ", (Time.get_ticks_usec()-begin)/120.0)
    print("chunks: ", m.terrain._chunks.size())
    quit()
