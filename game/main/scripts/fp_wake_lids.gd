extends CanvasLayer

## Waking in the restroom after a death (spec 07: the player wakes there):
## the eyes start shut, the room is red light through the lids for a
## heartbeat or two, then they open with a slow, heavy blink. Same lids as
## the Esc screen (fp_pause_lids.gdshader). Input passes through.

const HOLD := 0.9
const OPEN := 0.55
const REBLINK := 0.35

var lids: ColorRect
var _mat: ShaderMaterial
var _t := -1.0
var _beat := 0.0

func _ready() -> void:
	layer = 34
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

func play() -> void:
	_t = 0.0
	_beat = 0.0
	visible = true
	_apply()

func playing() -> bool:
	return _t >= 0.0

## 1 shut .. 0 open: held shut, opens, half closes again heavily, opens.
func shut_at(t: float) -> float:
	if t < HOLD:
		return 1.0
	t -= HOLD
	if t < OPEN:
		return 1.0 - smoothstep(0.0, 1.0, t / OPEN)
	t -= OPEN
	if t < REBLINK * 2.0:
		return 0.55 * sin(PI * t / (REBLINK * 2.0))
	return 0.0

func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	_beat += delta
	if _t >= HOLD + OPEN + REBLINK * 2.0:
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
