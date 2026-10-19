class_name FPVomitButton
extends Control

## The wordless on-screen vomit button (docs/spec/01-body-eating.md), shown
## once the player has overfilled past a threshold: a puckered mouth at the
## end of the stomach gauge (fp_stomach_hud.gd) that gags open, bile running
## out (fp_vomit_mouth.gdshader). Click it (or press fp_vomit) to vomit.

signal pressed

const AT := Vector2(259, -68)
const SIZE := 62.0

var shown: bool = false
var _t: float = 0.0
var _alpha: float = 0.0
var _open: float = 0.0
var _hover := false
var _face: ColorRect
var _mat: ShaderMaterial

func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(SIZE, SIZE)
	_face = ColorRect.new()
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://main/scripts/fp_vomit_mouth.gdshader")
	_mat.set_shader_parameter("rect_size", Vector2(SIZE, SIZE))
	_face.material = _mat
	add_child(_face)
	mouse_entered.connect(func(): _hover = true)
	mouse_exited.connect(func(): _hover = false)
	_place()

func _place() -> void:
	var vp := get_viewport_rect().size
	var k := FPStomachHUD.ui_scale(vp.y)
	scale = Vector2(k, k)
	position = Vector2(AT.x * k, vp.y + AT.y * k)

func _process(delta: float) -> void:
	_t += delta
	_alpha = move_toward(_alpha, 1.0 if shown else 0.0, delta * 4.0)
	_open = move_toward(_open, 1.0 if shown else 0.0, delta * 2.5)
	visible = _alpha > 0.01
	if not visible:
		return
	_place()
	_mat.set_shader_parameter("open", _open)
	_mat.set_shader_parameter("alpha", _alpha)
	_mat.set_shader_parameter("time", _t)
	_mat.set_shader_parameter("hover", 1.0 if _hover and shown else 0.0)

func _gui_input(event: InputEvent) -> void:
	if shown and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()
