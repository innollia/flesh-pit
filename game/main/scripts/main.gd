extends Node3D

## flesh-pit main scene: the white restroom, the three flesh shells around
## it, and the full loop (design-core): dig/eat -> stomach -> vomit at the
## toilet or a rest point -> flush -> teeth in the tank + hairs on the arm ->
## trade at the vent, mutate at the mirror -> dig farther -> break out.
## Game rules live here and in fp_*.gd; nothing in addons/ refers back.
## Visuals of the new systems are placeholder shapes only.

signal died(cause: String)
signal ending_reached
signal canary_chirp(urgency: float)
signal canary_cry(frightened: bool)
signal flushed(teeth_gain: int, hair_gain: int)
## Opening: the flush heard on the black screen (audio: game/audio_HOOKUP.md).
signal opening_flush

const SAVE_VERSION := 3

const RESTROOM_CENTER := Vector3(0, 1, 0)
## Empty space around the room box: surface-nets vertices can sit most of a
## cell inside the solid side, so this must exceed one cell.
const ROOM_MARGIN := 0.65
## Right in front of the door the margin is pulled down to under 5 cm.
const DOOR_GAP := 0.04
const MEMBRANE_THICKNESS := 0.9
const VOMIT_BUTTON_OVERFILL := 0.35
const WORLD_GEN_HALF := 10.0
const SHELL_THICKNESS := FPWorldFeatures.SHELL_THICKNESS
const OUTER_RADIUS := FPWorldFeatures.OUTER_RADIUS
const START_POS := Vector3(-0.95, 0.95, 0.75)
const START_YAW := -PI * 0.5 - 0.02
const START_PITCH := -0.32
const SEAT_POS := Vector3(0.75, 0.55, -1.05)
const OPENING_TIME := FPOpening.TOTAL
const BODY_PROTECT_RADIUS := 0.9
const CRUSH_TIME := 6.0
const CRUSH_BLOCK := 0.8
const NERVE_TOUCH_RADIUS := 0.45
const CONTRACT_RADIUS := 1.3
const CONTRACT_AMOUNT := 0.45
const HAZARD_TIME := 1.2
const HEALTH_REGEN := 12.0
const BARRIER_PRESSURE := 14.0
const CANARY_TICK := 0.25
const CANARY_FEED_TIME := 120.0
const REACH := 2.5

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
var settle_camera: Camera3D
var environment: Environment
var player_lamp: OmniLight3D
var nerves: Array[FDKNerveStalk] = []

var progression: FPProgression = FPProgression.new()
var barrier_field: FDKBarrierField
var canary: FDKCanary
var hazard: FDKHazardCheck = FDKHazardCheck.new()
var death_drop: FDKDeathDrop
## Session D glue: tissue-aware chewing, saw, blender, spray (fp_tissue_tools.gd).
var tissue_tools: FPTissueTools
## Per-game random rotation of the rest points (saved).
var rest_seed: int = 0
var vent: FPVent
## W04 toilet bowl + lever settlement (no numbers, no shop).
var toilet: FPToiletSettlement
var _vent_in_room: bool = true
var _vent_away_t: float = 0.0
## W06 edge flags for room-distance vent events (distances in vent_rules.json).
var _vent_flags: Dictionary = {}
var _vent_hover_id: String = ""
## Crayon tumor drawings posted on the wall (03-restroom 10).
var drawing_nodes: Array[Node3D] = []
var mirror: FPMirror
var ending: FPEnding
var art_hookup: FPArtHookup
var mutation_apply: FPMutationApply
var rest_points: Array[Vector3] = []
var tumor_nodes: Array[Node3D] = []
var taken_tumor_spots: Array = []

var carried_flesh: float = 0.0
var carried_units: Dictionary = {}
var carry_mode: bool = false
var blender_charge: float = 0.0
var has_canary: bool = false
var canary_feed_left: float = 0.0
var canary_urgency: float = 0.0
var hand_blood: float = 0.0
var deaths: int = 0
var opening_done: bool = false
var ended: bool = false
var _opening_t: float = -1.0
var _chew_ratio: float = 0.0
var _settling: bool = false
var _settle_amount: float = 0.0
var _mirror_open: bool = false
## Sitting on the toilet (F at the bowl while standing).
var _seated: bool = false
## Esc menu: key settings screen (fp_keybind_menu.gd).
var keybind_menu: FPKeybindMenu
var _crush_t: float = 0.0
var _hazards: Array = []
var _nerve_cool: Dictionary = {}
var _canary_t: float = 0.0
var _was_inside: bool = true
var _flash: float = 0.0
var _stream_queue: Array[Vector3i] = []
var _last_stream_chunk: Vector3i = Vector3i(99999, 0, 0)
var _tank_teeth_shown: int = -1
var _noise: FastNoiseLite

var ps1_post: FDKPs1ScreenPost

var money: int:
    get: return progression.teeth
var has_blender: bool:
    get: return progression.owns("blender")
    set(v):
        if v:
            progression.tools.grant("blender")

func _ready() -> void:
    if FDKPs1Settings.active.enabled:
        ps1_post = FDKPs1ScreenPost.new()
        add_child(ps1_post)
    _register_inputs()
    _noise = FastNoiseLite.new()
    _noise.seed = 1337
    _noise.frequency = 0.35
    if rest_seed == 0:
        rest_seed = randi_range(1, 999999)
    rest_points = FPWorldFeatures.rest_points(RESTROOM_CENTER, rest_seed)
    tissue_tools = FPTissueTools.new(self)

    terrain = FDKTerrainField.new()
    terrain.name = "TerrainField"
    terrain.config = terrain_config
    terrain.depth_origin = RESTROOM_CENTER
    terrain.density_sampler = _world_density
    terrain.tissue_sampler = _world_tissue
    terrain.regen_rate_scale = _regen_scale
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
    player.position = START_POS
    add_child(player)
    player.set("_yaw", START_YAW)

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
    chewer.chew_progress.connect(func(r, _c): _chew_ratio = r)
    chewer.cell_torn.connect(func(_p): _chew_ratio = 0.0)
    chewer.released.connect(func(): _chew_ratio = 0.0)

    stomach_view = FPStomachView.new()
    stomach_view.name = "StomachView"
    player.camera.add_child(stomach_view)
    stomach.fill_changed.connect(func(_f, _c, _o): stomach_view.set_state(stomach.fill_ratio(), stomach.overfill_ratio()))

    player_lamp = OmniLight3D.new()
    player_lamp.name = "BodyGlow"
    player_lamp.light_color = Color(1.0, 0.8, 0.72)
    player_lamp.light_energy = 2.4
    player_lamp.omni_range = 9.0
    player_lamp.omni_attenuation = 0.6
    player_lamp.position = Vector3(0.1, 0.15, 0.1)
    player.camera.add_child(player_lamp)

    barrier_field = FDKBarrierField.new()
    barrier_field.name = "Barriers"
    barrier_field.terrain = terrain
    barrier_field.pressure_scale = BARRIER_PRESSURE
    add_child(barrier_field)

    canary = FDKCanary.new()
    canary.name = "Canary"
    canary.terrain = terrain
    canary.route_warning.connect(_on_canary_route)
    canary.anomaly_reaction.connect(func(f): canary_cry.emit(f))
    add_child(canary)

    death_drop = FDKDeathDrop.new()
    death_drop.name = "DeathDrop"
    add_child(death_drop)
    var dm := MeshInstance3D.new()
    var dsm := SphereMesh.new()
    dsm.radius = 0.2
    dsm.height = 0.4
    dm.mesh = dsm
    death_drop.add_child(dm)
    death_drop.visible = false

    vent = FPVent.new()
    vent.name = "Vent"
    vent.position = FPRestroom.VENT_CENTER - Vector3(0, 0.03, 0)
    add_child(vent)
    vent.drawing_dropped.connect(_on_drawing_dropped)
    toilet = FPToiletSettlement.new()
    toilet.name = "ToiletSettlement"
    add_child(toilet)

    for r in rest_points:
        FPWorldFeatures.build_container(self, r)
    var spots := FPWorldFeatures.tumor_spots(RESTROOM_CENTER)
    for i in range(spots.size()):
        var t := FPWorldFeatures.build_tumor(self, spots[i])
        t.set_meta("spot", i)
        tumor_nodes.append(t)

    art_hookup = FPArtHookup.new()
    art_hookup.name = "ArtHookup"
    add_child(art_hookup)
    art_hookup.setup(self)
    mutation_apply = FPMutationApply.new()
    mutation_apply.name = "MutationApply"
    add_child(mutation_apply)
    mutation_apply.setup(self)

    _setup_environment()
    _build_ui()
    _build_settle_camera()
    _spawn_door_nerves()
    _setup_restroom_front()
    _begin_opening()

