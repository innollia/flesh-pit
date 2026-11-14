extends Node3D
const FPProfile := preload("res://main/scripts/fp_profile.gd")
const FPGore := preload("res://main/scripts/fp_gore.gd")
const FPTearFeel := preload("res://main/scripts/fp_tear_feel.gd")
const FPWakeLids := preload("res://main/scripts/fp_wake_lids.gd")

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
## Opening: the flush heard on the black screen (audio: game/audio/HOOKUP.md).
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
## Bare fingers slipped off flesh they cannot grip (muscle, membrane): the
## rubbery creak that says a blade is needed.
signal grab_refused(tissue: int, world_pos: Vector3)
## V away from the toilet and rest points before the first lever settlement:
## the body retches but nothing comes up (decision 0009), unless the stomach
## is at its end (decision 0013: then it does come up).
signal dry_heaved
## The stomach is full and a bite at real, grippable flesh was refused: at
## most once every FULL_REFUSE_EVERY seconds while the eat input is held
## (FDKChewer.refused_full fires every frame). world_pos is the contact on the
## wall. Nothing was dug and nothing went down; the audio owns its own sound.
signal stomach_refused(world_pos: Vector3)
## The same refusal for carrying hands that hold all they can.
signal carry_refused(world_pos: Vector3)
## Teeth shut in the tank knocked its lid (the first-trade nudge, below
## _step_teeth_nudges); the audio plays a clink of teeth at the tank.
signal tank_teeth_knocked

## 6 (decision 0012): the flesh unit halved and hair prices doubled. Slots
## written before it are not converted and not read: load_from_disk refuses
## them and the title offers only a new game.
const SAVE_VERSION := 6

const RESTROOM_CENTER := Vector3(0, 1, 0)
## The signed density ramp places the flesh surface against the room walls.
const ROOM_MARGIN := 0.04
## Right in front of the door the margin is pulled down to under 5 cm.
const DOOR_GAP := 0.04
## The empty space above the ceiling vent, around its duct model (0.52 m
## wide, 0.7 m tall). One terrain cell (0.5 m) more on every side, so every
## cell that touches the duct has only empty corners and no flesh face can
## sit inside it, wherever the 0.5 m grid falls against the vent.
const VENT_DUCT_HALF := 0.26 + 0.5
const VENT_DUCT_TOP := 0.7 + 0.5
const MEMBRANE_THICKNESS := 0.9
const VOMIT_BUTTON_OVERFILL := 0.35
const WORLD_GEN_HALF := 10.0
const SHELL_THICKNESS := FPWorldFeatures.SHELL_THICKNESS
const OUTER_RADIUS := FPWorldFeatures.OUTER_RADIUS
## The toilet faces +Z, toward the door (FPRestroom.TOILET_YAW): standing up
## from the seat the door is straight ahead, and coming in through the door
## the bowl is.
const START_POS := Vector3(FPRestroom.TOILET_X, 0.95, FPRestroom.TOILET_Z + 0.64)
const START_YAW := PI - 0.02
const START_PITCH := -0.32
const SEAT_POS := Vector3(FPRestroom.TOILET_X, 0.55, FPRestroom.TOILET_Z + 0.30)
const SEAT_YAW := PI
## Where the body stands after rising from the seat.
const STAND_POS := Vector3(SEAT_POS.x, START_POS.y, SEAT_POS.z + 0.28)
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
## Bits and droplets out of tears and splashes (fp_gore.gd).
var gore: Node3D
## Snap, strands, wet rims and jolt of a tear (fp_tear_feel.gd).
var tear_feel: Node3D
## Eyes opening when waking in the restroom after a death (fp_wake_lids.gd).
var wake_lids: CanvasLayer
var vomit_button: FPVomitButton
var settle_camera: Camera3D
var environment: Environment
var player_lamp: OmniLight3D
var body_fill: OmniLight3D
const BODY_LAYER := 1 << 11 ## the first-person waist (belt, shirt, trousers)
const BODY_FILL := 0.35 ## body fill energy per unit of player lamp energy
## Eye lamp in the flesh (2026-10-19 play: stepping out of the door blew the
## view out to white). The lamp switched from 0 to full within ~0.3 s and lit
## walls half a metre away at full strength. The lamp now comes up as the
## eyes adapt and dims while a wall is right in front of the eye.
## Frames between a chunk's regrowth steps (FDKTerrainField.regen_stagger).
const REGEN_STAGGER := 6
const LAMP_ENERGY := 2.4
const LAMP_ADAPT_TIME := 2.5 ## s from leaving the room to full lamp
const LAMP_ADAPT_START := 0.3 ## share of full lamp the moment you step out
## A wall nearer than this gets the lamp scaled by (d / LAMP_FULL_AT) ^
## attenuation, which cancels the light's own near falloff: a wall at the
## eye reads as lit as one at LAMP_FULL_AT instead of blowing out.
const LAMP_FULL_AT := 1.2
const LAMP_NEAR_MIN := 0.12
const LAMP_TIGHT := 0.5 ## share of the lamp with the body fully squeezed
const LAMP_SIDE_NEAR := 0.4 ## m: a wall this close beside the eye counts like one LAMP_FULL_AT ahead
const LAMP_DOOR_ZONE := 1.8 ## m past the door plane the open, lit room still keeps the eyes light-adapted
var _eye_adapt := 0.0
var nerves: Array[FDKNerveStalk] = []

var progression: FPProgression = FPProgression.new()
var barrier_field: FDKBarrierField
var canary: FDKCanary
var hazard: FDKHazardCheck = FDKHazardCheck.new()
## The newest body left by a death (tests and M29 read it).
var death_drop: FDKDeathDrop
## Every body not yet recovered, oldest first. Each death leaves its own;
## nothing is overwritten (100 deaths without recovery = 100 bodies).
var death_drops: Array[FDKDeathDrop] = []
## Marker lamps that actually light (nearest bodies only).
const DROP_LIT_MARKERS := 8
var _drop_light_t := 0.0
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
var shadow_body: FPShadowBody ## the whole body as a shadow-only caster
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
## Several biomes per shell (main/data/biomes.json): their tissue, hollows,
## half-swallowed structures and mood. biome_life tracks where the player is.
var biomes: FPBiomes
var biome_life: FPBiomeLife
var structure_nodes: Array[Node3D] = []
## The spray can on each rest point's chair (rest_points order) and the
## indexes already taken this game (decision 0006).
var rest_cans: Array[Node3D] = []
var looted_rest_cans: Array = []
## True once a lever flush has settled teeth or a tumour. Until then V away
## from the toilet and rest points is only a dry heave, so the first
## expedition's full stomach has to come back to the toilet (decision 0009,
## playtests s1 and s4 emptied it outside and never settled).
var lever_settled: bool = false

var carried_flesh: float = 0.0
## Flesh in the hands per shell, in flesh units (not cells).
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
## A bite refused because nothing more fits (stomach, or carrying hands): the
## wall is gripped and let go and the refusal is told at most this often.
const FULL_REFUSE_EVERY := 0.9
const FULL_PRESS_TIME := 0.3
const FULL_PRESS := 0.35
var _full_cool := 0.0
var _full_frame := -100
var _full_press_t := 0.0
## True near the toilet or a rest point's bucket, where vomiting settles: the
## only places a vomit key shows (decision 0009).
var at_settle_spot := false
## Flesh under the aim but beyond the arm (the one-cell tunnel the body cannot
## follow, findings s4): the world point this frame (INF = none) and how long
## the eat input has been held on it (decays when it is not).
const REACH_SHORT_EXTRA := 1.0
const DIG_HINT_AFTER := 1.0
const DIG_HINT_LINGER := 2.5
const DIG_HINT_PITCH := 15.0
var reach_short_at: Vector3 = Vector3.INF
var reach_short_t := 0.0
var _reach_short_frame := -100
var _dig_hint_left := 0.0
var _dig_up_learned := false
var _dig_down_learned := false
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
## Holding the interact / right-hand input at the tank or the vent keeps
## moving teeth one at a time: the op the press started, the input holding
## it, and the time to the next tooth.
const TOOTH_REPEAT_DELAY := 0.35
const TOOTH_REPEAT_EVERY := 0.07
var _tooth_op := ""
var _tooth_action := ""
var _tooth_rep_t := 0.0
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
	# the held discard must be decided before the bow's first lump comes up
	assert(DISCARD_HOLD < 0.36 * float(FPHandMotions.DUR["vomit_floor"]))
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
	biomes = FPBiomes.new(RESTROOM_CENTER)
	biomes.apply_rest_points(rest_points)
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
	# growth is a few thousandths a second: each chunk grows on one frame in
	# six by the time it waited (its cost no longer scales with all dug flesh)
	terrain.regen_stagger = REGEN_STAGGER
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
	player.config.climb_up_speed = 4.5
	player.name = "Player"
	player.movement_filter = _filter_terrain_motion
	player.shape_fits = func(): return _body_clearance.fits(player, terrain)
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
	chewer.refused_full.connect(_on_chew_refused_full)

	stomach_view = FPStomachView.new()
	stomach_view.name = "StomachView"
	player.camera.add_child(stomach_view)
	stomach.fill_changed.connect(func(_f, _c, _o): stomach_view.set_state(stomach.fill_ratio(), stomach.overfill_ratio()))
	gore = FPGore.new()
	gore.exclude.append(player.get_rid())
	gore.name = "Gore"
	add_child(gore)
	tear_feel = FPTearFeel.new()
	tear_feel.name = "TearFeel"
	tear_feel.terrain = terrain
	tear_feel.gore = gore
	tear_feel.grip_node = func(): return hands_rig.torn_chunk() if hands_rig != null else null
	add_child(tear_feel)
	wake_lids = FPWakeLids.new()
	wake_lids.name = "WakeLids"
	add_child(wake_lids)

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

	death_drop = _new_death_drop()
	death_drop.visible = false

	vent = FPVent.new()
	vent.name = "Vent"
	vent.position = FPRestroom.VENT_CENTER - Vector3(0, 0.03, 0)
	add_child(vent)
	vent.drawing_dropped.connect(_on_drawing_dropped)
	toilet = FPToiletSettlement.new()
	toilet.name = "ToiletSettlement"
	add_child(toilet)

	for i in range(rest_points.size()):
		var loot: String = FPWorldFeatures.REST_SPRAY_LOOT[FPWorldFeatures.rest_shell(i)]
		var rest := FPWorldFeatures.build_container(self, rest_points[i], loot)
		var can := rest.get_node("LootCan") as Node3D
		can.set_meta("rest", i)
		rest_cans.append(can)
	var spots := FPWorldFeatures.tumor_spots(RESTROOM_CENTER)
	for i in range(spots.size()):
		var t := FPWorldFeatures.build_tumor(self, spots[i])
		t.set_meta("spot", i)
		tumor_nodes.append(t)
	structure_nodes = biomes.build_structures(self)
	biome_life = FPBiomeLife.new()
	biome_life.name = "BiomeLife"
	add_child(biome_life)
	biome_life.setup(self, biomes)

	art_hookup = FPArtHookup.new()
	art_hookup.name = "ArtHookup"
	add_child(art_hookup)
	art_hookup.setup(self)
	belt_swap = FPBeltSwap.new(self)
	hand_actions = FPHandActions.new(self)
	hand_motions = FPHandMotions.new(self)
	# From the start, not only after the first situational motion: the
	# blender plug and the M22 alien hand shape the left hand through it.
	hands_rig.pose_hook = hand_motions
	# Capture the neutral animation base before a terrain correction can
	# be mistaken for a permanent offset by the first hand motion.
	hand_motions._save_cams()
	get_tree().process_frame.connect(_restore_frame_camera)
	RenderingServer.frame_pre_draw.connect(_guard_terrain_eye)
	mutation_apply = FPMutationApply.new()
	mutation_apply.name = "MutationApply"
	add_child(mutation_apply)
	mutation_apply.setup(self)
	# timed reward-event log for the reward scale, only when FP_PLAY_LOG is set
	if FPPlayLog.wanted() != "":
		var play_log := FPPlayLog.new()
		play_log.name = "PlayLog"
		add_child(play_log)
		play_log.setup(self, FPPlayLog.wanted())

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
	var voice: Node = audio_hookup.get_node("Voice")
	voice.connect("voice_started", subtitles.follow_voice)
	voice.connect("voice_cut", subtitles.voice_cut)
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
## Where this player's keys are read and written. Tests point it at their own
## file before ready (like save_path) so they never touch the player's keys.
var user_keybinds_path: String = USER_KEYBINDS_PATH

