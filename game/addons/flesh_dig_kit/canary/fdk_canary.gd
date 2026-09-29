class_name FDKCanary
extends Node

## Return-route + anomaly warning companion (design-core 7). Pure
## logic/signals -- no cage mesh, no chirp audio, no visuals (frontend
## scope; see STATUS.md handoff pattern). Presentation note for the
## frontend: the design calls for a small portable cage/carrier that can
## enter view when its reaction matters, not a permanently visible bird.
##
## Two independent checks, run each call to `update`:
##  1. Return-route danger: as the tunnel behind the player narrows/closes
##     from regeneration, the canary should warn with rising urgency. This
##     is approximated by sampling density along the path back toward a
##     reference point (the last safe position, e.g. the restroom) and
##     reporting how much of that path is now blocked.
##  2. Anomaly reaction: an odd cry / frightened reaction near unusual
##     nearby biome conditions (qualitative, not a precise detector).
##
## No exact direction is ever given for either signal (design-core 7).

signal route_warning(urgency: float) ## 0..1, rising as the return route narrows
signal anomaly_reaction(frightened: bool) ## qualitative "something's off" cue

@export var terrain: FDKTerrainField
## How many sample points along the straight line back are checked.
@export var route_samples: int = 8
## Fraction of the return line that must be blocked (density >= this) to
## count as "obstructed" at a sample point.
@export var block_density: float = 0.85
## Anomaly check radius (world units) and how much tissue variety within it
## counts as "unusual" (placeholder heuristic: distinct tissue ids nearby).
@export var anomaly_radius: float = 2.5

var last_route_urgency: float = 0.0
var is_frightened: bool = false

## Call once per tick with the player's current position and the reference
## point to check the return route against (usually the restroom door or
## the last rest point). Emits route_warning only when urgency changes
## meaningfully, so a game doesn't need its own dedupe.
func update(player_pos: Vector3, safe_pos: Vector3) -> void:
	if terrain == null:
		return
	var urgency := _sample_route_block(player_pos, safe_pos)
	if absf(urgency - last_route_urgency) > 0.02:
		last_route_urgency = urgency
		route_warning.emit(urgency)
	var frightened := _sample_anomaly(player_pos)
	if frightened != is_frightened:
		is_frightened = frightened
		anomaly_reaction.emit(frightened)

func _sample_route_block(a: Vector3, b: Vector3) -> float:
	var blocked := 0
	for i in range(1, route_samples + 1):
		var t := float(i) / float(route_samples + 1)
		var p := a.lerp(b, t)
		if terrain.density_at(p) >= block_density:
			blocked += 1
	return float(blocked) / float(route_samples)

## Heuristic-only: counts distinct tissue ids in a small ring around the
## player. A biome edge/anomaly tends to mix tissues that are otherwise
## uniform locally. This is deliberately qualitative (design-core 7: "not a
## precise biome detector"), tuned loosely rather than exactly.
func _sample_anomaly(p: Vector3) -> bool:
	var seen: Dictionary = {}
	var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
	for d in dirs:
		var t := terrain.tissue_at(p + d * anomaly_radius)
		seen[t] = true
	return seen.size() >= 4
