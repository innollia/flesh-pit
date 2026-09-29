class_name FDKBarrier
extends Node3D

## Consumable route-control item (docs/spec/06-tools.md): a deployable industrial
## tension barrier that automatically expands across the local tunnel
## cross-section and holds back moving/regenerating tissue. Surrounding
## biome tissue keeps moving, so stress accumulates against the barrier
## while it stands. It has 4 durability states (100%, ~67%, ~33%, broken) in
## 33%-step visual damage transitions. When it finally breaks, the stored
## deformation is released in one sudden elastic "boing" rather than a quiet
## fade -- see `signal broke`.
##
## Placement: automatic cross-section fit is a game-side concern (this node
## only needs a `radius` capturing "how wide a tunnel it can block" and a
## `position`); the frontend/game decides where and how large to place it.
## No visuals are drawn here -- this is backend state + signals only, per the
## kit rule that appearance is frontend scope (see STATUS.md handoff).
##
## Frontend contract (signals a barrier-mesh/animation layer should use):
##   stress_changed(ratio: float)      -- 0..1 accumulated load, drives bend
##   damage_step_changed(step: int)    -- 0=intact,1,2,3=broken (33% steps)
##   broke(release_ratio: float)       -- stored deformation released ("boing")

signal stress_changed(ratio: float)
signal damage_step_changed(step: int)
signal broke(release_ratio: float)

## Regeneration pressure (units/sec-equivalent) required to fully break an
## intact barrier from zero stress. Tunable per-instance.
@export var break_threshold: float = 12.0
## How much stress dissipates per second on its own (a barrier under light,
## intermittent pressure can survive indefinitely).
@export var stress_decay: float = 0.15
## Radius (world units) of tunnel cross-section this barrier can block.
@export var radius: float = 0.9

var stress: float = 0.0
var broken: bool = false
var _last_step: int = 0

## Call every frame (or on a fixed tick) with the regeneration pressure the
## field wanted to apply against this barrier's position this tick (e.g. the
## density delta that would have regenerated had the barrier not blocked
## it). Positive values only; the barrier absorbs it instead of the tissue.
func absorb_pressure(amount: float, delta: float) -> void:
	if broken:
		return
	stress = maxf(0.0, stress - stress_decay * delta)
	stress += amount
	var ratio := stress_ratio()
	stress_changed.emit(ratio)
	var step := damage_step()
	if step != _last_step:
		_last_step = step
		damage_step_changed.emit(step)
	if stress >= break_threshold:
		_break()

## 0..1, how loaded the barrier currently is.
func stress_ratio() -> float:
	if break_threshold <= 0.0:
		return 1.0
	return clampf(stress / break_threshold, 0.0, 1.0)

## 0 intact, 1 ~67% left, 2 ~33% left, 3 broken -- 4 states in 33% steps.
func damage_step() -> int:
	if broken:
		return 3
	var r := stress_ratio()
	if r >= 0.667:
		return 2
	if r >= 0.333:
		return 1
	return 0

func is_broken() -> bool:
	return broken

func _break() -> void:
	broken = true
	var release_ratio := stress_ratio()
	damage_step_changed.emit(3)
	broke.emit(release_ratio)
	stress = 0.0

## Serializes just enough to restore stress/broken state after a save/load
## (the game owns which barriers exist and where; see FDKBarrier.deserialize
## for the counterpart).
func serialize() -> Dictionary:
	return {
		"version": 1,
		"position": [position.x, position.y, position.z],
		"radius": radius,
		"break_threshold": break_threshold,
		"stress": stress,
		"broken": broken,
	}

func deserialize(data: Dictionary) -> void:
	var pos: Array = data.get("position", [0.0, 0.0, 0.0])
	position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	radius = float(data.get("radius", radius))
	break_threshold = float(data.get("break_threshold", break_threshold))
	stress = float(data.get("stress", 0.0))
	broken = bool(data.get("broken", false))
	_last_step = damage_step()