func _on_canary_route(u: float) -> void:
    canary_urgency = u
    canary_chirp.emit(u)

func _register_inputs() -> void:
    FDKInputActions.register_defaults()
    if not InputMap.has_action("fp_pick"):
        InputMap.add_action("fp_pick")
        var mb := InputEventMouseButton.new()
        mb.button_index = MOUSE_BUTTON_RIGHT
        InputMap.action_add_event("fp_pick", mb)
        var rk := InputEventKey.new()
        rk.physical_keycode = KEY_R
        InputMap.action_add_event("fp_pick", rk)
    _register_keybinds()
    # W32: gamepad sticks/triggers and mouse-only bindings (fp_input_modes.gd)
    (load("res://main/scripts/fp_input_modes.gd") as GDScript).call("register")

## Default keys live in main/data/keybinds.json. A player's own changes go to
## user://keybinds.json (same shape) and win over the defaults.
const KEYBINDS_PATH := "res://main/data/keybinds.json"
const USER_KEYBINDS_PATH := "user://keybinds.json"

func _register_keybinds() -> void:
    var binds: Dictionary = {}
    for path in [KEYBINDS_PATH, USER_KEYBINDS_PATH]:
        if FileAccess.file_exists(path):
            var d = JSON.parse_string(FileAccess.get_file_as_string(path))
            if d is Dictionary:
                for k in d.get("키", {}):
                    binds[k] = d["키"][k]
    for action in binds:
        var b: Dictionary = binds[action]
        if not InputMap.has_action(action):
            InputMap.add_action(action)
        else:
            InputMap.action_erase_events(action)
        var code := OS.find_keycode_from_string(String(b.get("키보드", "")))
        if code != KEY_NONE:
            var ev := InputEventKey.new()
            ev.physical_keycode = code
            InputMap.action_add_event(action, ev)
        if int(b.get("패드", -1)) >= 0:
            var jb := InputEventJoypadButton.new()
            jb.button_index = int(b["패드"])
            InputMap.action_add_event(action, jb)

## Change one key and save it for this player (for a future settings screen).
func rebind_key(action: String, key_name: String) -> bool:
    var code := OS.find_keycode_from_string(key_name)
    if code == KEY_NONE or not InputMap.has_action(action):
        return false
    var d: Dictionary = {"키": {}}
    if FileAccess.file_exists(USER_KEYBINDS_PATH):
        var old = JSON.parse_string(FileAccess.get_file_as_string(USER_KEYBINDS_PATH))
        if old is Dictionary:
            d = old
    var pad := -1
    for e in InputMap.action_get_events(action):
        if e is InputEventJoypadButton:
            pad = e.button_index
    d["키"][action] = {"키보드": key_name, "패드": pad}
    var f := FileAccess.open(USER_KEYBINDS_PATH, FileAccess.WRITE)
    f.store_string(JSON.stringify(d, " "))
    f.close()
    _register_keybinds()
    return true

# --- world generation ---------------------------------------------------------

func _room_dist(p: Vector3) -> float:
    var h := FPRestroom.HALF
    var q := Vector3(absf(p.x) - h.x, maxf(-p.y, p.y - 2.0 * h.y), absf(p.z) - h.z)
    return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length()

func _world_density(p: Vector3) -> float:
    var h := FPRestroom.HALF
    var margin := ROOM_MARGIN
    if p.z > h.z and absf(p.x) < FPRestroom.DOOR_HALF_W and p.y > -0.1 and p.y < FPRestroom.DOOR_H:
        margin = DOOR_GAP
    if absf(p.x) <= h.x + margin and p.y >= -margin and p.y <= 2.0 * h.y + margin and absf(p.z) <= h.z + margin:
        return 0.0
    if p.distance_to(RESTROOM_CENTER) >= OUTER_RADIUS:
        return 0.0
    if FPWorldFeatures.in_container(p, rest_points):
        return 0.0
    return 1.0

func _in_door_column(p: Vector3) -> bool:
    return p.z > 0.0 and absf(p.x) < FPRestroom.DOOR_HALF_W + 0.9 and p.y < FPRestroom.DOOR_H + 0.9

func shell_at(p: Vector3) -> int:
    return FPWorldFeatures.shell_of_depth(p.distance_to(RESTROOM_CENTER))

## Tissue ids: 0 flesh, 1 nerve bundle, 2 fat band (shell boundary),
## 3 membrane (restroom shell), 4 contractile fibers (mantle, needs a blade).
func _world_tissue(p: Vector3) -> int:
    var room := _room_dist(p) < MEMBRANE_THICKNESS + ROOM_MARGIN and not _in_door_column(p)
    return FPWorldFeatures.world_tissue(p, RESTROOM_CENTER, _noise.get_noise_3dv(p), room)

func _regen_scale(p: Vector3) -> float:
    return FDKDepthDanger.danger_multiplier(p.distance_to(RESTROOM_CENTER), SHELL_THICKNESS)

func _stream_world() -> void:
    var cc := terrain.world_to_chunk_coord(player.global_position)
    if cc != _last_stream_chunk:
        _last_stream_chunk = cc
        var chunk_world := terrain_config.chunk_size * terrain_config.cell_size
        for dz in range(-1, 2):
            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    var c := cc + Vector3i(dx, dy, dz)
                    if terrain.get_chunk(c) == null and not _stream_queue.has(c):
                        var mid := (Vector3(c) + Vector3.ONE * 0.5) * chunk_world
                        if mid.distance_to(RESTROOM_CENTER) < OUTER_RADIUS + chunk_world:
                            _stream_queue.append(c)
    if not _stream_queue.is_empty():
        terrain.get_or_create_chunk(_stream_queue.pop_front())

