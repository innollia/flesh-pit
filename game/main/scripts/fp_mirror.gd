class_name FPMirror
extends CanvasLayer

## Mutation screen on the forearm (형님 2026-09-30, replaces the mirror
## screen; the mirror itself only reflects, FPMirrorReflection).
## A key (fp_mutate: Tab / pad button, rebindable) opens it anywhere: the
## left arm comes up like reading a wristwatch and a small whole-body doll
## (FPMirrorBody) stands on the forearm. The background is dimmed about 70%;
## the arm and the doll are drawn again above the dim by a second camera on
## HOLO_LAYER, so only they and the arm hairs read clearly. While open the
## cursor shows, the view does not turn and the player does not move.
## Hovering a doll part (or Left/Right) highlights it and opens a list panel
## beside it: each mutation's name, a one-line effect, the cost in hair kind
## + count (both kinds for a combination). Unaffordable rows are faded.
## Hovering a row (or Up/Down, or the wheel) grows that mutation as a ghost
## on the doll; clicking (or Enter) buys it: the doll and the real body
## change at once. Not enough hairs: the part blinks red (denied). The
## candidate picked per part is remembered while open. Tumor bumps on the
## belly are bought the same way (a random tumor mutation). Same key, Esc
## or RMB closes.
## Kept from the mirror screen: closed / mutated / denied signals, part
## shimmer, ghost preview, red blink, per-part candidate memory, focus of
## the next open part after a buy, keyboard-only use.

signal closed
signal mutated(id: String)
signal denied(part: String)

const POOL_COLOR := {
	"common": Color(0.2, 0.16, 0.15),
	"core": Color(0.95, 0.35, 0.55),
	"mantle": Color(0.5, 0.3, 0.62),
	"surface": Color(0.95, 0.85, 0.3),
}
const POOL_NAME := {"common": "검은 털", "core": "분홍 털", "mantle": "보라 털", "surface": "노란 털"}
const PART_NAME := {"face": "머리", "neck": "목", "chest": "가슴·어깨", "belly": "배", "right_hand": "오른손·팔", "left_hand": "왼손·팔", "arms": "팔다리", "whole": "온몸", "tumor": "배의 혹"}
## One-line effect per mutation (docs/spec/05-mutations.md, shortened).
const DESC := {
	"M01": "위장이 커진다 (용량 +20)", "M02": "넘치게 먹어도 덜 느려진다",
	"M03": "화장실 쪽에서 귀가 윙 울린다", "M04": "씹는 시간이 15% 줄어든다",
	"M05": "좁은 곳에서 몸이 가늘어진다", "M06": "파묻혀도 3초 더 버틴다",
	"M07": "한 번에 한 칸 더 뜯는다", "M08": "딱딱한 살이 30% 물러진다",
	"M09": "맨손으로 막을 잡는다 (씹기 느림)", "M10": "손이 0.4 m 더 멀리 닿는다",
	"M12": "아주 단단한 살을 절반만큼 쉽게", "M13": "살을 1.5배 더 든다",
	"M14": "한 칸 더 뜯지만 조금 느려진다", "M15": "살 더미를 3초에 통째로 삼킨다",
	"M16": "위장 속 살이 60초마다 10% 줄어든다", "M17": "받는 피해가 절반, 멍이 안 보인다",
	"M18": "질긴 살이 40% 물러진다", "M19": "눌릴수록 오히려 빨라진다",
	"M20": "눌려도 느려지지 않는다", "M21": "믹서기가 왼손에서 저절로 충전된다",
	"M22": "가만히 서면 왼손이 멋대로 뜯어 먹는다", "M23": "수축 1.5초 전에 팔 털이 떨린다",
	"M24": "손전등이 1.6배 넓게 비춘다", "M25": "죽은 자리 표시가 계속 따라온다",
	"M26": "몸이 3배 빨리 회복된다", "M27": "가까운 종양 쪽으로 코끝이 씰룩인다",
	"M28": "살 더미를 든 채 두 손 도구를 쓴다", "M29": "압사해도 30초 뒤 화장실에서 깬다",
	"M30": "넘치는 위장이 40 더 늘어난다",
}
const HOVER_PX := 40.0 ## at 720 p; scaled with the window height
const DIM := 0.7
## Doll layer: drawn by the eye camera AND by the overlay camera above the dim.
const HOLO_LAYER := 1 << 14
const DOLL_SCALE := 0.1
## Doll feet on the forearm, in the left hand root's space (the forearm runs
## toward +Z = the elbow, the hairy top faces +Y).
const DOLL_ON_ARM := Vector3(0.0, 0.035, 0.13)

