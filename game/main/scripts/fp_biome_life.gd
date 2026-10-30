class_name FPBiomeLife
extends Node

## Where the player is among the biomes (main/data/biomes.json): a blended
## mood (light colour, light strength, fog colour, how much of it applies)
## that main's _update_atmosphere mixes into the flesh's own light, the
## terrain fog colour, and the first visit of a biome or a structure,
## remembered (saved) and handed to the vent being, which may remark on it
## after being paid. The restroom, rest containers and base biomes have no
## mood (weight 0). It also builds structure art near the player and frees
## it far away (FPBiomes.stream_art).

## Seconds between position checks and the mood crossfade time.
const CHECK_EVERY := 0.25
const FADE := 2.5
const ROOM := "room"

var m: Node
var biomes: FPBiomes
var current := ROOM
## Structure index the player is standing in (-1 none).
var current_structure := -1
var visited_biomes: Array = []
var visited_structures: Array = []
## The blended mood: biome light colour, light strength multiplier, fog
## colour, and how much of it applies (0 restroom / base biome .. 1).
var ambient := Color(1, 1, 1)
var energy := 1.0
var fog := Color(0.08, 0.01, 0.02)
var weight := 0.0
var _t := 0.0
## Terrain distance fog colour (FDKPs1Materials default) and its current value.
const BASE_FOG := Color(0.08, 0.01, 0.02)
var _terrain_fog := BASE_FOG

func setup(main: Node, p_biomes: FPBiomes) -> void:
	m = main
	biomes = p_biomes

## Bed name for the audio hookup ("" = the shell's own body bed).
func current_bed() -> String:
	if current == ROOM or biomes == null or biomes.is_base(current):
		return ""
	return String(biomes.biome(current).get("bed", ""))

func _process(delta: float) -> void:
	if m == null or biomes == null:
		return
	_t += delta
	if _t >= CHECK_EVERY:
		_t = 0.0
		_check()
	_blend(delta)

func _check() -> void:
	var player = m.get("player")
	if player == null:
		return
	var p: Vector3 = (player as Node3D).global_position
	var nodes = m.get("structure_nodes")
	if nodes != null:
		biomes.stream_art(nodes, p, m.get("terrain"), 1)
	var restroom = m.get("restroom")
	var inside: bool = restroom != null and restroom.contains(p)
	if not inside:
		inside = FPWorldFeatures.in_container(p, m.get("rest_points"))
	current = ROOM if inside else biomes.biome_at(p)
	if current != ROOM and not biomes.is_base(current) and not visited_biomes.has(current):
		visited_biomes.append(current)
		_tell_vent("new_biome", current)
	current_structure = -1 if inside else biomes.structure_at(p + Vector3(0, 0.3, 0))
	if current_structure >= 0:
		var kind := String(biomes.structures[current_structure]["kind"])
		if not visited_structures.has(kind):
			visited_structures.append(kind)
			_tell_vent("new_struct", kind)

func _tell_vent(key: String, id: String) -> void:
	var vent = m.get("vent")
	if vent != null:
		vent.player_state[key] = id

func _blend(delta: float) -> void:
	var k := clampf(delta / FADE, 0.0, 1.0)
	var target_w := 0.0
	if current != ROOM and not biomes.is_base(current):
		# colours move only toward a biome; leaving one just fades the weight
		var b := biomes.biome(current)
		target_w = 1.0
		ambient = ambient.lerp(_col(b.get("ambient", []), ambient), k if weight > 0.01 else 1.0)
		energy = lerpf(energy, float(b.get("ambient_energy", 1.0)), k if weight > 0.01 else 1.0)
		fog = fog.lerp(_col(b.get("fog", []), fog), k if weight > 0.01 else 1.0)
	weight = move_toward(weight, target_w, k)
	var tf := BASE_FOG.lerp(fog, weight)
	if not tf.is_equal_approx(_terrain_fog):
		_terrain_fog = tf
		for id in range(FDKChunk.TISSUE_TEXTURES.size()):
			FDKChunk.terrain_material(id).set_shader_parameter("fog_color", tf)

## Jumps the mood straight to where the player stands (after a load).
func snap() -> void:
	_check()
	_blend(FADE)

static func _col(a, fallback: Color) -> Color:
	if a is Array and a.size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback

func serialize() -> Dictionary:
	return {"biomes": visited_biomes.duplicate(), "structures": visited_structures.duplicate()}

func deserialize(d: Dictionary) -> void:
	visited_biomes = (d.get("biomes", []) as Array).duplicate()
	visited_structures = (d.get("structures", []) as Array).duplicate()
