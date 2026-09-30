extends SceneTree

## Session A (restroom look) captures: W01 W02 W07 W09 W13 W14. One windowed
## run walks through every shot, HOLD frames each, and writes the frame range
## of each shot into shots.txt next to the frames:
##   Godot_console --path game --windowed --resolution 1280x720
##     --write-movie captures/restroom_a/f.png --fixed-fps 10
##     --quit-after <N> --script res://tools/restroom_capture.gd
## The last frame of each shot's range is the one to judge.

const HOLD := 14
const SHOTS := [
	"open_black", "open_rise", "open_stand",
	"seat_look_up", "hole_standing", "hole_crouching",
	"vent_eyes", "vent_subtitle",
	"hair_0", "hair_5", "hair_20",
	"blood_before", "blood_after",
	"door_spill", "glare", "room_wide",
]

var _main: Node3D
var _frame := 0
var _shot_i := -1
var _log: Array[String] = []
var _open_t := -1.0

func _init() -> void:
	_main = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)

func _eye_offset() -> float:
	return _main.player.camera.global_position.y - _main.player.global_position.y

func _pose(pos: Vector3, yaw: float, pitch: float) -> void:
	var p = _main.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.set("_yaw", yaw)
	p.set("_pitch", pitch)
	p.rotation.y = yaw
	p.camera_pivot.rotation.x = pitch

func _look(pos: Vector3, target: Vector3) -> void:
	var eye: Vector3 = pos + Vector3(0, _eye_offset(), 0)
	var d := (target - eye).normalized()
	_pose(pos, atan2(-d.x, -d.z), asin(clampf(d.y, -1.0, 1.0)))

func _crouch(on: bool) -> void:
	var p = _main.player
	p.camera_pivot.position.y = p.eye_pivot_y(on)

func _dig_tunnel() -> void:
	var t = _main.terrain
	for zi in range(9):
		for xi in range(-1, 2):
			for yi in range(0, 4):
				t.dig_at(Vector3(xi * 0.5 + 0.25, yi * 0.5 + 0.25, 1.9 + zi * 0.5), 1.0)
	t.remesh_all()

func _hairs(n_common: int, n_core: int) -> void:
	var prog: FPProgression = _main.progression
	for pool in [FPProgression.COMMON, "core", "mantle", "surface"]:
		prog.mutation_tree.add_points(pool, -prog.hairs(pool))
	prog.mutation_tree.add_points(FPProgression.COMMON, n_common)
	prog.mutation_tree.add_points("core", n_core)

## Close camera on the left forearm hairs (the first-person view keeps the
## forearm below the frame; this is how the arm reads when raised).
var _arm_cam: Camera3D
func _arm_view() -> void:
	_pose(Vector3(-0.2, 0.95, 0.4), PI * 0.5, 0.0)
	var hair: Node3D = _main.art_hookup.arm_hair
	if _arm_cam == null:
		_arm_cam = Camera3D.new()
		_arm_cam.fov = 50.0
		_arm_cam.near = 0.01
		_main.add_child(_arm_cam)
	_arm_cam.global_position = hair.to_global(Vector3(0.2, 0.17, -0.02))
	_arm_cam.look_at(hair.to_global(Vector3(0, 0.0, -0.14)), Vector3.UP)
	_arm_cam.make_current()

func _setup(shot: String) -> void:
	var m = _main
	var r: FPRestroom = m.restroom
	_crouch(false)
	if _arm_cam != null and not shot.begins_with("hair_"):
		_main.player.camera.make_current()
	m.subtitles.show_text("", 0.01)
	match shot:
		"open_black", "open_rise", "open_stand":
			var t: float = {"open_black": 0.5, "open_rise": FPOpening.BLACK_TIME + FPOpening.FADE_TIME + 0.7, "open_stand": FPOpening.TOTAL - 0.02}[shot]
			_open_t = t
			m.set("_opening_t", t)
			m.apply_opening_at(t)
		"seat_look_up":
			_open_t = -1.0
			m.finish_opening()
			r.set_door_open(false, true)
			_pose(m.SEAT_POS, PI, deg_to_rad(45.0))
		"hole_standing":
			r.set_door_open(false, true)
			_look(Vector3(-1.2, 0.95, -0.75), FPRestroom.CANARY_HOLE + Vector3(0, 0.14, 0))
		"hole_crouching":
			_crouch(true)
			_look(Vector3(-1.2, 0.1, -0.75), FPRestroom.CANARY_HOLE + Vector3(0, 0.14, 0))
		"vent_eyes":
			m.vent.open(12)
			if m.vent.art != null:
				m.vent.art.call("set_open", 1.0)
				m.vent.art.call("set_eyes", true)
			_look(Vector3(0.7, 0.95, 0.1), m.vent.global_position + Vector3(0, 0.1, 0))
		"vent_subtitle":
			m.subtitles.show_now(String(FPSubtitles.LINES["vent_bong_frantic"]))
		"hair_0":
			_hairs(0, 0)
			_arm_view()
		"hair_5":
			_hairs(2, 3)
			_arm_view()
		"hair_20":
			_hairs(8, 12)
			_arm_view()
		"blood_before":
			_hairs(0, 0)
			m.hand_blood = 0.9
			print("BLOODDBG attach=", FPHandBlood.attach(m.hands_rig, m.hand_blood_mat), " vis=", m.hands_rig.visible)
			_pose(Vector3(-1.55, 0.95, -0.35), PI * 0.5, deg_to_rad(-30.0))
		"blood_after":
			m.wash_hands()
		"door_spill":
			r.set_door_open(true, true)
			_dig_tunnel()
			_pose(Vector3(0.0, 0.95, 4.6), 0.0, deg_to_rad(-4.0))
		"room_wide":
			r.set_door_open(false, true)
			_look(Vector3(-1.6, 0.95, 1.2), Vector3(1.2, 0.9, -0.4))
		"glare":
			m.set("_was_inside", false)
			_pose(Vector3(0.0, 0.95, 0.9), PI, 0.0)
	m.apply_atmosphere_now()
	if shot == "glare":
		# one frame of the blinding flash, not the settled light
		m.set("_was_inside", false)
		m.call("_update_atmosphere", 0.05)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	var i := (_frame - 3) / HOLD
	if i != _shot_i:
		_shot_i = i
		if i >= SHOTS.size():
			_write_log()
			quit(0)
			return true
		_setup(SHOTS[i])
		_log.append("%s %d %d" % [SHOTS[i], _frame, _frame + HOLD - 1])
	var shot: String = SHOTS[i]
	if shot.begins_with("vent_") and "absent_left" in _main.vent:
		_main.vent.set("absent_left", 0.0)
	if _open_t >= 0.0:
		_main.set("_opening_t", _open_t)
	else:
		_main.player.set_physics_process(false)
	if shot.begins_with("open_") or shot == "seat_look_up" or shot.begins_with("hole_") or shot.begins_with("vent_") or shot.begins_with("hair_") or shot.begins_with("blood_"):
		_main.player.velocity = Vector3.ZERO
	if shot == "glare" and _frame == 3 + i * HOLD + HOLD - 2:
		_main.set("_flash", 1.0)
	return false

func _write_log() -> void:
	var f := FileAccess.open("res://captures/restroom_a/shots.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_log) + "\n")
