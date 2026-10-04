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
    await closed_solid_volume()
    await concave_volume_observer()
    await narrowing_surface_crossings()
    print("%d passed, %d failed" % [passed, failed])
    quit(1 if failed else 0)

func closed_solid_volume() -> void:
    field = FDKTerrainField.new()
    field.config.chunk_size = 4
    field.density_sampler = func(_p: Vector3): return 1.0
    root.add_child(field)
    field.set_process(false)
    field.generate_region(AABB(Vector3.ONE * -2, Vector3.ONE * 4))
    for x in range(-1, 1):
        for y in range(-1, 1):
            for z in range(-1, 1):
                field.dig_at(Vector3(x, y, z) * 0.5 + Vector3.ONE * 0.25, 1.0)
    for step in range(4):
        field.contract_sphere(Vector3.ZERO, 1.3, 0.45)
    field.remesh_all()
    var minimum := 1.0
    for x in range(-1, 2):
        for y in range(-1, 2):
            for z in range(-1, 2):
                minimum = minf(minimum, field.corner_density_global(Vector3i(x,y,z)))
    check(minimum >= field.config.iso_level, "closed cavity really contains only solid corners")
    var eye := Vector3(0.1, 0.3, 0.1)
    var density_before := field.serialize()
    field.constrain_eye(eye, eye - Vector3.UP * 0.7, 0.02)
    check(field.has_method("solid_contact_ray"), "closed solid volume has geometry contact query")
    if field.has_method("solid_contact_ray"):
        check(field._solid_volume._faces.size() <= 343 * 12 * 3, "volume geometry is bounded to 343 cells")
        check(field._solid_volume._faces.size()/3 <= 600, "uniform solid union avoids redundant interior subdivision faces")
        check(field._solid_volume.mesh.get_surface_count() > 0, "closed solid volume has actual 3D rendered geometry")
        var original_volume_mesh: Mesh = field._solid_volume.mesh
        var chunks_before := field._chunks.size()
        for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
            var hit: Dictionary = field.call("solid_contact_ray", eye, eye + axis)
            check(not hit.is_empty(), "closed solid volume contact " + str(axis))
            if not hit.is_empty():
                check(hit.collider.has_meta("fdk_terrain_chunk"), "volume contact retains actual terrain body")
                check(hit.position.distance_to(eye) <= 1.0, "volume contact is within caller reach")
                check(hit.normal.dot(axis) <= 0, "volume contact normal opposes incoming ray")
                check(field._eye_surface_outward(hit).dot(axis) > 0, "volume helper returns true partition outward")
                var target: Vector3 = hit.position - field._eye_surface_outward(hit) * 0.05
                var location := field.world_to_cell(target)
                var cell: Vector3i = location[0] * field.config.chunk_size + location[1]
                check(field._solid_volume._solid(cell), "volume ray targets a proven fully solid actual cell")
        check(field._solid_volume.mesh == original_volume_mesh, "identical volume membership reuses mesh")
        var materials_match := true
        for surface in range(original_volume_mesh.get_surface_count()):
            materials_match = materials_match and original_volume_mesh.surface_get_material(surface) == FDKChunk.terrain_material(0)
        check(materials_match, "interior volume retains actual tissue materials")
        check(field.call("solid_contact_ray", eye, eye + Vector3.RIGHT * 0.001).is_empty(), "short ray cannot get remote contact")
        check(field.call("solid_contact_ray", Vector3.ONE * 100, Vector3.ONE * 101).is_empty(), "ungenerated world cannot invent volume")
        check(not field._solid_volume.visible and field._solid_volume.mesh == null, "outside world hides and clears volume")
        check(field._chunks.size() == chunks_before, "volume query cannot generate world")
        check(field.serialize() == density_before, "volume render and contact cannot write density/tissue/seals/boost")
        var collider_unchanged := true
        for chunk in field._chunks.values():
            collider_unchanged = collider_unchanged and chunk._collision.shape == null
        check(collider_unchanged, "volume adds no body collision shape or physical push")
        for point in [Vector3.ZERO, Vector3.ONE*0.5, Vector3.ONE*2.0]:
            for axis in [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.FORWARD,Vector3.BACK]:
                var corner_hit := field.solid_contact_ray(point,point+axis)
                check(not corner_hit.is_empty(), "exact solid corner/chunk boundary has actual contact %s %s" % [point,axis])
        var hit: Dictionary = field.solid_contact_ray(eye, eye + Vector3.RIGHT)
        var target: Vector3 = hit.position - field._eye_surface_outward(hit) * 0.05
        var before_density := field.density_at(target)
        field.dig_at(target, 1.0)
        field.remesh_all()
        check(field.density_at(target) < before_density, "real volume contact tears actual density")
        var rendered_boundaries := 0
        for chunk in field._chunks.values():
            if chunk._collision.shape != null: rendered_boundaries += chunk._collision.shape.get_faces().size()
        check(rendered_boundaries > 0, "first volume tear creates actual outer surface and collision")
        field.constrain_eye(eye, eye - Vector3.UP * 0.7, 0.02)
        check(not field._solid_volume.visible, "new actual cavity disables internal volume")
        check(field.solid_contact_ray(eye, eye + Vector3.RIGHT).is_empty(), "empty eye has no internal volume contact")
        var partial_eye := Vector3(1.25,1.25,1.25)
        field._add_corner_global(Vector3i(2,2,2),-1.0)
        field.remesh_all()
        field.solid_contact_ray(partial_eye,partial_eye+Vector3.RIGHT)
        var partial_entry := field.solid_contact_ray(partial_eye,partial_eye+Vector3.RIGHT*0.4)
        check(not partial_entry.is_empty(), "partial solid eye reaches the first rendered full-volume entry")
        if not partial_entry.is_empty():
            check(is_equal_approx(partial_entry.position.x,1.5), "partial solid entry agrees with nearest rendered face")
            check(field._eye_surface_outward(partial_entry).dot(Vector3.RIGHT)<0, "partial solid entry has actual inward-facing volume boundary")
        field.solid_contact_ray(partial_eye,partial_eye+Vector3.RIGHT*0.4)
        check(field._solid_volume.proof_cache_hit, "same observer and published geometry reuse partial-solid proof")
        var boundary_eye := Vector3(1.5,1.25,1.25)
        var boundary_entry := field.solid_contact_ray(boundary_eye,boundary_eye+Vector3.LEFT*1.1)
        check(not boundary_entry.is_empty(), "full-cell boundary observer can reach later first visible entry")
        if not boundary_entry.is_empty():
            check(is_equal_approx(boundary_entry.position.x,0.5), "boundary contact equals the nearest visible volume face")
        check(not field._solid_volume._solid(Vector3i(2,2,2)), "partly empty cell cannot invent filled volume")
        var only_actual_solid := true
        for cell in field._solid_volume._face_cells:
            only_actual_solid = only_actual_solid and field._solid_volume._solid(cell)
        check(only_actual_solid, "partial solid observer never adds partial-cell geometry")
        var partial_void := Vector3(1.02,1.02,1.02)
        check(field.solid_contact_ray(partial_void,partial_void+Vector3.RIGHT).is_empty(), "actual partial-cell void has no internal contact")
        check(not field._solid_volume.visible, "actual partial-cell void preserves ordinary exposed isosurface presentation")
        field.solid_contact_ray(partial_eye,partial_eye+Vector3.RIGHT)
        field.dig_at(partial_eye,1.0)
        field.remesh_all()
        check(field.solid_contact_ray(partial_eye,partial_eye+Vector3.RIGHT).is_empty(), "published removal invalidates old partial-solid proof")
        check(not field._solid_volume.proof_cache_hit, "changed density/published geometry cannot reuse stale proof")
    field.queue_free()
    await process_frame

