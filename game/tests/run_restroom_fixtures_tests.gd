extends SceneTree

## Restroom fixture fixes (2026-11-03 user requests):
## 1. no light stuck on the doorway pointing out; the lamp's glare is the
##    eye adaptation on coming back in (real Main atmosphere loop)
## 2. the basin is a low-poly PS1 prop: few faces, 64 px ceramic, 32 px
##    painted bowl image
## 3. the shower riser does not intersect the mirror cabinet (shut or open)
## 4. each mirror door has a solid back behind the glass

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func world_aabb(mi: MeshInstance3D) -> AABB:
	return mi.global_transform * mi.mesh.get_aabb()

func tri_count(mi: MeshInstance3D) -> int:
	var total := 0
	for s in range(mi.mesh.get_surface_count()):
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		total += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return total

func _run() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_restroom_fixtures.json"
	m.save_path = "user://capture-restroom-fixtures-test.bin"
	root.add_child(m)
	await frames(6)
	m.finish_opening()
	var r: FPRestroom = m.restroom
	await _test_door_light_and_glare(r)
	_test_basin(r)
	await _test_shower_vs_cabinet(r)
	_test_mirror_back(r)
	print("RESTROOM FIXTURES: %d passed, %d failed" % [passed, failed])
	m.queue_free()
	await frames(2)
	quit(1 if failed else 0)

func _test_door_light_and_glare(r: FPRestroom) -> void:
	r.set_door_open(true, true)
	var lights := r.find_children("*", "Light3D", true, false)
	check(r.find_children("*", "SpotLight3D", true, false).is_empty(), "no spot light cone on the restroom")
	check(r.get_node_or_null("DoorSpill") == null and r.get_node_or_null("DoorSpillFill") == null, "door spill lights removed")
	var reaches_out := false
	for l in lights:
		# terrain and default props live on layer 1; only room layers may be lit
		if (l as Light3D).light_cull_mask & 1:
			reaches_out = true
	check(not reaches_out, "every restroom light is culled to room layers, none lights the flesh outside (%d lights)" % lights.size())
	# real Main loop: 20 s of real dark arms, stepping in blows out, eases back
	m.player.set_physics_process(false)
	m.player.global_position = Vector3(0, 0.9, 6.0)
	m.terrain.fill_box_uniform(AABB(Vector3(-0.7, 0.0, 1.55), Vector3(1.4, 2.4, 5.0)), 0.0, 0)
	m.terrain.remesh_all()
	m._reset_glare()
	check(m._is_dark_atmosphere(m.player.global_position), "deep passage counts as real dark")
	m.glare_controller.reset(false)
	for i in range(21):
		m._update_atmosphere(1.0)
	check(m.glare_controller.glare_ready, "20 s in the dark arms the entry glare")
	check(is_equal_approx(m.environment.tonemap_exposure, 1.0), "no glare while still out in the dark")
	m.player.global_position = Vector3(0, 0.9, 0.5)
	m._update_atmosphere(1.0 / 60.0)
	var peak: float = m.environment.tonemap_exposure
	check(m.glare_controller.total_flashes == 1 and peak > 3.5, "stepping into the lit room blows the view out (exposure %.2f)" % peak)
	var prev := peak
	var falls := true
	var at_half := 0.0
	for i in range(160):
		m._update_atmosphere(1.0 / 60.0)
		if m.environment.tonemap_exposure > prev + 0.0001:
			falls = false
		prev = m.environment.tonemap_exposure
		if i == 29:
			at_half = prev
	check(falls, "exposure only eases down while the eyes adapt")
	check(at_half > 1.8 and at_half < peak, "half a second in, still dazzled (%.2f)" % at_half)
	check(is_equal_approx(m.environment.tonemap_exposure, 1.0), "adapted to normal exposure within ~2.7 s")
	# M24 owl eyes: the dazzle lasts twice as long
	m.glare_controller.reset(false)
	m.player.global_position = Vector3(0, 0.9, 6.0)
	for i in range(21):
		m._update_atmosphere(1.0)
	m.progression.mutation_tree._purchased["M24"] = true
	m.player.global_position = Vector3(0, 0.9, 0.5)
	for i in range(int(2.6 * 60)):
		m._update_atmosphere(1.0 / 60.0)
	check(m.environment.tonemap_exposure > 1.0, "M24 still dazzled after the normal adaptation time")
	m.progression.mutation_tree._purchased.erase("M24")
	m._reset_glare()
	m.player.set_physics_process(true)

