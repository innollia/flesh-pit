extends Node3D

## 화장실과 세 겹의 살점, 전체 진행을 연결한다.
## 실제 굴착·먹기 -> 위장과 즉시 털 성장 -> 변기로 토하기 -> 물내림과 이빨 정산 ->
## 환풍구 거래·거울 변이 -> 더 깊이 굴착 -> 바깥으로 탈출.
## Game rules live here and in fp_*.gd; nothing in addons/ refers back.
## Visuals of the new systems are placeholder shapes only.

signal died(cause: String)
signal ending_reached
signal canary_chirp(urgency: float)
signal canary_cry(frightened: bool)
signal flushed(teeth_gain: int, hair_gain: int)
## Opening: the flush heard on the black screen (audio: game/audio_HOOKUP.md).
signal opening_flush
## Sound hooks for stage-5 events that had no signal (game/audio/HOOKUP.md).
signal spray_used(world_pos: Vector3)
signal blender_drunk
signal scissors_snipped
signal saw_stroked
signal settle_ticked(teeth_gain: int)
signal ui_clicked
## Look-down belt swap (fp_belt_swap.gd): a tool hung / taken, or refused.
signal belt_swapped(from_id: String, to_id: String)
signal belt_refused

const SAVE_VERSION := 5

const RESTROOM_CENTER := Vector3(0, 1, 0)
## The signed density ramp places the flesh surface against the room walls.
const ROOM_MARGIN := 0.04
## Right in front of the door the margin is pulled down to under 5 cm.
const DOOR_GAP := 0.04
const MEMBRANE_THICKNESS := 0.9
const VOMIT_BUTTON_OVERFILL := 0.35
const WORLD_GEN_HALF := 10.0
const SHELL_THICKNESS := FPWorldFeatures.SHELL_THICKNESS
const OUTER_RADIUS := FPWorldFeatures.OUTER_RADIUS
const START_POS := Vector3(FPRestroom.TOILET_X + 0.64, 0.95, FPRestroom.TOILET_Z)
const START_YAW := -PI * 0.5 - 0.02
const START_PITCH := -0.32
const SEAT_POS := Vector3(FPRestroom.TOILET_X + 0.30, 0.55, FPRestroom.TOILET_Z)
const SEAT_YAW := -PI * 0.5
const OPENING_TIME := FPOpening.TOTAL
const BODY_PROTECT_RADIUS := 0.9
const CRUSH_TIME := 6.0
const CRUSH_BLOCK := 0.8
const NERVE_TOUCH_RADIUS := 0.45
const CONTRACT_RADIUS := 1.3
const CONTRACT_AMOUNT := 0.45
const HAZARD_TIME := 1.2
const HEALTH_REGEN := 12.0
## Keep barrier load above its 0.15/s relaxation after the slower regrowth.
## 0.003 * (0.28 / 0.003) preserves the previous 0.01 * 28 pressure
## at the same depth without changing barrier strength or relaxation.
const BARRIER_PRESSURE := 0.28 / 0.003
const CANARY_TICK := 0.25
const CANARY_FEED_TIME := 120.0
const REACH := 2.5

@export var terrain_config: FDKTerrainConfig = FDKTerrainConfig.new()
@export var stomach_config: FDKStomachConfig = FDKStomachConfig.new()

var excavated_cells := 0
var stomach_hud: FPStomachHUD
var terrain: FDKTerrainField
var stomach: FDKStomach
var chewer: FDKChewer
var player: FDKFirstPersonController
var hands_rig: FDKHandsRig:
    get: return player.hands_rig as FDKHandsRig
    set(v): player.hands_rig = v
var restroom: FPRestroom
var tank_lid: FPTankLid
var stomach_view: FPStomachView
var vomit_button: FPVomitButton
var settle_camera: Camera3D
var environment: Environment
var player_lamp: OmniLight3D
var body_fill: OmniLight3D
const BODY_LAYER := 1 << 11 ## the first-person waist (belt, shirt, trousers)
const BODY_FILL := 0.35 ## body fill energy per unit of player lamp energy
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
var mirror: FPMirror ## forearm hologram mutation screen (fp_mutate key)
var mirror_view_right: FPMirrorReflection
var mirror_view: FPMirrorReflection ## the restroom mirror: reflection only
var _mutate_guard_frame := -1
var ending: FPEnding
var art_hookup: FPArtHookup
var hand_actions: FPHandActions
var belt_swap: FPBeltSwap
## Situational hand / body motions (fp_hand_motions.gd).
var hand_motions: FPHandMotions
var _body_clearance := FPBodyClearance.new()
var _body_relief_needed := false
var mutation_apply: FPMutationApply
var rest_points: Array[Vector3] = []
var _world_density_cache: Dictionary = {}
const WORLD_DENSITY_CACHE_LIMIT := 8192
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
var _opening_rising := false
var _chew_ratio: float = 0.0
## 형님 2026-09-29: keeps the chewer aimed at one cell for the whole hold, so a
## sub-pixel raycast drift does not reset FDKChewer's progress every frame.
var _chew_target: Vector3 = Vector3.INF
var _chew_contact: Vector3 = Vector3.INF
## Camera motion owns the desired local pose; terrain contact is temporary.
var _terrain_eye_delta := Vector3.ZERO
var _terrain_eye_pose := Vector3.ZERO
## Bounded query metadata only; no contacts or poses survive a shape change.
var _terrain_query_shapes: Dictionary = {}
var _settling: bool = false
var _settle_entry_frame: int = -1
var _settle_amount: float = 0.0
var _mirror_open: bool = false
## Sitting on the toilet (F at the bowl while standing).
var _seated: bool = false
## Esc menu: key settings screen (fp_keybind_menu.gd).
var keybind_menu: FPKeybindMenu
## Title screen, Esc pause and settings (fp_title_screen.gd, fp_pause_menu.gd,
## fp_settings_menu.gd). Settings live in user://settings.json (FPSettings).
var title_screen: FPTitleScreen
var pause_menu: FPPauseMenu
var settings_menu: FPSettingsMenu
var settings: Dictionary = {}
## Where the run is saved on disk (title "이어하기", pause "저장하고 시작 화면으로").
var save_path: String = "user://save.bin"
const AUTOSAVE_INTERVAL := 30.0
var _autosave_elapsed := 0.0
var _esc_guard_frame: int = -10
var _crush_t: float = 0.0
var _hazards: Array = []
var _nerve_cool: Dictionary = {}
var _canary_t: float = 0.0
var glare_controller := FPGlareController.new()
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
    terrain.surface_constraint = _room_surface_constraint
    for id in range(FDKChunk.TISSUE_TEXTURES.size()):
        var tissue_mat := FDKChunk.terrain_material(id)
        tissue_mat.set_shader_parameter("fit_room_seams", true)
        tissue_mat.set_shader_parameter("room_half", FPRestroom.HALF)
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

    ## hands_rig is now a computed property mirroring player.hands_rig (see
    ## its declaration above); no assignment needed here.
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
    # the lamp sits a hand's width from the eye, so looking down it blew the
    # shirt and belt out to white in the flesh; the body (belt, torso,
    # trousers) is on BODY_LAYER, which the lamp skips, and gets a soft fill
    player_lamp.light_cull_mask = 0xFFFFF & ~BODY_LAYER & ~FPMirrorReflection.MIRROR_BODY_LAYER
    body_fill = OmniLight3D.new()
    body_fill.name = "BodyFill"
    body_fill.light_color = player_lamp.light_color
    body_fill.light_cull_mask = BODY_LAYER
    body_fill.omni_range = 3.0
    body_fill.position = Vector3(0.1, 0.3, 0.2)
    body_fill.light_energy = 0.0
    player.camera.add_child(body_fill)

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
    belt_swap = FPBeltSwap.new(self)
    hand_actions = FPHandActions.new(self)
    hand_motions = FPHandMotions.new(self)
    # Capture the neutral animation base before a terrain correction can
    # be mistaken for a permanent offset by the first hand motion.
    hand_motions._save_cams()
    get_tree().process_frame.connect(_restore_frame_camera)
    RenderingServer.frame_pre_draw.connect(_guard_terrain_eye)
    mutation_apply = FPMutationApply.new()
    mutation_apply.name = "MutationApply"
    add_child(mutation_apply)
    mutation_apply.setup(self)

    _setup_environment()
    _build_ui()
    _build_settle_camera()
    _setup_restroom_front()
    tank_lid = FPTankLid.new()
    tank_lid.name = "LooseTankLid"
    add_child(tank_lid)
    tank_lid.setup(self)
    _setup_front_menus()
    # every on-screen button clicks (vomit button, key settings, mirror ...)
    get_tree().node_added.connect(_on_node_added_for_click)
    for b in find_children("*", "BaseButton", true, false):
        _on_node_added_for_click(b)
    flushed.connect(func(teeth, _hairs): settle_ticked.emit(teeth))
    var audio_hookup: Node = preload("res://audio/fp_audio_hookup.gd").new()
    audio_hookup.name = "AudioHookup"
    add_child(audio_hookup)
    # volume buses: beds to Music, everything else to SFX (FPSettings)
    get_tree().node_added.connect(_on_node_added_for_bus)
    for a in find_children("*", "AudioStreamPlayer", true, false) + find_children("*", "AudioStreamPlayer3D", true, false):
        FPSettings.route_player.call_deferred(a)

