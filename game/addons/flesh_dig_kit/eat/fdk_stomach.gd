class_name FDKStomach
extends Node

## Tracks how full the player is and how much that slows down chewing.
## Pure state/logic node with no visuals; a game wires its own UI to the
## signals below.

signal fill_changed(fill: float, capacity: float, overfill_capacity: float)
signal vomited(amount: float)

@export var config: FDKStomachConfig = FDKStomachConfig.new()

var fill: float = 0.0

func add_flesh(amount: float) -> void:
	fill += amount
	fill_changed.emit(fill, config.capacity, config.overfill_capacity)

## Empties the stomach (e.g. vomiting in the restroom). Returns the amount
## that was emptied.
func vomit() -> float:
	var amount := fill
	fill = 0.0
	fill_changed.emit(fill, config.capacity, config.overfill_capacity)
	vomited.emit(amount)
	return amount

## Frontend contract: fill_ratio() and overfill_ratio() are the two numbers
## a stomach-gauge visualization needs (see STATUS.md's frontend handoff
## section for the full list). No backend code assumes any particular
## gauge presentation.

## 0.0 empty, 1.0 exactly at capacity, >1.0 while overfull (uncapped, so a
## gauge can keep growing past the "comfortable" mark instead of clamping).
func fill_ratio() -> float:
	if config.capacity <= 0.0:
		return 0.0
	return fill / config.capacity

## 0.0 at/under capacity, 1.0 at capacity + overfill_capacity, clamped.
func overfill_ratio() -> float:
	if config.overfill_capacity <= 0.0:
		return 0.0 if fill <= config.capacity else 1.0
	var over := fill - config.capacity
	return clampf(over / config.overfill_capacity, 0.0, 1.0)

## Multiplier applied to chew time: 1.0 when comfortable, rising toward
## overfill_chew_multiplier as the player gorges past capacity.
func chew_time_multiplier() -> float:
	return lerpf(1.0, config.overfill_chew_multiplier, overfill_ratio())

func is_overfull() -> bool:
	return fill > config.capacity

func serialize() -> Dictionary:
	return {"version": 1, "fill": fill}

func deserialize(data: Dictionary) -> void:
	fill = float(data.get("fill", 0.0))
	fill_changed.emit(fill, config.capacity, config.overfill_capacity)
