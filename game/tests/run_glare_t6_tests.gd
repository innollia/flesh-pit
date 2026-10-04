extends SceneTree

const FPGlareController = preload("res://main/scripts/fp_glare_controller.gd")

## T6 / R10 Regression test suite:
## Cave return glare 20s dark dwell threshold and recurrence suppression.
## - bright outside 20s -> no arm
## - dark 19.9s -> bright threshold reset (no arm, return gives 0 flash)
## - dark 20.0s -> bright return 1 flash
## - door threshold oscillation -> 0 additional flashes
## - re-adaptation and second long dark dwell -> 1 additional flash
## - title / load / death respawn reset -> 0 unintended flash
## - mutation M24 glare factor duration scaling (x2 duration)
## - spatial dark discrimination (door_spill, threshold frame, depth)

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
	_test_bright_outside_20s_no_arm()
	_test_dark_19_9s_bright_threshold_reset()
	_test_dark_20s_bright_return_single_flash()
	_test_door_threshold_oscillation_zero_extra_flash()
	_test_readaptation_and_second_long_dwell()
	_test_title_load_death_respawn_zero_flash()
	_test_m24_glare_duration_scaling()
	_test_is_dark_at_spatial_discrimination()
	_test_restroom_coordinate_integration()

	print("GLARE T6: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

## Demonstrates why naive logic (if inside and not was_inside: flash = 1.0) was flawed (RED)
## and how FPGlareController cures it (GREEN).
func _test_naive_logic_flaw_contrast() -> void:
	# Naive old logic simulation:
	var naive_flashes := 0
	var naive_was_inside := true
	# 1) Player steps out for 2 seconds and comes back:
	naive_was_inside = false # outside
	if true and not naive_was_inside: # inside
		naive_flashes += 1
	check(naive_flashes == 1, "contrast: naive old logic erroneously triggered on short trip")

	# FPGlareController on the same 2s trip:
	var ctrl := FPGlareController.new()
	ctrl.step(false, 2.0, true)
	var triggered := ctrl.step(true, 0.016, false)
	check(not triggered and ctrl.flash == 0.0 and ctrl.total_flashes == 0,
		"cured: FPGlareController suppresses flash on short 2s trip")

## Component test 1: bright outside 20s -> no arm
## Player stays outside, but in bright threshold / door_spill light for 20s.
## Result: dark_time does not accumulate, glare_ready NEVER arms.
func _test_bright_outside_20s_no_arm() -> void:
	var ctrl := FPGlareController.new()

	# Spend 20.0 continuous seconds in bright outside (is_dark = false)
	for i in range(20):
		ctrl.step(false, 1.0, false)
	check(ctrl.cave_time == 0.0, "bright outside 20s: cave_time remains 0.0")
	check(not ctrl.is_glare_ready(), "bright outside 20s: glare_ready is NOT armed")
	check(ctrl.total_flashes == 0, "bright outside 20s: total flashes is 0")

	# Returning to restroom triggers 0 flash
	var triggered := ctrl.step(true, 0.016, false)
	check(not triggered, "bright outside 20s: return triggers 0 flash")
	check(ctrl.total_flashes == 0, "bright outside 20s: total flashes remains 0")
	check(ctrl.flash == 0.0, "bright outside 20s: flash intensity is 0.0")

## Component test 2: dark 19.9s -> bright threshold reset
## Player spends 19.9s in dark cave, then steps into bright threshold before reaching 20s.
## Result: dark_time resets to 0.0, no arm, return to restroom gives 0 flash.
func _test_dark_19_9s_bright_threshold_reset() -> void:
	var ctrl := FPGlareController.new()

	# 19.9 seconds in dark cave
	ctrl.step(false, 19.9, true)
	check(is_equal_approx(ctrl.cave_time, 19.9), "dark 19.9s: cave_time reaches 19.9s")
	check(not ctrl.is_glare_ready(), "dark 19.9s: not armed at 19.9s")

	# Step into bright threshold / door spill for 0.5s before entering
	ctrl.step(false, 0.5, false)
	check(ctrl.cave_time == 0.0, "dark 19.9s: bright threshold resets cave_time to 0.0")
	check(not ctrl.is_glare_ready(), "dark 19.9s: glare_ready remains unarmed after threshold reset")

	# Step into restroom
	var triggered := ctrl.step(true, 0.016, false)
	check(not triggered, "dark 19.9s: return triggers 0 flash")
	check(ctrl.total_flashes == 0, "dark 19.9s: total flashes remains 0")

## Component test 3: dark 20s -> bright return 1
## Player spends 20.0s in dark cave -> armed.
## Passing through bright threshold into restroom triggers exactly 1 flash.
func _test_dark_20s_bright_return_single_flash() -> void:
	var ctrl := FPGlareController.new()

	# Spend 20.0 continuous seconds in dark cave
	ctrl.step(false, 10.0, true)
	check(not ctrl.is_glare_ready(), "dark 20s: 10s is not enough to arm")
	ctrl.step(false, 10.0, true)
	check(ctrl.is_glare_ready(), "dark 20s: 20s dark dwell arms glare_ready")

	# Walk through bright threshold for 0.5s on the way into restroom
	ctrl.step(false, 0.5, false)
	check(ctrl.is_glare_ready(), "dark 20s: glare_ready stays armed while passing through threshold")

	# Return to bright restroom
	var triggered := ctrl.step(true, 0.016, false)
	check(triggered, "dark 20s: bright return triggers flash")
	check(ctrl.total_flashes == 1, "dark 20s: total flashes is exactly 1")
	check(ctrl.flash > 0.9, "dark 20s: flash intensity is active (~1.0)")
	check(not ctrl.is_glare_ready(), "dark 20s: glare_ready disarmed immediately upon return")
	check(ctrl.cave_time == 0.0, "dark 20s: cave_time reset to 0.0")

## Component test 4: door threshold oscillation -> 0 additional flashes
## After returning, hovering or repeatedly crossing between bright threshold and restroom
## produces 0 additional flashes.
func _test_door_threshold_oscillation_zero_extra_flash() -> void:
	var ctrl := FPGlareController.new()

	# Trigger initial flash via 20s dark dwell + return
	ctrl.step(false, 20.0, true)
	ctrl.step(true, 0.016, false)
	check(ctrl.total_flashes == 1, "oscillation: initial flash triggered")

	# Rapidly oscillate across the doorway threshold (bright threshold <-> inside):
	for i in range(20):
		ctrl.step(false, 0.2, false) # step to bright threshold (is_dark = false)
		check(not ctrl.is_glare_ready(), "oscillation: bright threshold does not arm glare")
		var triggered_in := ctrl.step(true, 0.1, false) # step inside restroom
		check(not triggered_in, "oscillation: stepping back inside does not re-trigger flash")

	check(ctrl.total_flashes == 1, "oscillation: exactly 0 additional flashes during 20 threshold crossings")
	check(not ctrl.is_glare_ready(), "oscillation: glare_ready remains false")

## Test 5: Re-adaptation and second long dark dwell -> 1 additional flash (total 2)
func _test_readaptation_and_second_long_dwell() -> void:
	var ctrl := FPGlareController.new()

	# First 20s dark dwell and return
	ctrl.step(false, 20.0, true)
	ctrl.step(true, 0.016, false)
	check(ctrl.total_flashes == 1, "rearm: first return triggered flash")

	# Re-adapt inside restroom: let flash decay completely to 0.0
	for i in range(10):
		ctrl.step(true, 0.2, false)
	check(ctrl.flash == 0.0, "rearm: eyes adapted, flash decayed to 0.0")

	# Short trip out to bright threshold (3s) -> still no flash
	ctrl.step(false, 3.0, false)
	ctrl.step(true, 0.016, false)
	check(ctrl.total_flashes == 1, "rearm: short trip produces no flash")

	# Second long dwell in actual dark cave (20s)
	ctrl.step(false, 20.0, true)
	check(ctrl.is_glare_ready(), "rearm: 20s dark dwell re-arms glare")

	# Second return to restroom
	var triggered2 := ctrl.step(true, 0.016, false)
	check(triggered2, "rearm: second return triggers second flash")
	check(ctrl.total_flashes == 2, "rearm: total flashes is now exactly 2")
	check(not ctrl.is_glare_ready(), "rearm: glare_ready disarmed again")

## Test 6: Title / load / death respawn reset -> 0 unintended flash
func _test_title_load_death_respawn_zero_flash() -> void:
	var ctrl := FPGlareController.new()

	# Initial construction represents game start / title screen:
	check(ctrl.was_inside, "init: was_inside defaults to true")
	check(ctrl.cave_time == 0.0, "init: cave_time defaults to 0.0")
	check(not ctrl.is_glare_ready(), "init: glare_ready defaults to false")
	check(ctrl.flash == 0.0, "init: flash defaults to 0.0")

	# Stepping on frame 1 in restroom:
	var t1 := ctrl.step(true, 0.016, false)
	check(not t1 and ctrl.flash == 0.0, "init: frame 1 inside restroom triggers no flash")

	# Simulate death outside: player was in dark cave for 15s, then dies
	ctrl.step(false, 15.0, true)
	# On death, main.die() respawns player at START_POS (inside) and calls reset(true):
	ctrl.reset(true)
	check(ctrl.was_inside, "death: was_inside reset to true")
	check(ctrl.cave_time == 0.0, "death: cave_time reset to 0.0")
	check(not ctrl.is_glare_ready(), "death: glare_ready reset to false")
	check(ctrl.flash == 0.0, "death: flash reset to 0.0")
	var t_respawn := ctrl.step(true, 0.016, false)
	check(not t_respawn and ctrl.flash == 0.0, "death: respawn in restroom triggers 0 flash")

	# Simulate save loading: load sets reset(true)
	ctrl.step(false, 25.0, true) # player was outside in dark
	check(ctrl.is_glare_ready(), "pre-load: armed before load")
	ctrl.reset(true) # loading game checkpoint resets state
	check(not ctrl.is_glare_ready(), "load: glare_ready cleared on load")
	var t_load := ctrl.step(true, 0.016, false)
	check(not t_load and ctrl.flash == 0.0, "load: loaded game triggers 0 flash")

## Test 7: Mutation M24 glare factor duration scaling (x2 duration)
func _test_m24_glare_duration_scaling() -> void:
	# Standard progression (glare_factor = 1.0)
	var ctrl_std := FPGlareController.new()
	ctrl_std.step(false, 20.0, true)
	ctrl_std.step(true, 0.0, false)
	ctrl_std.flash = 1.0
	ctrl_std.step(true, 1.0, false, 1.0)
	check(is_equal_approx(ctrl_std.flash, 0.2), "m24: standard flash after 1.0s is 0.2")

	# M24 Owl Eyes progression (glare_factor = 2.0)
	var ctrl_m24 := FPGlareController.new()
	ctrl_m24.step(false, 20.0, true)
	ctrl_m24.step(true, 0.0, false)
	ctrl_m24.flash = 1.0
	ctrl_m24.step(true, 1.0, false, 2.0)
	check(is_equal_approx(ctrl_m24.flash, 0.6), "m24: M24 flash after 1.0s is 0.6 (decays half as fast)")

	# Complete fade: standard reaches 0.0 at 1.25s, M24 at 2.5s (2x duration)
	ctrl_std.step(true, 0.3, false, 1.0)
	check(ctrl_std.flash == 0.0, "m24: standard flash reaches 0.0 in 1.25s")
	check(ctrl_m24.flash > 0.0, "m24: M24 flash still active past 1.25s")
	ctrl_m24.step(true, 1.5, false, 2.0)
	check(ctrl_m24.flash == 0.0, "m24: M24 flash reaches 0.0 at 2.5s (exact 2x duration)")

## Test 8: Spatial dark discrimination helper (is_dark_at)
func _test_is_dark_at_spatial_discrimination() -> void:
	# Inside restroom box -> always bright (false)
	check(not FPGlareController.is_dark_at(true, 0.0, 1.0, 0.5), "spatial: inside restroom is never dark")

	# Outside, but standing right at door frame / jamb / threshold (< 0.8m) -> bright (false)
	check(not FPGlareController.is_dark_at(false, 0.5, 0.0, 1.6), "spatial: door threshold frame (<0.8m) is bright")

	# Outside, in front of door within door_spill cone (< 2.5m, door open) -> bright (false)
	check(not FPGlareController.is_dark_at(false, 2.0, 1.0, 2.0), "spatial: open door spill cone (<2.5m) is bright")

	# Outside, shallow depth (< 2.2m) near restroom boundary -> bright (false)
	check(not FPGlareController.is_dark_at(false, 2.6, 0.0, 1.8), "spatial: shallow depth (<2.2m) is not dark cave")

	# Outside, deep in flesh cave (> 2.5m from door, depth > 2.2m) -> genuinely dark (true)
	check(FPGlareController.is_dark_at(false, 4.0, 1.0, 5.0), "spatial: deep flesh cave (>2.5m, depth 5m) is dark")
	check(FPGlareController.is_dark_at(false, 3.0, 0.0, 3.5), "spatial: cave with closed door is dark")

## Test 9: Integration with restroom bounding box logic
func _test_restroom_coordinate_integration() -> void:
	var ctrl := FPGlareController.new()
	var restroom_half := FPRestroom.HALF # Vector3(2.25, 1.3, 1.5)

	var in_room_pos := Vector3(0.0, 0.95, 0.0)
	var in_room := absf(in_room_pos.x) <= restroom_half.x and in_room_pos.y >= 0.0 and in_room_pos.y <= 2 * restroom_half.y and absf(in_room_pos.z) <= restroom_half.z
	check(in_room, "coords: START_POS is inside restroom")

	var door_threshold_pos := Vector3(0.0, 0.95, 1.6) # right at threshold outside door (HALF.z = 1.5)
	var dist_door := door_threshold_pos.distance_to(Vector3(0.0, 1.0, 1.5))
	var is_door_dark := FPGlareController.is_dark_at(false, dist_door, 1.0, 1.6)
	check(not is_door_dark, "coords: door threshold position is NOT dark")

	var deep_cave_pos := Vector3(0.0, 0.95, 5.0)
	var dist_cave := deep_cave_pos.distance_to(Vector3(0.0, 1.0, 1.5))
	var is_cave_dark := FPGlareController.is_dark_at(false, dist_cave, 1.0, 5.0)
	check(is_cave_dark, "coords: deep cave position (z=5.0) IS dark")

	# Spend 20s in deep cave:
	for i in range(20):
		ctrl.step(false, 1.0, is_cave_dark)
	check(ctrl.is_glare_ready(), "coords: 20s in deep cave arms glare")

	# Walk to door threshold:
	ctrl.step(false, 0.5, is_door_dark)
	check(ctrl.is_glare_ready(), "coords: walking through bright threshold retains arming")

	# Step inside room:
	var tr := ctrl.step(in_room, 0.016, false)
	check(tr and ctrl.total_flashes == 1, "coords: entering room triggers glare")
