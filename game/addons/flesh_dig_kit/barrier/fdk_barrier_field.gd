class_name FDKBarrierField
extends Node3D

## Owns the player's currently-placed FDKBarrier instances (carry cap 3,
## docs/spec/06-tools.md) and feeds them regeneration pressure from an FDKTerrainField
## each tick, so barriers accumulate stress from the actual biome motion they
## are holding back instead of a scripted timer.
##
## Usage: call `update(delta)` once per frame after the terrain's own
## regenerate_all. Broken barriers stop absorbing pressure and their tissue
## resumes normal regeneration on the next tick (this field does not un-block
## anything itself -- see `carve_release` for the "boing" pop, called
## automatically on `broke`).

signal barrier_broke(barrier: FDKBarrier, world_pos: Vector3)

const MAX_CARRIED: int = 3

@export var terrain: FDKTerrainField
## How much of the field's regen_rate becomes "pressure" fed to a barrier
## standing in tissue that would otherwise be regenerating there. Tuned so a
## barrier in fast-regrowing flesh breaks noticeably sooner than one in a
## quiet spot.
@export var pressure_scale: float = 6.0

var carried_count: int = 0
var _barriers: Array[FDKBarrier] = []

## Places a new barrier at world_pos if the carry cap allows it. Returns the
## barrier, or null if none are left to place.
func place(world_pos: Vector3, radius: float = 0.9) -> FDKBarrier:
	if _barriers.size() - _count_broken() >= MAX_CARRIED:
		return null
	var b := FDKBarrier.new()
	b.name = "Barrier%d" % _barriers.size()
	b.position = world_pos
	b.radius = radius
	b.broke.connect(func(release_ratio): _on_broke(b, release_ratio))
	add_child(b)
	_barriers.append(b)
	return b

func _count_broken() -> int:
	var n := 0
	for b in _barriers:
		if b.is_broken():
			n += 1
	return n

func carried_remaining() -> int:
	return MAX_CARRIED - (_barriers.size() - _count_broken())

func get_barriers() -> Array[FDKBarrier]:
	return _barriers

## Feeds each intact barrier the local regeneration pressure at its position
## (approximated as field.config.regen_rate scaled by how much density is
## currently missing nearby, i.e. how much tissue *wants* to move back in).
func update(delta: float) -> void:
	if terrain == null:
		return
	for b in _barriers:
		if b.is_broken():
			continue
		var deficit := 1.0 - terrain.density_at(b.position)
		if deficit <= 0.0:
			continue
		var pressure := terrain.config.regen_rate * pressure_scale * deficit
		b.absorb_pressure(pressure * delta, delta)

## On break: the barrier stops absorbing pressure (see `update`), so the
## tissue it was holding resumes regenerating on the terrain's own next
## regenerate_all pass -- no separate catch-up push is needed, since the
## deficit is exactly what accumulated while the barrier stood. The "boing"
## itself (docs/spec/06-tools.md) is a presentation event: `release_ratio` (how
## loaded the barrier was at the instant it broke, 0..1) tells the frontend
## how big a pop to play. `barrier_broke` re-emits this at the field level so
## game code has one place to hook the FX regardless of which barrier broke.
func _on_broke(b: FDKBarrier, release_ratio: float) -> void:
	barrier_broke.emit(b, b.position)

func serialize() -> Dictionary:
	var arr: Array = []
	for b in _barriers:
		if not b.is_broken():
			arr.append(b.serialize())
	return {"version": 1, "barriers": arr}

func deserialize(data: Dictionary) -> void:
	for c in _barriers:
		c.queue_free()
	_barriers.clear()
	var arr: Array = data.get("barriers", [])
	for entry in arr:
		var b := FDKBarrier.new()
		b.deserialize(entry)
		b.name = "Barrier%d" % _barriers.size()
		b.broke.connect(func(release_ratio): _on_broke(b, release_ratio))
		add_child(b)
		_barriers.append(b)
