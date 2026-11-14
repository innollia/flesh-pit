extends SceneTree
var m: Node3D
var passed := 0
var failed := 0
func _init() -> void:
    m = load("res://main/scenes/main.tscn").instantiate()
    m.user_keybinds_path = "user://keybinds_test_terrain_density_cache.json"
    m.save_path = "res://../.dryforge/evidence/checks/density-cache-isolated.bin"
    root.add_child(m)
    run.call_deferred()
func check(ok: bool,label: String) -> void:
    if ok: passed += 1
    else:
        failed += 1
        print("FAIL: ",label)
func expected(p: Vector3) -> float:
    if m.in_vent_duct(p): return 0.0
    return FPWorldFeatures.world_density(p,FPRestroom.HALF,FPRestroom.DOOR_HALF_W,FPRestroom.DOOR_H,m.ROOM_MARGIN,m.DOOR_GAP,m.RESTROOM_CENTER,m.OUTER_RADIUS,m.rest_points,m.rest_halves)
func run() -> void:
    await process_frame
    m._world_density_cache.clear()
    for p in [Vector3.ZERO,Vector3(0,1,1.8),Vector3(0,1,2.2),Vector3(-2.3,1,0),Vector3(8,4,8),Vector3.ONE*1000,FPRestroom.VENT_CENTER+Vector3.UP*0.2]:
        check(is_equal_approx(m._world_density(p),expected(p)),"cached world density equals authored generator "+str(p))
        check(is_equal_approx(m._world_density(p),expected(p)),"repeated cached world density remains exact")
    m._world_density_cache.clear()
    for i in range(m.WORLD_DENSITY_CACHE_LIMIT+32):
        m._world_density(Vector3(1000+i,2000,3000))
    check(m._world_density_cache.size()<=m.WORLD_DENSITY_CACHE_LIMIT,"cache memory stays bounded across world traversal")
    # The rest layout is fixed (decision 0016): no seed moves a container, so
    # a cached hollow stays the authored one. Each box is empty inside and
    # solid 0.6 m out of each of its faces.
    check(m.rest_points.size() == 7 and m.rest_points == FPWorldFeatures.rest_points(m.RESTROOM_CENTER), "seven rest containers, where the fixed layout puts them")
    for i in range(m.rest_points.size()):
        var rc: Vector3 = m.rest_points[i]
        var rh: Vector3 = m.rest_halves[i]
        check(is_equal_approx(m._world_density(rc),0.0) and is_equal_approx(expected(rc),0.0),"rest %d is hollow at its middle" % i)
        check(m._world_density(rc + rh * 0.98) < 0.5 and is_equal_approx(m._world_density(rc + (rh - Vector3.ONE * 0.6)),0.0),"rest %d has no flesh up to its corner (under iso at the steel, nothing 0.6 m in)" % i)
        var solid_out := true
        for axis in range(3):
            for side in [-1.0, 1.0]:
                var q := rc
                q[axis] += side * (rh[axis] + 0.6)
                # the generator gives whole flesh there; a biome may loosen it, never open it
                if not is_equal_approx(expected(q),1.0) or m._world_density(q) < 0.5:
                    solid_out = false
        check(solid_out,"rest %d is whole flesh 0.6 m out of every face" % i)
        # the surface the flesh makes lies on the box face, not half a cell in
        var face := rc
        face.x += rh.x + FPWorldFeatures.REST_MARGIN
        check(absf(m._world_density(face) - 0.5) < 0.001,"rest %d: the flesh surface lies on the box face" % i)
    # The open vent: no flesh face inside the duct model. Every cell touching
    # it must have only empty corners (density_at = max of a cell's 8 corners).
    var t: FDKTerrainField = m.terrain
    var duct_cells_empty := func() -> bool:
        for ix in range(-5, 6):
            for iy in range(0, 15):
                for iz in range(-5, 6):
                    var q: Vector3 = FPRestroom.VENT_CENTER + Vector3(ix * 0.05, 0.01 + iy * 0.049, iz * 0.05)
                    if t.density_at(q) >= m.terrain_config.iso_level:
                        print("  flesh corner in a duct cell at ", q - FPRestroom.VENT_CENTER)
                        return false
        return true
    check(duct_cells_empty.call(), "no flesh corner in any cell the vent duct model touches")
    # an older save still holds flesh there: loading clears only the duct
    var probe: Vector3 = FPRestroom.VENT_CENTER + Vector3(0.3, 1.5, 0.3)
    var probe_before := t.density_at(probe)
    t.fill_box_uniform(AABB(FPRestroom.VENT_CENTER + Vector3(-0.5, -0.02, -0.5), Vector3(1.0, 0.9, 1.0)), 1.0, FDKTissueRules.COMPRESSIVE)
    check(not duct_cells_empty.call(), "fixture: old-save flesh put back into the duct")
    m.deserialize(m.serialize())
    check(duct_cells_empty.call(), "loading an old save clears the flesh out of the vent duct")
    check(is_equal_approx(t.density_at(probe), probe_before), "flesh outside the duct space is left as saved")
    print("%d passed, %d failed" % [passed,failed])
    m.queue_free()
    await process_frame
    quit(1 if failed else 0)
