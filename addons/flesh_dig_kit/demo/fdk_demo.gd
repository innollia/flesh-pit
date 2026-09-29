extends Node3D

## Wires the kit's terrain, stomach, chewer, and player controller together
## for a standalone demo. Also serves as the reference for how a game
## should wire the kit's pieces.

@export var terrain_config: FDKTerrainConfig = FDKTerrainConfig.new()
@export var stomach_config: FDKStomachConfig = FDKStomachConfig.new()

var terrain: FDKTerrainField
var stomach: FDKStomach
var chewer: FDKChewer
var player: FDKFirstPersonController
var hands_rig: FDKHandsRig

func _ready() -> void:
	terrain = FDKTerrainField.new()
	terrain.name = "TerrainField"
	terrain.config = terrain_config
	add_child(terrain)

	# A solid flesh wall in front of the spawn point, and an empty spherical
	# room around spawn so the player does not start embedded in tissue.
	terrain.carve_sphere(Vector3(0, 1, 0), 3.0)
	terrain.fill_box_uniform(AABB(Vector3(-4, -4, 3), Vector3(8, 8, 12)), 1.0, 0)

	stomach = FDKStomach.new()
	stomach.name = "Stomach"
	stomach.config = stomach_config
	add_child(stomach)

	var player_scene: PackedScene = load("res://addons/flesh_dig_kit/player/fdk_first_person_controller.tscn")
	player = player_scene.instantiate()
	player.name = "Player"
	player.position = Vector3(0, 1, 0)
	add_child(player)

	chewer = FDKChewer.new()
	chewer.name = "Chewer"
	chewer.terrain = terrain
	chewer.stomach = stomach
	chewer.config = stomach_config
	add_child(chewer)

	hands_rig = player.hands_rig
	chewer.chew_progress.connect(hands_rig.animate_chew)
	chewer.cell_torn.connect(func(_p): hands_rig.notify_tear())

func _process(delta: float) -> void:
	if player == null or chewer == null:
		return
	var ray: Array = player.get_look_ray()
	var origin: Vector3 = ray[0]
	var direction: Vector3 = ray[1]

	if Input.is_action_pressed("fdk_eat"):
		var space_state := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 2.5)
		var hit := space_state.intersect_ray(query)
		if hit:
			chewer.try_start(hit.position - direction * 0.05)
			chewer.process_chew(delta)
		else:
			chewer.stop()
			if hands_rig != null:
				hands_rig.reset_chew()
	else:
		chewer.stop()
		if hands_rig != null:
			hands_rig.reset_chew()

	terrain.regenerate_all(delta, player.global_position, 2.0)