func _register_keybinds() -> void:
	var binds: Dictionary = {}
	for path in [KEYBINDS_PATH, user_keybinds_path]:
		if FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary:
				for k in d.get("키", {}):
					if path == user_keybinds_path and not binds.has(k):
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
	if FileAccess.file_exists(user_keybinds_path):
		var old = JSON.parse_string(FileAccess.get_file_as_string(user_keybinds_path))
		if old is Dictionary:
			d = old
	var pad := -1
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			pad = e.button_index
	d["키"][action] = {"키보드": key_name, "패드": pad}
	var f := FileAccess.open(user_keybinds_path, FileAccess.WRITE)
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
	var density: float
	if in_vent_duct(p):
		density = 0.0
	else:
		density = FPWorldFeatures.world_density(p, FPRestroom.HALF, FPRestroom.DOOR_HALF_W, FPRestroom.DOOR_H,
			ROOM_MARGIN, DOOR_GAP, RESTROOM_CENTER, OUTER_RADIUS, rest_points)
		if biomes != null:
			density = biomes.shape_density(p, density)
	if _world_density_cache.size() >= WORLD_DENSITY_CACHE_LIMIT:
		_world_density_cache.clear()
	_world_density_cache[p] = density
	return density

static func in_vent_duct(p: Vector3) -> bool:
	var o := p - FPRestroom.VENT_CENTER
	return absf(o.x) < VENT_DUCT_HALF and absf(o.z) < VENT_DUCT_HALF and o.y >= -0.04 and o.y < VENT_DUCT_TOP

func _room_surface_constraint(p: Vector3) -> Vector3:
	var vent_offset := p - FPRestroom.VENT_CENTER
	if absf(vent_offset.x) < VENT_DUCT_HALF + 0.08 and absf(vent_offset.z) < VENT_DUCT_HALF + 0.08 and vent_offset.y > -0.04:
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
	var noise := _noise.get_noise_3dv(p)
	var t := FPWorldFeatures.world_tissue_at(p, RESTROOM_CENTER, noise, room)
	return biomes.tissue_at(p, t, noise) if biomes != null else t

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

## Where the lever is on screen while the first vomit waits in the bowl and
## nothing was ever flushed (INF otherwise). Over the bowl the cursor is free
## and the right button there flushes; standing, the eye must find it.
func _first_lever_spot() -> Vector2:
	if lever_settled or vent._first_flush_heard or not toilet.has_contents() or not restroom.contains(player.global_position):
		return Vector2.INF
	var rect := get_viewport().get_visible_rect()
	var cam: Camera3D = settle_camera if _settling else player.camera
	var p := lever_point()
	var inner := rect.grow(-40.0) if rect.size.x > 100.0 and rect.size.y > 100.0 else rect
	if not cam.is_position_behind(p) and inner.has_point(cam.unproject_position(p)):
		return cam.unproject_position(p)
	if not _settling:
		return Vector2.INF
	# over the bowl the lever is out of view (R reaches back for it): the
	# hint sits on the screen edge toward it
	var local := cam.global_basis.inverse() * (p - cam.global_position)
	var dir := Vector2(local.x, -local.y)
	if dir.length() < 0.001:
		dir = Vector2.UP
	dir = dir.normalized()
	var c := rect.get_center()
	var half := (rect.size * 0.5 - Vector2(70.0, 60.0)).max(Vector2.ONE)
	var k := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	return c + dir * k

## The door stands open on the flesh and no cell has ever been torn: the
## eat button shows (2026-10-31 play: the open door gave no cue to dig).
func _first_eat_waiting() -> bool:
	if excavated_cells > 0 or lever_settled or _settling or _seated or restroom.door_open_amount() < 0.5:
		return false
	var door_center := restroom.global_position + Vector3(0.0, 1.0, FPRestroom.HALF.z)
	return player.global_position.distance_to(door_center) < 3.0

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
	environment.tonemap_exposure = glare_controller.get_tonemap_exposure()
	var k := 1.0 if immediate else 1.0 - exp(-delta * 3.0)
	var depth_tone := clampf(terrain.depth_at(player.global_position) / terrain_config.depth_tone_distance, 0.0, 1.0)
	environment.fog_density = lerpf(environment.fog_density, 0.01 if inside else lerpf(0.1, 0.2, depth_tone), k)
	var out_light := Color(0.55, 0.22, 0.24)
	var out_energy := 0.42
	# a biome's own light mixes in (FPBiomeLife, main/data/biomes.json)
	var mood: float = biome_life.weight if biome_life != null else 0.0
	if mood > 0.0:
		out_light = out_light.lerp(biome_life.ambient * 0.5, 0.7 * mood)
		out_energy *= lerpf(1.0, biome_life.energy, mood)
	environment.ambient_light_color = environment.ambient_light_color.lerp(Color(0.85, 0.87, 0.9) if inside else out_light, k)
	environment.ambient_light_energy = lerpf(environment.ambient_light_energy, 0.12 if inside else out_energy, k)
	var from_door := player.global_position.z - (restroom.global_position.z + FPRestroom.HALF.z)
	# the eyes do not get used to the dark while the open, lit room is
	# right behind them: the lamp waits until the body is past the doorway
	var door_lit: bool = restroom.door_open_amount() > 0.05 and from_door < LAMP_DOOR_ZONE
	if inside:
		_eye_adapt = 0.0
	elif door_lit and not immediate:
		_eye_adapt = maxf(0.0, _eye_adapt - delta / LAMP_ADAPT_TIME)
	else:
		_eye_adapt = minf(1.0, _eye_adapt + (1.0 if immediate else delta / LAMP_ADAPT_TIME))
	player_lamp.light_energy = lerpf(player_lamp.light_energy, 0.0 if inside else lamp_target(), k)
	body_fill.light_energy = player_lamp.light_energy * BODY_FILL
	if not inside:
		environment.fog_light_color = Color(0.22, 0.03, 0.05).lerp(Color(0.1, 0.01, 0.07), depth_tone)
		if mood > 0.0:
			environment.fog_light_color = environment.fog_light_color.lerp(biome_life.fog * 1.6, 0.7 * mood)

## Eye lamp energy outside the room: eye adaptation times the near-wall dim.
func lamp_target() -> float:
	var adapt := lerpf(LAMP_ADAPT_START, 1.0, smoothstep(0.0, 1.0, _eye_adapt))
	var near := clampf(pow(_wall_ahead() / LAMP_FULL_AT, player_lamp.omni_attenuation), LAMP_NEAR_MIN, 1.0)
	# a squeezed body is in a tight gap: everything the lamp lights is close
	var tight := lerpf(1.0, LAMP_TIGHT, float(player.squeeze())) if player.has_method("squeeze") else 1.0
	return LAMP_ENERGY * adapt * near * tight

## Distance from the eye to the nearest real surface ahead or right beside it.
func _wall_ahead() -> float:
	if not is_inside_tree() or player == null:
		return LAMP_FULL_AT
	var ray: Array = player.get_look_ray()
	var origin: Vector3 = ray[0]
	var fwd: Vector3 = ray[1]
	var basis: Basis = player.camera.global_basis
	var space := get_world_3d().direct_space_state
	var best := LAMP_FULL_AT
	# a cone ahead (counted as it is) plus the sides, top and bottom, which
	# count only when pressed close (squeezed into a tight gap the walls right
	# beside the eye blew out; an ordinary tunnel's walls must not dim it)
	var rays: Array = []
	for off in [Vector2.ZERO, Vector2(0.35, 0.0), Vector2(-0.35, 0.0), Vector2(0.0, -0.3)]:
		rays.append([(fwd + basis.x * off.x + basis.y * off.y).normalized(), LAMP_FULL_AT])
	for side in [basis.x, -basis.x, basis.y, -basis.y]:
		rays.append([(side + fwd * 0.3).normalized(), LAMP_SIDE_NEAR])
	for r in rays:
		var reach: float = r[1]
		var q := PhysicsRayQueryParameters3D.create(origin, origin + (r[0] as Vector3) * reach)
		q.exclude = [player.get_rid()]
		# an eye pressed right against the flesh starts at its surface
		q.hit_from_inside = true
		q.hit_back_faces = true
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			best = minf(best, origin.distance_to(hit.position) * LAMP_FULL_AT / reach)
	return best

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
	# the player's shadow: a whole shadow-only body wearing the belt
	shadow_body = FPShadowBody.new()
	shadow_body.name = "ShadowBodyCaster"
	add_child(shadow_body)
	shadow_body.setup(self)
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
	# the standing body (waist, legs) and its own hands stay where the player
	# stood; seen from the bowl they read as a second person beside it
	settle_camera.cull_mask &= ~FPMirrorReflection.MIRROR_BODY_LAYER & ~BODY_LAYER & ~FPMirrorReflection.HANDS_ROOM_LAYER
	add_child(settle_camera)
	var bowl := restroom.bowl_center
	settle_camera.global_position = bowl + Vector3(-0.06, 0.34, 0.2)
	settle_camera.look_at(bowl + Vector3(0, 0, -0.04), Vector3.UP)

# --- opening ----------------------------------------------------------------------

## Session A (restroom look): opening cover, vent subtitles, blood on hands.
const OPENING_SEAT_PITCH := -0.28
var opening_view: FPOpening
var subtitles: FPSubtitles
## Name and count tags over the items the vent holds out.
var offer_labels: FPOfferLabels
var hand_blood_mat: ShaderMaterial

