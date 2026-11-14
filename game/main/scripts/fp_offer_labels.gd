class_name FPOfferLabels
extends CanvasLayer

## Small tags over the items the vent being holds out (user 2026-11-09:
## "거래시 물건 받을때는 물건마다 위에 이게 뭐하는 놈인지랑 개수 정도는
## 띄워주자"). Each tag sits just above its item on screen: the name and how
## many of it the player would get, then what it does. Shown only while the
## offer is held out, hidden otherwise. Reads the vent; changes nothing.
## Text comes from res://main/data/vent_item_labels.json.

const DATA_PATH := "res://main/data/vent_item_labels.json"
## The offer counts as held out from this far along its way down.
const SHOW_EXTEND := 0.9
## No tags from farther than this (m) from the items.
const MAX_DIST := 2.5
## Gap (px at 720 lines) between the item's top and its tag.
const GAP := 6.0
const PAD := 4.0

var vent: FPVent
var _root: Control
var _tags: Array[PanelContainer] = []
var _shown_ids: Array[String] = []
static var _data: Dictionary = {}

func _ready() -> void:
	layer = 21
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

static func _labels() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary and d.get("물건") is Dictionary:
				_data = d["물건"]
	return _data

## Item name from the data file (the id when it has none).
static func item_name(id: String) -> String:
	var e = _labels().get(id, {})
	return str(e.get("이름", id)) if e is Dictionary else id

## What the item does, as written in the data file. An item whose line is
## not written yet has none and its tag is the name alone: the placeholder
## key is a note for whoever writes the line, never something on screen.
static func item_use(id: String) -> String:
	var e = _labels().get(id, {})
	if not e is Dictionary:
		return ""
	return str(e.get("하는일", ""))

## The key the item's line is filed under (data only, never drawn).
static func item_use_key(id: String) -> String:
	var e = _labels().get(id, {})
	return str(e.get("하는일_키", "")) if e is Dictionary else ""

## How many of `id` taking it from this offer gives (one grant per offered id).
static func count_for(offers: Array, id: String) -> int:
	return offers.count(id)

## First line of a tag: name and count.
static func head_text(offers: Array, id: String) -> String:
	return "%s ×%d" % [item_name(id), count_for(offers, id)]

func tags_shown() -> int:
	var n := 0
	for t in _tags:
		if t.visible:
			n += 1
	return n

## Screen rects of the shown tags (index = offer index).
func tag_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for t in _tags:
		if t.visible:
			out.append(Rect2(t.position, t.size))
	return out

## The lines tag `i` shows (a line it hides is not one of them).
func tag_texts(i: int) -> PackedStringArray:
	var out := PackedStringArray()
	if i < 0 or i >= _tags.size():
		return out
	for l in _tags[i].get_child(0).get_children():
		if (l as Label).visible:
			out.append((l as Label).text)
	return out

## Whether the tags should be up now.
func want_shown() -> bool:
	if vent == null or not vent.is_open or vent.offers.is_empty() or vent.art == null:
		return false
	if int(vent.art.call("hand_count")) <= 0 or float(vent.art.call("offer_extend")) < SHOW_EXTEND:
		return false
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return false
	return cam.global_position.distance_to(vent.offer_center()) <= MAX_DIST

func _process(_delta: float) -> void:
	if not want_shown():
		for t in _tags:
			t.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	var ids: Array[String] = vent.offers.duplicate()
	if ids != _shown_ids:
		_rebuild(ids)
	var ui := maxf(get_viewport().get_visible_rect().size.y / 720.0, 0.5)
	for i in range(ids.size()):
		var item: Node3D = vent.art.call("item_node", i)
		var r := _screen_box(cam, item)
		var tag := _tags[i]
		if r.size == Vector2.ZERO:
			tag.visible = false
			continue
		tag.visible = true
		_style(tag, ui)
		tag.reset_size()
		var sz := tag.get_combined_minimum_size()
		tag.size = sz
		tag.position = Vector2(r.get_center().x - sz.x * 0.5, r.position.y - GAP * ui - sz.y)
	_spread(ui)

