extends SceneTree

## The compass hangs on the waist (decision 0009) and is only ever in the
## hand after the player takes it from there (2026-11-09 user: "시작부터
## 나침반 들고있는 문제"). Empty hands, the compass on the waist and no compass
## in the left palm: from the very first frame of Main, at a new game, after
## loading a save where it was not held, after death and wake, and after the
## ending's return. A save where it was held brings it back in the left hand
## only. Isolated save and key files.

var m: Node3D
var passed := 0
var failed := 0
const SAVE := "user://compass-start-test.bin"

func _init() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames(c: int) -> void:
	for i in range(c):
		await physics_frame
		await process_frame

func fresh() -> void:
	if is_instance_valid(m):
		m.queue_free()
		await frames(2)
	m = load("res://main/scenes/main.tscn").instantiate()
	m.user_keybinds_path = "user://keybinds_test_compass_start.json"
	m.save_path = SAVE
	root.add_child(m)
	m.save_path = SAVE

func empty_hands(where: String) -> void:
	var p: FPProgression = m.progression
	check(p.hands.left == "" and p.hands.right == "", "%s: both hands empty (left '%s', right '%s')" % [where, p.hands.left, p.hands.right])
	check(p.equipped() != "compass", "%s: the compass is not the active tool" % where)
	check(not m.art_hookup.hand_compass.visible, "%s: no compass in the left palm" % where)
	check(m.art_hookup.waist_compass.visible, "%s: the compass hangs on the waist" % where)
	check(float(m.hand_motions.get("_cup_wl")) <= 0.0, "%s: the left hand is not cupped palm up" % where)

func run() -> void:
	# the first frame Main exists, before any of its per-frame syncs ran
	await fresh()
	check(not m.art_hookup.hand_compass.visible, "Main just built: no compass in the left palm before the first frame")
	check(m.progression.hands.left == "", "Main just built: left hand empty")
	await frames(6)
	# new game through the opening
	m.new_game()
	await frames(3)
	await empty_hands("new game, seated")
	m.finish_opening()
	await frames(10)
	await empty_hands("new game, standing")
	# take the compass, put it back, save: the load comes back empty-handed
	check(m.equip_hand("compass", FDKToolKit.Hand.LEFT), "the compass can be taken into the left hand")
	await frames(4)
	check(m.art_hookup.hand_compass.visible and not m.art_hookup.waist_compass.visible, "held: in the palm, gone from the waist")
	check(not m.equip_hand("compass", FDKToolKit.Hand.RIGHT), "the right hand does not take the compass")
	m.equip_hand("", FDKToolKit.Hand.LEFT)
	await frames(4)
	check(m.save_to_disk(), "save written")
	await fresh()
	await frames(6)
	check(m.continue_game(), "continue loads the save")
	await frames(6)
	await empty_hands("loaded (not held when saved)")
	m.finish_opening()
	await frames(6)
	await empty_hands("loaded, standing")
	# a save that holds it brings it back in the left hand, nowhere else
	m.equip_hand("compass", FDKToolKit.Hand.LEFT)
	await frames(2)
	m.save_to_disk()
	await fresh()
	await frames(6)
	m.continue_game()
	m.finish_opening()
	await frames(6)
	check(m.progression.hands.left == "compass" and m.progression.hands.right == "", "loaded (held when saved): back in the left hand")
	# a save whose right hand somehow says compass (or a legacy save whose
	# last tool was the compass) does not put it in a hand on load
	var d: Dictionary = m.progression.serialize()
	d["hands"] = {"left": "", "right": "compass"}
	m.progression.deserialize(d)
	check(m.progression.hands.right == "" and m.progression.hands.left == "", "a right-hand compass in the save is dropped back to the waist")
	d.erase("hands")
	d["tools"] = m.progression.tools.serialize()
	d["tools"]["equipped"] = "compass"
	m.progression.deserialize(d)
	check(m.progression.hands.left == "" and m.progression.hands.right == "", "a legacy save (no hands) does not equip the compass from its last tool")
	await frames(40) # the palm turns back down over a few frames
	await empty_hands("after sanitized loads")
	# death and wake: whatever was held drops, the compass back on the waist
	m.equip_hand("compass", FDKToolKit.Hand.LEFT)
	await frames(2)
	m.die("test")
	await frames(20)
	await empty_hands("after death and wake")
	# the ending's return to the restroom
	m.reach_ending()
	await frames(4)
	m.save_to_disk()
	await fresh()
	await frames(6)
	m.continue_game()
	m.finish_opening()
	await frames(6)
	await empty_hands("after the ending's return")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
