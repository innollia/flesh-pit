extends SceneTree
var m: Node3D
var passed := 0
var failed := 0
var tears: Array = []
func _init():
    m = load("res://main/scenes/main.tscn").instantiate()
    root.add_child(m)
    run.call_deferred()
func check(ok: bool, label: String):
    if ok: passed += 1
    else:
        failed += 1
        print("FAIL: ", label)
func aim(point: Vector3):
    m.player.camera.look_at(point, Vector3.UP)
    m.player.force_update_transform()
func run():
    for i in range(6): await physics_frame
    m.finish_opening()
    m.set_process(false)
    m.player.set_physics_process(false)
    m.player.global_position = Vector3(-FPRestroom.HALF.x + 0.85, 0.95, FPRestroom.SINK_Z)
    aim(m.sink_point())
    check(m.interact_target() == "sink", "sink requires aim and displays the executed target")
    m.hand_blood = 0.8
    aim(Vector3(1, 1.65, 0))
    m._interact()
    check(is_equal_approx(m.hand_blood, 0.8), "looking away cannot wash hands")
    m.player.global_position = Vector3(0, 0.95, 0.8)
    aim(Vector3(0, 1, FPRestroom.HALF.z))
    check(m.interact_target() == "door", "close door can be selected")
    m.player.global_position = Vector3(0, 0.95, -0.8)
    aim(Vector3(0, 1, FPRestroom.HALF.z))
    check(m.interact_target() != "door", "distant door cannot be selected")
    m.player.global_position = Vector3(0, 0.95, 0.8)
    aim(Vector3(0.5, 1, FPRestroom.HALF.z))
    check(m.interact_target() != "door", "door rejects peripheral aim")
    var wall := StaticBody3D.new()
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(0.5, 0.5, 0.1)
    shape.shape = box
    wall.add_child(shape)
    m.add_child(wall)
    wall.global_position = m.player.camera.global_position + Vector3(0, 0, 0.3)
    await physics_frame
    aim(wall.global_position + Vector3(0, 0, 0.6))
    check(not m._interaction_aim(wall.global_position + Vector3(0, 0, 0.6), 8, 1.25), "opaque obstruction blocks interaction")
    wall.queue_free()
    m.player.camera.rotation = Vector3.ZERO
    m.player.rotation.y = PI
    m.player.camera_pivot.rotation.x = 0
    m.player.global_position = Vector3(0, 0.95, FPRestroom.HALF.z - 0.65)
    m.restroom.set_door_open(true, true)
    for i in range(4): await physics_frame
    var before: Dictionary = m._look_hit()
    var distance: float = m.player.camera.global_position.distance_to(before.position)
    var chunk = before.collider.get_parent()
    var old_mesh = chunk._mesh_instance.mesh
    m.chewer.cell_torn.connect(func(p): tears.append(p))
    Input.action_press("fdk_eat")
    for i in range(240):
        m.hand_actions.tick(1.0 / 60.0)
        m.step_world(1.0 / 60.0)
        await physics_frame
    Input.action_release("fdk_eat")
    m.hand_actions.tick(0)
    var after: Dictionary = m._look_hit()
    check(tears.size() >= 3, "held LMB repeatedly tears during real world regeneration")
    check(chunk._mesh_instance.mesh != old_mesh, "visible ArrayMesh is replaced by digging")
    check(after.is_empty() or m.player.camera.global_position.distance_to(after.position) > distance + 0.4, "surface retreats visibly in full game loop")
    print("tears: ", tears.size(), " start depth: ", distance, " end depth: ", m.player.camera.global_position.distance_to(after.position) if not after.is_empty() else -1)
    check(m.hands_rig._material.shader == m.art_hookup.belt._skin_mat().shader, "hands and first-person belly share skin shading")
    check(m.mirror_view.body._skin.shader == m.hands_rig._material.shader, "mirror skin shares hand shading")
    check(m.mirror_view.body.part_node("face").get_node("Head").material_override.shader == m.hands_rig._material.shader, "face has same skin pipeline")
    m.open_mirror()
    for pitch in [-1.2, 0.0, 1.2]:
        m.player.camera_pivot.rotation.x = pitch
        m.mirror._place()
        check(m.mirror.body.global_basis.y.normalized().dot(m.player.camera.global_basis.y) > 0.999, "Tab figure follows camera pitch " + str(pitch))
    m.mirror.close()
    check(m.mirror._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "closed Tab viewport stops rendering")
    print("--- oct02: %d passed, %d failed ---" % [passed, failed])
    quit(1 if failed else 0)
