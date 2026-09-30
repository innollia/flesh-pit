class_name FPMirror
extends CanvasLayer

## Mirror mutation screen (docs/spec/03-restroom.md 8, 05-mutations.md).
## Interacting with the mirror keeps the first-person view: the left arm comes
## up like reading a wristwatch and the glass panel on the right shows your
## whole body. Parts that can still mutate shimmer (an enchant-like glint) without
## hovering. Hovering a part lays a translucent ghost of that part's next
## mutation over the body; small chips under the glass switch between the
## part's mutations. Clicking a part (or a chip) buys it: the hairs fall off
## the arm and the body changes. Not enough hairs: the part blinks red.
## Tumor bumps on the belly are pressed the same way for a random tumor
## mutation. Keyboard only: Left/Right move between parts, Up/Down switch
## the mutation, Enter buys, Esc leaves. No text, no numbers.

signal closed
signal mutated(id: String)
signal denied(part: String)

const POOL_COLOR := {
	"common": Color(0.12, 0.1, 0.1),
	"core": Color(0.95, 0.35, 0.55),
	"mantle": Color(0.5, 0.3, 0.62),
	"surface": Color(0.95, 0.85, 0.3),
}
const HOVER_PX := 60.0
## Glass panel in screen fractions (right side, full body visible).
const GLASS_RECT := Rect2(0.62, 0.05, 0.34, 0.78)

var prog: FPProgression
var body: FPMirrorBody
var cam: Camera3D
var _root: Control
var glass: Control
var _vpc: SubViewportContainer
var _vp: SubViewport
var _chips: HBoxContainer
var _part: String = ""
var _cand: Dictionary = {} ## part -> index into mutations_for_part
var _ghost: Node3D
var _ghost_id := ""
var _order: Array[String] = []

func _ready() -> void:
	layer = 6
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# The first-person view stays on screen; the glass is a panel on the right
	# (the left arm is raised like reading a wristwatch, fp_hand_motions watch).
	glass = Control.new()
	glass.name = "Glass"
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.anchor_left = GLASS_RECT.position.x
	glass.anchor_top = GLASS_RECT.position.y
	glass.anchor_right = GLASS_RECT.end.x
	glass.anchor_bottom = GLASS_RECT.end.y
	_root.add_child(glass)
	var bg := ColorRect.new()
	bg.color = Color(0.72, 0.74, 0.77)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.add_child(bg)
	_vpc = SubViewportContainer.new()
	_vpc.stretch = true
	_vpc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vpc.offset_left = 8
	_vpc.offset_right = -8
	_vpc.offset_top = 8
	_vpc.offset_bottom = -8
	_vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.add_child(_vpc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	_vpc.add_child(_vp)
	_build_room()
	_chips = HBoxContainer.new()
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips.anchor_left = GLASS_RECT.position.x
	_chips.anchor_right = GLASS_RECT.end.x
	_chips.anchor_top = GLASS_RECT.end.y
	_chips.anchor_bottom = GLASS_RECT.end.y
	_chips.offset_top = 10
	_chips.offset_bottom = 58
	_chips.add_theme_constant_override("separation", 14)
	_root.add_child(_chips)
	visible = false

func _build_room() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.72, 0.78, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.9)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var light := OmniLight3D.new()
	light.position = Vector3(0.2, 2.3, 1.2)
	light.light_energy = 1.6
	light.omni_range = 5.0
	_vp.add_child(light)
	var K := preload("res://main/art/fp_art_kit.gd")
	var wall := Node3D.new()
	_vp.add_child(wall)
	var st := K.begin()
	K.quad(st, Transform3D.IDENTITY, Vector3(-3, -0.2, -0.6), Vector3(3, -0.2, -0.6), Vector3(3, 2.6, -0.6), Vector3(-3, 2.6, -0.6), Vector3.BACK, Color(0.9, 0.92, 0.93))
	K.add_mesh(wall, "BackWall", K.finish(st, 3.0), K.mat("tex_tile_wall_128.png", 0.2, false))
	body = FPMirrorBody.new()
	body.name = "Body"
	_vp.add_child(body)
	cam = Camera3D.new()
	cam.fov = 44.0
	cam.position = Vector3(0, 0.95, 2.75)
	_vp.add_child(cam)
	cam.look_at(Vector3(0, 0.93, 0), Vector3.UP)
	cam.current = true

