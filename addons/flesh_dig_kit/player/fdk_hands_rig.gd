class_name FDKHandsRig
extends Node3D

## Two low-poly hand meshes fixed to the camera, acting as the "in-world
## HUD" the design calls for (no floating stomach text). Connect a
## FDKChewer's chew_progress signal to animate_chew() to make the hands
## reach in and squeeze/tear during chewing.

@export var reach_distance: float = 0.55
@export var hand_spacing: float = 0.18
@export var idle_bob_amplitude: float = 0.01

var _left_hand: MeshInstance3D
var _right_hand: MeshInstance3D
var _chew_ratio: float = 0.0
var _time: float = 0.0

func _ready() -> void:
	_left_hand = _make_hand_mesh(-1.0)
	_right_hand = _make_hand_mesh(1.0)
	add_child(_left_hand)
	add_child(_right_hand)

func _make_hand_mesh(side: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Hand%s" % ("Left" if side < 0 else "Right")
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.05, 0.16)
	mesh_instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.55, 0.5)
	material.roughness = 0.8
	mesh_instance.material_override = material
	mesh_instance.position = Vector3(side * hand_spacing, -0.15, -reach_distance)
	return mesh_instance

func _process(delta: float) -> void:
	_time += delta
	var idle := sin(_time * 2.0) * idle_bob_amplitude
	var reach: float = lerpf(0.0, 0.12, _chew_ratio)
	if _left_hand:
		_left_hand.position = Vector3(-hand_spacing, -0.15 + idle, -reach_distance + reach)
	if _right_hand:
		_right_hand.position = Vector3(hand_spacing, -0.15 + idle, -reach_distance + reach)

## ratio 0..1 from FDKChewer.chew_progress: hands reach forward and squeeze
## as the tear approaches completion.
func animate_chew(ratio: float, _target_cell: Vector3i) -> void:
	_chew_ratio = ratio

func reset_chew() -> void:
	_chew_ratio = 0.0