func _spawn_door_nerves() -> void:
    var z := FPRestroom.HALF.z + ROOM_MARGIN
    var spots := [Vector3(-0.35, 1.55, z), Vector3(0.3, 0.55, z), Vector3(0.05, 1.85, z), Vector3(-0.2, 0.3, z)]
    for s in spots:
        var n := _spawn_nerve(s + Vector3(0, 0, 0.02), Vector3(0, 0, -1).rotated(Vector3.UP, randf_range(-0.4, 0.4)).rotated(Vector3.RIGHT, randf_range(-0.3, 0.3)))
        n.length = 0.19

func _add_nerve(n: FDKNerveStalk) -> void:
    add_child(n)

func _spawn_nerve(at: Vector3, normal: Vector3) -> FDKNerveStalk:
    var n := FDKNerveStalk.new()
    n.length = randf_range(0.35, 0.65)
    n.terrain = terrain
    n.set_meta("pending_add", true)
    call_deferred("_add_nerve", n)
    n.place(at, normal)
    n.disturbed.connect(_on_nerve_disturbed)
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
    environment.fog_enabled = false
    environment.fog_light_color = Color(0.22, 0.03, 0.05)
    environment.fog_density = 0.09
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    we.environment = environment
    var sun: DirectionalLight3D = get_node_or_null("DirectionalLight3D")
    if sun != null:
        sun.light_energy = 0.12
        sun.light_color = Color(0.96, 0.97, 1.0)

func _update_atmosphere(delta: float) -> void:
    var inside := restroom.contains(player.global_position)
    # coming back from the flesh, the fluorescent tube blinds for a moment
    if inside and not _was_inside:
        _flash = 1.0
    _was_inside = inside
    _flash = maxf(0.0, _flash - delta * 0.8)
    environment.tonemap_exposure = 1.0 + 2.5 * _flash
    var k := 1.0 - exp(-delta * 3.0)
    var depth_tone := clampf(terrain.depth_at(player.global_position) / terrain_config.depth_tone_distance, 0.0, 1.0)
    environment.fog_density = lerpf(environment.fog_density, 0.01 if inside else lerpf(0.1, 0.2, depth_tone), k)
    environment.ambient_light_color = environment.ambient_light_color.lerp(Color(0.85, 0.87, 0.9) if inside else Color(0.55, 0.22, 0.24), k)
    environment.ambient_light_energy = lerpf(environment.ambient_light_energy, 0.12 if inside else 0.42, k)
    player_lamp.light_energy = lerpf(player_lamp.light_energy, 0.0 if inside else 2.4, k)
    if not inside:
        environment.fog_light_color = Color(0.22, 0.03, 0.05).lerp(Color(0.1, 0.01, 0.07), depth_tone)

func apply_atmosphere_now() -> void:
    _update_atmosphere(100.0)

## 0..1 loudness of the ending melody inside the flesh (louder outward).
func melody_level() -> float:
    if restroom.contains(player.global_position):
        return 0.0
    return clampf(pow(terrain.depth_at(player.global_position) / OUTER_RADIUS, 1.5), 0.0, 1.0)

# --- UI ---------------------------------------------------------------------------

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    layer.name = "HUD"
    add_child(layer)
    vomit_button = FPVomitButton.new()
    vomit_button.name = "VomitButton"
    layer.add_child(vomit_button)
    vomit_button.pressed.connect(request_vomit)
    interact_ring = (load("res://main/scripts/fp_interact_ring.gd") as GDScript).new()
    interact_ring.name = "InteractRing"
    layer.add_child(interact_ring)
    mirror = FPMirror.new()
    mirror.name = "Mirror"
    add_child(mirror)
    mirror.closed.connect(_on_mirror_closed)
    keybind_menu = FPKeybindMenu.new()
    keybind_menu.name = "KeybindMenu"
    add_child(keybind_menu)
    keybind_menu.setup(self)
    keybind_menu.closed.connect(_on_keybind_menu_closed)
    ending = FPEnding.new()
    ending.name = "Ending"
    add_child(ending)

func _build_settle_camera() -> void:
    settle_camera = Camera3D.new()
    settle_camera.name = "SettleCamera"
    settle_camera.fov = 66.0
    settle_camera.near = 0.02
    add_child(settle_camera)
    var bowl := restroom.bowl_center
    settle_camera.global_position = bowl + Vector3(-0.06, 0.34, 0.2)
    settle_camera.look_at(bowl + Vector3(0, 0, -0.04), Vector3.UP)

# --- opening ----------------------------------------------------------------------

## Session A (restroom look): opening cover, vent subtitles, blood on hands.
const OPENING_SEAT_PITCH := -0.28
var opening_view: FPOpening
var subtitles: FPSubtitles
var hand_blood_mat: ShaderMaterial

func _setup_restroom_front() -> void:
    opening_view = FPOpening.new()
    opening_view.name = "OpeningView"
    add_child(opening_view)
    subtitles = FPSubtitles.new()
    subtitles.name = "Subtitles"
    add_child(subtitles)
    vent.line_spoken.connect(func(id: String): subtitles.show_line(id))
    hand_blood_mat = FPHandBlood.make_material()
    FPHandBlood.attach(hands_rig, hand_blood_mat)

func _update_restroom_front() -> void:
    FPHandBlood.set_amount(hand_blood_mat, hand_blood)

## The player finishes on the toilet, stands up, opens the stall door.
func _begin_opening() -> void:
    _opening_t = 0.0
    player.global_position = SEAT_POS
    player.set("_yaw", PI)
    player.rotation.y = PI
    player.set("_pitch", OPENING_SEAT_PITCH)
    player.camera_pivot.rotation.x = OPENING_SEAT_PITCH
    player.set_physics_process(false)
    if opening_view != null:
        opening_view.apply(0.0)
    opening_flush.emit()

func _process_opening(delta: float) -> void:
    if _opening_t < 0.0:
        return
    _opening_t += delta
    apply_opening_at(_opening_t)
    if _opening_t >= OPENING_TIME:
        finish_opening()

## Poses the opening at time t (also used by captures and tests).
func apply_opening_at(t: float) -> void:
    var k := FPOpening.rise_at(t)
    player.global_position = SEAT_POS.lerp(Vector3(SEAT_POS.x, START_POS.y, SEAT_POS.z + 0.25), k)
    var pitch := lerpf(OPENING_SEAT_PITCH, 0.0, k)
    player.set("_pitch", pitch)
    player.camera_pivot.rotation.x = pitch
    if opening_view != null:
        opening_view.apply(t)

func finish_opening() -> void:
    if _opening_t < 0.0:
        return
    _opening_t = -1.0
    opening_done = true
    if opening_view != null:
        opening_view.done()
    player.set_physics_process(true)

func is_opening() -> bool:
    return _opening_t >= 0.0

# --- loop -------------------------------------------------------------------------

