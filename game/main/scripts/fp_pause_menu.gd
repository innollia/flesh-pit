class_name FPPauseMenu
extends CanvasLayer

## Esc during play shuts the eyes (fp_pause_lids.gdshader): the lids close,
## the room shows only as red light through them, and the items glow on the
## dark like the title's ink: 눈 뜨기 / 설정 / 시작 화면으로 / 종료.
## Esc again = 눈 뜨기, and the eyes open again over the running game.
## The tree is paused while this is up (main.gd).

signal resumed
signal settings_requested
signal title_requested
signal quit_requested

const FONT := preload("res://main/art/fonts/BlackHanSans-Regular.ttf")
const CLOSE_TIME := 0.24
const OPEN_TIME := 0.16
const ITEM_INK := Color(0.92, 0.66, 0.56, 0.62)
const FOCUS_INK := Color(1.0, 0.88, 0.53)

var root: Control
var buttons: Array = []
var settings_menu: FPSettingsMenu
var lids: ColorRect
var column: VBoxContainer
var _closed_frame: int = -10
var _open := false
## 0 = eyes open, 1 = shut.
var shut := 0.0
var _beat := 0.0
var _glow_pos := Vector2(0.5, 0.5)
var _lid_mat: ShaderMaterial

func _ready() -> void:
    layer = 36
    process_mode = Node.PROCESS_MODE_ALWAYS
    root = FPMenuKit.make_root(self)
    lids = ColorRect.new()
    lids.name = "Lids"
    lids.set_anchors_preset(Control.PRESET_FULL_RECT)
    lids.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _lid_mat = ShaderMaterial.new()
    _lid_mat.shader = load("res://main/scripts/fp_pause_lids.gdshader")
    lids.material = _lid_mat
    root.add_child(lids)
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(center)
    column = VBoxContainer.new()
    column.add_theme_constant_override("separation", 6)
    center.add_child(column)
    for pair in [["눈 뜨기", resume], ["설정", func(): settings_requested.emit()],
            ["시작 화면으로", func(): title_requested.emit()], ["종료", func(): quit_requested.emit()]]:
        var b := FPMenuKit.button(pair[0], 360, 46)
        _ink_button(b)
        b.pressed.connect(pair[1])
        column.add_child(b)
        buttons.append(b)
    FPMenuKit.chain_focus(buttons)
    _set_shown(false)
    get_viewport().size_changed.connect(func(): FPMenuKit.fit(self, root))
    FPMenuKit.fit(self, root)

## Text only, like the title menu: no plates, the focused item lit.
func _ink_button(b: Button) -> void:
    b.add_theme_font_override("font", FONT)
    b.add_theme_font_size_override("font_size", 30)
    for state in ["normal", "hover", "focus", "pressed", "disabled"]:
        b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
    b.add_theme_color_override("font_color", ITEM_INK)
    b.add_theme_color_override("font_focus_color", FOCUS_INK)
    b.add_theme_color_override("font_hover_color", FOCUS_INK)
    b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
    b.add_theme_color_override("font_outline_color", Color(0.12, 0.0, 0.02, 0.55))
    b.add_theme_constant_override("outline_size", 8)

func is_open() -> bool:
    return _open

func just_closed() -> bool:
    return Engine.get_process_frames() - _closed_frame <= 1

func open() -> void:
    if is_open():
        return
    _open = true
    _set_shown(true)
    FPMenuKit.fit(self, root)
    (buttons[0] as Button).grab_focus()

func resume() -> void:
    if not is_open():
        return
    _open = false
    var focused := root.get_viewport().gui_get_focus_owner()
    if focused != null and buttons.has(focused):
        focused.release_focus()
    # The lids open over the running game (_process), passing input through.
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    column.visible = false
    _closed_frame = Engine.get_process_frames()
    resumed.emit()

## Back from settings: the item that opened it keeps focus.
func refocus() -> void:
    if is_open():
        (buttons[1] as Button).grab_focus()

func _set_shown(on: bool) -> void:
    visible = on
    if root != null:
        root.visible = on
        root.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
        column.visible = on
        column.modulate.a = 0.0

func _process(delta: float) -> void:
    if not visible:
        return
    shut = move_toward(shut, 1.0 if _open else 0.0, delta / (CLOSE_TIME if _open else OPEN_TIME))
    if not _open and shut <= 0.0:
        _set_shown(false)
        return
    _beat += delta
    var eased := shut * shut * (3.0 - 2.0 * shut)
    column.modulate.a = clampf((shut - 0.6) / 0.4, 0.0, 1.0)
    var focused := root.get_viewport().gui_get_focus_owner()
    if focused != null and buttons.has(focused):
        var r: Rect2 = focused.get_global_rect()
        var at := (r.get_center() - root.get_global_rect().position) / root.size
        _glow_pos = _glow_pos.lerp(at, 1.0 - exp(-delta * 14.0))
    _lid_mat.set_shader_parameter("close", eased)
    _lid_mat.set_shader_parameter("beat", _beat)
    _lid_mat.set_shader_parameter("rect_size", root.size)
    _lid_mat.set_shader_parameter("glow_pos", _glow_pos)
    _lid_mat.set_shader_parameter("glow", column.modulate.a)

func _input(event: InputEvent) -> void:
    if not is_open():
        return
    if settings_menu != null and (settings_menu.is_open() or settings_menu.just_closed()):
        return
    if event.is_action_pressed("ui_cancel"):
        get_viewport().set_input_as_handled()
        resume()
