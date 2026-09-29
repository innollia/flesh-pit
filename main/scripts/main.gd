extends Node3D

## flesh-pit main scene: the white restroom, the concentric flesh world around
## it, and the eat -> fill -> vomit -> settle loop, built on the Flesh Dig Kit.
## Game-specific rules live here (restroom, rewards, shop placeholder, carry
## pile); nothing in addons/ refers back to this file.

const RESTROOM_CENTER := Vector3(0, 1, 0)
const ROOM_MARGIN := 0.25
const MEMBRANE_THICKNESS := 0.9
## Overfill ratio past which the on-screen vomit button appears.
const VOMIT_BUTTON_OVERFILL := 0.35
## Reward per flesh unit vomited into the toilet (placeholder tuning).
const MUTATION_PER_FLESH := 0.5
const MONEY_PER_FLESH := 12.0
const WORLD_GEN_HALF := 10.0

@export var terrain_config: FDKTerrainConfig = FDKTerrainConfig.new()
@export var stomach_config: FDKStomachConfig = FDKStomachConfig.new()

var terrain: FDKTerrainField
var stomach: FDKStomach
var chewer: FDKChewer
var player: FDKFirstPersonController
var hands_rig: FDKHandsRig
var restroom: FPRestroom
var stomach_view: FPStomachView
var vomit_button: FPVomitButton
var settlement: FPToiletSettlement
var settle_camera: Camera3D
var environment: Environment
var player_lamp: OmniLight3D
var nerves: Array[FDKNerveStalk] = []

## Kept for save compatibility; counts toilet vomits.
var mutation_progress: float = 0.0
var mutation_points: int = 0
var money: int = 0
## Flesh held in the hands (carry mode). While > 0, two-handed tools are off.
var carried_flesh: float = 0.0
var carry_mode: bool = false
var purchased_items: Array = []
var _settling: bool = false
var _coin: MeshInstance3D
var _coin_t: float = -1.0
var _noise: FastNoiseLite

func _ready() -> void:
    _register_inputs()
    _noise = FastNoiseLite.new()
    _noise.seed = 1337
    _noise.frequency = 0.35

    terrain = FDKTerrainField.new()
    terrain.name = "TerrainField"
    terrain.config = terrain_config
    terrain.depth_origin = RESTROOM_CENTER
    terrain.density_sampler = _world_density
    terrain.tissue_sampler = _world_tissue
    add_child(terrain)
    terrain.generate_region(AABB(Vector3.ONE * -WORLD_GEN_HALF, Vector3.ONE * WORLD_GEN_HALF * 2.0))
    terrain.remesh_all()

    restroom = FPRestroom.new()
    restroom.name = "Restroom"
    add_child(restroom)

    stomach = FDKStomach.new()
    stomach.name = "Stomach"
    stomach.config = stomach_config
    add_child(stomach)

    var player_scene: PackedScene = load("res://addons/flesh_dig_kit/player/fdk_first_person_controller.tscn")
    player = player_scene.instantiate()
    player.name = "Player"
    player.position = Vector3(0, 0.95, -0.2)
    add_child(player)
    player.set("_yaw", PI) # face the door (+Z)

    chewer = FDKChewer.new()
    chewer.name = "Chewer"
    chewer.terrain = terrain
    chewer.stomach = stomach
    chewer.config = stomach_config
    chewer.cell_torn.connect(_on_cell_torn)
    add_child(chewer)

    hands_rig = player.hands_rig
    chewer.grab_started.connect(hands_rig.on_grab_started)
    chewer.chew_progress.connect(hands_rig.on_chew_progress)
    chewer.cell_torn.connect(hands_rig.on_cell_torn)
    chewer.released.connect(hands_rig.on_released)

    stomach_view = FPStomachView.new()
    stomach_view.name = "StomachView"
    player.camera.add_child(stomach_view)
    stomach.fill_changed.connect(func(_f, _c, _o): stomach_view.set_state(stomach.fill_ratio(), stomach.overfill_ratio()))

    player_lamp = OmniLight3D.new()
    player_lamp.name = "BodyGlow"
    player_lamp.light_color = Color(1.0, 0.8, 0.72)
    player_lamp.light_energy = 1.1
    player_lamp.omni_range = 7.0
    player_lamp.omni_attenuation = 1.4
    player_lamp.position = Vector3(0.1, 0.15, 0.1)
    player.camera.add_child(player_lamp)

    _setup_environment()
    _build_ui()
    _build_settle_camera()
    _spawn_door_nerves()

    # Navigation aids are placeholders only (design-core 7).
    var compass := Node3D.new()
    compass.name = "CompassTODO"
    add_child(compass)
    var canary := Node3D.new()
    canary.name = "CanaryTODO"
    add_child(canary)

