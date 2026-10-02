class_name FPOpening
extends CanvasLayer

## Opening (spec 03 §3, spec 10 0:00): black screen with the flush sound,
## then fades in seated. Main holds the seated phase until forward input,
## then advances the rise animation. The input icons live on this layer.
## main.gd drives the timeline; this node only owns the black cover and the
## phase math so it can be captured and tested on its own.

const BLACK_TIME := 1.6   # full black while the flush plays
const FADE_TIME := 0.7    # black fades away, still seated
const RISE_TIME := 1.6    # stand up from the seat
const TOTAL := BLACK_TIME + FADE_TIME + RISE_TIME

var cover: ColorRect
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
	cover.color.a = black_at(t)
	visible = true

func done() -> void:
	cover.color.a = 0.0
	visible = true