var prog: FPProgression
var body: FPMirrorBody ## the doll
var eye: Camera3D
var hand_root: Node3D ## left hand root of the rig (doll stands on its forearm)
var holo_nodes: Array[Node] = [] ## nodes drawn above the dim while open
var _root: Control
var _dim: ColorRect
var _vp: SubViewport
var _over: TextureRect
var ocam: Camera3D
var panel: PanelContainer
var _list: VBoxContainer
var _title: Label
var _rows: Array[Button] = []
var _part: String = ""
var _cand: Dictionary = {} ## part -> index into the part's open ids
var _ghost: Node3D
var _ghost_id := ""
var _order: Array[String] = []
var _kb := false ## keyboard picked the focus: mouse hover waits for motion

func _ready() -> void:
	layer = 6
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0, 0, 0, DIM)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)
	_vp = SubViewport.new()
	_vp.name = "HoloView"
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	ocam = Camera3D.new()
	ocam.name = "HoloCamera"
	ocam.cull_mask = HOLO_LAYER
	_vp.add_child(ocam)
	ocam.current = true
	_over = TextureRect.new()
	_over.name = "Holo"
	_over.texture = _vp.get_texture()
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.stretch_mode = TextureRect.STRETCH_SCALE
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_over)
	panel = PanelContainer.new()
	panel.name = "List"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.06, 0.88)
	sb.border_color = Color(0.85, 0.8, 0.75, 0.6)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	_title = Label.new()
	vb.add_child(_title)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	vb.add_child(_list)
	_root.add_child(panel)
	panel.visible = false
	visible = false
	_build_doll()

func _build_doll() -> void:
	body = FPMirrorBody.new()
	body.name = "Doll"
	add_child(body) # top-level 3D node in the main world; placed each frame
	body.build()
	body.scale = Vector3.ONE * DOLL_SCALE
	body.visible = false
	tag_layer(body, HOLO_LAYER)

## Main wires the camera and the arm the doll stands on.
func setup(eye_cam: Camera3D, left_hand_root: Node3D, holo: Array[Node]) -> void:
	eye = eye_cam
	hand_root = left_hand_root
	holo_nodes = holo

static func tag_layer(n: Node, bits: int) -> void:
	if n is VisualInstance3D and not (n is Light3D):
		(n as VisualInstance3D).layers = bits
		if n is GeometryInstance3D and bits != 1 and bits != FPRestroom.ROOM_VISUAL_LAYER:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		tag_layer(c, bits)

func _ui_scale() -> float:
	return clampf(get_viewport().get_visible_rect().size.y / 720.0, 1.0, 2.0) if get_viewport() != null else 1.0

func open(p: FPProgression) -> void:
	prog = p
	visible = true
	body.visible = true
	_cand.clear()
	_kb = false
	for n in holo_nodes:
		tag_layer(n, HOLO_LAYER)
	refresh()
	_place()
	var first := ""
	for part in _order:
		if part_available(part):
			first = part
			break
	focus_part(first if first != "" else (_order[0] if not _order.is_empty() else ""))

func close() -> void:
	visible = false
	body.visible = false
	panel.visible = false
	_clear_ghost()
	closed.emit()

