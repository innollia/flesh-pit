class_name FPPauseMenu
extends CanvasLayer

## Esc during play: 계속 / 설정 / 저장하고 시작 화면으로 / 종료.
## Esc again = 계속. The tree is paused while this is up (main.gd).

signal resumed
signal settings_requested
signal title_requested
signal quit_requested

var root: Control
var buttons: Array = []
var settings_menu: FPSettingsMenu
var _closed_frame: int = -10

func _ready() -> void:
    layer = 36
    process_mode = Node.PROCESS_MODE_ALWAYS
    root = FPMenuKit.make_root(self)
    FPMenuKit.backdrop(root, 0.62)
    var col := FPMenuKit.plate(root)
    var title := FPMenuKit.label("정지", 24, FPMenuKit.DIM_INK)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    col.add_child(title)
    for pair in [["계속", resume], ["설정", func(): settings_requested.emit()],
            ["저장하고 시작 화면으로", func(): title_requested.emit()], ["종료", func(): quit_requested.emit()]]:
        var b := FPMenuKit.button(pair[0], 320)
        b.pressed.connect(pair[1])
        col.add_child(b)
        buttons.append(b)
    FPMenuKit.chain_focus(buttons)
    _set_shown(false)
    get_viewport().size_changed.connect(func(): FPMenuKit.fit(self, root))
    FPMenuKit.fit(self, root)

func is_open() -> bool:
    return root != null and root.visible

func just_closed() -> bool:
    return Engine.get_process_frames() - _closed_frame <= 1

func open() -> void:
    if is_open():
        return
    _set_shown(true)
    FPMenuKit.fit(self, root)
    (buttons[0] as Button).grab_focus()

func resume() -> void:
    if not is_open():
        return
    _set_shown(false)
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

func _input(event: InputEvent) -> void:
    if not is_open():
        return
    if settings_menu != null and (settings_menu.is_open() or settings_menu.just_closed()):
        return
    if event.is_action_pressed("ui_cancel"):
        get_viewport().set_input_as_handled()
        resume()