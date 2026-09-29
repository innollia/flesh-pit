class_name FPEnding
extends CanvasLayer

## Ending signal (docs/spec/00-overview.md): breaking through the outermost shell.
## A white flash, then the player lands on an empty city street in bright
## daylight while the building-sized meat sphere rolls away down it
## (main/art fp_ending_street), then a credits card. `voice_layers` tells
## the audio layer how many song voices to play.

signal finished

var active: bool = false
var voice_layers: int = 1
var _t: float = 0.0
var _fade: ColorRect
var _credits: Label
## 3D ending set, built on start() far below the flesh world.
var street: Node3D
var street_camera: Camera3D
const STREET_AT := Vector3(0, -3000, 0)
const REVEAL_AT := 1.2

func _ready() -> void:
	layer = 20
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(1, 1, 1, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_credits = Label.new()
	_credits.set_anchors_preset(Control.PRESET_CENTER)
	_credits.text = "flesh-pit"
	_credits.modulate = Color(0.2, 0.2, 0.2, 0)
	add_child(_credits)
	visible = false

func start(p_voice_layers: int) -> void:
	if active:
		return
	active = true
	voice_layers = p_voice_layers
	_t = 0.0
	visible = true
	_build_street()

func _build_street() -> void:
	if street != null:
		return
	street = Node3D.new()
	street.name = "EndingSet"
	add_child(street)
	street.position = STREET_AT
	var art: Node3D = (load("res://main/art/fp_ending_street.tscn") as PackedScene).instantiate()
	art.name = "Street"
	street.add_child(art)
	art.call("set_roll", 0.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.96, 0.88)
	street.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.78, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.8
	street_camera = Camera3D.new()
	street_camera.name = "StreetCamera"
	street_camera.environment = env
	street_camera.fov = 65.0
	street_camera.far = 600.0
	street.add_child(street_camera)
	_pose_camera(0.0)

## Lands from a short drop onto the road, then looks up the street at the
## sphere rolling away.
func _pose_camera(k: float) -> void:
	if street_camera == null:
		return
	var e := 1.0 - pow(1.0 - clampf(k, 0.0, 1.0), 3.0)
	# After landing the camera slowly pulls back up the street (W41) while
	# the ball rolls away, so the whole ball and the blocks stay in frame.
	var back := clampf((k - 1.0) / 5.0, 0.0, 1.0)
	back = back * back * (3.0 - 2.0 * back)
	street_camera.position = Vector3(0.4, lerpf(7.0, 1.3, e) + back * 5.0, 2.0 + back * 34.0)
	street_camera.look_at(street.global_position + Vector3(0, lerpf(-2.0, 34.0, e), -110.0), Vector3.UP)

func tick(delta: float) -> void:
	if not active:
		return
	_t += delta
	if _t < REVEAL_AT:
		_fade.color.a = clampf(_t / REVEAL_AT, 0.0, 1.0)
	else:
		if street_camera != null and not street_camera.current:
			street_camera.current = true
			(street.get_node("Street") as Node3D).call("play_roll_away", 14.0)
		_fade.color.a = clampf(1.0 - (_t - REVEAL_AT) / 1.6, 0.0, 1.0)
		_pose_camera((_t - REVEAL_AT) / 1.4)
	_credits.modulate.a = clampf((_t - 5.0) / 1.5, 0.0, 1.0)
	if _t >= 8.0 and _t - delta < 8.0:
		finished.emit()
