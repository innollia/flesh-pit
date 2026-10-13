class_name FDKStomachConfig
extends Resource

## Tunable numbers for FDKStomach and the chewing interaction.

## Normal (comfortable) stomach capacity, in abstract "flesh units".
@export var capacity: float = 100.0

## How far past capacity overfilling is still allowed before eating
## effectively stalls (chew_slowdown approaches its floor).
@export var overfill_capacity: float = 60.0

## Base seconds of sustained chewing required to tear off one cell's worth
## of flesh, before any overfill slowdown is applied.
@export var base_chew_time: float = 0.6

## When the stomach is past `capacity`, chew time is multiplied by
## lerp(1.0, overfill_chew_multiplier, overfill_ratio), overfill_ratio being
## how far into the overfill band the player currently is (0..1).
@export var overfill_chew_multiplier: float = 3.0

## Flesh units for one torn cell of solid flesh. A tear never pays more than
## the density it actually removed: if its corners lost less than 4 full
## corners' worth (a cell only partly grown back), it pays that share.
## Corners are shared with neighbouring cells, so a cell is "whole" at 4.
@export var flesh_per_cell: float = 4.0

## Flesh units for a tear whose 8 corners lost `removed` density in total.
func units_for_removed(removed: float) -> float:
    return flesh_per_cell * clampf(removed / 4.0, 0.0, 1.0)