func _setup_restroom_front() -> void:
	opening_view = FPOpening.new()
	opening_view.name = "OpeningView"
	add_child(opening_view)
	subtitles = FPSubtitles.new()
	subtitles.name = "Subtitles"
	add_child(subtitles)
	vent.line_spoken.connect(func(id: String): subtitles.show_line(id))
	offer_labels = FPOfferLabels.new()
	offer_labels.name = "OfferLabels"
	offer_labels.vent = vent
	add_child(offer_labels)
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
	player.global_position = SEAT_POS.lerp(STAND_POS, k)
	var pitch := lerpf(OPENING_SEAT_PITCH, 0.0, k)
	# the view is held while seated and rising; mouse input in the meantime
	# is dropped instead of snapping the view when the opening ends (s4)
	player.set("_yaw", SEAT_YAW)
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
	FPProfile.begin("main_pre")
	_restore_frame_camera()
	FPProfile.begin("atmosphere")
	_update_atmosphere(delta)
	FPProfile.end("atmosphere")
	_update_restroom_front()
	_update_hands_room_layer()
	player.climb_enabled = can_climb_at(player.global_position)
	# the restroom's fixtures are not flesh to squeeze past (2026-10-31 play:
	# walking up to the tank twisted the body and swayed the head)
	player.squeeze_enabled = not restroom.contains(player.global_position)
	stomach_view.set_state(stomach.fill_ratio(), stomach.overfill_ratio())
	# the vomit key and mouth show only where vomiting settles (decision 0009):
	# shown everywhere they taught emptying the stomach out in the flesh
	var settle_spot := _near_toilet() or _near_rest_point() >= 0
	at_settle_spot = settle_spot
	vomit_button.shown = not _settling and settle_spot and stomach.overfill_ratio() >= VOMIT_BUTTON_OVERFILL
	# before the first settlement any mouthful is worth bringing back: the key
	# shows at the bowl however full (2026-10-31 play: back half full, no cue)
	opening_view.hints.vomit_hint = not _settling and settle_spot and (stomach.fill_ratio() >= 1.0 or (not lever_settled and stomach.fill > 0.0))
	opening_view.hints.eat_hint = _first_eat_waiting()
	opening_view.hints.lever_at = _first_lever_spot()
	opening_view.hints.mirror_at = _first_mirror_spot()
	hands_rig.set_mutation(progression.mutation_amount())
	hands_rig.set_carry(clampf(carried_flesh / 40.0, 0.0, 1.0) if carried_flesh > 0.0 else 0.0)
	# an overfull stomach makes the same bite heavier: the pull trembles bigger
	# and slower, the tear's jolt lands longer (never the chew time itself)
	var overfull: float = stomach.overfill_ratio()
	tear_feel.heavy = overfull
	for rig in FPHandMotions.rigs_of(self):
		rig.set_strain(overfull)
	_full_press_t = maxf(0.0, _full_press_t - delta)
	_dig_hint_left = maxf(0.0, _dig_hint_left - delta)
	if Engine.get_process_frames() - _reach_short_frame > 1:
		reach_short_at = Vector3.INF
		reach_short_t = maxf(0.0, reach_short_t - delta * 0.5)
	vent.tick(delta)
	vent.watch_bowl(delta, toilet.has_contents() and restroom.contains(player.global_position))
	hand_motions.check_cancel()
	# after check_cancel (a second press of V cancels the bow first, so held
	# time never joins up across presses) and before the motion's own tick (so
	# the flesh is gone before the first lump shows)
	discard_hold_step(delta, Input.is_action_pressed("fp_vomit"))
	_watch_leans(delta)
	hand_motions.tick(delta)
	tear_feel.tick(delta)
	FPProfile.begin("eye_guard")
	_guard_terrain_eye(false, false)
	FPProfile.end("eye_guard")
	_vent_watch(delta)
	_update_tank_teeth()
	_step_teeth_nudges(delta)
	FPProfile.end("main_pre")
	if ended:
		ending.tick(delta)
		return
	_step_ending_bite(delta)
	if ended:
		return
	_process_opening(delta)
	if is_opening():
		return
	if is_pulling_canary():
		step_world(delta)
		_guard_terrain_eye(false)
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
		# the hands hold the forearm up to read it: no grab goes on (the
		# chew loop used to keep sounding while the mirror stayed open)
		chewer.stop()
		_process_mirror_look()
		return
	if Input.is_action_just_pressed("ui_cancel") and handle_esc() != "":
		return
	if mutation_apply != null and mutation_apply.is_dormant():
		# M29: the body sleeps curled up and wakes on its own (05-mutations.md);
		# the world goes on, no action of the player's does anything until then
		chewer.stop()
		step_world(delta)
		_guard_terrain_eye(false)
		tick_autosave(delta)
		return
	if InputMap.has_action("fp_mutate") and Input.is_action_just_pressed("fp_mutate") and Engine.get_process_frames() != _mutate_guard_frame:
		open_mirror()
		return
	FPProfile.begin("actions")
	_handle_actions()
	hand_actions.tick(delta)
	_repeat_tooth_op(delta)
	FPProfile.end("actions")
	step_world(delta)
	FPProfile.begin("eye_guard")
	_guard_terrain_eye(false)
	FPProfile.end("eye_guard")
	tick_autosave(delta)

# Start of a new frame, before hand/mutation camera writers. Do not use this
# combined restore inside _guard_terrain_eye: that would remove the effect.
func _restore_frame_camera() -> void:
	if danger_show != null:
		danger_show.restore_camera()
	_restore_terrain_eye()

func _filter_terrain_motion(motion: Vector3) -> Vector3:
	return _body_clearance.constrain_motion(player, terrain, motion)

func _physics_process(delta: float) -> void:
	FPProfile.begin("main_physics")
	_physics_process_inner(delta)
	FPProfile.end("main_physics")

func _physics_process_inner(delta: float) -> void:
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
		FPProfile.begin("nerve_anchors")
		_update_nerve_anchors()
		FPProfile.end("nerve_anchors")
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
		# the lid fills the right hand: F (or that hand, FPHandActions) puts it down
		if Input.is_action_just_pressed("fp_interact"):
			FPInteractions.press(self, FPInteractions.SOURCE_INTERACT)
		return
	if Input.is_action_just_pressed("fp_carry"):
		toggle_carry()
	if Input.is_action_just_pressed("fp_vomit"):
		request_vomit()
	if Input.is_action_just_pressed("fp_interact"):
		FPInteractions.press(self, FPInteractions.SOURCE_INTERACT)
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
	if carry_mode and carried_flesh >= progression.carry_capacity():
		# the hands are full: they push on the flesh, nothing more comes away
		chewer.stop()
		var full_hit := _look_hit()
		if not full_hit.is_empty() and full_hit.collider.has_meta("fdk_terrain_chunk"):
			_refuse_full(full_hit.position, player.get_look_ray()[1], false)
		else:
			terrain.set_press(Vector3.ZERO, Vector3.BACK, 0.0)
		return
	if saw_stroke_refused():
		# a saw stroke goes straight down even while carrying (_on_cell_torn),
		# and the chewer does not watch the stomach then: a full one refuses
		# here, before anything is torn
		chewer.stop()
		var saw_hit := _look_hit()
		if not saw_hit.is_empty() and saw_hit.collider.has_meta("fdk_terrain_chunk"):
			_refuse_full(saw_hit.position, player.get_look_ray()[1], true)
		else:
			terrain.set_press(Vector3.ZERO, Vector3.BACK, 0.0)
		return
	if hands_rig.state == FDKHandsRig.HandState.TEAR:
		terrain.set_press(Vector3.ZERO, Vector3.BACK, 0.0)
		return
	var dir: Vector3 = player.get_look_ray()[1]
	var hit := _look_hit()
	# nothing on the centre line: a body stuck at a tunnel it has outdug may
	# take the nearest flesh under the line that is in its own way
	if hit.is_empty() and _chew_assist_step(dir, delta):
		return
	if hit.is_empty() or not hit.collider.has_meta("fdk_terrain_chunk"):
		chewer.stop()
		terrain.set_press(Vector3.ZERO, Vector3.BACK, 0.0)
		_chew_target = Vector3.INF
		_chew_contact = Vector3.INF
		set_hand_reach(Vector3.INF)
		if hit.is_empty():
			_show_reach_short(delta)
		return
	# The hands reach the flesh actually held, wherever it sits on screen
	# (looking down they used to clench at a fixed spot, or swung aside).
	set_hand_reach(hit.position)
	# A locked grab must still have real unoccluded contact. Nearby collider
	# motion is allowed without restarting progress on the same cell.
	if chewer.is_chewing() and _chew_target != Vector3.INF and _chew_contact != Vector3.INF and _looking_at(_chew_contact, 12.0, progression.reach()) and terrain.density_at(_chew_target) >= terrain_config.iso_level and _chew_target.distance_to(hit.position) <= terrain_config.cell_size * 1.5:
		if tissue_tools.chew_at(_chew_target, hit.position, dir, delta):
			_show_pull(hit.position, dir, _chew_ratio)
		return
	var target := _terrain_target(hit, dir)
	_chew_target = target
	_chew_contact = hit.position
	# hardness per tissue, membrane only with a blade (fp_tissue_tools.gd)
	if tissue_tools.chew_at(target, hit.position, dir, delta):
		_show_pull(hit.position, dir, _chew_ratio if chewer.is_chewing() else 0.0)
	else:
		_chew_target = Vector3.INF
		_chew_contact = Vector3.INF

# --- chew assist: the body stuck behind its own level tunnel (decision 0015) ---
#
# Holding eat and forward on a fixed aim digs a tunnel along the aim line. Its
# floor stands higher than the floor the body is on (a dug cell opens the
# cells round it up to their middles), so there is a lip in front of the
# body. Out in the flesh the body crawls up it by itself; where it does not
# (the restroom, a lip too high) the face leaves the arm's reach and the bite
# used to stop without a word. When that is what happened (the start
# conditions in _assist_may_start), the hands take the nearest flesh UNDER the
# aim line that lies in front of the body. It is an ordinary bite on an
# ordinary contact: same reach, same occlusion, same tissue rules, the same
# chewer and stomach (eaten flesh = removed density). Nothing above the line,
# past the face or under the feet is ever taken, and nothing outside the view
# (so the lip right at the feet stays: docs/tracking/findings.md).

## A cell under the aim line was torn by the assist (its centre).
signal chew_assisted(cell_center: Vector3)
## Seconds the body must have been walking into the blocked way.
const CHEW_ASSIST_STUCK := 0.4
## Steeper aims are the climb's and the crouch's (dig_key_hint).
const CHEW_ASSIST_MAX_PITCH := 60.0
## A cell is taken only inside this cone round the aim (and inside the view).
const CHEW_ASSIST_CONE_MAX := 35.0
## The stuck body's aim and the way it pushes agree at least this much.
const CHEW_ASSIST_ALIGN := 0.87
const CHEW_ASSIST_SCAN := 0.1
const CHEW_ASSIST_CELLS := 12
## Off for the control run of the stall test.
var chew_assist_enabled := true
var assist_tears := 0
var _assist_cell := Vector3.INF
var _assist_aim := Vector3.INF ## the point on that cell's face the hand's ray goes to
var _assist_hit := {}
var _assist_frame := -100
var _assist_scan_t := 0.0

## The contact the hands are working: the centre line's, or the assist's while
## it holds a cell (then with "fp_assist_cell", that cell's centre). Empty when
## neither.
func chew_hit() -> Dictionary:
	var hit := _look_hit()
	if hit.is_empty() and _assist_cell != Vector3.INF and Engine.get_process_frames() - _assist_frame <= 1:
		return _assist_hit
	return hit

func _assist_drop() -> void:
	_assist_cell = Vector3.INF
	_assist_aim = Vector3.INF
	_assist_hit = {}

## One frame of the eat input with nothing on the centre line. True while the
## assist holds a cell (the caller then leaves the grab alone).
func _chew_assist_step(dir: Vector3, delta: float) -> bool:
	var frame := Engine.get_process_frames()
	if not chew_assist_enabled or frame - _assist_frame > 1:
		_assist_drop() # the input lapsed, or the centre line had it meanwhile
	if not chew_assist_enabled:
		return false
	var eye: Vector3 = player.get_look_ray()[0]
	var hit := {}
	if _assist_cell != Vector3.INF:
		# the same cell stays held while its own contact holds (no restart)
		hit = _assist_contact(eye, dir, _assist_cell, _assist_aim)
		if hit.is_empty():
			_assist_drop()
	if _assist_cell == Vector3.INF:
		_assist_scan_t -= delta
		if _assist_scan_t > 0.0 or not _assist_may_start(dir):
			return false
		_assist_scan_t = CHEW_ASSIST_SCAN
		var found := _assist_find(eye, dir)
		if found.is_empty():
			return false
		_assist_cell = found.cell
		_assist_aim = found.aim
		hit = found.hit
	_assist_frame = frame
	hit["fp_assist_cell"] = _assist_cell
	_assist_hit = hit
	var toward: Vector3 = (_assist_aim - eye).normalized()
	_chew_target = _assist_cell
	_chew_contact = hit.position
	set_hand_reach(hit.position)
	if tissue_tools.chew_at(_assist_cell, hit.position, toward, delta):
		_show_pull(hit.position, toward, _chew_ratio)
	else:
		# refused like any bite (a blade's tissue, a full stomach); the cell
		# stays the assist's so the refusal repeats at the same contact
		_chew_target = Vector3.INF
		_chew_contact = Vector3.INF
	return true

## The assist may start: flesh just past the arm on the aim line, the body
## walking that way and blocked, the aim not steep.
func _assist_may_start(dir: Vector3) -> bool:
	if absf(rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))) > CHEW_ASSIST_MAX_PITCH:
		return false
	if not ("stuck_time" in player) or float(player.stuck_time) < CHEW_ASSIST_STUCK:
		return false
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.001 or (player.stuck_dir as Vector3).dot(flat.normalized()) < CHEW_ASSIST_ALIGN:
		return false
	return _reach_short_point() != Vector3.INF

## How far under the aim line (metres) a cell's middle may lie and still be
## in the body's way: down to just over the feet. A dug cell leaves the
## surface of the cell under it at about that cell's middle, so a cell whose
## middle stands over the feet is a lip in front of the body, and one whose
## middle is under them is the floor. The body that could crawl up the lip by
## itself has done so before it counts as stuck (FDKFirstPersonController
## .stuck_time); what is left is a body held to the floor (crouch + eat), one
## that may not crawl (the restroom), or a lip too high.
const CHEW_ASSIST_FEET_CLEAR := 0.1
func _assist_body_depth() -> float:
	return player.get_look_ray()[0].y - player.get_feet_position().y - CHEW_ASSIST_FEET_CLEAR

