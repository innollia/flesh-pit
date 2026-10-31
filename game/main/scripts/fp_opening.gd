class_name FPOpening
extends CanvasLayer

## Opening (spec 03 §3, spec 10 0:00): eyes shut with the flush sound (the
## Esc screen's lids, fp_pause_lids.gdshader: the room only as red light
## through the skin), then they open, seated. It is also what loading a run
## looks like (title → continue / new game). Main holds the seated phase
## until forward input, then advances the rise animation. The input icons
## live on this layer. main.gd drives the timeline; this node only owns the
## lids cover and the phase math so it can be captured and tested on its own.

const BLACK_TIME := 1.6   # eyes shut while the flush plays
const FADE_TIME := 0.7    # the eyes open, still seated
const RISE_TIME := 1.6    # stand up from the seat
const TOTAL := BLACK_TIME + FADE_TIME + RISE_TIME

var cover: ColorRect
var _lids: ShaderMaterial
var hints: FPOnboarding
var waiting_to_rise := false:
	set(value):
		waiting_to_rise = value
		if hints != null:
			hints.waiting = value

func _ready() -> void:
	layer = 30
	cover = ColorRect.new()
	cover.name = "Black"
	cover.color = Color(0, 0, 0, 1)
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lids = ShaderMaterial.new()
	_lids.shader = load("res://main/scripts/fp_pause_lids.gdshader")
	cover.material = _lids
	add_child(cover)
	hints = FPOnboarding.new()
	add_child(hints)

func start_hints() -> void:
	hints.reset()

func show_movement_hints() -> void:
	hints.movement()

## Black cover opacity at time t (1 = black).
static func black_at(t: float) -> float:
	if t < BLACK_TIME:
		return 1.0
	return clampf(1.0 - (t - BLACK_TIME) / FADE_TIME, 0.0, 1.0)

## 0 = seated, 1 = standing, eased.
static func rise_at(t: float) -> float:
	var k := clampf((t - BLACK_TIME - FADE_TIME) / RISE_TIME, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)

func apply(t: float) -> void:
	_shut(black_at(t))
	visible = true

func done() -> void:
	_shut(0.0)
	visible = true

## Eye mutations shut differently (FPPauseMenu.apply_eyes).
func set_eyes(ids: Array, field_angle: float = 0.0) -> void:
	FPPauseMenu.apply_eyes(_lids, ids, field_angle)

## 1 = shut (cover.color.a keeps the old black-cover reading for checks).
func _shut(k: float) -> void:
	cover.color.a = k
	cover.visible = k > 0.0
	_lids.set_shader_parameter("close", k * k * (3.0 - 2.0 * k))
	_lids.set_shader_parameter("beat", float(Time.get_ticks_msec()) / 1000.0)
	_lids.set_shader_parameter("rect_size", cover.get_viewport_rect().size / maxf(cover.get_viewport_rect().size.y / 720.0, 0.5))
	_lids.set_shader_parameter("glow", 0.0)
