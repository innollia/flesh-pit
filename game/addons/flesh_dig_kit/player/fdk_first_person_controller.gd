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

## Optional host terrain boundary; standalone controllers retain normal physics.
## Receives the requested per-frame motion, returns a permitted motion.
var movement_filter: Callable
## Multiplies walking/crouching speed only (e.g. being pressed by flesh);
## the view bob keeps reading config.walk_speed, so it never speeds up.
var move_speed_scale: float = 1.0
## Squeezing through (config.step_height/squeeze_*): where the body would
## bump, it steps over a low lip, else ducks its head (lower capsule) or
## twists its hips (thinner capsule), slower the more it gives; it relaxes
## back as room returns. Only when even the tightest body has no room is the
## motion refused. The capsule really changes, so collision, the host's
## movement_filter and any crush check all see the same body.
var duck: float = 0.0 ## 0..1 lower than the requested stand/crouch height
var twist: float = 0.0 ## 0..1 hips turned sideways: a thinner capsule
## The body's own radius (a game sets it, e.g. mutations); -1 = scene's.
var natural_radius: float = -1.0
## Optional host check that the current capsule fits where it stands
## (e.g. not inside solid terrain). Defaults to a physics overlap query.
var shape_fits: Callable
var _rise_left: float = 0.0 ## metres still to climb into a found opening
var _hold_t: float = 0.0 ## after climbing up: stay level while moving onto the ledge
var last_posture_us: int = 0 ## cost of the last posture update (measurements)
var _wall_t: float = 0.0 ## a fruitless search waits this long before the next
var _relax_t: float = 0.0
const RELAX_EVERY := 0.1 ## the body checks for room to straighten up this often
## Share of the asked horizontal step the real move made last frame (1 = all).
var _last_ratio: float = 1.0
var _fit_t: float = 0.0

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
		if natural_radius < 0.0 and collision_shape.shape is CapsuleShape3D:
			natural_radius = (collision_shape.shape as CapsuleShape3D).radius
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
	_apply_posture()

func _apply_crouch_height() -> void:
	_apply_posture()

## 0..1: how much the body is giving way right now.
func squeeze() -> float:
	return maxf(duck, twist)

## Capsule height for the requested posture with the current duck.
func body_height() -> float:
	var asked := config.crouch_height if _is_crouching else config.stand_height
	return lerpf(asked, minf(asked, config.squeeze_min_height), duck)

func body_radius() -> float:
	var r := natural_radius if natural_radius > 0.0 else 0.35
	return r * lerpf(1.0, config.squeeze_min_radius_scale, twist)

## Sets the body's own radius (e.g. a mutation) and re-applies the posture.
func set_natural_radius(r: float) -> void:
	natural_radius = r
	_apply_posture()

## Sets the real capsule (feet stay put) and the eye from crouch/duck/twist.
func _apply_posture() -> void:
	var h := body_height()
	if collision_shape != null and collision_shape.shape is CapsuleShape3D:
		var cap := collision_shape.shape as CapsuleShape3D
		cap.radius = body_radius()
		cap.height = maxf(h, cap.radius * 2.0 + 0.01)
		collision_shape.position.y = - (config.stand_height - cap.height) * 0.5
		h = cap.height
	var feet_y := -config.stand_height * 0.5
	_pivot_base_y = feet_y + h * (config.eye_height / config.stand_height)
	if camera_pivot != null:
		camera_pivot.position.y = _pivot_base_y

## Does the current capsule fit where it stands?
func _fits_here() -> bool:
	if shape_fits.is_valid():
		return bool(shape_fits.call())
	if not is_inside_tree() or collision_shape == null:
		return true
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = collision_shape.shape
	q.transform = collision_shape.global_transform
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

