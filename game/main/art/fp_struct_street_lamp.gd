extends "res://main/art/fp_struct_model.gd"

## Biome structure: a 1960s cast-iron sodium street lamp swallowed into the
## hair thicket of the surface shell. A fluted cast base stands on a broken
## slab of pavement and kerb; across the kerb lie cracked asphalt chunks with
## a round manhole cover. Its job was lighting a street corner orange all
## night; the flesh pushed the pole until it bent over, and the lamp head still
## glows sodium orange. Matted dark hair grows over everything from pink scalp
## patches and hangs off the pole and lamp head in locks.
## Warning plate strapped to the pole: a circle of hair with an arrow closing
## it (hair closes fast behind you).
## The model and its painting: main/art/structures/street_lamp.glb / .png
## (tools/struct_models). Origin = pocket floor centre, mouth on +Z.

const POCKET_HALF := Vector3(1.0, 1.6, 1.0)

func _init() -> void:
	kind = "street_lamp"
	pocket = POCKET_HALF
	glow_center = Vector3(0.3, 2.6, -0.62)
	glow_half = Vector3(0.18, 0.015, 0.07)
	glow_color = Color(1.0, 0.6, 0.25)
	lamp_offset = Vector3(0.0, -0.2, 0.2)
	lamp_range = 3.5
	lamp_color = Color(1.0, 0.62, 0.3)
	lamp_energy = 1.0
