extends SceneTree

# Raw API checks for main._look_hit bounded ray candidate selection.
# Tests actual filled mass (ordinary mesh 0), pending surface patches,
# prop priority, reach rejection, and stable physics fastpath preserving nearer patches.

const FDKSurfacePatch = preload("res://addons/flesh_dig_kit/terrain/fdk_surface_patch.gd")

var m: Node3D
var passed := 0
var failed := 0
var center := Vector3(8, 5, 8)

func _init() -> void:
    Engine.max_fps = 60
    m = load("res://main/scenes/main.tscn").instantiate()
    m.rest_seed = 1337
    root.add_child(m)
    run.call_deferred()

func check(ok: bool, label: String) -> void:
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL: ", label)

func aim(direction: Vector3) -> void:
    var dir := direction.normalized()
    m.player._yaw = atan2(-dir.x, -dir.z)
    m.player._pitch = asin(clampf(dir.y, -1, 1))
    m.player.rotation.y = m.player._yaw
    m.player.camera_pivot.rotation.x = m.player._pitch

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

func ray(origin: Vector3, direction: Vector3, distance: float) -> Dictionary:
    var q := PhysicsRayQueryParameters3D.create(origin, origin + direction * distance)
    q.exclude = [m.player.get_rid()]
    return m.get_world_3d().direct_space_state.intersect_ray(q)

