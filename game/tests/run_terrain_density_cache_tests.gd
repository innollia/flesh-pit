extends SceneTree
var m: Node3D
var passed := 0
var failed := 0
func _init() -> void:
    m = load("res://main/scenes/main.tscn").instantiate()
    m.rest_seed = 1337
    m.save_path = "res://../.dryforge/evidence/checks/density-cache-isolated.bin"
    root.add_child(m)
    run.call_deferred()
func check(ok: bool,label: String) -> void:
    if ok: passed += 1
    else:
        failed += 1
        print("FAIL: ",label)
func expected(p: Vector3) -> float:
    var vent := p-FPRestroom.VENT_CENTER
    if absf(vent.x)<0.30 and absf(vent.z)<0.30 and vent.y>=-0.04 and vent.y<0.8: return 0.0
    return FPWorldFeatures.world_density(p,FPRestroom.HALF,FPRestroom.DOOR_HALF_W,FPRestroom.DOOR_H,m.ROOM_MARGIN,m.DOOR_GAP,m.RESTROOM_CENTER,m.OUTER_RADIUS,m.rest_points)
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
    var seed := 98765
    var changed_point := Vector3.INF
    for attempt in range(20):
        var points := FPWorldFeatures.rest_points(m.RESTROOM_CENTER,seed)
        for p in m.rest_points:
            if not FPWorldFeatures.in_container(p,points):
                changed_point=p
                break
        if changed_point != Vector3.INF: break
        seed += 1
    check(changed_point != Vector3.INF,"fixture has a container that moves after loading another seed")
    if changed_point != Vector3.INF:
        check(is_equal_approx(m._world_density(changed_point),0.0),"old container hollow actually cached")
        m.tissue_tools.relayout_rest_points(seed)
        check(is_equal_approx(m._world_density(changed_point),expected(changed_point)),"layout change invalidates old hollow samples")
        check(m._world_density(changed_point)>0.5,"old container hollow no longer returned after layout changes")
        for p in m.rest_points:
            check(is_equal_approx(m._world_density(p),0.0),"new container hollow uses new layout")
    print("%d passed, %d failed" % [passed,failed])
    m.queue_free()
    await process_frame
    quit(1 if failed else 0)
