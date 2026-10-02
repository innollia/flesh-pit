class_name FPTitleWall
extends Control

## The menu is ink on a real FDK terrain chunk surface, using the same
## low-poly mesher, flesh texture, material and living motion as the game.
var terrain: FDKTerrainField
var labels: SubViewport
var view: SubViewport
var display: TextureRect
var surface: MeshInstance3D
var camera: Camera3D
var mat: ShaderMaterial
var menu_root: Control
var phase := 0.0
var _mouse_inside := false
var extent := Vector2(3.55556, 2.0)

func setup(root: Control) -> void:
	menu_root = root
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels = SubViewport.new()
	labels.transparent_bg = true
	labels.disable_3d = true
	labels.size = Vector2i(1280, 720)
	add_child(labels)
	root.reparent(labels)
	view = SubViewport.new()
	view.own_world_3d = true
	view.size = labels.size
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position.z = 3.0
	view.add_child(camera)
	camera.current = true
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.02, 0.03)
	view.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -25, 0)
	light.light_color = Color(1.0, 0.77, 0.7)
	light.light_energy = 0.6
	view.add_child(light)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.36, 0.34)
	env.environment.ambient_light_energy = 0.35
	terrain = FDKTerrainField.new()
	terrain.config = FDKTerrainConfig.new()
	terrain.config.cell_size = 0.40
	terrain.config.facet_jitter = 0.22
	terrain.density_sampler = _density
	view.add_child(terrain)
	# The ink is sampled in undeformed world XY, so every glyph lies on
	# the flesh triangles and bends/moves with them, never a floating quad.
	var shader := Shader.new()
	var source := FileAccess.get_file_as_string("res://addons/flesh_dig_kit/common/fdk_ps1_material.gdshader")
	source = source.replace("render_mode cull_back,", "render_mode cull_disabled,")
	source = source.replace("varying float vfog;", "uniform sampler2D menu_tex : source_color, filter_linear;\nuniform vec2 menu_extent;\nvarying float vfog;")
	source = source.replace("ROUGHNESS =", "vec2 ink_uv = vec2(vwpos.x / menu_extent.x + 0.5, 0.5 - vwpos.y / menu_extent.y);\n    vec4 ink = texture(menu_tex, ink_uv);\n    if (any(lessThan(ink_uv, vec2(0))) || any(greaterThan(ink_uv, vec2(1)))) { ink.a = 0.0; }\n    ALBEDO = mix(ALBEDO, ink.rgb, ink.a);\n    ROUGHNESS =")
	source = source.replace("EMISSION = tex * rim * 0.12 * wetness;", "EMISSION = tex * rim * 0.12 * wetness + ink.rgb * ink.a * 0.45;")
	shader.code = source
	mat = FDKChunk.terrain_material(0).duplicate() as ShaderMaterial
	mat.shader = shader
	mat.set_shader_parameter("menu_tex", labels.get_texture())
	mat.set_shader_parameter("menu_extent", extent)
	mat.set_shader_parameter("fog_distance", 100000.0)
	mat.set_shader_parameter("fit_room_seams", false)
	for x in [-1, 0]:
		for y in [-1, 0]:
			for z in [-1, 0]:
				var chunk := terrain.get_or_create_chunk(Vector3i(x, y, z))
				chunk.remesh()
				chunk._mesh_instance.material_override = mat
				if surface == null:
					surface = chunk._mesh_instance
	display = TextureRect.new()
	display.texture = view.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)

func _process(delta: float) -> void:
	var title := get_parent() as FPTitleScreen
	visible = menu_root.visible and (title.settings_menu == null or not title.settings_menu.is_open())
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	labels.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	if not visible:
		if _mouse_inside:
			labels.notify_mouse_exited()
			_mouse_inside = false
		return
	phase += delta
	mat.set_shader_parameter("motion_clock", phase)
	if Vector2(labels.size) != menu_root.size:
		labels.size = Vector2i(menu_root.size)
		view.size = labels.size
		extent.x = 2.0 * menu_root.size.x / menu_root.size.y
		mat.set_shader_parameter("menu_extent", extent)
	display.size = menu_root.size

func _density(p: Vector3) -> float:
	# A bulky wall of actual tissue with broad bulges and smaller folds.
	var face := 0.27 * sin(p.x * 1.8) * cos(p.y * 2.0) + 0.10 * sin(p.x * 4.0 + p.y * 3.0)
	return clampf(0.5 + (face - p.z) * 2.0, 0.0, 1.0)

func displacement(p: Vector2) -> Vector2:
	return Vector2(0.055 * sin(p.y * 4.0 + phase * 0.8) + 0.035 * sin(p.x * 3.0 + phase * 0.4), 0.05 * sin(p.x * 4.0 + phase * 0.7))

func screen_to_menu(point: Vector2) -> Vector2:
	var target := Vector2(point.x / menu_root.size.x - 0.5, 0.5 - point.y / menu_root.size.y) * extent
	var source := target
	for i in range(8):
		source = target - displacement(source)
	return Vector2(source.x / extent.x + 0.5, 0.5 - source.y / extent.y) * menu_root.size

func _input(event: InputEvent) -> void:
	if not menu_root.visible:
		return
	var title := get_parent() as FPTitleScreen
	if title.settings_menu != null and (title.settings_menu.is_open() or title.settings_menu.just_closed()):
		return
	if event.is_action_pressed("ui_cancel") and title.is_confirming():
		title._show_confirm(false)
		get_viewport().set_input_as_handled()
		return
	var forwarded := event.duplicate() as InputEvent
	if forwarded is InputEventMouse:
		if not _mouse_inside:
			labels.notify_mouse_entered()
			_mouse_inside = true
		var mouse := forwarded as InputEventMouse
		mouse.position = screen_to_menu(get_global_transform_with_canvas().affine_inverse() * mouse.position)
		mouse.global_position = mouse.position
	labels.push_input(forwarded, true)
	if event is InputEventMouseButton or event is InputEventKey or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
