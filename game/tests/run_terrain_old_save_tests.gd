extends SceneTree

var m: Node3D
var passed := 0
var failed := 0
var copy_path: String
var old_data: Dictionary
var torn: Array[Vector3] = []
const HOLE := Vector3(0.25,1.25,4.25)
const MELT := Vector3(1.25,1.25,4.25)
const SHA := "71946d862fd19b6e17c9ddd12880c8838b7664da00c07c3e057e052bd6385f02"

func check(ok: bool,label: String) -> void:
    if ok: passed += 1
    else:
        failed += 1
        print("FAIL: ",label)

func _init() -> void:
    var folder := ProjectSettings.globalize_path("res://../.dryforge/evidence/old-save-roundtrip")
    DirAccess.make_dir_recursive_absolute(folder)
    copy_path = folder.path_join("isolated-copy.bin")
    var compressed := FileAccess.get_file_as_bytes("res://tests/fixtures/terrain_old_v5.bin.gz")
    var raw := compressed.decompress(6722764,FileAccess.COMPRESSION_GZIP)
    check(raw.size() == 6722764,"historical fixture decompressed byte length")
    if raw.size() != 6722764:
        finish.call_deferred()
        return
    var destination := FileAccess.open(copy_path,FileAccess.WRITE)
    destination.store_buffer(raw)
    destination.close()
    check(FileAccess.get_sha256(copy_path) == SHA,"historical v5 exact binary hash")
    var source := FileAccess.open(copy_path,FileAccess.READ)
    old_data = source.get_var()
    source.close()
    check(int(old_data.version)==5,"fixture is actual old version 5")
    m = load("res://main/scenes/main.tscn").instantiate()
    m.rest_seed = 1337
    m.save_path = copy_path
    root.add_child(m)
    run.call_deferred()

func compare_chunks(expected: Dictionary,label: String) -> void:
    for entry in expected.chunks:
        var c: Array = entry.chunk_coord
        var chunk: FDKChunk = m.terrain.get_chunk(Vector3i(c[0],c[1],c[2]))
        check(chunk != null,label+" loaded chunk "+str(c))
        if chunk == null: continue
        var actual := chunk.serialize()
        check(actual.density == entry.density,label+" exact density "+str(c))
        check(actual.tissue == entry.tissue,label+" exact tissue "+str(c))
        check(actual.sealed == entry.sealed,label+" permanent melt mask "+str(c))
        check(actual.boost == entry.boost,label+" spray boost "+str(c))

func mouse(held: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = held
    Input.parse_input_event(event)

func run() -> void:
    await process_frame
    m.save_path = copy_path
    check(m.load_from_disk(),"actual historical load_from_disk")
    compare_chunks(old_data.terrain,"historical load")
    check(m.SAVE_VERSION==5,"single-slot format unchanged")
    check(is_equal_approx(m.terrain_config.regen_rate,0.003),"old slot uses current slower regeneration")
    check(m.terrain.density_at(HOLE)<0.5,"historical hole remains open")
    check(m.terrain.is_sealed_at(MELT),"historical permanent melt remains sealed")
    var original_density: PackedFloat32Array = m.terrain.get_chunk(Vector3i.ZERO)._original_density.duplicate()
    m.terrain.dig_at(Vector3(0.25,1.25,5.25),1.0)
    m.stomach.add_flesh(8.0)
    var saved: Dictionary = m.serialize()
    check(m.save_to_disk(),"actual isolated atomic save")
    check(not FileAccess.file_exists(copy_path+".tmp"),"successful save leaves no temporary slot")
    m.terrain.dig_at(Vector3(0.25,1.25,6.25),1.0)
    m.stomach.add_flesh(20.0)
    check(m.load_from_disk(),"actual isolated load after further mutation")
    compare_chunks(saved.terrain,"roundtrip")
    check(m.stomach.serialize()==saved.stomach,"saved stomach restored exactly")
    check(m.terrain.get_chunk(Vector3i.ZERO)._original_density==original_density,"restoration preserves original regeneration target")
    check(m.terrain.is_sealed_at(MELT),"roundtrip permanent melt preserved")
    # The old hole is real saved geometry; no replacement density sampler.
    m.finish_opening()
    m.player.global_position = HOLE-Vector3.UP*m.player.eye_pivot_y(false)
    m.player.velocity = Vector3.ZERO
    m.player._yaw = 0
    m.player.rotation.y = 0
    m.player._pitch = 0
    m.player.camera_pivot.rotation.x = 0
    m._crush_t = 0.0
    m.hazard.health = 100
    m.carry_mode = false
    m.equip_tool("")
    InputMap.action_erase_events("fdk_eat")
    var binding := InputEventMouseButton.new()
    binding.button_index = MOUSE_BUTTON_LEFT
    InputMap.action_add_event("fdk_eat",binding)
    m.chewer.cell_torn.connect(func(p): torn.append(p))
    await physics_frame
    await physics_frame
    await process_frame
    var first: Dictionary = m._look_hit()
    check(not first.is_empty() and first.collider.has_meta("fdk_terrain_chunk"),"actual reachable surface after restoring saved hole")
    var fill_before: float = m.stomach.fill
    var count_before: int = m.excavated_cells
    mouse(true)
    for frame in range(100):
        if not torn.is_empty(): break
        await process_frame
    mouse(false)
    await process_frame
    await process_frame
    check(torn.size()>=1,"actual LMB tears after historical load")
    check(m.excavated_cells-count_before==torn.size(),"restored gameplay actual tear count")
    check(is_equal_approx(m.stomach.fill-fill_before,torn.size()*m.stomach_config.flesh_per_cell),"restored gameplay food matches actual tears")
    for p in torn: check(m.terrain.density_at(p)<0.5,"restored gameplay removes actual density")
    check(not m.chewer.is_chewing(),"restored gameplay real release cancels")
    check(m.deaths==int(old_data.get("deaths",0)) and m.hazard.health>0,"no death reset during resumed input")
    var hole_before: float = m.terrain.density_at(HOLE)
    var melt_before: float = m.terrain.density_at(MELT)
    await create_timer(0.5).timeout
    check(m.terrain.density_at(HOLE)>hole_before,"normal resumed loop continuously regenerates old hole")
    check(m.terrain.is_sealed_at(MELT) and is_equal_approx(m.terrain.density_at(MELT),melt_before),"normal resumed loop never heals melted flesh")
    check(m.save_path==copy_path,"one isolated active save path")
    finish()

func finish() -> void:
    print("%d passed, %d failed" % [passed,failed])
    if is_instance_valid(m): m.queue_free()
    quit(1 if failed else 0)