func concave_volume_observer() -> void:
    field = FDKTerrainField.new()
    field.config.chunk_size = 4
    field.density_sampler = func(p: Vector3): return 0.0 if minf(p.length(),p.distance_to(Vector3.RIGHT))<0.8 else 1.0
    root.add_child(field)
    field.set_process(false)
    field.generate_region(AABB(Vector3.ONE*-2,Vector3.ONE*4))
    field.remesh_all()
    topology("concave joined cavities")
    for eye in [Vector3.ZERO,Vector3.RIGHT,Vector3(0.5,0,0),Vector3(0.5,0.25,0),Vector3(0.5,-0.25,0),Vector3(0.5,0,0.25)]:
        var contact := field.solid_contact_ray(eye,eye+Vector3.UP)
        if not contact.is_empty(): print("CONCAVE eye=",eye," proof=",field._solid_volume.observer_proof)
        check(contact.is_empty(), "actual concave cavity cannot activate internal mass contact "+str(eye))
        check(not field._solid_volume.visible, "concave cavity keeps real open isosurface view "+str(eye))
    field.queue_free()
    await process_frame

func get_published_world_triangles() -> Array:
    var tris: Array = []
    for chunk in field.get_chunks():
        var faces: PackedVector3Array = chunk._surface_faces
        for i in range(0, faces.size(), 3):
            tris.append([chunk.to_global(faces[i]), chunk.to_global(faces[i + 1]), chunk.to_global(faces[i + 2])])
    return tris

