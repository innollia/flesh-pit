extends Node3D

## Base of the biome structures (fp_struct_<kind>.gd): one low-poly model
## (main/art/structures/<kind>.glb, a few hundred triangles) wearing one
## painted atlas (<kind>.png) through the kit's PS1 material. Every detail is
## in the painting, made the hwapongstuy texture3d way
## (tools/struct_models/README.md). Only the lamp is built here: a small glow
## box and the light it gives.
## Origin = pocket floor centre, mouth on +Z. Public: pocket_half(),
## set_light(on), set_flicker(on).

const K := preload("res://main/art/fp_art_kit.gd")
const DIR := "res://main/art/structures/"

## Set by each structure in _init.
var kind := ""
var pocket := Vector3.ONE
## Glow box (centre, half size, colour); half zero = no lamp of its own.
var glow_center := Vector3.ZERO
var glow_half := Vector3.ZERO
var glow_color := Color(1, 1, 1)
var lamp_offset := Vector3.ZERO
var lamp_range := 2.5
var lamp_color := Color(1, 1, 1)
var lamp_energy := 0.6
var flicker := false

var _glow: MeshInstance3D
var _lamp: OmniLight3D
var _t := 0.0

func pocket_half() -> Vector3:
	return pocket

func _ready() -> void:
	var scene := load(DIR + kind + ".glb") as PackedScene
	if scene != null:
		var model := scene.instantiate() as Node3D
		model.name = "Model"
		add_child(model)
		if ResourceLoader.exists(DIR + kind + ".png"):
			var mat := FDKPs1Material.get_material(DIR + kind + ".png", 1.0, false, 0.2, 0.7, 1.0, true)
			for mi in model.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = mat
	if glow_half == Vector3.ZERO:
		return
	var st := K.begin()
	K.rbox(st, K.T(glow_center), glow_half, 0.0, glow_color)
	_glow = K.add_mesh(self, "Glow", st.commit(), K.glow(Color(1, 1, 1)))
	_lamp = OmniLight3D.new()
	_lamp.name = "Lamp"
	_lamp.position = glow_center + lamp_offset
	_lamp.omni_range = lamp_range
	_lamp.light_color = lamp_color
	_lamp.light_energy = lamp_energy
	_lamp.shadow_enabled = false
	_lamp.light_cull_mask = 0xFFFFF & ~FPRestroom.ROOM_VISUAL_LAYER & ~FPMirrorReflection.HANDS_ROOM_LAYER & ~FPMirrorReflection.MIRROR_BODY_LAYER & ~FPMirror.HOLO_LAYER
	add_child(_lamp)

func set_light(on: bool) -> void:
	if _glow != null:
		_glow.visible = on
		_lamp.visible = on

func set_flicker(on: bool) -> void:
	flicker = on

func _process(delta: float) -> void:
	if not flicker or _lamp == null or not _lamp.visible:
		return
	_t += delta
	# a tired tube: on, then a short stutter every few seconds
	var f := 1.0 if fmod(_t * 1.3, 4.0) > 0.3 else 0.15 + 0.35 * absf(sin(_t * 70.0))
	_lamp.light_energy = lamp_energy * f
	_glow.visible = f > 0.3