func _on_node_added_for_bus(n: Node) -> void:
    if n is AudioStreamPlayer or n is AudioStreamPlayer3D:
        FPSettings.route_player.call_deferred(n)

func _on_node_added_for_click(n: Node) -> void:
    if n is BaseButton and is_ancestor_of(n) and not n.pressed.is_connected(ui_clicked.emit):
        (n as BaseButton).pressed.connect(ui_clicked.emit)

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
                    if path == USER_KEYBINDS_PATH and not binds.has(k):
                        continue
                    var merged: Dictionary = binds.get(k, {}).duplicate()
                    merged.merge(d["키"][k], true)
                    binds[k] = merged
    for retired in ["fp_spray", "fp_blend", "fp_feed_canary", "fp_tool_1", "fp_tool_2", "fp_tool_3", "fp_tool_4"]:
        if InputMap.has_action(retired):
            InputMap.erase_action(retired)
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
        if int(b.get("마우스", -1)) > 0:
            var mouse := InputEventMouseButton.new()
            mouse.button_index = int(b["마우스"])
            InputMap.action_add_event(action, mouse)
        if int(b.get("패드", -1)) >= 0:
            var jb := InputEventJoypadButton.new()
            jb.button_index = int(b["패드"])
            InputMap.action_add_event(action, jb)
    # Rebinding rebuilds events, including the default triggers and hand buttons.
    (load("res://main/scripts/fp_input_modes.gd") as GDScript).call("register")

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

## World-shape rules delegate to FPWorldFeatures (static, unit-testable
## without a main instance); this stays as the call site the rest of
## main.gd and every test already use.
func _room_dist(p: Vector3) -> float:
    return FPWorldFeatures.room_dist(p, FPRestroom.HALF)

func _world_density(p: Vector3) -> float:
    if _world_density_cache.has(p):
        return _world_density_cache[p]
    # The ceiling duct stays empty and dark instead of revealing exterior flesh.
    var vent_offset := p - FPRestroom.VENT_CENTER
    var density: float
    if absf(vent_offset.x) < 0.30 and absf(vent_offset.z) < 0.30 and vent_offset.y >= -0.04 and vent_offset.y < 0.8:
        density = 0.0
    else:
        density = FPWorldFeatures.world_density(p, FPRestroom.HALF, FPRestroom.DOOR_HALF_W, FPRestroom.DOOR_H,
            ROOM_MARGIN, DOOR_GAP, RESTROOM_CENTER, OUTER_RADIUS, rest_points)
    if _world_density_cache.size() >= WORLD_DENSITY_CACHE_LIMIT:
        _world_density_cache.clear()
    _world_density_cache[p] = density
    return density

func _room_surface_constraint(p: Vector3) -> Vector3:
    var vent_offset := p - FPRestroom.VENT_CENTER
    if absf(vent_offset.x) < 0.38 and absf(vent_offset.z) < 0.38 and vent_offset.y > -0.04:
        return p
    # Keep the exposed doorway organic; only concealed room seams are fitted.
    if p.z > FPRestroom.HALF.z - 0.25 and absf(p.x) < FPRestroom.DOOR_HALF_W + 0.12 and p.y > 0.1 and p.y < FPRestroom.DOOR_H - 0.08:
        return p
    var h := FPRestroom.HALF + Vector3.ONE * 0.055
    var q := Vector3(absf(p.x) - h.x, absf(p.y - FPRestroom.HALF.y) - h.y, absf(p.z) - h.z)
    if maxf(q.x, maxf(q.y, q.z)) > 0.35:
        return p
    # Snap adjoining faces together at corners too: projecting only the
    # closest face leaves diagonal triangles cutting through the tiles.
    if q.x > -0.35:
        p.x = signf(p.x) * h.x
    if q.y > -0.35:
        p.y = FPRestroom.HALF.y + signf(p.y - FPRestroom.HALF.y) * h.y
    if q.z > -0.35:
        p.z = signf(p.z) * h.z
    return p

func _in_door_column(p: Vector3) -> bool:
    return FPWorldFeatures.in_door_column(p, FPRestroom.DOOR_HALF_W, FPRestroom.DOOR_H)

func shell_at(p: Vector3) -> int:
    return FPWorldFeatures.shell_of_depth(p.distance_to(RESTROOM_CENTER))

## Tissue ids: 0 flesh, 1 nerve bundle, 2 fat band (shell boundary),
## 3 membrane (restroom shell), 4 contractile fibers (mantle, needs a blade).
func _world_tissue(p: Vector3) -> int:
    var room := _room_dist(p) < MEMBRANE_THICKNESS + ROOM_MARGIN and not _in_door_column(p)
    # Initial exposed doorway is flesh; nerves belong to newly excavated depth.
    if _in_door_column(p) and p.z > FPRestroom.HALF.z - 0.2 and p.z < FPRestroom.HALF.z + 1.0 and p.y > -0.1 and p.y < FPRestroom.DOOR_H + 0.3:
        return FDKTissueRules.COMPRESSIVE
    return FPWorldFeatures.world_tissue_at(p, RESTROOM_CENTER, _noise.get_noise_3dv(p), room)

func _regen_scale(p: Vector3) -> float:
    return FPWorldFeatures.regen_scale(p, RESTROOM_CENTER, SHELL_THICKNESS)

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

func _add_nerve(n: FDKNerveStalk) -> void:
    if not is_instance_valid(n) or n.is_queued_for_deletion():
        return
    n.remove_meta("pending_add")
    if not n.update_anchor():
        nerves.erase(n)
        n.free()
        return
    add_child(n)

func _update_nerve_anchors() -> void:
    var surviving: Array[FDKNerveStalk] = []
    for n in nerves:
        if not is_instance_valid(n) or n.is_queued_for_deletion():
            continue
        if n.update_anchor():
            surviving.append(n)
        elif n.is_inside_tree():
            n.queue_free()
        elif not n.has_meta("pending_add"):
            n.free()
    nerves = surviving

func _spawn_nerve(at: Vector3, normal: Vector3) -> FDKNerveStalk:
    if excavated_cells < 8 or restroom.contains(at):
        return null
    var n := FDKNerveStalk.new()
    n.length = randf_range(0.35, 0.65)
    n.terrain = terrain
    n.place(at, normal)
    # 삼각형 접점과 연속 밀도 경계의 작은 차이를 현재 살점에서 해결한다.
    # 먼 고체로 이동하지 않고 기존 기반 탐침 .15m 안의 첫 iso 교차만 찾는다.
    var iso: float = terrain_config.iso_level
    if n.sample_density(at) < iso and n.sample_density(n.base_probe) >= iso:
        var axis := normal.normalized()
        var outside := at
        for step in range(1, 17):
            var inside := at - axis * (0.15 * float(step) / 16.0)
            if n.sample_density(inside) >= iso:
                for iteration in range(12):
                    var middle := outside.lerp(inside, 0.5)
                    if n.sample_density(middle) >= iso:
                        inside = middle
                    else:
                        outside = middle
                n.place(inside, normal)
                break
            outside = inside
    if not n.is_anchored():
        n.free()
        return null
    n.set_meta("pending_add", true)
    call_deferred("_add_nerve", n)
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
    environment.ambient_light_color = Color(0.85, 0.87, 0.9)
    environment.ambient_light_energy = 0.12
    environment.fog_enabled = false
    environment.fog_light_color = Color(0.22, 0.03, 0.05)
    environment.fog_density = 0.09
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    we.environment = environment
    var sun: DirectionalLight3D = get_node_or_null("DirectionalLight3D")
    if sun != null:
        sun.light_energy = 0.12
        sun.light_color = Color(0.96, 0.97, 1.0)