func _process(delta: float) -> void:
    if player == null or chewer == null:
        return
    _update_atmosphere(delta)
    _update_restroom_front()
    stomach_view.set_state(stomach.fill_ratio(), stomach.overfill_ratio())
    vomit_button.shown = not _settling and stomach.overfill_ratio() >= VOMIT_BUTTON_OVERFILL
    hands_rig.set_mutation(progression.mutation_amount())
    hands_rig.set_carry(clampf(carried_flesh / 40.0, 0.0, 1.0) if carried_flesh > 0.0 else 0.0)
    vent.tick(delta)
    _vent_watch(delta)
    _update_tank_teeth()
    if ended:
        ending.tick(delta)
        return
    _process_opening(delta)
    if is_opening():
        return
    if _settling:
        chewer.stop()
        if Input.is_action_just_pressed("fp_interact"):
            flush() # the lever, pressed by hand
        elif Input.is_action_just_pressed("ui_cancel"):
            leave_settlement() # stand up without flushing: nothing settles
        return
    if keybind_menu != null and keybind_menu.is_open():
        chewer.stop()
        return
    if _seated:
        chewer.stop()
        _process_seated()
        return
    if _mirror_open:
        return
    if Input.is_action_just_pressed("ui_cancel") and keybind_menu != null and not keybind_menu.just_closed():
        open_keybind_menu()
        return
    _handle_actions()
    if Input.is_action_pressed("fdk_eat"):
        _chew_step(delta)
    else:
        chewer.stop()
        terrain.set_press(Vector3.ZERO, Vector3.BACK, 0.0)
    step_world(delta)

func _handle_actions() -> void:
    if Input.is_action_just_pressed("fp_carry"):
        toggle_carry()
    if Input.is_action_just_pressed("fp_vomit"):
        request_vomit()
    if Input.is_action_just_pressed("fp_interact"):
        _interact()
    if Input.is_action_just_pressed("fp_pick"):
        _pick()
    if Input.is_action_just_pressed("fp_barrier"):
        place_barrier()
    if Input.is_action_just_pressed("fp_spray"):
        use_spray(Input.is_key_pressed(KEY_SHIFT))
    if Input.is_action_just_pressed("fp_blend"):
        use_blender()
    if Input.is_action_just_pressed("fp_eat_tumor"):
        eat_tumor()
    if Input.is_action_just_pressed("fp_feed_canary"):
        feed_canary()
    if Input.is_action_just_pressed("fp_tool_next"):
        cycle_tool()
    for i in range(4):
        if Input.is_action_just_pressed("fp_tool_%d" % (i + 1)):
            equip_tool(["", "knife", "blender", "big_saw"][i])

func _chew_step(delta: float) -> void:
    var hit := _look_hit()
    if hit.is_empty() or not hit.collider.has_meta("fdk_terrain_chunk"):
        chewer.stop()
        terrain.set_press(Vector3.ZERO, Vector3.BACK, 0.0)
        return
    var dir: Vector3 = player.get_look_ray()[1]
    var target: Vector3 = hit.position + dir * terrain_config.cell_size * 0.5
    # hardness per tissue, membrane only with a blade (fp_tissue_tools.gd)
    if tissue_tools.chew_at(target, hit.position, dir, delta):
        terrain.set_press(hit.position, -dir, _chew_ratio)

## Everything that moves on its own each frame (tests drive it directly).
func step_world(delta: float) -> void:
    _stream_world()
    var blockers: Array = []
    for b in barrier_field.get_barriers():
        if not b.is_broken():
            blockers.append(Vector4(b.position.x, b.position.y, b.position.z, b.radius))
    if mutation_apply != null:
        blockers.append_array(mutation_apply.extra_regen_blockers())
    terrain.regen_blockers = blockers
    barrier_field.pressure_scale = BARRIER_PRESSURE * _regen_scale(player.global_position)
    terrain.regenerate_all(delta, player.global_position, BODY_PROTECT_RADIUS)
    barrier_field.update(delta)
    _step_nerve_touch(delta)
    _step_hazards(delta)
    _step_canary(delta)
    _step_canary_pull(delta)
    if danger_show == null and hands_rig != null:
        danger_show = (load("res://main/scripts/fp_danger_show.gd") as GDScript).new()
        danger_show.setup(self)
    if danger_show != null:
        danger_show.tick(delta)
    if interact_ring != null:
        interact_ring.set("shown", interact_target() != "")
    _step_death_drop(delta)
    terrain.step_contraction(delta, player.global_position)
    tissue_tools.step_charge(delta, Input.is_action_pressed("fp_blend"))
    tissue_tools.step_blend(delta)
    if not ended and player.global_position.distance_to(RESTROOM_CENTER) >= OUTER_RADIUS - 0.3:
        reach_ending()

func _look_hit() -> Dictionary:
    var ray: Array = player.get_look_ray()
    var q := PhysicsRayQueryParameters3D.create(ray[0], ray[0] + ray[1] * progression.reach())
    q.exclude = [player.get_rid()]
    return get_world_3d().direct_space_state.intersect_ray(q)

func _pitch() -> float:
    return player.camera_pivot.rotation.x

func _looking_at(p: Vector3, deg: float, dist: float) -> bool:
    var ray: Array = player.get_look_ray()
    var to: Vector3 = p - ray[0]
    if to.length() > dist:
        return false
    return to.normalized().dot(ray[1]) > cos(deg_to_rad(deg))

func _interact() -> void:
    var p := player.global_position
    if p.distance_to(mirror_point()) < 1.1 and _looking_at(mirror_point(), 35.0, 1.6):
        open_mirror()
    elif not has_canary and _looking_at(canary_hole_point(), 25.0, 1.4):
        begin_canary_pull()
    elif _near_toilet() and _looking_at(lever_point(), 12.0, 1.4):
        pull_lever()
    elif _near_toilet() and _pitch() > 0.45:
        use_vent()
    elif p.distance_to(sink_point()) < 0.9:
        wash_hands()
    elif _near_toilet():
        if stomach.fill > 0.0 or progression.tumors.carried_count() > 0 or toilet.has_contents():
            start_settlement()
        elif not _looking_at(lever_point(), 35.0, 1.6):
            sit_down() # facing the bowl, not the tank: sit on it
        else:
            var opening := restroom._lid_target == 0.0
            if not opening and progression.teeth_in_hand > 0:
                put_teeth_back()
            else:
                restroom.set_tank_open(opening)
                vent.notice("lid_open" if opening else "lid_close")
    elif p.distance_to(Vector3(0, 1, FPRestroom.HALF.z)) < 1.6:
        restroom.set_door_open(not restroom.is_door_open())
    else:
        pick_up_tumor()

func _pick() -> void:
    if vent.is_open and not vent.offers.is_empty():
        take_vent_offer()
    elif vent.is_open and _near_toilet() and _pitch() > 0.45:
        reach_into_vent()
    elif _near_toilet() and restroom._lid_target != 0.0:
        scoop_teeth()

func mirror_point() -> Vector3:
    return Vector3(-FPRestroom.HALF.x + 0.05, 1.5, -0.35)

func sink_point() -> Vector3:
    return Vector3(-FPRestroom.HALF.x + 0.3, 0.95, -0.35)

func canary_hole_point() -> Vector3:
    return FPRestroom.CANARY_HOLE + Vector3(0.03, 0.0, 0.0)

func _near_toilet() -> bool:
    return player.global_position.distance_to(restroom.toilet.global_position + Vector3(0, 0.9, 0.5)) < 1.3

func _near_rest_point() -> int:
    for i in range(rest_points.size()):
        var bucket := rest_points[i] + Vector3(0, -FPWorldFeatures.CONTAINER_HALF.y + 0.9, -FPWorldFeatures.CONTAINER_HALF.z + 0.5)
        if player.global_position.distance_to(bucket) < 1.4:
            return i
    return -1

