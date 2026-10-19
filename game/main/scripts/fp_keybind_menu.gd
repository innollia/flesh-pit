class_name FPKeybindMenu
extends CanvasLayer

## Esc menu: the key settings screen, one action at a time. Arrows on both
## sides (or ←/→) step through every action in keybinds.json: the player's
## own body stands on a turntable once per action, the one in the light
## loops that action's motion, the previous and next wait at the sides by
## the arrows, and a step turns the table (fp_keybind_doll.gd). Under it the
## action's name and its key cap. Click the cap (or Enter) and
## press the new key; Esc cancels the wait. A key already used by another
## action swaps with it. "기본값 되돌리기" drops the player's own keys.
## Works with the mouse alone and with the keyboard alone.

signal closed

const KeybindDoll := preload("res://main/scripts/fp_keybind_doll.gd")
const ITEM_INK := Color(0.85, 0.72, 0.66)
const FOCUS_INK := Color(1.0, 0.88, 0.53)

var main: Node
var root: Control
var hint: Label
var reset_button: Button
var close_button: Button
var action_label: Label
var index_label: Label
var doll: Node
var doll_rect: TextureRect
var prev_arrow: Button
var next_arrow: Button
## action -> key Button (only the shown action's cap is visible)
var buttons: Dictionary = {}
## Action waiting for its new key ("" = none).
var waiting: String = ""
## Index into _order of the action on show.
var current := 0
var _order: Array = []
var _names: Dictionary = {}
var _caps: HBoxContainer
var _closed_frame: int = -10
var _last_wait: String = ""

## A chunky tooth-coloured arrow, lit like a focused item on hover.
class ArrowButton extends Button:
	var dir := 1.0
	var _hot := false
	func _init(d: float) -> void:
		dir = d
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(90, 150)
		for state in ["normal", "hover", "focus", "pressed", "disabled"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		mouse_entered.connect(func(): _hot = true; queue_redraw())
		mouse_exited.connect(func(): _hot = false; queue_redraw())
	func _draw() -> void:
		var c := size * 0.5
		var w := 26.0 if not _hot else 30.0
		var h := 46.0 if not _hot else 52.0
		var tip := c + Vector2(dir * w, 0)
		var pts := PackedVector2Array([tip, c + Vector2(-dir * w, -h), c + Vector2(-dir * w * 0.45, 0), c + Vector2(-dir * w, h)])
		var shadow := PackedVector2Array()
		for p in pts:
			shadow.append(p + Vector2(0, 4))
		draw_colored_polygon(shadow, Color(0.06, 0.01, 0.02, 0.7))
		draw_colored_polygon(pts, Color(1.0, 0.88, 0.53) if _hot else Color(0.9, 0.84, 0.74))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.06, 0.01, 0.02, 0.85), 2.0)

func _ready() -> void:
	layer = 40
	_build()
	_set_shown(false)
	get_viewport().size_changed.connect(func(): FPMenuKit.fit(self, root))
	FPMenuKit.fit(self, root)

func setup(m: Node) -> void:
	main = m
	_fill()

func is_open() -> bool:
	return root != null and root.visible

## True on the frame the menu closed (so the same Esc does not reopen it).
func just_closed() -> bool:
	return Engine.get_process_frames() - _closed_frame <= 1

func open() -> void:
	if is_open():
		return
	waiting = ""
	if doll.get("view") == null:
		var vp: SubViewport = doll.call("build")
		doll_rect.texture = vp.get_texture()
	_fill()
	if main != null and main.get("progression") != null:
		doll.call("dress", main.progression)
	_set_shown(true)
	FPMenuKit.fit(self, root)
	show_action(0, true)
	if not _order.is_empty():
		(buttons[_order[0]] as Button).grab_focus()

func close() -> void:
	if not is_open():
		return
	waiting = ""
	_set_shown(false)
	_closed_frame = Engine.get_process_frames()
	closed.emit()

