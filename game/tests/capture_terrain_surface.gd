extends SceneTree

var field: FDKTerrainField
var camera: Camera3D
var destination: String
var failures := 0

func _init() -> void:
    destination = OS.get_environment("FP_TERRAIN_CAPTURE_DIR")
    if destination.is_empty():
        destination = ProjectSettings.globalize_path("res://../.dryforge/evidence/terrain")
    DirAccess.make_dir_recursive_absolute(destination)
    setup.call_deferred()

func setup() -> void:
    root.size = Vector2i(640, 360)
    var world := Node3D.new()
    root.add_child(world)
    var environment := WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    # Bright sentinel makes exposed background measurable without masking it.
    environment.environment.background_color = Color(1, 0, 1)
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color.WHITE
    environment.environment.ambient_light_energy = 0.8
    world.add_child(environment)
    field = FDKTerrainField.new()
    field.config.chunk_size = 4
    field.density_sampler = func(p: Vector3): return 0.0 if p.length() < 0.8 else 1.0
    field.tissue_sampler = func(p: Vector3): return 0 if p.x < 0 else 2
    world.add_child(field)
    field.generate_region(AABB(Vector3.ONE * -2, Vector3.ONE * 4))
    field.remesh_all()
    camera = Camera3D.new()
    camera.near = 0.02
    world.add_child(camera)
    camera.current = true
    await shot("01_center", Vector3.ZERO, Vector3(1, 0.15, 0.12))
    await shot("02_diagonal", Vector3.ZERO, Vector3.ONE)
    await shot("03_close", Vector3(0.54, 0, 0), Vector3.RIGHT)
    await shot("04_inner_side", Vector3(0.65, 0, 0), Vector3.LEFT)
    var constrained := field.constrain_eye(Vector3(0.65, 0, 0), Vector3.ZERO, camera.near)
    print("CONTACT desired=(.65,0,0) constrained=", constrained)
    await shot("04_contact_guard", constrained, Vector3.RIGHT)
    if "--intrusion-probe" in OS.get_cmdline_user_args():
        # Deliberately place the eye beyond the physical closed surface;
        # this diagnoses actual invasion separately from near clipping.
        await shot("04_forced_physical_intrusion", Vector3(0.65, 0, 0), Vector3.RIGHT)
    field.set_press(Vector3(0.6, 0, 0), Vector3.LEFT, 0.8)
    await shot("05_press", Vector3(0.54, 0, 0), Vector3.RIGHT)
    field.set_press(Vector3.ZERO, Vector3.ZERO, 0)
    field.remesh_budget_per_frame = 1
    field.dig_at(Vector3(0.55, 0.1, 0.1), 1)
    for frame in range(10):
        await shot("06_removal_%02d" % frame, Vector3.ZERO, Vector3(1, 0.3, 0.3))
    for frame in range(10):
        field.regenerate_all(1, Vector3.ONE * 100, 0.01)
        await shot("07_regen_%02d" % frame, Vector3.ZERO, Vector3(1, 0.3, 0.3))
    print("CAPTURE failures=", failures, " directory=", destination)
    quit(1 if failures else 0)

func shot(label: String, eye: Vector3, direction: Vector3) -> void:
    camera.position = eye
    camera.look_at(eye + direction.normalized(), Vector3.UP)
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    var img := root.get_texture().get_image()
    img.save_png(destination.path_join(label + ".png"))
    var exposed := 0
    for y in range(img.get_height()):
        for x in range(img.get_width()):
            var color := img.get_pixel(x, y)
            if color.r > 0.8 and color.b > 0.8 and color.g < 0.2:
                exposed += 1
    print(label, " background_pixels=", exposed)
    if exposed:
        failures += 1
