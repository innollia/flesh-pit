extends SceneTree

## Squeezing through flesh and stepping out of the door (2026-10-19 play):
## the body steps or crawls up into openings, ducks under low ceilings and
## twists through narrow gaps without Space, slowing as it gives way; it is
## still stopped by a real wall; the legs and the crisis cues follow; the eye
## lamp no longer blows the view out at the doorway. Walking never changes
## the terrain (eaten = removed stays the only way flesh disappears).

var m: Node3D
var passed := 0
var failed := 0

func _init() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	root.add_child(m)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func carve(base: Vector3, x0: int, x1: int, y0: int, y1: int, z0: int, z1: int) -> void:
	for z in range(z0, z1):
		for y in range(y0, y1):
			for x in range(x0, x1):
				m.terrain.dig_at(base + Vector3(x * 0.5 + 0.25, y * 0.5 + 0.25, z * 0.5 + 0.25), 1.0)

## Stand in a pocket at `base` facing -Z and walk forward for `frames`.
func walk(base: Vector3, frames: int) -> Dictionary:
	m.player.global_position = base + Vector3(0.0, 0.95, 0.3)
	m.player.velocity = Vector3.ZERO
	m.player._yaw = 0.0
	m.player._pitch = -0.15
	m.player.duck = 0.0
	m.player.twist = 0.0
	m.player._apply_posture()
	for i in range(10):
		await physics_frame
	var start: Vector3 = m.player.global_position
	var r := {"progress": 0.0, "rise": 0.0, "squeeze": 0.0, "duck_mid": 0.0, "twist_mid": 0.0, "crush": 0.0, "tight": 0.0, "posture_ms": 0.0, "costs": []}
	Input.action_press("fdk_move_forward")
	for i in range(frames):
		await physics_frame
		r["rise"] = maxf(r["rise"], m.player.global_position.y - start.y)
		r["squeeze"] = maxf(r["squeeze"], m.player.squeeze())
		r["crush"] = maxf(r["crush"], m.crush_progress())
		r["tight"] = maxf(r["tight"], m.danger_show.tightness())
		r["posture_ms"] = maxf(r["posture_ms"], m.player.last_posture_us / 1000.0)
		(r["costs"] as Array).append(m.player.last_posture_us / 1000.0)
		if i == frames / 2:
			r["duck_mid"] = m.player.duck
			r["twist_mid"] = m.player.twist
	Input.action_release("fdk_move_forward")
	r["progress"] = start.z - m.player.global_position.z
	return r

