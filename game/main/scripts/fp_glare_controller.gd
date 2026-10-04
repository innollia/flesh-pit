class_name FPGlareController
extends RefCounted

## R10 / T6: Cave return glare controller.
## Returning to the brightly lit restroom after staying in the dark cave
## for 20+ seconds triggers a momentary glare (flash = 1.0).
## Short visits (< 20s) or doorway threshold crossings do not trigger or re-trigger glare.
## Rearming requires spending at least 20 seconds in the dark cave again.
## On title start, load, or death respawn, state is cleanly reset to prevent accidental glare.

const DARK_DWELL_THRESHOLD: float = 20.0
const BASE_DECAY_RATE: float = 0.8

var dark_dwell_threshold: float = DARK_DWELL_THRESHOLD
var decay_rate: float = BASE_DECAY_RATE

var was_inside: bool = true
var cave_time: float = 0.0
var glare_ready: bool = false
var flash: float = 0.0

var total_flashes: int = 0

func _init(p_threshold: float = DARK_DWELL_THRESHOLD, p_decay: float = BASE_DECAY_RATE) -> void:
	dark_dwell_threshold = p_threshold
	decay_rate = p_decay
	reset(true)

## Resets state to clean defaults (default inside restroom).
## Initial title, game load, or death respawn sets was_inside = true,
## cave_time = 0.0, glare_ready = false, flash = 0.0.
func reset(inside: bool = true) -> void:
	was_inside = inside
	cave_time = 0.0
	glare_ready = false
	flash = 0.0

## Advances glare state machine by delta seconds.
## inside: true if player is inside the restroom, false if in the flesh cave.
## delta: frame delta time in seconds.
## glare_factor: progression multiplier (e.g. M24 doubles glare duration -> halves decay rate).
## Returns true on the exact step when flash is triggered.
func step(inside: bool, delta: float, glare_factor: float = 1.0) -> bool:
	var triggered := false
	if inside:
		if not was_inside and glare_ready:
			flash = 1.0
			glare_ready = false
			total_flashes += 1
			triggered = true
		cave_time = 0.0
	else:
		cave_time += delta
		if cave_time >= dark_dwell_threshold:
			glare_ready = true

	was_inside = inside

	var effective_decay := decay_rate / maxf(0.001, glare_factor)
	flash = maxf(0.0, flash - delta * effective_decay)
	return triggered

## Returns whether glare is armed and ready to trigger on next restroom entry.
func is_glare_ready() -> bool:
	return glare_ready

## Returns elapsed continuous time spent in dark cave.
func get_cave_time() -> float:
	return cave_time

## Returns current flash intensity (0.0 to 1.0).
func get_flash() -> float:
	return flash

## Computes tonemap exposure matching main.gd formula: 1.0 + 2.5 * flash
func get_tonemap_exposure() -> float:
	return 1.0 + 2.5 * flash
