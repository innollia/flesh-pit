extends SceneTree
var m: Node3D
var passed := 0
var failed := 0
var destination: String
## First frames after a real load show no outside through a saved hole.
## The historical v5 file is refused (decision 0012: old slots are not
## converted), so the slot is written here in the current format by a first
## Main that digs the hole, and a second, fresh Main loads it.
const HOLE := Vector3(0.25,1.25,4.25)
const SHA := "71946d862fd19b6e17c9ddd12880c8838b7664da00c07c3e057e052bd6385f02"
func _new_main() -> Node3D:
    var made: Node3D = load("res://main/scenes/main.tscn").instantiate()
    made.user_keybinds_path = "user://keybinds_test_terrain_main_restore.json"
    made.rest_seed = 1337
    made.save_path = destination.path_join("copy.bin")
    return made
func _init() -> void:
    destination = ProjectSettings.globalize_path("res://../.dryforge/evidence/old-save-gpu")
    DirAccess.make_dir_recursive_absolute(destination)
    var compressed := FileAccess.get_file_as_bytes("res://tests/fixtures/terrain_old_v5.bin.gz")
    var raw := compressed.decompress(6722764,FileAccess.COMPRESSION_GZIP)
    if raw.size() != 6722764:
        print("0 passed, 1 failed")
        quit(1)
        return
    var file := FileAccess.open(destination.path_join("copy.bin"),FileAccess.WRITE)
    file.store_buffer(raw)
    file.close()
    if FileAccess.get_sha256(destination.path_join("copy.bin")) != SHA:
        print("0 passed, 1 failed")
        quit(1)
        return
    m = _new_main()
    root.add_child(m)
    run.call_deferred()
func run() -> void:
    await process_frame
    root.size = Vector2i(640,360)
    m.save_path = destination.path_join("copy.bin")
    if not m.load_from_disk() and not m.has_current_save() and FileAccess.get_sha256(m.save_path) == SHA: passed += 1
    else: failed += 1
    m.terrain.dig_at(HOLE,1.0)
    if m.save_to_disk() and m.has_current_save(): passed += 1
    else: failed += 1
    m.queue_free()
    await process_frame
    await process_frame
    m = _new_main()
    root.add_child(m)
    await process_frame
    m.save_path = destination.path_join("copy.bin")
    var loaded: bool = m.load_from_disk()
    if loaded and m.terrain.density_at(HOLE) < 0.5: passed += 1
    else: failed += 1
    m.finish_opening()
    var hole := HOLE
    m.player.global_position = hole-Vector3.UP*m.player.eye_pivot_y(false)
    m.player.velocity = Vector3.ZERO
    m.player._yaw = 0
    m.player.rotation.y = 0
    m.player._pitch = 0
    m.player.camera_pivot.rotation.x = 0
    m.environment.background_color = Color(1,0,1)
    m.apply_atmosphere_now()
    for frame in range(10):
        await process_frame
        await RenderingServer.frame_post_draw
        var img := root.get_texture().get_image()
        if img.get_size() != Vector2i(640,360):
            failed += 1
        img.save_png(destination.path_join("load_%02d.png" % frame))
        var exposed := 0
        for y in range(img.get_height()):
            for x in range(img.get_width()):
                var color := img.get_pixel(x,y)
                if color.r > 0.8 and color.b > 0.8 and color.g < 0.2: exposed += 1
        print("OLD_SAVE_LOAD frame=",frame," exposed=",exposed," eye=",m.player.camera.global_position," density=",m.terrain.density_at(m.player.camera.global_position))
        if exposed == 0: passed += 1
        else: failed += 1
    # A genuinely exposed background must be detectable by the same renderer.
    m.terrain.hide()
    await process_frame
    await RenderingServer.frame_post_draw
    var control := root.get_texture().get_image()
    var control_pixels := 0
    for y in range(control.get_height()):
        for x in range(control.get_width()):
            var color := control.get_pixel(x,y)
            if color.r > 0.8 and color.b > 0.8 and color.g < 0.2:
                control_pixels += 1
    print("OLD_SAVE_POSITIVE_CONTROL exposed=",control_pixels)
    if control_pixels > 1000: passed += 1
    else: failed += 1
    m.terrain.show()
    print("%d passed, %d failed" % [passed,failed])
    m.queue_free()
    await process_frame
    quit(1 if failed else 0)
