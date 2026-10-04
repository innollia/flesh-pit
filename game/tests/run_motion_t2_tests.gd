extends SceneTree

# NOTE: Bathtub collision integration and normal Main full render checks are deferred to subsequent T9/T10.

var passed := 0
var failed := 0
var _frame := 0
var _step := 0
var _cycle := 0
const TOTAL_CYCLES := 100

var _floor: StaticBody3D
var _ceiling: StaticBody3D
var _terrain: FDKTerrainField
var _ctrl: FDKFirstPersonController

var _stand_feet_y: float = 0.0
var _stand_eye_y: float = 0.0
var _pre_jump_y: float = 0.0
var _pre_terrain_dig_y: float = 0.0
var _hold_wait := 0

func _assert(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", message)

func _feet_y() -> float:
	if _ctrl.has_method("get_feet_position"):
		return _ctrl.get_feet_position().y
	var offset := _ctrl.collision_shape.position.y - (_ctrl.collision_shape.shape as CapsuleShape3D).height * 0.5
	return _ctrl.global_position.y + offset

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
	_ceiling.position = Vector3(0, 50.0, 0)
	_ceiling.add_child(cshape)
	get_root().add_child(_ceiling)

	# Instantiate FDKFirstPersonController
	var pscene: PackedScene = load("res://addons/flesh_dig_kit/player/fdk_first_person_controller.tscn")
	_ctrl = pscene.instantiate()
	_ctrl.name = "FDKFirstPersonController"
	_ctrl.mouse_look_enabled = false
	_ctrl.climb_enabled = false
	get_root().add_child(_ctrl)
	_ctrl.position = Vector3(0, 0.9, 0)

func _physics_process(_delta: float) -> bool:
	_frame += 1

	match _step:
		0:
			# Settle on floor
			if _frame >= 5:
				_stand_feet_y = _feet_y()
				_stand_eye_y = _ctrl.camera_pivot.global_position.y
				_assert(is_equal_approx(_stand_feet_y, 0.0), "Standing feet y starts at floor level (got %f)" % _stand_feet_y)
				_assert(is_equal_approx(_stand_eye_y, 1.6), "Standing eye y is 1.6 above floor (got %f)" % _stand_eye_y)
				print("--- Test 1: Grounded Crouch & 100-cycle Posture Invariance ---")
				_step = 1

		1:
			# 100 crouch/stand cycles across actual engine physics frames
			if not _ctrl._is_crouching:
				Input.action_press("fdk_crouch")
			else:
				var crouch_feet := _feet_y()
				var crouch_eye := _ctrl.camera_pivot.global_position.y
				_assert(is_equal_approx(crouch_feet, _stand_feet_y), "Crouch feet y matches stand feet y (cycle %d)" % _cycle)
				_assert(is_equal_approx(crouch_eye, _stand_eye_y - 0.8), "Crouch eye y lowered by 0.8m proportionally (cycle %d)" % _cycle)
				Input.action_release("fdk_crouch")
				_cycle += 1
				if _cycle >= TOTAL_CYCLES:
					_hold_wait = 0
					_step = 2

		2:
			# Verify posture after 100 cycles
			_hold_wait += 1
			if _hold_wait >= 2:
				_assert(not _ctrl._is_crouching, "Controller standing after 100 cycles")
				_assert(is_equal_approx(_feet_y(), _stand_feet_y), "Feet y invariant after 100 cycles (drift = %f)" % absf(_feet_y() - _stand_feet_y))
				_assert(is_equal_approx(_ctrl.camera_pivot.global_position.y, _stand_eye_y), "Eye y invariant after 100 cycles")
				# Setup low ceiling at y = 1.3 (underside at 1.2m)
				print("--- Test 2: Low Passage / Ceiling Stand Obstruction Hold (서기 보류) ---")
				_ceiling.position = Vector3(0, 1.3, 0)
				_ceiling.force_update_transform()
				Input.action_press("fdk_crouch")
				_hold_wait = 0
				_step = 3

		3:
			# Crouch under ceiling
			_hold_wait += 1
			if _hold_wait >= 2:
				_assert(_ctrl._is_crouching, "Crouched under low ceiling")
				# Release crouch input while under ceiling
				Input.action_release("fdk_crouch")
				_hold_wait = 0
				_step = 4

		4:
			# Verify stand hold under obstacle
			_hold_wait += 1
			if _hold_wait >= 3:
				_assert(_ctrl._is_crouching, "Holds crouch posture under low ceiling (서기 보류)")
				_assert(not _ctrl.can_stand(), "can_stand() is false under low ceiling")
				_assert(is_equal_approx((_ctrl.collision_shape.shape as CapsuleShape3D).height, _ctrl.config.crouch_height), "Height remains crouch_height")
				print("--- Test 3: Clear Ceiling Obstacle & Automatic Stand ---")
				_ceiling.position = Vector3(0, 50.0, 0)
				_ceiling.force_update_transform()
				_hold_wait = 0
				_step = 5

		5:
			# Verify automatic stand after ceiling removal
			_hold_wait += 1
			if _hold_wait >= 3:
				_assert(not _ctrl._is_crouching, "Player automatically stands up once obstacle removed")
				_assert(is_equal_approx((_ctrl.collision_shape.shape as CapsuleShape3D).height, _ctrl.config.stand_height), "Height restored to stand_height")
				_assert(is_equal_approx(_feet_y(), _stand_feet_y), "Feet y remains at floor level after standing")
				print("--- Test 4: Space on Normal Floor Does Not Jump ---")
				_ctrl.climb_enabled = false
				_pre_jump_y = _ctrl.global_position.y
				Input.action_press("fdk_jump")
				_hold_wait = 0
				_step = 6

		6:
			# Verify Space on normal floor does not jump
			_hold_wait += 1
			if _hold_wait >= 3:
				_assert(_ctrl.velocity.y <= 0.0, "fdk_jump does not jump off normal floor (velocity.y <= 0)")
				_assert(is_equal_approx(_ctrl.global_position.y, _pre_jump_y), "Position y unchanged by Space on normal floor")
				Input.action_release("fdk_jump")
				print("--- Test 5: Excavation Descent Inputs (Ctrl+Eat vs Ctrl alone) ---")
				# Move floor away to test descent inputs
				_floor.position = Vector3(0, -100.0, 0)
				_floor.force_update_transform()
				_hold_wait = 0
				_step = 7

		7:
			_hold_wait += 1
			if _hold_wait >= 1:
				# Ctrl alone: purely posture, no climb_input
				Input.action_press("fdk_crouch")
				_hold_wait = 0
				_step = 8

		8:
			_hold_wait += 1
			if _hold_wait >= 1:
				_assert(_ctrl._climb_input == 0.0, "Ctrl alone is purely posture: climb_input remains 0.0")
				# Now press eat together with crouch (Ctrl + Eat)
				Input.action_press("fdk_eat")
				_hold_wait = 0
				_step = 9

		9:
			_hold_wait += 1
			if _hold_wait >= 1:
				_assert(_ctrl._climb_input == -1.0, "Ctrl + Eat activates excavation descent climb_input (-1.0)")
				_assert(_ctrl.velocity.y <= -_ctrl.config.climb_speed + 0.01, "Downward velocity equals climb_speed (%.2f)" % _ctrl.velocity.y)
				Input.action_release("fdk_crouch")
				Input.action_release("fdk_eat")
				print("--- Test 6: Actual FDKTerrainField Excavation & Descent Grounding ---")
				# Set up solid terrain slab under player
				_terrain = FDKTerrainField.new()
				_terrain.config = FDKTerrainConfig.new()
				get_root().add_child(_terrain)
				_terrain.fill_box_uniform(AABB(Vector3(-2, -2, -2), Vector3(4, 2, 4)), 1.0, 0)
				_terrain.remesh_all()
				_ctrl.position = Vector3(0, 0.9, 0)
				_ctrl.velocity = Vector3.ZERO
				_hold_wait = 0
				_step = 10

		10:
			# Settle on terrain slab
			_hold_wait += 1
			if _hold_wait >= 5:
				_assert(_ctrl.is_on_floor(), "Player is grounded on top of solid FDKTerrainField")
				_pre_terrain_dig_y = _ctrl.global_position.y
				# Dig a pit directly under the player in the terrain
				_terrain.dig_at(Vector3(0, -0.5, 0), 1.0)
				_terrain.remesh_all()
				_hold_wait = 0
				_step = 11

		11:
			# Wait for natural descent into dug cavity and re-grounding
			_hold_wait += 1
			if _hold_wait >= 15:
				_assert(_ctrl.global_position.y < _pre_terrain_dig_y - 0.15, "Player descended into excavated terrain cavity (from %.3f to %.3f)" % [_pre_terrain_dig_y, _ctrl.global_position.y])
				_assert(_ctrl.is_on_floor(), "Player re-grounded on cavity floor")
				_assert(_ctrl.velocity.y == 0.0, "Vertical velocity settled to 0.0 after grounding")
				_step = 12

		12:
			print("Scope note: Bathtub collision integration and normal Main full render checks are deferred to subsequent T9/T10.")
			print("--- %d passed, %d failed ---" % [passed, failed])
			quit(1 if failed > 0 else 0)
			return true

	return false