## Would this horizontal motion get (mostly: `need` of it) through from here?
func _motion_ok(motion: Vector3, need: float = 0.6) -> bool:
	var allowed := motion
	if movement_filter.is_valid():
		allowed = movement_filter.call(motion)
		allowed.y = 0.0
	if allowed.length() < motion.length() * need:
		return false
	return not test_move(global_transform, allowed * 0.9)

## A squeezed body crawls on even when only this share of a step gets past.
const SQUEEZE_NEED := 0.35

## Tries a posture; keeps it when it fits here (and lets `motion` through).
func _try_posture(d: float, t: float, motion: Vector3 = Vector3.ZERO) -> bool:
	var keep := Vector2(duck, twist)
	duck = d
	twist = t
	_apply_posture()
	if _fits_here() and (motion.is_zero_approx() or _motion_ok(motion, SQUEEZE_NEED)):
		return true
	duck = keep.x
	twist = keep.y
	_apply_posture()
	return false

## How fast the body gives way (per second) when the space ahead tightens.
const SQUEEZE_IN_SPEED := 4.0

## The space around the body, felt with a few rays against the real
## collision (cheap; the capsule checks stay the authority), here and at a
## near and a farther point ahead along `dir`:
##   rise    highest floor ahead over the feet (0 = level)
##   ceiling lowest free height over the floor, here and ahead
##   width   narrowest free width across the way at the farther point
##           ahead (knee, hip, chest height)
func probe_space(dir: Vector3) -> Dictionary:
	var out := {"rise": 0.0, "ceiling": config.stand_height + 0.2, "width": 9.0}
	if not is_inside_tree():
		return out
	var space := get_world_3d().direct_space_state
	var feet := global_position - Vector3.UP * config.stand_height * 0.5
	var r_nat := natural_radius if natural_radius > 0.0 else 0.35
	var flat := Vector3(dir.x, 0.0, dir.z)
	var moving := flat.length() > 0.001
	flat = flat.normalized() if moving else -global_transform.basis.z
	var top := config.stand_height + 0.2
	var points: Array = [[feet, 0.0]]
	if moving:
		for d in [r_nat * 0.5 + 0.1, r_nat + 0.25]:
			var at: Vector3 = feet + flat * d
			var floor_h := 0.0
			var hit := _ray(space, at + Vector3.UP * (config.climb_reach + 0.25), at + Vector3.DOWN * 0.3)
			if not hit.is_empty():
				floor_h = clampf(float(hit.position.y) - feet.y, 0.0, config.climb_reach + 0.25)
			points.append([at, floor_h])
			out["rise"] = maxf(float(out["rise"]), floor_h)
	var side := flat.cross(Vector3.UP).normalized()
	var ceiling := top
	var width := 9.0
	for pt in points:
		var base: Vector3 = pt[0] + Vector3.UP * (float(pt[1]) + 0.25)
		var hit := _ray(space, base, base + Vector3.UP * top)
		if not hit.is_empty():
			ceiling = minf(ceiling, float(hit.position.y) - (feet.y + float(pt[1])))
		if pt != points[points.size() - 1]:
			continue # across the way only at the farther point: a near point
			# sits inside the body's own radius and would read the wall it is
			# brushing as a narrow gap
		for h in [0.35, 0.7, 1.1]:
			var b: Vector3 = pt[0] + Vector3.UP * (float(pt[1]) + h)
			var reach := r_nat + 0.6
			var l := _ray(space, b, b - side * reach)
			var r := _ray(space, b, b + side * reach)
			var wl: float = b.distance_to(l.position) if not l.is_empty() else reach
			var wr: float = b.distance_to(r.position) if not r.is_empty() else reach
			width = minf(width, wl + wr)
	out["ceiling"] = ceiling
	out["width"] = width
	return out

func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, collision_mask, [get_rid()])
	return space.intersect_ray(q)