# --- stomach, toilet, rest points ----------------------------------------------

## At the toilet or a rest point vomiting settles; elsewhere nothing.
func request_vomit() -> void:
    if _settling:
        return
    if _near_toilet():
        start_settlement()
    elif _near_rest_point() >= 0:
        settle_at_rest_point()
    else:
        stomach.vomit()
        progression.discard_stomach()

func start_settlement() -> void:
    if _settling:
        return
    toilet.vomit_into(stomach.vomit())
    if toilet.throw_tumors(progression) > 0:
        progression.refresh_hands(carry_mode)
    _settling = true
    settle_camera.current = true
    restroom.set_tank_open(false)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Pressing the lever settles: teeth in the tank, hairs on the arm, and the
## flush sets the vent being off.
## The lever is just a thing on the toilet: it can be pressed at any time,
## sitting or standing, full bowl or empty. Settles whatever is in the bowl.
func pull_lever() -> Dictionary:
    if toilet.tank_node == null:
        toilet.tank_node = restroom.tank_art
    var tumor_kinds := toilet.bowl_tumors.duplicate()
    var got := toilet.press_lever(progression)
    vent.on_flush()
    vent.on_tumors_settled(tumor_kinds)
    flushed.emit(got["teeth"], got["hairs"])
    if _settling:
        _settling = false
        player.camera.current = true
        if player.mouse_look_enabled:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    return got

func flush() -> Dictionary:
    return pull_lever()

## Where the flush lever sits on the tank, in world space.
func lever_point() -> Vector3:
    return restroom.toilet.to_global(Vector3(-0.16, 0.733, 0.185))

func end_settlement() -> void:
    flush()

## Stand up from the bowl without the lever: the bowl keeps its contents.
func leave_settlement() -> void:
    if not _settling:
        return
    _settling = false
    player.camera.current = true
    if player.mouse_look_enabled:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func is_settling() -> bool:
    return _settling

## Sit on the toilet (F at the bowl while standing, not looking at the tank).
## F, Esc or a left click stands up again. The lever is still a thing on the
## toilet: seated, R / right click reaches back and presses it.
func sit_down() -> bool:
    if _seated or _settling or ended:
        return false
    _seated = true
    player.velocity = Vector3.ZERO
    player.global_position = SEAT_POS
    player.set("_yaw", PI)
    player.rotation.y = PI
    player.set("_pitch", OPENING_SEAT_PITCH)
    player.camera_pivot.rotation.x = OPENING_SEAT_PITCH
    player.set_physics_process(false)
    vent.notice("sit") # 딴짓_앉기 in vent_rules.json (open vent, no teeth given)
    return true

func stand_up() -> bool:
    if not _seated:
        return false
    _seated = false
    player.global_position = Vector3(SEAT_POS.x, START_POS.y, SEAT_POS.z + 0.25)
    player.set("_pitch", 0.0)
    player.camera_pivot.rotation.x = 0.0
    player.set_physics_process(true)
    return true

func is_seated() -> bool:
    return _seated

func _process_seated() -> void:
    for action in ["fp_pick", "fp_vomit", "fp_interact", "ui_cancel", "fdk_eat"]:
        if Input.is_action_just_pressed(action):
            seated_action(action)
            return

## One input while seated (tests drive this directly).
func seated_action(action: String) -> void:
    match action:
        "fp_pick":
            pull_lever()
        "fp_vomit":
            request_vomit()
        "fp_interact", "ui_cancel", "fdk_eat":
            stand_up()

# --- Esc menu: key settings -------------------------------------------------------

func open_keybind_menu() -> void:
    keybind_menu.open()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_keybind_menu_closed() -> void:
    if player.mouse_look_enabled and not _settling and not _mirror_open:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Default keys from keybinds.json (action -> {키보드, 패드, 설명}).
func keybind_defaults() -> Dictionary:
    var d = JSON.parse_string(FileAccess.get_file_as_string(KEYBINDS_PATH))
    return d.get("키", {}) if d is Dictionary else {}

## Forget the player's own keys: back to keybinds.json.
func reset_keybinds() -> void:
    if FileAccess.file_exists(USER_KEYBINDS_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_KEYBINDS_PATH))
    _register_keybinds()

func settle_at_rest_point() -> Dictionary:
    var got := progression.settle(stomach.vomit())
    flushed.emit(got["teeth"], got["hairs"])
    return got

## Tank teeth shown as a pile of real teeth in the tank model (whole
## handfuls of 4), never a number.
func _update_tank_teeth() -> void:
    var shown := int(ceil(progression.teeth / float(FPProgression.HANDFUL_TEETH)))
    if shown == _tank_teeth_shown:
        return
    _tank_teeth_shown = shown
    if restroom.tank_art != null:
        restroom.tank_art.call("set_handfuls", shown)

func scoop_teeth() -> int:
    if restroom._lid_target == 0.0:
        return 0
    var n := progression.scoop_handful()
    if n > 0:
        vent.notice("grab")
    return n

func try_pick_tank_item() -> bool:
    return scoop_teeth() > 0

# --- vent ------------------------------------------------------------------------

func use_vent() -> void:
    if not vent.is_open:
        vent.open(progression.teeth + progression.teeth_in_hand)
    elif progression.teeth_in_hand > 0:
        place_teeth_at_vent()
    elif vent.offers.is_empty() and progression.tumors.carried_count() > 0:
        vent.place_weird("tumor") # it will not take it; the tumor stays in hand
    elif vent.offers.is_empty():
        vent.close()

func place_teeth_at_vent() -> Array[String]:
    var ids := vent.place_teeth(progression.teeth_in_hand, progression)
    if not ids.is_empty():
        progression.teeth_in_hand = 0 # the being keeps the whole handful
    return ids

func take_vent_offer(id: String = "") -> bool:
    if id == "":
        var best_dot := -2.0
        var ray: Array = player.get_look_ray()
        for n in vent.offer_nodes():
            var d: float = ((n as Node3D).global_position - ray[0]).normalized().dot(ray[1])
            if d > best_dot:
                best_dot = d
                id = n.get_meta("offer_id")
    return vent.take(id, progression)

## Handful back into the tank: the being sighs.
func put_teeth_back() -> int:
    var n := progression.teeth_in_hand
    if n <= 0:
        return 0
    progression.teeth += n
    progression.teeth_in_hand = 0
    vent.notice("put_back")
    return n

## Pick into the open grate with nothing offered: the canary if carried
## (it gives the bird straight back), otherwise a bare hand.
func reach_into_vent() -> void:
    if has_canary:
        vent.place_weird("canary")
    else:
        vent.notice("hand_in")

## The offer the camera points at ("" when none).
func aimed_offer() -> String:
    var id := ""
    var best_dot := -2.0
    var ray: Array = player.get_look_ray()
    for n in vent.offer_nodes():
        var d: float = ((n as Node3D).global_position - ray[0]).normalized().dot(ray[1])
        if d > best_dot:
            best_dot = d
            id = n.get_meta("offer_id")
    return id

