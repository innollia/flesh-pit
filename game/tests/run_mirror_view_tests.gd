extends SceneTree

## The restroom mirror behaves like a real flat mirror from where the player
## stands (2026-11-09 user: "거울 보이는 시야각, 범위 문제"):
## - the reflection camera sits at the eye mirrored across the glass, its
##   frustum clipped exactly to the glass (no wider or narrower field), so a
##   room point shows on the glass exactly where its mirror image would;
## - the reflection stays live whenever any part of the glass is on screen
##   (it used to go blank grey as soon as the glass centre left the view);
## - near and far: from the glass to the far wall of the room.
## Isolated save and key files.

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
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

func look_at_point(p: Vector3, off_yaw := 0.0, off_pitch := 0.0) -> void:
	var e: Vector3 = m.player.camera.global_position
	var v := p - e
	m.player._yaw = atan2(-v.x, -v.z) + off_yaw
	m.player._pitch = atan2(v.y, Vector2(v.x, v.z).length()) + off_pitch

## Where a world point lands on the screen through the reflection: the
## reflection camera's view of it, mapped onto the glass quad, seen by the eye.
func through_glass(view: FPMirrorReflection, world: Vector3) -> Vector2:
	var px: Vector2 = view.cam.unproject_position(world)
	var uv := px / Vector2(FPMirrorReflection.VP_SIZE)
	# the quad's uv (fp_mirror_reflection._build_quad): u = 0.5 - x / 2W
	var lx := (0.5 - uv.x) * 2.0 * FPMirrorReflection.GLASS_W
	var ly := FPMirrorReflection.GLASS_CY + (0.5 - uv.y) * 2.0 * FPMirrorReflection.GLASS_HH
	var on_glass: Vector3 = view.art.global_transform.orthonormalized() * Vector3(lx, ly, FPMirrorReflection.GLASS_Z - 0.001)
	return m.player.camera.unproject_position(on_glass)

func run() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_mirror_view.json"
	m.save_path = "user://mirror-view-test.bin"
	root.add_child(m)
	await frames(6)
	m.save_path = "user://mirror-view-test.bin"
	m.finish_opening()
	await frames(6)
	var feet_y: float = m.player.global_position.y
	# both cabinet leaves are mirrors
	for leaf: FPMirrorReflection in [m.mirror_view, m.mirror_view_right]:
		await check_leaf(leaf, feet_y)
	var view: FPMirrorReflection = m.mirror_view
	var g: Vector3 = view.art.to_global(Vector3(0, FPMirrorReflection.GLASS_CY, FPMirrorReflection.GLASS_Z))
	# whole glass off screen: the reflection stops rendering
	m.player.global_position = Vector3(g.x, feet_y, g.z) + Vector3(1.4, 0, 0)
	await frames(2)
	look_at_point(g, PI, 0.0)
	await frames(3)
	check(not view._quad.visible, "facing away: the reflection does not render")
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func check_leaf(view: FPMirrorReflection, feet_y: float) -> void:
	var g: Vector3 = view.art.to_global(Vector3(0, FPMirrorReflection.GLASS_CY, FPMirrorReflection.GLASS_Z))
	var n: Vector3 = view.art.global_transform.basis.z.normalized()
	# standing spots in front of the sink: close, mid, far wall, and to the side
	var spots := {"close": Vector3(0.6, 0, 0), "mid": Vector3(1.4, 0, 0), "far": Vector3(3.6, 0, 0),
		"side": Vector3(1.2, 0, 0.9), "oblique_close": Vector3(0.5, 0, 0.8), "other_side": Vector3(1.6, 0, -1.0)}
	# room points to check through the glass: the far corners and the middle
	var room_pts := [Vector3(1.8, 0.3, 1.2), Vector3(1.8, 2.2, -1.2), Vector3(0.0, 1.0, 0.0), Vector3(-1.2, 1.6, 0.6), Vector3(2.1, 1.2, -1.4)]
	for name0 in spots:
		var name := "%s %s" % [view.name, name0]
		var at: Vector3 = Vector3(g.x, feet_y, g.z) + spots[name0]
		at.z = clampf(at.z, -1.2, 1.2) # stay inside the restroom
		m.player.global_position = at
		m.player.velocity = Vector3.ZERO
		await frames(3)
		look_at_point(g)
		await frames(4)
		var e: Vector3 = m.player.camera.global_position
		var d := n.dot(e - g)
		var mirrored := e - n * (2.0 * d)
		check(view._quad.visible, "%s: looking at the mirror shows the reflection" % name)
		check(view.cam.global_position.distance_to(mirrored) < 0.002, "%s: reflection eye is the eye mirrored across the glass (off %.4f m)" % [name, view.cam.global_position.distance_to(mirrored)])
		# the frustum is the glass: its four corners are the view's four corners
		var corners := FPMirrorReflection.glass_corners(view.art)
		var want := [Vector2(FPMirrorReflection.VP_SIZE.x, FPMirrorReflection.VP_SIZE.y), Vector2(0, FPMirrorReflection.VP_SIZE.y), Vector2(0, 0), Vector2(FPMirrorReflection.VP_SIZE.x, 0)]
		var worst := 0.0
		for i in range(4):
			worst = maxf(worst, (view.cam.unproject_position(corners[i]) - want[i]).length())
		check(worst < 0.5, "%s: glass corners frame the reflection exactly (worst %.2f px of 128x192)" % [name, worst])
		# same field and aspect as a flat mirror: every visible room point
		# lands where its mirror image does (within one reflection texel)
		var texel: float = m.player.camera.get_viewport().get_visible_rect().size.y / 540.0 * 3.0
		for p in room_pts:
			var pw: Vector3 = p # restroom space: floor at y 0, centre (0, 1, 0)
			var px: Vector2 = view.cam.unproject_position(pw)
			if view.cam.is_position_behind(pw) or px.x < 0 or px.y < 0 or px.x > FPMirrorReflection.VP_SIZE.x or px.y > FPMirrorReflection.VP_SIZE.y:
				continue
			var err: float = (through_glass(view, pw) - view.image_screen(pw)).length()
			check(err < texel + 2.0, "%s: room point %s shows where its mirror image is (off %.1f px)" % [name, p, err])
		# near and far cover the room: from the glass to past the far wall
		check(absf(view.cam.near - d) < 0.002, "%s: near plane is the glass (%.3f vs %.3f)" % [name, view.cam.near, d])
		check(view.cam.far >= 2.0 * d + 8.0, "%s: far plane reaches past the far wall (%.1f m)" % [name, view.cam.far])
		# bowed toward the basin, or turned so the glass centre is off screen
		# while the glass edge still shows: the reflection must stay live
		for turn in [Vector2(0.0, -0.75), Vector2(0.95, 0.0), Vector2(-0.95, 0.0), Vector2(0.0, 0.62)]:
			look_at_point(g, turn.x, turn.y)
			await frames(3)
			var any_on := FPMirrorReflection.glass_on_screen(view.art, m.player.camera)
			var centre_on: bool = m.player.camera.is_position_in_frustum(g)
			if any_on and not centre_on:
				check(view._quad.visible and view._vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "%s turned %s: glass edge on screen keeps the reflection (not blank glass)" % [name, turn])
