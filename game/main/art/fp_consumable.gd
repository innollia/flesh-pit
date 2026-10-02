class_name FPConsumable
extends Node3D

const K := preload("res://main/art/fp_art_kit.gd")
var item_id := ""

func _ready() -> void:
	var st := K.begin()
	if item_id.begins_with("spray_"):
		var deep := item_id == "spray_deep"
		K.lathe(st, Transform3D.IDENTITY, [Vector2(0, -0.075), Vector2(0.032, -0.075), Vector2(0.032, 0.065), Vector2(0.024, 0.08), Vector2(0, 0.08)], 10, [Color(0.12, 0.12, 0.14) if deep else Color(0.9, 0.87, 0.7)])
		K.rbox(st, K.T(Vector3(0, 0.087, 0)), Vector3(0.012, 0.008, 0.015), 0.002, Color(0.7, 0.1, 0.08) if deep else Color(0.85, 0.65, 0.07))
	elif item_id == "canary_feed":
		K.rbox(st, Transform3D.IDENTITY, Vector3(0.045, 0.055, 0.018), 0.009, Color(0.65, 0.45, 0.12))
		K.rbox(st, K.T(Vector3(0, 0.055, 0)), Vector3(0.045, 0.006, 0.02), 0.003, Color(0.9, 0.75, 0.25))
	elif item_id == "barrier":
		for i in range(4):
			K.rbox(st, K.T(Vector3(0, i * 0.017, 0)), Vector3(0.07, 0.007, 0.025), 0.005, Color(0.27, 0.3, 0.25))
	K.add_mesh(self, "Item", K.finish(st), K.mat("tex_door_paint_64.png", 0.25, true))

static func make(id: String) -> FPConsumable:
	var art := FPConsumable.new()
	art.item_id = id
	return art
