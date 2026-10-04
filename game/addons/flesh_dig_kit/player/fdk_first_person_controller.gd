class_name FDKFirstPersonController
extends CharacterBody3D

## First-person controller for tunneling through organic terrain: mouse+keyboard
## look, keyboard-only look fallback (arrow keys), crouch to fit narrow
## tunnels, and a climb mode for digging straight up/down. Footstep camera
## bob is emitted as a signal so a game's camera rig (or the kit's own
## Camera3D child) can apply it; hand meshes are exposed as a HandsRig child
## for the eating animation to drive.

signal footstep_bob(offset: Vector3) ## call each physics frame; apply to camera local position
signal crouch_changed(is_crouching: bool)

@export var config: FDKPlayerConfig = FDKPlayerConfig.new()
@export var mouse_look_enabled: bool = true

var _yaw: float = 0.0
var _pitch: float = 0.0
var _is_crouching: bool = false
var _bob_time: float = 0.0
var _bob_weight: float = 0.0 ## 0 standing still .. 1 walking; eases so the view settles softly
var _pivot_base_y: float = 0.9
var last_bob_offset: Vector3 = Vector3.ZERO
var _climb_input: float = 0.0 ## -1 (down) .. 1 (up), from crouch+jump combo or dedicated climb keys
## The game sets this per frame: true only while standing inside flesh
## (terrain solid at the player), so fdk_jump only climbs there. Outside
## flesh (open room floor) it is false, so Space does nothing -- there is
## no gravity jump in this kit, only this climb axis (형님 2026-09-30: "점프"
## he meant was Space lifting the player off an ordinary floor).
var climb_enabled: bool = false

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var hands_rig: Node3D = $CameraPivot/Camera3D/HandsRig
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	FDKInputActions.register_defaults()
	if mouse_look_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if collision_shape != null and collision_shape.shape != null:
		collision_shape.shape = collision_shape.shape.duplicate()
	if _is_crouching:
		_apply_crouch_height()
	else:
		_apply_stand_height()
	if hands_rig != null and hands_rig.has_method("apply_bob"):
		footstep_bob.connect(hands_rig.apply_bob)

func _unhandled_input(event: InputEvent) -> void:
	if mouse_look_enabled and event is InputEventMouseMotion:
		_yaw -= event.relative.x * config.mouse_sensitivity
		_pitch -= event.relative.y * config.mouse_sensitivity * (-1.0 if config.invert_y else 1.0)
		_pitch = clampf(_pitch, deg_to_rad(-config.pitch_limit_deg), deg_to_rad(config.pitch_limit_deg))

func _physics_process(delta: float) -> void:
	_process_keyboard_look(delta)
	_process_crouch()
	_process_move_and_climb(delta)
	rotation.y = _yaw
	camera_pivot.rotation.x = _pitch
	_process_footstep_bob(delta)

func _process_keyboard_look(delta: float) -> void:
	var look_x := 0.0
	var look_y := 0.0
	if Input.is_action_pressed("fdk_look_left"):
		look_x += 1.0
	if Input.is_action_pressed("fdk_look_right"):
		look_x -= 1.0
	if Input.is_action_pressed("fdk_look_up"):
		look_y += 1.0
	if Input.is_action_pressed("fdk_look_down"):
		look_y -= 1.0
	if look_x != 0.0:
		_yaw += look_x * config.keyboard_look_speed * delta
	if look_y != 0.0:
		_pitch += look_y * config.keyboard_look_speed * delta * (-1.0 if config.invert_y else 1.0)
		_pitch = clampf(_pitch, deg_to_rad(-config.pitch_limit_deg), deg_to_rad(config.pitch_limit_deg))

func _process_crouch() -> void:
	var wants_crouch := Input.is_action_pressed("fdk_crouch")
	if wants_crouch:
		if not _is_crouching:
			_is_crouching = true
			crouch_changed.emit(_is_crouching)
			_apply_crouch_height()
	else:
		if _is_crouching:
			if can_stand():
				_is_crouching = false
				crouch_changed.emit(_is_crouching)
				_apply_stand_height()

## Returns true if there is enough vertical clearance above the crouched player to stand up.
func can_stand() -> bool:
	if not _is_crouching:
		return true
	if not is_inside_tree() or collision_shape == null:
		return true
	var delta_h := config.stand_height - config.crouch_height
	if delta_h <= 0.0:
		return true
	return not test_move(global_transform, Vector3(0.0, delta_h, 0.0))

