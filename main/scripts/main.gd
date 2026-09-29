extends Node3D

## flesh-pit's main game scene: the white restroom, the flesh wall beyond
## its door, and the digging/eating/vomiting loop, built on top of the
## Flesh Dig Kit. This script owns game-specific rules (restroom room shape,
## depth bands, vomit/mutation bookkeeping); it never modifies addons/.

const RESTROOM_CENTER := Vector3(0, 1, 0)
const RESTROOM_RADIUS := 2.5
const DOOR_POSITION := Vector3(0, 1, 2.4)

@export var terrain_config: FDKTerrainConfig = FDKTerrainConfig.new()
@export var stomach_config: FDKStomachConfig = FDKStomachConfig.new()

var terrain: FDKTerrainField
var stomach: FDKStomach
var chewer: FDKChewer
var player: FDKFirstPersonController
var hands_rig: FDKHandsRig

## Mutation is a simple accumulating counter for now; presentation (hand
## appearance, footstep sound change) is TODO per docs/todo.md.
var mutation_progress: float = 0.0

func _ready() -> void:
	terrain = FDKTerrainField.new()
	terrain.name = "TerrainField"
	terrain.config = terrain_config
	terrain.depth_origin = RESTROOM_CENTER
	add_child(terrain)

	# Clean white restroom: a carved sphere. Everything past the door is
	# solid flesh, so opening the door reveals a wall to chew through
	# immediately, per design-core.md section 8.
	terrain.carve_sphere(RESTROOM_CENTER, RESTROOM_RADIUS)
	terrain.fill_box_uniform(
		AABB(DOOR_POSITION - Vector3(3, 3, 0), Vector3(6, 6, 40)),
		1.0,
		0
	)

	stomach = FDKStomach.new()
	stomach.name = "Stomach"
	stomach.config = stomach_config
	stomach.vomited.connect(_on_vomited)
	add_child(stomach)

	var player_scene: PackedScene = load("res://addons/flesh_dig_kit/player/fdk_first_person_controller.tscn")
	player = player_scene.instantiate()
	player.name = "Player"
	player.position = RESTROOM_CENTER
	add_child(player)

	chewer = FDKChewer.new()
	chewer.name = "Chewer"
	chewer.terrain = terrain
	chewer.stomach = stomach
	chewer.config = stomach_config
	chewer.cell_torn.connect(_on_cell_torn)
	add_child(chewer)

	hands_rig = player.hands_rig
	chewer.chew_progress.connect(hands_rig.animate_chew)

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

	# Vomiting: standing near the restroom center (toilet stand-in for now;
	# a real toilet model/trigger area is TODO) and holding crouch empties
	# the stomach. Kept simple until restroom content (step 6/TODO) is defined.
	if player.global_position.distance_to(RESTROOM_CENTER) < 1.0 and Input.is_action_just_pressed("fdk_crouch"):
		stomach.vomit()

func _on_cell_torn(_world_pos: Vector3) -> void:
	if hands_rig != null:
		hands_rig.notify_tear()
	# also a hook for chew sound/particles later

func _on_vomited(_amount: float) -> void:
	mutation_progress += 1.0

func serialize() -> Dictionary:
	return {
		"version": 1,
		"terrain": terrain.serialize(),
		"stomach": stomach.serialize(),
		"mutation_progress": mutation_progress,
		"player_position": [player.global_position.x, player.global_position.y, player.global_position.z],
	}

func deserialize(data: Dictionary) -> void:
	if data.has("terrain"):
		terrain.deserialize(data["terrain"])
	if data.has("stomach"):
		stomach.deserialize(data["stomach"])
	mutation_progress = float(data.get("mutation_progress", 0.0))
	var pos: Array = data.get("player_position", [])
	if pos.size() == 3:
		player.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
