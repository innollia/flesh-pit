class_name FPTitleScreen
extends CanvasLayer

## First thing on screen. The restroom stands blurred behind it and the view
## drifts a little. Items: 이어하기 (only with a save), 새로 시작 (asks first
## when a save would be lost), 설정, 종료. Short, flat labels only.

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

func _ready() -> void:
    layer = 34
    process_mode = Node.PROCESS_MODE_ALWAYS
    root = FPMenuKit.make_root(self)
    FPMenuKit.backdrop(root, 0.42, 2.2)
    _build()
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
    return confirm_col != null and confirm_col.get_parent().get_parent().visible

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
    for b in [continue_button, new_button, settings_button, quit_button]:
        if b.visible:
            items.append(b)
    FPMenuKit.chain_focus(items)

func _process(delta: float) -> void:
    if not is_open() or main == null:
        return
    _t += delta
    var p = main.get("player")
    if p is Node3D:
        (p as Node3D).rotation.y = _base_yaw + sin(_t * 0.13) * 0.05

## New game: straight in without a save, otherwise ask first.
func request_new_game() -> void:
    if has_save:
        _show_confirm(true)
    else:
        new_game_requested.emit()

func _show_confirm(on: bool) -> void:
    menu_col.get_parent().get_parent().visible = not on
    confirm_col.get_parent().get_parent().visible = on
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
    new_button = FPMenuKit.button("새로 시작", 300)
    new_button.pressed.connect(request_new_game)
    settings_button = FPMenuKit.button("설정", 300)
    settings_button.pressed.connect(func(): settings_requested.emit())
    quit_button = FPMenuKit.button("종료", 300)
    quit_button.pressed.connect(func(): quit_requested.emit())
    for b in [continue_button, new_button, settings_button, quit_button]:
        menu_col.add_child(b)

    confirm_col = _column(Vector2(96, 300))
    confirm_col.add_child(FPMenuKit.label("저장된 기록을 지웁니다.", 19))
    confirm_yes = FPMenuKit.button("지우고 시작", 300)
    confirm_yes.pressed.connect(func():
        _show_confirm(false)
        new_game_requested.emit())
    confirm_no = FPMenuKit.button("취소", 300)
    confirm_no.pressed.connect(func(): _show_confirm(false))
    confirm_col.add_child(confirm_yes)
    confirm_col.add_child(confirm_no)
    FPMenuKit.chain_focus([confirm_yes, confirm_no])
    confirm_col.get_parent().get_parent().visible = false

## A plate at a fixed spot on the left; returns its column.
func _column(at: Vector2) -> VBoxContainer:
    var holder := Control.new()
    holder.position = at
    holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(holder)
    var panel := PanelContainer.new()
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.08, 0.06, 0.06, 0.82)
    sb.border_color = FPMenuKit.EDGE
    sb.set_border_width_all(1)
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