## Fires `event` once each time `on` turns true.
func _vent_edge(key: String, on: bool, event: String) -> void:
    if on and not bool(_vent_flags.get(key, false)):
        vent.notice(event)
    _vent_flags[key] = on

func _on_drawing_dropped(kind: String) -> void:
    var paper := MeshInstance3D.new()
    paper.name = "Drawing_%d" % drawing_nodes.size()
    var pm := BoxMesh.new()
    pm.size = Vector3(0.004, 0.3, 0.21)
    paper.mesh = pm
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.93, 0.9, 0.8)
    paper.material_override = mat
    # a crude crayon blob, a different wobble per tumor kind
    var h := absi(hash(kind))
    var blob := MeshInstance3D.new()
    var bm := SphereMesh.new()
    bm.radius = 0.05 + float(h % 3) * 0.01
    bm.height = bm.radius * (1.2 + float(h % 5) * 0.15)
    blob.mesh = bm
    blob.scale = Vector3(0.05, 1.0, 1.0)
    blob.position = Vector3(-0.004, float(h % 7) * 0.006 - 0.02, float(h % 11) * 0.005 - 0.025)
    var bmat := StandardMaterial3D.new()
    bmat.albedo_color = Color.from_hsv(float(h % 360) / 360.0, 0.7, 0.8)
    blob.material_override = bmat
    paper.add_child(blob)
    paper.set_meta("tumor_kind", kind)
    paper.rotation.x = deg_to_rad(float(h % 9) - 4.0) # taped on crooked
    paper.position = FPVent.drawing_spot(drawing_nodes.size())
    restroom.add_child(paper)
    drawing_nodes.append(paper)

## W06: tell the vent being what the player does in the room.
func _vent_watch(delta: float) -> void:
    vent.shell = progression.deepest_shell
    vent.player_state["blood"] = hand_blood
    vent.player_state["hairs"] = progression.total_hairs()
    vent.player_state["extra_arm"] = ("extra_arm" in progression.tumor_mutations or "T2" in progression.tumor_mutations)
    if player == null or restroom == null:
        return
    var p := player.global_position
    var inside: bool = restroom.contains(p)
    if inside != _vent_in_room:
        _vent_in_room = inside
        if inside:
            vent.player_state["away"] = _vent_away_t
            vent.notice("returned")
        else:
            _vent_away_t = 0.0
            vent.notice("left_room")
    if not inside:
        _vent_away_t += delta
        return
    var tank_d: float = p.distance_to(restroom.toilet.global_position + Vector3(0, 0.9, 0.5))
    if tank_d < 0.9:
        vent.notice("tank_near")
    elif tank_d > 1.6:
        vent.notice("tank_far")
    var vent_d := p.distance_to(Vector3(vent.global_position.x, p.y, vent.global_position.z))
    if vent_d < FPVent.dist("UNDER_VENT", 1.0):
        vent.notice("near_vent")
    _vent_edge("sink", p.distance_to(sink_point()) < FPVent.dist("SINK_NEAR", 0.9), "near_sink")
    _vent_edge("door", p.distance_to(Vector3(0, p.y, FPRestroom.HALF.z)) < FPVent.dist("DOOR_NEAR", 1.0), "door")
    _vent_edge("away", vent.is_open and not vent.offers.is_empty() and vent_d > FPVent.dist("WALK_AWAY", 2.0), "walk_away")
    _vent_edge("with", progression.teeth_in_hand > 0 and tank_d > FPVent.dist("WALK_WITH", 1.8) and vent_d > FPVent.dist("UNDER_VENT", 1.0), "walk_with")
    if vent.is_open and not vent.offers.is_empty():
        var aim := aimed_offer()
        if _vent_hover_id != "" and aim != _vent_hover_id:
            vent.notice("hover")
        _vent_hover_id = aim
    else:
        _vent_hover_id = ""

# --- mirror, sink, canary ------------------------------------------------------

func open_mirror() -> void:
    _mirror_open = true
    vent.notice("mirror")
    mirror.open(progression)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_mirror_closed() -> void:
    _mirror_open = false
    if player.mouse_look_enabled:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func wash_hands() -> void:
    vent.notice("wash")
    hand_blood = 0.0

func take_canary() -> bool:
    if has_canary:
        return false
    has_canary = true
    return true

# --- W03 canary pull: lie down, reach into the hole, pocket one bird --------
const CANARY_PULL_TIME := 1.6
## -1 = not pulling; otherwise seconds into the pull.
var canary_pull_t: float = -1.0
var interact_ring: Control
## W27 wordless danger (bruised hands, crush squeeze); fp_danger_show.gd.
var danger_show = null
var _pull_eye_y: float = 0.0

func is_pulling_canary() -> bool:
    return canary_pull_t >= 0.0

func begin_canary_pull() -> bool:
    if has_canary or is_pulling_canary():
        return false
    canary_pull_t = 0.0
    _pull_eye_y = player.camera_pivot.position.y
    return true

## Drives the prone pose: the eye sinks to the floor and tilts at the hole,
## the canary is pocketed at the bottom of the reach, then the player gets up.
func _step_canary_pull(delta: float) -> void:
    if not is_pulling_canary():
        return
    canary_pull_t += delta
    var k := clampf(canary_pull_t / CANARY_PULL_TIME, 0.0, 1.0)
    var down := sin(k * PI) # 0 -> 1 (prone) -> 0
    player.camera_pivot.position.y = lerpf(_pull_eye_y, 0.18, down)
    var a := _aim_pitch_at(canary_hole_point())
    player.camera_pivot.rotation.x = lerpf(player.camera_pivot.rotation.x, a, down * 0.5)
    hands_rig.set_carry(down * 0.6) # both hands reach forward into the hole
    if k >= 0.5 and not has_canary:
        take_canary()
    if k >= 1.0:
        player.camera_pivot.position.y = _pull_eye_y
        canary_pull_t = -1.0

func _aim_pitch_at(p: Vector3) -> float:
    var eye: Vector3 = player.camera_pivot.global_position
    var d := (p - eye).normalized()
    return asin(clampf(d.y, -1.0, 1.0))

# --- W32 interaction affordance: a ring round the aim dot, no words ---------
## What fp_interact would do right now ("" = nothing but digging).
func interact_target() -> String:
    var p := player.global_position
    if p.distance_to(mirror_point()) < 1.1 and _looking_at(mirror_point(), 35.0, 1.6):
        return "mirror"
    if not has_canary and _looking_at(canary_hole_point(), 25.0, 1.4):
        return "canary"
    if _near_toilet():
        return "toilet"
    if p.distance_to(sink_point()) < 0.9:
        return "sink"
    if p.distance_to(Vector3(0, 1, FPRestroom.HALF.z)) < 1.6:
        return "door"
    return ""

func feed_canary() -> bool:
    if not has_canary or not progression.feed_canary():
        return false
    canary_feed_left = CANARY_FEED_TIME
    return true

func _safe_point() -> Vector3:
    var best := Vector3(0, 1, FPRestroom.HALF.z)
    var bd := player.global_position.distance_to(best)
    for r in rest_points:
        var d := player.global_position.distance_to(r)
        if d < bd:
            bd = d
            best = r
    return best

