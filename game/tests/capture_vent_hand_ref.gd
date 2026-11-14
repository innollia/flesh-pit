extends SceneTree

## The vent being's hand laid flat beside the photo references (back and
## palm, orthographic, fingers straight) and in its holding pose from the
## side, for the proportion pass (orchestra/vent/ref/proportions.md).
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --script res://tests/capture_vent_hand_ref.gd
## VENT_BUILD=B shows build B (FPVent art BUILD_B: the same lengths, 8-10 % broader).

var out := ""

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.2, 0.22)
	root.add_child(env)
	# VENT_BUILD=B: the broader hand of the A/B pick
	if OS.get_environment("VENT_BUILD") == "B":
		load("res://main/art/fp_vent.gd").set("build_b", true)
	var art: Node3D = (load("res://main/art/fp_vent.tscn") as PackedScene).instantiate()
	root.add_child(art)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.22
	root.add_child(cam)
	cam.current = true
	await frames(2)
	art.call("set_open", 1.0)
	art.call("set_offer_items", ["junk"])
	art.call("set_offer_extend", 1.0)
	await frames(3)
	var rig: Dictionary = art.get("_rigs")[0]
	var hand: Node3D = rig["hand"]
	(rig["slot"] as Node3D).visible = false
	art.set_process(false)
	# lay the hand upright in front of the camera: fingers up the screen
	rig["mirror"] = 1.0
	hand.global_transform = Transform3D(Basis(Vector3(0, 0, 1), PI), Vector3(0, -2, 0))
	for flat in [true, false]:
		art.set("flat_pose", flat)
		art.call("_pose_fingers")
		var tag := "flat" if flat else "hold"
		# back of the hand (-Z side), palm (+Z side), side (+X, thumb side)
		for v in [["back", Vector3(0, 0, -1)], ["palm", Vector3(0, 0, 1)], ["side", Vector3(1, 0, 0)]]:
			var d: Vector3 = hand.global_basis * (v[1] as Vector3)
			var c: Vector3 = hand.global_transform * Vector3(0, -0.075, 0)
			cam.global_position = c + d.normalized() * 0.5
			cam.look_at(c, hand.global_basis * Vector3(0, -1, 0))
			await frames(3)
			root.get_viewport().get_texture().get_image().save_png(out.path_join("handref_%s_%s.png" % [tag, v[0]]))
			print("CAP handref_%s_%s" % [tag, v[0]])
	quit(0)
