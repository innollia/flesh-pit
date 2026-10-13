extends SceneTree

## FPPlayLog: the timed reward-event CSV for docs/spec/09-reward-scale.md 10.2
## (tools/economy/reward_scale.py --log). Writes only its own file.

var m: Node3D
var passed := 0
var failed := 0
var path := ""

func _init() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	root.add_child(m)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func run() -> void:
	for i in range(4):
		await process_frame
	m.finish_opening()
	m.set_process(false)
	m.player.set_physics_process(false)
	path = OS.get_user_data_dir().path_join("play-log-test.csv")
	var log := FPPlayLog.new()
	m.add_child(log)
	check(log.setup(m, path), "the log opens its own CSV")
	# out in the flesh: digging out (B), a real tear, hair growing
	m.player.global_position = Vector3(0, 1, 4)
	log._process(1.1)
	m.chewer.last_units = 4.0
	m.chewer.cell_torn.emit(Vector3(0, 1, 5))
	m.progression.on_flesh_eaten(0, 150.0) # 3 core hairs and 1 common hair
	log._process(0.1)
	# walking back toward the restroom with flesh inside: the return (C)
	m.stomach.add_flesh(20.0)
	m.player.global_position = Vector3(0, 1, 2)
	log._process(1.1)
	# home again, settled at the lever
	m.player.global_position = Vector3(0, 1, 0)
	log._process(1.1)
	m.flushed.emit(8, 0)
	log._process(1.1)
	log._exit_tree()
	var lines := FileAccess.get_file_as_string(path).strip_edges().split("\n")
	check(lines[0] == FPPlayLog.COLS, "the header is the calculator's column list")
	var codes := []
	var phases := []
	for i in range(1, lines.size()):
		var c := lines[i].split(",")
		check(c.size() == 17, "every row has 17 columns (%d)" % c.size())
		codes.append(c[4])
		phases.append(c[1])
	check(codes.has("R-TEAR") and codes.has("R-HAIR-B") and codes.has("R-HAIR-C") and codes.has("R-SETL"), "tear, hair and settlement rows are written (%s)" % [codes])
	check(phases.has("B") and phases.has("C") and phases.has("A"), "out, back and home phases are recorded (%s)" % [phases])
	var tear_row: PackedStringArray = lines[codes.find("R-TEAR") + 1].split(",")
	check(tear_row[3] == "S" and is_equal_approx(float(tear_row[5]), 4.0), "a tear is a sensory event with its real flesh units")
	DirAccess.remove_absolute(path)
	print("--- play log: %d passed, %d failed ---" % [passed, failed])
	m.queue_free()
	quit(1 if failed else 0)
