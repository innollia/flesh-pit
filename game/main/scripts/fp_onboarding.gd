class_name FPOnboarding
extends Control

## Small, one-use input icons beside the hands and stomach.
const MOVE := ["fdk_move_forward", "fdk_move_left", "fdk_move_back", "fdk_move_right"]
var waiting := false
var remaining: Array[String] = []
var vomit_hint := false
## The vomit key is shown until it is used once, like the other icons (the
## stomach gauge keeps its own key prompt).
var vomit_learned := false
## The vomit key already shows elsewhere (the aim ring, the stomach gauge):
## one input is shown in one place.
var vomit_muted := false
## The open door's cue to dig (main sets it until the first cell is torn).
var eat_hint := false
## Screen spot of the flush lever before the first flush (INF = none): a
## pulsing ring with the right button beside it. The being cannot say it:
## it does not know anyone is there until it hears that flush.
var lever_at := Vector2.INF
## Over the bowl the lever is the right hand's; standing, either hand's.
var lever_left := true
## Screen spot of the mirror while the first mutation could be bought and
## none was (INF = none): the mutation screen's key cap pulses there. Buying
## happens in front of the mirror only.
var mirror_at := Vector2.INF
var _time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func reset() -> void:
	remaining.clear()
	waiting = false
	vomit_learned = false
	visible = true

func movement() -> void:
	remaining.assign(MOVE + ["fdk_eat", "fp_pick"])

func _input(event: InputEvent) -> void:
	if not visible or waiting or (event is InputEventKey and event.echo):
		return
	for action in remaining.duplicate():
		if event.is_action_pressed(action):
			remaining.erase(action)
	# only a vomit where it settles counts (V out in the flesh may just retch)
	if event.is_action_pressed("fp_vomit") and vomit_hint:
		vomit_hint = false
		vomit_learned = true

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.77)
	var alpha := 0.45 + 0.55 * (sin(_time * 5.0) * 0.5 + 0.5) if waiting else 0.9
	if waiting or remaining.has(MOVE[0]):
		_icon(c, _key(MOVE[0], "W"), alpha)
	if not waiting:
		for i in range(1, 4):
			if remaining.has(MOVE[i]):
				_icon(c + Vector2((i - 2) * 42, 42), _key(MOVE[i], ["A", "S", "D"][i - 1]), 0.9)
		if remaining.has("fdk_eat") or remaining.has("fp_pick"):
			FPMenuKit.draw_mouse(self, c + Vector2(118, 24), remaining.has("fdk_eat"), remaining.has("fp_pick"), 0.9)
	var pulse := 0.45 + 0.55 * (sin(_time * 5.0) * 0.5 + 0.5)
	if vomit_hint and not vomit_learned and not vomit_muted:
		_icon(Vector2(size.x * 0.5, size.y * 0.88), _key("fp_vomit", "V"), pulse)
	if lever_at.is_finite():
		var r := 15.0 + 4.0 * pulse
		draw_arc(lever_at, r + 2.0, 0.0, TAU, 40, Color(0.08, 0.07, 0.07, 0.6 * pulse), 5.0, true)
		draw_arc(lever_at, r, 0.0, TAU, 40, Color(0.96, 0.93, 0.88, pulse), 2.5, true)
		FPMenuKit.draw_mouse(self, lever_at + Vector2(r + 26.0, 22.0), lever_left, true, pulse)
	elif mirror_at.is_finite():
		_icon(mirror_at, _key("fp_mutate", "Tab"), pulse)
	elif eat_hint and not waiting:
		# above the subtitle band: the being may be talking while the door opens
		FPMenuKit.draw_mouse(self, Vector2(size.x * 0.5, size.y * 0.68), true, false, pulse)

func _key(action: String, fallback: String) -> String:
	var key := FPKeybindMenu.key_of(action)
	return fallback if key == "" else key

## Tooth-coloured key caps, like the stomach and interaction prompts.
func _icon(center: Vector2, text: String, alpha: float) -> void:
	FPMenuKit.draw_key(self, center, text, alpha, 17)