func run() -> void:
    await create_timer(0.1).timeout
    m.finish_opening()

    # --- Test 1: Filled mass ordinary mesh 0 in 6 directions ---
    m.terrain.fill_box_uniform(AABB(center - Vector3.ONE * 3, Vector3.ONE * 6), 1.0, 0)
    m.terrain.remesh_all()
    m.player.global_position = center - Vector3.UP * m.player.eye_pivot_y(false)
    m.player.velocity = Vector3.ZERO
    var eye: Vector3 = m.player.camera.global_position

    var directions: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN]
    for dir in directions:
        aim(dir)
        check(ray(eye, dir, m.progression.reach()).is_empty(), "ordinary physics has 0 faces along ray in solid mass for " + str(dir))
        check(m._published_terrain_contact(eye, dir, m.progression.reach()).is_empty(), "ordinary mesh has 0 faces within reach in solid mass for " + str(dir))
        var hit: Dictionary = m._look_hit()
        check(not hit.is_empty(), "solid mass hit in direction " + str(dir))
        if not hit.is_empty():
            check(hit.get("fdk_solid_volume", false) == true, "solid mass hit tagged with fdk_solid_volume for " + str(dir))
            check(hit.collider != null and hit.collider.has_meta("fdk_terrain_chunk"), "solid mass hit has terrain body for " + str(dir))
            var dist := eye.distance_to(hit.position)
            check(dist <= m.progression.reach(), "solid mass hit within reach for " + str(dir))
            var outward: Vector3 = m.terrain._eye_surface_outward(hit)
            check(outward != Vector3.ZERO and outward.dot(dir) > 0, "solid mass hit has true outward partition for " + str(dir))

    # --- Test 2: First actual dig selects pending actual patch ---
    aim(Vector3.FORWARD)
    var pre_hit: Dictionary = m._look_hit()
    check(not pre_hit.is_empty(), "pre-dig solid mass hit exists")
    var pre_outward: Vector3 = m.terrain._eye_surface_outward(pre_hit)
    var dig_pos: Vector3 = pre_hit.position - pre_outward * 0.05
    m.terrain.dig_at(dig_pos, 1.0)
    check(m.terrain._surface_patch != null and not m.terrain._surface_patch.faces.is_empty(), "dig_at creates pending surface patch")
    check(m._published_terrain_contact(eye, Vector3.FORWARD, m.progression.reach()).is_empty(), "ordinary mesh remains unpublished 0 faces before remesh")

    var patch_hit: Dictionary = m._look_hit()
    check(not patch_hit.is_empty(), "look_hit finds pending patch hit")
    check(patch_hit.get("fdk_surface_patch", false) == true, "look_hit selects actual pending surface patch")
    check(patch_hit.collider != null and patch_hit.collider.has_meta("fdk_terrain_chunk"), "pending patch hit has valid terrain chunk body")
    check(patch_hit.get("fdk_patch_outward") != null and m.terrain._eye_surface_outward(patch_hit) != Vector3.ZERO, "pending patch hit provides valid outward normal")
    check(patch_hit.get("shape", 0) == -1, "pending patch hit has shape -1")

    # --- Test 3: Prop priority: front prop wins, rear prop does not obscure ---
    var patch_dist: float = eye.distance_to(patch_hit.position)
    var front: StaticBody3D = blocker(eye + Vector3.FORWARD * (patch_dist * 0.5), Vector3.FORWARD)
    await physics_frame
    await physics_frame
    var hit_front: Dictionary = m._look_hit()
    check(not hit_front.is_empty() and hit_front.collider == front, "front prop preferred over pending patch")
    front.queue_free()
    await physics_frame
    await physics_frame

    var rear: StaticBody3D = blocker(eye + Vector3.FORWARD * (patch_dist + 0.5), Vector3.FORWARD)
    await physics_frame
    await physics_frame
    var hit_rear: Dictionary = m._look_hit()
    check(not hit_rear.is_empty() and hit_rear.collider != rear and hit_rear.collider.has_meta("fdk_terrain_chunk"), "rear prop does not obscure front terrain patch")
    rear.queue_free()
    await physics_frame
    await physics_frame

    # --- Test 4: Reach rejection ---
    m.terrain.carve_sphere(eye, 3.5)
    m.terrain.remesh_all()
    await physics_frame
    await physics_frame
    aim(Vector3.FORWARD)
    var far_hit: Dictionary = m._look_hit()
    check(far_hit.is_empty(), "look_hit rejects targets beyond reach")

    # --- Test 5: Stable physics fastpath preserves nearer patch ---
    # Keep normal descent live. Both physics phases aim through the actual
    # new cavity rather than a world-height cavity that the eye can miss.
    for phase in [3, 4]:
        m.terrain.fill_box_uniform(AABB(center - Vector3.ONE * 4, Vector3.ONE * 8), 1.0, 0)
        m.terrain.carve_sphere(center, 2.0)
        m.terrain.remesh_all()
        m.player.global_position = center - Vector3.UP * m.player.eye_pivot_y(false)
        m.player.velocity = Vector3.ZERO
        eye = m.player.camera.global_position
        aim(Vector3.FORWARD)
        await physics_frame
        await physics_frame
        for i in range(phase):
            m._look_hit()
            await physics_frame

        eye = m.player.camera.global_position
        var stable_physics_hit: Dictionary = m._look_hit()
        check(not stable_physics_hit.is_empty() and stable_physics_hit.collider.has_meta("fdk_terrain_chunk"), "stable physics terrain face detected")
        var stable_dist: float = eye.distance_to(stable_physics_hit.position)
        check(stable_dist > 1.8, "stable rear physics face is beyond 1.8m (actual: %.2f)" % stable_dist)

        # Introduce a nearer solid region and dig to create a surface patch at ~1.0m
        var tear_pt := eye + Vector3.FORWARD * 1.25
        # The nearer slab must not fill the eye/body itself: otherwise the
        # correct nearest hit can be an actual internal solid-cell face.
        var nearer_slab := AABB(tear_pt - Vector3.ONE * 1.5, Vector3(3.0, 3.0, 2.5))
        check(not nearer_slab.has_point(eye), "nearer patch fixture leaves actual ray origin outside added mass")
        m.terrain.fill_box_uniform(nearer_slab, 1.0, 0)
        m.terrain.dig_at(tear_pt, 1.0)
        check(m.terrain._surface_patch != null and not m.terrain._surface_patch.faces.is_empty(), "nearer surface patch created")

        var nearer_patch_hit: Dictionary = m._look_hit()
        print("NEAR_PHASE phase=",phase," eye=",eye," target=",tear_pt," hit=",nearer_patch_hit)
        check(not nearer_patch_hit.is_empty(), "look_hit finds hit with nearer patch")
        check(nearer_patch_hit.get("fdk_surface_patch", false) == true, "stable physics fastpath preserves nearer patch over rear physics face")
        check(eye.distance_to(nearer_patch_hit.position) < stable_dist - 0.3, "nearer patch hit is closer than rear physics face")
        m.terrain._clear_surface_patch()

    # --- Summary ---
    print("%d passed, %d failed" % [passed, failed])
    m.queue_free()
    await process_frame
    quit(1 if failed else 0)
