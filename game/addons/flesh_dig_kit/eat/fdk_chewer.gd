class_name FDKChewer
extends Node

## Drives the "look at flesh, hold to chew, tear it off" interaction.
## Call try_start(world_pos) each frame the eat input is held with a valid
## raycast hit, and stop() the frame it is released or the target changes.
## Reads FDKStomach to slow chewing down when overfull.
##
## Frontend contract: this is the full signal surface a hand-rig/animation
## layer needs and should rely on instead of polling state:
##   grab_started(target_cell)      -- a new cell was grabbed, curl closed from idle
##   chew_progress(ratio, target_cell) -- 0..1 progress toward the current tear, every frame while chewing
##   cell_torn(world_pos)           -- tear completed at world_pos (a.k.a. "tear")
##   released()                     -- chewing stopped (input released or target lost), curl should relax to idle
## No backend code here reads or assumes anything about hand meshes, hand
## animation state, or visuals -- that is frontend scope.

signal grab_started(target_cell: Vector3i)
signal chew_progress(ratio: float, target_cell: Vector3i) ## ratio 0..1 within the current chew, for squeeze/stretch visuals
signal cell_torn(world_pos: Vector3) ## a.k.a. "tear" in the frontend contract
signal released()

@export var terrain: FDKTerrainField
@export var stomach: FDKStomach
@export var config: FDKStomachConfig

var _chewing: bool = false
var _target_chunk_coord: Vector3i
var _target_local_cell: Vector3i
var _elapsed: float = 0.0

## Begins or continues chewing at world_pos. Resets progress if the target
## cell changed since the last call. Emits grab_started when a chew begins
## or the target cell changes (a fresh grab).
func try_start(world_pos: Vector3) -> void:
	if terrain == null:
		return
	if terrain.density_at(world_pos) < terrain.config.iso_level or (terrain.has_method("is_edible_at") and not terrain.is_edible_at(world_pos)):
		stop()
		return
	var result := terrain.world_to_cell(world_pos)
	var chunk_coord: Vector3i = result[0]
	var local_cell: Vector3i = result[1]
	if not _chewing or chunk_coord != _target_chunk_coord or local_cell != _target_local_cell:
		_chewing = true
		_target_chunk_coord = chunk_coord
		_target_local_cell = local_cell
		_elapsed = 0.0
		grab_started.emit(local_cell)

## Stops the current chew (input released, or raycast lost its target).
## Emits released() exactly once per was-chewing -> stopped transition.
func stop() -> void:
	if _chewing:
		released.emit()
	_chewing = false
	_elapsed = 0.0

func is_chewing() -> bool:
	return _chewing

## Advances the current chew by delta seconds. Emits chew_progress every
## call (drives squeeze/stretch deformation visuals before the tear), and
## cell_torn + adds flesh to the stomach once base_chew_time (scaled by
## overfill slowdown) is reached, then resets for the next cell.
func process_chew(delta: float) -> void:
	if not _chewing or terrain == null or config == null:
		return
	var multiplier: float = stomach.chew_time_multiplier() if stomach != null else 1.0
	var required: float = config.base_chew_time * multiplier
	_elapsed += delta
	var ratio: float = clampf(_elapsed / required, 0.0, 1.0)
	chew_progress.emit(ratio, _target_local_cell)
	if _elapsed >= required:
		var chunk := terrain.get_or_create_chunk(_target_chunk_coord)
		var world_pos: Vector3 = chunk.position + (Vector3(_target_local_cell) + Vector3(0.5, 0.5, 0.5)) * terrain.config.cell_size
		if terrain.density_at(world_pos) < terrain.config.iso_level:
			stop()
			return
		terrain.dig_at(world_pos, 1.0) # updates shared border corners in neighbour chunks too
		cell_torn.emit(world_pos)
		if stomach != null:
			stomach.add_flesh(config.flesh_per_cell)
		_elapsed = 0.0
