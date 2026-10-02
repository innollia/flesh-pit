extends SceneTree

var main: Node3D
var frame := 0
var destination: String
var eye_delta := Vector3.ZERO
var failures := 0
var frames_saved := 0

func _init() -> void:
    destination = ProjectSettings.globalize_path("res://../.dryforge/evidence/terrain-controller")
    DirAccess.make_dir_recursive_absolute(destination)
    main = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
    main.save_path = destination.path_join("isolated.save")
    root.add_child(main)
    # Main input wiring belongs to T3. Apply its future helper hookup here
    # at the render boundary, restoring the desired animation pose first.
    process_frame.connect(func():
        if is_instance_valid(main.player):
            main.player.camera.position -= eye_delta
            eye_delta = Vector3.ZERO
    )
    RenderingServer.frame_pre_draw.connect(func():
        if is_instance_valid(main.player):
            var desired: Vector3 = main.player.camera.global_position
            var desired_local: Vector3 = main.player.camera.position
            var guarded: Vector3 = main.terrain.constrain_eye(desired, main.player.global_position, main.player.camera.near)
            main.player.camera.global_position = guarded
            eye_delta = main.player.camera.position - desired_local
    )

func _process(_delta: float) -> bool:
    frame += 1
    if frame == 3:
        main.finish_opening()
        main.restroom.set_door_open(true, true)
        for z in range(11):
            for x in range(-1, 2):
                for y in range(4):
                    main.terrain.dig_at(Vector3(x * 0.5 + 0.25, y * 0.5 + 0.25, 1.9 + z * 0.5), 1)
        main.terrain.remesh_all()
        main.player.global_position = Vector3(0, 0.95, 4.2)
        main.player._yaw = -PI * 0.5
        main.player._pitch = 0
        main.environment.background_color = Color(1, 0, 1)
        main.apply_atmosphere_now()
        Input.action_press("fdk_move_forward")
    if frame == 24:
        Input.action_release("fdk_move_forward")
        main.player._pitch = 1.4
        Input.action_press("fdk_jump")
    if frame == 42:
        Input.action_release("fdk_jump")
        main.terrain.set_press(main.player.camera.global_position + Vector3.UP * 0.15, Vector3.DOWN, 0.9)
    if frame == 63:
        main.terrain.set_press(Vector3.ZERO, Vector3.ZERO, 0)
        main._on_nerve_disturbed(main.player.camera.global_position)
    if frame == 72:
        main._on_nerve_disturbed(main.player.global_position)
    if frame >= 12 and frame <= 60 and frame % 3 == 0 or frame >= 63 and frame <= 120:
        capture.call_deferred(frame)
    if frame == 123:
        main.terrain.set_press(Vector3.ZERO, Vector3.ZERO, 0)
        print("CONTROLLER_CAPTURE %d frames, %d background failures, body=%s eye=%s" % [frames_saved, failures, main.player.global_position, main.player.camera.global_position])
        quit(1 if failures else 0)
    return false

func capture(index: int) -> void:
    await RenderingServer.frame_post_draw
    var img := root.get_texture().get_image()
    img.save_png(destination.path_join("frame_%03d.png" % index))
    var exposed := 0
    for y in range(img.get_height()):
        for x in range(img.get_width()):
            var color := img.get_pixel(x, y)
            if color.r > 0.8 and color.b > 0.8 and color.g < 0.2:
                exposed += 1
    frames_saved += 1
    if exposed: failures += 1
    print("CONTROLLER frame=", index, " background_pixels=", exposed, " eye_correction=", eye_delta.length(), " body=", main.player.global_position)
