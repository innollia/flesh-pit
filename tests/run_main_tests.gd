extends SceneTree

## main.tscn rule tests: toilet settlement rewards, outside vomit gives
## nothing, vomit button threshold, restroom membrane is inedible, the eat
## ray targets solid tissue, carry pile blocks two-handed tools.
## Run: Godot_console.exe --headless --path <project> --script tests/run_main_tests.gd

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
    print("=== flesh-pit main rule tests ===")
    _m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
    get_root().add_child(_m)

func _process(_d: float) -> bool:
    _frame += 1
    if _frame == 2:
        # open the door and let physics pick up the new shapes before ray tests
        _m.restroom.set_door_open(true, true)
        _m.terrain.remesh_all()
    if _frame < 8:
        return false
    _run()
    _m.queue_free()
    print("--- %d passed, %d failed ---" % [_passed, _failures])
    quit(1 if _failures > 0 else 0)
    return true

func _run() -> void:
    var m = _m
    var cap: float = m.stomach_config.capacity
    var over: float = m.stomach_config.overfill_capacity
    # outside vomit: empties, no reward
    m.player.global_position = Vector3(0, 1, 4.0)
    m.stomach.add_flesh(50.0)
    m.request_vomit()
    _assert(m.stomach.fill == 0.0 and m.money == 0 and m.mutation_points == 0, "vomit outside the toilet empties the stomach with no reward")
    # vomit button threshold
    m.stomach.add_flesh(cap + over * 0.2)
    m._process(0.016)
    _assert(not m.vomit_button.shown, "vomit button hidden below the overfill threshold")
    m.stomach.add_flesh(over * 0.3)
    m._process(0.016)
    _assert(m.vomit_button.shown, "vomit button appears past the overfill threshold")
    # toilet settlement rewards
    m.player.global_position = m.restroom.toilet.global_position + Vector3(0, 0.9, 0.6)
    var amount: float = m.stomach.fill
    m.request_vomit()
    _assert(m.is_settling(), "vomit at the toilet opens the settlement view")
    _assert(m.money == int(round(amount * m.MONEY_PER_FLESH)) and m.mutation_points == int(round(amount * m.MUTATION_PER_FLESH)), "toilet vomit awards money and mutation points")
    _assert(m.settle_camera.current, "settlement switches to the toilet close-up camera")
    _assert(m.settlement.money_old == 0 and m.settlement.money_gain == m.money, "settlement shows old total + new gain")
    m._on_buy(2)
    _assert(m.purchased_items.size() == 1 and m.restroom.tank_items.get_child_count() == 1, "buying drops an item into the toilet tank")
    m.end_settlement()
    _assert(not m.is_settling() and m.restroom._lid_target != 0.0, "closing settlement opens the tank lid when something was bought")
    # membrane tissue around the restroom cannot be eaten; door-front flesh can
    _assert(not m.terrain.is_edible_at(Vector3(2.2, 1.0, 0.0)), "restroom side wall membrane is inedible")
    _assert(m.terrain.is_edible_at(Vector3(0.0, 1.0, 2.1)), "flesh beyond the door is edible")
    _assert(m.terrain.density_at(Vector3(0.0, 1.0, 2.3)) >= 0.5, "flesh wall starts right behind the door")
    _assert(m.terrain.density_at(Vector3(0.0, 1.0, 0.0)) < 0.5, "restroom interior is empty")
    _assert(m.terrain.density_at(Vector3(0.0, 1.0, 8.0)) >= 0.5 and m.terrain.density_at(Vector3(-8.0, -6.0, 3.0)) >= 0.5, "everything outside the restroom is flesh")
    # eat ray aims into the wall: chewing at the door wall removes tissue
    m.player.global_position = Vector3(0, 0.95, 1.2)
    m.player.set("_yaw", PI)
    m.player.rotation.y = PI
    m.player.camera_pivot.rotation.x = 0.0
    m.terrain.remesh_all()
    m.player.force_update_transform()
    var ray: Array = m.player.get_look_ray()
    var q := PhysicsRayQueryParameters3D.create(ray[0], ray[0] + ray[1] * 2.5)
    var hit: Dictionary = m.get_world_3d().direct_space_state.intersect_ray(q)
    _assert(not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk"), "look ray from the doorway hits the flesh wall")
    if not hit.is_empty():
        var target: Vector3 = hit.position + (ray[1] as Vector3) * m.terrain_config.cell_size * 0.5
        _assert(m.terrain.density_at(target) >= 0.5, "eat target (hit + half a cell) is solid tissue")
        var before: float = m.stomach.fill
        m.chewer.try_start(target)
        for i in range(60):
            m.chewer.process_chew(0.05)
        _assert(m.stomach.fill > before, "chewing the door wall tears flesh into the stomach")
    # carry pile
    m.toggle_carry()
    m._on_cell_torn(Vector3(0, 1, 3))
    _assert(m.carried_flesh > 0.0 and not m.two_handed_tools_available(), "carrying torn flesh blocks two-handed tools")
    m.toggle_carry()
    _assert(m.two_handed_tools_available(), "putting the pile down frees both hands")