func open(p: FPProgression) -> void:
	prog = p
	visible = true
	_cand.clear()
	refresh()
	var first := ""
	for part in _order:
		if part_available(part):
			first = part
			break
	focus_part(first if first != "" else (_order[0] if not _order.is_empty() else ""))

func close() -> void:
	visible = false
	_clear_ghost()
	closed.emit()

## Rebuild body shape and shimmer after a change.
func refresh() -> void:
	if prog == null:
		return
	body.apply(prog.all_mutations(), prog.belly_bumps())
	_order.clear()
	for part in FPProgression.PARTS:
		if not prog.mutations_for_part(part).is_empty():
			_order.append(part)
	if prog.belly_bumps() > 0:
		_order.append("tumor")
	for part in FPProgression.PARTS:
		body.set_shimmer(part, part_available(part) or (part == "belly" and part_available("tumor")))

## A part shimmers while it still has a mutation to take (affordable or not;
## the red blink tells the difference when pressed).
func part_available(part: String) -> bool:
	if prog == null:
		return false
	if part == "tumor":
		return prog.belly_bumps() > 0 and prog.tumor_mutations.size() < FPProgression.TUMOR_MUTATIONS.size()
	for id in prog.mutations_for_part(part):
		if not prog.mutation_tree.is_purchased(id):
			return true
	return false

func _open_ids(part: String) -> Array[String]:
	var out: Array[String] = []
	if prog == null:
		return out
	for id in prog.mutations_for_part(part):
		if not prog.mutation_tree.is_purchased(id):
			out.append(id)
	return out

func candidate(part: String = "") -> String:
	if part == "":
		part = _part
	if part == "tumor":
		return "tumor"
	var ids := _open_ids(part)
	if ids.is_empty():
		return ""
	return ids[clampi(int(_cand.get(part, 0)), 0, ids.size() - 1)]

func current_part() -> String:
	return _part

## Kept for callers/tests: show a part (hover/focus).
func show_part(part: String) -> void:
	focus_part(part)

func focus_part(part: String) -> void:
	_part = part
	_rebuild_chips()
	_show_ghost(candidate())

func listed_ids() -> Array[String]:
	return prog.mutations_for_part(_part) if prog != null and _part != "tumor" else ([] as Array[String])

