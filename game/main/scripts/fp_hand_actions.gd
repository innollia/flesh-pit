class_name FPHandActions
extends RefCounted

## The two hand buttons (LMB/E left, RMB/R right). What a fresh press does
## is decided in one place, FPInteractions.plan/press (lid, belt hook, aimed
## target, held item, dig, in that order). A press that acted on the lid,
## the belt or a target keeps its hand blocked until released, so holding
## the button never turns into digging or a second action; so does a used
## item (a spent can leaves a bare hand that must not start digging), except
## the blender, which charges while held.

var m: Node3D
var blocked := [false, false]
## Process frame of the press each hand last acted on: one press, one action,
## however often tick runs in that frame.
var _press_frame := [-1, -1]
## A tick saw the button up since that press (a new press in the same frame
## is then a real second press, as tests drive it).
var _released := [true, true]
const ACTIONS := ["fdk_eat", "fp_pick"]
## FDKHandsRig counts its hands the other way round: 0 right, 1 left.
const RIG_LEFT := 1
const SOURCES := [FPInteractions.SOURCE_LEFT, FPInteractions.SOURCE_RIGHT]

func _init(main: Node3D) -> void:
	m = main

func tick(delta: float) -> void:
	var chewing := false
	# teeth on the right palm out of the restroom (Main.palm_blocked): that
	# hand does not dig, and the left alone leads every bite
	var palm: bool = m.palm_blocked()
	for rig in FPHandMotions.rigs_of(m):
		rig.set("lead_lock", RIG_LEFT if palm else -1)
	for hand in range(2):
		var action: String = ACTIONS[hand]
		# a quick click can press and release between two frames: it still
		# counts once (it used to be dropped when the frame came late)
		var down := Input.is_action_pressed(action)
		var fresh: bool = Input.is_action_just_pressed(action) and (_press_frame[hand] != Engine.get_process_frames() or (down and _released[hand]))
		if not down and not fresh:
			blocked[hand] = false
			_released[hand] = true
			continue
		if blocked[hand] or m.belt_swap.busy():
			continue
		# the item in this hand is the one a use or dig applies to
		# (the palm full of teeth is no tool: it leaves the active one alone)
		var id: String = "" if palm and hand == FDKToolKit.Hand.RIGHT else m.progression.activate_hand(hand)
		if fresh:
			_press_frame[hand] = Engine.get_process_frames()
			_released[hand] = false
			var verb := FPInteractions.press(m, SOURCES[hand])
			if FPInteractions.blocks_hand(verb):
				blocked[hand] = true
				m.progression.refresh_equipment()
				continue
		if m.tank_lid.held:
			continue
		if palm and hand == FDKToolKit.Hand.RIGHT:
			continue # also a button held down while walking out of the door
		if id in FPInteractions.DIG_ITEMS and not chewing:
			if m.hands_rig.state in [FDKHandsRig.HandState.IDLE, FDKHandsRig.HandState.RELEASE]:
				m.hands_rig._lead = 1 - hand
			m._chew_step(delta)
			chewing = true
		m.progression.refresh_equipment()
	if not chewing:
		m.chewer.stop()
		m.terrain.set_press(Vector3.ZERO, Vector3.BACK, 0.0)
		m.set_hand_reach(Vector3.INF)

func charging() -> bool:
	for hand in range(2):
		if not blocked[hand] and m.progression.hands.item(hand) == "blender" and Input.is_action_pressed(ACTIONS[hand]):
			return true
	return false
