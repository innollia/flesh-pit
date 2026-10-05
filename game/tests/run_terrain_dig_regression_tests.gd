extends SceneTree

# Observation only: sample after the normal Main and hand process writers.
# This node never calls the guard and never writes camera or player transforms.
class GuardObservation:
    extends Node
    var game: Node3D
    var actual := Vector3.ZERO
    var desired := Vector3.ZERO
    var expected := Vector3.ZERO
    var samples := 0
    func _process(_delta: float) -> void:
        var camera: Camera3D = game.player.camera
        desired = game.player.camera_pivot.to_global(game.hand_motions._cam_rest_offset())
        expected = game.terrain.constrain_eye(desired, game.player.global_position, camera.near)
        actual = camera.global_position
        samples += 1
# Exercise the real main loop and physical mouse input, including its hand
# animation and world updates. Save isolation is supplied by the check runner.
var m: Node3D
var passed := 0
var failed := 0
var torn: Array[Vector3] = []
var center := Vector3(8, 5, 8)
var grabs := 0
var progress := 0
var releases := 0
var fixed_down_support: StaticBody3D

func _init() -> void:
    Engine.max_fps = 60
    m = load("res://main/scenes/main.tscn").instantiate()
    m.rest_seed = 1337
    root.add_child(m)
    run.call_deferred()

func check(ok: bool, label: String) -> void:
    if ok: passed += 1
    else:
        failed += 1
        print("FAIL: ", label)

