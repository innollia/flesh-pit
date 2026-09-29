class_name FDKToolKit
extends RefCounted

## Minimal tool ownership/equip data structure (design-core 4, "no inventory
## UI"; this is pure data, no visuals). One-handed vs two-handed rule:
## while carrying a flesh pile (game-side carry_mode / carried_flesh > 0),
## only one-handed tools may be equipped -- callers should check
## is_two_handed(equipped) against their own carry state before allowing
## an equip, and force-unequip a two-handed tool the moment carry starts.
##
## A game defines the tool ids it uses; this class only tracks
## ownership + which single tool is currently equipped (bare hands = "").

enum Hand { LEFT, RIGHT }

## id -> true (owned)
var _owned: Dictionary = {}
## id -> Hand (which hand a purchased tool occupies; game-side convention,
## e.g. blender always left, knife/saw/barrier/spray always right)
var _hand: Dictionary = {}
## id -> true (two-handed; empty/false = one-handed)
var _two_handed: Dictionary = {}
var equipped: String = "" ## "" = bare hands

func define_tool(id: String, hand: Hand, two_handed: bool = false) -> void:
	_hand[id] = hand
	_two_handed[id] = two_handed

func grant(id: String) -> void:
	_owned[id] = true

func owns(id: String) -> bool:
	return _owned.get(id, false)

func is_two_handed(id: String) -> bool:
	return _two_handed.get(id, false)

func hand_of(id: String) -> Hand:
	return _hand.get(id, Hand.RIGHT)

## Returns false (and leaves `equipped` unchanged) when the tool is not
## owned, or is two-handed while `carrying` is true.
func try_equip(id: String, carrying: bool) -> bool:
	if id != "" and not owns(id):
		return false
	if id != "" and carrying and is_two_handed(id):
		return false
	equipped = id
	return true

## Call when carry mode turns on: drops a two-handed tool back to bare
## hands, keeps a one-handed tool equipped.
func force_one_handed_if_needed(carrying: bool) -> void:
	if carrying and equipped != "" and is_two_handed(equipped):
		equipped = ""

func owned_ids() -> Array:
	return _owned.keys()

func serialize() -> Dictionary:
	return {
		"version": 1,
		"owned": _owned.keys(),
		"equipped": equipped,
	}

func deserialize(data: Dictionary) -> void:
	_owned.clear()
	for id in (data.get("owned", []) as Array):
		_owned[id] = true
	equipped = String(data.get("equipped", ""))