## The nearest cell under the aim line, in the body's way, that the eye sees
## and the arm reaches: {cell, aim, hit}, or empty. The cells are the slab
## under the line (the aim's own column, middles from half a cell under it
## down to _assist_body_depth, no farther than the face); the hand's ray is tried at each
## one nearest first, and the contact it really makes decides the cell by the
## centre line's own rule (_terrain_target). A contact that belongs to a cell
## outside the slab is not taken.
func _assist_find(eye: Vector3, d: Vector3) -> Dictionary:
	var face := _reach_short_point()
	if face == Vector3.INF:
		return {}
	var down := Vector3.DOWN - d * Vector3.DOWN.dot(d)
	if down.length() < 0.001:
		return {}
	var n := down.normalized()
	var side := d.cross(n).normalized()
	var cs: float = terrain_config.cell_size
	var iso: float = terrain_config.iso_level
	var far: float = (face - eye).dot(d)
	var deep: float = _assist_body_depth()
	var wide: float = cs * 0.5 + 0.01
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for a: float in [0.0, far]:
		for b: float in [cs * 0.5, deep]:
			for c: float in [-wide, wide]:
				var corner := eye + d * a + n * b + side * c
				lo = lo.min(corner)
				hi = hi.max(corner)
	var first := (lo / cs).floor()
	var last := (hi / cs).floor()
	var found: Array = []
	var slab := {}
	for z in range(int(first.z), int(last.z) + 1):
		for y in range(int(first.y), int(last.y) + 1):
			for x in range(int(first.x), int(last.x) + 1):
				var center := (Vector3(x, y, z) + Vector3.ONE * 0.5) * cs
				var rel := center - eye
				var along := rel.dot(d)
				var below := rel.dot(n)
				if along <= 0.0 or along > far or below < cs * 0.5 or below > deep or absf(rel.dot(side)) > wide:
					continue
				if terrain.density_at(center) < iso:
					continue
				found.append([along, below, center])
				slab[Vector3i(x, y, z)] = true
	found.sort_custom(func(p, q): return p[0] < q[0] if not is_equal_approx(p[0], q[0]) else p[1] < q[1])
	# a dug cell's surface lies about half a cell into its neighbours, so the
	# ray goes at the cell's middle and at its face toward the line, each also
	# a little back and forth along the aim
	var axis := Vector3.ZERO
	var up := -n
	match up.abs().max_axis_index():
		Vector3.AXIS_X: axis = Vector3(signf(up.x), 0, 0)
		Vector3.AXIS_Y: axis = Vector3(0, signf(up.y), 0)
		_: axis = Vector3(0, 0, signf(up.z))
	var slide := d - axis * d.dot(axis)
	slide = slide.normalized() * 0.15 if slide.length() > 0.01 else Vector3.ZERO
	var space := get_world_3d().direct_space_state
	var reach: float = progression.reach()
	for i in range(mini(found.size(), CHEW_ASSIST_CELLS)):
		var cell: Vector3 = found[i][2]
		var mid := cell + axis * cs * 0.5
		for aim: Vector3 in [cell, cell - slide, cell + slide, mid, mid - slide, mid + slide]:
			var toward := (aim - eye).normalized()
			if not _assist_in_cone(toward, d):
				continue
			# a plain physics ray first: the search tries many rays, and only
			# one that lands on the slab is worth the full aim query
			var q := PhysicsRayQueryParameters3D.create(eye, eye + toward * reach)
			q.exclude = [player.get_rid()]
			var rough := space.intersect_ray(q)
			if rough.is_empty() or not rough.collider.has_meta("fdk_terrain_chunk"):
				continue
			var rough_cell: Vector3 = (((rough.position as Vector3) - (rough.normal as Vector3) * cs * 0.5) / cs).floor()
			if not slab.has(Vector3i(rough_cell)):
				continue
			var hit := _look_hit_along(eye, toward, reach)
			if hit.is_empty() or not hit.collider.has_meta("fdk_terrain_chunk") or eye.distance_to(hit.position) > reach:
				continue
			var target := _terrain_target(hit, toward)
			if not slab.has(Vector3i((target / cs).floor())) or terrain.density_at(target) < iso:
				continue
			return {"cell": target, "aim": aim, "hit": hit}
	return {}

## The hand's ray stays inside the cone round the aim line, and inside the view.
func _assist_in_cone(toward: Vector3, d: Vector3) -> bool:
	var cone := minf(player.camera.fov * 0.5 - 3.0, CHEW_ASSIST_CONE_MAX)
	return toward.dot(d) >= cos(deg_to_rad(cone))

## The held cell's contact this frame, along the same ray it was taken on, or
## empty: still solid, inside the arm's reach and the cone, hidden by nothing,
## and still the cell the centre line's rule picks from that contact.
func _assist_contact(eye: Vector3, d: Vector3, cell: Vector3, aim: Vector3) -> Dictionary:
	if terrain.density_at(cell) < terrain_config.iso_level or eye.distance_to(aim) < 0.001:
		return {}
	var toward := (aim - eye).normalized()
	if not _assist_in_cone(toward, d):
		return {}
	var reach: float = progression.reach()
	var hit := _look_hit_along(eye, toward, reach)
	if hit.is_empty() or not hit.collider.has_meta("fdk_terrain_chunk") or eye.distance_to(hit.position) > reach:
		return {}
	if not _terrain_target(hit, toward).is_equal_approx(cell):
		return {}
	return hit

## Flesh straight ahead, past the arm: the point on it, or INF. Only tells
## "cannot reach"; the aim, the reach and what may be torn are _look_hit's.
func _reach_short_point() -> Vector3:
	var ray: Array = player.get_look_ray()
	var reach: float = progression.reach()
	var q := PhysicsRayQueryParameters3D.create(ray[0], ray[0] + ray[1] * (reach + REACH_SHORT_EXTRA))
	q.exclude = [player.get_rid()]
	var far := get_world_3d().direct_space_state.intersect_ray(q)
	if far.is_empty() or not far.collider.has_meta("fdk_terrain_chunk"):
		return Vector3.INF
	var at: Vector3 = far.position
	# a face the aim just rejected inside the reach, or a collider lagging a
	# fresh hole, is not flesh out of reach
	if ray[0].distance_to(at) <= reach or terrain.density_at(at + ray[1] * terrain_config.cell_size * 0.5) < terrain_config.iso_level:
		return Vector3.INF
	return at

## The eat input is held and nothing is in reach. If flesh is there just past
## the arm, both hands stretch at it with open fingers (FDKHandsRig
## .on_reach_short); held long enough, the ring may show the key that digs up
## or down (dig_key_hint). Nothing is pressed, torn or sounded.
func _show_reach_short(delta: float) -> void:
	var at := _reach_short_point()
	if at == Vector3.INF:
		return
	reach_short_at = at
	_reach_short_frame = Engine.get_process_frames()
	reach_short_t = minf(reach_short_t + delta, DIG_HINT_AFTER * 2.0)
	if reach_short_t >= DIG_HINT_AFTER:
		_dig_hint_left = DIG_HINT_LINGER
	for rig in FPHandMotions.rigs_of(self):
		rig.on_reach_short(at)

## The key cap the aim ring shows after the hands have stretched at flesh out
## of reach for a while: "fdk_jump" looking up where Space climbs, "fdk_crouch"
## looking down while standing, else "". Each goes away for good (this session;
## nothing is saved) once its key is pressed while shown.
func dig_key_hint() -> String:
	if _dig_hint_left <= 0.0 or _seated or _mirror_open or is_pulling_canary():
		return ""
	var pitch := rad_to_deg(asin(clampf(float(player.get_look_ray()[1].y), -1.0, 1.0)))
	if pitch >= DIG_HINT_PITCH and not _dig_up_learned and player.climb_enabled:
		return "fdk_jump"
	if pitch <= -DIG_HINT_PITCH and not _dig_down_learned and not player._is_crouching:
		return "fdk_crouch"
	return ""

## One frame of a bite refused because nothing more fits: the stomach
## (`stomach_full`) or the carrying hands. The wall at `at` is gripped and let
## go (the terrain's press, FULL_PRESS_TIME) and the refusal is told once every
## FULL_REFUSE_EVERY seconds, at once after a break. The stomach's refusal
## also lurches the stomach mass and dips the head. No density changes.
func _refuse_full(at: Vector3, dir: Vector3, stomach_full: bool) -> void:
	var frame := Engine.get_process_frames()
	if frame - _full_frame > 2:
		_full_cool = 0.0
	_full_frame = frame
	_full_cool -= get_process_delta_time()
	if _full_cool <= 0.0:
		_full_cool = FULL_REFUSE_EVERY
		_full_press_t = FULL_PRESS_TIME
		if stomach_full:
			stomach_view.heave()
			if danger_show != null:
				danger_show.heave()
			stomach_refused.emit(at)
		else:
			carry_refused.emit(at)
	var u := clampf(_full_press_t / FULL_PRESS_TIME, 0.0, 1.0)
	terrain.set_press(at, -dir, FULL_PRESS * sin(PI * (1.0 - u)) if _full_press_t > 0.0 else 0.0)

## Carrying with the big saw up (M28 / T2) and the stomach at its end: the
## stroke's flesh would go down, so the stroke is refused like a hand bite.
func saw_stroke_refused() -> bool:
	return carry_mode and progression.equipped() == "big_saw" and stomach.is_full()

func _on_chew_refused_full(world_pos: Vector3) -> void:
	_refuse_full(_chew_contact if _chew_contact != Vector3.INF else world_pos, player.get_look_ray()[1], true)

## The pull on the held flesh at `at` (look direction `dir`, progress
## `ratio`): the terrain's press, released while the hands show the tear,
## and the tear feel's weeping drops. The held cell's tissue sets how far it
## stretches and what it weeps (FDKTissueRules.look). Visual only.
func _show_pull(at: Vector3, dir: Vector3, ratio: float) -> void:
	var tissue: int = terrain.tissue_at(_chew_target) if _chew_target != Vector3.INF else FDKTissueRules.COMPRESSIVE
	terrain.set_press(at, -dir, ratio if hands_rig.state != FDKHandsRig.HandState.TEAR else 0.0, float(FDKTissueRules.look(tissue).pull_gain))
	tear_feel.on_chew(ratio, at, -dir, tissue)

## Point both hand rigs (plain and mutation) at the grabbed flesh, or clear
## it with Vector3.INF. The rig only reads the point; it never decides a tear.
func set_hand_reach(world_pos: Vector3) -> void:
	for rig in FPHandMotions.rigs_of(self):
		if world_pos == Vector3.INF:
			rig.clear_reach_point()
		else:
			rig.set_reach_point(world_pos)

## Tear out the cell at p and return the flesh units that came away (never
## more than its corners actually lost, see FDKStomachConfig). Publishes the
## hole at the first tear render. Used by the extra cells of the big saw and
## mutations; the chewer measures its own cell the same way.
func eat_cell_at(p: Vector3) -> float:
	var before: float = terrain.cell_corner_sum(p)
	terrain.dig_at(p, 1.0)
	terrain.queue_visible_tear(p)
	return stomach_config.units_for_removed(before - terrain.cell_corner_sum(p))

## What every real tear shows, the chewer's and the M22 alien hand's
## (fp_mutation_apply.alien_tear): blood on the hands, and the fresh hole --
## strands snap, the rim springs back, bits and blood spray toward the eater,
## the view jolts (fp_tear_feel.gd). Visual only: the caller has already
## removed the density and queued the hole (eat_cell_at / the chewer).
func show_tear(world_pos: Vector3) -> void:
	hand_blood = minf(1.0, hand_blood + 0.05)
	# world_pos is the torn cell's centre: its tissue picks the blood, the
	# strands and the recoil (the stored tissue outlives the dig)
	tear_feel.on_tear(world_pos, player.camera.global_position, terrain.tissue_at(world_pos))

## Torn flesh that goes to the hands instead of the stomach.
func add_carried(shell: int, units: float) -> void:
	carried_flesh += units
	carried_units[shell] = float(carried_units.get(shell, 0.0)) + units