func mouse(held: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = held
    Input.parse_input_event(event)

func aim(direction: Vector3) -> void:
    var dir := direction.normalized()
    m.player._yaw = atan2(-dir.x, -dir.z)
    m.player._pitch = asin(clampf(dir.y, -1, 1))
    m.player.rotation.y = m.player._yaw
    m.player.camera_pivot.rotation.x = m.player._pitch

func fixture(direction: Vector3, radius := 1.2, tissue := 0) -> void:
    mouse(false)
    if is_instance_valid(fixed_down_support): fixed_down_support.queue_free()
    m._crush_t = 0.0
    await create_timer(0.5).timeout
    m.terrain.fill_box_uniform(AABB(center - Vector3.ONE * 3, Vector3.ONE * 6), 1.0, tissue)
    m.terrain.carve_sphere(center, radius)
    # Leave room below the eye for the actual capsule rather than placing
    # the standing body's feet inside a sphere centered on its head.
    m.terrain.carve_sphere(center - Vector3.UP * 0.7, radius)
    m.terrain.remesh_all()
    m.player.global_position = center - Vector3.UP * m.player.eye_pivot_y(false)
    m.player.velocity = Vector3.ZERO
    m.stomach.fill = 0
    m.carried_flesh = 0
    m.excavated_cells = 0 # independent cavities start before nerve unlock
    m._crush_t = 0.0
    m.hazard.health = 100
    m.carry_mode = false
    m.equip_tool("")
    aim(direction)
    await physics_frame
    await physics_frame
    await process_frame
    torn.clear()

func ray(origin: Vector3, direction: Vector3, distance: float) -> Dictionary:
    var q := PhysicsRayQueryParameters3D.create(origin, origin + direction * distance)
    q.exclude = [m.player.get_rid()]
    return m.get_world_3d().direct_space_state.intersect_ray(q)

func mesh_triangle_count() -> int:
    var result := 0
    for chunk in m.terrain.get_chunks():
        var mesh: Mesh = chunk._mesh_instance.mesh
        if mesh == null: continue
        for surface in range(mesh.get_surface_count()):
            result += mesh.surface_get_array_len(surface) / 3
    return result

func hold_case(direction: Vector3, label: String, radius := 1.2) -> void:
    await fixture(direction, radius)
    var origin: Vector3 = m.player.camera.global_position
    var before: Dictionary = m._look_hit()
    check(not before.is_empty() and before.collider.has_meta("fdk_terrain_chunk"), label + " real surface hit")
    var mesh_before := mesh_triangle_count()
    var count_before: int = m.excavated_cells
    mouse(true)
    await create_timer(2.05).timeout
    mouse(false)
    await process_frame
    await process_frame
    check(torn.size() >= 2, label + " held LMB tears and proceeds to next cell")
    check(m.excavated_cells - count_before == torn.size(), label + " tear events agree with excavated cells")
    check(is_equal_approx(m.stomach.fill, torn.size() * m.stomach_config.flesh_per_cell), label + " food only for real tears (fill %.1f, tears %d)" % [m.stomach.fill, torn.size()])
    for p in torn:
        check(m.terrain.density_at(p) < m.terrain.config.iso_level, label + " torn cell density is empty " + str(p))
    m.terrain.remesh_all()
    await physics_frame
    await physics_frame
    check(mesh_triangle_count() != mesh_before, label + " visible mesh geometry changes")
    if not before.is_empty():
        var after := ray(origin, direction.normalized(), 2.5)
        check(after.is_empty() or origin.distance_to(after.position) > origin.distance_to(before.position) + 0.1, label + " collision recedes with visible hole")
    check(not m.chewer.is_chewing(), label + " physical LMB release stops chew")

func blocker(at: Vector3, direction: Vector3) -> StaticBody3D:
    var body := StaticBody3D.new()
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(1.2, 1.2, 0.08)
    shape.shape = box
    body.add_child(shape)
    m.add_child(body)
    body.global_position = at
    body.look_at(at + direction, Vector3.UP)
    return body

func shared_vertex_case() -> void:
    await fixture(Vector3.ONE, 1.2)
    var eye: Vector3 = m.player.camera.global_position
    var missed: Array[Vector3] = []
    # Query real mesh vertices, rather than asserting an implementation
    # constant or assuming that one arbitrary diagonal reproduces a miss.
    for chunk in m.terrain.get_chunks():
        if chunk._collision.shape == null: continue
        var faces: PackedVector3Array = chunk._collision.shape.get_faces()
        for point in faces:
            var delta: Vector3 = point + chunk.position - eye
            if delta.length() < 0.3 or delta.length() > 2.0: continue
            if ray(eye, delta.normalized(), 2.5).is_empty():
                missed.append(delta.normalized())
                if missed.size() >= 6: break
        if missed.size() >= 6: break
    check(not missed.is_empty(), "fixture reproduces a numerical shared-vertex physics miss")
    for direction in missed:
        aim(direction)
        var hit: Dictionary = m._look_hit()
        check(not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk"), "bounded physical fallback reaches shared vertex " + str(direction))
        if not hit.is_empty():
            var actual_ray: Array = m.player.get_look_ray()
            var offset: Vector3 = hit.position - actual_ray[0]
            check(offset.cross(actual_ray[1]).length() <= 0.0011, "shared-vertex fallback remains within one millimeter of aim")
            check(offset.length() <= m.progression.reach(), "shared-vertex fallback retains reach")

func published_contact_occlusion_case() -> void:
    await fixture(Vector3.FORWARD)
    var origin: Vector3 = m.player.camera.global_position
    var rear := blocker(origin + Vector3.FORWARD * 2.0, Vector3.FORWARD)
    await physics_frame
    await physics_frame
    # Deterministically represent the PhysicsServer cache gap while keeping
    # the actual published ConcavePolygonShape3D geometry intact. Restore
    # every body immediately after these synchronous query assertions.
    var disabled: Array[StaticBody3D] = []
    for chunk in m.terrain.get_chunks():
        if chunk._collision.shape != null:
            var body: StaticBody3D = chunk.get_body()
            PhysicsServer3D.body_set_shape_disabled(body.get_rid(), 0, true)
            disabled.append(body)
    var physical := ray(origin, Vector3.FORWARD, m.progression.reach())
    check(not physical.is_empty() and physical.collider == rear, "cache-gap fixture physically sees the rear prop")
    var gap_started := Time.get_ticks_usec()
    for i in range(100): m._look_hit()
    print("AIM_TIMING cache_gap_avg_ms=", (Time.get_ticks_usec() - gap_started) / 100000.0)
    var contact: Dictionary = m._look_hit()
    check(not contact.is_empty() and contact.collider.has_meta("fdk_terrain_chunk") and origin.distance_to(contact.position) < 2.0, "published flesh ahead of rear prop wins during physics cache gap")
    rear.global_position = origin + Vector3.FORWARD * 0.35
    rear.force_update_transform()
    var front: Dictionary = m._look_hit()
    check(not front.is_empty() and front.collider == rear, "front prop wins over published terrain in cache gap")
    for body in disabled:
        PhysicsServer3D.body_set_shape_disabled(body.get_rid(), 0, false)
    rear.queue_free()
    await physics_frame
    await physics_frame
    for i in range(3):
        m._look_hit()
        await physics_frame
    var stable_started := Time.get_ticks_usec()
    for i in range(100): m._look_hit()
    print("AIM_TIMING stable_physics_avg_ms=", (Time.get_ticks_usec() - stable_started) / 100000.0)

func newly_published_front_chunk_case() -> void:
    await fixture(Vector3.RIGHT)
    m.terrain.fill_box_uniform(AABB(Vector3(4, 2, 4), Vector3(8, 7, 8)), 0.0, 0)
    m.terrain.fill_box_uniform(AABB(Vector3(8.5, 3, 5), Vector3(0.6, 4, 4)), 1.0, 0)
    m.terrain.remesh_all()
    m.player.global_position = Vector3(6.8, 5, 7) - Vector3.UP * m.player.eye_pivot_y(false)
    m.player.velocity = Vector3.ZERO
    aim(Vector3.RIGHT)
    await physics_frame
    await physics_frame
    for i in range(3):
        m._look_hit()
        await physics_frame
    var origin: Vector3 = m.player.camera.global_position
    var far: Dictionary = ray(origin, Vector3.RIGHT, m.progression.reach())
    check(not far.is_empty() and far.collider.has_meta("fdk_terrain_chunk"), "stable rear terrain fixture has a real physics face")
    if far.is_empty(): return
    var far_shape: RID = (far.collider.get_parent() as FDKChunk)._collision.shape.get_rid()
    # Add a separate, closer chunk surface without changing the old rear
    # chunk. Only its PhysicsServer visibility is suppressed synchronously.
    m.terrain.fill_box_uniform(AABB(Vector3(7.5, 3, 5), Vector3(0.1, 4, 4)), 1.0, 0)
    var near_chunk: FDKChunk = m.terrain.get_chunk(Vector3i(0, 0, 0))
    near_chunk.remesh(true)
    var near_body: StaticBody3D = near_chunk.get_body()
    PhysicsServer3D.body_set_shape_disabled(near_body.get_rid(), 0, true)
    var physical: Dictionary = ray(origin, Vector3.RIGHT, m.progression.reach())
    check(not physical.is_empty() and physical.collider == far.collider and (far.collider.get_parent() as FDKChunk)._collision.shape.get_rid() == far_shape, "new front cache gap leaves the rear terrain shape unchanged")
    var actual: Dictionary = m._look_hit()
    check(not actual.is_empty() and actual.collider == near_body and origin.distance_to(actual.position) < origin.distance_to(far.position) - 0.5, "new front published terrain wins over an already stable rear physics face")
    PhysicsServer3D.body_set_shape_disabled(near_body.get_rid(), 0, false)
    await physics_frame
    await physics_frame

func run() -> void:
    await create_timer(0.1).timeout
    m.finish_opening()
    # Ready has now registered the game actions. Override only this process.
    InputMap.action_erase_events("fdk_eat")
    var binding := InputEventMouseButton.new()
    binding.button_index = MOUSE_BUTTON_LEFT
    InputMap.action_add_event("fdk_eat", binding)
    m.chewer.cell_torn.connect(func(p): torn.append(p))
    m.chewer.grab_started.connect(func(_p): grabs += 1)
    m.chewer.chew_progress.connect(func(_r, _p): progress += 1)
    m.chewer.released.connect(func(): releases += 1)
    for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK, Vector3(1, 0.9, 0.8), Vector3(-1, 0.4, -1), Vector3.ONE]:
        # The extra capsule-clearance sphere puts the old downward floor
        # outside reach after its first bite. Keep two surfaces reachable here;
        # the original wide floor is separately checked as a reach boundary.
        await hold_case(direction, "direction " + str(direction), 1.0 if direction == Vector3.DOWN else 1.2)
    await down_reach_boundary_case()
    await hold_case(Vector3.RIGHT, "close wall", 0.85)
    center = Vector3(7.5, 5, 7.5)
    await hold_case(Vector3.ONE, "chunk corner")
    center = Vector3(8, 5, 8)
    await shared_vertex_case()
    await published_contact_occlusion_case()
    await newly_published_front_chunk_case()
    await fixture(Vector3.FORWARD)
    mouse(true)
    await create_timer(0.2).timeout
    check(m.chewer.is_chewing(), "normal mouse starts grab before blocker appears")
    var prop := blocker(m.player.camera.global_position + Vector3.FORWARD * 0.4, Vector3.FORWARD)
    await physics_frame
    await physics_frame
    await create_timer(0.8).timeout
    check(torn.is_empty() and m.stomach.fill == 0, "new prop cancels locked grab without remote tear")
    check(not m.chewer.is_chewing(), "locked grab rechecks occlusion")
    mouse(false)
    prop.queue_free()
    await fixture(Vector3.RIGHT)
    mouse(true)
    await create_timer(0.2).timeout
    aim(Vector3.LEFT)
    await create_timer(0.45).timeout
    check(torn.is_empty(), "looking away cancels old target before tear")
    mouse(false)
    await process_frame
    await process_frame
    check(not m.chewer.is_chewing(), "input release cancels changed target")
    await fixture(Vector3.RIGHT)
    mouse(true)
    await create_timer(0.2).timeout
    # Arrange a real open cavity at the away position before moving there;
    # the locked cell is then beyond reach, with no new surface in reach.
    m.terrain.carve_sphere(center - Vector3.RIGHT * 5, 3.5)
    m.terrain.remesh_all()
    m.player.global_position -= Vector3.RIGHT * 5
    await create_timer(0.7).timeout
    check(torn.is_empty() and m.stomach.fill == 0 and not m.chewer.is_chewing(), "leaving reach cancels an already locked grab")
    mouse(false)
    await fixture(Vector3.RIGHT, 4.0)
    mouse(true)
    await create_timer(0.8).timeout
    check(torn.is_empty() and m.stomach.fill == 0, "empty space and outside reach do not remotely excavate")
    mouse(false)
    await fixture(Vector3.RIGHT, 1.2, FDKTissueRules.MEMBRANE)
    mouse(true)
    await create_timer(1.3).timeout
    check(torn.is_empty() and m.stomach.fill == 0, "bare hand cannot eat membrane")
    mouse(false)
    m.progression.grant_item("knife")
    m.equip_tool("knife")
    m.equip_hand("knife", FDKToolKit.Hand.LEFT)
    mouse(true)
    await create_timer(1.2).timeout
    mouse(false)
    check(not torn.is_empty(), "blade can tear reachable membrane")
    await fixture(Vector3.RIGHT)
    m.progression.grant_item("big_saw")
    m.equip_tool("big_saw")
    mouse(true)
    await create_timer(1.05).timeout
    mouse(false)
    check(not torn.is_empty() and m.stomach.fill >= 6 * m.stomach_config.flesh_per_cell, "shared physical aim drives six-cell saw stroke")
    await fixture(Vector3.FORWARD)
    m.progression.sprays.add(FDKSprayCan.new(FDKSprayCan.Tier.CHEAP))
    var hit: Dictionary = m._look_hit()
    var sprayed: int = m.tissue_tools.spray(false)
    check(sprayed > 0 and not hit.is_empty(), "spray uses reachable real surface aim")
    if not hit.is_empty():
        var point: Vector3 = hit.position + Vector3.FORWARD * 0.25
        check(m.terrain.tissue_at(point) == FDKTissueRules.MELTED, "sprayed hit becomes permanently inedible")
        check(not m.tissue_tools.can_grab_at(point), "melted cells cannot be grabbed")
    var prop2 := blocker(m.player.camera.global_position + Vector3.FORWARD * 0.4, Vector3.FORWARD)
    await physics_frame
    await physics_frame
    check(m.tissue_tools.spray(false) == -1, "prop blocks spray instead of melting unseen tissue")
    prop2.queue_free()
    await fixture(Vector3.RIGHT)
    m.progression.grant_item("blender")
    m.toggle_carry()
    m.equip_hand("", FDKToolKit.Hand.LEFT)
    check(m.carry_mode, "carry fixture has its required blender and free right hand")
    mouse(true)
    await create_timer(0.75).timeout
    mouse(false)
    check(torn.size() == 1 and is_equal_approx(m.carried_flesh, m.stomach_config.flesh_per_cell) and m.stomach.fill == 0, "carry receives exactly the actually torn cell")
    m.toggle_carry()
    # Camera guard is an independent initial fixture: previous movement
    # relief directions must not select its settling position.
    m.queue_free()
    await process_frame
    m = load("res://main/scenes/main.tscn").instantiate()
    m.rest_seed = 1337
    root.add_child(m)
    for frame in range(6): await physics_frame
    m.finish_opening()
    # Initial actual terrain chamber gives the approved DOWN idle head bow
    # a real surface contact. Normal physics settles the capsule first.
    mouse(false)
    if is_instance_valid(fixed_down_support): fixed_down_support.queue_free()
    m.terrain_config.facet_jitter = 0.0
    m.terrain.fill_box_uniform(AABB(Vector3(6, 2, 6), Vector3(4, 5, 4)), 1.0, 0)
    m.terrain.fill_box_uniform(AABB(Vector3(7.75, 4, 7.75), Vector3(0.5, 1, 0.5)), 0.0, 0)
    m.terrain.remesh_all()
    m.player.global_position = Vector3(8, 4.63, 8)
    m.player.velocity = Vector3.ZERO
    m._crush_t = 0.0
    aim(Vector3.DOWN)
    var observation := GuardObservation.new()
    observation.game = m
    observation.process_priority = 1000
    m.add_child(observation)
    await create_timer(0.4).timeout
    var body_before: Vector3 = m.player.global_position
    var base_before: Vector3 = m.hand_motions._cam_rest_offset()
    await create_timer(0.1).timeout
    print("GUARD_INITIAL_STATE samples=", observation.samples, " desired=", observation.desired, " expected=", observation.expected, " actual=", observation.actual, " body=", m.player.global_position, " rest=", m.hand_motions._cam_rest_offset(), " delta=", m._terrain_eye_delta, " crush=", m.crush_progress(), " pitch=", m.player._pitch)
    check(observation.samples > 0 and observation.desired.distance_to(observation.expected) > 0.01, "actual current surface requires positive idle eye correction")
    check(observation.actual.distance_to(observation.expected) < 0.003, "actual main applies terrain eye guard headless after normal process writers (actual %s, expected %s)" % [observation.actual, observation.expected])
    check(m.player.global_position.distance_to(body_before) < 0.01, "eye guard never relocates body")
    for i in range(20):
        aim(Vector3.FORWARD if i % 2 else Vector3.RIGHT)
        await process_frame
    aim(Vector3.DOWN)
    await create_timer(0.1).timeout
    check(observation.actual.distance_to(observation.expected) < 0.003 and m.hand_motions._cam_rest_offset().distance_to(base_before) < 0.003, "eye guard local correction does not accumulate after pivot changes")
    # Existing motion restores the approved idle base rather than storing
    # the terrain correction in that base. Production writers remain active.
    m.hand_motions.play_vomit(false, 0.2)
    await create_timer(0.4).timeout
    m.hand_motions.cancel()
    await create_timer(0.4).timeout
    aim(Vector3.DOWN)
    await create_timer(0.1).timeout
    check(observation.actual.distance_to(observation.expected) < 0.003 and m.hand_motions._cam_rest_offset().distance_to(base_before) < 0.003, "existing vomit motion restores neutral camera without storing guard offset")
    check(m.player.global_position.distance_to(body_before) < 0.01, "motion and guard preserve the capsule position")
    observation.queue_free()
    check(grabs > 0 and progress > 0 and releases > 0, "existing grab/progress/release signals remain active")
    print("%d passed, %d failed" % [passed, failed])
    m.queue_free()
    await process_frame
    quit(1 if failed else 0)

func down_reach_boundary_case() -> void:
    await fixture(Vector3.DOWN, 1.2)
    await support_fixed_down_reach()
    var supported_before: Vector3 = m.player.global_position
    mouse(true)
    await create_timer(2.05).timeout
    mouse(false)
    await process_frame
    await process_frame
    check(m.player.global_position.distance_to(supported_before) < 0.02, "reach fixture normal physics preserves actual distance")
    check(torn.size() == 1, "wide downward floor stops after the only reachable tear")
    check(m.excavated_cells == 1, "wide downward floor records only one actual excavation")
    check(is_equal_approx(m.stomach.fill, m.stomach_config.flesh_per_cell), "wide downward floor never adds food for the distant next surface")
    var rr: Array = m.player.get_look_ray()
    var beyond: Dictionary = m._published_terrain_contact(rr[0], rr[1], m.progression.reach() + m.terrain_config.cell_size)
    check(not beyond.is_empty() and rr[0].distance_to(beyond.position) > m.progression.reach(), "actual next downward surface is beyond unchanged reach")
    check(m._look_hit().is_empty() and not m.chewer.is_chewing(), "actual distant downward surface is rejected and grab stops")

func support_fixed_down_reach() -> void:
    # Initial physical fixture for the unchanged 2.5m reach boundary. The
    # approved idle head bow changes eye height; use an absolute initial
    # pose so prior unsupported physics frames cannot shorten the boundary.
    # A real support beside the feet keeps physics active and leaves the
    # down aim ray unobstructed. Separate radius1.0 cases remain unsupported.
    m.player.global_position = center - Vector3.UP * m.player.eye_pivot_y(false) + Vector3.UP * 0.3
    fixed_down_support = StaticBody3D.new()
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(0.2, 0.1, 0.2)
    shape.shape = box
    fixed_down_support.add_child(shape)
    m.add_child(fixed_down_support)
    fixed_down_support.global_position = m.player.get_feet_position() + Vector3(0.25, -0.05, 0)
    await physics_frame
    await physics_frame
    await process_frame
    var rr: Array = m.player.get_look_ray()
    var hit: Dictionary = ray(rr[0], rr[1], m.progression.reach() + 1.0)
    check(m.player.is_on_floor(), "reach fixture actual support grounds normal physics")
    check(not hit.is_empty() and hit.collider != fixed_down_support, "reach fixture support does not occlude actual flesh ray")
