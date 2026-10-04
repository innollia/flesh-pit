extends SceneTree

var m: Node3D
var passed := 0
var failed := 0
var torn: Array[Vector3] = []
var destination: String
var center := Vector3(8.25,5.25,8.25)

func _init() -> void:
    root.size = Vector2i(640,360)
    destination = ProjectSettings.globalize_path("res://../.dryforge/evidence/main-solid-gpu")
    DirAccess.make_dir_recursive_absolute(destination)
    m = load("res://main/scenes/main.tscn").instantiate()
    m.rest_seed = 1337
    m.save_path = destination.path_join("isolated-save.bin")
    root.add_child(m)
    run.call_deferred()

func check(ok: bool,label: String) -> void:
    if ok: passed += 1
    else:
        failed += 1
        print("FAIL: ",label)

func mouse(held: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = held
    Input.parse_input_event(event)

func aim(direction: Vector3) -> void:
    var dir := direction.normalized()
    m.player._yaw = atan2(-dir.x,-dir.z)
    m.player._pitch = asin(clampf(dir.y,-1,1))
    m.player.rotation.y = m.player._yaw
    m.player.camera_pivot.rotation.x = m.player._pitch

func shot(label: String,background_expected := false) -> void:
    await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    image.save_png(destination.path_join(label+".png"))
    var exposed := 0
    for y in range(image.get_height()):
        for x in range(image.get_width()):
            var color := image.get_pixel(x,y)
            if color.r > 0.8 and color.b > 0.8 and color.g < 0.2: exposed += 1
    print(label," background_pixels=",exposed," tears=",torn.size()," deaths=",m.deaths)
    check(exposed > 0 if background_expected else exposed == 0,label+" background detection")

func run() -> void:
    await process_frame
    m.finish_opening()
    InputMap.action_erase_events("fdk_eat")
    var binding := InputEventMouseButton.new()
    binding.button_index = MOUSE_BUTTON_LEFT
    InputMap.action_add_event("fdk_eat",binding)
    m.chewer.cell_torn.connect(func(p): torn.append(p))
    m.terrain.remesh_budget_per_frame = 1
    m.terrain.fill_box_uniform(AABB(center-Vector3.ONE*4,Vector3.ONE*8),1.0,0)
    m.terrain.remesh_all()
    m.player.global_position = center-Vector3.UP*m.player.eye_pivot_y(false)
    m.player.velocity = Vector3.ZERO
    m.stomach.fill = 0
    m.carried_flesh = 0
    m.excavated_cells = 0
    m._crush_t = 0
    m.hazard.health = 100
    m.carry_mode = false
    m.equip_tool("")
    m.environment.background_color = Color(1,0,1)
    m.apply_atmosphere_now()
    await physics_frame
    await physics_frame
    for direction in [Vector3.FORWARD,Vector3.BACK,Vector3.LEFT,Vector3.RIGHT,Vector3.UP,Vector3.DOWN,Vector3(1,0.9,0.8).normalized()]:
        aim(direction)
        await shot("full_mass_"+str(passed))
        check(m._look_hit().get("fdk_solid_volume",false),"actual volume contact")
    aim(Vector3.FORWARD)
    # Observability control only: temporarily hide terrain, then restore before input.
    m.terrain.visible = false
    await shot("background_positive_control",true)
    m.terrain.visible = true
    await shot("restored_full_mass")
    check(m.stomach.fill == 0 and torn.is_empty(),"no food before real input")
    mouse(true)
    var pending_frames := 0
    var captured := 0
    for frame in range(150):
        await process_frame
        if m.terrain._surface_patch != null:
            pending_frames += 1
        if torn.size() > captured:
            captured = torn.size()
            await shot("actual_tear_"+str(captured))
        if torn.size() >= 2: break
    mouse(false)
    await process_frame
    await shot("released_actual_cavity")
    check(torn.size() >= 2,"actual held input repeated tears")
    check(pending_frames > 0,"actual pending publication observed")
    check(m.excavated_cells == torn.size(),"excavated matches actual tears")
    check(is_equal_approx(m.stomach.fill,torn.size()*m.stomach_config.flesh_per_cell),"food matches actual tears")
    for p in torn: check(m.terrain.density_at(p)<m.terrain_config.iso_level,"actual density removed")
    check(not m.chewer.is_chewing(),"real release stops chew")
    check(m.deaths == 0 and m.hazard.health > 0,"no death reset hides failure")
    print("%d passed, %d failed" % [passed,failed])
    m.queue_free()
    await process_frame
    quit(1 if failed else 0)
