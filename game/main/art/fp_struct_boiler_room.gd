extends "res://main/art/fp_struct_model.gd"

## Structure: a 1930s boiler-room fragment swallowed by the fat caves of the
## core. A squat riveted coal/oil boiler lies along X against the back (-Z)
## wall; it once fed steam to a building through the pipes that now climb the
## walls and vanish into the ceiling flesh. Firebox door with a draft grille,
## a pressure gauge (dial and needle, no digits), a red valve wheel, a coal
## shovel left leaning on the wall, a caged amber bulkhead lamp. Soft yellow
## rendered fat has grown over the pipes and drips from them. Two pictogram
## plates warn about what the player meets here: "hot pipe / do not touch"
## (hand, heat waves, slash) and "the gap closes" (two arrows meeting: the
## fat is soft and regrows quickly). Origin = pocket floor centre, mouth +Z.
## The model and its painting: main/art/structures/boiler_room.glb / .png
## (tools/struct_models).

const POCKET_HALF := Vector3(1.4, 1.2, 1.4)

func _init() -> void:
	kind = "boiler_room"
	pocket = POCKET_HALF
	glow_center = Vector3(-1.3, 1.75, 0.3)
	glow_half = Vector3(0.05, 0.07, 0.07)
	glow_color = Color(1.0, 0.72, 0.4)
	lamp_offset = Vector3(0.18, 0.0, 0.0)
	lamp_range = 3.0
	lamp_color = Color(1.0, 0.7, 0.35)
	lamp_energy = 0.7
