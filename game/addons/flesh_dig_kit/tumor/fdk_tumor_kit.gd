class_name FDKTumorKit
extends RefCounted

## Tumor tradeoff (docs/spec/05-mutations.md): eat it for tumor-only mutation points,
## or keep it intact in the bag and throw it in the toilet for a large
## tooth payout + a codex entry. Pure data/logic; no visuals, no UI.
##
## The bag starts holding 1 tumor; capacity upgrades (bought at the vent,
## see FDKMutationTree-style flat purchases) raise `bag_capacity`.

var bag_capacity: int = 1
## kind id -> true (carried intact tumors currently in the bag, by kind)
var _carried: Array = [] ## Array[String] kind ids, one entry per tumor held
## kind id -> true (codex: ever thrown into the toilet intact)
var _codex: Dictionary = {}
## tumor-only mutation points, gained only by eating a tumor
var tumor_points: int = 0

func carried_count() -> int:
	return _carried.size()

func can_carry_more() -> bool:
	return _carried.size() < bag_capacity

## Eating a tumor: destroys it, grants tumor-only points, a large random
## bodily change is the game's job to roll and apply (docs/spec/05-mutations.md: "every
## tumor mutation is a large, obvious change ... added at random").
func eat(kind: String, points: int) -> void:
	tumor_points += points

## Picking it up intact: fails (returns false) if the bag is full.
func pick_up(kind: String) -> bool:
	if not can_carry_more():
		return false
	_carried.append(kind)
	return true

## Throwing an intact tumor into the toilet: removes it from the bag,
## marks the codex entry, returns the tooth payout for the caller to grant.
## Returns -1 if no tumor of that kind is carried.
func throw_in_toilet(kind: String, tooth_payout: int) -> int:
	var idx := _carried.find(kind)
	if idx < 0:
		return -1
	_carried.remove_at(idx)
	_codex[kind] = true
	return tooth_payout # payout is flat; the codex is tracked separately

func is_in_codex(kind: String) -> bool:
	return _codex.get(kind, false)

func codex_count() -> int:
	return _codex.size()

func raise_bag_capacity(by: int = 1) -> void:
	bag_capacity += by

func serialize() -> Dictionary:
	return {
		"version": 1,
		"bag_capacity": bag_capacity,
		"carried": _carried.duplicate(),
		"codex": _codex.keys(),
		"tumor_points": tumor_points,
	}

func deserialize(data: Dictionary) -> void:
	bag_capacity = int(data.get("bag_capacity", 1))
	_carried = (data.get("carried", []) as Array).duplicate()
	_codex.clear()
	for k in (data.get("codex", []) as Array):
		_codex[k] = true
	tumor_points = int(data.get("tumor_points", 0))
