class_name FPKeybindMenu
extends CanvasLayer

## Esc menu: the key settings screen. Lists every action in keybinds.json
## with its current key. Click a key (or move with arrows/Tab and press
## Enter) and press the new key; Esc cancels the wait. A key already used by
## another action swaps with it. "기본값 되돌리기" drops the player's own
## keys. Works with the mouse alone and with the keyboard alone.

signal closed

var main: Node
var root: Control
var list: VBoxContainer
var hint: Label
var reset_button: Button
var close_button: Button
## action -> key Button
var buttons: Dictionary = {}
## Action waiting for its new key ("" = none).
var waiting: String = ""
var _order: Array = []
var _closed_frame: int = -10

func _ready() -> void:
	layer = 40
	_build()
	_set_shown(false)

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
	_fill()
	_set_shown(true)
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

## Current keyboard key of an action, as a key name ("F", "Tab", "1").
static func key_of(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var code: int = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
			return OS.get_keycode_string(code)
	return ""

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
		(buttons[action] as Button).grab_focus()
	return ok

func reset_defaults() -> void:
	if main != null:
		main.reset_keybinds()
	waiting = ""
	_refresh()

func start_wait(action: String) -> void:
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

var _last_wait: String = ""

# --- building -------------------------------------------------------------------

func _build() -> void:
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.0, 0.01, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.07, 0.07, 0.97)
	sb.border_color = Color(0.55, 0.22, 0.22)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var title := Label.new()
	title.text = "키 설정"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.96, 0.9, 0.84))
	col.add_child(title)
	hint = Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.8, 0.68, 0.62))
	col.add_child(hint)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	col.add_child(list)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 16)
	col.add_child(bottom)
	reset_button = _button("기본값 되돌리기", 200)
	reset_button.pressed.connect(reset_defaults)
	bottom.add_child(reset_button)
	close_button = _button("닫기", 140)
	close_button.pressed.connect(close)
	bottom.add_child(close_button)

func _button(text: String, w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 34)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 18)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.24, 0.12, 0.12)
	n.set_corner_radius_all(6)
	var f := StyleBoxFlat.new()
	f.bg_color = Color(0.62, 0.2, 0.2)
	f.border_color = Color(1.0, 0.85, 0.7)
	f.set_border_width_all(2)
	f.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", f)
	b.add_theme_stylebox_override("focus", f)
	b.add_theme_stylebox_override("pressed", f)
	b.mouse_entered.connect(func(): b.grab_focus())
	return b

func _fill() -> void:
	if main == null or list == null:
		return
	for ch in list.get_children():
		ch.queue_free()
	buttons.clear()
	_order.clear()
	var defs: Dictionary = main.keybind_defaults()
	for action in defs:
		_order.append(action)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		var name_label := Label.new()
		name_label.text = String(defs[action].get("설명", action))
		name_label.custom_minimum_size = Vector2(300, 0)
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.add_theme_color_override("font_color", Color(0.93, 0.88, 0.82))
		row.add_child(name_label)
		var b := _button("", 150)
		b.pressed.connect(func(): _last_wait = action; start_wait(action))
		row.add_child(b)
		buttons[action] = b
		list.add_child(row)
	_refresh()

func _refresh() -> void:
	for action in buttons:
		var b: Button = buttons[action]
		b.text = "...새 키를 누르기" if action == waiting else key_of(action)
	if hint != null:
		hint.text = "새 키를 누르세요  ·  Esc 또는 오른쪽 클릭 = 취소" if waiting != "" else "눌러서 바꾸기  ·  방향키/Tab 이동, Enter 선택  ·  Esc 닫기"