extends "res://main/art/fp_struct_model.gd"

## Biome structure: a 1970s coin laundromat fragment swallowed into the
## clothing-wad stretch of the surface shell. Three white enamel front
## loaders stand in a row against the back (-Z) wall: chrome-ringed porthole
## doors with dark glass, coin slot plates, a beige control strip with plain
## knobs. Its job was washing strangers' clothes for coins; now one door hangs
## open and the swallowed clothes spill out of the drum onto an avocado lino
## strip. A folding table still holds a folded stack. Clothes the sphere ate
## are pressed into fabric wads with blood-brown creases on every corner, and
## sleeves and trouser legs dangle from them. A ceiling fluorescent hums.
## Warning plate: a clothes wad with a long slow arrow (clothes barely regrow).
## The model and its painting: main/art/structures/laundromat.glb / .png
## (tools/struct_models). Origin = pocket floor centre, mouth on +Z.

const POCKET_HALF := Vector3(1.5, 1.1, 0.9)

func _init() -> void:
	kind = "laundromat"
	pocket = POCKET_HALF
	glow_center = Vector3(0.0, 2.11, -0.2)
	glow_half = Vector3(0.56, 0.015, 0.03)
	glow_color = Color(0.9, 0.96, 1.0)
	lamp_offset = Vector3(0.0, -0.16, 0.05)
	lamp_range = 3.0
	lamp_color = Color(0.92, 0.97, 1.0)
	lamp_energy = 0.6
