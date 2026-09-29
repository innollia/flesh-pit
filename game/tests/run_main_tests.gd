extends SceneTree

## main.tscn rule tests: the full loop (settle on flush, teeth + hairs),
## outside vomit, rest points, vent trade, mirror, tools and hands, barrier,
## spray, nerves, crush death + drop, canary, tumors, opening, ending, and
## the restroom geometry rules.
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
        _assert(_m.is_opening(), "the game opens seated on the toilet")
        _m.finish_opening()
        _m.restroom.set_door_open(true, true)
        _m.terrain.remesh_all()
    if _frame < 8:
        return false
    _run()
    _run_systems()
    _m.queue_free()
    print("--- %d passed, %d failed ---" % [_passed, _failures])
    quit(1 if _failures > 0 else 0)
    return true

## Eat out a hollow the way the player would (regrows, unlike carve_sphere).
func _dig(m, center: Vector3, r: float) -> void:
    var step: float = m.terrain_config.cell_size * 0.5
    var n := int(ceil(r / step))
    for z in range(-n, n + 1):
        for y in range(-n, n + 1):
            for x in range(-n, n + 1):
                var p := center + Vector3(x, y, z) * step
                if p.distance_to(center) <= r:
                    m.terrain.dig_at(p, 1.0)

func _look(m, target: Vector3) -> void:
    var eye: Vector3 = m.player.camera.global_position
    var to: Vector3 = target - eye
    var yaw := atan2(-to.x, -to.z)
    m.player.set("_yaw", yaw)
    m.player.rotation = Vector3(0, yaw, 0)
    m.player.camera_pivot.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())
    m.player.force_update_transform()