func _set_shown(on: bool) -> void:
	visible = on
	if root != null:
		root.visible = on
	if doll != null:
		if doll.get("view") != null:
			(doll.get("view") as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
		doll.set_process(on)

## Current keyboard key of an action, as a key name ("F", "Tab", "1").
static func key_of(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var code: int = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
			return OS.get_keycode_string(code)
	return ""

static func binding_of(action: String) -> String:
	var names := [key_of(action)]
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			names.append("LMB" if event.button_index == MOUSE_BUTTON_LEFT else "RMB")
	return " / ".join(names)

## Shows action `i` (wrapping): the table turns it into the light, its
## name, number and key cap. `snap` skips the turn (opening the screen).
func show_action(i: int, snap: bool = false) -> void:
	if _order.is_empty():
		return
	var had_focus := false
	var owner_now := root.get_viewport().gui_get_focus_owner() if root.is_inside_tree() else null
	for b in buttons.values():
		if b == owner_now:
			had_focus = true
	current = posmod(i, _order.size())
	var action: String = _order[current]
	for a in buttons:
		(buttons[a] as Button).visible = a == action
	action_label.text = String(_names.get(action, action))
	index_label.text = "%d / %d" % [current + 1, _order.size()]
	doll.call("show_index", current, snap)
	reset_button.focus_neighbor_top = reset_button.get_path_to(buttons[action])
	close_button.focus_neighbor_top = close_button.get_path_to(buttons[action])
	if had_focus:
		(buttons[action] as Button).grab_focus()

func step(d: int) -> void:
	if waiting != "":
		return
	show_action(current + d)

func _show(action: String) -> void:
	var i := _order.find(action)
	if i >= 0 and i != current:
		show_action(i)

## Give an action a new key. A key another action already uses swaps.
func assign(action: String, key_name: String) -> bool:
	if main == null or key_name == "":
		return false
	var old := key_of(action)
	for other in _order:
		if other != action and key_of(other) == key_name and old != "":
			main.rebind_key(other, old)
	var ok: bool = main.rebind_key(action, key_name)
	waiting = ""
	_refresh()
	if buttons.has(action):
		_show(action)
		(buttons[action] as Button).grab_focus()
	return ok

func reset_defaults() -> void:
	if main != null:
		main.reset_keybinds()
	waiting = ""
	_refresh()

func start_wait(action: String) -> void:
	_show(action)
	waiting = action
	_refresh()

func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if waiting != "":
		if event is InputEventKey and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
			if code == KEY_ESCAPE:
				waiting = ""
				_refresh()
				if buttons.has(_last_wait):
					(buttons[_last_wait] as Button).grab_focus()
			else:
				assign(waiting, OS.get_keycode_string(code))
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
			waiting = ""
			_refresh()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	# ←/→ step through the actions while the key cap (or nothing) has focus;
	# on the bottom row they move between its buttons as usual
	var focused := root.get_viewport().gui_get_focus_owner()
	if focused == reset_button or focused == close_button:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		step(-1 if event.is_action_pressed("ui_left") else 1)

# --- building -------------------------------------------------------------------

func _build() -> void:
	root = FPMenuKit.make_root(self)
	FPMenuKit.backdrop(root, 1.0)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	# the menus' face (title, pause, settings) for every label and button
	var font_theme := Theme.new()
	font_theme.default_font = FPMenuKit.FONT
	col.theme = font_theme
	center.add_child(col)
	var title := FPMenuKit.label("키 설정", 30, Color(0.96, 0.9, 0.84))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	hint = FPMenuKit.label("", 15, Color(0.8, 0.68, 0.62))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	# ◀ protagonist ▶
	var stage := HBoxContainer.new()
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.add_theme_constant_override("separation", 10)
	col.add_child(stage)
	prev_arrow = ArrowButton.new(-1.0)
	prev_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prev_arrow.pressed.connect(func(): step(-1))
	stage.add_child(prev_arrow)
	# the bodies are built on first open (about 80 ms for six), not at start
	doll = KeybindDoll.new()
	doll.name = "Doll"
	add_child(doll)
	doll_rect = TextureRect.new()
	doll_rect.name = "Protagonist"
	doll_rect.custom_minimum_size = Vector2(KeybindDoll.VIEW) * 1.72
	doll_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	doll_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	doll_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	doll_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the one in front stands in a pool of light; the ones waiting in line
	# stay in the dark at the sides
	var stage_mat := ShaderMaterial.new()
	var stage_shader := Shader.new()
	stage_shader.code = """shader_type canvas_item;
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float lit = mix(0.32, 1.0, smoothstep(0.36, 0.1, abs(UV.x - 0.5)));
	vec2 p = (UV - vec2(0.5, 0.95)) * vec2(3.2, 14.0);
	float pool = exp(-dot(p, p)) * 0.55;
	vec2 c = (UV - vec2(0.5, 0.45)) * vec2(2.6, 1.0);
	float cone = exp(-dot(c, c) * 3.0) * 0.12;
	vec3 light = vec3(1.0, 0.82, 0.68) * (pool + cone);
	COLOR = vec4(mix(light, t.rgb * lit, t.a), max(t.a, clamp(pool + cone, 0.0, 1.0)));
}"""
	stage_mat.shader = stage_shader
	doll_rect.material = stage_mat
	stage.add_child(doll_rect)
	next_arrow = ArrowButton.new(1.0)
	next_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	next_arrow.pressed.connect(func(): step(1))
	stage.add_child(next_arrow)
	action_label = FPMenuKit.label("", 30, Color(1.0, 0.95, 0.88))
	action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(action_label)
	index_label = FPMenuKit.label("", 14, Color(0.7, 0.6, 0.56))
	index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(index_label)
	var caps_row := CenterContainer.new()
	caps_row.custom_minimum_size = Vector2(0, 52)
	col.add_child(caps_row)
	_caps = HBoxContainer.new()
	caps_row.add_child(_caps)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 30)
	col.add_child(bottom)
	reset_button = _button("기본값 되돌리기", 200, false)
	reset_button.pressed.connect(reset_defaults)
	bottom.add_child(reset_button)
	close_button = _button("닫기", 120, false)
	close_button.pressed.connect(close)
	bottom.add_child(close_button)

## Key buttons are the tooth-coloured key caps of the HUD prompts
## (FPMenuKit.draw_key); the others are plain ink, lit when focused.
func _button(text: String, w: float, key_cap: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 34)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 18)
	if not key_cap:
		for state in ["normal", "hover", "focus", "pressed", "disabled"]:
			b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", ITEM_INK)
		b.add_theme_color_override("font_focus_color", FOCUS_INK)
		b.add_theme_color_override("font_hover_color", FOCUS_INK)
		b.mouse_entered.connect(func(): b.grab_focus())
		return b
	b.custom_minimum_size = Vector2(w, 46)
	b.add_theme_font_size_override("font_size", 24)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.9, 0.84, 0.74)
	n.border_color = Color(0.06, 0.01, 0.02)
	n.set_border_width_all(1)
	n.border_width_bottom = 5
	n.set_corner_radius_all(2)
	n.content_margin_left = 18
	n.content_margin_right = 18
	var f := n.duplicate() as StyleBoxFlat
	f.bg_color = Color(1.0, 0.94, 0.72)
	f.border_color = Color(1.0, 0.55, 0.3)
	f.set_border_width_all(2)
	f.border_width_bottom = 5
	b.add_theme_color_override("font_color", Color(0.25, 0.05, 0.06))
	b.add_theme_color_override("font_focus_color", Color(0.32, 0.02, 0.04))
	b.add_theme_color_override("font_hover_color", Color(0.32, 0.02, 0.04))
	b.add_theme_color_override("font_pressed_color", Color(0.32, 0.02, 0.04))
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", f)
	b.add_theme_stylebox_override("focus", f)
	b.add_theme_stylebox_override("pressed", f)
	b.mouse_entered.connect(func(): b.grab_focus())
	return b

