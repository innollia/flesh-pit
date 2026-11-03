extends SceneTree

## Restroom fixture captures (lamp/door light, glare on entry, sink, shower vs
## mirror cabinet, back of the opened mirror doors). Run WINDOWED:
##   godot_console --path game --resolution 960x540
##     --script res://tests/capture_restroom_fixtures.gd -- <out_dir> <tag>
## Writes <out_dir>/<tag>_<shot>.png. Uses an isolated save slot.

var m: Node3D
var out_dir := ""
var tag := "shot"
var cam: Camera3D
var failed := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://capture-restroom")
	tag = args[1] if args.size() > 1 else "shot"
	DirAccess.make_dir_recursive_absolute(out_dir)
	run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := out_dir.path_join("%s_%s.png" % [tag, label])
	if image.save_png(path) != OK:
		failed += 1
	print("SHOT ", path)

func free_cam(pos: Vector3, target: Vector3, fov: float = 70.0) -> void:
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	cam.make_current()

func player_look(feet: Vector3, target: Vector3) -> void:
	m.player.global_position = feet
	m.player.velocity = Vector3.ZERO
	await process_frame
	var eye: Vector3 = m.player.camera.global_position
	var d := (target - eye).normalized()
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = asin(clampf(d.y, -1.0, 1.0))
	m.player.rotation.y = m.player._yaw
	m.player.camera_pivot.rotation.x = m.player._pitch
	m.player.camera.make_current()

func run() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://capture-restroom.bin"
	root.add_child(m)
	await frames(6)
	m.finish_opening()
	m.player.mouse_look_enabled = false
	cam = Camera3D.new()
	cam.near = 0.02
	cam.cull_mask &= ~FPMirrorReflection.MIRROR_BODY_LAYER
	root.add_child(cam)
	var r: FPRestroom = m.restroom
	r.set_door_open(false, true)
	m.apply_atmosphere_now()
	await frames(4)
	# --- sink close-up and room views (free camera inside the room)
	free_cam(Vector3(-1.0, 1.45, -0.3), Vector3(-2.2, 0.85, -0.3), 60.0)
	await frames(3)
	await shot("sink_front")
	free_cam(Vector3(-1.3, 1.25, 0.25), Vector3(-2.2, 0.8, -0.35), 55.0)
	await frames(3)
	await shot("sink_angle")
	# shower corner vs mirror cabinet (back-left corner of the -X wall)
	free_cam(Vector3(0.2, 1.6, 0.9), Vector3(-2.2, 1.5, -0.7), 60.0)
	await frames(3)
	await shot("shower_mirror")
	free_cam(Vector3(-1.2, 1.7, -0.2), Vector3(-2.25, 1.6, -1.1), 65.0)
	await frames(3)
	await shot("shower_mirror_close")
	free_cam(Vector3(-0.35, 1.5, -0.85), Vector3(-2.25, 1.5, -0.85), 75.0)
	await frames(3)
	await shot("shower_wall_straight")
	free_cam(Vector3(-1.75, 1.35, -0.3), Vector3(-2.0, 0.8, -0.3), 60.0)
	await frames(3)
	await shot("basin_top")
	# the canary hole from the player's standing eye (spec 03: hidden by the
	# basin from standing height, seen only crouching)
	m.player.set_physics_process(false)
	await player_look(Vector3(-1.2, 0.9, -0.75), FPRestroom.CANARY_HOLE + Vector3(0, 0.14, 0))
	await frames(3)
	await shot("hole_standing")
	await player_look(Vector3(-1.0, 0.9, -0.3), Vector3(-2.2, 0.6, -0.3))
	await frames(3)
	await shot("sink_player_eye")
	m.player.set_physics_process(true)
	# mirror cabinet opened: look at the back of both doors
	r.mirror_art.call("toggle_cabinet")
	await frames(60)
	free_cam(Vector3(-0.6, 1.7, -0.3), Vector3(-2.0, 1.75, 0.3), 70.0)
	await frames(3)
	await shot("mirror_open_back_right")
	free_cam(Vector3(-0.8, 1.7, 0.5), Vector3(-2.0, 1.75, -0.6), 70.0)
	await frames(3)
	await shot("mirror_open_back_left")
	free_cam(Vector3(-0.5, 1.6, 0.3), Vector3(-2.25, 1.7, 0.3), 75.0)
	await frames(3)
	await shot("mirror_open_front")
	r.mirror_art.call("toggle_cabinet")
	await frames(60)
	# --- door light from the flesh passage (door open, tunnel dug)
	r.set_door_open(true, true)
	m.terrain.fill_box_uniform(AABB(Vector3(-0.7, 0.0, 1.55), Vector3(1.4, 2.4, 4.5)), 0.0, 0)
	m.terrain.remesh_all()
	m.player.set_physics_process(false)
	await player_look(Vector3(0.0, 0.9, 4.6), Vector3(0.0, 0.9, 1.5))
	m.apply_atmosphere_now()
	await frames(8)
	await shot("passage_toward_door")
	await player_look(Vector3(0.0, 0.9, 3.0), Vector3(0.0, 0.6, 5.5))
	m.apply_atmosphere_now()
	await frames(8)
	await shot("passage_floor_outside_door")
	# the door's own light only: eye lamp and body fill hidden
	m.player_lamp.visible = false
	m.body_fill.visible = false
	await player_look(Vector3(0.0, 0.9, 3.0), Vector3(0.0, 0.3, 5.5))
	await frames(4)
	await shot("passage_door_light_only_away")
	await player_look(Vector3(0.3, 0.9, 4.2), Vector3(0.0, 1.0, 1.5))
	await frames(4)
	await shot("passage_door_light_only_toward")
	var spill = m.restroom.get_node_or_null("DoorSpill")
	var fill = m.restroom.get_node_or_null("DoorSpillFill")
	print("DOORLIGHT spill=", spill != null and spill.visible and spill.light_energy > 0.0, " fill=", fill != null and fill.visible and fill.light_energy > 0.0)
	m.player_lamp.visible = true
	m.body_fill.visible = true
	# --- returning after a long dark dwell: real controller arming, then step in
	m.glare_controller.reset(false)
	m.glare_controller.step(false, 21.0, true)
	print("GLARE armed=", m.glare_controller.glare_ready)
	await player_look(Vector3(0.0, 0.9, 1.3), Vector3(-1.5, 1.2, -1.2))
	var start := Time.get_ticks_msec()
	var marks := [0.0, 0.3, 0.8, 1.5, 3.0, 5.0]
	for mark in marks:
		while (Time.get_ticks_msec() - start) / 1000.0 < mark:
			await process_frame
		await shot("enter_glare_t%.1f" % mark)
		print("GLARE t=", (Time.get_ticks_msec() - start) / 1000.0, " flashes=", m.glare_controller.total_flashes, " flash=", m._flash, " exposure=", m.environment.tonemap_exposure)
	print("CAPTURE done failed=", failed)
	m.queue_free()
	await frames(2)
	quit(1 if failed else 0)
