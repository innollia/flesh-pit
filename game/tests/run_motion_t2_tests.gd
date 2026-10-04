extends SceneTree

var passed := 0
var failed := 0
var _frame := 0
var _phase := 0

var _floor: StaticBody3D
var _ceiling: StaticBody3D
var _ctrl: FDKFirstPersonController

func _assert(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", message)

func _init() -> void:
	print("=== FDK T2 Motion Tests ===")
	FDKInputActions.register_defaults()

	# Create physics floor at y = 0 (top of floor box is at y = 0.0)
	_floor = StaticBody3D.new()
	_floor.name = "Floor"
	var fshape := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(20, 0.2, 20)
	fshape.shape = fbox
	_floor.position = Vector3(0, -0.1, 0)
	_floor.add_child(fshape)
	get_root().add_child(_floor)

	# Create movable ceiling (initial position high above)
	_ceiling = StaticBody3D.new()
	_ceiling.name = "Ceiling"
	var cshape := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(20, 0.2, 20)
	cshape.shape = cbox
	_ceiling.position = Vector3(0, 10.0, 0)
	_ceiling.add_child(cshape)
	get_root().add_child(_ceiling)

	# Instantiate FDKFirstPersonController
	var pscene: PackedScene = load("res://addons/flesh_dig_kit/player/fdk_first_person_controller.tscn")
	_ctrl = pscene.instantiate()
	_ctrl.name = "FDKFirstPersonController"
	_ctrl.mouse_look_enabled = false
	get_root().add_child(_ctrl)
	_ctrl.position = Vector3(0, 0.9, 0)

func _physics_process(delta: float) -> bool:
	_frame += 1

	# Settle on floor initially
	if _frame < 5:
		return false

	match _phase:
		0:
			_test_grounded_crouch()
			_phase = 1
			return false
		1:
			_setup_ceiling_test()
			_phase = 2
			return false
		2:
			_test_stand_obstruction()
			_phase = 3
			return false
		3:
			_test_clear_obstruction()
			_phase = 4
			return false
		4:
			_test_descent_and_jump_gate()
			_phase = 5
			return false
		5:
			_finish()
			return true

	return false

func _feet_y() -> float:
	if _ctrl.has_method("get_feet_position"):
		return _ctrl.get_feet_position().y
	var offset := _ctrl.collision_shape.position.y - (_ctrl.collision_shape.shape as CapsuleShape3D).height * 0.5
	return _ctrl.global_position.y + offset

func _test_grounded_crouch() -> void:
	print("--- Test 1: Grounded Crouch & Feet Position Stability ---")
	var stand_feet_y := _feet_y()
	_assert(is_equal_approx(stand_feet_y, 0.0), "Standing feet y is at floor level (expected 0.0, got %f)" % stand_feet_y)
	
	# Perform crouch
	Input.action_press("fdk_crouch")
	_ctrl._physics_process(1.0 / 60.0)
	
	var crouch_feet_y := _feet_y()
	_assert(_ctrl._is_crouching, "Controller state is crouching")
	_assert(is_equal_approx((_ctrl.collision_shape.shape as CapsuleShape3D).height, _ctrl.config.crouch_height), "Capsule height is crouch_height")
	_assert(is_equal_approx(stand_feet_y, crouch_feet_y), "Crouching feet y matches standing feet y (stand: %f, crouch: %f)" % [stand_feet_y, crouch_feet_y])

	# 100 crouch/stand toggle stability test
	for i in range(100):
		Input.action_press("fdk_crouch")
		_ctrl._physics_process(1.0 / 60.0)
		Input.action_release("fdk_crouch")
		_ctrl._physics_process(1.0 / 60.0)

	var cycled_feet_y := _feet_y()
	_assert(is_equal_approx(stand_feet_y, cycled_feet_y), "100 crouch/stand cycles keep identical feet y (drift = %f)" % absf(cycled_feet_y - stand_feet_y))
	_assert(not _ctrl._is_crouching, "Controller back to standing after releases")

func _setup_ceiling_test() -> void:
	# Put ceiling at y = 1.3, so bottom of ceiling is 1.3 - 0.1 = 1.2m
	# Stand height is 1.8m, crouch height is 0.9m.
	_ceiling.position = Vector3(0, 1.3, 0)
	_ceiling.force_update_transform()
	# Crouch under ceiling
	Input.action_press("fdk_crouch")
	_ctrl._physics_process(1.0 / 60.0)

func _test_stand_obstruction() -> void:
	print("--- Test 2: Uncrouch Obstruction Hold (서기 보류) ---")
	_assert(_ctrl._is_crouching, "Player is currently crouched under 1.2m ceiling")

	# Release crouch input while under 1.2m ceiling
	Input.action_release("fdk_crouch")
	_ctrl._physics_process(1.0 / 60.0)

	_assert(_ctrl._is_crouching, "Player holds crouch due to overhead ceiling obstacle (서기 보류)")
	_assert(is_equal_approx((_ctrl.collision_shape.shape as CapsuleShape3D).height, _ctrl.config.crouch_height), "Capsule height remains crouch_height while held")
	if _ctrl.has_method("can_stand"):
		_assert(not _ctrl.can_stand(), "can_stand() reports false under low ceiling")

func _test_clear_obstruction() -> void:
	print("--- Test 3: Stand After Obstacle Removed ---")
	# Remove ceiling (lift high up)
	_ceiling.position = Vector3(0, 50.0, 0)
	_ceiling.force_update_transform()

	# Next physics tick: player should automatically stand up since fdk_crouch is released
	_ctrl._physics_process(1.0 / 60.0)

	_assert(not _ctrl._is_crouching, "Player stands up automatically once overhead obstacle is removed")
	_assert(is_equal_approx((_ctrl.collision_shape.shape as CapsuleShape3D).height, _ctrl.config.stand_height), "Capsule height restored to stand_height")
	var feet_after := _feet_y()
	_assert(is_equal_approx(feet_after, 0.0), "Feet y remains at floor level after standing up")

func _test_descent_and_jump_gate() -> void:
	print("--- Test 4: Descent In Empty Space & Jump Gate ---")
	# 4A: Jump gate on floor when climb_enabled is false
	_ctrl.climb_enabled = false
	Input.action_press("fdk_jump")
	_ctrl._physics_process(1.0 / 60.0)
	_assert(_ctrl.velocity.y <= 0.0, "fdk_jump does not jump off normal floor (velocity.y <= 0)")
	Input.action_release("fdk_jump")

	# Move floor away to test descent in empty space / vertical digging
	_floor.position = Vector3(0, -100.0, 0)
	_floor.force_update_transform()

	# 4B: Descent input (fdk_crouch + fdk_eat)
	Input.action_press("fdk_crouch")
	Input.action_press("fdk_eat")
	_ctrl._physics_process(1.0 / 60.0)
	_assert(_ctrl._climb_input < -0.9, "fdk_crouch + fdk_eat sets downward climb_input")
	_assert(_ctrl.velocity.y < -0.1, "fdk_crouch + fdk_eat produces downward descent velocity (%.2f)" % _ctrl.velocity.y)
	Input.action_release("fdk_crouch")
	Input.action_release("fdk_eat")

	# 4C: Descent input when climb_enabled (climbing down with fdk_crouch)
	_ctrl.climb_enabled = true
	Input.action_press("fdk_crouch")
	_ctrl._physics_process(1.0 / 60.0)
	_assert(_ctrl._climb_input < -0.9, "fdk_crouch while climb_enabled sets downward climb_input")
	_assert(_ctrl.velocity.y < -0.1, "fdk_crouch while climb_enabled produces downward descent velocity (%.2f)" % _ctrl.velocity.y)
	Input.action_release("fdk_crouch")
	_ctrl.climb_enabled = false

	# 4D: Natural descent / gravity into empty space below
	# Let multiple frames process without any climb inputs
	var initial_y := _ctrl.global_position.y
	for i in range(10):
		_ctrl._physics_process(1.0 / 60.0)
	_assert(_ctrl.global_position.y < initial_y - 0.05, "Controller falls into empty space below (dropped from %.3f to %.3f)" % [initial_y, _ctrl.global_position.y])
	_assert(_ctrl.velocity.y < -0.1, "Downward velocity accumulated while in mid-air (%.2f)" % _ctrl.velocity.y)

func _finish() -> void:
	print("--- %d passed, %d failed ---" % [passed, failed])
	quit(1 if failed > 0 else 0)
