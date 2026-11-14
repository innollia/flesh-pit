extends SceneTree

## Old slots are not converted (decision 0012): a real historical v5 file is
## refused and left as it is, and the run stays a new game. The slot checks
## that used to run on that file (exact terrain, permanent melt, resumed
## input, regrowth of a saved hole) run on a slot of the current format that
## holds the same hole and melt.

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
    m.user_keybinds_path = "user://keybinds_test_terrain_old_save.json"
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
        # Loading clears only the corners of the ceiling vent's duct space
        # (main._clear_vent_duct, above the ceiling, out of reach); every
        # other corner must still come back exactly as saved.
        var want: PackedFloat32Array = PackedFloat32Array(entry.density)
        var n: int = m.terrain_config.chunk_size + 1
        var cleared := 0
        for z in range(n):
            for y in range(n):
                for x in range(n):
                    var p: Vector3 = chunk.position + Vector3(x, y, z) * m.terrain_config.cell_size
                    var i: int = chunk._corner_index(x, y, z)
                    if m.in_vent_duct(p) and want[i] > 0.0:
                        want[i] = 0.0
                        cleared += 1
        check(PackedFloat32Array(actual.density) == want,label+" exact density outside the vent duct "+str(c))
        if cleared > 0:
            check(PackedFloat32Array(actual.density) != PackedFloat32Array(entry.density),label+" old flesh cleared from the vent duct "+str(c)+" ("+str(cleared)+" corners)")
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
    check(m.SAVE_VERSION==6,"single-slot format is version 6")
    check(m.has_save_file() and m.save_file_version()==5 and not m.has_current_save(),"historical v5 slot is old: the title offers no continue")
    var fresh: Dictionary = m.serialize()
    check(not m.load_from_disk(),"historical v5 slot is refused by load_from_disk")
    var after_refusal: Dictionary = m.serialize()
    check(after_refusal.terrain==fresh.terrain and after_refusal.progression==fresh.progression and after_refusal.stomach==fresh.stomach,"a refused old slot leaves the new game as it was")
    check(m.terrain.density_at(HOLE)>=0.5 and not m.terrain.is_sealed_at(MELT),"the old slot's hole and melt are not in the new game")
    check(FileAccess.get_sha256(copy_path)==SHA,"refusing the old slot does not rewrite it")
    check(is_equal_approx(m.terrain_config.regen_rate,0.003),"current slower regeneration")
    # the same hole and permanent melt, made in this run, in a slot of the current format
    m.terrain.dig_at(HOLE,1.0)
    check(m.terrain.spray_sphere(MELT,0.3)>0,"fixture: a permanent melt beside the hole")
    var slot: Dictionary = m.serialize()
    check(m.save_to_disk() and m.save_file_version()==m.SAVE_VERSION and m.has_current_save(),"a slot of the current format is offered for continue")
    m.terrain.dig_at(Vector3(0.25,1.25,7.25),1.0)
    check(m.load_from_disk(),"actual current-format load_from_disk")
    compare_chunks(slot.terrain,"current slot load")
    check(m.terrain.density_at(HOLE)<0.5,"saved hole remains open")
    check(m.terrain.is_sealed_at(MELT),"saved permanent melt remains sealed")
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
    check(not first.is_empty() and first.collider.has_meta("fdk_terrain_chunk"),"actual reachable surface after restoring the saved hole")
    var fill_before: float = m.stomach.fill
    var count_before: int = m.excavated_cells
    mouse(true)
    for frame in range(100):
        if not torn.is_empty(): break
        await process_frame
    mouse(false)
    await process_frame
    await process_frame
    check(torn.size()>=1,"actual LMB tears after a real load")
    check(m.excavated_cells-count_before==torn.size(),"restored gameplay actual tear count")
    check(is_equal_approx(m.stomach.fill-fill_before,torn.size()*m.stomach_config.flesh_per_cell),"restored gameplay food matches actual tears")
    for p in torn: check(m.terrain.density_at(p)<0.5,"restored gameplay removes actual density")
    check(not m.chewer.is_chewing(),"restored gameplay real release cancels")
    check(m.deaths==0 and m.hazard.health>0,"no death during resumed input")
    var hole_before: float = m.terrain.density_at(HOLE)
    var melt_before: float = m.terrain.density_at(MELT)
    await create_timer(0.5).timeout
    check(m.terrain.density_at(HOLE)>hole_before,"normal resumed loop continuously regenerates the saved hole")
    check(m.terrain.is_sealed_at(MELT) and is_equal_approx(m.terrain.density_at(MELT),melt_before),"normal resumed loop never heals melted flesh")
    check(m.save_path==copy_path,"one isolated active save path")
    finish()

func finish() -> void:
    print("%d passed, %d failed" % [passed,failed])
    if is_instance_valid(m): m.queue_free()
    quit(1 if failed else 0)
