extends "res://main/art/fp_struct_model.gd"

## Structure: a 1950s public drinking-fountain alcove (a station or park
## underpass), swallowed by the gut folds of the mantle. A shallow recess
## tiled in pale blue and white, a vitreous-china wall fountain with a
## chrome bubbler and push button, a stained drain, its supply pipe going
## down into the floor, a small enamel wall lamp that still glows a sickly
## green-white. The muscle of the fold wall bulges through the tiles and
## hangs from the soffit. A pictogram plate warns about the biome's rhythm:
## a clock ring whose beat mark is a squeeze (the folds squeeze shut on a
## beat). Origin = pocket floor centre; the fountain is on the -Z wall,
## The model and its painting: main/art/structures/fountain_alcove.glb / .png
## (tools/struct_models).

const POCKET_HALF := Vector3(0.9, 1.1, 0.8)

func _init() -> void:
	kind = "fountain_alcove"
	pocket = POCKET_HALF
	glow_center = Vector3(0.55, 1.47, -0.7)
	glow_half = Vector3(0.05, 0.02, 0.05)
	glow_color = Color(0.85, 1.0, 0.8)
	lamp_offset = Vector3(0.0, -0.05, 0.3)
	lamp_range = 2.2
	lamp_color = Color(0.8, 1.0, 0.75)
	lamp_energy = 0.5