func _is_dark_atmosphere(p: Vector3) -> bool:
    var inside := restroom.contains(p)
    var door_center := restroom.global_position + Vector3(0.0, 1.0, FPRestroom.HALF.z)
    return FPGlareController.is_dark_at(inside, p.distance_to(door_center), restroom.door_open_amount(), terrain.depth_at(p))

func _reset_glare() -> void:
    glare_controller.reset(true)
    _flash = 0.0
    if environment != null:
        environment.tonemap_exposure = 1.0

func _update_atmosphere(delta: float, immediate: bool = false) -> void:
    var inside := restroom.contains(player.global_position)
    var glare_factor: float = progression.restroom_glare_factor() if progression != null else 1.0
    glare_controller.step(inside, 0.0 if immediate else delta, _is_dark_atmosphere(player.global_position), glare_factor)
    _flash = glare_controller.flash
    environment.tonemap_exposure = 1.0 + 2.5 * _flash
    var k := 1.0 if immediate else 1.0 - exp(-delta * 3.0)
    var depth_tone := clampf(terrain.depth_at(player.global_position) / terrain_config.depth_tone_distance, 0.0, 1.0)
    environment.fog_density = lerpf(environment.fog_density, 0.01 if inside else lerpf(0.1, 0.2, depth_tone), k)
    environment.ambient_light_color = environment.ambient_light_color.lerp(Color(0.85, 0.87, 0.9) if inside else Color(0.55, 0.22, 0.24), k)
    environment.ambient_light_energy = lerpf(environment.ambient_light_energy, 0.12 if inside else 0.42, k)
    player_lamp.light_energy = lerpf(player_lamp.light_energy, 0.0 if inside else 2.4, k)
    body_fill.light_energy = player_lamp.light_energy * BODY_FILL
    if not inside:
        environment.fog_light_color = Color(0.22, 0.03, 0.05).lerp(Color(0.1, 0.01, 0.07), depth_tone)

func apply_atmosphere_now() -> void:
    _update_atmosphere(0.0, true)

## 0..1 loudness of the ending melody inside the flesh (louder outward).
func melody_level() -> float:
    if restroom.contains(player.global_position):
        return 0.0
    return clampf(pow(terrain.depth_at(player.global_position) / OUTER_RADIUS, 1.5), 0.0, 1.0)

# --- UI ---------------------------------------------------------------------------

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    layer.name = "HUD"
    layer.layer = 22
    add_child(layer)
    stomach_hud = FPStomachHUD.new()
    stomach_hud.main = self
    layer.add_child(stomach_hud)
    vomit_button = FPVomitButton.new()
    vomit_button.name = "VomitButton"
    layer.add_child(vomit_button)
    vomit_button.pressed.connect(request_vomit)
    vomit_button.pressed.connect(ui_clicked.emit)
    interact_ring = (load("res://main/scripts/fp_interact_ring.gd") as GDScript).new()
    interact_ring.name = "InteractRing"
    # Own layer above the PS1 post (layer 20): under it the thin ring was
    # pixelated and dithered away.
    var ring_layer := CanvasLayer.new()
    ring_layer.name = "InteractRingLayer"
    ring_layer.layer = 21
    add_child(ring_layer)
    ring_layer.add_child(interact_ring)
    mirror = FPMirror.new()
    mirror.name = "Mirror"
    add_child(mirror)
    mirror.closed.connect(_on_mirror_closed)
    # the real mirror: the player's own body stands in the world (seen only
    # by the mirror's reflection camera), the glass shows it
    mirror_view = FPMirrorReflection.new()
    mirror_view.name = "MirrorView"
    add_child(mirror_view)
    mirror_view.attach(restroom.mirror_art.call("reflection_surface"), player, player.camera, progression)
    mirror_view_right = FPMirrorReflection.new()
    mirror_view_right.name = "MirrorViewRight"
    add_child(mirror_view_right)
    mirror_view_right.attach(restroom.mirror_art.door_surface_right, player, player.camera, progression, mirror_view.body)
    keybind_menu = FPKeybindMenu.new()
    keybind_menu.name = "KeybindMenu"
    add_child(keybind_menu)
    keybind_menu.setup(self)
    keybind_menu.closed.connect(_on_keybind_menu_closed)
    ending = FPEnding.new()
    ending.name = "Ending"
    add_child(ending)
    ending.finished.connect(_on_ending_finished)

func _build_settle_camera() -> void:
    settle_camera = Camera3D.new()
    settle_camera.name = "SettleCamera"
    settle_camera.fov = 66.0
    settle_camera.near = 0.02
    settle_camera.cull_mask &= ~FPMirrorReflection.MIRROR_BODY_LAYER
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
    FPHandBlood.set_amount(hand_blood_mat, maxf(hand_blood, hand_motions.blood_visual() if hand_motions != null else 0.0))

## Hands (and anything they carry) live outside FPRestroom's tree (parented
## to the player camera), so restroom.gd's room-only render layer never
## reaches them: rest-container lamps outside excluded that layer from their
## light_cull_mask, but the hands stayed on the default layer and still
## picked up the green lamp light while inside the room. Toggle the hands'
## layer to match whichever side of the wall the player is actually on, only
## on the edge crossing so this stays a cheap once-per-frame bool check.
var _hands_in_room: bool = false

func _update_hands_room_layer() -> void:
    var inside := restroom.contains(player.global_position)
    if inside == _hands_in_room:
        return
    _hands_in_room = inside
    if inside:
        _tag_hands_layer(hands_rig, FPMirrorReflection.HANDS_ROOM_LAYER)
    else:
        FPRestroom.tag_default_layer(hands_rig)

## Hands in the room: their own bit (FPMirrorReflection.HANDS_ROOM_LAYER) instead of
## the room layer, so the mirror's reflection camera can leave the
## first-person hands out while the eye camera and room lights still see them.
func _tag_hands_layer(n: Node, bits: int) -> void:
    if n is VisualInstance3D and not (n is Light3D):
        (n as VisualInstance3D).layers = bits
    for c in n.get_children():
        _tag_hands_layer(c, bits)

## The player finishes on the toilet, stands up, opens the stall door.
func _begin_opening() -> void:
    _opening_t = 0.0
    _opening_rising = false
    opening_view.start_hints()
    player.global_position = SEAT_POS
    player.set("_yaw", SEAT_YAW)
    player.rotation.y = SEAT_YAW
    player.set("_pitch", OPENING_SEAT_PITCH)
    player.camera_pivot.rotation.x = OPENING_SEAT_PITCH
    player.set_physics_process(false)
    if opening_view != null:
        opening_view.apply(0.0)
    opening_flush.emit()

func _process_opening(delta: float) -> void:
    if _opening_t < 0.0:
        return
    var seated_until := FPOpening.BLACK_TIME + FPOpening.FADE_TIME
    if not _opening_rising:
        _opening_t = minf(_opening_t + delta, seated_until)
        opening_view.waiting_to_rise = _opening_t >= seated_until
        if opening_view.waiting_to_rise and Input.is_action_just_pressed("fdk_move_forward"):
            _opening_rising = true
            opening_view.waiting_to_rise = false
            opening_view.show_movement_hints()
    else:
        _opening_t += delta
    apply_opening_at(_opening_t)
    if _opening_t >= OPENING_TIME:
        finish_opening()

## Poses the opening at time t (also used by captures and tests).
func apply_opening_at(t: float) -> void:
    var k := FPOpening.rise_at(t)
    player.global_position = SEAT_POS.lerp(Vector3(SEAT_POS.x + 0.28, START_POS.y, SEAT_POS.z), k)
    var pitch := lerpf(OPENING_SEAT_PITCH, 0.0, k)
    player.set("_pitch", pitch)
    player.camera_pivot.rotation.x = pitch
    if opening_view != null:
        opening_view.apply(t)

