class_name FDKTerrainConfig
extends Resource

## Tunable numbers for one FDKTerrainField. Exposed as a Resource so a game
## can swap in different presets (e.g. tougher tissue deeper in the organism)
## without touching kit code.

## Number of cells along each axis of a single chunk. A chunk is chunk_size^3 cells.
@export var chunk_size: int = 16

## World-space size of one density cell, in meters.
@export var cell_size: float = 0.5

## Density value considered "solid" vs "empty" for meshing (isosurface level).
@export var iso_level: float = 0.5

## Density regenerates toward 1.0 (fully solid) at this many units per second
## for a fully torn-out cell. Cells the player currently occupies are excluded.
## Slower continuous healing: 0.003 takes over three times as long as the
## previous 0.01 with the same tissue, crowding, depth and spray conditions.
@export var regen_rate: float = 0.003

## Radius (in cells) around the player that is protected from regeneration,
## so the player is never sealed into solid tissue.
@export var regen_protect_radius: float = 1.5

## Density removed per second of sustained chewing on a cell (before it
## fully clears to density 0.0).
@export var dig_rate: float = 1.5

## How far (in cells, 0..0.5) surface vertices are nudged at random so the
## faceted walls look organic instead of a grid.
@export var facet_jitter: float = 0.22

## Distance from the depth origin at which flesh reaches its darkest deep tint.
@export var depth_tone_distance: float = 30.0
