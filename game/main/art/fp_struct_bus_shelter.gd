extends "res://main/art/fp_struct_model.gd"

## Structure: a 1980s city bus shelter swallowed into the surface shell,
## where the mass is mostly swallowed clothes pressed into wads. Square
## steel posts, a slanted roof with a fluorescent tube under it (still
## flickering), scratched safety-glass back panels with the middle one
## smashed out, a long slatted bench, a timetable frame on the side panel
## (coloured route bars only), and the stop pole with its round sign. The
## sign is the biome's warning: a bus with an upward arrow, the street is
## just above (the surface is close). Clothing wads bulge through the
## missing pane and sit on the roof, sleeves hang from the roof edge.
## Origin = pocket floor centre; back glass on the -Z side, mouth at +Z.
## The model and its painting: main/art/structures/bus_shelter.glb / .png
## (tools/struct_models).

const POCKET_HALF := Vector3(1.6, 1.2, 0.9)

func _init() -> void:
	kind = "bus_shelter"
	pocket = POCKET_HALF
	glow_center = Vector3(0.0, 2.13, -0.1)
	glow_half = Vector3(0.55, 0.015, 0.02)
	glow_color = Color(0.9, 0.95, 1.0)
	lamp_offset = Vector3(0.0, -0.15, 0.0)
	lamp_range = 3.0
	lamp_color = Color(0.9, 0.95, 1.0)
	lamp_energy = 0.6
	flicker = true