## Pushes overlapping tags apart sideways and keeps them on screen.
func _spread(ui: float) -> void:
	var view := get_viewport().get_visible_rect().size
	var shown: Array[PanelContainer] = []
	for t in _tags:
		if t.visible:
			shown.append(t)
	shown.sort_custom(func(a, b): return a.position.x + a.size.x * 0.5 < b.position.x + b.size.x * 0.5)
	for pass_i in range(8):
		for k in range(1, shown.size()):
			var a := shown[k - 1]
			var b := shown[k]
			var ra := Rect2(a.position, a.size).grow(PAD * ui * 0.5)
			var rb := Rect2(b.position, b.size).grow(PAD * ui * 0.5)
			if ra.intersects(rb):
				var push := (ra.end.x - rb.position.x) * 0.5
				a.position.x -= push
				b.position.x += push
		for t in shown:
			t.position.x = clampf(t.position.x, 4.0, maxf(4.0, view.x - t.size.x - 4.0))
			t.position.y = clampf(t.position.y, 4.0, maxf(4.0, view.y - t.size.y - 4.0))

## The item's outline on screen (zero when off screen or behind).
func _screen_box(cam: Camera3D, item: Node3D) -> Rect2:
	if item == null or not item.is_visible_in_tree():
		return Rect2()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var any := false
	for n in item.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := mi.get_aabb()
		var xf := mi.global_transform
		for c in range(8):
			var p: Vector3 = xf * box.get_endpoint(c)
			if cam.is_position_behind(p):
				return Rect2()
			var s := cam.unproject_position(p)
			lo = lo.min(s)
			hi = hi.max(s)
			any = true
	if not any:
		return Rect2()
	var view := get_viewport().get_visible_rect()
	var r := Rect2(lo, hi - lo)
	return r if view.intersects(r) else Rect2()

func _rebuild(ids: Array[String]) -> void:
	_shown_ids = ids.duplicate()
	while _tags.size() < ids.size():
		_tags.append(_new_tag())
	for i in range(_tags.size()):
		var t := _tags[i]
		t.visible = false
		if i >= ids.size():
			continue
		var box := t.get_child(0)
		(box.get_child(0) as Label).text = head_text(ids, ids[i])
		var use := item_use(ids[i])
		(box.get_child(1) as Label).text = use
		(box.get_child(1) as Label).visible = use != ""

func _new_tag() -> PanelContainer:
	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	# the subtitles' dim warm band, smaller
	sb.bg_color = Color(0.05, 0.01, 0.02, 0.62)
	tag.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	tag.add_child(box)
	for i in range(2):
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", FPMenuKit.FONT)
		l.add_theme_color_override("font_color", Color(0.96, 0.95, 0.88) if i == 0 else Color(0.85, 0.8, 0.74))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		box.add_child(l)
	tag.visible = false
	_root.add_child(tag)
	return tag

func _style(tag: PanelContainer, ui: float) -> void:
	var sb := tag.get_theme_stylebox("panel") as StyleBoxFlat
	sb.content_margin_left = roundf(8 * ui)
	sb.content_margin_right = roundf(8 * ui)
	sb.content_margin_top = roundf(2 * ui)
	sb.content_margin_bottom = roundf(4 * ui)
	var box := tag.get_child(0)
	var head := box.get_child(0) as Label
	var use := box.get_child(1) as Label
	head.add_theme_font_size_override("font_size", int(roundf(22 * ui)))
	head.add_theme_constant_override("outline_size", int(roundf(4 * ui)))
	use.add_theme_font_size_override("font_size", int(roundf(16 * ui)))
	use.add_theme_constant_override("outline_size", int(roundf(3 * ui)))