func finish_opening() -> void:
    if _opening_t < 0.0:
        return
    _opening_t = -1.0
    opening_view.waiting_to_rise = false
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
    _restore_frame_camera()
    _update_atmosphere(delta)
    _update_restroom_front()
    _update_hands_room_layer()
    player.climb_enabled = can_climb_at(player.global_position)
    stomach_view.set_state(stomach.fill_ratio(), stomach.overfill_ratio())
    vomit_button.shown = not _settling and stomach.overfill_ratio() >= VOMIT_BUTTON_OVERFILL
    opening_view.hints.vomit_hint = not _settling and stomach.fill_ratio() >= 1.0
    hands_rig.set_mutation(progression.mutation_amount())
    hands_rig.set_carry(clampf(carried_flesh / 40.0, 0.0, 1.0) if carried_flesh > 0.0 else 0.0)
    vent.tick(delta)
    hand_motions.check_cancel()
    hand_motions.tick(delta)
    _guard_terrain_eye(false, false)
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
        FPInteractions.handle_settling_input(self, _settle_entry_frame)
        return
    if keybind_menu != null and keybind_menu.is_open():
        chewer.stop()
        return
    if _seated:
        chewer.stop()
        _process_seated()
        return
    if _mirror_open:
        _process_mirror_look()
        return
    if Input.is_action_just_pressed("ui_cancel") and handle_esc() != "":
        return
    if InputMap.has_action("fp_mutate") and Input.is_action_just_pressed("fp_mutate") and Engine.get_process_frames() != _mutate_guard_frame:
        open_mirror()
        return
    _handle_actions()
    hand_actions.tick(delta)
    step_world(delta)
    _guard_terrain_eye(false)
    tick_autosave(delta)

# Start of a new frame, before hand/mutation camera writers. Do not use this
# combined restore inside _guard_terrain_eye: that would remove the effect.
func _restore_frame_camera() -> void:
    if danger_show != null:
        danger_show.restore_camera()
    _restore_terrain_eye()

func _physics_process(delta: float) -> void:
    if not _body_relief_needed or ended or _seated or _settling or is_opening():
        return
    if not is_instance_valid(player) or not is_instance_valid(terrain):
        return
    if restroom.contains(player.global_position) or FPWorldFeatures.in_container(player.global_position, rest_points):
        _body_relief_needed = false
        return
    # Never reuse the process-loop verdict: growth and publication may have
    # changed meanwhile. Ordinary movement/collision remains authoritative.
    var current: Dictionary = _body_clearance.assess(player, terrain)
    _body_relief_needed = bool(current.overlap) and not bool(current.trapped)
    if _body_relief_needed:
        _body_clearance.relieve(player, current, delta)

func _restore_terrain_eye() -> void:
    if is_instance_valid(player) and is_instance_valid(player.camera):
        # A motion or scene transition may replace the local camera pose
        # outright between ticks; its new desired pose has no old correction.
        if player.camera.position.is_equal_approx(_terrain_eye_pose):
            player.camera.position -= _terrain_eye_delta
    _terrain_eye_delta = Vector3.ZERO

func _guard_terrain_eye(update_nerves: bool = true, sync_mirrors: bool = true) -> void:
    if update_nerves:
        _update_nerve_anchors()
    # Also reached by production frame_pre_draw, after late child mutation
    # writes. Recompose without advancing shake time, then constrain the eye.
    if danger_show != null:
        danger_show.apply_camera()
    if not is_instance_valid(player) or not is_instance_valid(player.camera) or not is_instance_valid(terrain):
        return
    _restore_terrain_eye()
    var desired_local: Vector3 = player.camera.position
    player.camera.global_position = terrain.constrain_eye(player.camera.global_position, player.global_position, player.camera.near)
    _terrain_eye_delta = player.camera.position - desired_local
    _terrain_eye_pose = player.camera.position
    # Terrain can publish after the main tick. Flush the corrected camera
    # transform so the renderer does not retain the previous frame's view.
    player.camera.force_update_transform()
    # The aim guard does not update mirrors; they consume the final pose.
    if not sync_mirrors:
        return
    var mirrors_active: bool = restroom.contains(player.global_position) and not _seated and not _settling
    if mirror_view != null:
        mirror_view.sync(mirrors_active, has_canary)
    if mirror_view_right != null:
        mirror_view_right.sync(mirrors_active, has_canary)

func _exit_tree() -> void:
    if RenderingServer.frame_pre_draw.is_connected(_guard_terrain_eye):
        RenderingServer.frame_pre_draw.disconnect(_guard_terrain_eye)

func tick_autosave(delta: float) -> void:
    if is_opening() or ended or _settling or hand_motions.kind.begins_with("vomit") or get_tree().paused:
        return
    _autosave_elapsed += delta
    if _autosave_elapsed >= AUTOSAVE_INTERVAL and save_to_disk():
        _autosave_elapsed = 0.0

func can_climb_at(at: Vector3) -> bool:
    if restroom.contains(at):
        return false
    if terrain.density_at(at) >= 0.5:
        return true
    # Climb along flesh beside an excavated tunnel; an empty center is
    # normal after tearing. The ground alone does not enable Space.
    for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
        if terrain.density_at(at + direction * 0.6) >= 0.5:
            return true
    return false

func _handle_actions() -> void:
    if tank_lid.held:
        if Input.is_action_just_pressed("fp_interact"):
            tank_lid.drop()
        return
    if Input.is_action_just_pressed("fp_carry"):
        toggle_carry()
    if Input.is_action_just_pressed("fp_vomit"):
        request_vomit()
    if Input.is_action_just_pressed("fp_interact"):
        _interact()
    if Input.is_action_just_pressed("fp_barrier"):
        place_barrier()
    if Input.is_action_just_pressed("fp_eat_tumor"):
        eat_tumor()
    if Input.is_action_just_pressed("fp_tool_next"):
        cycle_tool()
    if Input.is_action_just_pressed("fp_tool_prev"):
        cycle_tool(-1)

func _chew_step(delta: float) -> void:
    if tank_lid.held:
        chewer.stop()
        return
    if hands_rig.state == FDKHandsRig.HandState.TEAR:
        terrain.set_press(Vector3.ZERO, Vector3.BACK, 0.0)
        return
    var dir: Vector3 = player.get_look_ray()[1]
    var hit := _look_hit()
    if hit.is_empty() or not hit.collider.has_meta("fdk_terrain_chunk"):
        chewer.stop()
        terrain.set_press(Vector3.ZERO, Vector3.BACK, 0.0)
        _chew_target = Vector3.INF
        _chew_contact = Vector3.INF
        return
    # A locked grab must still have real unoccluded contact. Nearby collider
    # motion is allowed without restarting progress on the same cell.
    if chewer.is_chewing() and _chew_target != Vector3.INF and _chew_contact != Vector3.INF and _looking_at(_chew_contact, 12.0, progression.reach()) and terrain.density_at(_chew_target) >= terrain_config.iso_level and _chew_target.distance_to(hit.position) <= terrain_config.cell_size * 1.5:
        if tissue_tools.chew_at(_chew_target, hit.position, dir, delta):
            terrain.set_press(hit.position, -dir, _chew_ratio if hands_rig.state != FDKHandsRig.HandState.TEAR else 0.0)
        return
    var target := _terrain_target(hit, dir)
    _chew_target = target
    _chew_contact = hit.position
    # hardness per tissue, membrane only with a blade (fp_tissue_tools.gd)
    if tissue_tools.chew_at(target, hit.position, dir, delta):
        terrain.set_press(hit.position, -dir, _chew_ratio if chewer.is_chewing() and hands_rig.state != FDKHandsRig.HandState.TEAR else 0.0)
    else:
        _chew_target = Vector3.INF
        _chew_contact = Vector3.INF

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
    if belt_swap != null:
        belt_swap.tick(delta)
    if interact_ring != null:
        interact_ring.set("shown", interact_target() != "")
    _step_death_drop(delta)
    terrain.step_contraction(delta, player.global_position)
    tissue_tools.step_charge(delta, hand_actions.charging())
    tissue_tools.step_blend(delta)
    if not ended and player.global_position.distance_to(RESTROOM_CENTER) >= OUTER_RADIUS - 0.3:
        reach_ending()