func run() -> void:
	for i in range(5):
		await process_frame
	m.finish_opening()
	var deaths0: int = m.deaths
	check(not Input.is_action_pressed("fdk_jump"), "nobody holds Space in these walks")
	# --- capsule and posture are the same body ---------------------------------
	var cap := m.player.collision_shape.shape as CapsuleShape3D
	m.player.twist = 1.0
	m.player.duck = 1.0
	m.player._apply_posture()
	check(is_equal_approx(cap.radius, m.player.body_radius()) and is_equal_approx(cap.height, m.player.body_height()), "the real capsule is the squeezed body")
	check(cap.radius < FPProgression.BASE_BODY_RADIUS * 0.7 and cap.height <= m.player.config.squeeze_min_height + 0.01, "a fully squeezed body is thinner and lower")
	m.player.duck = 0.0
	m.player.twist = 0.0
	m.player._apply_posture()
	check(is_equal_approx(cap.radius, m.progression.body_radius()) and is_equal_approx(cap.height, m.player.config.stand_height), "and back to the body's own size")
	# --- a raised tunnel mouth (floor half a metre up, 1.5 m tall) -------------
	var b := Vector3(-6, 0, -6)
	carve(b, -2, 2, 0, 4, -2, 2)
	carve(b, -1, 1, 1, 3, -8, -2)
	m.terrain.remesh_all()
	await physics_frame
	var epoch: int = m.terrain.get_dig_epoch()
	# the pocket's edge is ~1.3 m ahead: each tunnel must be well entered
	var raised := await walk(b, 260)
	check(raised["progress"] > 2.2 and raised["rise"] > 0.3, "walks up into a raised tunnel without Space (moved %.2f m, rose %.2f m)" % [raised["progress"], raised["rise"]])
	check(m.terrain.get_dig_epoch() == epoch, "walking and squeezing never change the flesh")
	# --- a low tunnel: duck -----------------------------------------------------
	b = Vector3(6, 0, -6)
	carve(b, -2, 2, 0, 4, -2, 2)
	carve(b, -1, 1, 0, 2, -8, -2)
	m.terrain.remesh_all()
	await physics_frame
	var low := await walk(b, 260)
	check(low["progress"] > 1.9, "walks on under a low ceiling (moved %.2f m)" % low["progress"])
	check(low["duck_mid"] > 0.15, "ducking its head in there (duck %.2f)" % low["duck_mid"])
	check(low["tight"] > 0.0, "the view tightens while squeezing (%.2f)" % low["tight"])
	# --- a narrow slot: twist ---------------------------------------------------
	b = Vector3(6, 0, 6)
	carve(b, -2, 2, 0, 4, -2, 2)
	carve(b, 0, 1, 0, 4, -8, -2)
	m.terrain.remesh_all()
	await physics_frame
	var narrow := await walk(b, 260)
	check(narrow["progress"] > 1.9, "worms through a narrow slot (moved %.2f m)" % narrow["progress"])
	# --- a dead end: still a wall -----------------------------------------------
	b = Vector3(-6, 0, 6)
	carve(b, -2, 2, 0, 4, -2, 2)
	m.terrain.remesh_all()
	await physics_frame
	var wall := await walk(b, 120)
	check(wall["progress"] < 1.6, "a real wall still stops the body (moved %.2f m)" % wall["progress"])
	check(wall["rise"] < 0.25, "and it does not climb the curved foot of a dead-end wall (rose %.2f m)" % wall["rise"])
	# a freshly carved tunnel can lag a tick behind in physics, so one crush
	# tick may show; squeezing through never comes anywhere near a crush
	var crush_max := maxf(maxf(raised["crush"], low["crush"]), maxf(narrow["crush"], wall["crush"]))
	check(crush_max < 0.25 and m.deaths == deaths0, "squeezing through never comes near a crush (%.2f %.2f %.2f %.2f)" % [raised["crush"], low["crush"], narrow["crush"], wall["crush"]])
	var worst := maxf(maxf(raised["posture_ms"], low["posture_ms"]), maxf(narrow["posture_ms"], wall["posture_ms"]))
	var costs: Array = (raised["costs"] as Array) + (low["costs"] as Array) + (narrow["costs"] as Array) + (wall["costs"] as Array)
	costs.sort()
	var p95: float = costs[int(costs.size() * 0.95)]
	check(p95 < 8.0, "the posture update is cheap frame to frame (p95 %.1f ms)" % p95)
	check(worst < 30.0, "and its rare spikes (a fresh surface build) stay bounded (%.1f ms)" % worst)
	# --- room returns: the body straightens up again ----------------------------
	m.player.twist = 0.8
	m.player.duck = 0.8
	m.player._apply_posture()
	m.player.global_position = Vector3(-6, 0.95, 6.0)
	for i in range(150):
		await physics_frame
	check(m.player.squeeze() < 0.05, "in open space the body relaxes (%.2f)" % m.player.squeeze())
	# --- legs ---------------------------------------------------------------------
	var legs: Node3D = m.art_hookup.legs
	check(legs != null and legs.get_parent() == m.player, "the player has legs")
	var on_body := true
	for mi in legs.find_children("*", "MeshInstance3D", true, false):
		if ((mi as MeshInstance3D).layers & m.BODY_LAYER) == 0:
			on_body = false
	check(on_body, "the legs are on the body layer (the mirror camera leaves them out)")
	var shin: Node3D = legs.find_child("Shin_r", true, false)
	m.art_hookup._sync_belt_posture(0.0)
	var straight := absf(shin.basis.get_euler().x)
	Input.action_press("fdk_crouch")
	for i in range(10):
		await physics_frame
	m.art_hookup._sync_belt_posture(0.0)
	var bent := absf(shin.basis.get_euler().x)
	Input.action_release("fdk_crouch")
	check(bent > straight + 0.5, "crouching bends the knees (%.2f -> %.2f)" % [straight, bent])
	for i in range(20):
		await physics_frame
	# --- crisis sound -----------------------------------------------------------
	var hook: Node = m.get_node_or_null("AudioHookup")
	check(hook != null and (hook.played_events as Array).has("squeeze"), "squeezing hard makes the flesh strain")
	# --- mutations change how the squeeze slows ---------------------------------
	m.progression.mutation_tree._purchased["M20"] = true
	m.mutation_apply.apply_now()
	check(is_equal_approx(m.player.config.squeeze_speed_min, 1.0), "M20 hypermobile joints: no slowdown squeezing")
	m.progression.mutation_tree._purchased.erase("M20")
	m.progression.mutation_tree._purchased["M19"] = true
	m.mutation_apply.apply_now()
	check(m.player.config.squeeze_speed_min > 1.0, "M19 peristalsis: pushed along faster the tighter it gets")
	m.progression.mutation_tree._purchased.erase("M19")
	m.mutation_apply.apply_now()
	check(is_equal_approx(m.player.config.squeeze_speed_min, FPProgression.POSTURE_SPEED_MIN), "otherwise the tightest squeeze is slow")
	# --- the eye lamp at the doorway ----------------------------------------------
	m.player.global_position = Vector3(0, 0.95, 0.0)
	for i in range(5):
		await process_frame
	m._update_atmosphere(0.1)
	check(m._eye_adapt == 0.0, "in the room the eyes are used to the light")
	m.player.global_position = Vector3(-6, 0.95, 6.3)
	m._eye_adapt = 0.0
	m._update_atmosphere(0.05)
	var first: float = m.lamp_target()
	check(first < m.LAMP_ENERGY * 0.5, "stepping out the lamp starts low, not at full (%.2f)" % first)
	for i in range(int(m.LAMP_ADAPT_TIME / 0.1) + 2):
		m._update_atmosphere(0.1)
	check(m._eye_adapt >= 1.0, "the eyes adapt over LAMP_ADAPT_TIME")
	m.player._yaw = 0.0
	m.player._pitch = 0.0
	m.player.global_position = Vector3(-6, 0.95, 6.3)
	await physics_frame
	var open_target: float = m.lamp_target()
	m.player._yaw = PI
	await physics_frame
	await process_frame
	var wall_target: float = m.lamp_target()
	check(wall_target < open_target, "facing a wall close up the lamp dims (%.2f < %.2f)" % [wall_target, open_target])
	check(is_equal_approx(FPRestroom.DOOR_SPILL_ENERGY, 0.85), "the approved door light is unchanged")
	# right outside the open door: the eyes wait and the door light dims
	m.restroom.set_door_open(true, true)
	m.player.global_position = Vector3(0, 0.95, FPRestroom.HALF.z + 0.4)
	m._eye_adapt = 0.5
	for i in range(30):
		m._update_atmosphere(0.1)
	check(m._eye_adapt < 0.05, "in the open door's light the eyes do not adapt to the dark (%.2f)" % m._eye_adapt)
	m.restroom._update_door_spill()
	check(m.restroom.door_spill.light_energy < FPRestroom.DOOR_SPILL_ENERGY * 0.6, "standing in its beam right outside, the door light dims (%.2f)" % m.restroom.door_spill.light_energy)
	m.player.global_position = Vector3(0, 0.95, 0.0)
	for i in range(30):
		m._update_atmosphere(0.1)
	m.restroom._update_door_spill()
	check(absf(m.restroom.door_spill.light_energy - FPRestroom.DOOR_SPILL_ENERGY) < 0.01, "seen from the room it is the approved light again (%.3f)" % m.restroom.door_spill.light_energy)
	print("--- squeeze: %d passed, %d failed ---" % [passed, failed])
	m.queue_free()
	quit(1 if failed else 0)
