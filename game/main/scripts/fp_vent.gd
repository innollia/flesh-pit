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
## The main/art vent model: grate, duct, blinking eyes, the arm and items.
var art: Node3D

## Game item id -> the art model's item kind.
const ART_KIND := {
	"spray_cheap": "spray_cheap", "spray_deep": "spray_expensive", "barrier": "barrier",
	"knife": "knife", "blender": "blender_box", "big_saw": "saw_box",
}

func _ready() -> void:
	art = (load("res://main/art/fp_vent.tscn") as PackedScene).instantiate()
	art.name = "VentArt"
	add_child(art)
	art.call("set_open", 0.0)
	art.call("set_eyes", false)
	_eyes = Node3D.new()
	_eyes.name = "Eyes"
	add_child(_eyes)
	_eyes.visible = false
	_offer_root = Node3D.new()
	_offer_root.name = "Offers"
	add_child(_offer_root)

func tick(delta: float) -> void:
	_since_flush += delta
	_since_paid += delta
	var md := mood()
	art.call("set_eye_mood", 1.0 if md == "frantic" else (0.0 if md == "calm" else 0.5))

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
	art.call("play_open")
	art.call("set_eyes", true)
	line_spoken.emit("vent_bong_" + mood())

func close() -> void:
	var was_open := is_open
	is_open = false
	_eyes.visible = false
	_clear_offers()
	art.call("set_offer_items", [])
	art.call("set_eyes", false)
	if was_open and is_inside_tree():
		create_tween().tween_method(func(v): art.call("set_open", v), 1.0, 0.0, 0.35)
	else:
		art.call("set_open", 0.0)

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
	art.call("take_item", offers.find(id))
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
		b.visible = false # aim anchor only; the art arm holds the real item
		_offer_root.add_child(b)
	var kinds: Array = []
	for id in offers:
		kinds.append(ART_KIND.get(id, "junk"))
	art.call("set_offer_items", kinds)
	art.call("play_offer")
	offers_changed.emit(offers)

func _clear_offers() -> void:
	offers.clear()
	for c in _offer_root.get_children():
		c.queue_free()
		_offer_root.remove_child(c)
	offers_changed.emit(offers)

func offer_nodes() -> Array:
	return _offer_root.get_children()
