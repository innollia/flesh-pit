extends SceneTree

## Turntable of the protagonist's models alone: the first-person hand rig and
## the mirror/Tab body, on a flat grey stage. No game scene is loaded, so no
## save file is ever opened. Run WINDOWED:
##   godot_console --path game --resolution 960x540 --fixed-fps 60
##     --script res://tests/capture_protagonist.gd -- <out_dir> <tag>
## Writes <out_dir>/<tag>_hand_<pose>_<view>.png and
## <out_dir>/<tag>_body_<view>_<distance>.png.

var out_dir := ""
var tag := "shot"
var cam: Camera3D
var stage: Node3D

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://capture-protagonist")
	tag = args[1] if args.size() > 1 else "shot"
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(960, 540)
	run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(label: String) -> void:
	await frames(2)
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join("%s_%s.png" % [tag, label])
	root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path)

func view(from: Vector3, at: Vector3, up: Vector3 = Vector3.UP) -> void:
	cam.global_position = from
	cam.look_at(at, up)

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.45, 0.47)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	stage.add_child(sun)
	cam = Camera3D.new()
	cam.near = 0.01
	cam.fov = 38.0
	stage.add_child(cam)
	cam.current = true
	await hands()
	await body()
	quit(0)

func hands() -> void:
	var rig := FDKHandsRig.new()
	stage.add_child(rig)
	rig.get_node("HandLeft").visible = false
	await frames(30)
	for pose in ["idle", "grab", "wet"]:
		if pose == "grab":
			rig.on_grab_started()
			await frames(30)
		elif pose == "wet":
			rig.on_released()
			await frames(40)
			rig.set("_wet", 1.0)
		var wrist: Node3D = rig.get_node("HandRight/Wrist")
		var t := wrist.global_transform
		var mid := t * Vector3(0.012, 0.0, -0.085)
		var b := t.basis
		var views := {
			"back": [mid + b.y * 0.36, -b.z],
			"palm": [mid - b.y * 0.36, -b.z],
			"thumb": [mid - b.x * 0.36 + b.y * 0.05, b.y],
			"tips": [mid - b.z * 0.36 + b.y * 0.1, b.y],
		}
		if pose == "wet":
			views = {"back": views["back"]}
		for v in views:
			view(views[v][0], mid, views[v][1])
			await shot("hand_%s_%s" % [pose, v])
	rig.queue_free()
	await frames(2)

func body() -> void:
	var b := FPMirrorBody.new()
	stage.add_child(b)
	await frames(4)
	b.apply([])
	var dirs := {"front": 0.0, "left45": 45.0, "side": 90.0, "back": 180.0}
	for d in dirs:
		var a := deg_to_rad(dirs[d])
		var dir := Vector3(sin(a), 0, cos(a))
		view(Vector3(0, 0.9, 0) + dir * 3.1, Vector3(0, 0.9, 0))
		await shot("body_%s_full" % d)
		view(Vector3(0, 1.25, 0) + dir * 1.35, Vector3(0, 1.22, 0))
		await shot("body_%s_upper" % d)
	# the reflection's right hand alone, close (palm side and back of hand)
	var hand: Vector3 = (b.sub_node("hand_r").global_position + b.sub_node("fingers_r").global_transform * Vector3(0, 0.05, 0.03)) * 0.5
	for d in ["front", "back", "out"]:
		var dir := Vector3(0, 0.1, 1) if d == "front" else (Vector3(0, 0.1, -1) if d == "back" else Vector3(1, 0.1, 0.2))
		view(hand + dir.normalized() * 0.4, hand)
		await shot("body_hand_%s" % d)
	# walking and crouching: the upper-arm roots swing here (armpit gaps)
	b.set_posture(0.0, 1.2, 1.0, 0.0)
	view(Vector3(0, 0.9, 3.1), Vector3(0, 0.9, 0))
	await shot("body_walk_front_full")
	view(Vector3(1.0, 1.25, 1.0), Vector3(0, 1.22, 0))
	await shot("body_walk_left45_upper")
	b.set_posture(1.0, 0.0, 0.0, 0.0)
	view(Vector3(0, 0.9, 3.1), Vector3(0, 0.9, 0))
	await shot("body_crouch_front_full")
	b.set_posture(0.0, 0.0, 0.0, 0.0)
	# the shape mutations that scale the trunk, on top of the base figure
	for set in [["M01", "M06"], ["M14", "T4"], ["M07", "M10", "M18"]]:
		b.apply(set)
		await frames(2)
		view(Vector3(2.2, 0.9, 2.2), Vector3(0, 0.9, 0))
		await shot("body_mut_%s" % "_".join(PackedStringArray(set)))
	b.apply([])
	b.queue_free()
	await frames(2)
