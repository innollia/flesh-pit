extends Node3D

## The teeth lying in a rest container's bucket (decision 0016): one real
## tooth per tooth, never a number, heaped on the bucket's floor. Visual
## only: main.rest_teeth is the amount, main._update_rest_teeth calls
## set_teeth. Origin = the bucket's floor centre (the container model's
## drain point); the bucket itself is part of the container model.

const K := preload("res://main/art/fp_art_kit.gd")
## Teeth drawn at most; more than this lie under the ones that show.
const SHOWN := 24
## Height of the bucket's mouth above its floor (the aim point for a hand).
const MOUTH_Y := 0.3
## A retch over a bucket that still holds teeth shivers the pile once.
const SHAKE_TIME := 0.25
const SHAKE_REACH := 0.012

## The tank's tooth mesh (main gives it; a small box without it).
var tooth_mesh: Mesh
var count := 0
var _pile: MultiMeshInstance3D
var _shake_t := -1.0

func _ready() -> void:
	_pile = MultiMeshInstance3D.new()
	_pile.name = "Teeth"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	if tooth_mesh == null:
		var box := BoxMesh.new()
		box.size = Vector3(0.016, 0.02, 0.012)
		tooth_mesh = box
	mm.mesh = tooth_mesh
	mm.instance_count = SHOWN
	for i in range(SHOWN):
		# filled from the middle outward, a second layer on top of the first
		var layer := i / 12
		var a := float(i) * 2.39996
		var r := 0.012 + 0.0075 * float(i % 12) * (1.0 - float(layer) * 0.3)
		var at := Vector3(cos(a) * r, 0.034 + float(layer) * 0.02 + K.h(i, 3) * 0.006, sin(a) * r)
		var rot := Vector3(K.h(i, 4), K.h(i, 5), K.h(i, 6)) * TAU
		mm.set_instance_transform(i, Transform3D(Basis.from_euler(rot).scaled(Vector3.ONE * 2.0), at))
		var y := K.h(i, 9)
		mm.set_instance_color(i, Color(0.9, 0.78 - y * 0.1, 0.55 - y * 0.15))
	mm.visible_instance_count = 0
	_pile.multimesh = mm
	_pile.material_override = K.mat("tex_ceramic_64.png", 0.5, false)
	_pile.custom_aabb = AABB(Vector3(-0.13, 0.0, -0.13), Vector3(0.26, 0.12, 0.26))
	_pile.visible = false
	add_child(_pile)
	set_process(false)
	set_teeth(count)

func set_teeth(n: int) -> void:
	count = maxi(0, n)
	if _pile == null:
		return
	_pile.multimesh.visible_instance_count = mini(count, SHOWN)
	_pile.visible = count > 0

## Teeth drawn right now.
func shown() -> int:
	return _pile.multimesh.visible_instance_count if _pile != null and _pile.visible else 0

func shake() -> void:
	_shake_t = 0.0
	set_process(true)

func shaking() -> bool:
	return _shake_t >= 0.0

func _process(delta: float) -> void:
	if _shake_t < 0.0:
		set_process(false)
		return
	_shake_t += delta
	if _shake_t >= SHAKE_TIME:
		_shake_t = -1.0
		_pile.position = Vector3.ZERO
		_pile.rotation = Vector3.ZERO
		set_process(false)
		return
	var k := 1.0 - _shake_t / SHAKE_TIME
	_pile.position = Vector3(sin(_shake_t * 90.0), 0.0, cos(_shake_t * 70.0)) * SHAKE_REACH * k
	_pile.rotation.y = sin(_shake_t * 60.0) * 0.5 * k
