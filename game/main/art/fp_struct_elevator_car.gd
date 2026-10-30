extends "res://main/art/fp_struct_model.gd"

## Structure: a 1950s service elevator car swallowed by the rib vault of the
## mantle. Brushed steel walls with a handrail, centre-opening sliding doors
## on the +Z side stuck half open, a floor indicator over the door made of a
## row of round lamps with only the lowest one lit (no digits), a button panel
## of plain round buttons, a domed ceiling lamp, and the roof hatch forced up
## by white-blue cartilage pushing down into the car. It carried goods and
## staff between floors; now a cartilage rib frames its doorway. The plate on
## the back wall tells what the player meets here: a car with an up arrow,
## crossed out (the way up is closed; you can only go on down).
## The model and its painting: main/art/structures/elevator_car.glb / .png
## (tools/struct_models). Origin = pocket floor centre, mouth on +Z.

const POCKET_HALF := Vector3(1.0, 1.2, 1.0)

func _init() -> void:
	kind = "elevator_car"
	pocket = POCKET_HALF
	glow_center = Vector3(-0.35, 2.18, 0.35)
	glow_half = Vector3(0.12, 0.02, 0.12)
	glow_color = Color(1.0, 0.96, 0.84)
	lamp_offset = Vector3(0.05, -0.28, -0.05)
	lamp_range = 2.5
	lamp_color = Color(1.0, 0.95, 0.8)
	lamp_energy = 0.6