## Duck and twist the felt space asks for (0..1 each).
func _posture_for(space: Dictionary) -> Vector2:
	var asked := config.crouch_height if _is_crouching else config.stand_height
	var low := minf(asked, config.squeeze_min_height)
	var need_h := clampf(float(space["ceiling"]) - 0.05, low, asked)
	var d := 0.0 if asked <= low + 0.001 else (asked - need_h) / (asked - low)
	var r_nat := natural_radius if natural_radius > 0.0 else 0.35
	var r_min := r_nat * config.squeeze_min_radius_scale
	var need_r := clampf(float(space["width"]) * 0.5 - 0.03, r_min, r_nat)
	var t := 0.0 if r_nat <= r_min + 0.0001 else (r_nat - need_r) / (r_nat - r_min)
	return Vector2(clampf(d, 0.0, 1.0), clampf(t, 0.0, 1.0))

## Gives the body back its room a little at a time, the hips and the head
## each on their own (a low ceiling keeps the duck but frees the hips).
func _relax_toward(target: Vector2, delta: float) -> void:
	var step := config.squeeze_relax_speed * delta
	if twist > target.y:
		_try_posture(duck, maxf(target.y, twist - step))
	if duck > target.x:
		_try_posture(maxf(target.x, duck - step), twist)

## Per physics frame: feel the space ahead (or here), squeeze toward what it
## asks, step or crawl up onto a raised floor when the way is blocked, give
## way where flesh closed in on the body, relax where there is room.
func _update_posture(motion: Vector3, delta: float) -> void:
	if not is_inside_tree() or collision_shape == null:
		return
	var started := Time.get_ticks_usec()
	_update_posture_inner(motion, delta)
	last_posture_us = Time.get_ticks_usec() - started

func _update_posture_inner(motion: Vector3, delta: float) -> void:
	_wall_t = maxf(0.0, _wall_t - delta)
	_relax_t -= delta
	var moving := not motion.is_zero_approx()
	# how the real step went last frame (no extra movement check per frame)
	var blocked := moving and _last_ratio < 0.15
	var through := not moving or _last_ratio >= 0.6
	var space := probe_space(motion)
	var want := _posture_for(space)
	# squeeze in toward what the space asks (each change must fit)
	var step := SQUEEZE_IN_SPEED * delta
	if want.x > duck + 0.01 or want.y > twist + 0.01:
		var d := minf(want.x, duck + step) if want.x > duck else duck
		var t := minf(want.y, twist + step) if want.y > twist else twist
		if not _try_posture(d, t):
			_try_posture(maxf(duck, want.x), maxf(twist, want.y))
	elif through and _relax_t <= 0.0 and squeeze() > 0.0:
		_relax_t = RELAX_EVERY
		_relax_toward(want, RELAX_EVERY)
	if blocked and _rise_left <= 0.0 and _wall_t <= 0.0:
		# truly blocked (not sliding along a wall) where the rays saw room: a
		# lip or a pinch they missed. The tightest body first, so a real wall
		# costs one check; then the least of it that still gets through.
		var squeezed := false
		if Vector2(duck, twist) != Vector2(1, 1) and _try_posture(1.0, 1.0, motion):
			squeezed = true
			for pose in [Vector2(minf(1.0, maxf(duck, want.x) + 0.5), 0.0), Vector2(0.0, minf(1.0, maxf(twist, want.y) + 0.5))]:
				if _try_posture(pose.x, pose.y, motion):
					break
		if not squeezed:
			# a raised floor ahead: climb onto it (no Space), low enough to fit
			# (the rays run down the middle; a lip off to one side can stand a
			# little higher, so a few heights from there up are tried)
			var rise: float = space["rise"]
			if rise > 0.04 and rise <= config.climb_reach + 0.05 and float(space["ceiling"]) >= config.squeeze_min_height and (is_on_floor() or _hold_t > 0.0):
				for h: float in [rise + 0.05, rise + 0.2, rise + 0.4]:
					if h > config.climb_reach + 0.05:
						break
					var up: Vector3 = Vector3.UP * h
					if test_move(global_transform, up):
						break # the ceiling: higher is blocked too
					# only an opening that really goes on from up there (not the
					# curved foot of a dead-end wall)
					var keep := global_position
					global_position = keep + up
					var ahead := motion.normalized() * maxf(motion.length(), 0.3)
					var goes_on := _fits_here() and _motion_ok(ahead)
					global_position = keep
					if goes_on:
						_rise_left = h
						break
			if _rise_left <= 0.0:
				_wall_t = 0.25 # really stuck here: do not search again every frame
	# flesh pressing on the body: give way until it fits again
	_fit_t -= delta
	if _fit_t <= 0.0:
		_fit_t = 0.15
		if not _fits_here():
			for pose in [Vector2(maxf(duck, 0.5), twist), Vector2(duck, maxf(twist, 0.5)), Vector2(1, twist), Vector2(duck, 1), Vector2(1, 1)]:
				if (pose.x > duck or pose.y > twist) and _try_posture(pose.x, pose.y):
					break

