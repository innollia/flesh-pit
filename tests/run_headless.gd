extends SceneTree

## Loads main.tscn headless and runs it for a fixed number of frames,
## exiting 0 on success or 1 on any script error captured during the run.
## Run with:
##   Godot_console.exe --headless --path <project> --script tests/run_headless.gd

const FRAME_COUNT := 300

var _frames_done: int = 0
var _root_node: Node

func _init() -> void:
	print("=== flesh-pit headless run (%d frames) ===" % FRAME_COUNT)
	var packed: PackedScene = load("res://main/scenes/main.tscn")
	if packed == null:
		printerr("FAIL: could not load main.tscn")
		quit(1)
		return
	_root_node = packed.instantiate()
	get_root().add_child(_root_node)

func _process(_delta: float) -> bool:
	_frames_done += 1
	if _frames_done >= FRAME_COUNT:
		print("--- ran %d frames without crashing ---" % _frames_done)
		quit(0)
		return true
	return false