func _step_canary(delta: float) -> void:
    if not has_canary:
        return
    canary_feed_left = maxf(0.0, canary_feed_left - delta)
    # a fed canary warns earlier: looser flesh already counts as blocking
    canary.block_density = 0.6 if canary_feed_left > 0.0 else 0.85
    _canary_t += delta
    if _canary_t < CANARY_TICK:
        return
    _canary_t = 0.0
    if restroom.contains(player.global_position):
        return
    canary.update(player.global_position, _safe_point())

# --- tools, carry, blender -------------------------------------------------------

func equip_tool(id: String) -> bool:
    return progression.equip(id, carried_flesh > 0.0)

func cycle_tool() -> void:
    var order := ["", "knife", "blender", "big_saw"]
    var i := order.find(progression.equipped())
    for k in range(1, order.size() + 1):
        if equip_tool(order[(i + k) % order.size()]):
            return

## Carry mode: torn flesh piles up in the hand for the blender.
func toggle_carry() -> void:
    if not carry_mode and ((not progression.owns("blender") and not progression.can_lift_without_blender()) or not progression.right_hand_can_carry()):
        return
    carry_mode = not carry_mode
    chewer.stomach = null if carry_mode else stomach
    if not carry_mode:
        carried_flesh = 0.0
        carried_units.clear()
    progression.refresh_hands(carry_mode)

func two_handed_tools_available() -> bool:
    return not progression.one_hand_busy(carried_flesh > 0.0)

## Blender: aimed at nerve-dense tissue it plugs in and charges (and may set
## off a contraction); otherwise the pile is poured in and drunk.
func use_blender() -> bool:
    return tissue_tools.use_blender()

## Blend the carried pile and drink it at once (the timed version runs from
## use_blender: 1.5 s spin + 1.5 s drink).
func drink_blender() -> bool:
    return tissue_tools.blend_now()

# --- barrier, spray --------------------------------------------------------------

## Barrier: auto-expands across the tunnel in front of the player and holds
## back the squeezing flesh until its stress breaks it (4 states, boing).
func place_barrier() -> FDKBarrier:
    if not progression.one_handed_action_allowed() or progression.barriers <= 0:
        return null
    var ray: Array = player.get_look_ray()
    var at: Vector3 = ray[0] + ray[1] * 0.9
    var hit := _look_hit()
    if not hit.is_empty():
        at = ray[0] + ray[1] * maxf(0.3, ray[0].distance_to(hit.position) - 0.4)
    if terrain.density_at(at) >= 0.5:
        return null
    var b := barrier_field.place(at, _tunnel_radius(at, ray[1]))
    if b != null:
        progression.use_barrier()
        b.broke.connect(func(release): _on_barrier_boing(b, release))
    return b

## The stored squeeze is released at once: flesh snaps into the gap.
func _on_barrier_boing(b: FDKBarrier, release: float) -> void:
    terrain.contract_sphere(b.position, b.radius + 0.3, 0.3 + 0.5 * release)

func _tunnel_radius(at: Vector3, axis: Vector3) -> float:
    var side := axis.cross(Vector3.UP)
    if side.length() < 0.1:
        side = axis.cross(Vector3.RIGHT)
    side = side.normalized()
    var up := side.cross(axis).normalized()
    var best := 0.4
    for d in [side, -side, up, -up]:
        var t := 0.2
        while t < 1.8 and terrain.density_at(at + d * t) < 0.5:
            t += 0.1
        best = maxf(best, t)
    return clampf(best + 0.2, 0.5, 2.0)

func use_spray(deep: bool = false) -> int:
    if not progression.one_handed_action_allowed():
        return -1
    var tier := progression.pick_spray_tier(deep)
    if tier < 0:
        return -1
    if vent.is_open and restroom.contains(player.global_position) and _pitch() > 0.45:
        vent.notice("spray") # sprayed at the vent being
    var hit := _look_hit()
    if hit.is_empty():
        return -1
    return progression.sprays.use(terrain, hit.position, tier, player.get_look_ray()[1])

# --- tumors -------------------------------------------------------------------------

func _nearest_tumor(dist: float) -> Node3D:
    var best: Node3D = null
    var bd := dist
    for t in tumor_nodes:
        if not is_instance_valid(t) or not t.visible:
            continue
        var d := player.camera.global_position.distance_to(t.global_position)
        if d < bd:
            bd = d
            best = t
    return best

func pick_up_tumor() -> bool:
    var t := _nearest_tumor(1.2)
    if t == null or not progression.pick_up_tumor(String(t.get_meta("kind")), carried_flesh > 0.0):
        return false
    t.visible = false
    taken_tumor_spots.append(int(t.get_meta("spot")))
    return true

func eat_tumor() -> bool:
    if progression.eat_carried_tumor():
        progression.refresh_hands(carry_mode)
        return true
    var t := _nearest_tumor(1.2)
    if t == null:
        return false
    progression.eat_tumor_kind(String(t.get_meta("kind")))
    t.visible = false
    taken_tumor_spots.append(int(t.get_meta("spot")))
    return true

# --- nerves, hazards, death --------------------------------------------------------

func _nearest_nerve(p: Vector3, dist: float) -> FDKNerveStalk:
    var best: FDKNerveStalk = null
    var bd := dist
    for n in nerves:
        if not is_instance_valid(n) or not n.visible:
            continue
        var d := n.global_position.distance_to(p)
        if d < bd:
            bd = d
            best = n
    return best

func _disturb_nerve(n: FDKNerveStalk, strength: float) -> void:
    var id := n.get_instance_id()
    if float(_nerve_cool.get(id, 0.0)) > 0.0:
        return
    _nerve_cool[id] = 2.0
    n.disturb(strength)

func _step_nerve_touch(delta: float) -> void:
    for k in _nerve_cool.keys():
        _nerve_cool[k] = float(_nerve_cool[k]) - delta
        if _nerve_cool[k] <= 0.0:
            _nerve_cool.erase(k)
    var p := player.global_position
    var danger := _regen_scale(p)
    for n in nerves:
        if not is_instance_valid(n) or not n.is_inside_tree() or not n.visible:
            continue
        if n.global_position.distance_to(p) < NERVE_TOUCH_RADIUS or n.global_position.distance_to(player.camera.global_position) < NERVE_TOUCH_RADIUS:
            _disturb_nerve(n, clampf(0.6 * danger, 0.0, 1.0))

## Touching a nerve: strong local contraction, clearly caused by the player.
func _on_nerve_disturbed(at: Vector3) -> void:
    terrain.contract_sphere(at, CONTRACT_RADIUS, CONTRACT_AMOUNT * _regen_scale(at))
    _hazards.append([at, HAZARD_TIME])

## 0..1: how close a crush death is. Rises over CRUSH_TIME while boxed in,
## falls back when the player frees themselves.
func crush_progress() -> float:
    return clampf(_crush_t / progression.crush_time(), 0.0, 1.0)

func _step_hazards(delta: float) -> void:
    if restroom.contains(player.global_position) or FPWorldFeatures.in_container(player.global_position, rest_points):
        _crush_t = 0.0
        hazard.health = minf(100.0, hazard.health + HEALTH_REGEN * delta)
        return
    var p := player.global_position
    var hurt := false
    for h in _hazards:
        h[1] -= delta
        if hazard.apply_hazard_tick(p, h[0], delta):
            hurt = true
    _hazards = _hazards.filter(func(h): return h[1] > 0.0)
    if not hurt:
        hazard.health = minf(100.0, hazard.health + HEALTH_REGEN * delta)
    if is_trapped():
        _crush_t += delta
    else:
        _crush_t = maxf(0.0, _crush_t - delta * 2.0)
    # crush is never instant: it creeps in over CRUSH_TIME while boxed in
    if _crush_t >= progression.crush_time():
        die("crush")
    elif hazard.health <= 0.0:
        die("tissue")