func count_nonadjacent_crossings(tris: Array) -> int:
    var crossings := 0
    for i in range(tris.size()):
        var a: Array = tris[i]
        var a_min := Vector3(minf(a[0].x, minf(a[1].x, a[2].x)), minf(a[0].y, minf(a[1].y, a[2].y)), minf(a[0].z, minf(a[1].z, a[2].z)))
        var a_max := Vector3(maxf(a[0].x, maxf(a[1].x, a[2].x)), maxf(a[0].y, maxf(a[1].y, a[2].y)), maxf(a[0].z, maxf(a[1].z, a[2].z)))
        for j in range(i + 1, tris.size()):
            var b: Array = tris[j]
            var b_min := Vector3(minf(b[0].x, minf(b[1].x, b[2].x)), minf(b[0].y, minf(b[1].y, b[2].y)), minf(b[0].z, minf(b[1].z, b[2].z)))
            var b_max := Vector3(maxf(b[0].x, maxf(b[1].x, b[2].x)), maxf(b[0].y, maxf(b[1].y, b[2].y)), maxf(b[0].z, maxf(b[1].z, b[2].z)))
            if a_max.x < b_min.x or a_min.x > b_max.x or a_max.y < b_min.y or a_min.y > b_max.y or a_max.z < b_min.z or a_min.z > b_max.z:
                continue
            var shared := false
            for av in a:
                for bv in b:
                    if av.distance_squared_to(bv) < 0.000000001:
                        shared = true
                        break
                if shared:
                    break
            if shared:
                continue
            var crossed := false
            for e in range(3):
                if Geometry3D.segment_intersects_triangle(a[e], a[(e + 1) % 3], b[0], b[1], b[2]) != null:
                    crossed = true
                    break
                if Geometry3D.segment_intersects_triangle(b[e], b[(e + 1) % 3], a[0], a[1], a[2]) != null:
                    crossed = true
                    break
            if crossed:
                crossings += 1
    return crossings

func narrowing_surface_crossings() -> void:
    field = FDKTerrainField.new()
    field.config.chunk_size = 4
    field.density_sampler = func(_p: Vector3): return 1.0
    root.add_child(field)
    field.set_process(false)
    field.generate_region(AABB(Vector3.ONE * -2, Vector3.ONE * 4))
    for x in range(-1, 1):
        for y in range(-1, 1):
            for z in range(-1, 1):
                field.dig_at(Vector3(x, y, z) * 0.5 + Vector3.ONE * 0.25, 1.0)
    field.remesh_all()
    topology("dug")
    var dug_tris := get_published_world_triangles()
    check(not dug_tris.is_empty(), "dug cavity has an actual surface to audit")
    check(count_nonadjacent_crossings(dug_tris) == 0, "dug nonadjacent crossings 0")

    for step in range(4):
        field.contract_sphere(Vector3.ZERO, 1.3, 0.45)
        field.remesh_all()
        var tris := get_published_world_triangles()
        if not tris.is_empty():
            topology("closing%d" % step)
        check(tris.is_empty() == (step == 3), "closing%d retains the surface until fully healed" % step)
        check(count_nonadjacent_crossings(tris) == 0, "closing%d nonadjacent crossings == 0" % step)
    field.queue_free()
    await process_frame

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
    var oriented_edges := {}
    var faces := {}
    var mismatches := 0
    var unresolved := 0
    for chunk in field.get_chunks():
        unresolved += chunk.unresolved_folded_quads
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
                    var directed := 1 if point_key(edge[0]) < point_key(edge[1]) else -1
                    oriented_edges[str(pair)] = oriented_edges.get(str(pair),0)+directed
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
    var incoherent := 0
    for balance in oriented_edges.values():
        if balance != 0: incoherent += 1
    check(incoherent == 0, label + " oriented shared-edge mismatches=" + str(incoherent))
    check(unresolved == 0, label + " self-crossing quad rings=" + str(unresolved))
