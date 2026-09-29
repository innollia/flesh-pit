class_name FPVent
extends Node3D

## Ceiling vent shop (design-core 5), no UI. Open the grate: two eyes in the
## dark. The being demands "BONG" (teeth). Right after a flush it is frantic;
## once paid it turns calm. Placing a handful of teeth makes it push out a
## few items; the player takes one by hand and the rest are pulled back.
## Speech lines are ids for the sound/voice layer, never shown as text.

signal line_spoken(line_id: String)
signal offers_changed(ids: Array)

const FRANTIC_TIME := 20.0
const CALM_TIME := 30.0

var is_open: bool = false
var offers: Array[String] = []
var _since_flush: float = INF
var _since_paid: float = INF
var _eyes: Node3D
var _offer_root: Node3D

func _ready() -> void:
	_eyes = Node3D.new()
	_eyes.name = "Eyes"
	add_child(_eyes)
	for sx in [-0.05, 0.05]:
		var e := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.018
		sm.height = 0.036
		e.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.95, 0.93, 0.8)
		m.emission_enabled = true
		m.emission = Color(0.6, 0.58, 0.4)
		e.material_override = m
		e.position = Vector3(sx, 0.06, 0.0)
		_eyes.add_child(e)
	_eyes.visible = false
	_offer_root = Node3D.new()
	_offer_root.name = "Offers"
	add_child(_offer_root)

func tick(delta: float) -> void:
	_since_flush += delta
	_since_paid += delta

## "frantic" right after a flush, "calm" after being paid, else "demanding".
func mood() -> String:
	if _since_paid < CALM_TIME:
		return "calm"
	if _since_flush < FRANTIC_TIME:
		return "frantic"
	return "demanding"

func on_flush() -> void:
	_since_flush = 0.0
	if is_open:
		line_spoken.emit("vent_heard_flush")

func open() -> void:
	if is_open:
		return
	is_open = true
	_eyes.visible = true
	line_spoken.emit("vent_bong_" + mood())

func close() -> void:
	is_open = false
	_eyes.visible = false
	_clear_offers()

## Player places `placed` teeth. Returns the offered ids ([] = the being
## pushes the teeth back as too few; the caller refunds them).
func place_teeth(placed: int, prog: FPProgression) -> Array[String]:
	if not is_open or placed <= 0:
		return []
	var ids := prog.vent_offer(placed)
	if ids.is_empty():
		line_spoken.emit("vent_not_enough")
		return []
	_since_paid = 0.0
	line_spoken.emit("vent_this_is_fair")
	_set_offers(ids)
	return ids

## Take one offered item; the others are pulled back.
func take(id: String, prog: FPProgression) -> bool:
	if id not in offers:
		return false
	var ok := prog.grant_item(id)
	_clear_offers()
	return ok

func _set_offers(ids: Array[String]) -> void:
	_clear_offers()
	offers = ids.duplicate()
	for i in range(offers.size()):
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, 0.05, 0.07)
		b.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.from_hsv(0.13 * i + 0.05, 0.5, 0.75)
		b.material_override = m
		b.position = Vector3((i - (offers.size() - 1) * 0.5) * 0.1, -0.04, 0.0)
		b.set_meta("offer_id", offers[i])
		_offer_root.add_child(b)
	offers_changed.emit(offers)

func _clear_offers() -> void:
	offers.clear()
	for c in _offer_root.get_children():
		c.queue_free()
		_offer_root.remove_child(c)
	offers_changed.emit(offers)

func offer_nodes() -> Array:
	return _offer_root.get_children()
