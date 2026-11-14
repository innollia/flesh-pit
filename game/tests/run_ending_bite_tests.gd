extends SceneTree

## The ending starts from the bite that opens the outside, not from a distance
## line (docs/design/overview.md "엔딩").
## - a torn cell with flesh still behind it opens nothing, however near the edge
## - a torn cell whose emptied corner joins a corner past the outer shell
##   (generator density 0) is a real hole to the outside
## - a real tear there (the M22 hand through Main.tear_effects, the same call
##   the chewer makes) arms the ending ENDING_BITE_DELAY later: the hole is in
##   the density first, the ending comes after, and nothing moves the player
## - a tear deep in the flesh arms nothing
## Real Main and real outer-shell flesh; save and key files are this suite's own.

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	Engine.max_fps = 60
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_ending_bite.json"
	m.save_path = "user://capture-ending-bite-tests.bin"
	root.add_child(m)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(c: int) -> void:
	for i in range(c):
		await physics_frame
		await process_frame

## Cell centres from `from` outward along `dir`, as long as they hold flesh.
func solid_run(from: Vector3, dir: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var cs: float = m.terrain_config.cell_size
	var last := Vector3.INF
	var t := 0.0
	while t < 6.0:
		var c: Vector3 = m.cell_center(from + dir * t)
		t += cs * 0.5
		if c == last:
			continue
		last = c
		if m.terrain.density_at(c) >= m.terrain_config.iso_level:
			out.append(c)
		elif not out.is_empty():
			break
	return out

func run() -> void:
	await frames(3)
	m.finish_opening()
	await frames(6)
	var R: float = m.OUTER_RADIUS
	var C: Vector3 = m.RESTROOM_CENTER
	var cs: float = m.terrain_config.cell_size
	var iso: float = m.terrain_config.iso_level
	m.player.set_physics_process(false)
	m.player.velocity = Vector3.ZERO

	# --- the rule itself, on real outer flesh (no tear effects, no timer) ---
	var dir_a := Vector3(-1, 0, 0)
	var run_a := solid_run(C + dir_a * (R - 2.5), dir_a)
	check(run_a.size() >= 3, "fixture: flesh runs to the outer edge along -X (%d cells)" % run_a.size())
	if run_a.size() >= 3:
		var edge: Vector3 = run_a[run_a.size() - 1]
		var inner: Vector3 = run_a[run_a.size() - 3]
		check(not m.tear_opens_outside(edge), "untorn flesh at the edge is no opening")
		var removed: float = m.eat_cell_at(inner)
		check(removed > 0.0 and m.terrain.density_at(inner) < iso, "fixture: a cell two short of the edge is really dug (%.1f)" % removed)
		check(not m.tear_opens_outside(inner), "a tear with flesh still behind it opens nothing (%.2f m from the centre)" % inner.distance_to(C))
		check(m.terrain.density_at(edge) >= iso, "the edge cell behind it still holds flesh")
		removed = m.eat_cell_at(edge)
		check(removed > 0.0, "fixture: the edge cell is really dug (%.1f)" % removed)
		check(m.tear_opens_outside(edge), "the tear whose corner reaches past the outer shell opens the outside")
		var far := 0.0
		for k in range(8):
			var corner: Vector3 = edge + Vector3(-0.5 if k & 1 == 0 else 0.5, -0.5 if k & 2 == 0 else 0.5, -0.5 if k & 4 == 0 else 0.5) * cs
			far = maxf(far, corner.distance_to(C))
		check(far >= R, "that cell does have a corner outside (%.2f >= %.1f)" % [far, R])
	check(not m.tear_opens_outside(C + Vector3(0, 0, 8.0)), "a place deep in the flesh is never an opening")
	check(m._ending_bite_t < 0.0 and not m.ended, "nothing armed the ending so far")

	# --- a real tear: the M22 hand, through the same tear_effects as the chewer ---
	var dir_b := Vector3(0, 0, -1)
	var pocket: Vector3 = C + dir_b * (R - 2.2) + Vector3(0, 0.3, 0)
	m.terrain.carve_sphere(pocket, 1.1)
	m.terrain.remesh_all()
	m.player.global_position = pocket + Vector3(0, -0.5, 0)
	m.player.rotation.y = 0.0 # looking -Z, outward
	m.player.camera_pivot.rotation.x = 0.0
	m.player.force_update_transform()
	await frames(4)
	m.player.global_position = pocket + Vector3(0, -0.5, 0)
	m.player.force_update_transform()
	m.progression.hands.clear()
	m.progression.mutation_tree._purchased["M22"] = true
	m.stomach.fill = 0.0
	var ma: FPMutationApply = m.mutation_apply
	var got_end := [false]
	m.ending_reached.connect(func(): got_end[0] = true)
	var tears := 0
	var armed_at := Vector3.INF
	var early := false
	while tears < 12 and m._ending_bite_t < 0.0 and not m.ended:
		var at: Vector3 = ma._alien_target()
		if at == Vector3.INF:
			# the collider lags the fresh hole: publish and look again
			m.terrain.remesh_all()
			await frames(2)
			m.player.global_position = pocket + Vector3(0, -0.5, 0)
			m.player.force_update_transform()
			at = ma._alien_target()
			if at == Vector3.INF:
				break
		at = m.cell_center(at)
		if not ma.alien_tear():
			break
		tears += 1
		var open: bool = m.tear_opens_outside(at)
		if m._ending_bite_t >= 0.0:
			armed_at = at
			early = early or not open
		else:
			early = early or open
	check(tears >= 1 and armed_at != Vector3.INF, "M22 tears outward until one opens the outside (%d tears)" % tears)
	check(not early, "the ending is armed by exactly the tear that opened the outside")
	if armed_at != Vector3.INF:
		check(is_equal_approx(m._ending_bite_t, m.ENDING_BITE_DELAY) and not m.ended and not got_end[0], "the opening tear arms the ending %.2f s ahead, it has not started" % m.ENDING_BITE_DELAY)
		check(m.terrain.density_at(armed_at) < iso, "the hole is already in the density when the ending is armed")
		var stood: Vector3 = m.player.global_position
		check(stood.distance_to(C) < R - 0.3, "the player still stands inside the shell (%.2f m)" % stood.distance_to(C))
		var waited := 0.0
		var n := 0
		while not m.ended and n < 120:
			await process_frame
			waited += 1.0 / 60.0
			n += 1
		check(m.ended and got_end[0] and m.ending.active, "the ending starts after the bite (%d frames)" % n)
		check(n >= 2, "not on the frame of the tear")
		check(m.player.global_position.distance_to(stood) < 0.05, "the player was not moved to make it happen")
		check(m._ending_bite_t < 0.0, "the bite timer is spent")
	m.queue_free()
	await frames(2)
	print("--- %d passed, %d failed ---" % [passed, failed])
	quit(1 if failed > 0 else 0)
