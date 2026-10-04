extends SceneTree

var passed := 0
var failed := 0
const Main = preload("res://main/scripts/main.gd")
const FAR := Vector3.ONE*1000

func _init() -> void:
    run.call_deferred()

func check(ok: bool,label: String) -> void:
    if ok: passed += 1
    else:
        failed += 1
        print("FAIL: ",label)

func pair_field(rate: float,scale: float,amount: float) -> Dictionary:
    var field := FDKTerrainField.new()
    field.config = FDKTerrainConfig.new()
    field.config.chunk_size = 4
    field.config.regen_rate = rate
    field.density_sampler = func(_p): return 1.0
    root.add_child(field)
    field.set_process(false) # advance both fields in identical explicit simulation steps
    field.generate_region(AABB(Vector3.ZERO,Vector3.ONE*2))
    var at := Vector3.ONE*0.75
    field.dig_at(at,amount)
    var barriers := FDKBarrierField.new()
    barriers.terrain = field
    barriers.pressure_scale = scale
    root.add_child(barriers)
    var barrier := barriers.place(at,1.8)
    field.regen_blockers = [Vector4(at.x,at.y,at.z,barrier.radius)]
    return {"field":field,"barriers":barriers,"barrier":barrier,"at":at}

func run() -> void:
    for depth in [1.0,1.35,1.7]:
        for deficit in [0.25,0.5,1.0]:
            var old := pair_field(0.01,28.0*depth,deficit)
            var current := pair_field(FDKTerrainConfig.new().regen_rate,Main.BARRIER_PRESSURE*depth,deficit)
            var old_break := -1
            var new_break := -1
            var old_start: float = old.field.density_at(old.at)
            var new_start: float = current.field.density_at(current.at)
            check(is_equal_approx(old_start,new_start),"initial actual deficit")
            check(is_equal_approx(old.barrier.break_threshold,current.barrier.break_threshold),"strength unchanged")
            check(is_equal_approx(old.barrier.stress_decay,current.barrier.stress_decay),"relaxation unchanged")
            for tick in range(1400):
                old.field.regenerate_all(0.1,FAR,0.1)
                current.field.regenerate_all(0.1,FAR,0.1)
                old.barriers.update(0.1)
                current.barriers.update(0.1)
                if old.barrier.is_broken() and old_break < 0: old_break=tick
                if current.barrier.is_broken() and new_break < 0: new_break=tick
                if tick % 100 == 0:
                    check(is_equal_approx(old.barrier.stress,current.barrier.stress),"actual stress timeline at "+str(tick))
                    check(old.barrier.damage_step()==current.barrier.damage_step(),"actual damage state timeline")
                    check(is_equal_approx(current.field.density_at(current.at),new_start),"barrier protects actual density")
                if old_break >= 0 and new_break >= 0: break
            check(old_break==new_break,"actual break time preserved depth="+str(depth)+" deficit="+str(deficit))
            if deficit == 1.0:
                check(old_break >= 0,"full deficit still breaks barrier")
            if old_break >= 0:
                old.field.regen_blockers = []
                current.field.regen_blockers = []
                old.field.regenerate_all(0.1,FAR,0.1)
                current.field.regenerate_all(0.1,FAR,0.1)
                var old_growth: float = old.field.density_at(old.at)-old_start
                var new_growth: float = current.field.density_at(current.at)-new_start
                check(old_growth > 0 and new_growth > 0,"actual regrowth resumes after break")
                check(old_growth/new_growth >= 3.0,"released density uses slower continuous regeneration")
            print("BARRIER depth=",depth," deficit=",deficit," old_break_tick=",old_break," new_break_tick=",new_break)
            old.barriers.free()
            old.field.free()
            current.barriers.free()
            current.field.free()
    print("%d passed, %d failed" % [passed,failed])
    quit(1 if failed else 0)