## Camera pivot height over the capsule centre: eye_height above the feet,
## scaled down with the capsule when crouching.
func eye_pivot_y(crouched: bool) -> float:
	var h := config.crouch_height if crouched else config.stand_height
	var feet_y := -config.stand_height * 0.5
	var eye_above_feet := h * (config.eye_height / config.stand_height)
	return feet_y + eye_above_feet

## Returns feet position in world space.
func get_feet_position() -> Vector3:
	if collision_shape != null and collision_shape.shape is CapsuleShape3D:
		var capsule := collision_shape.shape as CapsuleShape3D
		var axis := collision_shape.global_basis.y.normalized()
		var extent := capsule.radius + (capsule.height * 0.5 - capsule.radius) * absf(axis.y)
		return collision_shape.global_position - Vector3.UP * extent
	return global_position

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

	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	var wish: Vector3 = forward * -input_dir.y + right * input_dir.x
	var base_speed: float = (config.crouch_speed if _is_crouching else config.walk_speed) * move_speed_scale
	_update_posture(wish * base_speed * delta, delta)
	var speed: float = base_speed * lerpf(1.0, config.squeeze_speed_min, squeeze())
	var horizontal: Vector3 = wish * speed

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
		if _climb_input > 0.0 and config.climb_up_speed > 0.0:
			velocity.y = config.climb_up_speed
	elif _rise_left > 0.0:
		# stepping or crawling up into the opening found ahead
		velocity.y = config.climb_speed
		_rise_left = maxf(0.0, _rise_left - config.climb_speed * delta)
		if _rise_left <= 0.0:
			_hold_t = 0.5
	elif _hold_t > 0.0 and not is_on_floor():
		velocity.y = 0.0
		_hold_t -= delta
	elif not is_on_floor():
		velocity.y = -config.climb_speed
	else:
		velocity.y = 0.0

	if movement_filter.is_valid() and delta > 0.0:
		velocity = movement_filter.call(velocity * delta) / delta
	var before := global_position
	var asked := Vector2(horizontal.x, horizontal.z).length() * delta
	move_and_slide()
	if asked > 0.0005:
		var moved := global_position - before
		_last_ratio = clampf(Vector2(moved.x, moved.z).length() / asked, 0.0, 1.0)
	else:
		_last_ratio = 1.0

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
	# a twisted body sways and rolls its head from side to side as it worms on
	var worm := sin(_bob_time * 0.5) * twist * _bob_weight
	camera_pivot.position = Vector3(offset.x + worm * 0.035, _pivot_base_y + offset.y, 0.0)
	camera_pivot.rotation.z = -offset.x * config.bob_roll - worm * 0.1

## Returns a world-space ray (origin, direction) along the camera's look
## direction, for the game/kit's eat interaction to raycast with.
func get_look_ray() -> Array:
	var origin: Vector3 = camera.global_transform.origin
	var direction: Vector3 = -camera.global_transform.basis.z
	return [origin, direction]
