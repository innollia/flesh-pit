extends SceneTree

var passed := 0
var failed := 0
var field: FDKTerrainField

func _init() -> void:
    run.call_deferred()

func check(ok: bool, label: String) -> void:
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL: ", label)

func make_field(center: Vector3) -> void:
    field = FDKTerrainField.new()
    field.config = FDKTerrainConfig.new()
    field.config.chunk_size = 4
    field.density_sampler = func(p: Vector3): return 0.0 if p.distance_to(center) < 0.8 else 1.0
    field.tissue_sampler = func(p: Vector3): return 0 if p.x < center.x else 2
    root.add_child(field)
    field.set_process(false)
    field.generate_region(AABB(center - Vector3.ONE * 2, Vector3.ONE * 4))
    field.remesh_all()

func run() -> void:
    for center in [Vector3.ZERO, Vector3(-2, -2, -2)]:
        make_field(center)
        await physics_frame
        await physics_frame
        topology("initial " + str(center))
        await rays(center, "initial")
        var free_eye: Vector3 = center + Vector3(0.1, 0.1, 0.1)
        check(field.constrain_eye(free_eye, center, 0.02).is_equal_approx(free_eye), "free tunnel eye unchanged")
        var near_eye: Vector3 = center + Vector3.RIGHT * 0.75
        var guarded := field.constrain_eye(near_eye, center, 0.02)
        check(guarded.distance_to(center) < near_eye.distance_to(center), "near boundary eye contact")
        check(guarded.distance_to(center) > 0.3, "eye guard remains on physical anchor segment")
        var blocker := StaticBody3D.new()
        var blocker_shape := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = Vector3(0.05, 0.2, 0.2)
        blocker_shape.shape = box
        blocker.add_child(blocker_shape)
        root.add_child(blocker)
        blocker.position = center + Vector3.RIGHT * 0.2
        await physics_frame
        await physics_frame
        check(field.constrain_eye(near_eye, center, 0.02).is_equal_approx(guarded), "nonterrain prop cannot hide terrain eye contact")
        blocker.queue_free()
        await physics_frame
        var buried_anchor: Vector3 = center + Vector3.RIGHT
        var buried_eye := buried_anchor + Vector3.UP * 0.55
        var resolved := field.constrain_eye(buried_eye, buried_anchor, 0.02)
        check(resolved.distance_to(buried_eye) > 0.05, "buried eye resolves a nearby physical surface")
        check(resolved.distance_to(buried_eye) <= 0.7, "buried eye correction is bounded by capsule eye offset")
        var inside_ray := PhysicsRayQueryParameters3D.create(resolved, center)
        check(field.get_world_3d().direct_space_state.intersect_ray(inside_ray).is_empty(), "buried eye resolves to original cavity side")
        field.dig_at(center + Vector3(0.55, 0.55, 0.55), 0.65)
        field.remesh_all()
        topology("removal " + str(center))
        await rays(center, "removal")
        for step in range(4):
            field.regenerate_all(2.0, Vector3.ONE * 100, 0.01)
            field.remesh_all()
            topology("regen %d %s" % [step, center])
        await rays(center, "regen")
        # A boundary removal must dirty every mesh that reads its cells,
        # including neighbors that only read a one-corner padded border.
        field.remesh_budget_per_frame = 1
        field.dig_at(center + Vector3(0.55, 0.1, 0.1), 0.4)
        for step in range(20):
            field._process(0.016)
            topology("budgeted removal frame %d" % step)
        var initial_mesh: Mesh = field.get_chunk(field.world_to_chunk_coord(center))._mesh_instance.mesh
        var published := false
        for step in range(24):
            field.regenerate_all(0.1, Vector3.ONE * 100, 0.01)
            field._process(0.016)
            topology("continuous budgeted regen frame %d" % step)
            if field.get_chunk(field.world_to_chunk_coord(center))._mesh_instance.mesh != initial_mesh:
                published = true
        check(published, "continuous regen publishes despite new mutations")
        field.remesh_all()
        topology("flush pending continuous changes")
        field.regenerate_all(100, Vector3.ONE * 100, 0.01)
        for step in range(20):
            field._process(0.016)
            topology("final healed corner frame %d" % step)
        field.queue_free()
        await process_frame
    await streaming_during_batch()
    print("%d passed, %d failed" % [passed, failed])
    quit(1 if failed else 0)

