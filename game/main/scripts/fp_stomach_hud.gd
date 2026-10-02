class_name FPStomachHUD
extends Control

var main: Node3D
var _last_fill := -1.0
var _last_size := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_delta: float) -> void:
	visible = main != null and not main.title_screen.is_open() and not main.settings_menu.is_open() and not main.ended
	if not visible:
		return
	if main.stomach.fill != _last_fill or size != _last_size:
		_last_fill = main.stomach.fill
		_last_size = size
		queue_redraw()

func _draw() -> void:
	if main == null:
		return
	var scale_ui := maxf(size.y / 720.0, 0.65)
	var origin := Vector2(28, size.y / scale_ui - 38)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * scale_ui)
	var ratio: float = main.stomach.fill_ratio()
	var color := Color(0.9, 0.67, 0.54) if ratio < 1.0 else Color(1.0, 0.35, 0.27)
	var font := ThemeDB.fallback_font
	draw_string(font, origin - Vector2(0, 12), "위장  %d%%" % roundi(ratio * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.94, 0.88))
	draw_rect(Rect2(origin, Vector2(180, 9)), Color(0.1, 0.025, 0.025, 0.85))
	draw_rect(Rect2(origin, Vector2(180 * clampf(ratio, 0, 1), 9)), color)
	if ratio >= 1.0:
		var key := FPKeybindMenu.key_of("fp_vomit")
		draw_string(font, origin + Vector2(194, 9), "%s  토하기" % ("V" if key == "" else key), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)