## Torn flesh that goes straight down: stomach and the hair it grows.
func swallow_torn(shell: int, units: float) -> void:
	stomach.add_flesh(units)
	progression.on_flesh_eaten(shell, units)
	show_swallow(units)

## The swallow of flesh a tear just sent down, on the swallow sound's beat
## (FPStomachView.SWALLOW_DELAY after the tear): the stomach mass kicks up
## once and the head nods. Visual only; carried flesh is not swallowed.
func show_swallow(units: float) -> void:
	if units <= 0.0:
		return
	stomach_view.swallow_kick(units, FPStomachView.SWALLOW_DELAY)
	tear_feel.on_swallow(FPStomachView.SWALLOW_DELAY)

## Everything that moves on its own each frame (tests drive it directly).
func step_world(delta: float) -> void:
	FPProfile.begin("stream")
	_stream_world()
	FPProfile.end("stream")
	var blockers: Array = []
	for b in barrier_field.get_barriers():
		if not b.is_broken():
			blockers.append(Vector4(b.position.x, b.position.y, b.position.z, b.radius))
	if mutation_apply != null:
		blockers.append_array(mutation_apply.extra_regen_blockers())
	terrain.regen_blockers = blockers
	barrier_field.pressure_scale = BARRIER_PRESSURE * _regen_scale(player.global_position)
	FPProfile.begin("regen")
	terrain.regenerate_all(delta, player.global_position, BODY_PROTECT_RADIUS)
	FPProfile.end("regen")
	FPProfile.begin("barriers")
	barrier_field.update(delta)
	FPProfile.end("barriers")
	FPProfile.begin("nerves")
	_step_nerve_touch(delta)
	FPProfile.end("nerves")
	FPProfile.begin("hazards_crush")
	_step_hazards(delta)
	FPProfile.end("hazards_crush")
	FPProfile.begin("canary")
	_step_canary(delta)
	_step_canary_pull(delta)
	FPProfile.end("canary")
	if danger_show == null and hands_rig != null:
		danger_show = (load("res://main/scripts/fp_danger_show.gd") as GDScript).new()
		danger_show.setup(self)
	if danger_show != null:
		danger_show.tick(delta)
	if belt_swap != null:
		belt_swap.tick(delta)
	if interact_ring != null:
		FPProfile.begin("interact_ring")
		var target := interact_target()
		# the glyph names the input that acts (FPInteractions.plan): the belt
		# hooks take only the hand buttons; every other target takes F and the
		# hands that can do it. One input shows in one place: the ring's vomit
		# key gives way to the stomach's, the opening's to both
		interact_ring.set("action", "fp_vomit" if target == "toilet" else ("fp_pick" if target == "belt" else "fp_interact"))
		# at the mirror with something to buy the glyph is the Tab key cap: the
		# mirror is where the forearm screen buys (decision 0014). F and the
		# hands still open the cabinet door.
		var mirror_buys := target == "mirror" and at_mirror() and progression.any_buyable_mutation()
		if mirror_buys:
			interact_ring.set("action", "fp_mutate")
		interact_ring.set("shown", target != "" and not _settling and not is_pulling_canary())
		# standing over the canary hole: the crouch key cap says "get down"
		var crouch_hint := target == "" and not _settling and canary_crouch_hint()
		# hands stretched at flesh out of reach: the key that digs up or down
		# (one glyph by the ring: never beside another target's)
		var key_hint := "fdk_crouch" if crouch_hint else (dig_key_hint() if target == "" and not _settling else "")
		if key_hint != "" and not crouch_hint and Input.is_action_pressed(key_hint):
			if key_hint == "fdk_jump":
				_dig_up_learned = true
			else:
				_dig_down_learned = true
			key_hint = ""
		if key_hint != "":
			interact_ring.set("action", key_hint)
			interact_ring.set("shown", true)
		if key_hint != "":
			interact_ring.set("hand_left", false)
			interact_ring.set("hand_right", false)
		elif target == "belt":
			# only the buttons whose hand that item goes to (the blender and
			# the compass to the left) or whose held item goes back there
			interact_ring.set("hand_left", belt_swap.takes(belt_swap.aimed_hook(), FDKToolKit.Hand.LEFT))
			interact_ring.set("hand_right", belt_swap.takes(belt_swap.aimed_hook(), FDKToolKit.Hand.RIGHT))
		else:
			interact_ring.set("hand_left", target != "toilet" and not FPInteractions.right_hand_only(self, target))
			interact_ring.set("hand_right", target != "toilet" and not FPInteractions.left_hand_only(target))
		# the stomach's key shows only where vomiting settles (decision 0009)
		var stomach_key := stomach.fill_ratio() >= 1.0 and at_settle_spot
		interact_ring.set("glyph_on", not (target == "toilet" and stomach_key))
		opening_view.hints.vomit_muted = target == "toilet" or stomach_key
		opening_view.hints.lever_left = not _settling
		if target == "lever" and not _settling:
			opening_view.hints.lever_at = Vector2.INF
		if mirror_buys:
			opening_view.hints.mirror_at = Vector2.INF # the ring already shows the key
		FPProfile.end("interact_ring")
	FPProfile.begin("death_drop")
	_step_death_drop(delta)
	FPProfile.end("death_drop")
	FPProfile.begin("contraction")
	terrain.step_contraction(delta, player.global_position)
	FPProfile.end("contraction")
	FPProfile.begin("tissue_tools")
	tissue_tools.step_charge(delta, hand_actions.charging())
	tissue_tools.step_blend(delta)
	FPProfile.end("tissue_tools")
	# The safety net under the last bite (tear_opens_outside): a body that got
	# past the outer shell some other way (a hole dissolved by spray) still ends.
	if not ended and player.global_position.distance_to(RESTROOM_CENTER) >= OUTER_RADIUS - 0.3:
		reach_ending()

func _look_hit() -> Dictionary:
	var ray: Array = player.get_look_ray()
	return _look_hit_along(ray[0], ray[1], progression.reach())

## The aim's contact along any ray from the eye: the same reach, occlusion and
## published / unpublished surface rules as the centre line (_look_hit is this
## along the look ray). The chew assist judges its off-centre cells with it.
func _look_hit_along(origin: Vector3, direction: Vector3, reach: float) -> Dictionary:
	var ray: Array = [origin, direction]
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

## F on whatever is aimed (tests and old callers; normal input goes through
## FPInteractions.press, which also applies the one-target-per-frame rule).
func _interact() -> void:
	var target := interact_target()
	# F settles at the toilet like V does, standing by it without aiming
	if target == "" and _near_toilet() and has_settle_contents():
		start_settlement()
		return
	if FPInteractions.acts_on(target):
		activate_target(target, FPInteractions.SOURCE_INTERACT)

## The right hand on whatever is aimed (same, for the right-hand button).
func _pick() -> void:
	var target := interact_target()
	if FPInteractions.acts_on(target):
		activate_target(target, FPInteractions.SOURCE_RIGHT)

## Act on one aimed target. `source` is FPInteractions.SOURCE_INTERACT (F),
## SOURCE_RIGHT or SOURCE_LEFT (a hand button). The hand that pressed does
## the reaching (left click the left hand; F and right click the right).
## They differ only where the right hand itself does the work: at the tank
## it takes or puts back a tooth without leaning in, and at the open vent it
## hands over teeth or takes the offer. The left hand does what F does there,
## going on one tooth at a time while its own button stays held.
func activate_target(target: String, source: String) -> void:
	var right := source == FPInteractions.SOURCE_RIGHT
	var left := source == FPInteractions.SOURCE_LEFT
	var hold_action := "fdk_eat" if left else "fp_interact"
	hand_motions.acting_side = -1.0 if left else 1.0
	_activate_target(target, right, hold_action)
	hand_motions.acting_side = 1.0

func _activate_target(target: String, right: bool, hold_action: String) -> void:
	match target:
		"tank_lid":
			if tank_lid.held: tank_lid.drop()
			else: tank_lid.pick()
		"mirror":
			restroom.mirror_art.call("toggle_cabinet")
			vent.notice("mirror")
		"canary": begin_canary_pull()
		"tank_teeth":
			if right:
				_start_tooth_op("back" if progression.teeth_in_hand > 0 else "take", "fp_pick")
			else:
				# lean in over the tank, then pick teeth one at a time
				hand_motions.play_tank_lean()
				_start_tooth_op("take", hold_action)
		"lever":
			hand_motions.play_press(lever_point(), true)
			pull_lever()
		"vent":
			if right and vent.is_open:
				if progression.teeth_in_hand > 0: _start_tooth_op("place", "fp_pick")
				elif not vent.offers.is_empty(): take_vent_offer()
				else: reach_into_vent()
			else:
				use_vent(hold_action)
		"sink": wash_hands()
		"toilet":
			if has_settle_contents():
				start_settlement()
			else: sit_down()
		"door":
			hand_motions.play_press(door_handle_point(), false)
			restroom.set_door_open(not restroom.is_door_open())
		"tumor": pick_up_tumor()
		"rest_can": take_rest_can()

## The door's handle in world space (where a hand opening it takes hold).
func door_handle_point() -> Vector3:
	var width := 2.0 * FPRestroom.DOOR_HALF_W - 0.01
	return restroom.door_pivot.to_global(Vector3(width - 0.095, 0.995, 0))

func mirror_point() -> Vector3:
	return restroom.mirror_art.to_global(Vector3((restroom.mirror_art.call("mirror_center") as Vector3).x, 1.65, 0.24))

## Standing in the restroom and looking into the mirror from close by: the
## only place the Tab screen buys (decision 0014). Judged from the mirror's
## own place alone. An open cabinet door shows no reflection: looking only.
const MIRROR_BUY_DEGREES := 35.0
const MIRROR_BUY_REACH := 1.6
func at_mirror() -> bool:
	if not restroom.contains(player.global_position) or bool(restroom.mirror_art.get("cabinet_open")):
		return false
	return _looking_at(mirror_point(), MIRROR_BUY_DEGREES, MIRROR_BUY_REACH)

## Where the mirror is on screen while hairs or a bump could buy the first
## mutation and none was ever bought (INF otherwise): the Tab key cap pulses
## there, like the first lever's ring. Nothing is saved; the first mutation
## owned ends it.
func _first_mirror_spot() -> Vector2:
	if _settling or _seated or _mirror_open or is_pulling_canary() or not restroom.contains(player.global_position):
		return Vector2.INF
	if bool(restroom.mirror_art.get("cabinet_open")) or not progression.all_mutations().is_empty() or not progression.any_buyable_mutation():
		return Vector2.INF
	var cam: Camera3D = player.camera
	var p := mirror_point()
	var rect := get_viewport().get_visible_rect()
	var inner := rect.grow(-40.0) if rect.size.x > 100.0 and rect.size.y > 100.0 else rect
	if cam.is_position_behind(p) or not inner.has_point(cam.unproject_position(p)):
		return Vector2.INF
	return cam.unproject_position(p)

func sink_point() -> Vector3:
	return Vector3(-FPRestroom.HALF.x + 0.3, 0.95, FPRestroom.SINK_Z)

## 형님 2026-09-29: toilet interact ring should only show facing it, close (~1.2m).
func toilet_point() -> Vector3:
	return restroom.toilet.to_global(Vector3(0, 0.45, 0.3))

func canary_hole_point() -> Vector3:
	return FPRestroom.CANARY_HOLE + Vector3(0.03, 0.0, 0.0)

## Standing and looking down at the canary hole, too high to reach it
## (user 2026-11-08): the ring shows the crouch key so the player learns the
## body can get down there. The key cap follows the crouch keybind.
const CANARY_HINT_DEGREES := 22.0
const CANARY_HINT_REACH := 2.1
func canary_crouch_hint() -> bool:
	if has_canary or is_pulling_canary() or player._is_crouching or _seated or _mirror_open:
		return false
	return _looking_at(canary_hole_point(), CANARY_HINT_DEGREES, CANARY_HINT_REACH)

func _near_toilet() -> bool:
	return player.global_position.distance_to(restroom.toilet.to_global(Vector3(0, 0.9, 0.5))) < 1.3

