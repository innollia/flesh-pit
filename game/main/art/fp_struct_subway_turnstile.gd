extends "res://main/art/fp_struct_model.gd"

## Structure: a 1970s metro fare-gate line swallowed by the rib vault of the
## mantle. A strip of cream-and-green tiled station wall on -Z, a tiled
## floor, three steel tripod turnstiles in a row across X (token slot on top,
## a red "closed" lamp on each), a broken ceiling fluorescent fixture hanging
## by one chain, and a hanging pictogram sign. The gate let paying passengers
## down to the platforms; the sign now warns what the vault below needs: an
## arrow pointing down beside a knife ("below here you need a blade": the
## cartilage ribs do not give to bare hands). White-blue cartilage ribs have
## grown up over the tiles and arch across the ceiling. Origin = pocket floor
## The model and its painting: main/art/structures/subway_turnstile.glb / .png
## (tools/struct_models).

const POCKET_HALF := Vector3(1.8, 1.2, 1.0)

func _init() -> void:
	kind = "subway_turnstile"
	pocket = POCKET_HALF
	glow_center = Vector3(-0.75, 2.06, 0.0)
	glow_half = Vector3(0.2, 0.015, 0.02)
	glow_color = Color(0.85, 0.95, 1.0)
	lamp_offset = Vector3(-0.05, -0.21, 0.25)
	lamp_range = 3.0
	lamp_color = Color(0.8, 0.92, 1.0)
	lamp_energy = 0.7
