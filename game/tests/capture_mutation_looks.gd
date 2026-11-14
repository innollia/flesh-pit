extends SceneTree

## Before/after pictures of the protagonist's mutations, tumor bumps and
## hair. Run WINDOWED, one Godot at a time:
##   godot_console --path game --resolution 960x540 --fixed-fps 60
##     --script res://tests/capture_mutation_looks.gd -- <out_dir> <tag> <mode> [set,set,...]
## mode "model": the mirror/Tab body alone on a grey stage (no game scene, no
##   save): <tag>_model_<set>_<view>.png
## mode "game": the real game with an isolated save and key file; per set the
##   shots listed in SETS: <tag>_<set>_<shot>.png
##   A mirror blown up x4, B Tab doll, C hands held out, D looking down at
##   the belly, E a bystander beside the player, S the body's shadow on the
##   restroom floor, H the Tab look at the left forearm blown up x2.
## Hair sets in model mode: the hairy forearm scene alone (<set>_arm).
## The player's normal save and key file are never read or written.

const SAVE := "user://capture-mutation-looks.bin"
## set -> ids, belly bumps, hair [common, core, mantle, surface], game shots
const SETS := {
	"base": {"shots": "ABCDE"},
	"bump1": {"bumps": 1, "shots": "ABDE"},
	"bump3": {"bumps": 3, "shots": "ABD"},
	"bump7": {"bumps": 7, "shots": "ABD"},
	"hair6": {"hair": [2, 2, 1, 1], "shots": "CH"},
	"hair40": {"hair": [14, 9, 8, 9], "shots": "CH"},
	"hair240": {"hair": [60, 60, 60, 60], "shots": "BCH"},
	"core20": {"hair": [0, 20, 0, 0], "shots": "CH"},
	"mantle20": {"hair": [0, 0, 20, 0], "shots": "CH"},
	"surface20": {"hair": [0, 0, 0, 20], "shots": "CH"},
	"M23": {"ids": ["M23"], "shots": "ABCH"},
	"M23_hair240": {"ids": ["M23"], "hair": [60, 60, 60, 60], "shots": "CH"},
	"M09": {"ids": ["M09"], "shots": "AB"},
	"M15": {"ids": ["M15"], "shots": "AB"},
	"T1": {"ids": ["T1"], "shots": "AB"},
	"T3": {"ids": ["T3"], "shots": "AB"},
	"T6": {"ids": ["T6"], "shots": "AB"},
	"T7": {"ids": ["T7"], "shots": "ABS"},
	"T2": {"ids": ["T2"], "shots": "AB"},
	"M01": {"ids": ["M01"], "shots": "DEC"},
	"T4": {"ids": ["T4"], "shots": "DEC"},
	"T4_M01": {"ids": ["T4", "M01"], "shots": "DE"},
	"M16": {"ids": ["M16"], "shots": "DE"},
	"M03": {"ids": ["M03"], "shots": "AB"},
	"M20": {"ids": ["M20"], "shots": "AB"},
	"M24": {"ids": ["M24"], "shots": "AB"},
	"M25": {"ids": ["M25"], "shots": "AB"},
	"M26": {"ids": ["M26"], "shots": "ABC"},
	"T5": {"ids": ["T5"], "shots": "AB"},
}
const FACE_IDS := ["M03", "M15", "M24", "M25", "T1", "T5", "T6"]

var out_dir := ""
var tag := "shot"
var mode := "model"
var names: Array = []
var m: Node3D
var free_cam: Camera3D
var cam: Camera3D

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("user://capture-mutation-looks")
	tag = args[1] if args.size() > 1 else "shot"
	mode = args[2] if args.size() > 2 else "model"
	names = Array(args[3].split(",")) if args.size() > 3 else SETS.keys()
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(960, 540)
	if mode == "game":
		run_game.call_deferred()
	else:
		run_model.call_deferred()

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
	await process_frame

func save(label: String, rect: Rect2i = Rect2i(), factor: int = 1) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if rect.size.x > 0:
		image = image.get_region(rect)
		image.resize(rect.size.x * factor, rect.size.y * factor, Image.INTERPOLATE_NEAREST)
	var path := out_dir.path_join("%s_%s.png" % [tag, label])
	image.save_png(path)
	print("CAPTURE ", path)

# --- model mode -------------------------------------------------------------