func _register_inputs() -> void:
    FDKInputActions.register_defaults()
    for pair in [["fp_vomit", KEY_V], ["fp_interact", KEY_F], ["fp_carry", KEY_Q]]:
        if not InputMap.has_action(pair[0]):
            InputMap.add_action(pair[0])
            var ev := InputEventKey.new()
            ev.physical_keycode = pair[1]
            InputMap.action_add_event(pair[0], ev)

# --- world generation ---------------------------------------------------------

func _room_dist(p: Vector3) -> float:
    # signed-ish distance outside the room box (0 inside)
    var h := FPRestroom.HALF
    var q := Vector3(absf(p.x) - h.x, maxf(-p.y, p.y - 2.0 * h.y), absf(p.z) - h.z)
    return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()

func _world_density(p: Vector3) -> float:
    var h := FPRestroom.HALF
    if absf(p.x) <= h.x + ROOM_MARGIN and p.y >= -ROOM_MARGIN and p.y <= 2.0 * h.y + ROOM_MARGIN and absf(p.z) <= h.z + ROOM_MARGIN:
        return 0.0
    return 1.0

func _in_door_column(p: Vector3) -> bool:
    return p.z > 0.0 and absf(p.x) < FPRestroom.DOOR_HALF_W + 0.9 and p.y < FPRestroom.DOOR_H + 0.9

func _world_tissue(p: Vector3) -> int:
    if _room_dist(p) < MEMBRANE_THICKNESS + ROOM_MARGIN and not _in_door_column(p):
        return 3 # membrane: the restroom shell cannot be eaten around
    var n := _noise.get_noise_3dv(p)
    if n > 0.42:
        return 1 # nerve bundle
    var depth := p.distance_to(RESTROOM_CENTER)
    if fposmod(depth, 9.0) > 6.0 and n < -0.2:
        return 2 # fat band inside each shell
    return 0

func _spawn_door_nerves() -> void:
    var z := FPRestroom.HALF.z + ROOM_MARGIN
    var spots := [Vector3(-0.35, 1.55, z), Vector3(0.3, 0.55, z), Vector3(0.05, 1.85, z), Vector3(-0.2, 0.3, z)]
    for s in spots:
        _spawn_nerve(s + Vector3(0, 0, 0.02), Vector3(0, 0, -1).rotated(Vector3.UP, randf_range(-0.4, 0.4)).rotated(Vector3.RIGHT, randf_range(-0.3, 0.3)))

func _spawn_nerve(at: Vector3, normal: Vector3) -> FDKNerveStalk:
    var n := FDKNerveStalk.new()
    n.length = randf_range(0.35, 0.65)
    n.terrain = terrain
    add_child(n)
    n.place(at, normal)
    nerves.append(n)
    return n

# --- look & light ---------------------------------------------------------------

func _setup_environment() -> void:
    var we: WorldEnvironment = get_node_or_null("WorldEnvironment")
    if we == null:
        we = WorldEnvironment.new()
        we.name = "WorldEnvironment"
        add_child(we)
    environment = Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.08, 0.01, 0.02)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.55, 0.22, 0.24)
    environment.ambient_light_energy = 0.35
    environment.fog_enabled = true
    environment.fog_light_color = Color(0.22, 0.03, 0.05)
    environment.fog_density = 0.09
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    we.environment = environment
    var sun: DirectionalLight3D = get_node_or_null("DirectionalLight3D")
    if sun != null:
        sun.light_energy = 0.12
        sun.light_color = Color(1.0, 0.7, 0.65)

func _update_atmosphere(delta: float) -> void:
    var inside := restroom.contains(player.global_position)
    var k := 1.0 - exp(-delta * 3.0)
    environment.fog_density = lerpf(environment.fog_density, 0.012 if inside else 0.09, k)
    environment.ambient_light_color = environment.ambient_light_color.lerp(Color(0.85, 0.87, 0.9) if inside else Color(0.55, 0.22, 0.24), k)
    environment.ambient_light_energy = lerpf(environment.ambient_light_energy, 0.22 if inside else 0.35, k)
    player_lamp.light_energy = lerpf(player_lamp.light_energy, 0.2 if inside else 1.1, k)
    # deeper shells are darker and more purple
    var depth := terrain.depth_at(player.global_position)
    var tone := clampf(depth / terrain_config.depth_tone_distance, 0.0, 1.0)
    if not inside:
        environment.fog_light_color = Color(0.22, 0.03, 0.05).lerp(Color(0.1, 0.01, 0.07), tone)

