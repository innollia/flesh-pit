extends SceneTree

## Press-deform capture (movie writer): digs the reference tunnel, faces the
## +X flesh wall and holds a chew press so any seam between faces shows.
##   --write-movie <dir>/f.png --fixed-fps 10 --quit-after 30 --script res://tools/press_capture.gd -- <amount>
var _main: Node3D
var _frame := 0
var _amount := 0.8
const CENTER := Vector3(0.95, 1.3, 4.2)

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_amount = float(args[0])
	_main = (load("res://main/scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(_main)

func _process(_d: float) -> bool:
	_frame += 1
	var m = _main
	if _frame == 2:
		m.restroom.set_door_open(true, true)
		var t = m.terrain
		for zi in range(11):
			for xi in range(-1, 2):
				for yi in range(0, 4):
					t.dig_at(Vector3(xi * 0.5 + 0.25, yi * 0.5 + 0.25, 1.9 + zi * 0.5), 1.0)
		t.remesh_all()
		var p = m.player
		p.global_position = Vector3(0.0, 0.95, 4.2)
		p.set("_yaw", -PI * 0.5); p.rotation.y = -PI * 0.5
		p.set("_pitch", deg_to_rad(-6.0)); p.camera_pivot.rotation.x = deg_to_rad(-6.0)
		m.apply_atmosphere_now()
	if _frame >= 3:
		m.terrain.set_press(CENTER, Vector3(-1, 0, 0), _amount * clampf(float(_frame - 3) / 10.0, 0.0, 1.0))
	return false