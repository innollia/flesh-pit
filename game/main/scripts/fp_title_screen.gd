class_name FPTitleScreen
extends CanvasLayer

## Text-only menu on the moving flesh surface (FPTitleWall). New-game
## confirmation replaces its own row while the other options remain.

signal continue_requested
signal new_game_requested
signal settings_requested
signal quit_requested

var root: Control
var main: Node
var continue_button: Button
var new_button: Button
var settings_button: Button
var quit_button: Button
var menu_col: VBoxContainer
var confirm_col: VBoxContainer
var confirm_yes: Button
var confirm_no: Button
var has_save := false
var settings_menu: FPSettingsMenu
var _t := 0.0
var _base_yaw := 0.0
var wall: FPTitleWall
const FONT := preload("res://main/art/fonts/BlackHanSans-Regular.ttf")

func _ready() -> void:
    layer = 34
    process_mode = Node.PROCESS_MODE_ALWAYS
    root = FPMenuKit.make_root(self)
    _build()
    wall = FPTitleWall.new()
    add_child(wall)
    wall.setup(root)
    get_viewport().size_changed.connect(func(): FPMenuKit.fit(self, root))
    FPMenuKit.fit(self, root)

func setup(m: Node, save_exists: bool) -> void:
    main = m
    has_save = save_exists
    var p = m.get("player") if m != null else null
    if p != null:
        _base_yaw = float(p.get("_yaw"))
    _refresh()

func is_open() -> bool:
    return root != null and root.visible

func is_confirming() -> bool:
    return confirm_col != null and confirm_col.visible

func open() -> void:
    root.visible = true
    visible = true
    _show_confirm(false)
    _refresh()
    FPMenuKit.fit(self, root)
    focus_first()

func close() -> void:
    root.visible = false
    visible = false

func focus_first() -> void:
    (continue_button if has_save else new_button).grab_focus()

func _refresh() -> void:
    if continue_button == null:
        return
    continue_button.visible = has_save
    var items: Array = []
    for b in [continue_button, new_button, confirm_yes, confirm_no, settings_button, quit_button]:
        if b != null and b.visible and (b not in [confirm_yes, confirm_no] or confirm_col.visible):
            items.append(b)
    FPMenuKit.chain_focus(items)

## New game: straight in without a save, otherwise ask first.
func request_new_game() -> void:
    if has_save:
        _show_confirm(true)
    else:
        new_game_requested.emit()

func _show_confirm(on: bool) -> void:
    new_button.visible = not on
    confirm_col.visible = on
    _refresh()
    if on:
        confirm_no.grab_focus()
    elif is_open():
        new_button.grab_focus()

func _input(event: InputEvent) -> void:
    if not is_open():
        return
    if settings_menu != null and (settings_menu.is_open() or settings_menu.just_closed()):
        return
    if event.is_action_pressed("ui_cancel") and is_confirming():
        get_viewport().set_input_as_handled()
        _show_confirm(false)

func _build() -> void:
    var head := Control.new()
    head.set_anchors_preset(Control.PRESET_FULL_RECT)
    head.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(head)
    var title := FPMenuKit.label("FLESH PIT", 46, Color(0.96, 0.95, 0.93))
    title.add_theme_font_override("font", FONT)
    title.add_theme_constant_override("outline_size", 0)
    title.position = Vector2(96, 150)
    head.add_child(title)
    var rule := ColorRect.new()
    rule.color = Color(0.62, 0.22, 0.2)
    rule.position = Vector2(98, 212)
    rule.size = Vector2(250, 2)
    head.add_child(rule)


    menu_col = _column(Vector2(96, 300))
    continue_button = FPMenuKit.button("이어하기", 300)
    continue_button.pressed.connect(func(): continue_requested.emit())
    new_button = FPMenuKit.button("새 게임", 300)
    new_button.pressed.connect(request_new_game)
    settings_button = FPMenuKit.button("설정", 300)
    settings_button.pressed.connect(func(): settings_requested.emit())
    quit_button = FPMenuKit.button("종료", 300)
    quit_button.pressed.connect(func(): quit_requested.emit())
    for b in [continue_button, new_button, settings_button, quit_button]:
        _text_button(b)
        menu_col.add_child(b)

    confirm_col = VBoxContainer.new()
    menu_col.add_child(confirm_col)
    menu_col.move_child(confirm_col, 2)
    var question := FPMenuKit.label("새로 시작할까요?", 22)
    question.add_theme_font_override("font", FONT)
    confirm_col.add_child(question)
    confirm_yes = FPMenuKit.button("BONG", 300)
    confirm_yes.pressed.connect(func():
        _show_confirm(false)
        new_game_requested.emit())
    confirm_no = FPMenuKit.button("취소", 300)
    confirm_no.pressed.connect(func(): _show_confirm(false))
    confirm_col.add_child(confirm_yes)
    confirm_col.add_child(confirm_no)
    _text_button(confirm_yes)
    _text_button(confirm_no)
    FPMenuKit.chain_focus([confirm_yes, confirm_no])
    confirm_col.visible = false

func _text_button(b: Button) -> void:
    b.add_theme_font_override("font", FONT)
    b.add_theme_font_size_override("font_size", 27)
    b.alignment = HORIZONTAL_ALIGNMENT_LEFT
    for state in ["normal", "hover", "focus", "pressed", "disabled"]:
        b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
    b.add_theme_color_override("font_focus_color", Color(1.0, 0.88, 0.53))
    b.add_theme_color_override("font_hover_color", Color(1.0, 0.88, 0.53))

## A plate at a fixed spot on the left; returns its column.
func _column(at: Vector2) -> VBoxContainer:
    var holder := Control.new()
    holder.position = at
    holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(holder)
    var panel := PanelContainer.new()
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0, 0, 0, 0)
    sb.content_margin_left = 16
    sb.content_margin_right = 16
    sb.content_margin_top = 16
    sb.content_margin_bottom = 16
    panel.add_theme_stylebox_override("panel", sb)
    holder.add_child(panel)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 10)
    panel.add_child(col)
    return col