## Something to give at the toilet: a stomach to empty, tumors carried or
## a bowl not yet flushed.
func has_settle_contents() -> bool:
	return stomach.fill > 0.0 or progression.tumors.carried_count() > 0 or toilet.has_contents()

func _near_rest_point() -> int:
	for i in range(rest_points.size()):
		var bucket := rest_points[i] + Vector3(0, -FPWorldFeatures.CONTAINER_HALF.y + 0.9, -FPWorldFeatures.CONTAINER_HALF.z + 0.5)
		if player.global_position.distance_to(bucket) < 1.4:
			return i
	return -1

# --- stomach, toilet, rest points ----------------------------------------------

## Seconds the vomit key must stay down, away from the bowl and the rest
## points, before the stomach is thrown away (decision 0009, 2026-11-14): the
## body bows first (hands on the knees by 0.6 s) and the first retch is rising
## from 0.65 s, the first lump at 0.864 s. Letting go before this stands the
## body back up with the stomach as it was. A tap or a row of taps never
## empties it: the held time starts from zero at every press.
const DISCARD_HOLD := 0.8
## Seconds the key has been held into a discard; negative = none running.
var _discard_hold_t := -1.0

## One frame of the held discard (tests drive it with `held`). Keeps counting
## only while the key is down, the floor-vomit bow it started is still going,
## and the body is still away from the bowl and the rest points with nothing
## else holding the input. Anything else ends it and the body straightens;
## reaching DISCARD_HOLD empties the stomach for nothing.
func discard_hold_step(delta: float, held: bool) -> void:
	if _discard_hold_t < 0.0:
		return
	var bowing: bool = hand_motions.kind == "vomit_floor" and not hand_motions.cancelled
	if not held or not bowing or _settling or _seated or _mirror_open or _near_toilet() or _near_rest_point() >= 0:
		_discard_hold_t = -1.0
		if hand_motions.kind == "vomit_floor":
			hand_motions.cancel()
		return
	_discard_hold_t += delta
	if _discard_hold_t < DISCARD_HOLD:
		return
	_discard_hold_t = -1.0
	stomach.vomit()
	mutation_apply.take_cud_credit() # lost with the rest
	progression.discard_stomach()

## The held discard is running (the body is bowing, nothing thrown away yet).
func discard_holding() -> bool:
	return _discard_hold_t >= 0.0

## At the toilet or a rest point vomiting settles; elsewhere nothing.
func request_vomit() -> void:
	if _settling:
		return
	if _near_toilet():
		start_settlement()
	elif _near_rest_point() >= 0:
		hand_motions.play_vomit(false, stomach.fill_ratio())
		settle_at_rest_point()
	elif not lever_settled and not stomach.is_full():
		hand_motions.play_gag()
		dry_heaved.emit()
	else:
		# also before the first settlement once the stomach is at its end and
		# every bite is refused: with the tunnel grown shut behind there is no
		# other way out (decision 0013). Nothing is paid for it. The press only
		# starts the bow; the stomach goes once the key has been held
		# DISCARD_HOLD seconds (discard_hold_step).
		hand_motions.play_vomit(false, stomach.fill_ratio())
		_discard_hold_t = 0.0

func start_settlement() -> void:
	if _settling:
		return
	if stomach.fill > 0.0:
		hand_motions.play_vomit(true, stomach.fill_ratio())
	toilet.vomit_into(stomach.vomit() + mutation_apply.take_cud_credit())
	if opening_view != null:
		opening_view.hints.vomit_learned = true # settled once: the V hint has done its job
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
	var settled: bool = int(got["teeth"]) > 0 or not tumor_kinds.is_empty()
	if settled:
		lever_settled = true
	# an empty bowl flushed again does not restart the being's calling
	if settled or not vent._first_flush_heard:
		vent.on_flush()
	vent.on_tumors_settled(tumor_kinds)
	flushed.emit(got["teeth"], got["hairs"])
	if _settling:
		leave_settlement()
	if settled:
		save_to_disk() # a settlement is a checkpoint worth keeping
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
	player.global_position = STAND_POS
	player.set("_pitch", 0.0)
	player.camera_pivot.rotation.x = 0.0
	player.set_physics_process(true)
	return true

func is_seated() -> bool:
	return _seated

func _process_seated() -> void:
	for action in ["fp_pick", "fp_vomit", "fp_interact", "ui_cancel", "fdk_eat",
		"fdk_move_forward", "fdk_move_back", "fdk_move_left", "fdk_move_right", "fdk_jump"]:
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
		"fp_interact", "ui_cancel", "fdk_eat", "fdk_move_forward", "fdk_move_back", "fdk_move_left", "fdk_move_right", "fdk_jump":
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
	title_screen.setup(self, has_current_save())
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
	title_screen.has_save = has_current_save()
	title_screen.open()
	# the start screen opens out of shut eyes, as the Esc screen closes them
	wake_lids.set_eyes(progression.all_mutations(), restroom_field_angle())
	wake_lids.play(false)
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
	opening_view.set_eyes(progression.all_mutations(), restroom_field_angle())
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
	if hand_motions.vent_looking():
		return "vent_look"
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
		"vent_look":
			_end_lean()
		"pause":
			open_pause_menu()
	return t

func open_pause_menu() -> void:
	chewer.stop()
	pause_menu.set_eyes(progression.all_mutations(), restroom_field_angle())
	pause_menu.open()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Where the restroom lies from the eye, as a screen angle: 0 = straight
## ahead (up), positive to the right (the magnetic eye's field, M03).
func restroom_field_angle() -> float:
	var to := RESTROOM_CENTER - player.camera.global_position
	var local := player.camera.global_basis.inverse() * to
	if Vector2(local.x, local.z).length() < 0.01:
		return 0.0
	return atan2(local.x, -local.z)

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

## Version of the slot on disk; -1 when there is none or it cannot be read.
func save_file_version() -> int:
	if not has_save_file():
		return -1
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return -1
	var data = f.get_var()
	f.close()
	return int((data as Dictionary).get("version", 1)) if data is Dictionary else -1

## A slot this build continues from. One written before SAVE_VERSION is not
## (old saves start as a new game, decision 0012).
func has_current_save() -> bool:
	return save_file_version() >= SAVE_VERSION

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
	if int((data as Dictionary).get("version", 1)) < SAVE_VERSION:
		return false # an old slot is not converted: the run starts new
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
	if FileAccess.file_exists(user_keybinds_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(user_keybinds_path))
	_register_keybinds()

func settle_at_rest_point() -> Dictionary:
	var got := progression.settle(stomach.vomit() + mutation_apply.take_cud_credit())
	if opening_view != null:
		opening_view.hints.vomit_learned = true
	flushed.emit(got["teeth"], got["hairs"])
	return got

## Tank teeth shown as a pile of real teeth in the tank model, one per
## tooth, never a number.
func _update_tank_teeth() -> void:
	var shown := progression.teeth
	if shown == _tank_teeth_shown:
		return
	_tank_teeth_shown = shown
	if restroom.tank_art != null:
		restroom.tank_art.call("set_teeth", shown)

## Where teeth come from and where they go, shown in the room and not said
## (user 2026-11-09 "이빨을 챙겨야 한다는 것에 대한 넛지가 부족함"; the
## being calls them 봉, which never says "teeth"):
## - the open grate: an empty hand grasping at the air while teeth wait in
##   the tank and the hand is empty, the lip glinting while the player holds
##   teeth (FPVent.nudge_for);
## - the shut grate knocks in its frame every GRATE_KNOCK_EVERY s while the
##   player stands in the room with teeth in hand;
## - before the first trade, teeth shut in the tank knock its lid every
##   TANK_KNOCK_EVERY s while the player is in the room with an empty hand.
const GRATE_KNOCK_EVERY := 3.0
const TANK_KNOCK_FIRST := 2.0
const TANK_KNOCK_EVERY := 5.0
var _grate_knock_t := 0.0
var _tank_knock_t := 0.0

func _step_teeth_nudges(delta: float) -> void:
	vent.update_nudge(progression.teeth, progression.teeth_in_hand)
	_lean_into_paid_offer()
	var calm: bool = not ended and not _settling and not _seated and not _mirror_open and not is_opening() and restroom.contains(player.global_position)
	if grate_knock_due() and calm:
		_grate_knock_t += delta
		if _grate_knock_t >= GRATE_KNOCK_EVERY:
			_grate_knock_t = 0.0
			vent.art.call("jostle")
	else:
		_grate_knock_t = GRATE_KNOCK_EVERY * 0.5
	if tank_knock_due() and calm:
		_tank_knock_t += delta
		if _tank_knock_t >= TANK_KNOCK_EVERY:
			_tank_knock_t = 0.0
			restroom.tank_art.call("jostle")
			tank_teeth_knocked.emit()
	else:
		_tank_knock_t = TANK_KNOCK_EVERY - TANK_KNOCK_FIRST

## Teeth given and items held out for them: the head goes in under the
## vent by itself (user 2026-11-09: the move came on opening, before any
## tooth, and never after paying). Teeth still in the hand keep it out
## for more; a shut grate or a withdrawn offer drops it.
func _lean_into_paid_offer() -> void:
	if not vent.offer_after_pay:
		return
	if not vent.is_open or vent.offers.is_empty():
		vent.offer_after_pay = false
		return
	if progression.teeth_in_hand > 0 or _tooth_op != "" or _settling or _seated or _mirror_open or ended:
		return
	vent.offer_after_pay = false
	_begin_vent_look()

## The shut grate wants the teeth in the player's hand.
func grate_knock_due() -> bool:
	return not vent.is_open and progression.teeth_in_hand > 0 and vent.absent_left <= 0.0 and vent.art != null

## Teeth shut in the tank, nothing in the hand, no trade ever made.
func tank_knock_due() -> bool:
	return progression.teeth > 0 and progression.teeth_in_hand <= 0 and tank_lid != null and tank_lid.on_tank 		and not vent.paid_ever() and restroom.tank_art != null and not _tank_rattling()

## The settlement's own rattle of teeth going in is still sounding.
func _tank_rattling() -> bool:
	return toilet != null and toilet.is_rattling()

## Pick one tooth out of the open tank.
func scoop_teeth() -> int:
	if tank_lid == null or tank_lid.on_tank:
		return 0
	var first := progression.teeth_in_hand == 0
	var n := progression.take_tooth()
	if n > 0 and hand_motions.tank_leaning():
		hand_motions.dip()
	if n > 0 and first:
		vent.notice("grab")
		if not hand_motions.tank_leaning():
			hand_motions.play_scoop(restroom.tank_art.to_global(Vector3(0, 0.3, 0)) if restroom.tank_art != null else Vector3.INF)
	return n

## One tooth from the hand back into the tank.
func put_tooth_back() -> int:
	var n := progression.put_back_tooth()
	if n > 0 and hand_motions.tank_leaning():
		hand_motions.dip()
	if n > 0 and progression.teeth_in_hand == 0:
		vent.notice("put_back")
	return n

## One tooth from the hand onto the vent lip; the being looks at the pile
## once the hand stops (FPVent.APPRAISE_DELAY).
func place_tooth_at_vent() -> bool:
	if progression.teeth_in_hand <= 0 or not vent.add_tooth(progression):
		return false
	var first := vent.pile == 1
	progression.teeth_in_hand -= 1
	if first and not hand_motions.vent_looking():
		hand_motions.play_pour(1)
	return true

func _start_tooth_op(op: String, action: String) -> void:
	_tooth_op = op
	_tooth_action = action
	_tooth_rep_t = TOOTH_REPEAT_DELAY
	_do_tooth_op(op)

func _do_tooth_op(op: String) -> int:
	match op:
		"take": return scoop_teeth()
		"back": return put_tooth_back()
		"place": return 1 if place_tooth_at_vent() else 0
	return 0

## While the input that started a tooth op stays held on the same target,
## keep going one tooth at a time.
func _repeat_tooth_op(delta: float) -> void:
	if _tooth_op == "":
		return
	var target := interact_target()
	var on_target := target == "tank_teeth" if _tooth_op != "place" else (target == "vent" and vent.is_open)
	if not Input.is_action_pressed(_tooth_action) or not on_target or tank_lid.held:
		_tooth_op = ""
		return
	_tooth_rep_t -= delta
	while _tooth_rep_t <= 0.0:
		_tooth_rep_t += TOOTH_REPEAT_EVERY
		if _do_tooth_op(_tooth_op) == 0:
			_tooth_op = ""
			return

