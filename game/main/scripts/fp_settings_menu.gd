class_name FPSettingsMenu
extends CanvasLayer

## Settings screen (title screen and pause menu both open it). Volume,
## mouse sensitivity, invert look, field of view, window mode, resolution
## and the existing key settings screen. Every change is applied and saved
## at once (FPSettings). Mouse alone: drag sliders, click values (right
## click steps back). Keyboard/pad alone: up/down moves, left/right changes,
## Enter opens, Esc closes.

signal closed
signal changed(settings: Dictionary)

const WINDOW_LABELS := {"windowed": "창", "fullscreen": "전체 화면"}

var settings: Dictionary = FPSettings.defaults()
## Where changes are saved ("" = do not save; tests).
var save_path: String = FPSettings.PATH
var player: Node
var keybind_menu: FPKeybindMenu
var root: Control
var sliders: Dictionary = {}
var values: Dictionary = {}
var steppers: Dictionary = {}
var keys_button: Button
var close_button: Button
var _focus_order: Array = []
var _closed_frame: int = -10
var _filling := false

func _ready() -> void:
    layer = 38
    process_mode = Node.PROCESS_MODE_ALWAYS
    root = FPMenuKit.make_root(self)
    _tile_backdrop()
    _build()
    _set_shown(false)
    get_viewport().size_changed.connect(func(): FPMenuKit.fit(self, root))
    FPMenuKit.fit(self, root)