func _look_hit() -> Dictionary:
    var ray: Array = player.get_look_ray()
    var reach: float = progression.reach()
    var q := PhysicsRayQueryParameters3D.create(ray[0], ray[0] + ray[1] * reach)
    q.exclude = [player.get_rid()]
    q.hit_from_inside = true
    q.hit_back_faces = true
    var space := get_world_3d().direct_space_state
    var hit := space.intersect_ray(q)
    var solid_contact := {}
    if terrain != null and terrain.has_method("solid_contact_ray"):
        var sc: Dictionary = terrain.solid_contact_ray(ray[0], ray[0] + ray[1] * reach)
        if not sc.is_empty():
            var body = sc.get("collider", null)
            if body != null and is_instance_valid(body) and body is CollisionObject3D:
                var dist: float = ray[0].distance_to(sc.position)
                if dist <= reach and (sc.position - ray[0]).dot(ray[1]) > 0.00001:
                    var obstruction := PhysicsRayQueryParameters3D.create(ray[0], sc.position)
                    obstruction.exclude = [player.get_rid()]
                    obstruction.hit_from_inside = true
                    var blocking := space.intersect_ray(obstruction)
                    if not blocking.is_empty() and not blocking.collider.has_meta("fdk_terrain_chunk"):
                        solid_contact = blocking
                    else:
                        solid_contact = sc
    var current_face: bool = not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk") and _physics_face_matches(hit, ray[0], ray[1])
    # A stable rear face alone does not prove that a nearer chunk has
    # synchronized. Check every chunk intersecting this bounded ray before
    # using its exact current published face as the normal fast path.
    if current_face and _terrain_ray_shapes_synced(ray[0], ray[1], reach):
        return _nearest_look_contact([hit, solid_contact], ray[0], ray[1], reach)
    if not hit.is_empty() and hit.collider.has_meta("fdk_terrain_chunk") and not current_face:
        hit = {}
    var published := _published_terrain_contact(ray[0], ray[1], reach)
    var chosen := _nearest_look_contact([hit, published, solid_contact], ray[0], ray[1], reach)
    if not chosen.is_empty():
        return chosen
    # Exact shared triangle vertices can miss numerically. These one-mm
    # parallel rays retain reach and accept only actual terrain contacts.
    var right: Vector3 = player.camera.global_basis.x.normalized()
    var up: Vector3 = player.camera.global_basis.y.normalized()
    var nearest := reach + 0.001
    var result := {}
    for offset in [right, -right, up, -up, (right + up).normalized(), (right - up).normalized(), (-right + up).normalized(), (-right - up).normalized()]:
        var shifted: Vector3 = ray[0] + offset * 0.001
        q.from = shifted
        q.to = shifted + ray[1] * reach
        var candidate := space.intersect_ray(q)
        if candidate.is_empty() or not candidate.collider.has_meta("fdk_terrain_chunk") or not _physics_face_matches(candidate, shifted, ray[1]):
            candidate = {}
        if terrain != null and terrain.has_method("solid_contact_ray"):
            var vcandidate: Dictionary = terrain.solid_contact_ray(shifted, shifted + ray[1] * reach)
            if not vcandidate.is_empty():
                var vbody = vcandidate.get("collider", null)
                if vbody != null and is_instance_valid(vbody) and vbody is CollisionObject3D:
                    var vdist: float = ray[0].distance_to(vcandidate.position)
                    if vdist <= reach and (vcandidate.position - ray[0]).dot(ray[1]) > 0.00001:
                        candidate = _nearest_look_contact([candidate, vcandidate], ray[0], ray[1], reach)
        if candidate.is_empty():
            continue
        var distance: float = ray[0].distance_to(candidate.position)
        if distance > reach or distance >= nearest:
            continue
        var obstruction := PhysicsRayQueryParameters3D.create(ray[0], candidate.position)
        obstruction.exclude = [player.get_rid()]
        obstruction.hit_from_inside = true
        var blocking := space.intersect_ray(obstruction)
        if not blocking.is_empty() and not blocking.collider.has_meta("fdk_terrain_chunk"):
            continue
        nearest = distance
        result = candidate
    return result

func _physics_face_matches(hit: Dictionary, origin: Vector3, direction: Vector3) -> bool:
    var chunk := hit.collider.get_parent() as FDKChunk
    if chunk == null or chunk._collision.shape == null:
        return false
    var shape: ConcavePolygonShape3D = chunk._collision.shape
    if PhysicsServer3D.body_get_shape(hit.rid, int(hit.get("shape", 0))) != shape.get_rid():
        return false
    var faces := shape.get_faces()
    var index := int(hit.get("face_index", -1)) * 3
    if index < 0 or index + 2 >= faces.size():
        return false
    var transform: Transform3D = chunk.global_transform
    var contact = Geometry3D.ray_intersects_triangle(origin, direction, transform * faces[index], transform * faces[index + 1], transform * faces[index + 2])
    return contact != null and origin.distance_to(contact) <= progression.reach() and (contact - origin).dot(direction) > 0.00001 and (contact as Vector3).distance_to(hit.position) <= 0.0001

func _terrain_ray_shapes_synced(origin: Vector3, direction: Vector3, reach: float) -> bool:
    var frame := Engine.get_physics_frames()
    var synced := true
    for chunk in _terrain_ray_chunks(origin, direction, reach):
        var key: int = chunk.get_instance_id()
        var shape_rid: RID = chunk._collision.shape.get_rid() if chunk._collision.shape != null else RID()
        var known: Dictionary = _terrain_query_shapes.get(key, {})
        if known.get("shape") != shape_rid:
            if _terrain_query_shapes.size() >= 32:
                _terrain_query_shapes.clear()
            _terrain_query_shapes[key] = {"shape": shape_rid, "observed": frame}
            synced = false
        elif frame - int(known.observed) < 2:
            synced = false
        if shape_rid.is_valid() and PhysicsServer3D.body_get_shape(chunk.get_body().get_rid(), 0) != shape_rid:
            synced = false
    return synced

func _nearest_look_contact(candidates: Array, origin: Vector3, direction: Vector3, reach: float) -> Dictionary:
    var result := {}
    var closest := reach + 0.00001
    for candidate in candidates:
        if (candidate as Dictionary).is_empty():
            continue
        var offset: Vector3 = candidate.position - origin
        var distance := offset.length()
        if distance > reach or offset.dot(direction) < -0.00001:
            continue
        if candidate.collider.has_meta("fdk_terrain_chunk") and offset.dot(direction) <= 0.00001:
            continue
        if distance < closest or is_equal_approx(distance, closest) and not candidate.collider.has_meta("fdk_terrain_chunk"):
            closest = distance
            result = candidate
    return result

func _terrain_ray_chunks(origin: Vector3, direction: Vector3, reach: float) -> Array:
    var end := origin + direction * reach
    var cs: float = terrain_config.cell_size
    var width: float = cs * terrain_config.chunk_size
    var local_start: Vector3 = terrain.to_local(origin)
    var local_end: Vector3 = terrain.to_local(end)
    var first := terrain.world_to_chunk_coord(local_start.min(local_end) - Vector3.ONE * cs)
    var last := terrain.world_to_chunk_coord(local_start.max(local_end) + Vector3.ONE * cs)
    var candidates: Array = []
    for z in range(first.z, last.z + 1):
        for y in range(first.y, last.y + 1):
            for x in range(first.x, last.x + 1):
                var nearby := terrain.get_chunk(Vector3i(x, y, z))
                if nearby != null:
                    var bounds: AABB = nearby.global_transform * AABB(Vector3.ONE * -cs, Vector3.ONE * (width + 2.0 * cs))
                    if bounds.intersects_segment(origin, end) != null:
                        candidates.append(nearby)
    return candidates

func _published_terrain_contact(origin: Vector3, direction: Vector3, reach: float) -> Dictionary:
    var nearest := reach + 0.00001
    var result := {}
    var candidates := _terrain_ray_chunks(origin, direction, reach)
    for chunk in candidates:
        if chunk._collision.shape == null:
            continue
        var transform: Transform3D = chunk.global_transform
        var faces: PackedVector3Array = chunk._collision.shape.get_faces()
        for i in range(0, faces.size(), 3):
            var a: Vector3 = transform * faces[i]
            var b: Vector3 = transform * faces[i + 1]
            var c: Vector3 = transform * faces[i + 2]
            var contact = Geometry3D.ray_intersects_triangle(origin, direction, a, b, c)
            if contact == null:
                continue
            if (contact - origin).dot(direction) <= 0.00001:
                continue
            var distance: float = origin.distance_to(contact)
            if distance > reach or distance >= nearest:
                continue
            nearest = distance
            var body: StaticBody3D = chunk.get_body()
            result = {"position": contact, "normal": -(b - a).cross(c - a).normalized(), "collider": body, "collider_id": body.get_instance_id(), "rid": body.get_rid(), "shape": 0, "face_index": i / 3}
    if result.is_empty():
        return result
    var obstruction := PhysicsRayQueryParameters3D.create(origin, result.position)
    obstruction.exclude = [player.get_rid()]
    obstruction.hit_from_inside = true
    var blocking := get_world_3d().direct_space_state.intersect_ray(obstruction)
    if not blocking.is_empty() and not blocking.collider.has_meta("fdk_terrain_chunk"):
        return blocking
    return result

