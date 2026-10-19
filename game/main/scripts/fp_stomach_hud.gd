class_name FPStomachHUD
extends Control

## Stomach % and gauge, bottom left (spec 01 위장 UI, a requested exception
## to the no-HUD rule): a length of gut filling with chewed flesh
## (fp_stomach_gut.gdshader), the fill in the menu font above it, and past
## capacity the vomit key beside the mouth at its end (vomit_button.gd).
## Layout in 720-high units, scaled to the window.

const GUT := Rect2(18, -60, 244, 46)
const MOUTH_W := 62.0

var main: Node3D
var gut: ColorRect
var _mat: ShaderMaterial
var _time := 0.0
var _shown_fill := 0.0
var _shown_over := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gut = ColorRect.new()
	gut.name = "Gut"
	gut.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gut.size = GUT.size
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://main/scripts/fp_stomach_gut.gdshader")
	_mat.set_shader_parameter("rect_size", GUT.size)
	gut.material = _mat
	add_child(gut)

static func ui_scale(height: float) -> float:
	return maxf(height / 720.0, 0.65)

func _process(delta: float) -> void:
	visible = main != null and not main.title_screen.is_open() and not main.settings_menu.is_open() and not main.ended
	if not visible:
		return
	_time += delta
	var k := 1.0 - exp(-delta * 6.0)
	_shown_fill = lerpf(_shown_fill, clampf(main.stomach.fill_ratio(), 0.0, 1.0), k)
	_shown_over = lerpf(_shown_over, main.stomach.overfill_ratio(), k)
	var s := ui_scale(size.y)
	gut.scale = Vector2(s, s)
	gut.position = Vector2(GUT.position.x, size.y / s + GUT.position.y) * s
	_mat.set_shader_parameter("fill", _shown_fill)
	_mat.set_shader_parameter("over", _shown_over)
	_mat.set_shader_parameter("time", _time)
	queue_redraw()

func _draw() -> void:
	if main == null:
		return
	var s := ui_scale(size.y)
	var h := size.y / s
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * s)
	var ratio: float = main.stomach.fill_ratio()
	var over := ratio >= 1.0
	var at := Vector2(GUT.position.x + 8, h + GUT.position.y - 2)
	FPMenuKit.draw_ink(self, at, "위장", 17, Color(0.86, 0.74, 0.66, 0.9))
	var num := "%d%%" % roundi(ratio * 100.0)
	var jitter := Vector2.ZERO
	if over:
		# a strained, shaking number past capacity
		var t := floorf(_time * 20.0)
		jitter = Vector2(sin(t * 12.9898), cos(t * 78.233)) * (0.6 + 1.6 * _shown_over)
	var num_color := Color(1.0, 0.36, 0.26) if over else Color(1.0, 0.93, 0.84)
	FPMenuKit.draw_ink(self, at + Vector2(42, 1) + jitter, num, 25, num_color)
	if over:
		var key := FPKeybindMenu.key_of("fp_vomit")
		var mouth_open: bool = main.vomit_button != null and main.vomit_button.shown
		var x := GUT.end.x + (MOUTH_W + 4.0 if mouth_open else 10.0)
		var cy := h + GUT.position.y + GUT.size.y * 0.5
		var pulse := 0.75 + 0.25 * sin(_time * 6.0)
		var w := FPMenuKit.draw_key(self, Vector2(x + 14, cy), "V" if key == "" else key, 1.0, 16)
		FPMenuKit.draw_ink(self, Vector2(x + 14 + w * 0.5 + 8, cy + 7), "토하기", 19, Color(1.0, 0.5, 0.38, pulse))