func _rebuild_chips() -> void:
	for c in _chips.get_children():
		_chips.remove_child(c)
		c.queue_free()
	if prog == null or _part == "" or _part == "tumor":
		return
	var ids := _open_ids(_part)
	for i in range(ids.size()):
		var id := ids[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		b.focus_mode = Control.FOCUS_NONE
		b.set_meta("mut_id", id)
		var sb := StyleBoxFlat.new()
		var pools: Array = prog.mutation_info[id]["alt"] if not (prog.mutation_info[id]["alt"] as Array).is_empty() else [prog.mutation_info[id]["pool"]]
		sb.bg_color = POOL_COLOR.get(pools[0], Color.GRAY)
		if pools.size() > 1:
			sb.border_color = POOL_COLOR.get(pools[1], Color.GRAY)
			sb.set_border_width_all(6)
		sb.set_corner_radius_all(22)
		if not prog.can_buy_mutation(id):
			sb.bg_color = sb.bg_color.lerp(Color(0.6, 0.6, 0.6), 0.55)
		var sel := StyleBoxFlat.new()
		sel.bg_color = sb.bg_color
		sel.border_color = Color(1, 1, 1)
		sel.set_border_width_all(4)
		sel.set_corner_radius_all(22)
		var is_sel := i == clampi(int(_cand.get(_part, 0)), 0, ids.size() - 1)
		b.add_theme_stylebox_override("normal", sel if is_sel else sb)
		b.add_theme_stylebox_override("hover", sel)
		b.add_theme_stylebox_override("pressed", sel)
		b.mouse_entered.connect(func(): select_candidate(i, false))
		b.pressed.connect(func():
			select_candidate(i, false)
			buy_current())
		_chips.add_child(b)

func select_candidate(i: int, rebuild: bool = true) -> void:
	var n := _open_ids(_part).size()
	if n == 0:
		return
	_cand[_part] = posmod(i, n)
	if rebuild:
		_rebuild_chips()
	else:
		for k in range(_chips.get_child_count()):
			var b := _chips.get_child(k) as Button
			var st: StyleBoxFlat = (b.get_theme_stylebox("hover") as StyleBoxFlat)
			b.add_theme_stylebox_override("normal", st if k == _cand[_part] else _chip_style(b))
	_show_ghost(candidate())

func _chip_style(b: Button) -> StyleBox:
	var id: String = b.get_meta("mut_id")
	var sb := StyleBoxFlat.new()
	var info: Dictionary = prog.mutation_info[id]
	var pools: Array = info["alt"] if not (info["alt"] as Array).is_empty() else [info["pool"]]
	sb.bg_color = POOL_COLOR.get(pools[0], Color.GRAY)
	if not prog.can_buy_mutation(id):
		sb.bg_color = sb.bg_color.lerp(Color(0.6, 0.6, 0.6), 0.55)
	if pools.size() > 1:
		sb.border_color = POOL_COLOR.get(pools[1], Color.GRAY)
		sb.set_border_width_all(6)
	sb.set_corner_radius_all(22)
	return sb

func _clear_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_ghost_id = ""

func _show_ghost(id: String) -> void:
	if id == _ghost_id:
		return
	_clear_ghost()
	if id == "" or id == "tumor" or body == null:
		return
	_ghost = body.ghost(id)
	_ghost_id = id

func ghost_id() -> String:
	return _ghost_id

## Buy the focused part's current mutation. Returns the id bought or "".
func buy_current() -> String:
	if prog == null or _part == "":
		return ""
	if _part == "tumor":
		var got := prog.buy_tumor_mutation()
		if got == "":
			body.blink_red("belly")
			denied.emit("tumor")
			return ""
		_after_buy(got)
		return got
	var id := candidate()
	if id == "" or not prog.can_buy_mutation(id):
		body.blink_red(_part)
		denied.emit(_part)
		return ""
	prog.buy_mutation(id)
	_after_buy(id)
	return id

func _after_buy(id: String) -> void:
	_clear_ghost()
	mutated.emit(id)
	refresh()
	if not part_available(_part):
		for p in _order:
			if part_available(p):
				focus_part(p)
				return
	focus_part(_part)

func _move_part(step: int) -> void:
	if _order.is_empty():
		return
	var i := _order.find(_part)
	focus_part(_order[posmod(i + step, _order.size())])

## Part under a screen point (nearest projected part centre).
func part_at(screen: Vector2) -> String:
	var local := screen - _vpc.get_global_rect().position
	local *= Vector2(_vp.size) / _vpc.get_global_rect().size
	var best := ""
	var bd := HOVER_PX
	for part in _order:
		var c := body.part_center(part)
		if cam.is_position_behind(c):
			continue
		var d := cam.unproject_position(c).distance_to(local)
		if d < bd:
			bd = d
			best = part
	return best

## Screen point of a part (tests, captures).
func part_screen(part: String) -> Vector2:
	var p := cam.unproject_position(body.part_center(part))
	return _vpc.get_global_rect().position + p * _vpc.get_global_rect().size / Vector2(_vp.size)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var p := part_at((event as InputEventMouseMotion).position)
		if p != "" and p != _part:
			focus_part(p)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var p := part_at(mb.position)
			if p != "":
				focus_part(p)
				buy_current()
				get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_candidate(int(_cand.get(_part, 0)) - 1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_candidate(int(_cand.get(_part, 0)) + 1)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			close()
	elif event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_focus_next"):
		_move_part(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_focus_prev"):
		_move_part(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		select_candidate(int(_cand.get(_part, 0)) + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		select_candidate(int(_cand.get(_part, 0)) - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		buy_current()
		get_viewport().set_input_as_handled()
