extends SceneTree

## Session C captures (mirror, mutations, tumors, stomach forms). Run WINDOWED
## with the movie writer, one shot per run:
##   Godot_console --path game --windowed --resolution 1280x720
##     --write-movie <dir>/f.png --fixed-fps 10 --quit-after <N>
##     --script res://tools/mutation_capture.gd -- <shot>
## Shots: mirror_shimmer, mirror_ghost, mirror_red, hand_before, hand_after,
## codex, looks (one mutation per 4 frames, order in LOOK_ORDER, from frame 8),
## stomach (forms per 6 frames: none, M01, M02, M30, all; from frame 8).

const LOOK_ORDER := ["M01", "M02", "M03", "M04", "M05", "M06", "M07", "M08", "M09", "M10", "M12", "M13", "M14", "M15", "M16", "M17", "M18", "M19", "M20", "M21", "M22", "M23", "M24", "M25", "M26", "M27", "M28", "M29", "M30", "T1", "T2", "T3", "T4", "T5", "T6", "T7"]
const STOMACH_ORDER := [[], ["M01"], ["M02"], ["M30"], ["M01", "M02", "M30"]]

var _main: Node3D
var _shot := "mirror_shimmer"
var _frame := 0
var _extra_ids: Array = []  ## clean/ghost_*: mutations already owned (args after the shot)

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_shot = args[0]
		for k in range(1, args.size()):
			_extra_ids.append(args[k])
	_main = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)

func _pose(pos: Vector3, yaw: float, pitch: float = 0.0) -> void:
	var p = _main.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.set("_yaw", yaw)
	p.set("_pitch", pitch)
	p.rotation.y = yaw
	p.camera_pivot.rotation.x = pitch

func _setup() -> void:
	var m = _main
	var prog: FPProgression = m.progression
	m.finish_opening()
	m.restroom.set_door_open(false, true)
	match _shot:
		"mirror_shimmer", "mirror_ghost", "mirror_red", "looks":
			_pose(Vector3(-0.9, 0.95, -0.35), PI * 0.5, 0.0)
			if _shot == "mirror_ghost":
				prog.mutation_tree.add_points("core", 20)
				prog.mutation_tree.add_points("common", 30)
			m.open_mirror()
			if _shot == "mirror_ghost":
				m.mirror.focus_part("right_hand")
				while m.mirror.candidate() != "M10":
					m.mirror.select_candidate(int(m.mirror._cand.get("right_hand", 0)) + 1)
			elif _shot == "mirror_red":
				m.mirror.focus_part("face")
		"clean", "ghost_belly", "ghost_face":
			_pose(Vector3(-0.9, 0.95, -0.35), PI * 0.5, 0.0)
			prog.mutation_tree.add_points("core", 20)
			prog.mutation_tree.add_points("common", 30)
			for id in _extra_ids:
				prog.mutation_tree._purchased[id] = true
			m.open_mirror()
		"lookdown":
			_pose(Vector3(0.0, 0.95, 0.4), 0.0, deg_to_rad(-80.0 if _extra_ids.is_empty() else float(_extra_ids[0])))
		"hand_before", "hand_after":
			if _shot == "hand_after":
				prog.mutation_tree._purchased["M10"] = true
			_pose(Vector3(0.0, 0.95, 0.4), PI, deg_to_rad(-10.0))
		"codex":
			for k in FPProgression.TUMOR_KINDS:
				prog.tumors._codex[k] = true
			_pose(Vector3(0.1, 0.95, 0.3), -PI * 0.5, deg_to_rad(12.0))
		"stomach":
			_pose(Vector3(0.0, 0.95, 0.4), PI, deg_to_rad(-6.0))
	m.apply_atmosphere_now()

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_setup()
	var m = _main
	if _frame > 2:
		match _shot:
			"mirror_ghost":
				if m.mirror.current_part() != "right_hand":
					m.mirror.focus_part("right_hand")
				while m.mirror.candidate() != "M10":
					m.mirror.select_candidate(int(m.mirror._cand.get("right_hand", 0)) + 1)
			"mirror_red":
				if m.mirror.current_part() != "face":
					m.mirror.focus_part("face")
				if _frame % 7 == 3:
					m.mirror.buy_current()
			"clean":
				m.mirror._clear_ghost()
				for part in FPProgression.PARTS:
					m.mirror.body.set_shimmer(part, false)
			"ghost_belly", "ghost_face":
				var gp := "belly" if _shot == "ghost_belly" else "face"
				if m.mirror.current_part() != gp:
					m.mirror.focus_part(gp)
				for part in FPProgression.PARTS:
					m.mirror.body.set_shimmer(part, false)
			"lookdown":
				_pose(Vector3(0.0, 0.95, 0.4), 0.0, deg_to_rad(-80.0 if _extra_ids.is_empty() else float(_extra_ids[0])))
			"hand_before", "hand_after":
				_pose(Vector3(0.0, 0.95, 0.4), PI, deg_to_rad(-10.0))
			"codex":
				_pose(Vector3(0.1, 0.95, 0.3), -PI * 0.5, deg_to_rad(12.0))
			"stomach":
				_pose(Vector3(0.0, 0.95, 0.4), PI, deg_to_rad(-6.0))
				var i := clampi((_frame - 8) / 6, 0, STOMACH_ORDER.size() - 1) if _frame >= 8 else 0
				m.stomach_view.set_forms(STOMACH_ORDER[i])
				m.stomach.fill = m.stomach_config.capacity + m.stomach_config.overfill_capacity * 0.85
				m.stomach_view.set_state(m.stomach.fill_ratio(), 0.85)
				m.stomach_view.snap()
			"looks":
				if _frame >= 8:
					var i := clampi((_frame - 8) / 4, 0, LOOK_ORDER.size() - 1)
					var id: String = LOOK_ORDER[i]
					var b: FPMirrorBody = m.mirror.body
					m.mirror._clear_ghost()
					if b.applied != [id]:
						b.apply([id], 0)
						for part in FPProgression.PARTS:
							b.set_shimmer(part, false)
	return false