func streaming_during_batch() -> void:
    var center := Vector3(1.5, 2, 1)
    field = FDKTerrainField.new()
    field.config.chunk_size = 4
    field.density_sampler = func(p: Vector3): return 0.0 if p.distance_to(center) < 0.4 else 1.0
    field.tissue_sampler = func(_p: Vector3): return 0
    root.add_child(field)
    field.set_process(false)
    field.generate_region(AABB(Vector3.ZERO, Vector3(1.9, 3.9, 1.9)))
    field.remesh_all()
    topology("streaming initial cavity")
    field.remesh_budget_per_frame = 1
    field._add_corner_global(Vector3i(3, 4, 2), -0.2)
    field._process(0.016)
    check(not field._mesh_batch.is_empty(), "streaming test has unfinished snapshot")
    field.get_or_create_chunk(Vector3i(1, 0, 0))
    field._add_corner_global(Vector3i(4, 3, 2), -1.0)
    field._add_corner_global(Vector3i(3, 3, 2), -1.0)
    for step in range(20):
        field._process(0.016)
        topology("streaming mid-batch frame %d" % step)
    field.queue_free()
    await process_frame

func rays(center: Vector3, label: String) -> void:
    await physics_frame
    await physics_frame
    for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD, Vector3(1, 0.9, 0.8).normalized()]:
        var query := PhysicsRayQueryParameters3D.create(center, center + axis * 3.0)
        var hit := field.get_world_3d().direct_space_state.intersect_ray(query)
        if hit.is_empty():
            var nearest := INF
            for chunk in field.get_chunks():
                if chunk._collision.shape == null: continue
                var vs: PackedVector3Array = chunk._collision.shape.get_faces()
                for i in range(0, vs.size(), 3):
                    var cross = Geometry3D.ray_intersects_triangle(center, axis, vs[i] + chunk.position, vs[i + 1] + chunk.position, vs[i + 2] + chunk.position)
                    if cross != null: nearest = minf(nearest, center.distance_to(cross))
            print("MISS center=", center, " axis=", axis, " CPU nearest=", nearest)
        check(not hit.is_empty(), label + " physical hit " + str(axis))

func point_key(v: Vector3) -> String:
    return str(Vector3i(roundi(v.x * 10000), roundi(v.y * 10000), roundi(v.z * 10000)))

func face_key(a: Vector3, b: Vector3, c: Vector3) -> String:
    var keys := [point_key(a), point_key(b), point_key(c)]
    keys.sort()
    return str(keys)

func topology(label: String) -> void:
    var edges := {}
    var faces := {}
    var mismatches := 0
    for chunk in field.get_chunks():
        if chunk._mesh_instance.mesh == null:
            continue
        for surface in range(chunk._mesh_instance.mesh.get_surface_count()):
            var vs: PackedVector3Array = chunk._mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
            for i in range(0, vs.size(), 3):
                var a: Vector3 = vs[i] + chunk.position
                var b: Vector3 = vs[i + 1] + chunk.position
                var c: Vector3 = vs[i + 2] + chunk.position
                faces[face_key(a, b, c)] = (b - a).cross(c - a).normalized()
                for edge in [[a, b], [b, c], [c, a]]:
                    var pair := [point_key(edge[0]), point_key(edge[1])]
                    pair.sort()
                    edges[str(pair)] = edges.get(str(pair), 0) + 1
    for chunk in field.get_chunks():
        if chunk._collision.shape == null:
            continue
        var vs: PackedVector3Array = chunk._collision.shape.get_faces()
        for i in range(0, vs.size(), 3):
            var a: Vector3 = vs[i] + chunk.position
            var b: Vector3 = vs[i + 1] + chunk.position
            var c: Vector3 = vs[i + 2] + chunk.position
            var visual: Vector3 = faces.get(face_key(a, b, c), Vector3.ZERO)
            if visual != Vector3.ZERO and visual.dot((b - a).cross(c - a).normalized()) < 0.99:
                mismatches += 1
    var open_edges := 0
    for count in edges.values():
        if count != 2:
            open_edges += 1
    check(not faces.is_empty(), label + " has surface")
    check(open_edges == 0, label + " welded open edges=" + str(open_edges))
    check(mismatches == 0, label + " winding mismatches=" + str(mismatches))