## Rebuild the doll's shape and shimmer after a change.
func refresh() -> void:
	if prog == null:
		return
	body.apply(prog.all_mutations(), prog.belly_bumps())
	if body._belt != null:
		body._belt.call("set_worn", prog.has_belt)
	tag_layer(body, HOLO_LAYER)
	_order.clear()
	for part in FPProgression.PARTS:
		if not prog.mutations_for_part(part).is_empty():
			_order.append(part)
	if prog.belly_bumps() > 0:
		_order.append("tumor")
	_update_glow()

## Parts that can still mutate shimmer faintly; the focused part strongly.
func _update_glow() -> void:
	for part in FPProgression.PARTS:
		var avail := part_available(part) or (part == "belly" and part_available("tumor"))
		var sel := part == _part or (part == "belly" and _part == "tumor")
		body.set_shimmer(part, avail or sel, 1.4 if sel else 0.45)

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
	if prog == null or part == "tumor":
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

func show_part(part: String) -> void:
	focus_part(part)

func focus_part(part: String) -> void:
	_part = part
	_update_glow()
	_rebuild_list()
	_show_ghost(candidate())

func listed_ids() -> Array[String]:
	return prog.mutations_for_part(_part) if prog != null and _part != "tumor" else ([] as Array[String])

# --- list panel ---------------------------------------------------------------

## Cost text: hair kind + count; a combination shows both kinds.
func cost_text(id: String) -> String:
	if id == "tumor":
		return "비용: 배의 혹 1개"
	var info: Dictionary = prog.mutation_info[id]
	var pools: Array = info["alt"] if not (info["alt"] as Array).is_empty() else [info["pool"]]
	var parts: Array[String] = []
	for p in pools:
		parts.append("%s %d개" % [POOL_NAME.get(p, p), prog.cost_in(id, p)])
	return "비용: " + " 또는 ".join(parts)

func rows() -> Array[Button]:
	return _rows

func _rebuild_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	if prog == null or _part == "":
		panel.visible = false
		return
	var s := _ui_scale()
	_title.text = PART_NAME.get(_part, _part)
	_title.add_theme_font_size_override("font_size", int(20 * s))
	var ids: Array[String] = []
	if _part == "tumor":
		ids.append("tumor")
	else:
		ids = _open_ids(_part)
	for i in range(ids.size()):
		var id := ids[i]
		var b := Button.new()
		b.set_meta("mut_id", id)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		var nm: String = "무작위 종양 변이" if id == "tumor" else String(prog.mutation_info[id]["name"])
		var ds: String = "혹을 눌러 무작위 큰 변이를 얻는다" if id == "tumor" else String(DESC.get(id, ""))
		b.text = "%s\n%s\n%s" % [nm, ds, cost_text(id)]
		b.add_theme_font_size_override("font_size", int(16 * s))
		b.custom_minimum_size = Vector2(300 * s, 0)
		var ok := part_available("tumor") if id == "tumor" else prog.can_buy_mutation(id)
		b.set_meta("afford", ok)
		b.modulate = Color(1, 1, 1, 1.0 if ok else 0.45)
		b.mouse_entered.connect(func():
			_kb = false
			select_candidate(i))
		b.pressed.connect(func():
			select_candidate(i)
			buy_current())
		_list.add_child(b)
		_rows.append(b)
	_style_rows()
	panel.visible = true
	_place_panel()

func _row_style(on: bool, pool_col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.12, 0.13, 0.9) if not on else Color(0.3, 0.26, 0.26, 0.95)
	sb.border_color = Color(1, 1, 1) if on else pool_col
	sb.border_width_left = 8
	sb.set_border_width_all(3 if on else 0)
	sb.border_width_left = 8
	sb.set_content_margin_all(8)
	return sb

