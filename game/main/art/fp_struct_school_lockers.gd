extends "res://main/art/fp_struct_model.gd"

## Structure: a fragment of a 1960s school corridor swallowed by the gut
## folds of the mantle. Six tall steel pupils' lockers stood in a row along
## the corridor wall (alternating faded green / grey enamel, pressed vent
## slots, lift handles), a varnished wooden bench in front where children
## changed shoes, a strip of the corridor's linoleum. One locker door hangs
## open on a sprung hinge: empty inside, a shelf and a coat hook. The muscle
## of the fold wall has grown over the top of the row and pushes it forward,
## so the lockers lean into the corridor. A pictogram plate on one door
## warns about the biome: two walls squeeze a figure between them (the gut
## folds squeeze shut every few seconds). No light of its own.
## Origin = pocket floor centre; the row stands on the -Z wall, mouth at +Z.
## The model and its painting: main/art/structures/school_lockers.glb / .png
## (tools/struct_models).

const POCKET_HALF := Vector3(1.6, 1.1, 0.8)

func _init() -> void:
	kind = "school_lockers"
	pocket = POCKET_HALF
