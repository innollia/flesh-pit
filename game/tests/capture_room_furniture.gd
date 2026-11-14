extends SceneTree

## Furniture and layout captures: the room from the door and from the seat,
## the toilet, tub, door, paper holder, basin, shower, the vent seen from the
## door, and the inside of a rest container. Run WINDOWED:
##   godot_console --path game --resolution 960x540 --fixed-fps 60
##     --script res://tests/capture_room_furniture.gd -- <out_dir> <tag>
## Writes <out_dir>/<tag>_<shot>.png. Isolated save slot and key file.

var m: Node3D
var out_dir := ""
var tag := "shot"
var cam: Camera3D
var failed := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://capture-room-furniture")
	tag = args[1] if args.size() > 1 else "shot"
	DirAccess.make_dir_recursive_absolute(out_dir)
	run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(label: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := out_dir.path_join("%s_%s.png" % [tag, label])
	if image.save_png(path) != OK:
		failed += 1
	print("SHOT ", path)

func free_cam(pos: Vector3, target: Vector3, fov: float = 70.0) -> void:
	# the free camera is a bystander's eye: without this the player's own
	# body stands in the picture
	m.player.visible = false
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	cam.make_current()

func player_view(feet: Vector3, yaw: float, pitch: float) -> void:
	m.player.visible = true
	m.player.global_position = feet
	m.player.velocity = Vector3.ZERO
	m.player._yaw = yaw
	m.player._pitch = pitch
	m.player.rotation.y = yaw
	m.player.camera_pivot.rotation.x = pitch
	m.player.camera.make_current()

func player_look(feet: Vector3, target: Vector3) -> void:
	m.player.global_position = feet
	m.player.velocity = Vector3.ZERO
	await process_frame
	var eye: Vector3 = m.player.camera.global_position
	var d := (target - eye).normalized()
	player_view(feet, atan2(-d.x, -d.z), asin(clampf(d.y, -1.0, 1.0)))

func run() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_room_furniture.json"
	m.save_path = "user://capture-room-furniture.bin"
	root.add_child(m)
	await frames(6)
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.player.set_physics_process(false)
	cam = Camera3D.new()
	cam.near = 0.02
	cam.cull_mask &= ~FPMirrorReflection.MIRROR_BODY_LAYER
	root.add_child(cam)
	var r: FPRestroom = m.restroom
	r.set_door_open(false, true)
	m.apply_atmosphere_now()
	await frames(4)
	# --- the seat: the game's first view
	for view in [["seat_level", 0.0], ["seat_opening", -0.28], ["seat_up_15", 0.26]]:
		player_view(m.SEAT_POS, PI, view[1])
		await frames(3)
		await shot(view[0])
	# --- furniture, free camera
	free_cam(Vector3(-0.9, 1.2, -0.3), Vector3(0, 0.45, -1.2), 55.0)
	await shot("toilet_3q")
	free_cam(Vector3(-1.1, 0.7, -1.15), Vector3(0, 0.45, -1.15), 55.0)
	await shot("toilet_side")
	free_cam(Vector3(-0.3, 1.6, 0.4), Vector3(1.4, 0.4, -1.0), 60.0)
	await shot("tub_3q")
	free_cam(Vector3(0, 1.3, -0.6), Vector3(0, 1.0, 1.5), 60.0)
	await shot("door_inside")
	free_cam(Vector3(-0.2, 1.0, -0.7), Vector3(-0.55, 0.7, -1.5), 50.0)
	await shot("paper_holder")
	free_cam(Vector3(-1.0, 1.45, -0.3), Vector3(-2.2, 0.85, -0.3), 60.0)
	await shot("sink_front")
	free_cam(Vector3(-1.3, 1.25, 0.25), Vector3(-2.2, 0.8, -0.35), 55.0)
	await shot("sink_angle")
	free_cam(Vector3(-1.3, 0.75, 0.3), Vector3(-2.2, 0.65, -0.3), 55.0)
	await shot("sink_low")
	free_cam(Vector3(-0.35, 1.5, -0.85), Vector3(-2.25, 1.5, -0.85), 75.0)
	await shot("shower_wall_straight")
	free_cam(Vector3(-1.2, 1.7, -0.2), Vector3(-2.25, 1.6, -1.1), 65.0)
	await shot("shower_mirror_close")
	free_cam(Vector3(1.9, 1.9, 1.2), Vector3(-0.6, 0.9, -0.9), 75.0)
	await shot("room_wide")
	await player_look(Vector3(-1.2, 0.9, -0.75), FPRestroom.CANARY_HOLE + Vector3(0, 0.14, 0))
	await shot("hole_standing")
	# --- walking in through the door
	r.set_door_open(true, true)
	await player_look(Vector3(0, 0.9, 1.3), Vector3(0, 0.9, -1.4))
	await frames(4)
	await shot("door_enter")
	# --- the vent open with an offer, from the same spot at the door
	r.set_door_open(false, true)
	m.vent.open(30)
	await frames(50)
	m.progression.teeth_in_hand = 30
	m.place_teeth_at_vent()
	await frames(100)
	await player_look(Vector3(0, 0.9, 1.3), Vector3(0, 0.9, -1.4))
	await shot("vent_from_door")
	player_view(m.SEAT_POS, PI, 0.0)
	await shot("vent_from_seat")
	player_view(m.SEAT_POS, PI, 0.26)
	await shot("vent_from_seat_up_15")
	# --- inside a rest container (the terrain streams in around the player)
	var rest: Node3D = m.rest_cans[0].get_parent()
	m.player.global_position = rest.to_global(Vector3(0.0, -0.2, 0.0))
	await frames(400)
	free_cam(rest.to_global(Vector3(0.3, 0.45, 1.9)), rest.to_global(Vector3(-0.2, -0.5, -1.2)), 75.0)
	await shot("rest_inside_a")
	free_cam(rest.to_global(Vector3(0.3, 0.45, -1.9)), rest.to_global(Vector3(-0.2, -0.5, 1.2)), 75.0)
	await shot("rest_inside_b")
	free_cam(rest.to_global(Vector3(0.7, 0.3, 0.2)), rest.to_global(Vector3(-1.1, -0.1, 0.0)), 80.0)
	await shot("rest_door_wall")
	# --- the container model alone, far outside the flesh (no terrain in it).
	# FP_OLD_CONTAINER=<path of an older fp_rest_container.gd> shoots that
	# model stretched the way it used to be placed, for a before picture.
	var art: Node3D = (load("res://main/art/fp_rest_container.tscn") as PackedScene).instantiate()
	var old := OS.get_environment("FP_OLD_CONTAINER")
	if old != "":
		art.set_script(load(old))
		art.scale = Vector3(2.2 / 1.5, 2.2 / 1.3, 1.1 / 1.2)
	var stand := Node3D.new()
	stand.position = Vector3(0, 300, 0)
	root.add_child(stand)
	stand.add_child(art)
	art.call("set_flicker", false)
	art.call("set_door_open", 0.8)
	var o := stand.position
	await frames(4)
	free_cam(o + Vector3(1.9, 1.55, 0.6), o + Vector3(-1.2, 0.5, -0.6), 75.0)
	await shot("can_inside_chair")
	free_cam(o + Vector3(-1.9, 1.55, -0.5), o + Vector3(1.7, 0.3, 0.2), 75.0)
	await shot("can_inside_bucket")
	free_cam(o + Vector3(-0.5, 1.45, -0.8), o + Vector3(0.1, 1.4, 1.1), 70.0)
	await shot("can_inside_door_wall")
	free_cam(o + Vector3(3.4, 2.6, 5.2), o + Vector3(0, 1.0, 0), 55.0)
	await shot("can_outside")
	print("CAPTURE done failed=", failed)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture-room-furniture.bin"))
	m.queue_free()
	await frames(2)
	quit(1 if failed else 0)