func _test_basin(r: FPRestroom) -> void:
	var art: Node3D = r.mirror_art
	var body: MeshInstance3D = art.get_node_or_null("Basin")
	var bowl: MeshInstance3D = art.get_node_or_null("BasinBowl")
	check(body != null and bowl != null, "basin body and painted bowl exist")
	if body == null or bowl == null:
		return
	var tris := tri_count(body) + tri_count(bowl)
	# the old 12-sided double lathe was 12 * (5 + 3) * 2 = ~190 triangles
	check(tris <= 60, "basin is low-poly (%d triangles)" % tris)
	var body_tex: Texture2D = (body.material_override as ShaderMaterial).get_shader_parameter("albedo_tex")
	var bowl_tex: Texture2D = (bowl.material_override as ShaderMaterial).get_shader_parameter("albedo_tex")
	check(body_tex != null and body_tex.get_width() <= 64, "basin body wears the 64 px ceramic")
	check(bowl_tex != null and bowl_tex.get_width() <= 32, "bowl is a 32 px painted image")
	var img := bowl_tex.get_image()
	var centre: Vector2 = art.call("bowl_uv", Vector3(0, 0, 0.245)) * img.get_width()
	check(img.get_pixelv(Vector2i(centre)).v < 0.3, "drain painted dark in the bowl image")
	check(img.get_pixel(1, img.get_height() - 2).v > 0.7, "bowl glaze painted white toward the rim")
	# still a basin the hands can reach: the sink point sits over the bowl
	var top := world_aabb(body)
	check(top.end.y > 0.86 and top.end.y < 0.91 and top.position.y < 0.45, "basin keeps its height (top %.2f, bottom %.2f)" % [top.end.y, top.position.y])

func _test_shower_vs_cabinet(r: FPRestroom) -> void:
	var art: Node3D = r.mirror_art
	var shower := world_aabb(r.get_node("Shower"))
	var cabinet := world_aabb(art.get_node("StorageCabinet"))
	check(not shower.intersects(cabinet), "shower riser clear of the mirror cabinet (shower z %.2f..%.2f, cabinet z %.2f..%.2f)" % [shower.position.z, shower.end.z, cabinet.position.z, cabinet.end.z])
	check(shower.position.z > -FPRestroom.HALF.z, "shower stays inside the room")
	check(shower.position.x < -FPRestroom.HALF.x + 0.01, "shower stays on the -X wall (image A corner)")
	for open in [false, true]:
		if art.cabinet_open != open:
			art.call("toggle_cabinet")
		for i in range(5):
			art.call("_process", 1.0)
		for leaf in [art.door_surface, art.door_surface_right]:
			for mi in (leaf as Node3D).find_children("*", "MeshInstance3D", true, false):
				check(not shower.intersects(world_aabb(mi)), "shower clear of %s/%s (%s)" % [leaf.name, mi.name, "open" if open else "shut"])
	if art.cabinet_open:
		art.call("toggle_cabinet")
		for i in range(5):
			art.call("_process", 1.0)

func _test_mirror_back(r: FPRestroom) -> void:
	var art: Node3D = r.mirror_art
	for leaf in [art.door_surface, art.door_surface_right]:
		var back: MeshInstance3D = (leaf as Node3D).get_node_or_null("MirrorBack")
		check(back != null, "%s has a back board" % leaf.name)
		if back == null:
			continue
		check(back.visible and back.material_override != null, "%s back is drawn with a material" % leaf.name)
		# faces whose normal points away from the glass (-Z local) must cover
		# the glass rectangle
		var arr: Array = back.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var area := 0.0
		var bb := AABB()
		var first := true
		for i in range(0, v.size(), 3):
			if n[i].z < -0.9:
				area += (v[i + 1] - v[i]).cross(v[i + 2] - v[i]).length() * 0.5
				for k in range(3):
					if first:
						bb = AABB(v[i + k], Vector3.ZERO)
						first = false
					else:
						bb = bb.expand(v[i + k])
		var glass_area: float = (2.0 * art.LEAF_W) * (2.0 * art.HH)
		check(area > glass_area * 0.97, "%s back faces cover the glass (%.3f of %.3f m2)" % [leaf.name, area, glass_area])
		check(bb.position.x <= -art.LEAF_W + 0.01 and bb.end.x >= art.LEAF_W - 0.01 and bb.position.y <= art.CY - art.HH + 0.01 and bb.end.y >= art.CY + art.HH - 0.01, "%s back spans the whole leaf" % leaf.name)
		var glass: MeshInstance3D = (leaf as Node3D).get_node("Glass")
		check(world_aabb(back).get_center().distance_to(world_aabb(glass).get_center()) < 0.03, "%s back sits right behind its glass" % leaf.name)
