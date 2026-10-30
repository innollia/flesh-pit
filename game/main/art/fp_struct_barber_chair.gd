extends "res://main/art/fp_struct_model.gd"

## Biome structure: a 1950s barber shop corner swallowed into the hair
## thicket of the surface shell. A heavy hydraulic barber chair on a chrome
## pedestal (cracked red leatherette seat, headrest, footrest) faces a wall
## mirror that has gone dark, over a mint counter with a jar of combs. A red,
## white and blue striped pole hangs on the side wall. Its job was cutting
## hair; now the cut hair heaps on the checker floor and the hair the sphere
## grows mats over the corners, hanging in locks from pink scalp patches.
## A warm bulb burns over the mirror.
## Warning plate on the counter: scissors over hair (a blade cuts hair fast).
## The model and its painting: main/art/structures/barber_chair.glb / .png
## (tools/struct_models). Origin = pocket floor centre, mouth on +Z.

const POCKET_HALF := Vector3(1.2, 1.1, 1.0)

func _init() -> void:
	kind = "barber_chair"
	pocket = POCKET_HALF
	glow_center = Vector3(-0.2, 2.15, -0.9)
	glow_half = Vector3(0.05, 0.05, 0.05)
	glow_color = Color(1.0, 0.88, 0.7)
	lamp_offset = Vector3(0.0, -0.45, 0.2)
	lamp_range = 2.5
	lamp_color = Color(1.0, 0.85, 0.65)
	lamp_energy = 0.6
