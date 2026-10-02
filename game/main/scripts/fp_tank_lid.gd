class_name FPTankLid
extends Node

## The loose ceramic lid has one owner: the tank, a hand, or the floor.
var main: Node3D
var lid: Node3D
var held := false
var on_tank := true
var _home: Transform3D

func setup(m: Node3D) -> void:
	main = m
	lid = m.restroom.tank_art.get("_lid")
	_home = lid.transform

func can_pick() -> bool:
	return not held and main.carried_flesh <= 0.0 and not main.progression.tumor_in_hand() and main.progression.hands.right == ""

func aimed() -> bool:
	return not held and main._interaction_aim(lid.global_position, 8.0, 1.25)

func pick() -> bool:
	if not can_pick():
		return false
	var from_tank := on_tank
	main.restroom.set_tank_open(true, true)
	lid.reparent(main.hands_rig.get_hand_root("right").get_node("Wrist"), false)
	lid.transform = Transform3D(Basis.IDENTITY, Vector3(0, -0.05, -0.14))
	lid.visible = true
	main._tag_hands_layer(lid, FPMirrorReflection.HANDS_ROOM_LAYER if main._hands_in_room else 1)
	held = true
	on_tank = false
	if from_tank:
		main.vent.notice("lid_open")
	return true

func drop() -> bool:
	if not held:
		return false
	var ray: Array = main.player.get_look_ray()
	var at: Vector3 = ray[0] + ray[1] * 0.7
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.25, at + Vector3.DOWN * 8.0)
	query.exclude = [main.player.get_rid()]
	var hit := main.get_world_3d().direct_space_state.intersect_ray(query)
	var landing: Vector3 = hit.position if not hit.is_empty() else main.player.global_position + Vector3.DOWN * (main.player.config.stand_height * 0.5)
	lid.reparent(self, false)
	lid.global_transform = Transform3D(Basis.IDENTITY, landing + Vector3.UP * 0.018)
	FPRestroom.tag_room_layer(lid) if main.restroom.contains(landing) else FPRestroom.tag_default_layer(lid)
	lid.visible = true
	held = false
	return true

func replace_on_tank() -> void:
	lid.reparent(main.restroom.tank_art, false)
	lid.transform = _home
	on_tank = true
	held = false
	lid.visible = true
	main.restroom.set_tank_open(false, true)
	FPRestroom.tag_room_layer(lid)

func serialize() -> Dictionary:
	return {"on_tank": on_tank, "held": held, "position": [lid.global_position.x, lid.global_position.y, lid.global_position.z]}

func deserialize(data: Dictionary) -> void:
	replace_on_tank()
	if bool(data.get("held", false)):
		pick()
	elif not bool(data.get("on_tank", true)):
		var p: Array = data.get("position", [0, 0.02, 0])
		main.restroom.set_tank_open(true, true)
		lid.reparent(self, false)
		lid.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		lid.visible = true
		on_tank = false
		FPRestroom.tag_room_layer(lid) if main.restroom.contains(lid.global_position) else FPRestroom.tag_default_layer(lid)