func apply_atmosphere_now() -> void:
    _update_atmosphere(100.0)

# --- UI ---------------------------------------------------------------------------

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    layer.name = "HUD"
    add_child(layer)
    vomit_button = FPVomitButton.new()
    vomit_button.name = "VomitButton"
    layer.add_child(vomit_button)
    vomit_button.pressed.connect(request_vomit)
    settlement = FPToiletSettlement.new()
    settlement.name = "Settlement"
    add_child(settlement)
    settlement.buy_requested.connect(_on_buy)

func _build_settle_camera() -> void:
    settle_camera = Camera3D.new()
    settle_camera.name = "SettleCamera"
    settle_camera.fov = 66.0
    settle_camera.near = 0.02
    add_child(settle_camera)
    var bowl := restroom.bowl_center
    settle_camera.global_position = bowl + Vector3(-0.06, 0.34, 0.2)
    settle_camera.look_at(bowl + Vector3(0, 0, -0.04), Vector3.UP)
    var coin_st := SurfaceTool.new()
    coin_st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var prof := FDKLowPoly.round_profile(10)
    var rings := [FDKLowPoly.ring(prof, 0.004, Vector2(0.03, 0.03)), FDKLowPoly.ring(prof, -0.004, Vector2(0.03, 0.03))]
    FDKLowPoly.loft(coin_st, rings, [Color(0.95, 0.78, 0.2)], true, true)
    _coin = MeshInstance3D.new()
    _coin.mesh = coin_st.commit()
    var cm := StandardMaterial3D.new()
    cm.vertex_color_use_as_albedo = true
    cm.metallic = 0.8
    cm.roughness = 0.3
    _coin.material_override = cm
    _coin.visible = false
    add_child(_coin)

# --- loop -------------------------------------------------------------------------

func _process(delta: float) -> void:
    if player == null or chewer == null:
        return
    _update_atmosphere(delta)
    stomach_view.set_state(stomach.fill_ratio(), stomach.overfill_ratio())
    vomit_button.shown = not _settling and stomach.overfill_ratio() >= VOMIT_BUTTON_OVERFILL
    hands_rig.set_mutation(clampf(mutation_points / 400.0, 0.0, 1.0))
    hands_rig.set_carry(clampf(carried_flesh / 40.0, 0.0, 1.0) if carried_flesh > 0.0 else 0.0)
    _process_coin(delta)

    if _settling:
        chewer.stop()
        if Input.is_action_just_pressed("fp_interact") or Input.is_action_just_pressed("ui_cancel"):
            end_settlement()
        return

    if Input.is_action_just_pressed("fp_carry"):
        toggle_carry()
    if Input.is_action_just_pressed("fp_vomit"):
        request_vomit()
    if Input.is_action_just_pressed("fp_interact"):
        _interact()

    var ray: Array = player.get_look_ray()
    var origin: Vector3 = ray[0]
    var direction: Vector3 = ray[1]
    if Input.is_action_pressed("fdk_eat"):
        var space_state := get_world_3d().direct_space_state
        var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 2.5)
        query.exclude = [player.get_rid()]
        var hit := space_state.intersect_ray(query)
        if hit and hit.collider.has_meta("fdk_terrain_chunk"):
            # aim half a cell INTO the wall: the targeted cell is solid tissue
            chewer.try_start(hit.position + direction * terrain_config.cell_size * 0.5)
            chewer.process_chew(delta)
        else:
            chewer.stop()
    else:
        chewer.stop()

    terrain.regenerate_all(delta, player.global_position, 2.0)

func _interact() -> void:
    var p := player.global_position
    if p.distance_to(restroom.toilet.global_position + Vector3(0, 0.9, 0.5)) < 1.3:
        start_settlement()
    elif p.distance_to(Vector3(0, 1, FPRestroom.HALF.z)) < 1.6:
        restroom.set_door_open(not restroom.is_door_open())

func _near_toilet() -> bool:
    return player.global_position.distance_to(restroom.toilet.global_position + Vector3(0, 0.9, 0.5)) < 1.3

## Vomit button / key: into the toilet when standing at it (rewarded), anywhere
## else just empties the stomach with no reward (design-core 1).
func request_vomit() -> void:
    if _settling:
        return
    if _near_toilet():
        start_settlement()
    else:
        stomach.vomit()

