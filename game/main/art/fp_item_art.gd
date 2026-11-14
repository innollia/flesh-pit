class_name FPItemArt
extends RefCounted

## One model per offered item, the same in the vent being's palm and in the
## player's hand on the way to the waist, and matching what then sits on the
## belt (FPConsumable cans and packs, the belt's knife). Items lie across the
## palm (long side along X), origin in their middle.
## Kinds (FPVent.ART_KIND): spray_cheap, spray_expensive, barrier, knife,
## blender_box, saw_box, canary_feed, tumor_bag, pouch, junk; spray_deep is taken
## as spray_expensive (rest-room loot uses the item id).

const K := preload("res://main/art/fp_art_kit.gd")
const KnifeScene := preload("res://main/art/fp_knife.tscn")
const PouchScene := preload("res://main/art/fp_tooth_pouch.tscn")

static func make(kind: String, seed: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "Item"
	match kind:
		"spray_cheap", "spray_expensive", "spray_deep":
			var can := FPConsumable.make("spray_cheap" if kind == "spray_cheap" else "spray_deep")
			can.rotation_degrees = Vector3(0, 0, 90)
			root.add_child(can)
		"barrier":
			var pack := FPConsumable.make("barrier")
			pack.rotation_degrees = Vector3(80, 0, 0) # slabs facing out of the palm
			root.add_child(pack)
		"canary_feed":
			var bag := FPConsumable.make("canary_feed")
			bag.rotation_degrees = Vector3(80, 0, 0)
			root.add_child(bag)
		"knife":
			# the belt's kitchen knife, grip at the origin, blade along +X
			var knife: Node3D = KnifeScene.instantiate()
			knife.rotation_degrees = Vector3(0, -90, 0) # flat of the blade on the palm
			knife.position = Vector3(-0.07, 0, 0)
			knife.scale = Vector3.ONE * 0.85
			root.add_child(knife)
		"pouch":
			# the belt's tooth pouch lying on the palm, its cord trailing
			var pouch: Node3D = PouchScene.instantiate()
			pouch.rotation_degrees = Vector3(-80, 0, 0)
			pouch.position = Vector3(0, 0.0, -0.05)
			root.add_child(pouch)
		_:
			K.add_mesh(root, "Mesh", _box_mesh(kind, seed), K.mat("tex_fixture_64.png", 0.2, false))
	return root

## Things with no belt model of their own: a boxed tool, the tumor bag, junk.
static func _box_mesh(kind: String, seed: int) -> ArrayMesh:
	var st := K.begin()
	var I := Transform3D.IDENTITY
	match kind:
		"tumor_bag":
			# a deflated basketball-like sack with a drawstring
			K.blob(st, I, Vector3.ZERO, Vector3(0.06, 0.045, 0.06), 0.25, 31, Color(0.62, 0.32, 0.18), Color(0.45, 0.22, 0.12))
			K.tube(st, I, [Vector3(-0.03, 0.045, 0), Vector3(0, 0.07, 0), Vector3(0.03, 0.045, 0)], [0.004], 3, [Color(0.2, 0.15, 0.1)], false)
		"blender_box", "saw_box":
			K.rbox(st, I, Vector3(0.07, 0.05, 0.06), 0.01, Color(0.68, 0.55, 0.38), Color(0.55, 0.42, 0.28))
			K.tube(st, I, [Vector3(-0.071, 0.051, 0), Vector3(0.071, 0.051, 0)], [0.004], 3, [Color(0.3, 0.1, 0.08)], false)
		_:
			K.blob(st, I, Vector3.ZERO, Vector3(0.035, 0.02, 0.03), 0.5, 60 + seed, Color(0.45, 0.42, 0.36), Color(0.3, 0.28, 0.25))
	return K.finish(st, 6.0)

## Every mesh under `node` on these render layers (call once it is in the tree).
static func set_layers(node: Node, layers: int) -> void:
	for n in node.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = layers

## Pull the depth toward the eye like the first-person hands' skin
## (FDKSkinMaterial squash), so a held item is not painted over by the palm.
static func squash(node: Node, amount: float) -> void:
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var mat := mi.material_override as ShaderMaterial
		if mat != null and mat.get_shader_parameter("viewmodel_squash") != null:
			mat = mat.duplicate()
			mat.set_shader_parameter("viewmodel_squash", amount)
			mi.material_override = mat
