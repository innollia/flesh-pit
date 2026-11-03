extends SceneTree

## Screens of the wired mutation signals in the running game (normal loop,
## real rendering, isolated save):
## - M22: the alien left hand tears a cell on its own -> blood, bits, the
##   snapping rim (m22_*.png)
## - M29: a crush death sleeps curled with the eyes shut for 30 s, then the
##   eyes open on the curled body and it stands (m29_*.png, real 33 s)
## - T1: what a tongue-click pulse already shows (t1_*.png)
## Run windowed:
##   FP_WIRE_OUT=<dir> godot_console --path game --resolution 960x540 --script res://tests/capture_mutation_wire.gd
var m: Node3D
var out: String
var torn_frame := -1

func _init() -> void:
	out = OS.get_environment("FP_WIRE_OUT")
	if out.is_empty():
		out = OS.get_user_data_dir().path_join("capture-mutation-wire")
	DirAccess.make_dir_recursive_absolute(out)
	run.call_deferred()

func grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", name)

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func seconds(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame

func pocket() -> void:
	m.terrain.carve_sphere(Vector3(0, 1.2, 4.2), 1.6)
	m.terrain.remesh_all()
	m.player.set_physics_process(false)
	m.player.velocity = Vector3.ZERO
	m.player.global_position = Vector3(0, 0.6, 4.0)
	m.player._yaw = PI
	m.player.rotation.y = PI
	m.player._pitch = -0.15
	m.player.camera_pivot.rotation.x = -0.15
	m.player.force_update_transform()

func run() -> void:
	m = load("res://main/scenes/main.tscn").instantiate()
	m.rest_seed = 1337
	m.save_path = "user://capture-mutation-wire.bin"
	root.add_child(m)
	await process_frame
	m.finish_opening()
	m.player.mouse_look_enabled = false
	await frames(30)
	var prog: FPProgression = m.progression
	var ma: FPMutationApply = m.mutation_apply
	var only := OS.get_environment("FP_WIRE_ONLY")
	if only == "m29":
		await m29(prog, ma)
		return
	# --- M22 --------------------------------------------------------------
	pocket()
	await frames(20)
	await grab("m22_0_before")
	ma.alien_hand_tore.connect(func(): torn_frame = Engine.get_process_frames())
	prog.mutation_tree._purchased["M22"] = true
	while torn_frame < 0:
		await process_frame
		if ma.alien_reach > 0.8 and torn_frame < 0:
			await grab("m22_1_reach")
			while torn_frame < 0:
				await process_frame
	await grab("m22_2_tear")
	await frames(3)
	await grab("m22_3_tear_plus3")
	await frames(8)
	await grab("m22_4_tear_plus11")
	await seconds(1.0)
	await grab("m22_5_after")
	print("M22 hand_blood=%.2f gore=%d" % [m.hand_blood, m.gore.live_count()])
	prog.mutation_tree._purchased.erase("M22")
	# --- T1 ---------------------------------------------------------------
	prog.tumor_mutations.append("T1")
	await seconds(1.6)
	await grab("t1_0_pulse")
	await seconds(0.5)
	await grab("t1_1_pulse")
	print("T1 counts ", ma.echo_counts)
	prog.tumor_mutations.erase("T1")
	await frames(10)
	await m29(prog, ma)

func m29(prog: FPProgression, ma: FPMutationApply) -> void:
	# --- M29 --------------------------------------------------------------
	pocket()
	m.player.set_physics_process(true)
	await frames(5)
	prog.mutation_tree._purchased["M29"] = true
	m.die("crush")
	await seconds(1.5)
	await grab("m29_0_asleep_1s")
	await seconds(13.0)
	await grab("m29_1_asleep_15s")
	while ma._dormant_t < FPProgression.DORMANT_WAKE - 0.2:
		await process_frame
	await grab("m29_2_asleep_30s")
	var shots := [0.35, 0.6, 0.9, 1.3, 1.7, 2.1, 2.6]
	var i := 0
	for at in shots:
		while ma.is_dormant() and ma._dormant_t < FPProgression.DORMANT_WAKE + at:
			await process_frame
		await grab("m29_%d_wake_%.2f" % [3 + i, at])
		i += 1
	await seconds(0.5)
	await grab("m29_9_awake")
	print("M29 dormant=%s physics=%s" % [ma.is_dormant(), m.player.is_physics_processing()])
	m.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://capture-mutation-wire.bin"))
	quit(0)