func run_model() -> void:
	var stage := Node3D.new()
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
	var b := FPMirrorBody.new()
	stage.add_child(b)
	await frames(4)
	for nm in names:
		if not SETS.has(nm):
			continue
		var spec: Dictionary = SETS[nm]
		if spec.has("hair"):
			var h: Array = spec["hair"]
			var arm: Node3D = load("res://main/art/fp_arm_hair.tscn").instantiate()
			arm.position = Vector3(3, 0, 0)
			stage.add_child(arm)
			arm.call("set_hair", int(h[0]), {"core": int(h[1]), "mantle": int(h[2]), "surface": int(h[3])})
			cam.global_position = arm.position + Vector3(0.12, 0.16, -0.1)
			cam.look_at(arm.position + Vector3(0, 0.0, -0.17), Vector3.UP)
			await save("model_%s_arm" % nm)
			arm.queue_free()
			# a set with mutations as well (M23_hair240) also gets the body views
			if not spec.has("ids"):
				continue
		var ids: Array = spec.get("ids", [])
		b.apply(ids, int(spec.get("bumps", 0)))
		await frames(2)
		var views := {"front": 0.0, "left45": 45.0, "side": 90.0}
		for v in views:
			var a := deg_to_rad(views[v])
			var dir := Vector3(sin(a), 0, cos(a))
			cam.global_position = Vector3(0, 1.22, 0) + dir * 1.5
			cam.look_at(Vector3(0, 1.2, 0), Vector3.UP)
			await save("model_%s_%s" % [nm, v])
		var face := false
		for id in ids:
			face = face or id in FACE_IDS
		if face:
			cam.global_position = Vector3(0.12, 1.6, 0.62)
			cam.look_at(Vector3(0, 1.56, 0), Vector3.UP)
			await save("model_%s_face" % nm)
		if int(spec.get("bumps", 0)) > 0:
			cam.global_position = Vector3(0.25, 1.1, 0.5)
			cam.look_at(Vector3(0.05, 1.05, 0.1), Vector3.UP)
			await save("model_%s_belly" % nm)
	quit(0)

# --- game mode --------------------------------------------------------------

func aim(point: Vector3) -> void:
	var d: Vector3 = (point - m.player.camera.global_position).normalized()
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = asin(d.y)
	m.player.rotation.y = m.player._yaw
	m.player.camera_pivot.rotation.x = m.player._pitch

func pitch(p: float) -> void:
	m.player._pitch = p
	m.player.camera_pivot.rotation.x = p

func free_view(from: Vector3, at: Vector3) -> void:
	if free_cam == null:
		free_cam = Camera3D.new()
		free_cam.name = "CaptureCam"
		free_cam.fov = 60.0
		# the world sees what a bystander would: never the mirror-only body
		free_cam.cull_mask = 0xFFFFF & ~FPMirrorReflection.MIRROR_BODY_LAYER & ~FPMirror.HOLO_LAYER
		m.add_child(free_cam)
	free_cam.global_position = from
	free_cam.look_at(at, Vector3.UP)
	free_cam.current = true

func eye_view() -> void:
	if free_cam != null:
		free_cam.current = false
	m.player.camera.current = true

func wear(spec: Dictionary) -> void:
	var prog = m.progression
	var tree = prog.mutation_tree
	tree._purchased.clear()
	prog.tumor_mutations.clear()
	for id in spec.get("ids", []):
		if String(id).begins_with("T"):
			prog.tumor_mutations.append(String(id))
		else:
			tree._purchased[String(id)] = true
	prog.tumors.tumor_points = int(spec.get("bumps", 0))
	var hair: Array = spec.get("hair", [0, 0, 0, 0])
	var pools := ["common", "core", "mantle", "surface"]
	for i in range(4):
		tree.add_points(pools[i], int(hair[i]) - int(tree.points(pools[i])))

func run_game() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_mutation_looks.json"
	m.save_path = SAVE
	root.add_child(m)
	await frames(6)
	m.finish_opening()
	m.player.mouse_look_enabled = false
	m.progression.has_belt = true
	var surface: Node3D = m.restroom.mirror_art.call("reflection_surface")
	var glass: Vector3 = surface.to_global(Vector3(0, 1.78, 0.016))
	var n: Vector3 = surface.global_transform.basis.z.normalized()
	var stand := glass + n * 1.15
	stand.y = 0.95
	var side: Vector3 = n.cross(Vector3.UP).normalized()
	for nm in names:
		if not SETS.has(nm):
			continue
		var spec: Dictionary = SETS[nm]
		wear(spec)
		m.player.global_position = stand
		await frames(8)
		for s in String(spec.get("shots", "")):
			match s:
				"A":
					aim(glass + Vector3(0, -0.32, 0))
					await save("%s_A" % nm, Rect2i(400, 200, 160, 180), 4)
				"B":
					aim(stand - n * 1.0)
					m.open_mirror()
					await frames(40)
					await save("%s_B" % nm)
					m.mirror.close()
					await frames(10)
				"H":
					aim(stand - n * 1.0)
					m.open_mirror()
					await frames(40)
					await save("%s_H" % nm, Rect2i(90, 400, 640, 140), 2)
					m.mirror.close()
					await frames(10)
				"C":
					aim(stand + Vector3(0, 0.55, 0) - n * 1.0)
					await save("%s_C" % nm)
				"D":
					aim(stand + Vector3(0, 0.55, 0) - n * 1.0)
					pitch(-1.25)
					await save("%s_D" % nm)
				"E":
					aim(stand + Vector3(0, 0.55, 0) - n * 1.0)
					free_view(stand + side * 0.9 + n * 0.25 + Vector3(0, -0.25, 0), stand + Vector3(0, -0.5, 0))
					await save("%s_E" % nm)
					eye_view()
				"S":
					m.player.global_position = Vector3(1.0, 0.95, 0.6)
					await frames(4)
					aim(Vector3(1.6, 0.0, 1.0))
					free_view(Vector3(-1.6, 2.3, -1.2), Vector3(1.2, 0.3, 0.8))
					await save("%s_S" % nm)
					eye_view()
	m.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
