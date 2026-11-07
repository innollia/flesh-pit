extends SceneTree

## Ending frame sequence, run WINDOWED with the movie writer (never headless):
##   godot_console --path game --resolution 960x540 --write-movie <dir>/f.png
##     --fixed-fps 10 --quit-after 90 --script res://tests/capture_ending.gd [-- main]
## Default: the FPEnding layer alone (no Main, no save touched).
## "main": the real Main with an isolated capture save, ending reached via
## reach_ending(), so the flesh world above the set is also in the scene.
## Every frame of the 8 s ending (white flash, overhead city, credits) is
## written; check all of them, not one.

var _ending: FPEnding
var _main: Node
var _frame := 0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "main":
		_main = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
		_main.user_keybinds_path = "user://keybinds_test_ending.json"
		_main.set("save_path", "user://capture-ending.bin")
		get_root().add_child(_main)
		return
	_ending = FPEnding.new()
	get_root().add_child(_ending)

func _process(delta: float) -> bool:
	_frame += 1
	if _main != null:
		if _frame == 3:
			_main.call("finish_opening")
			_main.call("reach_ending")
		return false
	if _frame == 1:
		_ending.start(1)
	elif _frame > 1:
		_ending.tick(delta)
	return false
