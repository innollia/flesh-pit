extends SceneTree

var field: FDKTerrainField
var camera: Camera3D
var destination: String
var passed := 0
var failed := 0

func _init() -> void:
    destination = OS.get_environment("FP_TERRAIN_EVIDENCE")
    if destination.is_empty():
        destination = ProjectSettings.globalize_path("res://../.dryforge/evidence/terrain-solid-volume")
    DirAccess.make_dir_recursive_absolute(destination)
    setup.call_deferred()

func setup() -> void:
    root.size = Vector2i(640,360)
    var world := Node3D.new()
    root.add_child(world)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color(1,0,1)
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color.WHITE
    environment.environment.ambient_light_energy = 0.8
    world.add_child(environment)
    field = FDKTerrainField.new()
    field.config.chunk_size = 4
    field.density_sampler = func(_p: Vector3): return 1.0
    world.add_child(field)
    field.generate_region(AABB(Vector3.ONE * -2, Vector3.ONE * 4))
    for x in range(-1,1):
        for y in range(-1,1):
            for z in range(-1,1):
                field.dig_at(Vector3(x,y,z)*0.5 + Vector3.ONE*0.25,1.0)
    field.remesh_all()
    camera = Camera3D.new()
    camera.near = 0.02
    world.add_child(camera)
    camera.current = true
    camera.position = Vector3(0,0.3,0)
    await shot("dug", false)
    for step in range(4):
        field.contract_sphere(Vector3.ZERO,1.3,0.45)
        field.remesh_all()
        await physics_frame
        await physics_frame
        var eye := Vector3(0,0.3,0)
        camera.global_position = field.constrain_eye(eye,Vector3(0,-0.4,0),camera.near)
        camera.force_update_transform()
        print("CLOSING proof=",field._solid_volume.observer_proof," triangles=",field._solid_volume._faces.size()/3,
            " proof_us=",field._solid_volume.last_proof_us," prepare_us=",field._solid_volume.last_prepare_us)
        await shot("closing_%d" % step,false)
    var minimum := 1.0
    for x in range(-1,2):
        for y in range(-1,2):
            for z in range(-1,2):
                minimum = minf(minimum,field.corner_density_global(Vector3i(x,y,z)))
    print("FULL_SOLID minimum_corner_density=",minimum," triangles=",field._solid_volume._faces.size()/3)
    if minimum >= field.config.iso_level: passed += 1
    else: failed += 1
    var directions := [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK,Vector3(1,1,1).normalized()]
    var positions := [Vector3(0.1,0.3,0.1),Vector3.ZERO,Vector3.ONE*0.5,Vector3(0.501,0.501,0.501),Vector3(1.99,0.25,0.25)]
    for i in range(positions.size()):
        for j in range(directions.size()):
            var eye: Vector3 = positions[i]
            camera.global_position = field.constrain_eye(eye,eye-Vector3.UP*0.7,camera.near)
            var up := Vector3.RIGHT if absf(directions[j].y) > 0.9 else Vector3.UP
            camera.look_at(camera.global_position+directions[j],up)
            camera.force_update_transform()
            await shot("buried_%d_%d" % [i,j],false)
    camera.global_position = Vector3(0.1,0.3,0.1)
    camera.look_at(camera.global_position+Vector3.FORWARD,Vector3.UP)
    field.constrain_eye(camera.global_position,camera.global_position-Vector3.UP*0.7,camera.near)
    field.set_press(camera.global_position+Vector3.FORWARD*0.25,Vector3.BACK,0.85)
    for clock in [0.0,1.5]:
        for tid in range(FDKChunk.TISSUE_TEXTURES.size()):
            FDKChunk.terrain_material(tid).set_shader_parameter("motion_clock",clock)
        await shot("buried_press_%s" % str(clock),false)
    field.set_press(Vector3.ZERO,Vector3.ZERO,0.0)
    var hit := field.solid_contact_ray(camera.global_position,camera.global_position+Vector3.FORWARD)
    if hit.is_empty(): failed += 1
    else:
        field.dig_at(hit.position-field._eye_surface_outward(hit)*0.05,1.0)
        field.remesh_all()
        camera.global_position = field.constrain_eye(camera.global_position,camera.global_position-Vector3.UP*0.7,camera.near)
        camera.force_update_transform()
        await shot("first_actual_tear",false)
    camera.global_position = Vector3.ONE*100
    field.constrain_eye(camera.global_position,camera.global_position-Vector3.UP*0.7,camera.near)
    camera.force_update_transform()
    await shot("outside_generated_world",true)
    print("%d passed, %d failed" % [passed,failed])
    quit(1 if failed else 0)

func shot(label: String, expect_background: bool) -> void:
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    image.save_png(destination.path_join(label+".png"))
    var exposed := 0
    for y in range(image.get_height()):
        for x in range(image.get_width()):
            var color := image.get_pixel(x,y)
            if color.r > 0.8 and color.b > 0.8 and color.g < 0.2: exposed += 1
    var ok := exposed > 0 if expect_background else exposed == 0
    if ok: passed += 1
    else: failed += 1
    print(label," background_pixels=",exposed," expected_background=",expect_background)