## Toilet settlement: vomit into the toilet, convert to mutation points and
## money, show the toilet close-up with counters and the shop.
func start_settlement() -> void:
    if _settling:
        return
    var amount := stomach.vomit()
    var mut_gain := int(round(amount * MUTATION_PER_FLESH))
    var money_gain := int(round(amount * MONEY_PER_FLESH))
    settlement.open(mutation_points, mut_gain, money, money_gain)
    mutation_points += mut_gain
    money += money_gain
    if amount > 0.0:
        mutation_progress += 1.0
    _settling = true
    settle_camera.current = true
    restroom.set_tank_open(false)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func end_settlement() -> void:
    if not _settling:
        return
    _settling = false
    settlement.close()
    player.camera.current = true
    if purchased_items.size() > 0:
        restroom.set_tank_open(true)
    if player.mouse_look_enabled:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func is_settling() -> bool:
    return _settling

## Shop placeholder: no items or prices yet. A purchase throws a coin into
## the bowl and drops a placeholder item into the toilet tank.
func _on_buy(slot: int) -> void:
    _coin_t = 0.0
    _coin.visible = true
    purchased_items.append({"slot": slot})
    var item := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = Vector3(0.08, 0.1, 0.06)
    item.mesh = bm
    var m := StandardMaterial3D.new()
    m.albedo_color = Color.from_hsv(0.1 * slot, 0.6, 0.8)
    item.material_override = m
    item.position = Vector3(-0.12 + 0.05 * (purchased_items.size() % 5), 0, 0)
    restroom.tank_items.add_child(item)

func _process_coin(delta: float) -> void:
    if _coin_t < 0.0:
        return
    _coin_t += delta
    var t := clampf(_coin_t / 0.7, 0.0, 1.0)
    var from := settle_camera.global_position + settle_camera.global_basis * Vector3(0.18, -0.12, -0.2)
    var to := restroom.bowl_center + Vector3(0, -0.02, 0)
    var p := from.lerp(to, t)
    p.y += sin(t * PI) * 0.18
    _coin.global_position = p
    _coin.rotation = Vector3(t * 14.0, t * 5.0, 0)
    if t >= 1.0:
        _coin.visible = false
        _coin_t = -1.0

## Carry mode: torn flesh piles up in both hands instead of going to the
## stomach (the portable blender will consume it later). While carrying,
## two-handed tools are unavailable.
func toggle_carry() -> void:
    carry_mode = not carry_mode
    chewer.stomach = null if carry_mode else stomach
    if not carry_mode:
        carried_flesh = 0.0 # put the pile down

func two_handed_tools_available() -> bool:
    return carried_flesh <= 0.0

func _on_cell_torn(world_pos: Vector3) -> void:
    if carry_mode:
        carried_flesh += stomach_config.flesh_per_cell
    # new tunnel walls sometimes expose a nerve
    if FDKLowPoly.hash3(int(world_pos.x * 2.0), int(world_pos.y * 2.0), int(world_pos.z * 2.0)) > 0.8:
        var dir := Vector3(1, 0, 0) if FDKLowPoly.hash3(int(world_pos.z * 2.0), 1, 2) > 0.5 else Vector3(-1, 0, 0)
        var space_state := get_world_3d().direct_space_state
        var q := PhysicsRayQueryParameters3D.create(world_pos, world_pos + dir * 1.5)
        var hit := space_state.intersect_ray(q)
        if hit and hit.collider.has_meta("fdk_terrain_chunk"):
            _spawn_nerve(hit.position, hit.normal)

func serialize() -> Dictionary:
    return {
        "version": 2,
        "terrain": terrain.serialize(),
        "stomach": stomach.serialize(),
        "mutation_progress": mutation_progress,
        "mutation_points": mutation_points,
        "money": money,
        "carried_flesh": carried_flesh,
        "purchased_items": purchased_items.duplicate(true),
        "player_position": [player.global_position.x, player.global_position.y, player.global_position.z],
    }

func deserialize(data: Dictionary) -> void:
    if data.has("terrain"):
        terrain.deserialize(data["terrain"])
    if data.has("stomach"):
        stomach.deserialize(data["stomach"])
    mutation_progress = float(data.get("mutation_progress", 0.0))
    mutation_points = int(data.get("mutation_points", 0))
    money = int(data.get("money", 0))
    carried_flesh = float(data.get("carried_flesh", 0.0))
    purchased_items = (data.get("purchased_items", []) as Array).duplicate(true)
    var pos: Array = data.get("player_position", [])
    if pos.size() == 3:
        player.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