func _terrain_target(hit: Dictionary, direction: Vector3) -> Vector3:
    # Follow the actual solid side on grazing, vertical and back-face hits.
    var outward: Vector3 = terrain._eye_surface_outward(hit)
    var into := -outward if outward.length_squared() > 0.5 else direction
    var sample: Vector3 = hit.position + into * terrain_config.cell_size * 0.5
    var cell: Vector3 = (sample / terrain_config.cell_size).floor()
    return (cell + Vector3.ONE * 0.5) * terrain_config.cell_size

func _pitch() -> float:
    return player.camera_pivot.rotation.x

func _looking_at(p: Vector3, deg: float, dist: float) -> bool:
    var ray: Array = player.get_look_ray()
    var to: Vector3 = p - ray[0]
    if to.length() > dist:
        return false
    return to.normalized().dot(ray[1]) > cos(deg_to_rad(deg))

func _interact() -> void:
    match interact_target():
        "tank_lid":
            if tank_lid.held: tank_lid.drop()
            else: tank_lid.pick()
        "mirror":
            restroom.mirror_art.call("toggle_cabinet")
            vent.notice("mirror")
        "canary": begin_canary_pull()
        "tank_teeth":
            if progression.teeth_in_hand > 0: put_teeth_back()
            else: scoop_teeth()
        "lever": pull_lever()
        "vent": use_vent()
        "sink": wash_hands()
        "toilet":
            if stomach.fill > 0.0 or progression.tumors.carried_count() > 0 or toilet.has_contents():
                start_settlement()
            else: sit_down()
        "door": restroom.set_door_open(not restroom.is_door_open())
        "tumor": pick_up_tumor()

func _pick() -> void:
    var target := interact_target()
    if target == "lever":
        pull_lever()
    elif target == "tank_teeth":
        if progression.teeth_in_hand > 0: put_teeth_back()
        else: scoop_teeth()
    elif target == "vent" and vent.is_open:
        if not vent.offers.is_empty(): take_vent_offer()
        else: reach_into_vent()

func mirror_point() -> Vector3:
    return restroom.mirror_art.to_global(Vector3(-0.6, 1.65, 0.24))

func sink_point() -> Vector3:
    return Vector3(-FPRestroom.HALF.x + 0.3, 0.95, FPRestroom.SINK_Z)

## 형님 2026-09-29: toilet interact ring should only show facing it, close (~1.2m).
func toilet_point() -> Vector3:
    return restroom.toilet.to_global(Vector3(0, 0.45, 0.3))

func canary_hole_point() -> Vector3:
    return FPRestroom.CANARY_HOLE + Vector3(0.03, 0.0, 0.0)

func _near_toilet() -> bool:
    return player.global_position.distance_to(restroom.toilet.to_global(Vector3(0, 0.9, 0.5))) < 1.3

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
        hand_motions.play_vomit(false, stomach.fill_ratio())
        settle_at_rest_point()
    else:
        hand_motions.play_vomit(false, stomach.fill_ratio())
        stomach.vomit()
        progression.discard_stomach()

func start_settlement() -> void:
    if _settling:
        return
    if stomach.fill > 0.0:
        hand_motions.play_vomit(true, stomach.fill_ratio())
    toilet.vomit_into(stomach.vomit())
    if toilet.throw_tumors(progression) > 0:
        progression.refresh_hands(carry_mode)
    _settling = true
    _settle_entry_frame = Engine.get_process_frames()
    FPInteractions.begin_settlement(self)
    player.velocity = Vector3.ZERO
    player.set_physics_process(false)
    settle_camera.current = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## 레버 물내림은 이빨을 탱크에 정산하고 환풍구 존재의 반응을 시작한다.
## 털은 실제 먹을 때 이미 자라므로 물내림에서는 다시 지급하지 않는다.
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
        leave_settlement()
    return got

func flush() -> Dictionary:
    return pull_lever()

## Where the flush lever sits on the tank, in world space.
func lever_point() -> Vector3:
    return restroom.toilet.to_global(Vector3(-0.16, 0.733, 0.185))

func end_settlement() -> void:
    flush()
    # 형님 2026-09-30: only "leave to title" and "quit" saved, so a crash or
    # a forced close between visits lost everything back to the last one.
    save_to_disk()

## Stand up from the bowl without the lever: the bowl keeps its contents.
func leave_settlement() -> void:
    if not _settling:
        return
    _settling = false
    _settle_entry_frame = -1
    if hand_motions.kind == "vomit_toilet":
        hand_motions._finish()
    stand_up()
    player.set_physics_process(true)
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
    player.set("_yaw", SEAT_YAW)
    player.rotation.y = SEAT_YAW
    player.set("_pitch", OPENING_SEAT_PITCH)
    player.camera_pivot.rotation.x = OPENING_SEAT_PITCH
    player.set_physics_process(false)
    vent.notice("sit") # 딴짓_앉기 in vent_rules.json (open vent, no teeth given)
    return true

func stand_up() -> bool:
    if not _seated:
        return false
    _seated = false
    player.global_position = Vector3(SEAT_POS.x + 0.28, START_POS.y, SEAT_POS.z)
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

# --- title screen, pause, settings ----------------------------------------------

## Tests and capture scripts load main.tscn with --script: no title there.
## A normal launch shows it; --skip-title (after --) goes straight in.
func title_wanted() -> bool:
    if "--skip-title" in OS.get_cmdline_user_args() or "--skip-title" in OS.get_cmdline_args():
        return false
    if "--script" in OS.get_cmdline_args() or "-s" in OS.get_cmdline_args():
        return false
    return get_tree().current_scene == self

func _setup_front_menus() -> void:
    settings = FPSettings.load_from()
    FPSettings.apply_audio(settings)
    FPSettings.apply_look(settings, player)
    keybind_menu.process_mode = Node.PROCESS_MODE_ALWAYS
    settings_menu = FPSettingsMenu.new()
    settings_menu.name = "SettingsMenu"
    add_child(settings_menu)
    settings_menu.setup(settings, player, keybind_menu)
    settings_menu.changed.connect(func(s): settings = s)
    settings_menu.closed.connect(_on_settings_closed)
    pause_menu = FPPauseMenu.new()
    pause_menu.name = "PauseMenu"
    add_child(pause_menu)
    pause_menu.settings_menu = settings_menu
    pause_menu.resumed.connect(_on_pause_resumed)
    pause_menu.settings_requested.connect(open_settings)
    pause_menu.title_requested.connect(go_to_title)
    pause_menu.quit_requested.connect(quit_game)
    title_screen = FPTitleScreen.new()
    title_screen.name = "TitleScreen"
    add_child(title_screen)
    title_screen.settings_menu = settings_menu
    title_screen.setup(self, has_save_file())
    title_screen.continue_requested.connect(continue_game)
    title_screen.new_game_requested.connect(new_game)
    title_screen.settings_requested.connect(open_settings)
    title_screen.quit_requested.connect(func(): get_tree().quit())
    # Saved window settings apply on every real boot, title or not.
    if FileAccess.file_exists(FPSettings.PATH) and not "--resolution" in OS.get_cmdline_args() \
            and get_tree().current_scene == self:
        FPSettings.apply_window(settings)
    if title_wanted():
        show_title()
    else:
        title_screen.close()
        _begin_opening()

func show_title() -> void:
    _reset_glare()
    mirror_view.sync(false, has_canary)
    mirror_view_right.sync(false, has_canary)
    title_screen.has_save = has_save_file()
    title_screen.open()
    hands_rig.visible = false
    get_tree().paused = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _leave_title() -> void:
    title_screen.close()
    hands_rig.visible = true
    get_tree().paused = false
    _esc_guard_frame = Engine.get_process_frames()
    if player.mouse_look_enabled:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Title "새로 시작": the save (if any) is dropped, the opening plays.
func new_game() -> void:
    _reset_glare()
    if has_save_file():
        DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
    _leave_title()
    _begin_opening()