## Both leans lock the body and end on frantic movement (LEAN_FRANTIC
## movement presses within LEAN_FRANTIC_WINDOW seconds); backing off ends
## them too (fp_hand_motions TANK_CANCEL).
## The lean over the tank ends when the eye leaves it (looking away), the
## lid goes back on, or there is nothing left to pick or put back; left/right
## walk the head round the tank (still bent over it, LEAN_ORBIT_MAX each way).
const LEAN_ORBIT_SPEED := 1.6
const LEAN_ORBIT_MAX := 1.2
const LEAN_FRANTIC := 4
const LEAN_FRANTIC_WINDOW := 1.0
var _lean_off_t := 0.0
var _lean_presses: Array[float] = []
var _lean_clock := 0.0
func _watch_leans(delta: float) -> void:
	player.move_locked = hand_motions.leaning()
	if not hand_motions.leaning():
		_lean_off_t = 0.0
		_lean_presses.clear()
		return
	_lean_clock += delta
	for a in ["fdk_move_forward", "fdk_move_back", "fdk_move_left", "fdk_move_right"]:
		if Input.is_action_just_pressed(a):
			_lean_presses.append(_lean_clock)
	_lean_presses = _lean_presses.filter(func(t): return _lean_clock - t <= LEAN_FRANTIC_WINDOW)
	if _lean_presses.size() >= LEAN_FRANTIC:
		_end_lean()
	elif hand_motions.vent_looking():
		_steer_vent_look(delta)
	else:
		_steer_tank_lean(delta)

func _end_lean() -> void:
	hand_motions.release_tank_lean()
	hand_motions.release_vent_look()
	player.move_locked = false

func _steer_tank_lean(delta: float) -> void:
	var turn := Input.get_action_strength("fdk_move_right") - Input.get_action_strength("fdk_move_left")
	hand_motions.lean_orbit = clampf(hand_motions.lean_orbit + turn * LEAN_ORBIT_SPEED * delta, -LEAN_ORBIT_MAX, LEAN_ORBIT_MAX)
	var empty: bool = progression.teeth <= 0 and progression.teeth_in_hand <= 0
	if tank_lid.on_tank or tank_lid.held or empty:
		_end_lean()
		return
	_lean_off_t = 0.0 if interact_target() == "tank_teeth" else _lean_off_t + delta
	if _lean_off_t > 0.4:
		_end_lean()

## Head in under the open vent: the mouse and left/right turn the eye across
## the offer within VENT_PAN_MAX (the aim stays on the vent), and with
## nothing left to trade the head comes back out by itself.
const VENT_PAN_MAX := Vector2(0.62, 0.34)
const VENT_PAN_KEYS := 1.1
const VENT_LOOK_IDLE := 1.6
var _vent_pan_base := Vector2.ZERO
var _vent_look_idle := 0.0

func _begin_vent_look() -> bool:
	if not restroom.contains(player.global_position):
		return false
	if not hand_motions.vent_looking():
		hand_motions.play_vent_look()
		_vent_pan_base = Vector2(player._yaw, player._pitch)
		_vent_look_idle = 0.0
	return true

func _steer_vent_look(delta: float) -> void:
	if not vent.is_open or not restroom.contains(player.global_position) or _settling or _seated or ended:
		_end_lean()
		return
	var turn := Input.get_action_strength("fdk_move_right") - Input.get_action_strength("fdk_move_left")
	player._yaw -= turn * VENT_PAN_KEYS * delta
	var pan := Vector2(wrapf(player._yaw - _vent_pan_base.x, -PI, PI), player._pitch - _vent_pan_base.y)
	pan = pan.clamp(-VENT_PAN_MAX, VENT_PAN_MAX)
	player._yaw = _vent_pan_base.x + pan.x
	player._pitch = _vent_pan_base.y + pan.y
	hand_motions.vent_pan = pan
	var idle: bool = progression.teeth_in_hand <= 0 and vent.pile <= 0 and vent.offers.is_empty()
	_vent_look_idle = _vent_look_idle + delta if idle else 0.0
	if _vent_look_idle > VENT_LOOK_IDLE:
		_end_lean()

func try_pick_tank_item() -> bool:
	return scoop_teeth() > 0

# --- vent ------------------------------------------------------------------------

## `hold_action`: the input that keeps placing teeth while held (F, or the
## left hand button when the left hand pressed).
## Teeth in the hand always go on the lip first, standing where the hand
## and the lip are in view (user 2026-11-09: opening with teeth in hand put
## the head straight in under the vent, the hands sunk out of the frame and
## the lip out of view, so no tooth could be seen going in); the head goes
## in only for what the being holds out.
func use_vent(hold_action: String = "fp_interact") -> void:
	if not vent.is_open:
		vent.open(progression.teeth + progression.teeth_in_hand, progression.teeth_in_hand, tank_lid != null and not tank_lid.on_tank)
		if progression.teeth_in_hand <= 0 and not vent.offers.is_empty():
			_begin_vent_look()
	elif progression.teeth_in_hand > 0:
		_start_tooth_op("place", hold_action)
	elif vent.offers.is_empty() and vent.bring_out_held():
		# the offer it held back for the teeth, now the hand is empty
		_begin_vent_look()
	elif not vent.offers.is_empty():
		# The first press puts the head in under the hands (user 2026-11-07);
		# inside, F takes the offer the eye is nearest, as the right button
		# does (2026-11-02 play: F on the offered items did nothing). Leaving
		# them is walking off (the being holds them for next time).
		if hand_motions.vent_looking() or not _begin_vent_look():
			take_vent_offer()
	elif progression.tumors.carried_count() > 0:
		vent.place_weird("tumor") # it will not take it; the tumor stays in hand
	elif hand_motions.vent_looking():
		# head in, the being still looking at the pile: a stray press is not
		# the grate shutting on the trade
		if vent.pile <= 0:
			vent.close()
	elif vent.offers.is_empty():
		vent.close()

## Every tooth in the hand onto the lip at once, looked at right away
## (tests and quick trades; normal input places them one by one).
func place_teeth_at_vent() -> Array[String]:
	var n := progression.teeth_in_hand
	if n <= 0 or not vent.is_open:
		return []
	for i in range(n):
		vent.add_tooth(progression)
	progression.teeth_in_hand = 0 # the being keeps them all
	if not hand_motions.vent_looking():
		hand_motions.play_pour(n)
	return vent.appraise(progression)

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
	# a full belt refuses it on the lip: no grab that comes back empty
	if idx >= 0 and idx < vent.offer_nodes().size() and progression.can_hold(id):
		var at: Vector3 = (vent.offer_nodes()[idx] as Node3D).global_position
		hand_motions.play_take(at, str(FPVent.ART_KIND.get(id, "junk")))
	return vent.take(id, progression)

## Handful back into the tank: the being sighs.
## Every tooth in the hand back into the tank.
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
	if player != null and not restroom.contains(player.global_position):
		progression.max_depth = maxf(progression.max_depth, player.global_position.distance_to(RESTROOM_CENTER))
	# right before the outermost shell the being gives everything away
	# (docs/content/vent-lines.md 마지막 거래)
	vent.final_trade = progression.max_depth >= OUTER_RADIUS - FPProgression.FINAL_TRADE_MARGIN
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
	# buying happens in front of the mirror only (decision 0014). The body and
	# the view hold still while the screen is open, so this is asked once.
	mirror.can_buy_here = at_mirror()
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

# --- Canary pull: lie prone, fish out one bird, tuck into existing briefs ---
const CANARY_PULL_TIME := FPCanaryPull.DURATION
## -1 = not pulling; otherwise seconds into the pull.
var canary_pull_t: float = -1.0
var interact_ring: Control
## W27 wordless danger (bruised hands, crush squeeze); fp_danger_show.gd.
var danger_show = null
var _pull_eye_y: float = 0.0
var canary_pull: FPCanaryPull

func is_pulling_canary() -> bool:
	return canary_pull_t >= 0.0

func begin_canary_pull() -> bool:
	if has_canary or is_pulling_canary():
		return false
	canary_pull_t = 0.0
	_pull_eye_y = player.camera_pivot.position.y
	canary_pull = FPCanaryPull.new(self)
	return true

## Physical prone capsule, one searching arm, then a held bird and briefs tuck.
func _step_canary_pull(delta: float) -> void:
	if not is_pulling_canary():
		return
	canary_pull_t += delta
	if canary_pull.step(delta):
		canary_pull_t = -1.0
		canary_pull = null
		mirror_view._sync_body_posture()

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
	# coming back out the eye is not where it aims: F in that moment goes back in
	if hand_motions.kind == "vent_lean":
		return "vent"
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
	var order := ["", "compass", "knife", "blender", "big_saw", "spray_cheap", "spray_deep", "canary_feed", "barrier"]
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
		# a mist out of the hand, and melted flesh spitting where it lands
		var look: Vector3 = player.get_look_ray()[1]
		var nozzle: Vector3 = player.camera.global_position + look * 0.35 + player.camera.global_basis.y * -0.12
		gore.burst(nozzle, look, 0, 16, Color(0.78, 0.86, 0.62), 3.0, 0.18)
		gore.burst(hit.position - look * 0.05, -look, 0, 8, Color(0.74, 0.46, 0.3), 0.9, 0.8)
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

## The spray can left in a rest point (closest one in reach). With three cans
## already on the belt the hand touches it and it stays (B10 cap).
func nearest_rest_can(dist: float) -> Node3D:
	var best: Node3D = null
	var bd := dist
	for c in rest_cans:
		if not c.visible:
			continue
		var d := c.global_position.distance_to(player.camera.global_position)
		if d < bd:
			bd = d
			best = c
	return best

func take_rest_can() -> bool:
	var c := nearest_rest_can(1.4)
	if c == null:
		return false
	var kind := String(c.get_meta("loot"))
	if not progression.can_hold(kind):
		emit_signal("belt_refused")
		return false
	hand_motions.play_take(c.global_position, kind)
	if not progression.grant_item(kind):
		emit_signal("belt_refused")
		return false
	c.visible = false
	looted_rest_cans.append(int(c.get_meta("rest")))
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
	# no flesh pressing into the body: it cannot be boxed in (the full escape
	# search below cost ms every frame while simply standing on flesh)
	if _body_clearance.clearly_free(player, terrain):
		_body_relief_needed = false
		return false
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
	_discard_hold_t = -1.0 # a discard being held dies with the body
	has_canary = false
	canary.reset_trail()
	blender_charge = 0.0
	death_drop = _new_death_drop()
	death_drop.drop(at, payload)
	death_drop.visible = true
	death_drops.append(death_drop)
	hazard.reset()
	_hazards.clear()
	_crush_t = 0.0
	deaths += 1
	player.global_position = START_POS
	player.velocity = Vector3.ZERO
	wake_lids.set_eyes(progression.all_mutations(), restroom_field_angle())
	wake_lids.play()
	died.emit(cause)
	# 형님 2026-09-30: same autosave gap as end_settlement -- a death is a
	# real checkpoint (deaths count, tank/canary state reset) worth keeping
	# even if nothing is saved again before the next crash/close.
	save_to_disk()

## A body: the dropped belongings, a curled skin-coloured lump, and its
## stake marker (FDKDeathDrop). One per death.
func _new_death_drop() -> FDKDeathDrop:
	var d := FDKDeathDrop.new()
	d.name = "DeathDrop%d" % deaths
	add_child(d)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var cap := CapsuleMesh.new()
	cap.radius = 0.17
	cap.height = 1.05
	cap.radial_segments = 8
	cap.rings = 3
	body.mesh = cap
	body.rotation_degrees = Vector3(0, 0, 90)
	body.position = Vector3(0, -0.1, 0)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.78, 0.6, 0.52)
	skin.roughness = 0.6
	body.material_override = skin
	d.add_child(body)
	return d

