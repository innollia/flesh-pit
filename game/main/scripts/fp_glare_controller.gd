class_name FPGlareController
extends RefCounted

## R10 / T6: Cave return glare controller.
## Returning to the brightly lit restroom after staying in the dark cave
## for 20+ seconds triggers a momentary glare (flash = 1.0).
## Short visits (< 20s), bright doorway threshold crossings, or standing
## in front of the illuminated open door (door_spill) do not arm or re-trigger glare.
## Rearming requires spending at least 20 continuous seconds in the actual dark cave.
## On title start, load, or death respawn, state is cleanly reset to prevent accidental glare.

const DARK_DWELL_THRESHOLD: float = 20.0
const BASE_DECAY_RATE: float = 0.8

var dark_dwell_threshold: float = DARK_DWELL_THRESHOLD
var decay_rate: float = BASE_DECAY_RATE

var was_inside: bool = true
var cave_time: float = 0.0
var bright_time: float = 0.0
var glare_ready: bool = false
var flash: float = 0.0

var total_flashes: int = 0

func _init(p_threshold: float = DARK_DWELL_THRESHOLD, p_decay: float = BASE_DECAY_RATE) -> void:
	dark_dwell_threshold = p_threshold
	decay_rate = p_decay
	reset(true)

## Resets state to clean defaults (default inside restroom).
## Initial title, game load, or death respawn sets was_inside = true,
## cave_time = 0.0, bright_time = 0.0, glare_ready = false, flash = 0.0.
func reset(inside: bool = true) -> void:
	was_inside = inside
	cave_time = 0.0
	bright_time = 0.0
	glare_ready = false
	flash = 0.0

## Advances glare state machine by delta seconds.
## inside: true if player is inside the restroom, false if outside.
## delta: frame delta time in seconds.
## p3: is_dark (bool) or glare_factor (float if p3 is numeric).
## p4: glare_factor (float) if p3 is is_dark (bool).
## Returns true on the exact step when flash is triggered.
func step(inside: bool, delta: float, p3: Variant = null, p4: Variant = null) -> bool:
	var is_dark: bool = false
	var glare_factor: float = 1.0

	if typeof(p3) == TYPE_BOOL:
		is_dark = bool(p3)
		if p4 != null:
			glare_factor = float(p4)
	elif p3 != null:
		glare_factor = float(p3)
		is_dark = not inside
	else:
		is_dark = not inside

	var triggered := false
	if inside:
		# Player is inside bright restroom
		if not was_inside and glare_ready:
			flash = 1.0
			glare_ready = false
			total_flashes += 1
			triggered = true
		cave_time = 0.0
		bright_time = 0.0
	else:
		# Player is outside restroom
		if is_dark:
			# Player is in actual dark cave: accumulate continuous dark dwell
			cave_time += delta
			bright_time = 0.0
			if cave_time >= dark_dwell_threshold:
				glare_ready = true
		else:
			# Player is outside, but in bright threshold / door_spill / bright area
			# 20초 연속 어둠만 누적, 밝은 문턱 구간은 dark_time 불누적 / 연속 체류 reset
			cave_time = 0.0
			if glare_ready:
				bright_time += delta
				if bright_time >= dark_dwell_threshold:
					glare_ready = false
					bright_time = 0.0

	was_inside = inside

	var effective_decay := decay_rate / maxf(0.001, glare_factor)
	flash = maxf(0.0, flash - delta * effective_decay)
	return triggered

## Evaluates whether a 3D position in the world is genuinely dark.
## Used by Main._update_atmosphere to determine is_dark.
## - inside: inside restroom box -> false (bright)
## - dist_to_door < 0.8: standing in door frame / threshold (문기둥) -> false
## - door_open_amount > 0.05 and dist_to_door < 2.5: illuminated by open door spill -> false
## - depth < 2.2: shallow entrance zone near restroom -> false
## - otherwise (deep in flesh cave): true (dark)
static func is_dark_at(inside: bool, dist_to_door: float, door_open_amount: float = 0.0, depth: float = 999.0) -> bool:
	if inside:
		return false
	if dist_to_door < 0.8:
		return false
	if door_open_amount > 0.05 and dist_to_door < 2.5:
		return false
	if depth < 2.2:
		return false
	return true

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