func _run() -> void:
    var m = _m
    var cap: float = m.stomach_config.capacity
    var over: float = m.stomach_config.overfill_capacity
    var prog: FPProgression = m.progression
    # outside vomit: empties, nothing gained
    m.player.global_position = Vector3(0, 1, 4.0)
    m.stomach.add_flesh(50.0)
    prog.on_flesh_eaten(0, 5)
    m.request_vomit()
    _assert(m.stomach.fill == 0.0 and prog.teeth == 0 and prog.total_hairs() == 0 and prog.pending_hair_total() == 0, "vomit outside the toilet empties the stomach with no reward")
    # vomit button threshold
    m.player.global_position = Vector3(0, 0.95, 0)
    m.stomach.add_flesh(cap + over * 0.2)
    m._process(0.016)
    _assert(not m.vomit_button.shown, "vomit button hidden below the overfill threshold")
    m.stomach.add_flesh(over * 0.3)
    m._process(0.016)
    _assert(m.vomit_button.shown, "vomit button appears past the overfill threshold")
    # toilet: vomit, then the flush settles
    prog.on_flesh_eaten(0, 10)
    m.player.global_position = m.restroom.toilet.global_position + Vector3(0, 0.9, 0.6)
    var amount: float = m.stomach.fill
    m.request_vomit()
    _assert(m.is_settling() and m.settle_camera.current, "vomit at the toilet looks down into the bowl")
    _assert(prog.teeth == 0, "nothing is paid before the flush")
    var got: Dictionary = m.flush()
    _assert(prog.teeth == int(round(amount * FPProgression.TEETH_PER_FLESH)) and got["teeth"] == prog.teeth, "flush puts teeth in the tank (%d)" % prog.teeth)
    _assert(prog.hairs(FPProgression.COMMON) == 10 and prog.hairs("core") == 10, "flush grows 1 common + 1 core hair per core unit")
    _assert(not m.is_settling() and m.vent.mood() == "frantic", "the flush sets the vent being off")
    # shell multipliers
    prog.on_flesh_eaten(1, 1)
    prog.on_flesh_eaten(2, 1)
    _assert(prog.pending_hairs["mantle"] == 2 and prog.pending_hairs["surface"] == 3 and prog.pending_hairs[FPProgression.COMMON] == 5, "shell multiplier x2 mantle, x3 surface")
    prog.discard_stomach()
    # membrane and flesh wall
    _assert(not m.terrain.is_edible_at(Vector3(2.2, 1.0, 0.0)), "restroom side wall membrane is inedible")
    _assert(m.terrain.is_edible_at(Vector3(0.0, 1.0, 2.1)), "flesh beyond the door is edible")
    _assert(m.terrain.density_at(Vector3(0.0, 1.0, 2.3)) >= 0.5, "flesh wall starts right behind the door")
    _assert(m.terrain.density_at(Vector3(0.0, 1.0, 0.0)) < 0.5, "restroom interior is empty")
    _assert(m.terrain.density_at(Vector3(0.0, 1.0, 8.0)) >= 0.5 and m.terrain.density_at(Vector3(-8.0, -6.0, 3.0)) >= 0.5, "everything outside the restroom is flesh")
    _assert(m._world_density(m.RESTROOM_CENTER + Vector3(0, 0, m.OUTER_RADIUS + 1.0)) == 0.0, "outside the outermost shell is open air")
    # eat ray aims into the wall
    m.player.global_position = Vector3(0, 0.95, 1.2)
    m.player.set("_yaw", PI)
    m.player.rotation.y = PI
    m.player.camera_pivot.rotation.x = 0.0
    m.terrain.remesh_all()
    m.player.force_update_transform()
    var hit: Dictionary = m._look_hit()
    _assert(not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk"), "look ray from the doorway hits the flesh wall")
    if not hit.is_empty():
        var ray: Array = m.player.get_look_ray()
        var target: Vector3 = hit.position + (ray[1] as Vector3) * m.terrain_config.cell_size * 0.5
        _assert(m.terrain.density_at(target) >= 0.5, "eat target (hit + half a cell) is solid tissue")
        var before: float = m.stomach.fill
        m.chewer.try_start(target)
        for i in range(60):
            m.chewer.process_chew(0.05)
        _assert(m.stomach.fill > before and prog.pending_hair_total() > 0, "chewing the door wall fills the stomach and grows pending hairs")
    # no flesh surface pokes into the restroom
    var inside := 0
    for ch in m.terrain.get_chunks():
        var mesh: ArrayMesh = ch.get_node("Body/Mesh").mesh
        if mesh == null:
            continue
        var v: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
        for p in v:
            var w: Vector3 = ch.position + p
            var h: Vector3 = FPRestroom.HALF
            if absf(w.x) < h.x + 0.05 and w.y > -0.05 and w.y < 2.0 * h.y + 0.05 and absf(w.z) < h.z + 0.05:
                inside += 1
    _assert(inside == 0, "no flesh vertex inside the restroom box (+5 cm) (found %d)" % inside)
    var door_probe := Vector3(0.0, 1.0, FPRestroom.HALF.z + m.DOOR_GAP + 0.03)
    _assert(m.terrain.density_at(door_probe) >= 0.5, "flesh starts right past the door")
    var fat_inner := 0
    var fat_edge := 0
    for i in range(400):
        var dir := Vector3(sin(i * 1.7), cos(i * 0.9), sin(i * 2.3)).normalized()
        if m._world_tissue(m.RESTROOM_CENTER + dir * (4.0 + fposmod(i * 0.37, 3.5))) == 2:
            fat_inner += 1
        if m._world_tissue(m.RESTROOM_CENTER + dir * 8.6) == 2:
            fat_edge += 1
    _assert(fat_inner == 0 and fat_edge > 100, "fat appears only as the shell boundary band (inner %d, edge %d)" % [fat_inner, fat_edge])
    _assert(m._world_tissue(m.RESTROOM_CENTER + Vector3(12.5, 0.3, 0.2)) in [1, 2, 4], "mantle shell is contractile tissue")
    # chew press
    m.terrain.set_press(Vector3(0, 1, 2.3), Vector3(0, 0, -1), 0.6)
    _assert(is_equal_approx(m.terrain.get_press_amount(), 0.6), "chew press is sent to the terrain shader")
    m.terrain.set_press(Vector3.ZERO, Vector3.BACK, 0.0)

func _run_systems() -> void:
    var m = _m
    var prog: FPProgression = m.progression
    # --- vent: scoop a handful of 4, place, take one
    prog.teeth = 20
    m.player.global_position = m.restroom.toilet.global_position + Vector3(0, 0.9, 0.6)
    m.restroom.set_tank_open(true, true)
    _assert(m.scoop_teeth() == 4 and prog.teeth == 16 and prog.teeth_in_hand == 4, "one handful from the tank is 4 teeth")
    m.vent.open()
    var offer: Array = m.place_teeth_at_vent()
    _assert(offer.size() >= 1 and "barrier" in offer and prog.teeth_in_hand == 0, "a handful at the vent buys a barrier-sized offer (%s)" % [offer])
    _assert(not ("big_saw" in offer), "the big saw is not offered for one handful")
    _assert(m.take_vent_offer("barrier") and prog.barriers == 1 and m.vent.offers.is_empty(), "taking one item pulls the rest back")
    _assert(m.vent.mood() == "calm", "a paid vent being turns calm")
    prog.teeth_in_hand = 1
    _assert(m.place_teeth_at_vent().is_empty() and prog.teeth_in_hand == 1, "too few teeth are pushed back")
    prog.teeth_in_hand = 0
    prog.deepest_shell = 0
    _assert(prog.vent_offer(1000).has("big_saw") == false, "big saw stays locked until the surface shell")
    prog.deepest_shell = 2
    _assert(prog.vent_offer(1000).has("big_saw"), "big saw unlocks at the surface shell")
    _assert(prog.price_for("big_saw") == 20 * prog.price_for("barrier"), "price guide ratio barrier 0.5 : big saw 10")
    m.vent.close()
    # --- mirror: ~30 mutations, no prerequisites, hover a part
    _assert(prog.mutation_count() == 30, "30 mutations defined (%d)" % prog.mutation_count())
    prog.mutation_tree.add_points("mantle", 40)
    _assert(prog.buy_mutation("mantle_clench_jaw"), "a biome mutation is bought with no prerequisite")
    _assert(not prog.can_buy_mutation("core_padded_palm"), "core mutations need core hairs")
    prog.mutation_tree.add_points("core", 100)
    prog.mutation_tree.add_points("surface", 0)
    _assert(prog.buy_mutation("combo_core_surface"), "combination paid from one contributing pool, no chain")
    m.open_mirror()
    m.mirror.show_part("jaw")
    _assert(m.mirror.visible and m.mirror.listed_ids().has("wide_jaw") and m.mirror.listed_ids().has("mantle_clench_jaw"), "hovering the jaw lists jaw mutations")
    m.mirror.close()
    _assert(not m._mirror_open, "mirror closes")
    # --- tools and hands
    _assert(not m.equip_tool("knife"), "cannot equip an unowned knife")
    prog.grant_item("knife")
    prog.grant_item("big_saw")
    prog.grant_item("blender")
    _assert(not prog.can_tear(true), "bare hands cannot tear contractile fibers")
    _assert(m.equip_tool("knife") and prog.can_tear(true) and prog.dig_multiplier() > 1.0, "the knife cuts tough flesh")
    _assert(m.equip_tool("big_saw") and not prog.one_handed_action_allowed(), "the two-handed saw blocks one-handed actions")
    m.toggle_carry()
    m._on_cell_torn(Vector3(0, 1, 3))
    _assert(m.carried_flesh > 0.0 and prog.equipped() == "", "carrying a pile drops the two-handed saw")
    _assert(not m.equip_tool("big_saw") and m.equip_tool("knife"), "while carrying only one-handed tools work")
    m.hands_rig.set_carry(clampf(m.carried_flesh / 40.0, 0.0, 1.0))
    for i in range(8):
        m.hands_rig.step(1.0 / 60.0)
    var pile: MeshInstance3D = m.hands_rig._pile
    var aabb: AABB = pile.mesh.get_aabb()
    var cam: Camera3D = m.player.camera
    var min_y := INF
    var max_y := -INF
    for i in range(8):
        var local: Vector3 = aabb.position + Vector3(aabb.size.x * (i & 1), aabb.size.y * ((i >> 1) & 1), aabb.size.z * ((i >> 2) & 1))
        var sp := cam.unproject_position(pile.global_transform * local)
        min_y = minf(min_y, sp.y)
        max_y = maxf(max_y, sp.y)
    var pct := 100.0 * (max_y - min_y) / float(cam.get_viewport().size.y)
    _assert(pct <= 20.0, "carry pile stays within 20%% of screen height (got %.1f%%)" % pct)
    _assert(not m.drink_blender(), "an uncharged blender does not spin")
    m.blender_charge = 1.0
    var f0: float = m.stomach.fill
    var pile_amt: float = m.carried_flesh
    _assert(m.drink_blender() and is_equal_approx(m.stomach.fill - f0, pile_amt * FPProgression.BLENDER_PACKING), "the blender packs the pile tighter into the stomach")
    m.toggle_carry()
    _assert(m.two_handed_tools_available(), "putting the pile down frees both hands")
    m.equip_tool("")
    # --- barrier: holds the squeeze, 4 states, then breaks with a boing
    var bpos := Vector3(0, 1, 5.0)
    _dig(m, bpos, 1.0)
    var b: FDKBarrier = m.barrier_field.place(bpos, 0.9)
    var steps := []
    b.damage_step_changed.connect(func(s): steps.append(s))
    b.broke.connect(func(r): m._on_barrier_boing(b, r))
    m.player.global_position = Vector3(0, 1, 1.0)
    m.step_world(0.5)
    _assert(m.terrain.density_at(bpos) < 0.5 and not b.is_broken(), "an intact barrier holds the tunnel open")
    var t := 0.0
    while not b.is_broken() and t < 120.0:
        m.step_world(0.25)
        t += 0.25
    _assert(b.is_broken() and steps.has(1) and steps.has(2) and steps.has(3), "the barrier gives way in 33%% steps and breaks (%.1fs, %s)" % [t, steps])
    _assert(m.terrain.density_at(bpos) >= 0.3, "breaking releases the squeeze into the tunnel (boing)")
    # --- danger and regen rise outward
    _assert(m._regen_scale(m.RESTROOM_CENTER + Vector3(0, 0, 4)) < m._regen_scale(m.RESTROOM_CENTER + Vector3(0, 0, 13)) and m._regen_scale(m.RESTROOM_CENTER + Vector3(0, 0, 13)) < m._regen_scale(m.RESTROOM_CENTER + Vector3(0, 0, 22)), "danger and regrowth rise from core to surface")
    # --- spray: permanent, and the flesh around regrows faster
    var sp_pos := Vector3(3.0, 1.0, 6.0)
    var sealed := FDKSprayCan.new(FDKSprayCan.Tier.DEEP).apply(m.terrain, sp_pos)
    for i in range(40):
        m.step_world(0.5)
    _assert(sealed > 0 and m.terrain.density_at(sp_pos) < 0.5 and not m.terrain.is_edible_at(sp_pos), "sprayed flesh dissolves for good")
    var sch: FDKChunk = m.terrain.get_chunk(m.terrain.world_to_chunk_coord(sp_pos))
    _assert(sch._any_sealed, "the sprayed chunk regrows faster around the tunnel")
    # --- nerves: touching one contracts the tunnel and hurts
    var np := Vector3(-2.0, 3.5, 4.0)
    _dig(m, np, 1.2)
    var d0: float = m.terrain.density_at(np + Vector3(0.5, 0, 0))
    m._on_nerve_disturbed(np)
    _assert(m.terrain.density_at(np + Vector3(0.5, 0, 0)) > d0, "a touched nerve squeezes the tunnel shut")
    m.player.global_position = np
    var h0: float = m.hazard.health
    m._step_hazards(0.5)
    _assert(m.hazard.health < h0, "the convulsing nerve hurts nearby")
    m.hazard.reset()
    m._hazards.clear()
    _run_death(m, prog)

func _run_death(m, prog: FPProgression) -> void:
    # --- crush death creeps in over 6 s, then drops the stomach + consumables
    var cp := Vector3(6.0, 1.0, 6.0) # solid flesh, a boxed-in spot
    m.player.global_position = cp
    _dig(m, cp, 0.6)
    _assert(m.is_trapped(), "flesh closed on all sides counts as trapped")
    m.stomach.fill = 30.0
    prog.barriers = 2
    prog.discard_stomach()
    prog.on_flesh_eaten(0, 3)
    var deaths0: int = m.deaths
    m._step_hazards(3.0)
    _assert(m.deaths == deaths0 and absf(m.crush_progress() - 0.5) < 0.01, "crush death approaches gradually (half way at 3 s)")
    m._step_hazards(2.9)
    _assert(m.deaths == deaths0, "still alive just before 6 s")
    m._step_hazards(0.2)
    _assert(m.deaths == deaths0 + 1, "crushed after 6 s boxed in")
    _assert(m.stomach.fill == 0.0 and prog.barriers == 0 and m.death_drop.active and m.death_drop.last_known_position.is_equal_approx(cp), "death drops stomach and consumables at the marked spot")
    _assert(m.player.global_position.is_equal_approx(m.START_POS) and prog.owns("knife"), "death is not a wipe: back in the restroom, tools kept")
    m.death_drop.carry_along(Vector3(0.3, 0, 0))
    _assert(m.death_drop.last_known_position.is_equal_approx(cp), "the marker stays at the last known spot while flesh pushes the drop")
    m.player.global_position = m.death_drop.current_position
    m._step_death_drop(0.016)
    _assert(not m.death_drop.active and m.stomach.fill == 30.0 and prog.barriers == 2 and prog.pending_hair_total() == 6, "recovering the drop returns everything")
    m.stomach.fill = 0.0
    prog.discard_stomach()
    # --- canary: pulled from the hole, chirps when the route back narrows
    m.player.global_position = m.START_POS
    _assert(m.take_canary() and m.has_canary, "a canary comes out of the hole")
    var chirps := []
    m.canary_chirp.connect(func(u): chirps.append(u))
    m.player.global_position = Vector3(0, 1, 7.5)
    for i in range(3):
        m._step_canary(0.3)
    _assert(chirps.size() > 0 and m.canary_urgency > 0.0, "the canary chirps when flesh blocks the way back")
    prog.canary_feed = 1
    _assert(m.feed_canary() and m.canary_feed_left > 0.0, "feeding makes the canary warn earlier")
    m._step_canary(0.3)
    _assert(m.canary.block_density < 0.85, "a fed canary counts looser flesh as blocking")
    # --- rest points: settle there, nothing else
    var rp: Vector3 = m.rest_points[0]
    _assert(m.rest_points.size() == 9 and m.terrain.density_at(rp) < 0.5, "9 identical rest points, hollow inside the flesh")
    m.player.global_position = rp + Vector3(0, -FPWorldFeatures.CONTAINER_HALF.y + 0.9, -FPWorldFeatures.CONTAINER_HALF.z + 0.5)
    m.stomach.add_flesh(50.0)
    prog.on_flesh_eaten(0, 2)
    var t0: int = prog.teeth
    m.request_vomit()
    _assert(not m.is_settling() and prog.teeth > t0 and prog.pending_hair_total() == 0, "vomiting at a rest point settles on the spot")
    # --- tumors: 12, eat for tumor points or carry one per bag to the toilet
    _assert(m.tumor_nodes.size() == 12, "12 tumors in the world")
    var tn: Node3D = m.tumor_nodes[0]
    m.player.global_position = tn.global_position - Vector3(0, 0.6, 0)
    _assert(m.pick_up_tumor() and prog.tumor_in_hand(), "without the bag a tumor fills one hand")
    _assert(not m.two_handed_tools_available(), "a tumor in hand blocks two-handed tools")
    var t2: Node3D = m.tumor_nodes[1]
    m.player.global_position = t2.global_position - Vector3(0, 0.6, 0)
    _assert(not m.pick_up_tumor(), "without the bag only one tumor can be carried")
    prog.grant_item("tumor_bag")
    _assert(m.pick_up_tumor() and prog.tumors.carried_count() == 2, "the basketball bag holds one more tumor")
    var t3: Node3D = m.tumor_nodes[2]
    m.player.global_position = t3.global_position - Vector3(0, 0.6, 0)
    _assert(not m.pick_up_tumor(), "one bag holds only one tumor")
    m.player.global_position = m.restroom.toilet.global_position + Vector3(0, 0.9, 0.6)
    var tt: int = prog.teeth
    m.start_settlement()
    m.flush()
    _assert(prog.teeth == tt + 2 * FPProgression.TUMOR_TOOTH_PAYOUT and prog.tumors.codex_count() == 2, "tumors thrown in the toilet pay teeth and fill the codex")
    m.player.global_position = t3.global_position - Vector3(0, 0.6, 0)
    _assert(m.eat_tumor() and prog.tumors.tumor_points == 1, "eating a tumor gives tumor-only points")
    var tm := prog.buy_tumor_mutation()
    _assert(tm in FPProgression.TUMOR_MUTATIONS and prog.tumor_mutations.size() == 1, "tumor points buy a random large mutation (%s)" % tm)
    # --- save v3 round trip of the progression
    var saved: Dictionary = m.serialize()
    _assert(int(saved["version"]) == 3 and int(saved["progression"]["version"]) == 2, "save is versioned (main 3, progression 2)")
    var teeth_saved: int = prog.teeth
    prog.teeth = 0
    m.deserialize(saved)
    _assert(m.progression.teeth == teeth_saved and m.progression.owns("knife") and m.progression.tumors.codex_count() == 2 and not m.tumor_nodes[0].visible, "save/load restores teeth, tools, codex and taken tumors")
    var old := {"version": 2, "money": 77, "mutation_points": 5}
    m.deserialize(old)
    _assert(m.progression.teeth == 77 and m.progression.hairs(FPProgression.COMMON) == 5, "v2 saves migrate money -> teeth, points -> hairs")
    # --- ending: breaking out of the outermost shell
    var got_end := [false]
    m.ending_reached.connect(func(): got_end[0] = true)
    m.player.global_position = m.RESTROOM_CENTER + Vector3(0, 0, m.OUTER_RADIUS)
    m.step_world(0.016)
    _assert(m.ended and got_end[0] and m.ending.active, "breaking out of the outermost shell starts the ending")
    _assert(m.melody_level() > 0.9, "the melody is loudest at the surface")
