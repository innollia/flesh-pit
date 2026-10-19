extends SceneTree

## Performance budget (2026-10-19: "few polygons, little going on, why the
## lag"). Work counts, not timings, so the checks hold on any machine:
## - standing idle, chunks are not re-meshed every frame (regrowth hairs and
##   out-of-sight contraction pulses each cost a whole chunk mesh before)
## - the temporary tear patch drops tiles as their real mesh is published,
##   even while the flesh keeps regrowing (it used to keep and rebuild the
##   whole dug area every frame)
## - the camera guard's many rays refresh that patch once a frame
## - staggered regrowth grows every chunk by the same total as per-frame
## Timings come from tests/bench_play.gd (windowed, same machine).

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	root.add_child(m)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func run() -> void:
	await frames(5)
	m.finish_opening()
	var t: FDKTerrainField = m.terrain
	# let world streaming and the first meshes settle
	await frames(240)
	# idle in the restroom
	m.player.global_position = Vector3(0.3, 0.9, 0.2)
	var before := t.remesh_count
	await frames(180)
	var idle := t.remesh_count - before
	check(idle <= 12, "idle in the restroom, chunks are hardly re-meshed (%d in 180 frames)" % idle)
	# a tear in the flesh: the patch goes once its real mesh is out
	m.restroom.set_door_open(true, true)
	var p := Vector3(0.25, 1.25, FPRestroom.HALF.z + 0.75)
	t.queue_visible_tear(p)
	t.dig_at(p, 1.0)
	var cleared := false
	for i in range(240):
		await process_frame
		if t._surface_patch == null or t._surface_patch_tiles.is_empty():
			cleared = true
			break
	check(cleared, "the tear patch clears as its mesh is published, while regrowth runs")
	# many camera guard rays in one frame refresh the patch once
	t.dig_at(p + Vector3(0.5, 0, 0), 1.0)
	var refreshes := t.patch_refresh_count
	for i in range(20):
		t.constrain_eye(m.player.camera.global_position, m.player.global_position, 0.05)
	check(t.patch_refresh_count - refreshes <= 1, "twenty guard checks in one frame refresh the patch at most once (%d)" % (t.patch_refresh_count - refreshes))
	t.dig_at(p + Vector3(1.0, 0, 0), 1.0)
	t.constrain_eye(m.player.camera.global_position, m.player.global_position, 0.05)
	check(t.patch_refresh_count - refreshes >= 1 or t._surface_patch == null, "a new edit in the same frame refreshes it again")
	# staggered regrowth: same total growth per chunk
	var cell := Vector3(3.25, 1.25, 4.25) # core flesh (the boundary band near 9 m never regrows)
	t.dig_at(cell, 1.0)
	var g := Vector3i((cell / t.config.cell_size).floor())
	var d0 := t.corner_density_global(g)
	m.set_process(false)
	t.regen_stagger = 6
	for i in range(12):
		t.regenerate_all(0.5, Vector3(100, 100, 100), 0.0)
	# growth still waiting for its chunk's turn is applied on the next turns
	for i in range(6):
		t.regenerate_all(0.0, Vector3(100, 100, 100), 0.0)
	var staggered := t.corner_density_global(g) - d0
	t.dig_at(cell, 1.0)
	d0 = t.corner_density_global(g)
	t.regen_stagger = 1
	for i in range(12):
		t.regenerate_all(0.5, Vector3(100, 100, 100), 0.0)
	var direct := t.corner_density_global(g) - d0
	t.regen_stagger = m.REGEN_STAGGER
	m.set_process(true)
	check(direct > 0.0 and absf(staggered - direct) <= direct * 0.2 + 0.0005, "staggered regrowth grows as much as growing every frame (%.4f vs %.4f)" % [staggered, direct])
	check(m.terrain.regen_stagger > 1, "the game spreads regrowth over frames")
	print("--- perf budget: %d passed, %d failed ---" % [passed, failed])
	m.queue_free()
	quit(1 if failed else 0)