## Boxed in: flesh has closed in on all six sides just outside the body.
func is_trapped() -> bool:
    var p := player.global_position
    for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.DOWN]:
        if terrain.density_at(p + d * (BODY_PROTECT_RADIUS + progression.body_radius())) < CRUSH_BLOCK:
            return false
    return true

## Death: stomach contents and carried consumables drop here; only this
## spot is marked. The player wakes in the restroom. Never a wipe.
func die(cause: String) -> void:
    var at := player.global_position
    var payload := progression.take_death_payload(stomach.fill)
    stomach.fill = 0.0
    stomach.fill_changed.emit(0.0, stomach_config.capacity, stomach_config.overfill_capacity)
    carried_flesh = 0.0
    carried_units.clear()
    carry_mode = false
    chewer.stomach = stomach
    chewer.stop()
    has_canary = false
    blender_charge = 0.0
    death_drop.drop(at, payload)
    death_drop.visible = true
    hazard.reset()
    _hazards.clear()
    _crush_t = 0.0
    deaths += 1
    player.global_position = START_POS
    player.velocity = Vector3.ZERO
    died.emit(cause)

## Moving flesh keeps pushing a buried drop with no cap; the marker stays.
func _step_death_drop(delta: float) -> void:
    if not death_drop.active:
        return
    if terrain.density_at(death_drop.current_position) >= 0.5:
        var away := (death_drop.current_position - RESTROOM_CENTER).normalized()
        var push := away.cross(Vector3.UP)
        if push.length() < 0.1:
            push = Vector3.RIGHT
        death_drop.carry_along(push.normalized() * 0.04 * delta)
    var got := death_drop.try_recover(player.global_position)
    if not got.is_empty():
        stomach.add_flesh(progression.restore_death_payload(got))
        death_drop.visible = false

# --- ending ---------------------------------------------------------------------------

func reach_ending() -> void:
    if ended:
        return
    ended = true
    chewer.stop()
    player.set_physics_process(false)
    ending.start(1 + (1 if progression.codex_complete() else 0))
    ending_reached.emit()

# --- eating ---------------------------------------------------------------------------

func _on_cell_torn(world_pos: Vector3) -> void:
    var shell := shell_at(world_pos)
    hand_blood = minf(1.0, hand_blood + 0.05)
    tissue_tools.on_cell_torn(world_pos)
    if carry_mode:
        carried_flesh += stomach_config.flesh_per_cell
        carried_units[shell] = int(carried_units.get(shell, 0)) + 1
    else:
        progression.on_flesh_eaten(shell)
    var near := _nearest_nerve(world_pos, 0.7)
    if near != null:
        _disturb_nerve(near, clampf(0.5 * _regen_scale(world_pos), 0.0, 1.0))
    var chance := 0.8 if shell < 2 else 0.55
    if FDKLowPoly.hash3(int(world_pos.x * 2.0), int(world_pos.y * 2.0), int(world_pos.z * 2.0)) > chance:
        var dir := Vector3(1, 0, 0) if FDKLowPoly.hash3(int(world_pos.z * 2.0), 1, 2) > 0.5 else Vector3(-1, 0, 0)
        var q := PhysicsRayQueryParameters3D.create(world_pos, world_pos + dir * 1.5)
        var hit := get_world_3d().direct_space_state.intersect_ray(q)
        if hit and hit.collider.has_meta("fdk_terrain_chunk"):
            _spawn_nerve(hit.position, hit.normal)

# --- save/load ------------------------------------------------------------------------

func serialize() -> Dictionary:
    return {
        "version": SAVE_VERSION,
        "terrain": terrain.serialize(),
        "stomach": stomach.serialize(),
        "progression": progression.serialize(),
        "barriers": barrier_field.serialize(),
        "death_drop": death_drop.serialize(),
        "hazard": hazard.serialize(),
        "carried_flesh": carried_flesh,
        "carried_units": carried_units.duplicate(),
        "carry_mode": carry_mode,
        "blender_charge": blender_charge,
        "has_canary": has_canary,
        "canary_feed_left": canary_feed_left,
        "hand_blood": hand_blood,
        "deaths": deaths,
        "rest_seed": rest_seed,
        "opening_done": opening_done or not is_opening(),
        "ended": ended,
        "taken_tumor_spots": taken_tumor_spots.duplicate(),
        "player_position": [player.global_position.x, player.global_position.y, player.global_position.z],
        "drawings": vent.drawings.duplicate(),
    }

func deserialize(data: Dictionary) -> void:
    var v := int(data.get("version", 1))
    if data.has("terrain"):
        terrain.deserialize(data["terrain"])
    if data.has("stomach"):
        stomach.deserialize(data["stomach"])
    progression = FPProgression.new()
    if data.has("progression"):
        progression.deserialize(data["progression"])
    elif v < 3:
        # v2 saves: money -> teeth, mutation points -> common hairs
        progression.teeth = int(data.get("money", 0))
        progression.mutation_tree.add_points(FPProgression.COMMON, int(data.get("mutation_points", 0)))
    if data.has("barriers"):
        barrier_field.deserialize(data["barriers"])
    if data.has("death_drop"):
        death_drop.deserialize(data["death_drop"])
        death_drop.visible = death_drop.active
    if data.has("hazard"):
        hazard.deserialize(data["hazard"])
    carried_flesh = float(data.get("carried_flesh", 0.0))
    carried_units = (data.get("carried_units", {}) as Dictionary).duplicate()
    carry_mode = bool(data.get("carry_mode", false))
    chewer.stomach = null if carry_mode else stomach
    blender_charge = float(data.get("blender_charge", 0.0))
    has_canary = bool(data.get("has_canary", false))
    canary_feed_left = float(data.get("canary_feed_left", 0.0))
    hand_blood = float(data.get("hand_blood", 0.0))
    deaths = int(data.get("deaths", 0))
    if data.has("rest_seed"):
        tissue_tools.relayout_rest_points(int(data["rest_seed"]))
    ended = bool(data.get("ended", false))
    if bool(data.get("opening_done", v < 3)):
        finish_opening()
        opening_done = true
    taken_tumor_spots = (data.get("taken_tumor_spots", []) as Array).duplicate()
    for t in tumor_nodes:
        t.visible = not taken_tumor_spots.has(int(t.get_meta("spot")))
    _tank_teeth_shown = -1
    var pos: Array = data.get("player_position", [])
    if pos.size() == 3:
        player.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
    _restore_drawings(data.get("drawings", []) as Array)

## Crayon tumor drawings come back on the wall in the order they were given.
func _restore_drawings(kinds: Array) -> void:
    for n in drawing_nodes:
        n.queue_free()
    drawing_nodes.clear()
    vent.drawings.clear()
    for k in kinds:
        vent.drawings.append(String(k))
        _on_drawing_dropped(String(k))