## Title "이어하기".
func continue_game() -> bool:
    _leave_title()
    _begin_opening()
    if not load_from_disk():
        return false
    if ended:
        # A completed slot must not reload into an inert ending flag.
        # Keep the run's progress and resume in the restroom.
        ended = false
        player.global_position = START_POS
        player.velocity = Vector3.ZERO
    return true

## Any menu that holds the game (title, pause, settings, keys).
func is_menu_up() -> bool:
    return (title_screen != null and title_screen.is_open()) \
        or (pause_menu != null and pause_menu.is_open()) \
        or (settings_menu != null and settings_menu.is_open()) \
        or (keybind_menu != null and keybind_menu.is_open())

## What Esc does right now, highest first: the key screen, settings, pause;
## then the toilet view, the seat and the mirror close themselves; only
## plain play opens pause.
func esc_target() -> String:
    if keybind_menu != null and keybind_menu.is_open():
        return "keys"
    if settings_menu != null and settings_menu.is_open():
        return "settings"
    if pause_menu != null and pause_menu.is_open():
        return "resume"
    if (title_screen != null and title_screen.is_open()) or ended or is_opening():
        return ""
    if _settling:
        return "settle"
    if _seated:
        return "seat"
    if _mirror_open:
        return "mirror"
    if Engine.get_process_frames() - _esc_guard_frame <= 1:
        return ""
    return "pause"

## One Esc press. Returns what it did ("" = nothing).
func handle_esc() -> String:
    var t := esc_target()
    match t:
        "keys":
            keybind_menu.close()
        "settings":
            settings_menu.close()
        "resume":
            pause_menu.resume()
        "settle":
            leave_settlement()
        "seat":
            stand_up()
        "mirror":
            mirror.close()
        "pause":
            open_pause_menu()
    return t

func open_pause_menu() -> void:
    chewer.stop()
    pause_menu.open()
    get_tree().paused = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_pause_resumed() -> void:
    get_tree().paused = false
    _esc_guard_frame = Engine.get_process_frames()
    if player.mouse_look_enabled and not _settling and not _mirror_open and not _seated:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func open_settings() -> void:
    settings_menu.open()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_settings_closed() -> void:
    _esc_guard_frame = Engine.get_process_frames()
    if pause_menu.is_open():
        pause_menu.refocus()
    elif title_screen.is_open():
        title_screen.settings_button.grab_focus()

func has_save_file() -> bool:
    return FileAccess.file_exists(save_path)

func save_to_disk() -> bool:
    var temporary := save_path + ".tmp"
    var f := FileAccess.open(temporary, FileAccess.WRITE)
    if f == null:
        return false
    f.store_var(serialize())
    var error := f.get_error()
    f.close()
    if error != OK:
        return false
    return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(save_path)) == OK

func load_from_disk() -> bool:
    if not has_save_file():
        return false
    var f := FileAccess.open(save_path, FileAccess.READ)
    if f == null:
        return false
    var data = f.get_var()
    f.close()
    if not data is Dictionary:
        return false
    deserialize(data)
    # Restore the actual mesh and collision before input/rendering resumes.
    # This runs once per load; ordinary digging keeps its frame budget.
    terrain.remesh_all()
    return true

## Pause "저장하고 시작 화면으로": save, then a fresh scene with the title up.
func go_to_title() -> void:
    save_to_disk()
    get_tree().paused = false
    get_tree().reload_current_scene()

## The ending's credits (fp_ending.gd) finished but nothing was listening,
## so the game just sat there past the 8-second mark (형님 2026-09-30).
## Reuse the same "save, unpause, reload" path as leaving to the title.
func _on_ending_finished() -> void:
    save_to_disk()
    get_tree().paused = false
    get_tree().reload_current_scene()

## Pause "종료": the run is kept.
func quit_game() -> void:
    save_to_disk()
    get_tree().quit()
# --- Esc menu: key settings -------------------------------------------------------

func open_keybind_menu() -> void:
    keybind_menu.open()
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_keybind_menu_closed() -> void:
    _esc_guard_frame = Engine.get_process_frames()
    if is_menu_up():
        return
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
    if tank_lid == null or tank_lid.on_tank:
        return 0
    var n := progression.scoop_handful()
    if n > 0:
        vent.notice("grab")
        hand_motions.play_scoop()
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
    var n := progression.teeth_in_hand
    var ids := vent.place_teeth(n, progression)
    if not ids.is_empty():
        hand_motions.play_pour(n)
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
    var idx := vent.offers.find(id)
    if idx >= 0 and idx < vent.offer_nodes().size():
        var item: MeshInstance3D = null
        var slots = vent.art.get("_offers") if vent.art != null else null
        if slots is Array and idx < slots.size():
            item = (slots[idx] as Node3D).get_node_or_null("Item") as MeshInstance3D
        var at: Vector3 = item.global_position if item != null and item.is_inside_tree() else (vent.offer_nodes()[idx] as Node3D).global_position
        hand_motions.play_take(at, str(FPVent.ART_KIND.get(id, "junk")), item)
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
    var tank_d: float = p.distance_to(restroom.toilet.to_global(Vector3(0, 0.9, 0.5)))
    if tank_d < 0.9:
        vent.notice("tank_near")
    elif tank_d > 1.6:
        vent.notice("tank_far")
    var vent_d := p.distance_to(Vector3(vent.global_position.x, p.y, vent.global_position.z))
    if vent_d < FPVent.dist("UNDER_VENT", 1.0):
        vent.notice("near_vent")
    var sink_d := p.distance_to(sink_point())
    _vent_edge("sink", sink_d < FPVent.dist("SINK_NEAR", 0.9) and sink_d < tank_d, "near_sink")
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
    # the forearm hologram: arm up like reading a watch, doll on the forearm,
    # the rest dimmed; the view holds still and the player stands
    if art_hookup != null:
        art_hookup._sync_mutations(progression)
    _mirror_open = true
    var holo: Array[Node] = [hands_rig]
    if art_hookup != null and art_hookup.get("mut_hands") != null:
        holo.append(art_hookup.mut_hands)
    var active_rig: FDKHandsRig = hands_rig
    if art_hookup != null and art_hookup.mut_hands != null:
        var variant: FDKHandsRig = art_hookup.mut_hands.call("rig")
        if variant.is_visible_in_tree():
            active_rig = variant
    mirror.setup(player.camera, active_rig.call("get_hand_root", "left"), holo)
    mirror.open(progression)
    hand_motions.play_watch()
    player.set_physics_process(false)
    player.set_process_unhandled_input(false)
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## While the hologram is open nothing else runs (no look, no move); the same
## key, Esc or RMB close it (handled by FPMirror).
func _process_mirror_look() -> void:
    pass

func _on_mirror_closed() -> void:
    _mirror_open = false
    _mutate_guard_frame = Engine.get_process_frames()
    hand_motions.release_watch()
    player.set_physics_process(true)
    player.set_process_unhandled_input(true)
    var bits := FPMirrorReflection.HANDS_ROOM_LAYER if _hands_in_room else 1
    _tag_hands_layer(hands_rig, bits)
    if art_hookup != null and art_hookup.get("mut_hands") != null:
        _tag_hands_layer(art_hookup.mut_hands, bits)
    _esc_guard_frame = Engine.get_process_frames()
    if player.mouse_look_enabled:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func wash_hands() -> void:
    vent.notice("wash")
    hand_motions.play_wash(hand_blood)
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
    var low_eye_y: float = player.get_feet_position().y - player.global_position.y + 0.18
    player.camera_pivot.position.y = lerpf(_pull_eye_y, low_eye_y, down)
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
func _interaction_aim(point: Vector3, degrees: float, reach: float, target_name: String = "") -> bool:
    if target_name == "" and tank_lid != null:
        if point.is_equal_approx(restroom.tank_art.to_global(Vector3(0, 0.34, 0))):
            target_name = "tank_teeth"
        elif point.is_equal_approx(tank_lid.lid.global_position):
            target_name = "tank_lid"
    return _looking_at(point, degrees, reach) and FPInteractions.check_aim(self, point, target_name)

