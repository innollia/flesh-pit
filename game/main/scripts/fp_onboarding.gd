class_name FPOnboarding
extends Control

## Small, one-use input icons beside the hands and stomach.
const MOVE := ["fdk_move_forward", "fdk_move_left", "fdk_move_back", "fdk_move_right"]
var waiting := false
var remaining: Array[String] = []
var vomit_hint := false
var _time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func reset() -> void:
	remaining.clear()
	waiting = false
	visible = true

func movement() -> void:
	remaining.assign(MOVE + ["fdk_eat", "fp_pick"])

func _input(event: InputEvent) -> void:
	if not visible or waiting or (event is InputEventKey and event.echo):
		return
	for action in remaining.duplicate():
		if event.is_action_pressed(action):
			remaining.erase(action)
	if event.is_action_pressed("fp_vomit"):
		vomit_hint = false

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.77)
	var alpha := 0.45 + 0.55 * (sin(_time * 5.0) * 0.5 + 0.5) if waiting else 0.9
	if waiting or remaining.has(MOVE[0]):
		_icon(c, _key(MOVE[0], "W"), alpha)
	if not waiting:
		for i in range(1, 4):
			if remaining.has(MOVE[i]):
				_icon(c + Vector2((i - 2) * 42, 42), _key(MOVE[i], ["A", "S", "D"][i - 1]), 0.9)
		_mouse(c + Vector2(118, 24))
	if vomit_hint:
		_icon(Vector2(size.x * 0.5, size.y * 0.88), _key("fp_vomit", "V"), alpha)

func _key(action: String, fallback: String) -> String:
	var key := FPKeybindMenu.key_of(action)
	return fallback if key == "" else key

func _mouse(center: Vector2) -> void:
	if not remaining.has("fdk_eat") and not remaining.has("fp_pick"):
		return
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(0.08, 0.06, 0.05, 0.25)
	outline.border_color = Color(1, 1, 1, 0.75)
	outline.set_border_width_all(1)
	outline.set_corner_radius_all(20)
	draw_style_box(outline, Rect2(center - Vector2(27, 35), Vector2(54, 70)))
	for i in range(2):
		if not remaining.has(["fdk_eat", "fp_pick"][i]):
			continue
		var button := StyleBoxFlat.new()
		button.bg_color = Color(1, 1, 1, 0.2)
		button.set_corner_radius_all(4)
		button.set_corner_radius(CORNER_TOP_LEFT if i == 0 else CORNER_TOP_RIGHT, 16)
		draw_style_box(button, Rect2(center + Vector2(-24 + i * 25, -32), Vector2(23, 28)))
		draw_string(ThemeDB.fallback_font, center + Vector2(-17 + i * 25, -12), "L" if i == 0 else "R", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9))

func _icon(center: Vector2, text: String, alpha: float, width: float = 34) -> void:
	var box := Rect2(center - Vector2(width, 30) * 0.5, Vector2(width, 30))
	draw_style_box(_box(alpha), box)
	var font := ThemeDB.fallback_font
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(font, center + Vector2(-tw * 0.5, 5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, alpha))

func _box(alpha: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.04, 0.04, alpha * 0.6)
	s.border_color = Color(1, 1, 1, alpha)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	return s
