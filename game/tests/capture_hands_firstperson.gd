extends SceneTree

## First-person hands in the real game: idle, grab, tear and the restroom
## start view. Uses only what Main and the hand rig have had since before the
## protagonist reshaping, so the same file runs against an older checkout for
## a before/after pair (give this file's absolute path to --script there).
##   godot_console --path game --resolution 960x540 --fixed-fps 60
##     --script res://tests/capture_hands_firstperson.gd -- <out dir> <tag>
## Writes <tag>_idle.png, <tag>_grab.png, <tag>_tear.png, <tag>_restroom.png.
## The player's normal save and key file are never read or written.

const SAVE := "user://capture-hands-firstperson.bin"

var out_dir := ""
var tag := "shot"
var m: Node3D

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://capture-hands-firstperson")
	tag = args[1] if args.size() > 1 else "shot"
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(960, 540)
	run.call_deferred()

func frames(count: int) -> void:
	for i in range(count):
		await process_frame

func save(label: String) -> void:
	await frames(2)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join("%s_%s.png" % [tag, label]))
	print("saved ", label)

func pose(pos: Vector3, yaw: float, pitch: float) -> void:
	var p = m.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.set("_yaw", yaw)
	p.set("_pitch", pitch)
	p.rotation.y = yaw
	p.camera_pivot.rotation.x = pitch

func run() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_hands_firstperson.json"
	m.save_path = SAVE
	root.add_child(m)
	await frames(6)
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.restroom.set_door_open(false, true)
	var rig = m.hands_rig
	# the restroom as the game starts
	pose(m.START_POS, m.START_YAW, m.START_PITCH)
	await frames(30)
	await save("restroom")
	# idle: level view at a wall, hands at rest
	pose(m.START_POS, m.START_YAW + PI * 0.5, 0.0)
	await frames(30)
	await save("idle")
	# grab: both hands out, the bite half chewed
	rig.on_grab_started()
	for i in range(24):
		rig.on_chew_progress(0.6)
		await process_frame
	await save("grab")
	# tear: a little into the pull
	rig.on_cell_torn()
	await frames(5)
	await save("tear")
	rig.on_released()
	m.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://keybinds_test_hands_firstperson.json"))
	quit(0)