func interact_target() -> String:
    if tank_lid != null and tank_lid.held:
        return "tank_lid"
    if belt_swap != null and belt_swap.can_act():
        return "belt"
    var candidates: Array = FPInteractions.get_candidates(self)
    var best := ""
    var best_dot := -1.0
    var ray: Array = player.get_look_ray()
    for candidate in candidates:
        var point: Vector3 = candidate[1]
        if _interaction_aim(point, candidate[2], candidate[3], candidate[0]):
            var dot: float = (point - ray[0]).normalized().dot(ray[1])
            if dot > best_dot:
                best_dot = dot
                best = candidate[0]
    return best

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
    canary.block_density = 0.35 if canary_feed_left > 0.0 else 0.5
    _canary_t += delta
    if _canary_t < CANARY_TICK:
        return
    _canary_t = 0.0
    if restroom.contains(player.global_position):
        return
    canary.update(player.global_position, _safe_point(), CANARY_TICK)

# --- tools, carry, blender -------------------------------------------------------

func equip_tool(id: String) -> bool:
    if tank_lid != null and tank_lid.held:
        return false
    return progression.equip(id, carried_flesh > 0.0)

func equip_hand(id: String, hand: int) -> bool:
    if tank_lid != null and tank_lid.held:
        return false
    return progression.equip_hand(id, hand, carried_flesh > 0.0)

func cycle_tool(direction: int = 1) -> void:
    var order := ["", "knife", "blender", "big_saw", "spray_cheap", "spray_deep", "canary_feed", "barrier"]
    var i := order.find(progression.equipped())
    var current_hand := FDKToolKit.Hand.LEFT if progression.hands.left == progression.equipped() and progression.equipped() != "" else FDKToolKit.Hand.RIGHT
    for k in range(1, order.size() + 1):
        var id: String = order[posmod(i + k * direction, order.size())]
        var hand: int = current_hand if id == "" else progression.tools.hand_of(id)
        if equip_hand(id, hand):
            if k < order.size():
                hand_motions.play_cycle()
            return

## Carry mode: torn flesh piles up in the hand for the blender.
func toggle_carry() -> void:
    if not carry_mode and ((not progression.owns("blender") and not progression.can_lift_without_blender()) or not progression.right_hand_can_carry()):
        return
    carry_mode = not carry_mode
    if carry_mode and progression.hands.right != "":
        var held := progression.hands.right
        if held == "knife" and progression.hands.left == "":
            progression.hands.set_item(held, FDKToolKit.Hand.LEFT)
        else:
            progression.hands.set_item("", FDKToolKit.Hand.RIGHT)
            progression.tools.equipped = progression.hands.left
    if carry_mode and progression.owns("blender") and progression.hands.left == "":
        var active_tool := progression.tools.equipped
        progression.equip_hand("blender", FDKToolKit.Hand.LEFT, true)
        progression.tools.equipped = active_tool
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
    if vent.is_open and _interaction_aim(FPRestroom.VENT_CENTER, 12.0, 2.0, "vent"):
        vent.notice("spray") # sprayed at the vent being
    var hit := _look_hit()
    if hit.is_empty():
        return -1
    var used := progression.sprays.use(terrain, hit.position, tier, player.get_look_ray()[1])
    if used >= 0:
        spray_used.emit(hit.position)
    return used

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
    if t == null or not _interaction_aim(t.global_position, 10.0, 1.25, "tumor") or not progression.pick_up_tumor(String(t.get_meta("kind")), carried_flesh > 0.0):
        return false
    t.visible = false
    taken_tumor_spots.append(int(t.get_meta("spot")))
    return true

func eat_tumor() -> bool:
    if progression.eat_carried_tumor():
        progression.refresh_hands(carry_mode)
        return true
    var t := _nearest_tumor(1.2)
    if t == null or not _interaction_aim(t.global_position, 10.0, 1.25, "tumor"):
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

## Current capsule volume and reachable collision-respecting escape path.
func is_trapped() -> bool:
    var current: Dictionary = _body_clearance.assess(player, terrain)
    _body_relief_needed = bool(current.overlap) and not bool(current.trapped)
    return bool(current.trapped)

## Death: stomach contents and carried consumables drop here; only this
## spot is marked. The player wakes in the restroom. Never a wipe.
func die(cause: String) -> void:
    _reset_glare()
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
    canary.reset_trail()
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
    # 형님 2026-09-30: same autosave gap as end_settlement -- a death is a
    # real checkpoint (deaths count, tank/canary state reset) worth keeping
    # even if nothing is saved again before the next crash/close.
    save_to_disk()

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
    excavated_cells += 1
    _chew_target = Vector3.INF
    _chew_contact = Vector3.INF
    tissue_tools.on_cell_torn(world_pos)
    if carry_mode:
        carried_flesh += stomach_config.flesh_per_cell
        carried_units[shell] = int(carried_units.get(shell, 0)) + 1
    else:
        progression.on_flesh_eaten(shell, stomach_config.flesh_per_cell)
    _update_nerve_anchors()
    var near := _nearest_nerve(world_pos, 0.7)
    if near != null:
        _disturb_nerve(near, clampf(0.5 * _regen_scale(world_pos), 0.0, 1.0))
    var chance := 0.8 if shell < 2 else 0.55
    if excavated_cells >= 8 and FDKLowPoly.hash3(int(world_pos.x * 2.0), int(world_pos.y * 2.0), int(world_pos.z * 2.0)) > chance:
        var dir := Vector3(1, 0, 0) if FDKLowPoly.hash3(int(world_pos.z * 2.0), 1, 2) > 0.5 else Vector3(-1, 0, 0)
        var hit: Dictionary = terrain.solid_contact_ray(world_pos, world_pos + dir * 1.5)
        var published: Dictionary = _published_terrain_contact(world_pos, dir, 1.5)
        if not published.is_empty() and published.collider.has_meta("fdk_terrain_chunk"):
            if hit.is_empty() or world_pos.distance_to(published.position) < world_pos.distance_to(hit.position):
                hit = published
        if not hit.is_empty():
            # Current continuous density validates the root even when a
            # published collider is stale while excavation is pending.
            _spawn_nerve(hit.position, terrain._eye_surface_outward(hit))

# --- save/load ------------------------------------------------------------------------

func serialize() -> Dictionary:
    return {
        "version": SAVE_VERSION,
        "excavated_cells": excavated_cells,
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
        "tank_lid": tank_lid.serialize() if tank_lid != null else {},
        "taken_tumor_spots": taken_tumor_spots.duplicate(),
        "player_position": [player.global_position.x, player.global_position.y, player.global_position.z],
        "drawings": vent.drawings.duplicate(),
    }

func deserialize(data: Dictionary) -> void:
    _restore_frame_camera()
    _terrain_eye_delta = Vector3.ZERO
    _terrain_eye_pose = Vector3.ZERO
    _reset_glare()
    var v := int(data.get("version", 1))
    if data.has("terrain"):
        terrain.deserialize(data["terrain"])
        if v < 5:
            _migrate_restroom_terrain()
    excavated_cells = int(data.get("excavated_cells", 0))
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
    if tank_lid != null:
        tank_lid.deserialize(data.get("tank_lid", {}))
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
    if v < 5 and terrain.density_at(player.global_position) >= terrain_config.iso_level:
        player.global_position = START_POS
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

## Restore room space in older saves without filling any excavated cavities.
func _migrate_restroom_terrain() -> void:
    var cells := terrain_config.chunk_size
    var n := cells + 1
    var cs := terrain_config.cell_size
    for chunk in terrain._chunks.values():
        var touched := false
        for z in range(n):
            for y in range(n):
                for x in range(n):
                    var p: Vector3 = chunk.position + Vector3(x, y, z) * cs
                    if absf(p.x) <= 2.8 and p.y >= -0.55 and p.y <= 3.15 and p.z >= -FPRestroom.HALF.z - 0.55 and p.z < FPRestroom.HALF.z - 0.2:
                        var index: int = chunk._corner_index(x, y, z)
                        chunk._density[index] = minf(chunk._density[index], _world_density(p))
                        touched = true
        if touched:
            for z in range(cells):
                for y in range(cells):
                    for x in range(cells):
                        var p: Vector3 = chunk.position + (Vector3(x, y, z) + Vector3.ONE * 0.5) * cs
                        if absf(p.x) <= 2.8 and p.y >= -0.55 and p.y <= 3.15 and p.z >= -FPRestroom.HALF.z - 0.55 and p.z < FPRestroom.HALF.z - 0.2:
                            if chunk.get_density_at_corner(x, y, z) >= terrain_config.iso_level:
                                chunk.set_tissue_at_cell(x, y, z, _world_tissue(p))
            chunk._regen_scan = true
            chunk._dirty = true
    terrain.remesh_all()
