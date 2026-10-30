extends "res://main/art/fp_struct_model.gd"

## Structure: a 1960s public telephone booth swallowed by the fat caves of the
## core. Painted steel frame, kick panels and dark bluish glass (some panes
## cracked, some gone), a folding door on the +Z side left ajar, a coin wall
## phone with a rotary dial (finger holes only) and its handset hanging on the
## coiled cord, a little shelf with a chained directory, a fluorescent tube in
## the roof. It stood on a pavement so people could ring from the street;
## now soft yellow fat has grown over its roof and down one corner. The sticker
## on the front pane warns what this biome does: a handset with an arrow
## sinking into wavy flesh (things you drop here sink). Origin = pocket floor
## The model and its painting: main/art/structures/phone_booth.glb / .png
## (tools/struct_models).

const POCKET_HALF := Vector3(0.9, 1.2, 0.9)

func _init() -> void:
	kind = "phone_booth"
	pocket = POCKET_HALF
	glow_center = Vector3(0.0, 2.12, 0.0)
	glow_half = Vector3(0.32, 0.015, 0.02)
	glow_color = Color(0.85, 1.0, 0.92)
	lamp_offset = Vector3(0.0, -0.07, 0.0)
	lamp_range = 2.5
	lamp_color = Color(0.85, 1.0, 0.9)
	lamp_energy = 0.6
