class_name FDKDepthDanger
extends RefCounted

## Per-shell danger scaling (design-core 13: "left for tuning by playtest").
## Pure function of depth -> multipliers; callers apply these to regen
## rate, nerve disturb chance/strength, and hazard damage.
##
## Baseline: core (shell 0) is calm; each further shell scales danger up
## by DANGER_STEP, matching design-core 7 ("danger rises outward").

const DANGER_STEP := 0.35 ## +35% per shell past the first

static func shell_index(depth: float, shell_thickness: float) -> int:
	return int(depth / shell_thickness)

## Multiplier applied to regen rate / nerve disturb / hazard damage.
static func danger_multiplier(depth: float, shell_thickness: float) -> float:
	return 1.0 + float(shell_index(depth, shell_thickness)) * DANGER_STEP

## Chance per chew that biting nerve-dense tissue (tissue id 1) triggers a
## disturb, scaled by depth.
static func nerve_disturb_chance(depth: float, shell_thickness: float) -> float:
	return clampf(0.35 * danger_multiplier(depth, shell_thickness), 0.0, 0.95)