func _style_rows() -> void:
	var sel := clampi(int(_cand.get(_part, 0)), 0, maxi(_rows.size() - 1, 0))
	for k in range(_rows.size()):
		var b := _rows[k]
		var id: String = b.get_meta("mut_id")
		var pc: Color = POOL_COLOR["core"] if id == "tumor" else POOL_COLOR.get(prog.mutation_info[id]["pool"], Color.GRAY)
		var st := _row_style(k == sel, pc)
		for n in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(n, st if n != "hover" else _row_style(true, pc))

func selected_row() -> int:
	return clampi(int(_cand.get(_part, 0)), 0, maxi(_rows.size() - 1, 0))

func _place_panel() -> void:
	if not panel.visible or eye == null or _part == "":
		return
	var vs := get_viewport().get_visible_rect().size
	var p := part_screen(_part)
	panel.reset_size()
	var sz := panel.get_combined_minimum_size()
	var x := p.x + 40.0 * _ui_scale()
	if x + sz.x > vs.x - 10.0:
		x = p.x - 40.0 * _ui_scale() - sz.x
	panel.position = Vector2(clampf(x, 10.0, maxf(10.0, vs.x - sz.x - 10.0)), clampf(p.y - sz.y * 0.5, 10.0, maxf(10.0, vs.y - sz.y - 10.0)))

func select_candidate(i: int, _rebuild: bool = true) -> void:
	var n := _open_ids(_part).size()
	if n == 0:
		return
	_cand[_part] = posmod(i, n)
	_style_rows()
	_show_ghost(candidate())

# --- ghost / buying (unchanged behaviour) ----------------------------------

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
	tag_layer(_ghost, HOLO_LAYER)
	_ghost_id = id

func ghost_id() -> String:
	return _ghost_id

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

# --- placing the doll, aiming --------------------------------------------------

func _place() -> void:
	if eye == null or hand_root == null:
		return
	var feet := hand_root.global_transform * DOLL_ON_ARM
	# upright, facing the eye
	var to_eye := eye.global_position - feet
	to_eye.y = 0.0
	var z := to_eye.normalized() if to_eye.length() > 0.001 else Vector3.BACK
	var x := Vector3.UP.cross(z).normalized()
	body.global_transform = Transform3D(Basis(x, Vector3.UP, z).scaled(Vector3.ONE * DOLL_SCALE), feet)
	ocam.global_transform = eye.global_transform
	ocam.fov = eye.fov
	ocam.near = eye.near
	ocam.far = eye.far
	var vs := Vector2i(get_viewport().get_visible_rect().size)
	if _vp.size != vs:
		_vp.size = vs

func part_at(screen: Vector2) -> String:
	if eye == null:
		return ""
	var best := ""
	var bd := HOVER_PX * _ui_scale()
	for part in _order:
		var c := body.part_center(part)
		if eye.is_position_behind(c):
			continue
		var d := eye.unproject_position(c).distance_to(screen)
		if d < bd:
			bd = d
			best = part
	return best

func part_screen(part: String) -> Vector2:
	return eye.unproject_position(body.part_center(part)) if eye != null else Vector2.ZERO

func _process(_delta: float) -> void:
	if not visible:
		return
	_place()
	_place_panel()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var mp := (event as InputEventMouseMotion).position
		_kb = false
		if panel.visible and panel.get_global_rect().has_point(mp):
			return
		var p := part_at(mp)
		if p != "" and p != _part:
			focus_part(p)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if panel.visible and panel.get_global_rect().has_point(mb.position):
				return # the row button buys
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
	elif event.is_action_pressed("ui_cancel") or (InputMap.has_action("fp_mutate") and event.is_action_pressed("fp_mutate")):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_kb = true
		_move_part(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_kb = true
		_move_part(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_kb = true
		select_candidate(int(_cand.get(_part, 0)) + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_kb = true
		select_candidate(int(_cand.get(_part, 0)) - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		buy_current()
		get_viewport().set_input_as_handled()