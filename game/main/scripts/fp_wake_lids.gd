extends CanvasLayer

## Waking in the restroom after a death (spec 07: the player wakes there):
## the eyes start shut, the room is red light through the lids for a
## heartbeat or two, then they open with a slow, heavy blink. Same lids as
## the Esc screen (fp_pause_lids.gdshader). Input passes through.
## Also the start screen: the title opens out of shut eyes (play(false):
## no held beat, no second blink), as it does coming back from Esc.

const HOLD := 0.9
const OPEN := 0.55
const REBLINK := 0.35

var lids: ColorRect
var _mat: ShaderMaterial
var _t := -1.0
var _beat := 0.0
var _hold := HOLD
var _reblink := REBLINK
var _held := false

func _ready() -> void:
	layer = 37 # over the title (34) and the Esc lids (36)
	process_mode = Node.PROCESS_MODE_ALWAYS
	lids = ColorRect.new()
	lids.name = "WakeLids"
	lids.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lids.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://main/scripts/fp_pause_lids.gdshader")
	lids.material = _mat
	add_child(lids)
	visible = false

func set_eyes(ids: Array, field_angle: float = 0.0) -> void:
	FPPauseMenu.apply_eyes(_mat, ids, field_angle)

## hold: s the lids stay shut first (default HOLD, 0.25 when not heavy).
func play(heavy: bool = true, hold: float = -1.0) -> void:
	_hold = hold if hold >= 0.0 else (HOLD if heavy else 0.25)
	_reblink = REBLINK if heavy else 0.0
	_t = 0.0
	if not _held:
		_beat = 0.0 # waking from M29 the heart keeps its beat
	_held = false
	visible = true
	lids.visible = true
	_apply()

## M29 dormancy (fp_mutation_apply.gd): called every frame the body sleeps.
## The eyes stay shut, the heartbeat behind them runs at `rate`; play()
## then opens them. While the game is paused the Esc lids show instead.
func hold_shut(delta: float, rate: float = 1.0) -> void:
	_t = -1.0
	_held = true
	_beat += delta * rate
	visible = true
	lids.visible = true
	_mat.set_shader_parameter("close", 1.0)
	_mat.set_shader_parameter("beat", _beat)
	_mat.set_shader_parameter("rect_size", lids.get_viewport_rect().size / maxf(lids.get_viewport_rect().size.y / 720.0, 0.5))
	_mat.set_shader_parameter("glow", 0.0)

func held_shut() -> bool:
	return _held

func playing() -> bool:
	return _t >= 0.0

## 1 shut .. 0 open: held shut, opens, half closes again heavily, opens.
func shut_at(t: float) -> float:
	if t < _hold:
		return 1.0
	t -= _hold
	if t < OPEN:
		return 1.0 - smoothstep(0.0, 1.0, t / OPEN)
	t -= OPEN
	if t < _reblink * 2.0:
		return 0.55 * sin(PI * t / (_reblink * 2.0))
	return 0.0

func _process(delta: float) -> void:
	if _held:
		# the Esc screen (layer 36) closes its own lids under these
		lids.visible = not get_tree().paused
		return
	if _t < 0.0:
		return
	_t += delta
	_beat += delta
	if _t >= _hold + OPEN + _reblink * 2.0:
		_t = -1.0
		visible = false
		return
	_apply()

func _apply() -> void:
	var s := shut_at(maxf(_t, 0.0))
	_mat.set_shader_parameter("close", s)
	_mat.set_shader_parameter("beat", _beat)
	_mat.set_shader_parameter("rect_size", lids.get_viewport_rect().size / maxf(lids.get_viewport_rect().size.y / 720.0, 0.5))
	_mat.set_shader_parameter("glow", 0.0)
