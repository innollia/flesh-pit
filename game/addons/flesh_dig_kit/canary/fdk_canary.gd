class_name FDKCanary
extends Node

## Return-route + anomaly warning companion (docs/spec/07-danger-navigation.md). Pure
## logic/signals -- no cage mesh, no chirp audio, no visuals (frontend
## scope; see STATUS.md handoff pattern). Presentation note for the
## frontend: the design calls for a small portable cage/carrier that can
## enter view when its reaction matters, not a permanently visible bird.
##
## Two independent checks, run each call to `update`:
##  1. Return-route danger: the minimum clearance along the best explored
##     route back to the safe point (see below), not straight-line density.
##  2. Anomaly reaction: an odd cry / frightened reaction near unusual
##     nearby biome conditions (qualitative, not a precise detector).
##
## No exact direction is ever given for either signal (docs/spec/07-danger-navigation.md).

signal route_warning(urgency: float) ## 0..1, rising as the return route narrows
signal anomaly_reaction(frightened: bool) ## qualitative "something's off" cue

## Return-route model (docs/research/runtime-regeneration-navigation.md
## 7-9, P3): a coarse 1 m grid of the cells the player actually walked
## through (plus their face neighbours). Every `route_interval` seconds each
## explored cell gets a cheap clearance estimate (distance to the nearest
## solid sample, capped), and a widest-path search from the player's cell to
## the safe cell finds the best return route. Danger comes from that route's
## minimum clearance, not from distance to the restroom. Only the 0..1
## danger leaves this node; path/bottleneck live in `last_route` for tests
## and logs, never for the player.

@export var terrain: FDKTerrainField
## Density at or above this counts as solid for the clearance samples.
## A fed canary lowers it (looser, regrowing flesh already counts).
@export var block_density: float = 0.5
@export var anomaly_radius: float = 2.5
@export var grid_cell: float = 1.0
## Clearance (m) below which the player no longer fits.
@export var body_radius: float = 0.4
## Clearance (m) at or above which the route feels comfortably wide.
@export var comfort_clearance: float = 1.0
@export var route_interval: float = 2.0
@export var max_cells: int = 1500
@export var debug_log: bool = false

const CLEAR_STEPS := [0.25, 0.5, 0.75, 1.0, 1.25, 1.5]
const MAX_CLEAR := 1.75

var last_route_urgency: float = 0.0
var is_frightened: bool = false
## Debug only: {reachable, path_length, min_clearance, bottleneck}.
var last_route: Dictionary = {}

var _explored: Dictionary = {} ## Vector3i -> true
var _order: Array[Vector3i] = []
var _last_trail: Variant = null
var _route_t: float = INF
var _dirs: Array[Vector3] = []

func _init() -> void:
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x == 0 and y == 0 and z == 0:
					continue
				if abs(x) + abs(y) + abs(z) == 2:
					continue # 6 faces + 8 corners is enough for a rough radius
				_dirs.append(Vector3(x, y, z).normalized())

## Call once per tick. `dt` is the time since the previous call.
func update(player_pos: Vector3, safe_pos: Vector3, dt: float = 0.25) -> void:
	if terrain == null:
		return
	if _last_trail == null:
		_last_trail = safe_pos
	record_trail(player_pos)
	_route_t += dt
	if _route_t >= route_interval:
		_route_t = 0.0
		var r := compute_route(player_pos, safe_pos)
		var urgency := danger_from_route(r)
		if absf(urgency - last_route_urgency) > 0.02:
			last_route_urgency = urgency
			route_warning.emit(urgency)
	var frightened := _sample_anomaly(player_pos)
	if frightened != is_frightened:
		is_frightened = frightened
		anomaly_reaction.emit(frightened)

func reset_trail() -> void:
	_explored.clear()
	_order.clear()
	_last_trail = null
	_route_t = INF

func cell_of(p: Vector3) -> Vector3i:
	return Vector3i((p / grid_cell).floor())

