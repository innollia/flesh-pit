extends SceneTree

## Drives main.tscn for a handful of frames at each of 4 staged camera
## positions, saving a PNG per stage per resolution. Needs a real window +
## viewport to render (not --headless). Run with:
##   Godot_console.exe --path <project> --script tools/capture.gd
## Auto-quits once all captures are written.

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const STAGE_NAMES := ["01_restroom", "02_flesh_wall", "03_dug_tunnel", "04_regrowing_tunnel"]
const FRAMES_TO_SETTLE := 15

var _stage_index: int = 0
var _frame_in_stage: int = 0
var _main: Node3D
var _capturing: bool = false

func _init() -> void:
	var packed: PackedScene = load("res://main/scenes/main.tscn")
	_main = packed.instantiate()
	get_root().add_child(_main)
	get_root().size = RESOLUTIONS[0]

func _process(_delta: float) -> bool:
	if _capturing:
		return false
	if _stage_index >= STAGE_NAMES.size():
		return false

	_apply_stage(_stage_index)
	_frame_in_stage += 1
	if _frame_in_stage < FRAMES_TO_SETTLE:
		return false

	_capturing = true
	_do_capture(_stage_index)
	_stage_index += 1
	_frame_in_stage = 0
	_capturing = false

	if _stage_index >= STAGE_NAMES.size():
		print("=== capture complete ===")
		quit(0)
		return true
	return false

func _apply_stage(index: int) -> void:
	var player = _main.player
	var terrain = _main.terrain
	match index:
		0: # inside the clean white restroom, looking toward the door
			player.global_position = Vector3(0, 1, 0)
			player.rotation.y = 0.0
		1: # right up against the flesh wall beyond the door, before digging
			player.global_position = Vector3(0, 1, 2.0)
			player.rotation.y = 0.0
		2: # a dug tunnel: carve a short straight tunnel forward, stand inside it
			for i in range(6):
				terrain.dig_at(Vector3(0, 1, 3.0 + i * 0.5), 1.0)
			player.global_position = Vector3(0, 1, 4.0)
			player.rotation.y = 0.0
		3: # regenerating/narrowing tunnel: dig, then let regen run with the
			# player marked "away" so nothing protects the tunnel from healing
			for i in range(6):
				terrain.dig_at(Vector3(0, 1, 3.0 + i * 0.5), 1.0)
			for i in range(200):
				terrain.regenerate_all(0.1, Vector3(0, 1, 20.0), 1.0)
			player.global_position = Vector3(0, 1, 4.0)
			player.rotation.y = 0.0

func _do_capture(index: int) -> void:
	var stage_name: String = STAGE_NAMES[index]
	for res in RESOLUTIONS:
		get_root().size = res
		# Force several real render passes so the new size and the moved
		# camera are actually reflected in the viewport texture before we
		# read it back -- a single implicit frame after a resize was not
		# enough and produced an all-transparent image.
		for i in range(5):
			RenderingServer.force_draw()
		var img := get_root().get_texture().get_image()
		var dir_path := "res://captures/%dx%d" % [res.x, res.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
		var path := "%s/%s.png" % [dir_path, stage_name]
		var err := img.save_png(path)
		if err != OK:
			printerr("FAIL saving capture: %s (err=%d)" % [path, err])
		else:
			print("OK captured %s" % ProjectSettings.globalize_path(path))