func _fill() -> void:
	if main == null or _caps == null:
		return
	for ch in _caps.get_children():
		ch.queue_free()
	buttons.clear()
	_order.clear()
	_names.clear()
	var defs: Dictionary = main.keybind_defaults()
	for action in defs:
		_order.append(action)
		_names[action] = String(defs[action].get("설명", action))
		var b := _button("", 180)
		b.pressed.connect(func(): _last_wait = action; start_wait(action))
		_caps.add_child(b)
		buttons[action] = b
	for action in buttons:
		var b: Button = buttons[action]
		b.focus_neighbor_bottom = b.get_path_to(reset_button)
		b.focus_neighbor_top = b.get_path_to(b)
		b.focus_neighbor_left = b.get_path_to(b)
		b.focus_neighbor_right = b.get_path_to(b)
	doll.call("set_actions", _order)
	current = clampi(current, 0, maxi(0, _order.size() - 1))
	_refresh()
	if not _order.is_empty():
		show_action(current, true)

func _refresh() -> void:
	for action in buttons:
		var b: Button = buttons[action]
		b.text = "...새 키를 누르기" if action == waiting else binding_of(action)
	if hint != null:
		hint.text = "새 키를 누르세요  ·  Esc 또는 오른쪽 클릭 = 취소" if waiting != "" else "←/→ 행동 넘기기  ·  키를 눌러 바꾸기  ·  Esc 닫기"
