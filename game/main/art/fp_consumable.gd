class_name FPConsumable
extends Node3D

## A belt consumable standing upright (origin = its middle): spray can,
## canary feed bag or barrier pack. The same mesh is used on the belt, in
## the hand, in the vent being's palm and in the rest-room loot, so what is
## offered is what arrives at the waist.

const K := preload("res://main/art/fp_art_kit.gd")
var item_id := ""

func _ready() -> void:
	K.add_mesh(self, "Item", item_mesh(item_id), item_material(item_id))

static func make(id: String) -> FPConsumable:
	var art := FPConsumable.new()
	art.item_id = id
	return art

## Upright mesh of `id` (spray_cheap / spray_deep / canary_feed / barrier).
static func item_mesh(id: String) -> ArrayMesh:
	var st := K.begin()
	if id.begins_with("spray_"):
		# the belt's holstered can: steel ends, coloured body with a band
		var deep := id == "spray_deep"
		var body := Color(0.12, 0.1, 0.1) if deep else Color(0.9, 0.88, 0.8)
		var band := Color(0.75, 0.08, 0.06) if deep else Color(0.9, 0.75, 0.1)
		var metal := Color(0.75, 0.76, 0.78)
		K.lathe(st, Transform3D.IDENTITY, [Vector2(0.0, -0.07), Vector2(0.028, -0.07), Vector2(0.031, -0.064), Vector2(0.031, -0.02), Vector2(0.031, 0.02), Vector2(0.031, 0.05), Vector2(0.024, 0.066), Vector2(0.012, 0.072), Vector2(0.012, 0.085), Vector2(0.0, 0.088)], 8, [metal, metal, body, band, body, metal, metal, Color(0.95, 0.95, 0.95)])
	elif id == "canary_feed":
		K.rbox(st, Transform3D.IDENTITY, Vector3(0.045, 0.055, 0.018), 0.009, Color(0.65, 0.45, 0.12))
		K.rbox(st, K.T(Vector3(0, 0.055, 0)), Vector3(0.045, 0.006, 0.02), 0.003, Color(0.9, 0.75, 0.25))
	elif id == "barrier":
		for i in range(4):
			K.rbox(st, K.T(Vector3(0, i * 0.017 - 0.025, 0)), Vector3(0.07, 0.007, 0.025), 0.005, Color(0.27, 0.3, 0.25))
	return K.finish(st, 8.0 if id.begins_with("spray_") else 4.0)

static func item_material(id: String) -> ShaderMaterial:
	return K.mat("tex_chrome_64.png", 0.35, true) if id.begins_with("spray_") else K.mat("tex_door_paint_64.png", 0.25, true)
