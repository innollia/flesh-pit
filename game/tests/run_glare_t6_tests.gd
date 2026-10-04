extends SceneTree

const FPGlareController = preload("res://main/scripts/fp_glare_controller.gd")

## T6 / R10 Regression test suite:
## Cave return glare 20s dark dwell threshold and recurrence suppression.
## - Short cave visit (< 20s, e.g. 5s) -> 0 flash
## - Long cave dwell (>= 20s) -> 1 flash on return
## - Continuous threshold crossing / lingering -> 0 additional flashes
## - Re-adaptation and second long cave dwell -> 1 flash on return
## - Title / load / death respawn reset -> 0 unintended flash
## - Mutation M24 glare factor duration scaling

var passed := 0
var failed := 0

func _init() -> void:
	run()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func run() -> void:
	_test_naive_logic_flaw_contrast()
	_test_short_cave_visit_zero_flash()
	_test_long_cave_dwell_single_flash()
	_test_door_threshold_oscillation_zero_extra_flash()
	_test_readaptation_and_second_long_dwell()
	_test_title_load_death_respawn_zero_flash()
	_test_boundary_precision_19_9s_vs_20s()
	_test_m24_glare_duration_scaling()
	_test_restroom_coordinate_integration()

	print("GLARE T6: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

## Demonstrates why the old naive logic (if inside and not was_inside: flash = 1.0) was broken (RED)
## and how FPGlareController cures it (GREEN).
func _test_naive_logic_flaw_contrast() -> void:
	# Naive old logic simulation:
	var naive_flashes := 0
	var naive_was_inside := true
	# 1) Player steps out for 2 seconds and comes back:
	naive_was_inside = false # outside
	if true and not naive_was_inside: # inside
		naive_flashes += 1
	# In the old logic, naive_flashes became 1 on a short 2s trip (BUG!)
	check(naive_flashes == 1, "contrast: naive old logic erroneously triggered on short trip")

	# FPGlareController on the same 2s trip:
	var ctrl := FPGlareController.new()
	ctrl.step(false, 2.0)
	var triggered := ctrl.step(true, 0.016)
	check(not triggered and ctrl.flash == 0.0 and ctrl.total_flashes == 0,
		"cured: FPGlareController suppresses flash on short 2s trip")

## Test 1: Short cave visit (< 20s, e.g. 5s) -> 0 flash
func _test_short_cave_visit_zero_flash() -> void:
	var ctrl := FPGlareController.new()
	check(ctrl.total_flashes == 0, "short visit: initial flash count is 0")

	# Step outside for 5.0 seconds total in chunks
	for i in range(5):
		ctrl.step(false, 1.0)
	check(is_equal_approx(ctrl.cave_time, 5.0), "short visit: cave time accumulates to 5s")
	check(not ctrl.is_glare_ready(), "short visit: glare_ready is false after 5s")

	# Return to restroom
	var triggered := ctrl.step(true, 0.016)
	check(not triggered, "short visit: return does not trigger flash")
	check(ctrl.flash == 0.0, "short visit: flash intensity remains 0.0")
	check(ctrl.total_flashes == 0, "short visit: total flashes remains 0")
	check(ctrl.cave_time == 0.0, "short visit: cave time resets to 0.0 on inside")

## Test 2: Long cave dwell (>= 20s) -> exactly 1 flash on return
func _test_long_cave_dwell_single_flash() -> void:
	var ctrl := FPGlareController.new()

	# Spend 20.0 seconds in the dark cave
	ctrl.step(false, 10.0)
	check(not ctrl.is_glare_ready(), "long dwell: 10s is not enough for glare_ready")
	ctrl.step(false, 10.0)
	check(ctrl.is_glare_ready(), "long dwell: 20s dark dwell arms glare_ready")
	check(ctrl.total_flashes == 0, "long dwell: flash has not triggered while still outside")

	# Stay an additional 5 seconds outside; glare_ready stays armed
	ctrl.step(false, 5.0)
	check(ctrl.is_glare_ready(), "long dwell: glare_ready remains armed")

	# Return to restroom
	var triggered := ctrl.step(true, 0.016)
	check(triggered, "long dwell: return triggers flash")
	check(is_equal_approx(ctrl.flash, 1.0 - 0.016 * 0.8), "long dwell: flash starts at 1.0 (minus first tick decay)")
	check(not ctrl.is_glare_ready(), "long dwell: glare_ready disarmed immediately upon return")
	check(ctrl.total_flashes == 1, "long dwell: total flashes is exactly 1")
	check(ctrl.cave_time == 0.0, "long dwell: cave_time reset to 0")

## Test 3: Continuous doorway threshold crossing / hovering -> 0 additional flashes
func _test_door_threshold_oscillation_zero_extra_flash() -> void:
	var ctrl := FPGlareController.new()

	# Trigger initial flash via 20s dwell
	ctrl.step(false, 20.0)
	ctrl.step(true, 0.016)
	check(ctrl.total_flashes == 1, "oscillation: initial flash triggered")

	# Rapidly oscillate across the doorway threshold:
	# Outside (0.2s) -> Inside (0.1s) -> Outside (0.5s) -> Inside (0.2s) ...
	for i in range(15):
		ctrl.step(false, 0.2)
		check(not ctrl.is_glare_ready(), "oscillation: quick step outside does not arm glare")
		var triggered_in := ctrl.step(true, 0.1)
		check(not triggered_in, "oscillation: stepping back inside does not re-trigger flash")

	check(ctrl.total_flashes == 1, "oscillation: exactly 0 additional flashes during threshold oscillation")
	check(not ctrl.is_glare_ready(), "oscillation: glare_ready remains false")

## Test 4: Re-adaptation and second long cave dwell -> 1 new flash on return
func _test_readaptation_and_second_long_dwell() -> void:
	var ctrl := FPGlareController.new()

	# First 20s dwell and return
	ctrl.step(false, 20.0)
	ctrl.step(true, 0.016)
	check(ctrl.total_flashes == 1, "rearm: first return triggered flash")

	# Re-adapt inside restroom: let flash decay completely to 0.0
	for i in range(10):
		ctrl.step(true, 0.2)
	check(ctrl.flash == 0.0, "rearm: eyes adapted, flash decayed to 0.0")

	# Short trip out and back (3s) -> still no flash
	ctrl.step(false, 3.0)
	ctrl.step(true, 0.016)
	check(ctrl.total_flashes == 1, "rearm: short trip during adaptation produces no flash")

	# Second long dwell in dark cave (20s)
	ctrl.step(false, 20.0)
	check(ctrl.is_glare_ready(), "rearm: 20s dark dwell re-arms glare")

	# Second return to restroom
	var triggered2 := ctrl.step(true, 0.016)
	check(triggered2, "rearm: second return triggers second flash")
	check(ctrl.total_flashes == 2, "rearm: total flashes is now exactly 2")
	check(not ctrl.is_glare_ready(), "rearm: glare_ready disarmed again")

## Test 5: Title / load / death respawn reset -> 0 unintended flash
func _test_title_load_death_respawn_zero_flash() -> void:
	var ctrl := FPGlareController.new()

	# Initial construction represents game start / title screen:
	check(ctrl.was_inside, "init: was_inside defaults to true")
	check(ctrl.cave_time == 0.0, "init: cave_time defaults to 0.0")
	check(not ctrl.is_glare_ready(), "init: glare_ready defaults to false")
	check(ctrl.flash == 0.0, "init: flash defaults to 0.0")

	# Stepping on frame 1 in restroom:
	var t1 := ctrl.step(true, 0.016)
	check(not t1 and ctrl.flash == 0.0, "init: frame 1 inside restroom triggers no flash")

	# Simulate death outside: player was in cave for 15s, then dies
	ctrl.step(false, 15.0)
	# On death, main.die() respawns player at START_POS (inside) and calls reset(true):
	ctrl.reset(true)
	check(ctrl.was_inside, "death: was_inside reset to true")
	check(ctrl.cave_time == 0.0, "death: cave_time reset to 0.0")
	check(not ctrl.is_glare_ready(), "death: glare_ready reset to false")
	check(ctrl.flash == 0.0, "death: flash reset to 0.0")
	var t_respawn := ctrl.step(true, 0.016)
	check(not t_respawn and ctrl.flash == 0.0, "death: respawn in restroom triggers 0 flash")

	# Simulate save loading: load sets reset(true)
	ctrl.step(false, 25.0) # player was outside
	check(ctrl.is_glare_ready(), "pre-load: armed before load")
	ctrl.reset(true) # loading game checkpoint resets state
	check(not ctrl.is_glare_ready(), "load: glare_ready cleared on load")
	var t_load := ctrl.step(true, 0.016)
	check(not t_load and ctrl.flash == 0.0, "load: loaded game triggers 0 flash")

## Test 6: Boundary precision: 19.9s vs 20.0s
func _test_boundary_precision_19_9s_vs_20s() -> void:
	var ctrl := FPGlareController.new()

	# 19.9 seconds in cave
	ctrl.step(false, 19.9)
	check(not ctrl.is_glare_ready(), "boundary: 19.9s is strictly below 20s threshold")
	ctrl.step(true, 0.016)
	check(ctrl.total_flashes == 0, "boundary: 19.9s return triggers 0 flash")

	# Now 20.0 seconds in cave
	ctrl.step(false, 20.0)
	check(ctrl.is_glare_ready(), "boundary: exactly 20.0s arms glare")
	ctrl.step(true, 0.016)
	check(ctrl.total_flashes == 1, "boundary: 20.0s return triggers 1 flash")

## Test 7: Mutation M24 glare factor duration scaling (x2 duration)
func _test_m24_glare_duration_scaling() -> void:
	# Standard progression (glare_factor = 1.0)
	var ctrl_std := FPGlareController.new()
	ctrl_std.step(false, 20.0)
	ctrl_std.step(true, 0.0) # flash = 1.0
	ctrl_std.flash = 1.0
	# Decay 1.0 second at factor 1.0: decay = 0.8 / 1.0 = 0.8
	ctrl_std.step(true, 1.0, 1.0)
	check(is_equal_approx(ctrl_std.flash, 0.2), "m24: standard flash after 1.0s is 0.2")

	# M24 Owl Eyes progression (glare_factor = 2.0)
	var ctrl_m24 := FPGlareController.new()
	ctrl_m24.step(false, 20.0)
	ctrl_m24.step(true, 0.0)
	ctrl_m24.flash = 1.0
	# Decay 1.0 second at factor 2.0: decay = 0.8 / 2.0 = 0.4
	ctrl_m24.step(true, 1.0, 2.0)
	check(is_equal_approx(ctrl_m24.flash, 0.6), "m24: M24 flash after 1.0s is 0.6 (decays half as fast)")

	# Complete fade: standard reaches 0.0 at 1.25s, M24 at 2.5s (2x duration)
	ctrl_std.step(true, 0.3, 1.0)
	check(ctrl_std.flash == 0.0, "m24: standard flash reaches 0.0 in 1.25s")
	check(ctrl_m24.flash > 0.0, "m24: M24 flash still active past 1.25s")
	ctrl_m24.step(true, 1.5, 2.0)
	check(ctrl_m24.flash == 0.0, "m24: M24 flash reaches 0.0 at 2.5s (exact 2x duration)")

## Test 8: Integration with restroom bounding box logic
func _test_restroom_coordinate_integration() -> void:
	var ctrl := FPGlareController.new()
	var restroom_half := FPRestroom.HALF # Vector3(2.25, 1.3, 1.5)

	var in_room_pos := Vector3(0.0, 0.95, 0.0)
	var in_room := absf(in_room_pos.x) <= restroom_half.x and in_room_pos.y >= 0.0 and in_room_pos.y <= 2 * restroom_half.y and absf(in_room_pos.z) <= restroom_half.z
	check(in_room, "coords: START_POS is inside restroom")

	var cave_pos := Vector3(0.0, 0.95, -2.5) # beyond door (door z is negative or positive)
	var in_cave := not (absf(cave_pos.x) <= restroom_half.x and cave_pos.y >= 0.0 and cave_pos.y <= 2 * restroom_half.y and absf(cave_pos.z) <= restroom_half.z)
	check(in_cave, "coords: flesh cave position is outside restroom")

	# Step in cave coords for 21 seconds
	for i in range(21):
		ctrl.step(not in_cave, 1.0)
	check(ctrl.is_glare_ready(), "coords: player standing at cave coords for 21s arms glare")

	# Step to restroom coords
	var tr := ctrl.step(in_room, 0.016)
	check(tr and ctrl.total_flashes == 1, "coords: walking to restroom coords triggers glare")
