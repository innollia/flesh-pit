extends SceneTree

## One shot per biome structure kind, standing at the pocket's +Z side and
## looking in, in the real game (terrain streamed in, biome light and fog
## settled). Plus one shot per biome looking out of a pocket at its tissue.
## Isolated save.
##   CAP_OUT=<dir> godot_console --path game --resolution 960x540 --fixed-fps 60 --script res://tests/capture_biomes.gd

var m: Node3D
var out := ""
const SAVE := "user://capture-biomes.bin"

func _init() -> void:
	out = OS.get_environment("CAP_OUT")
	if out == "":
		out = OS.get_user_data_dir()
	m = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	m.save_path = SAVE
	root.add_child(m)
	_run.call_deferred()

func frames(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await frames(2)
	root.get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("CAP ", name)

func look_at_point(target: Vector3) -> void:
	var eye: Vector3 = m.player.camera.global_position
	var d := target - eye
	m.player._yaw = atan2(-d.x, -d.z)
	m.player._pitch = atan2(d.y, Vector2(d.x, d.z).length())

func _run() -> void:
	await frames(5)
	m.finish_opening()
	m.died.connect(func(cause): print("  DIED ", cause, " at ", m.player.global_position.snappedf(0.01), " frame ", Engine.get_process_frames(), " trapped ", m._crush_t))
	var seen := {}
	var seen_biome := {}
	for s in m.biomes.structures:
		if not s["enabled"] or seen.has(s["kind"]):
			continue
		seen[s["kind"]] = true
		var pos: Vector3 = s["pos"]
		var half: Vector3 = s["half"]
		# the far chunks must exist with collision before the body arrives,
		# or it drops into solid flesh and is crushed
		m.terrain.generate_region(AABB(pos - Vector3(6, 6, 6), Vector3(12, 12, 12)))
		m.terrain.remesh_all()
		# global_position is the capsule centre: 0.95 over the floor (START_POS)
		m.player.global_position = pos + Vector3(0, 0.95, half.z * 0.35)
		m.player.velocity = Vector3.ZERO
		print("  TP ", m.player.global_position.snappedf(0.01), " frame ", Engine.get_process_frames(), " dens ", m.terrain.density_at(m.player.global_position + Vector3(0, 0.9, 0)))
		await frames(3)
		look_at_point(pos + Vector3(0, minf(1.0, half.y), -half.z))
		# streaming, remesh and the mood fade
		await frames(360)
		var at: String = m.biome_life.current
		print("  crush ", m.crush_progress(), " health ", m.hazard.health)
		print("STRUCT ", s["kind"], " biome ", s["biome"], " player biome ", at, " in structure ", m.biome_life.current_structure,
			" tissue below ", m.terrain.tissue_at(pos + Vector3(0, -0.3, 0)), " deaths ", m.deaths,
			" off ", (m.player.global_position - pos).snappedf(0.01))
		await shot("biome_%s_%s" % [s["biome"], s["kind"]])
		if not seen_biome.has(s["biome"]):
			seen_biome[s["biome"]] = true
			# turn around: the pocket's +Z wall is the biome's own tissue
			look_at_point(pos + Vector3(0, 0.3, half.z + 1.0))
			await frames(30)
			await shot("biome_%s_wall" % s["biome"])
	m.queue_free()
	await frames(2)
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
