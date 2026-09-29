class_name FPMirror
extends CanvasLayer

## Mirror mutation screen (design-core 5/6), placeholder shapes only.
## Hover/focus a body part to list the mutations possible there; press one
## to spend arm hairs. Works with mouse alone (hover + click) and keyboard
## alone (arrows/Tab + Enter, Esc closes). Costs are never shown as numbers:
## an affordable mutation is bright, an unaffordable one is dim.

signal closed
signal mutated(id: String)

var prog: FPProgression
var _root: Control
var _parts: HBoxContainer
var _list: VBoxContainer
var _part: String = ""

func _ready() -> void:
	layer = 6
	_root = PanelContainer.new()
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.custom_minimum_size = Vector2(620, 380)
	_root.position = Vector2(-310, -190)
	add_child(_root)
	var v := VBoxContainer.new()
	_root.add_child(v)
	_parts = HBoxContainer.new()
	v.add_child(_parts)
	_list = VBoxContainer.new()
	v.add_child(_list)
	visible = false

func open(p: FPProgression) -> void:
	prog = p
	visible = true
	for c in _parts.get_children():
		c.queue_free()
	var first: Button = null
	for part in FPProgression.PARTS + ["tumor"]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(110, 60)
		b.tooltip_text = part
		b.set_meta("part", part)
		b.mouse_entered.connect(func(): show_part(part))
		b.focus_entered.connect(func(): show_part(part))
		b.pressed.connect(func(): show_part(part))
		_parts.add_child(b)
		if first == null:
			first = b
	show_part(FPProgression.PARTS[0])
	if first != null:
		first.grab_focus()

func close() -> void:
	visible = false
	closed.emit()

func show_part(part: String) -> void:
	_part = part
	for c in _list.get_children():
		c.queue_free()
		_list.remove_child(c)
	if prog == null:
		return
	if part == "tumor":
		var t := Button.new()
		t.custom_minimum_size = Vector2(0, 44)
		t.disabled = prog.tumors.tumor_points < FPProgression.TUMOR_MUTATION_COST
		t.pressed.connect(func():
			var got := prog.buy_tumor_mutation()
			if got != "":
				mutated.emit(got)
			show_part("tumor"))
		_list.add_child(t)
		return
	for id in prog.mutations_for_part(part):
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 30)
		b.tooltip_text = id
		var owned := prog.mutation_tree.is_purchased(id)
		b.disabled = owned or not prog.can_buy_mutation(id)
		b.modulate = Color(0.5, 0.9, 0.5) if owned else (Color.WHITE if not b.disabled else Color(0.5, 0.5, 0.5))
		b.pressed.connect(func():
			if prog.buy_mutation(id):
				mutated.emit(id)
			show_part(part))
		_list.add_child(b)

func listed_ids() -> Array[String]:
	var out: Array[String] = []
	for c in _list.get_children():
		if c.tooltip_text != "":
			out.append(c.tooltip_text)
	return out

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