## Moving flesh keeps pushing a buried body with no cap; its marker stays.
## Reaching a body takes back what fits; the rest stays on it.
func _step_death_drop(delta: float) -> void:
	var gone: Array[FDKDeathDrop] = []
	for d in death_drops:
		if not d.active:
			gone.append(d)
			continue
		if terrain.density_at(d.current_position) >= 0.5:
			var away := (d.current_position - RESTROOM_CENTER).normalized()
			var push := away.cross(Vector3.UP)
			if push.length() < 0.1:
				push = Vector3.RIGHT
			d.carry_along(push.normalized() * 0.04 * delta)
		var near := player.global_position.distance_to(d.current_position) <= 1.2
		if d.has_meta("full_until_away"):
			if not near:
				d.remove_meta("full_until_away")
			continue
		var got := d.try_recover(player.global_position)
		if got.is_empty():
			continue
		stomach.add_flesh(progression.restore_death_payload(got))
		if FPProgression.payload_empty(got):
			gone.append(d)
		else:
			# hands and belt are full: the rest stays on the body
			d.drop(d.last_known_position, got)
			d.current_position = d.position
			d.set_meta("full_until_away", true)
	for d in gone:
		death_drops.erase(d)
		if d != death_drop:
			d.queue_free()
		else:
			d.visible = false
	_drop_light_t -= delta
	if _drop_light_t <= 0.0:
		_drop_light_t = 0.5
		_light_nearest_markers()

## Only the nearest few marker lamps cast light; the rest just glow.
func _light_nearest_markers() -> void:
	var sorted := death_drops.duplicate()
	var p := player.global_position
	sorted.sort_custom(func(a, b): return a.last_known_position.distance_squared_to(p) < b.last_known_position.distance_squared_to(p))
	for i in range(sorted.size()):
		var marker: Node3D = sorted[i].marker
		if marker == null:
			continue
		for c in marker.get_children():
			if c is OmniLight3D:
				(c as OmniLight3D).visible = i < DROP_LIT_MARKERS

# --- ending ---------------------------------------------------------------------------

## Seconds from the tear that opens the outside to the ending: the hole is
## published and its strands, recoil and blood (show_tear) have played, so the
## white flash reads as the light coming in through that hole.
const ENDING_BITE_DELAY := 0.35
## How far (in cells) from the torn cell the open space is followed to the
## outside: the tear's own extra cells (big saw, M07/M14) are inside this.
const ENDING_BITE_SPAN := 2
## Counts down after a tear opened the outside; negative while idle. Not
## saved: a reload finds the real hole again (the next tear, or walking out).
var _ending_bite_t: float = -1.0

## True when the tear at world_pos (a torn cell's centre) left a real hole to
## the outside: an emptied corner of that cell joins, through emptied corners
## no more than ENDING_BITE_SPAN cells away, a corner past the outer shell
## (where the generator has no flesh at all). A torn cell that still has a
## layer of flesh behind it is not an opening, however near the edge it is.
## Reads live density only.
func tear_opens_outside(world_pos: Vector3) -> bool:
	var cs: float = terrain_config.cell_size
	var span := float(ENDING_BITE_SPAN + 2) * cs * 1.8
	if world_pos.distance_to(RESTROOM_CENTER) < OUTER_RADIUS - span:
		return false
	var iso: float = terrain_config.iso_level
	if terrain.density_at(world_pos) >= iso:
		return false # the cell itself still holds flesh: no hole here
	var cell := Vector3i(floori(world_pos.x / cs), floori(world_pos.y / cs), floori(world_pos.z / cs))
	var lo := cell - Vector3i.ONE * ENDING_BITE_SPAN
	var hi := cell + Vector3i.ONE * (ENDING_BITE_SPAN + 1)
	var seen := {}
	var queue: Array[Vector3i] = []
	for dz in range(2):
		for dy in range(2):
			for dx in range(2):
				var g := cell + Vector3i(dx, dy, dz)
				if terrain.corner_density_global(g) < iso:
					seen[g] = true
					queue.append(g)
	var steps: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	while not queue.is_empty():
		var g: Vector3i = queue.pop_back()
		if (Vector3(g) * cs).distance_to(RESTROOM_CENTER) >= OUTER_RADIUS:
			return true
		for s in steps:
			var n: Vector3i = g + s
			if seen.has(n) or n.x < lo.x or n.y < lo.y or n.z < lo.z or n.x > hi.x or n.y > hi.y or n.z > hi.z:
				continue
			seen[n] = true
			if terrain.corner_density_global(n) < iso:
				queue.append(n)
	return false

## The last bite: a tear that opened the outside starts the ending
## ENDING_BITE_DELAY later. Nothing covers the hole in between.
func _step_ending_bite(delta: float) -> void:
	if _ending_bite_t < 0.0:
		return
	_ending_bite_t -= delta
	if _ending_bite_t <= 0.0:
		_ending_bite_t = -1.0
		reach_ending()

func reach_ending() -> void:
	if ended:
		return
	ended = true
	_ending_bite_t = -1.0
	chewer.stop()
	player.set_physics_process(false)
	ending.start(1 + (1 if progression.codex_complete() else 0))
	ending_reached.emit()

# --- eating ---------------------------------------------------------------------------

func _on_cell_torn(world_pos: Vector3) -> void:
	var shell := shell_at(world_pos)
	if _assist_cell != Vector3.INF and cell_center(world_pos).is_equal_approx(_assist_cell):
		assist_tears += 1
		chew_assisted.emit(_assist_cell)
		_assist_drop()
	_chew_target = Vector3.INF
	_chew_contact = Vector3.INF
	# the chewer already put chewer.last_units in the stomach unless carrying
	if carry_mode and progression.equipped() == "big_saw":
		swallow_torn(shell, chewer.last_units) # a saw stroke cannot be held (06-tools.md)
	elif carry_mode:
		add_carried(shell, chewer.last_units)
	else:
		progression.on_flesh_eaten(shell, chewer.last_units)
		show_swallow(chewer.last_units)
	tear_effects(world_pos)

## The centre of the terrain cell holding p: where a tear of that cell lands
## (the chewer reports its cell this way; the M22 alien hand snaps to it).
func cell_center(p: Vector3) -> Vector3:
	var cs: float = terrain_config.cell_size
	return (Vector3(floorf(p.x / cs), floorf(p.y / cs), floorf(p.z / cs)) + Vector3(0.5, 0.5, 0.5)) * cs

## Everything one real tear does to the game past its own cell's dig and
## flesh, the same for the chewer (_on_cell_torn) and the M22 alien hand
## (fp_mutation_apply.alien_tear), called once per tear: the dug count, the
## tool's and mutations' extra cells (big saw, tear_cells), the published hole
## and what it shows, the nerve it touches and the nerve that grows in after.
## The caller has already removed the cell's density and booked its flesh.
func tear_effects(world_pos: Vector3) -> void:
	var shell := shell_at(world_pos)
	excavated_cells += 1
	tissue_tools.on_cell_torn(world_pos)
	terrain.queue_visible_tear(world_pos)
	show_tear(world_pos)
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
	if mutation_apply != null:
		mutation_apply.on_torn(world_pos)
	# after the tool's and mutations' extra cells: the bite that opens the
	# outside ends the game (the chewer's, the saw's, the M22 hand's alike)
	if not ended and _ending_bite_t < 0.0 and tear_opens_outside(world_pos):
		_ending_bite_t = ENDING_BITE_DELAY

# --- save/load ------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"excavated_cells": excavated_cells,
		"terrain": terrain.serialize(),
		"stomach": stomach.serialize(),
		"progression": progression.serialize(),
		"barriers": barrier_field.serialize(),
		# every body still out there, plus the newest one under the old key
		"death_drops": death_drops.map(func(d): return d.serialize()),
		"death_drop": death_drop.serialize(),
		"hazard": hazard.serialize(),
		"carried_flesh": carried_flesh,
		"carried_units": carried_units.duplicate(),
		"carried_units_are_flesh": true,
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
		"looted_rest_cans": looted_rest_cans.duplicate(),
		"lever_settled": lever_settled,
		"player_position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"drawings": vent.drawings.duplicate(),
		"vent_progress": vent.serialize_progress(),
		"biome_visits": biome_life.serialize() if biome_life != null else {},
	}

func deserialize(data: Dictionary) -> void:
	hand_motions.stop_vent_look()
	_restore_frame_camera()
	_terrain_eye_delta = Vector3.ZERO
	_terrain_eye_pose = Vector3.ZERO
	_reset_glare()
	var v := int(data.get("version", 1))
	if data.has("terrain"):
		terrain.deserialize(data["terrain"])
		if v < 5:
			_migrate_restroom_terrain()
		_clear_vent_duct()
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
	for d in death_drops:
		if d != death_drop:
			d.queue_free()
	death_drops.clear()
	if is_instance_valid(death_drop):
		death_drop.queue_free()
	# the newest body (old saves had only this one), then every other body
	var newest: Dictionary = data.get("death_drop", {})
	death_drop = _new_death_drop()
	if not newest.is_empty():
		death_drop.deserialize(newest)
	death_drop.visible = death_drop.active
	var drops: Array = data.get("death_drops", [newest] if death_drop.active else [])
	for dd in drops:
		if dd == newest and death_drop.active and not death_drops.has(death_drop):
			death_drops.append(death_drop)
			continue
		var d := _new_death_drop()
		d.deserialize(dd)
		d.visible = d.active
		if d.active:
			death_drops.append(d)
		else:
			d.queue_free()
	if data.has("hazard"):
		hazard.deserialize(data["hazard"])
	carried_flesh = float(data.get("carried_flesh", 0.0))
	carried_units = (data.get("carried_units", {}) as Dictionary).duplicate()
	if not bool(data.get("carried_units_are_flesh", false)):
		# older saves counted cells in the hands
		for k in carried_units.keys():
			carried_units[k] = float(carried_units[k]) * stomach_config.flesh_per_cell
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
	_ending_bite_t = -1.0
	if bool(data.get("opening_done", v < 3)):
		finish_opening()
		opening_done = true
	taken_tumor_spots = (data.get("taken_tumor_spots", []) as Array).duplicate()
	for t in tumor_nodes:
		t.visible = not taken_tumor_spots.has(int(t.get_meta("spot")))
	looted_rest_cans = (data.get("looted_rest_cans", []) as Array).duplicate()
	for c in rest_cans:
		c.visible = not looted_rest_cans.has(int(c.get_meta("rest")))
	_tank_teeth_shown = -1
	var pos: Array = data.get("player_position", [])
	if pos.size() == 3:
		player.global_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	if v < 5 and terrain.density_at(player.global_position) >= terrain_config.iso_level:
		player.global_position = START_POS
	# a save from before the toilet moved to the back wall, standing where it is now
	if restroom.toilet_blocks(player.global_position):
		player.global_position = START_POS
	_restore_drawings(data.get("drawings", []) as Array)
	vent.restore_progress(data.get("vent_progress", {}), progression.has_belt)
	if biome_life != null:
		biome_life.deserialize(data.get("biome_visits", {}))
		biome_life.snap()
	# older saves: anyone who has met the being has flushed teeth before
	lever_settled = bool(data.get("lever_settled", vent._paid_ever or vent._met or progression.has_belt))

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
## Saves from before the wider duct space still hold flesh corners where the
## duct now is (above the ceiling, out of reach). Lower only those corners to
## the generator's density; the caller remeshes after loading.
func _clear_vent_duct() -> void:
	var n := terrain_config.chunk_size + 1
	var cs := terrain_config.cell_size
	var area := AABB(FPRestroom.VENT_CENTER + Vector3(-VENT_DUCT_HALF, -0.04, -VENT_DUCT_HALF),
		Vector3(VENT_DUCT_HALF * 2.0, VENT_DUCT_TOP + 0.04, VENT_DUCT_HALF * 2.0)).grow(cs)
	for chunk in terrain._chunks.values():
		if not AABB(chunk.position, Vector3.ONE * cs * (n - 1)).intersects(area):
			continue
		var touched := false
		for z in range(n):
			for y in range(n):
				for x in range(n):
					var p: Vector3 = chunk.position + Vector3(x, y, z) * cs
					if not in_vent_duct(p):
						continue
					var index: int = chunk._corner_index(x, y, z)
					if chunk._density[index] > 0.0:
						chunk._density[index] = 0.0
						touched = true
		if touched:
			chunk._regen_scan = true
			chunk._dirty = true

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
