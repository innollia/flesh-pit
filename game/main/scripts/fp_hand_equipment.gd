class_name FPHandEquipment
extends RefCounted

## Serializable hand slots. The existing tool kit's equipped field is the
## active action tool; these slots are the source of what is actually held.
const LEFT := FDKToolKit.Hand.LEFT
const RIGHT := FDKToolKit.Hand.RIGHT
var left := ""
var right := ""

func item(hand: int) -> String:
	return left if hand == LEFT else right

func holds(id: String) -> bool:
	return id != "" and id in [left, right]

func set_item(id: String, hand: int, two_handed: bool = false) -> void:
	if two_handed:
		left = id
		right = id
		return
	if holds("big_saw"):
		clear()
	# One physical item cannot occupy both hands. Its home slot is fixed.
	if id != "" and item(1 - hand) == id:
		if hand == LEFT:
			right = ""
		else:
			left = ""
	if hand == LEFT:
		left = id
	else:
		right = id

func clear() -> void:
	left = ""
	right = ""

func serialize() -> Dictionary:
	return {"left": left, "right": right}

func deserialize(data: Dictionary) -> void:
	left = str(data.get("left", ""))
	right = str(data.get("right", ""))
