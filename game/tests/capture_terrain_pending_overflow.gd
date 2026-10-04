extends SceneTree
var field: FDKTerrainField
var camera: Camera3D
var failed := 0
var passed := 0
var destination := ProjectSettings.globalize_path("res://../.dryforge/evidence/pending-overflow-gpu")
func _init() -> void:
	run.call_deferred()
func capture(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var count := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			if c.r > 0.8 and c.b > 0.8 and c.g < 0.2:
				count += 1
	var saved := img.save_png(destination.path_join(label + ".png")) == OK
	if saved and count == 0:
		passed += 1
	else:
		failed += 1
	print(label, " background_pixels=", count, " saved=", saved)
func place_eye(point: Vector3, direction: Vector3) -> void:
	camera.global_position = field.constrain_eye(point, point - Vector3.UP * 0.7, camera.near)
	camera.look_at(camera.global_position + direction, Vector3.UP)
	camera.force_update_transform()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(destination)
	root.size = Vector2i(640, 360)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(1, 0, 1)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.8
	world.add_child(env)
	camera = Camera3D.new()
	camera.near = 0.02
	world.add_child(camera)
	camera.current = true
	field = FDKTerrainField.new()
	field.config.chunk_size = 4
	field.density_sampler = func(_p: Vector3): return 1.0
	world.add_child(field)
	field.set_process(false)
	field.generate_region(AABB(Vector3.ONE * -4, Vector3.ONE * 8))
	field.remesh_all()
	var eye := Vector3.ZERO
	for cx in range(-4, 5):
		eye = (Vector3(cx, 0, 0) + Vector3.ONE * 0.5) * field.config.cell_size
		field.dig_at(eye, 1.0)
		place_eye(eye, Vector3.RIGHT)
		await capture("tear_%d" % (cx + 4))
	field.remesh_budget_per_frame = 1
	for i in range(24):
		field._process(1.0 / 60.0)
		place_eye(eye, Vector3.RIGHT)
		await capture("publish_%d" % i)
	if field._surface_patch == null:
		passed += 1
	else:
		failed += 1
		print("FAIL: patch remained after all ordinary meshes published")
	print("%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
