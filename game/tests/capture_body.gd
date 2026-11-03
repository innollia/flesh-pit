extends SceneTree

## Visual evidence for the whole-body hair, whole-body blood and the body
## shadow (body group). Windowed run:
##   FP_CAPTURE_DIR=<folder> FP_CAPTURE_TAG=after \
##   godot_console --path game --resolution 960x540 --script res://tests/capture_body.gd
## Isolated save path; the player's normal save is never read or written.

var m: Node3D
var folder: String
var tag: String
var free_cam: Camera3D

func _init() -> void:
	folder = OS.get_environment("FP_CAPTURE_DIR")
	if folder == "":
		folder = ProjectSettings.globalize_path("user://capture-body")
	tag = OS.get_environment("FP_CAPTURE_TAG")
	if tag == "":
		tag = "shot"
	DirAccess.make_dir_recursive_absolute(folder)
	root.size = Vector2i(960, 540)
	run.call_deferred()

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
	await process_frame

func aim(point: Vector3) -> void:
	var d: Vector3 = (point - m.player.camera.global_position).normalized()
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = asin(d.y)
	m.player.rotation.y = m.player._yaw
	m.player.camera_pivot.rotation.x = m.player._pitch

func shot(label: String) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := folder.path_join("%s_%s.png" % [tag, label])
	image.save_png(path)
	print("CAPTURE ", path)

## Crop `rect` of the screen and blow it up (nearest) so small detail reads.
func zoom(label: String, rect: Rect2i, factor: int = 3) -> void:
	await frames(3)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image().get_region(rect)
	image.resize(rect.size.x * factor, rect.size.y * factor, Image.INTERPOLATE_NEAREST)
	var path := folder.path_join("%s_%s.png" % [tag, label])
	image.save_png(path)
	print("CAPTURE ", path)

func set_hair(common: int, core: int, mantle: int, surface: int) -> void:
	var tree = m.progression.mutation_tree
	for pool in ["common", "core", "mantle", "surface"]:
		var have: int = tree.points(pool)
		var want: int = {"common": common, "core": core, "mantle": mantle, "surface": surface}[pool]
		tree.add_points(pool, want - have)

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

func run() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.save_path = "user://capture-body.bin"
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
	for level in [[0, 0.0], [40, 0.0], [90, 0.0], [12, 0.35], [40, 0.7], [90, 1.0]]:
		var hairs: int = level[0]
		set_hair(hairs / 3, hairs / 6, hairs / 6, hairs - hairs / 3 - 2 * (hairs / 6))
		m.hand_blood = level[1]
		m.player.global_position = stand
		await frames(4)
		# mirror: the reflected body
		aim(glass + Vector3(0, -0.32, 0))
		await shot("mirror_h%02d_b%03d" % [hairs, int(level[1] * 100)])
		# the reflected body blown up (the glass is a 128x192 texture)
		await zoom("mirrorzoom_h%02d_b%03d" % [hairs, int(level[1] * 100)], Rect2i(400, 200, 160, 180), 4)
		# first person: hands held out (both forearms)
		aim(stand + Vector3(0, 0.55, 0) - n * 1.0)
		await shot("hands_h%02d_b%03d" % [hairs, int(level[1] * 100)])
		# first person: looking down at the belly
		m.player._pitch = -1.25
		m.player.camera_pivot.rotation.x = -1.25
		await shot("belly_h%02d_b%03d" % [hairs, int(level[1] * 100)])
		# straight down past the belly at the first-person legs
		m.player._pitch = -1.52
		m.player.camera_pivot.rotation.x = -1.52
		await shot("legs_h%02d_b%03d" % [hairs, int(level[1] * 100)])
		# a bystander beside the player sees the first-person legs and belly
		var side: Vector3 = n.cross(Vector3.UP).normalized()
		free_view(stand + side * 0.9 + n * 0.25 + Vector3(0, -0.25, 0), stand + Vector3(0, -0.5, 0))
		await shot("legsfree_h%02d_b%03d" % [hairs, int(level[1] * 100)])
		eye_view()
		if hairs == 90 and level[1] > 0.5:
			aim(stand - n * 1.0)
			m.open_mirror()
			await frames(40)
			await shot("tabdoll_h%02d_b%03d" % [hairs, int(level[1] * 100)])
			m.mirror.close()
			await frames(10)
	# shadow under the restroom ceiling light: eye view down at the floor
	m.player.global_position = Vector3(1.0, 0.95, 0.6)
	await frames(4)
	aim(Vector3(1.6, 0.0, 1.0))
	await shot("shadow_eye_room")
	m.player._pitch = -1.45
	m.player.camera_pivot.rotation.x = -1.45
	await shot("shadow_eye_down")
	# bystander view of the same spot (player body is not rendered for the
	# camera, only its shadow; the first-person waist/hands still are)
	free_view(Vector3(-1.6, 2.3, -1.2), Vector3(1.2, 0.3, 0.8))
	await shot("shadow_free_room")
	# crouched
	m.player.set("_is_crouching", true)
	await frames(8)
	await shot("shadow_free_crouch")
	m.player.set("_is_crouching", false)
	eye_view()
	eye_view()
	m.queue_free()
	await process_frame
	quit(0)