func _apply_stand_height() -> void:
	if collision_shape != null and collision_shape.shape is CapsuleShape3D:
		(collision_shape.shape as CapsuleShape3D).height = config.stand_height
		collision_shape.position.y = 0.0
	_pivot_base_y = eye_pivot_y(false)
	camera_pivot.position.y = _pivot_base_y

func _apply_crouch_height() -> void:
	if collision_shape != null and collision_shape.shape is CapsuleShape3D:
		(collision_shape.shape as CapsuleShape3D).height = config.crouch_height
		collision_shape.position.y = - (config.stand_height - config.crouch_height) * 0.5
	_pivot_base_y = eye_pivot_y(true)
	camera_pivot.position.y = _pivot_base_y

## Camera pivot height over the capsule centre: eye_height above the feet,
## scaled down with the capsule when crouching.
func eye_pivot_y(crouched: bool) -> float:
	var h := config.crouch_height if crouched else config.stand_height
	var feet_y := -config.stand_height * 0.5
	var eye_above_feet := h * (config.eye_height / config.stand_height)
	return feet_y + eye_above_feet

## Returns feet position in world space.
func get_feet_position() -> Vector3:
	var offset := 0.0
	if collision_shape != null and collision_shape.shape is CapsuleShape3D:
		offset = collision_shape.position.y - (collision_shape.shape as CapsuleShape3D).height * 0.5
	return global_transform * Vector3(0.0, offset, 0.0)

func _process_move_and_climb(delta: float) -> void:
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("fdk_move_forward"):
		input_dir.y -= 1.0
	if Input.is_action_pressed("fdk_move_back"):
		input_dir.y += 1.0
	if Input.is_action_pressed("fdk_move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("fdk_move_right"):
		input_dir.x += 1.0
	input_dir = input_dir.normalized()

	var speed: float = config.crouch_speed if _is_crouching else config.walk_speed
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	var horizontal: Vector3 = (forward * -input_dir.y + right * input_dir.x) * speed

	# Climb mode: digging straight up/down through flesh. Jump = up (when climb_enabled),
	# crouch + eat = down (excavation descent input). Ctrl alone is purely posture.
	_climb_input = 0.0
	if Input.is_action_pressed("fdk_jump") and climb_enabled:
		_climb_input += 1.0
	if Input.is_action_pressed("fdk_crouch") and Input.is_action_pressed("fdk_eat"):
		_climb_input -= 1.0

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if _climb_input != 0.0:
		velocity.y = _climb_input * config.climb_speed
	elif not is_on_floor():
		velocity.y = -config.climb_speed
	else:
		velocity.y = 0.0

	move_and_slide()

func _process_footstep_bob(delta: float) -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var moving := horizontal_speed > 0.05 and is_on_floor()
	if moving:
		_bob_time += delta * config.bob_frequency * (horizontal_speed / max(config.walk_speed, 0.01))
	_bob_weight = move_toward(_bob_weight, 1.0 if moving else 0.0, delta * config.bob_ease_speed)
	var bob_offset := bob_offset_at(_bob_time, _bob_weight)
	last_bob_offset = bob_offset
	_apply_head_bob(bob_offset)
	footstep_bob.emit(bob_offset)

## Head bob for a bob phase and walk weight. y dips once per step (its
## trough is where fdk_audio_director plays the footstep); x sways to one
## side per step, so a full left-right cycle spans two steps.
func bob_offset_at(phase: float, weight: float) -> Vector3:
	return Vector3(sin(phase * 0.5) * config.bob_sway * weight, sin(phase) * config.bob_amplitude * weight, 0.0)

## Moves the camera pivot (not the camera, which hand motions own).
func _apply_head_bob(offset: Vector3) -> void:
	if not config.head_bob_enabled:
		offset = Vector3.ZERO
	camera_pivot.position = Vector3(offset.x, _pivot_base_y + offset.y, 0.0)
	camera_pivot.rotation.z = -offset.x * config.bob_roll

## Returns a world-space ray (origin, direction) along the camera's look
## direction, for the game/kit's eat interaction to raycast with.
func get_look_ray() -> Array:
	var origin: Vector3 = camera.global_transform.origin
	var direction: Vector3 = -camera.global_transform.basis.z
	return [origin, direction]