func _tile_backdrop() -> void:
    var wall := ColorRect.new()
    wall.set_anchors_preset(Control.PRESET_FULL_RECT)
    wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var shader := Shader.new()
    shader.code = """shader_type canvas_item;
uniform sampler2D tile : filter_linear, repeat_enable;
void fragment() {
    vec2 p = FRAGCOORD.xy / vec2(120.0, 120.0);
    vec3 detail = texture(tile, p).rgb;
    vec3 ceramic = vec3(0.28, 0.29, 0.27) + (detail.r - 0.5) * 0.045;
    COLOR = vec4(mix(ceramic, vec3(0.13, 0.14, 0.13), detail.b), 1.0);
}"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("tile", FPRestroom.tile_texture())
    wall.material = material
    root.add_child(wall)

func setup(s: Dictionary, p: Node, kb: FPKeybindMenu) -> void:
    settings = FPSettings.sanitize(s)
    player = p
    keybind_menu = kb
    if keybind_menu != null and not keybind_menu.closed.is_connected(_on_keys_closed):
        keybind_menu.closed.connect(_on_keys_closed)
    _fill()

func is_open() -> bool:
    return root != null and root.visible

func just_closed() -> bool:
    return Engine.get_process_frames() - _closed_frame <= 1

func open() -> void:
    if is_open():
        return
    _fill()
    _set_shown(true)
    FPMenuKit.fit(self, root)
    (_focus_order[0] as Control).grab_focus()

func close() -> void:
    if not is_open():
        return
    if keybind_menu != null and keybind_menu.is_open():
        keybind_menu.close()
    _set_shown(false)
    _closed_frame = Engine.get_process_frames()
    closed.emit()

func _set_shown(on: bool) -> void:
    visible = on
    if root != null:
        root.visible = on

func _input(event: InputEvent) -> void:
    if not is_open():
        return
    if keybind_menu != null and (keybind_menu.is_open() or keybind_menu.just_closed()):
        return
    if event.is_action_pressed("ui_cancel"):
        get_viewport().set_input_as_handled()
        close()

# --- values ---------------------------------------------------------------------

## Change one setting (menu rows and tests go through here).
func set_value(key: String, v) -> void:
    settings[key] = v
    settings = FPSettings.sanitize(settings)
    FPSettings.apply_audio(settings)
    FPSettings.apply_look(settings, player)
    if key == "window_mode" or key == "resolution":
        FPSettings.apply_window(settings)
    if save_path != "":
        FPSettings.save_to(settings, save_path)
    _fill()
    changed.emit(settings)

func step(key: String, dir: int) -> void:
    match key:
        "invert_y":
            set_value(key, not bool(settings[key]))
        "window_mode":
            set_value(key, _cycle(FPSettings.WINDOW_MODES, String(settings[key]), dir))
        "resolution":
            set_value(key, _cycle(FPSettings.RESOLUTIONS, String(settings[key]), dir))

func _cycle(list: Array, cur: String, dir: int) -> String:
    var i := list.find(cur)
    return String(list[(maxi(i, 0) + dir + list.size()) % list.size()])

func _text_for(key: String) -> String:
    match key:
        "master", "sfx", "music":
            return "%d%%" % roundi(float(settings[key]) * 100.0)
        "mouse_sensitivity":
            return "%.2fx" % float(settings[key])
        "fov":
            return "%d" % roundi(float(settings[key]))
        "invert_y":
            return "켜짐" if bool(settings[key]) else "꺼짐"
        "window_mode":
            return String(WINDOW_LABELS.get(String(settings[key]), "창"))
        "resolution":
            return String(settings[key]).replace("x", " x ")
    return ""

func _fill() -> void:
    _filling = true
    for key in sliders:
        var s: HSlider = sliders[key]
        var v := float(settings[key])
        s.value = v * 100.0 if key in ["master", "sfx", "music"] else v
    for key in values:
        (values[key] as Label).text = _text_for(key)
    for key in steppers:
        (steppers[key] as Button).text = "<   %s   >" % _text_for(key)
    if steppers.has("resolution"):
        (steppers["resolution"] as Button).disabled = String(settings["window_mode"]) == "fullscreen"
    _filling = false

# --- building -------------------------------------------------------------------

func _build() -> void:
    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(center)
    var col := VBoxContainer.new()
    col.custom_minimum_size.x = 620
    col.add_theme_constant_override("separation", 10)
    col.add_theme_font_override("font", load("res://main/art/fonts/BlackHanSans-Regular.ttf"))
    center.add_child(col)
    var title := FPMenuKit.label("설정", 26)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    col.add_child(title)
    _section(col, "소리")
    _slider_row(col, "master", "전체 음량", 0, 100, 5)
    _slider_row(col, "sfx", "효과음", 0, 100, 5)
    _slider_row(col, "music", "배경음", 0, 100, 5)
    _section(col, "시점")
    _slider_row(col, "mouse_sensitivity", "마우스 감도", FPSettings.SENS_MIN, FPSettings.SENS_MAX, 0.05)
    _stepper_row(col, "invert_y", "상하 반전")
    _slider_row(col, "fov", "시야각", FPSettings.FOV_MIN, FPSettings.FOV_MAX, 1)
    _section(col, "화면")
    _stepper_row(col, "window_mode", "창 모드")
    _stepper_row(col, "resolution", "해상도")
    var bottom := HBoxContainer.new()
    bottom.alignment = BoxContainer.ALIGNMENT_CENTER
    bottom.add_theme_constant_override("separation", 16)
    col.add_child(bottom)
    keys_button = FPMenuKit.button("키 설정", 200)
    keys_button.pressed.connect(open_keys)
    bottom.add_child(keys_button)
    close_button = FPMenuKit.button("닫기", 160)
    close_button.pressed.connect(close)
    bottom.add_child(close_button)
    _focus_order.append(keys_button)
    _focus_order.append(close_button)
    for control in _focus_order:
        if control is Button:
            for state in ["normal", "hover", "pressed", "focus", "disabled"]:
                control.add_theme_stylebox_override(state, StyleBoxEmpty.new())
    FPMenuKit.chain_focus(_focus_order)
    keys_button.focus_neighbor_right = keys_button.get_path_to(close_button)
    close_button.focus_neighbor_left = close_button.get_path_to(keys_button)

func _section(col: VBoxContainer, text: String) -> void:
    var l := FPMenuKit.label(text, 14, FPMenuKit.DIM_INK)
    col.add_child(l)

func _row(col: VBoxContainer, text: String) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    var l := FPMenuKit.label(text, 18)
    l.custom_minimum_size = Vector2(170, 0)
    row.add_child(l)
    col.add_child(row)
    return row

func _slider_row(col: VBoxContainer, key: String, text: String, a: float, b: float, st: float) -> void:
    var row := _row(col, text)
    var s := FPMenuKit.slider(a, b, st, 280)
    row.add_child(s)
    var v := FPMenuKit.label("", 17, FPMenuKit.DIM_INK)
    v.custom_minimum_size = Vector2(80, 0)
    row.add_child(v)
    sliders[key] = s
    values[key] = v
    s.value_changed.connect(func(x: float):
        if _filling:
            return
        set_value(key, x / 100.0 if key in ["master", "sfx", "music"] else x))
    _focus_order.append(s)

func _stepper_row(col: VBoxContainer, key: String, text: String) -> void:
    var row := _row(col, text)
    var b := FPMenuKit.button("", 280, 34)
    row.add_child(b)
    steppers[key] = b
    b.pressed.connect(func(): step(key, 1))
    b.gui_input.connect(func(e: InputEvent):
        if e.is_action_pressed("ui_left"):
            step(key, -1)
            b.accept_event()
        elif e.is_action_pressed("ui_right"):
            step(key, 1)
            b.accept_event()
        elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
            step(key, -1)
            b.accept_event())
    _focus_order.append(b)

# --- key settings -----------------------------------------------------------------

func open_keys() -> void:
    if keybind_menu == null:
        return
    keybind_menu.open()

func _on_keys_closed() -> void:
    if is_open():
        keys_button.grab_focus()