## Marks the walked segment since the previous trail point as explored.
func record_trail(p: Vector3) -> void:
	var from: Vector3 = p if _last_trail == null else _last_trail
	var steps := int(ceil(from.distance_to(p) / (grid_cell * 0.5))) + 1
	for i in range(steps + 1):
		var c := cell_of(from.lerp(p, float(i) / float(steps)))
		_mark(c)
		for d in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
			_mark(c + d)
	_last_trail = p

func _mark(c: Vector3i) -> void:
	if _explored.has(c):
		return
	_explored[c] = true
	_order.append(c)
	while _order.size() > max_cells:
		_explored.erase(_order.pop_front())

func explored_count() -> int:
	return _explored.size()

## Rough distance (m) from the cell centre to the nearest solid sample.
func clearance_at(p: Vector3) -> float:
	if terrain.density_at(p) >= block_density:
		return 0.0
	for r in CLEAR_STEPS:
		for d in _dirs:
			if terrain.density_at(p + d * r) >= block_density:
				return r
	return MAX_CLEAR

## Widest-path (max of the min clearance) search over explored cells from
## the player's cell to the safe cell. Debug data only.
func compute_route(player_pos: Vector3, safe_pos: Vector3) -> Dictionary:
	var start := cell_of(player_pos)
	var goal := cell_of(safe_pos)
	_mark(start)
	_mark(goal)
	var clear: Dictionary = {}
	for c in _explored.keys():
		clear[c] = clearance_at((Vector3(c) + Vector3.ONE * 0.5) * grid_cell)
	var best: Dictionary = {start: clear[start]}
	var dist: Dictionary = {start: 0}
	var prev: Dictionary = {}
	var open: Array = [start]
	var done: Dictionary = {}
	var nbrs := [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
	while not open.is_empty():
		var bi := 0
		for i in range(1, open.size()):
			var a: Vector3i = open[i]
			var o: Vector3i = open[bi]
			if best[a] > best[o] or (best[a] == best[o] and dist[a] < dist[o]):
				bi = i
		var cur: Vector3i = open[bi]
		open.remove_at(bi)
		if done.has(cur):
			continue
		done[cur] = true
		if cur == goal:
			break
		for d in nbrs:
			var nb: Vector3i = cur + d
			if not clear.has(nb) or done.has(nb) or float(clear[nb]) <= 0.0:
				continue
			var w := minf(best[cur], clear[nb])
			var nd: int = dist[cur] + 1
			if not best.has(nb) or w > best[nb] or (w == best[nb] and nd < dist[nb]):
				best[nb] = w
				dist[nb] = nd
				prev[nb] = cur
				open.append(nb)
	var out := {"reachable": false, "path_length": -1.0, "min_clearance": 0.0, "bottleneck": Vector3.ZERO}
	if done.has(goal) and float(clear[start]) > 0.0:
		var min_c := INF
		var bottle := goal
		var c: Vector3i = goal
		while true:
			if float(clear[c]) < min_c:
				min_c = clear[c]
				bottle = c
			if c == start:
				break
			c = prev[c]
		out = {
			"reachable": min_c >= body_radius,
			"path_length": float(dist[goal]) * grid_cell,
			"min_clearance": min_c,
			"bottleneck": (Vector3(bottle) + Vector3.ONE * 0.5) * grid_cell,
		}
	last_route = out
	if debug_log:
		print("[canary route] ", out)
	return out

## Hidden danger scalar 0..1 from a route result.
func danger_from_route(r: Dictionary) -> float:
	if not bool(r.get("reachable", false)):
		return 1.0
	var m := float(r.get("min_clearance", 0.0))
	return 1.0 - clampf((m - body_radius) / (comfort_clearance - body_radius), 0.0, 1.0)
## Heuristic-only: counts distinct tissue ids in a small ring around the
## player. A biome edge/anomaly tends to mix tissues that are otherwise
## uniform locally. This is deliberately qualitative (docs/spec/07-danger-navigation.md: "not a
## precise biome detector"), tuned loosely rather than exactly.
func _sample_anomaly(p: Vector3) -> bool:
	var seen: Dictionary = {}
	var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]
	for d in dirs:
		var t := terrain.tissue_at(p + d * anomaly_radius)
		seen[t] = true
	return seen.size() >= 4
