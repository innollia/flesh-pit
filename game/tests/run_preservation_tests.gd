extends SceneTree

var m: Node3D
var passed := 0
var failed := 0
var capture := false

func _init() -> void:
    capture = "--capture" in OS.get_cmdline_user_args()
    m = load("res://main/scenes/main.tscn").instantiate()
    root.add_child(m)
    run.call_deferred()

func check(ok: bool, label: String) -> void:
    if ok: passed += 1
    else:
        failed += 1
        print("FAIL: ", label)

func shot(label: String) -> void:
    if not capture: return
    for frame in range(4): await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png("res://captures/preservation/" + label + ".png")

func raise_watch() -> void:
    for frame in range(30):
        m.hand_motions.tick(1.0 / 60.0)
        await process_frame
    m.mirror._place()

func run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/preservation"))
    for frame in range(6): await physics_frame
    m.finish_opening()
    m.set_process(false)
    m.player.set_physics_process(false)
    m.player.global_position = Vector3(0, 0.95, 0)
    m.player.rotation.y = 0
    m.player.camera.rotation = Vector3.ZERO
    m.player.camera_pivot.rotation = Vector3.ZERO
    m.opening_view.hints.visible = false
    m.open_mirror()
    await shot("tab_raise_start")
    await raise_watch()
    check(m.hand_motions.watch_raised() > 0.99, "watch raising completes and remains held")
    Input.action_press("fdk_eat")
    m.hand_motions.check_cancel()
    check(not m.hand_motions.cancelled, "clicking Tab rows does not cancel the watch pose")
    Input.action_release("fdk_eat")
    var left: Node3D = m.hands_rig.get_hand_root("left")
    check(left.position.distance_to(FPHandMotions.WATCH_WRIST_POS) < 0.03, "left wrist lifts into watch position")
    check(left.get_node("ArmHair/Forearm").visible, "full watch forearm is visible")
    check(m.mirror.hand_root == left, "doll uses the visible normal arm")
    for pitch in [-1.2, 0.0, 1.2]:
        m.player.camera_pivot.rotation.x = pitch
        m.mirror._place()
        check(m.mirror.body.global_position.distance_to(m.mirror.arm_top(FPMirror.DOLL_ON_ARM.z)) < 0.002, "feet remain on arm at pitch " + str(pitch))
        check(m.mirror.body.global_basis.y.normalized().dot(m.player.camera.global_basis.y) > 0.999, "only orientation follows camera at pitch " + str(pitch))
        var feet: Vector2 = m.player.camera.unproject_position(m.mirror.body.global_position)
        var head: Vector2 = m.player.camera.unproject_position(m.mirror.body.to_global(Vector3(0,1.76,0)))
        check(absf(head.y-feet.y) > root.size.y * 0.25, "doll retains readable full-body screen size")
        check(m.player.camera.is_position_in_frustum(m.mirror.body.to_global(Vector3(0,1.76,0))), "head stays in view without moving feet")
        await shot("tab_pitch_" + str(pitch))
    var candidate: int = m.mirror._cand.get(m.mirror._part, 0)
    var wheel := InputEventMouseButton.new()
    wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
    wheel.pressed = true
    m.mirror._input(wheel)
    check(m.mirror._cand.get(m.mirror._part, 0) == candidate, "wheel cannot change Tab candidates")
    for action in InputMap.get_actions():
        for event in InputMap.action_get_events(action):
            check(not (event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]), "wheel is not bound to " + action)
    m.mirror._clear_ghost()
    m.mirror.body.set_shimmer("face", false)
    await shot("tab_no_ghost")
    var body: FPMirrorBody = m.mirror.body
    body.apply(["M04"])
    var head_material: ShaderMaterial = body.part_node("face").get_node("Head").material_override
    check((head_material.get_shader_parameter("jaw_scale") as Vector3).x > 1.7, "jaw mutation deforms the image head")
    await shot("tab_jaw")
    body.apply(["M15"])
    check((head_material.get_shader_parameter("jaw_offset") as Vector3).y < -0.29, "M15 retains downward jaw deformation")
    body.apply(["M24"])
    check(body._sub["eyes"].get_node("EyeImageLeft").visible, "mutated bitmap eyes have visible depth geometry")
    check(body._sub["eyes"].scale.z > 1.5, "eye mutation preserves depth scale")
    await shot("tab_eyes")
    body.apply([])
    var ghost := body.ghost("M04")
    var ghost_mat: ShaderMaterial = ghost.part_node("face").get_node("Head").material_override
    check(ghost_mat.get_shader_parameter("face_tex") != null and ghost_mat.get_shader_parameter("ghost"), "ghost retains face image markings")
    check((ghost_mat.get_shader_parameter("jaw_scale") as Vector3).x > 1.7, "ghost previews the changed jaw")
    ghost.queue_free()
    m.progression.tumor_mutations.append("T2")
    m.art_hookup._mut_key = "force refresh"
    m.art_hookup._sync_mutations(m.progression)
    await raise_watch()
    var variant: FDKHandsRig = m.art_hookup.mut_hands.call("rig")
    check(variant.pose_hook == m.hand_motions, "mutation rig receives watch motion")
    check(m.mirror.hand_root == variant.get_hand_root("left"), "doll follows visible mutation arm")
    check(variant.get_hand_root("left").position.distance_to(FPHandMotions.WATCH_WRIST_POS) < 0.03, "mutation wrist raises too")
    await shot("tab_mutation_arm")
    m.mirror.close()
    check(is_equal_approx(FPRestroom.HALF.x, 2.25), "original room width restored")
    m.restroom.set_door_open(true, true)
    m.restroom._update_door_spill()
    check(is_equal_approx(m.restroom.door_spill.light_energy, 0.85), "approved dim door light retained")
    check(m.restroom.get_node("RoomLight").shadow_enabled, "fixture shadows restored")
    m.progression.teeth_in_hand = 3
    m.tank_lid.pick()
    m.tank_lid.drop()
    var point: Vector3 = m.restroom.tank_art.to_global(Vector3(0,0.3,0))
    m.player.global_position = Vector3(point.x + 0.6, 0.95, point.z)
    m.player.camera_pivot.rotation = Vector3.ZERO
    m.player.camera.look_at(point, Vector3.UP)
    await physics_frame
    check(m.interact_target() == "tank_teeth", "tank teeth return is reachable through aimed interaction")
    m._interact()
    check(m.progression.teeth_in_hand == 0, "actual interact input returns held teeth")
    var cavity := Vector3(2.6, 1, 0)
    m.terrain.dig_at(cavity, 1.0)
    var before_density: float = m.terrain.density_at(cavity)
    m._migrate_restroom_terrain()
    check(m.terrain.density_at(cavity) <= before_density + 0.001, "migration never fills an excavated cavity beside the restroom")
    m.progression.tumor_mutations.clear()
    m.art_hookup._sync_mutations(m.progression)
    m.progression.grant_item("knife")
    m.equip_tool("knife")
    m.art_hookup._process(0.0)
    check(m.art_hookup.scissors.visible, "empty left hand retains scissors with the right-hand knife")
    m.mirror_view._sync_live_details()
    check(m.mirror_view._held["scissors"].visible, "restored scissors are reflected too")
    if capture:
        m.player.set_physics_process(false)
        m.player.global_position = Vector3(-FPRestroom.HALF.x + 0.85, 0.95, FPRestroom.SINK_Z)
        m.player.rotation.y = PI * 0.5
        m.player.camera.rotation = Vector3.ZERO
        m.player.camera_pivot.rotation.x = 0
        m.hand_blood = 0.5
        m.mirror_view.sync(true, false)
        m.mirror_view_right.sync(true, false)
        await shot("mirror_body_skin")
        m.player.camera_pivot.rotation.x = -1.2
        m._update_hands_room_layer()
        await shot("belly_hand_skin")
        m.player.global_position = Vector3(0.6, 0.95, 1.15)
        m.player.camera_pivot.rotation.x = 0
        m.player.camera.look_at(Vector3(-1.0, 1.0, -0.8), Vector3.UP)
        await shot("restored_wide_room")
    print("--- preservation: %d passed, %d failed ---" % [passed, failed])
    quit(1 if failed else 0)
