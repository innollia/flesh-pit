class_name FPHandActions
extends RefCounted

var m: Node3D
var blocked := [false, false]
const ACTIONS := ["fdk_eat", "fp_pick"]

func _init(main: Node3D) -> void:
	m = main

func tick(delta: float) -> void:
	var chewing := false
	for hand in range(2):
		var action: String = ACTIONS[hand]
		if not Input.is_action_pressed(action):
			blocked[hand] = false
			continue
		if blocked[hand] or m.tank_lid.held or m.belt_swap.busy():
			continue
		if Input.is_action_just_pressed(action) and m.belt_swap.aimed_hook() >= 0:
			m.belt_swap.begin(hand)
			blocked[hand] = true
			continue
		var id: String = m.progression.activate_hand(hand)
		if Input.is_action_just_pressed(action):
			match id:
				"spray_cheap", "spray_deep": m.use_spray(id == "spray_deep")
				"blender": m.use_blender()
				"canary_feed": m.feed_canary()
				"barrier": m.place_barrier()
				"":
					if hand == FDKToolKit.Hand.RIGHT:
						m._pick()
		if id in ["", "knife", "big_saw"] and not chewing:
			if m.hands_rig.state in [FDKHandsRig.HandState.IDLE, FDKHandsRig.HandState.RELEASE]:
				m.hands_rig._lead = 1 - hand
			m._chew_step(delta)
			chewing = true
		m.progression.refresh_equipment()
	if not chewing:
		m.chewer.stop()
		m.terrain.set_press(Vector3.ZERO, Vector3.BACK, 0.0)

func charging() -> bool:
	for hand in range(2):
		if not blocked[hand] and m.progression.hands.item(hand) == "blender" and Input.is_action_pressed(ACTIONS[hand]):
			return true
	return false
