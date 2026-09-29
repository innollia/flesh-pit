class_name FDKDeathDrop
extends Node3D

## On-death belongings drop (design-core 6). Holds the dropped inventory at
## the death location; the player can return and recover it. No severe
## penalty for failing to recover -- just the drop itself. Navigation only
## preserves the LAST KNOWN location (no live tracking, no marker update
## after the drop): if the surrounding tissue moves/regenerates and pushes
## the drop, the marker stays where the drop WAS placed, not where it drifts
## to (design-core 6: "if the item drifts, the player must search from that
## stale location").
##
## Presentation (marker mesh, on-screen indicator) is frontend scope; this
## node is state + a `carried_along` displacement behaviour only.

signal recovered(items: Dictionary)

## Items dropped on death (game-defined shape; opaque to this node).
var items: Dictionary = {}
## Where the marker points (stays fixed at the moment of death, per
## design-core 6 -- never updated after drop() is called).
var last_known_position: Vector3 = Vector3.ZERO
## The drop's actual current position, which CAN drift as tissue moves
## (design-core 6: "no fixed displacement cap").
var current_position: Vector3 = Vector3.ZERO
var active: bool = false

func drop(at: Vector3, dropped_items: Dictionary) -> void:
	items = dropped_items.duplicate(true)
	last_known_position = at
	current_position = at
	position = at
	active = true

## Call each tick with the world-space displacement tissue moved this frame
## at the drop's current position (e.g. a chunk regenerating/shifting under
## it). There is deliberately no cap -- design-core 6 allows unbounded
## drift -- and last_known_position is NOT updated, so the marker goes stale.
func carry_along(displacement: Vector3) -> void:
	if not active:
		return
	current_position += displacement
	position = current_position

## Player recovers the drop by reaching current_position (not the stale
## marker) within pickup_radius. Returns the items, or an empty Dictionary
## if out of range or already recovered.
func try_recover(player_pos: Vector3, pickup_radius: float = 1.2) -> Dictionary:
	if not active:
		return {}
	if player_pos.distance_to(current_position) > pickup_radius:
		return {}
	var out := items.duplicate(true)
	active = false
	recovered.emit(out)
	return out

func serialize() -> Dictionary:
	return {
		"version": 1,
		"active": active,
		"items": items.duplicate(true),
		"last_known_position": [last_known_position.x, last_known_position.y, last_known_position.z],
		"current_position": [current_position.x, current_position.y, current_position.z],
	}

func deserialize(data: Dictionary) -> void:
	active = bool(data.get("active", false))
	items = (data.get("items", {}) as Dictionary).duplicate(true)
	var lk: Array = data.get("last_known_position", [0.0, 0.0, 0.0])
	last_known_position = Vector3(float(lk[0]), float(lk[1]), float(lk[2]))
	var cp: Array = data.get("current_position", [0.0, 0.0, 0.0])
	current_position = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
	position = current_position
